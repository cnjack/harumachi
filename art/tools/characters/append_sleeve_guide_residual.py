"""Append one local stretch control; preserve other shape curves and every bone key.

The new scalar is a finite support triangle in clip time. The two neighbouring
SleeveFit fields crossfade through this control. Other old values are interpolated
with f32 error disclosed. Other actions receive an identically zero new column.
"""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from glb_io import load
from motion_math import world_matrices
from prepare_local_garments import read
from sew_arm_seams import dense_part
from synchronize_sleeve_corrective_seams import posed_part, garment_vertices
from corrective_normals import unit, geometry_normals, rotate_between
from garment_bake_support import extend_original_curve
from repair_head_neck import append, save


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args):
    d, raw = load(args.input)
    rd, rb = load(args.reference)
    b = bytearray(raw)
    selected = ['CharacterBody', 'Sleeve_Left', 'Sleeve_Right']
    parts = {n['name']: dense_part(d, b, n) for n in d['nodes'] if n.get('name') in selected}
    refs = {n['name']: dense_part(rd, rb, n) for n in rd['nodes'] if n.get('name') in selected}
    rows = [r for r in json.loads(args.manifest.read_text())['shots']
            if r['id'] == args.character and r['clip'] == 'stretch' and r['view'] == 'front']
    row = min(rows, key=lambda r: abs(r['phase'] - args.phase))
    phase, time = float(row['phase']), float(row['clip_time'])
    assert args.start < phase < args.end
    name = f'SleeveGuide_stretch_{round(phase * 1000000):06d}'
    world, _ = world_matrices(d, b)
    ids = {n.get('name'): i for i, n in enumerate(d['nodes'])}
    for bone in row['bones']:
        i = ids[bone['name'].replace('mixamorig_', 'mixamorig:')]
        world[i] = np.eye(4)
        world[i][:3, :3] = np.asarray(bone['basis']).T
        world[i][:3, 3] = np.asarray(bone['position']) - row['position']
    sk = d['skins'][0]
    ib = read(d, b, sk['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    matrices = np.array([world[j] @ bind for j, bind in zip(sk['joints'], ib)])
    report = {'input': str(args.input), 'input_sha256': digest(args.input),
              'reference': str(args.reference), 'reference_sha256': digest(args.reference),
              'manifest': str(args.manifest), 'manifest_sha256': digest(args.manifest),
              'phase': phase, 'clip_time': time, 'target': name,
              'support_phase': [args.start, phase, args.end], 'parts': [], 'curves': []}
    old_counts = {}
    for mesh_name, part in parts.items():
        old_counts[mesh_name] = len(part['names'])
        q = np.load(args.trace_dir / f'{mesh_name}-SleeveFit_stretch_625.npz')
        gamma, guide = q['gamma'], q['guide']
        reference = refs[mesh_name]
        old_points, _, _ = posed_part(rd, rb, reference, row)
        base = reference['pos'].copy()
        for target, value in row['blend_shape_values'][mesh_name].items():
            if value and not target.startswith('SleeveFit_stretch_'):
                base += value * reference['shapes'][target]
        guided = np.einsum('vj,jab,vb->va', guide, matrices[:, :3, :3], base)
        guided += guide @ matrices[:, :3, 3]
        desired = old_points + gamma[:, None] * (guided - old_points)
        before, B, normal = posed_part(d, b, part, row)
        shift = desired - before
        shift[gamma <= 1e-8] = 0
        delta = np.einsum('vab,vb->va', np.linalg.pinv(B), shift)
        fit_names = [n for n in part['names'] if n.startswith('SleeveFit_stretch_')]
        for target in fit_names:
            delta += row['blend_shape_values'][mesh_name][target] * part['shapes'][target]
        after = before + shift
        faces = read(d, b, part['p']['indices']).reshape(-1, 3)
        changed = np.linalg.norm(shift, axis=1) > 1e-9
        affected = np.zeros(len(changed), bool)
        affected[np.unique(faces[changed[faces].any(1)])] = True
        affected &= garment_vertices(part, args.character)
        base_n = unit(read(d, b, part['a']['NORMAL']))
        rest_geo = geometry_normals(part['pos'], faces)
        reference_n = unit(np.einsum('vab,vb->va', B, rest_geo))
        render_n = unit(np.einsum('vab,vb->va', B, base_n))
        wanted = unit(np.einsum('vab,vb->va', B, unit(normal)))
        guided_normal = unit(rotate_between(reference_n, geometry_normals(after, faces), render_n))
        wanted[affected] = guided_normal[affected]
        wanted_rest = unit(np.einsum('vab,vb->va', np.linalg.pinv(B), wanted))
        other_normal = normal.copy()
        for target in fit_names:
            ti = part['names'].index(target)
            dn_old = unit(base_n + read(d, b, part['p']['targets'][ti]['NORMAL'])) - base_n
            other_normal -= row['blend_shape_values'][mesh_name][target] * dn_old
        offset = base_n - other_normal
        along = (offset * wanted_rest).sum(1)
        discriminant = along ** 2 + 1 - (offset ** 2).sum(1)
        if np.any(discriminant < -1e-8):
            raise ValueError('New unit normal target cannot reach desired direction')
        dn = unit(offset + (-along + np.sqrt(np.maximum(discriminant, 0)))[:, None] * wanted_rest) - base_n
        normal_template = part['p']['targets'][0]['NORMAL']
        part['p']['targets'].append({'POSITION': append(d, b, part['a']['POSITION'], delta.astype(np.float32)),
                                     'NORMAL': append(d, b, normal_template, dn.astype(np.float32))})
        part['mesh']['extras']['targetNames'].append(name)
        if 'weights' in part['mesh']:
            part['mesh']['weights'].append(0.)
        if 'weights' in part['node']:
            part['node']['weights'].append(0.)
        report['parts'].append({'mesh': mesh_name, 'moved_vertices': int(changed.sum()),
                                'world_residual_max_m': float(np.linalg.norm(shift, axis=1).max()),
                                'rest_residual_max_m': float(np.linalg.norm(delta, axis=1).max())})
    for animation in d['animations']:
        length = max(float(read(d, b, s['input']).max()) for s in animation['samplers'])
        for channel in animation['channels']:
            target = channel['target']
            ni = target.get('node')
            if target.get('path') != 'weights' or d['nodes'][ni].get('name') not in selected:
                continue
            mesh_name = d['nodes'][ni]['name']
            sampler = animation['samplers'][channel['sampler']]
            times = read(d, b, sampler['input']).ravel()
            values = read(d, b, sampler['output']).reshape(-1, old_counts[mesh_name])
            if animation['name'] == 'stretch':
                knots = np.asarray([args.start * length, time, args.end * length], dtype=np.float32)
                extended, old, evidence = extend_original_curve(times, values, knots,
                    [parts[mesh_name]['shapes'][n] for n in parts[mesh_name]['names'][:-1]])
                amount = np.interp(extended, knots, [0., 1., 0.], left=0., right=0.).astype(np.float32)
                inside = (extended >= knots[0]) & (extended <= knots[-1])
                left_name = f'SleeveFit_stretch_{round(args.start * 1000):03d}'
                right_name = f'SleeveFit_stretch_{round(args.end * 1000):03d}'
                for target_name, value in [(left_name, [1., 0., 0.]), (right_name, [0., 0., 1.])]:
                    ti = parts[mesh_name]['names'].index(target_name)
                    old[inside, ti] = np.interp(extended[inside], knots, value).astype(np.float32)
                sampler['input'] = append(d, b, sampler['input'], extended)
                report['curves'].append({'mesh': mesh_name, 'clip': 'stretch', **evidence})
            else:
                old, amount = values, np.zeros(len(times), dtype=np.float32)
            sampler['output'] = append(d, b, sampler['output'], np.c_[old, amount].astype(np.float32).ravel())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    save(d, b, args.output)
    report.update(output=str(args.output), output_sha256=digest(args.output), tool_sha256=digest(Path(__file__)))
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(args.output, report['output_sha256'], name)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['input', 'reference', 'manifest', 'trace-dir', 'output', 'report']:
        p.add_argument('--' + name, required=True, type=Path)
    p.add_argument('--character', default='mio')
    p.add_argument('--phase', type=float, default=.5)
    p.add_argument('--start', type=float, default=.375)
    p.add_argument('--end', type=float, default=.625)
    run(p.parse_args())

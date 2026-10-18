"""Bake full-surface cloth contacts while preserving the authored vertical drape.

Contact is solved along model Z, then inverse-skinned into ordinary XYZ morphs.
This prevents a local-Z clearance field from curling upward with a flexed thigh.
Original geometry, skin, bones and morph functions remain unchanged. The output
still needs independent source, native game, fit and interpolation verification.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json

import numpy as np
from scipy.optimize import linprog
from scipy.sparse import csr_matrix, vstack
from audit_local_garments import mesh_state, pose
from audit_native_garment_surfaces import witnesses, complete_painted_cloth_union
from garment_bake_support import complete_source_domain, extend_original_curve, circular_weights_batch
from source_surface_rays import envelope
from motion_math import world_matrices
from glb_io import durations
from repair_head_neck import read, append, save
from corrective_normals import geometry_normals, rotate_between, unit


def face_coefficients(coefficients, faces, barycentrics, sign):
    result = np.zeros((len(faces), coefficients.shape[1]))
    for corner in range(3):
        result += coefficients[faces[:, corner]] * barycentrics[:, corner, None]
    return result * sign


def solve_contact(state, base, panels, queries, movable, margin):
    coefficients = np.column_stack([state['shapes'][i][:, 2] for i in state['local']])
    centers = []
    current = np.zeros(len(state['local']))
    for attempt in range(6):
        positioned = base.copy()
        positioned[:, 2] += coefficients @ current
        constraints, requirements = [], []
        seeds = []
        for side, sign in [('front', 1), ('back', -1)]:
            hit = envelope(positioned, panels[side], queries, sign)
            accepted = np.isfinite(hit['signed_depth_m']) & (hit['normal_abs_dot_ray'] >= .35)
            faces = panels[side][hit['face_ids'][accepted]]
            bary = hit['barycentrics'][accepted]
            matrix = face_coefficients(coefficients, faces, bary, sign)
            right = sign * (queries[accepted, 2] - np.sum(base[faces, 2] * bary, axis=1)) + margin
            unavailable = (np.maximum(matrix, 0).sum(1) < right + 1e-9) & (right > 0)
            # Small independently painted corners may have no Local support.
            for index in np.flatnonzero(unavailable):
                center = bary[index] @ state['positions'][faces[index]]
                if any(np.linalg.norm(center-previous) < .008 for previous in centers + [s[0] for s in seeds]):
                    continue
                seeds.append((center, sign))
            constraints.append(csr_matrix(-matrix))
            requirements.append(-right)
        if seeds:
            for center, sign in seeds:
                if len(centers) >= 24:
                    raise ValueError('Too many uncovered source cloth corners')
                kernel = sign * .04 * np.exp(-np.sum((state['positions']-center)**2, axis=1)/(2*.015**2))
                kernel[~movable] = 0.
                coefficients = np.column_stack([coefficients, kernel])
                centers.append(center)
            current = np.pad(current, (0, len(seeds)))
            continue
        solution = linprog(np.ones(coefficients.shape[1]), A_ub=vstack(constraints),
                           b_ub=np.concatenate(requirements), bounds=(0., 1.), method='highs')
        if not solution.success:
            raise ValueError('Fixed-XY cloth contact is infeasible: '+solution.message)
        current = solution.x
        positioned[:, 2] = base[:, 2] + coefficients @ current
        maximum = 0.
        for side, sign in [('front', 1), ('back', -1)]:
            hit = envelope(positioned, panels[side], queries, sign)
            accepted = np.isfinite(hit['signed_depth_m']) & (hit['normal_abs_dot_ray'] >= .35)
            maximum = max(maximum, float(hit['signed_depth_m'][accepted].max(initial=0.)))
        if maximum <= .003:
            world_z = coefficients @ current
            if abs(world_z).max() > .1205:
                raise ValueError('World contact exceeds the explicit 12cm displacement cap')
            return world_z, {'attempts': attempt+1, 'extra_source_corner_fields': len(centers),
                             'maximum_world_shift_m': float(abs(world_z).max()),
                             'maximum_key_penetration_m': maximum}
    raise ValueError('Source cloth contact did not converge')


def inverse_skin_delta(state, animation, time, world_z):
    worlds, _ = world_matrices(state['d'], state['b'], animation, time)
    transforms = np.array([worlds[joint] @ bind for joint, bind in zip(state['skin']['joints'], state['binds'])])
    selected = np.flatnonzero(abs(world_z) > 1e-12)
    basis = np.zeros((len(selected), 3, 3))
    for slot in range(state['joints'].shape[1]):
        basis += transforms[state['joints'][selected, slot], :3, :3] * state['weights'][selected, slot, None, None]
    desired = np.zeros((len(selected), 3))
    desired[:, 2] = world_z[selected]
    delta = np.zeros_like(state['positions'], dtype=float)
    delta[selected] = np.linalg.solve(basis, desired[..., None])[..., 0]
    reconstructed = np.einsum('vij,vj->vi', basis, delta[selected])
    error = float(abs(reconstructed-desired).max(initial=0.))
    return delta, error


def author(source, output, actor, report_path, samples=128, extra_run_phases=()):
    state = mesh_state(source, actor)
    original, raw = state['d'], state['b']
    doc, blob = copy.deepcopy(original), bytearray(raw)
    rig = next(n for n in doc['nodes'] if n.get('name') == 'Rig')
    if rig.get('extras', {}).get('source_garment_animation'):
        raise ValueError('Use the explicit unbaked source')
    panels, domain = complete_painted_cloth_union(state, actor)
    triangles, barycentrics, coverage = witnesses(state, actor)
    _, movable, _ = complete_source_domain(state, 'yellow' if actor == 'kazuko' else 'blue')
    mesh = doc['meshes'][state['node']['mesh']]
    primitive = mesh['primitives'][0]
    attributes = primitive['attributes']
    faces = read(original, raw, primitive['indices']).reshape(-1, 3)
    normals = read(original, raw, attributes['NORMAL'])
    old_count = len(state['names'])
    lengths = durations(source)
    shape_names, authored, reports = [], {}, []
    for clip in ['walk', 'run']:
        animation = next(a for a in original['animations'] if a['name'] == clip)
        first_shape = len(shape_names)
        phases = np.unique(np.r_[np.arange(samples)/samples,
                                 extra_run_phases if clip == 'run' else []])
        if np.any((phases < 0) | (phases >= 1)):
            raise ValueError('Extra phase keys must be in [0,1)')
        for index, phase in enumerate(phases):
            time = lengths[clip]*phase
            base, _ = pose(state, clip, time)
            queries = np.r_[base[state['body']], np.einsum('wc,wcj->wj', barycentrics, base[triangles])]
            world_z, detail = solve_contact(state, base, panels, queries, movable, .008)
            delta, error = inverse_skin_delta(state, animation, time, world_z)
            if abs(delta[state['body']]).max(initial=0.) > 1e-10:
                raise ValueError('Authored cloth field overlaps a protected body vertex')
            morph_channel = next(c for c in animation['channels'] if c['target'] == {'node': state['ni'], 'path': 'weights'})
            sampler = animation['samplers'][morph_channel['sampler']]
            times = read(original, raw, sampler['input']).ravel()
            values = read(original, raw, sampler['output']).reshape(len(times), old_count)
            weights = np.array([np.interp(time, times, values[:, i]) for i in range(old_count)])
            rest = state['positions'].copy()
            current_normals = normals.copy()
            for weight, shape, target in zip(weights, state['shapes'], original['meshes'][state['node']['mesh']]['primitives'][0]['targets']):
                if weight == 0.: continue
                rest += shape * weight
                if 'NORMAL' in target: current_normals += read(original, raw, target['NORMAL']) * weight
            wanted = unit(rotate_between(geometry_normals(rest, faces), geometry_normals(rest+delta, faces), unit(current_normals)))
            normal_delta = wanted-current_normals
            normal_delta[np.linalg.norm(delta, axis=1) < 1e-10] = 0.
            normal_delta[state['body']] = 0.
            primitive['targets'].append({'POSITION': append(doc, blob, attributes['POSITION'], delta.astype(np.float32)),
                                         'NORMAL': append(doc, blob, attributes['NORMAL'], normal_delta.astype(np.float32))})
            shape_names.append('GarmentSourceContact_'+clip+'_%03d' % index)
            reports.append({'clip': clip, 'phase': float(phase), 'inverse_skin_world_error_m': error, **detail})
            if index % 16 == 0: print(actor, clip, index, detail, flush=True)
        authored[clip] = (first_shape, phases)
    mesh['extras']['targetNames'].extend(shape_names)
    mesh['weights'] = list(mesh.get('weights', [0.]*old_count)) + [0.]*len(shape_names)
    node = doc['nodes'][state['ni']]
    if 'weights' in node: node['weights'] += [0.]*len(shape_names)
    curve_reports = []
    for animation, prior in zip(doc['animations'], original['animations']):
        channel = next(c for c in animation['channels'] if c['target'] == {'node': state['ni'], 'path': 'weights'})
        sampler = animation['samplers'][channel['sampler']]
        times = read(original, raw, sampler['input']).ravel()
        values = read(original, raw, sampler['output']).reshape(len(times), old_count)
        selected = authored.get(animation['name'])
        preservation = {'old_key_values_exact': True}
        if selected is not None:
            first, phases = selected
            knots = (np.r_[phases, 1.] * lengths[animation['name']]).astype(np.float32)
            times, values, preservation = extend_original_curve(times, values, knots)
        extra = np.zeros((len(times), len(shape_names)))
        if selected is not None:
            extra[:, first:first+len(phases)] = circular_weights_batch(phases, times / lengths[animation['name']])
        sampler['input'] = append(doc, blob, sampler['input'], times[:, None])
        sampler['output'] = append(doc, blob, sampler['output'], np.c_[values, extra].astype(np.float32).reshape(-1, 1))
        curve_reports.append({'clip': animation['name'], 'old_curves': preservation})
    rig.setdefault('extras', {})['source_garment_animation'] = {
        'version': 1, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'authored_clips': ['idle', 'run', 'walk'], 'source_idle_unchanged': True,
        'runtime_owned_source_weights_zero': True, 'authored_shape_prefix': 'GarmentSourceContact_',
        'method': 'Fixed world-XY full-surface Z contact with inverse-skin XYZ source morphs',
        'samples_per_moving_clip': samples, 'terrain_or_leg_correction_baked': False}
    rig['extras']['source_garment_animation']['extra_run_phases'] = list(extra_run_phases)
    save(doc, blob, output)
    result = {'actor': actor, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'output_sha256': hashlib.sha256(output.read_bytes()).hexdigest(), 'domains': domain,
              'body_witnesses': coverage, 'samples': reports, 'curves': curve_reports,
              'source_xy_preserved_by_construction': True, 'game_modifiers': 0,
              'scope': 'Authored source contacts only; independent midpoints, native game and visual fit required'}
    report_path.write_text(json.dumps(result, indent=2)+'\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ['source', 'output', 'report']: parser.add_argument('--'+key, type=Path, required=True)
    parser.add_argument('--character', choices=['mio', 'kazuko'], required=True)
    parser.add_argument('--samples', type=int, default=128)
    parser.add_argument('--extra-run-phase', type=float, action='append', default=[])
    args = parser.parse_args()
    if args.samples < 8: parser.error('--samples must be at least 8')
    author(args.source, args.output, args.character, args.report, args.samples, args.extra_run_phase)

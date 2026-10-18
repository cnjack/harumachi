"""Bake a bounded run-only cloth fold offset from exact native final poses.

The offset closes millimetre-scale pleat valleys; it does not push the whole
garment towards a remote rear-wall ray hit. Source skin, old targets, base mesh,
UV, texture and every non-run animation value remain unchanged.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy import sparse
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree

from audit_garment_surface_witnesses import envelope
from audit_local_garments import mesh_state, pose
from corrective_normals import geometry_normals, rotate_between, unit
from glb_io import load
from motion_math import world_matrices
from prepare_local_garments import read
from prepare_sleeve_correctives import patch_weights
from repair_head_neck import append, save


def smooth(lo, hi, values):
    t = np.clip((values - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def final_matrices(state, row):
    animation = next(a for a in state['d']['animations'] if a['name'] == row['clip'])
    worlds, _ = world_matrices(state['d'], state['b'], animation, row['clip_time'])
    names = {n.get('name'): i for i, n in enumerate(state['d']['nodes'])}
    for bone in row['bones']:
        node = names[bone['name'].replace('mixamorig_', 'mixamorig:')]
        worlds[node][:3, :3] = np.asarray(bone['basis']).T
        worlds[node][:3, 3] = np.asarray(bone['position']) - row['position']
    return np.asarray([worlds[j] @ bind for j, bind in zip(state['skin']['joints'], state['binds'])])


def prepare(args):
    state = mesh_state(args.input, 'mio')
    source_sha = hashlib.sha256(args.input.read_bytes()).hexdigest()
    provenance = json.loads((args.native.parent / 'model-hashes.json').read_text())
    if provenance.get('CH_mio.glb') != source_sha:
        raise ValueError('Native final poses were recorded from a different GLB')
    captured = [json.loads(line.split(' ', 1)[1]) for line in args.native.read_text().splitlines()
                if line.startswith('GARMENT_FULL_SOURCE ')]
    rows = {round(row['phase'], 8): row['measurement'] for row in captured
            if row['id'] == 'mio' and row['clip'] == 'run' and row['phase'] < 1}
    phases = np.unique(np.r_[np.arange(16) / 16, .2, .8])
    if any(float(phase) not in rows for phase in phases):
        raise ValueError('Need the sixteen cyclic keys and exact native .2/.8 run poses')
    if any(name.startswith('GarmentFoldFair_') for name in state['names']):
        raise ValueError('Fold fairing already exists')
    d, raw = load(args.input)
    b = bytearray(raw)
    node = d['nodes'][state['ni']]
    mesh = d['meshes'][node['mesh']]
    primitive = mesh['primitives'][0]
    attrs = primitive['attributes']
    count = len(state['names'])
    faces = read(d, b, primitive['indices']).reshape(-1, 3)
    normals = unit(read(d, b, attrs['NORMAL']))
    source_normal_deltas = [unit(normals + read(d, b, target['NORMAL'])) - normals
                            if 'NORMAL' in target else np.zeros_like(normals)
                            for target in primitive['targets']]
    mask = np.zeros(len(state['positions']))
    mask[np.unique(state['layers']['front'])] = 1
    x, y, _ = state['positions'].T
    mask *= smooth(.075, .105, abs(x)) * (1 - smooth(.18, .22, abs(x)))
    mask *= smooth(.52, .57, y) * (1 - smooth(.77, .83, y))
    pairs = cKDTree(state['positions']).query_pairs(1e-6, output_type='ndarray')
    graph = sparse.coo_matrix((np.ones(2 * len(pairs)),
                              (np.r_[pairs[:, 0], pairs[:, 1]], np.r_[pairs[:, 1], pairs[:, 0]])),
                             shape=(len(mask), len(mask))).tocsr()
    groups, labels = connected_components(graph, directed=False)
    sizes = np.bincount(labels, minlength=groups)
    allowed = np.full(groups, True)
    np.logical_and.at(allowed, labels, mask > 0)
    mask *= allowed[labels]
    # Confirmed source-pixel witnesses remain the same final posed skin faces.
    pixels = [p for p in json.loads(args.pixel_witnesses.read_text())['pixels']
              if p['source_face'] in [28058, 28050]]
    report = {'input': str(args.input), 'source_sha256': source_sha, 'native': str(args.native),
              'scope': f'Run-only, {args.offset * 1000:g}mm maximum local front-fold offset at native calibration keys along final geometric normals; final posed skin triangle barycentric witnesses; no whole-skirt depth inflation',
              'maximum_permitted_offset_m': args.offset, 'samples': []}
    new_names = []
    for phase in phases:
        row = rows[float(phase)]
        current, _ = pose(state, 'run', row['clip_time'], row, actual_shapes=True)
        shift = geometry_normals(current, faces) * (mask * args.offset)[:, None]
        sums = np.zeros((groups, 3))
        np.add.at(sums, labels, shift)
        shift = sums[labels] / sizes[labels, None]
        shift *= allowed[labels, None]
        old_cross = np.cross(current[faces[:, 1]] - current[faces[:, 0]], current[faces[:, 2]] - current[faces[:, 0]])
        original_area = np.linalg.norm(old_cross, axis=1)
        for retreat in range(80):
            new_cross = np.cross((current + shift)[faces[:, 1]] - (current + shift)[faces[:, 0]], (current + shift)[faces[:, 2]] - (current + shift)[faces[:, 0]])
            flipped = (np.einsum('ij,ij->i', old_cross, new_cross) <= 0) & (original_area > 1e-12)
            flipped |= (np.linalg.norm(new_cross, axis=1) < original_area * .15) & (original_area > 1e-12)
            if not flipped.any():
                break
            multiplier = np.ones(groups)
            multiplier[np.unique(labels[faces[flipped]])] = .65
            shift *= multiplier[labels, None]
        if flipped.any():
            raise ValueError('Local fold offset inverted a source triangle')
        matrices = final_matrices(state, row)
        B = np.zeros((len(mask), 3, 3))
        for slot in range(state['joints'].shape[1]):
            B += matrices[state['joints'][:, slot], :3, :3] * state['weights'][:, slot, None, None]
        active = np.linalg.norm(shift, axis=1) > 1e-8
        delta = np.zeros_like(shift)
        delta[active] = np.einsum('nij,nj->ni', np.linalg.pinv(B[active]), shift[active])
        values = row['blend_shape_values'][state['node']['name']]
        normal = normals.copy()
        for name, dn in zip(state['names'], source_normal_deltas):
            normal += float(values[name]) * dn
        old_geo = geometry_normals(current, faces)
        new_geo = geometry_normals(current + shift, faces)
        original_render = unit(np.einsum('nij,nj->ni', B, unit(normal)))
        wanted_render = unit(rotate_between(old_geo, new_geo, original_render))
        desired_rest = unit(np.einsum('nij,nj->ni', np.linalg.pinv(B), wanted_render))
        offset = normals - normal
        along = np.sum(offset * desired_rest, axis=1)
        scale = -along + np.sqrt(np.maximum(along * along + 1 - np.sum(offset * offset, axis=1), 0))
        dn = unit(offset + scale[:, None] * desired_rest) - normals
        dn[mask == 0] = 0
        primitive['targets'].append({'POSITION': append(d, b, attrs['POSITION'], delta.astype(np.float32)),
                                     'NORMAL': append(d, b, attrs['NORMAL'], dn.astype(np.float32))})
        name = f'GarmentFoldFair_run_{round(phase * 1000):03d}'
        new_names.append(name)
        queries = np.asarray([np.asarray(p['barycentric']) @ current[faces[p['source_face']]] for p in pixels])
        before = envelope(current, state['cloth_faces'], queries)
        after = envelope(current + shift, state['cloth_faces'], queries)
        report['samples'].append({'phase': float(phase), 'target': name,
                                  'maximum_posed_shift_m': float(np.linalg.norm(shift, axis=1).max()),
                                  'body_max_shift_m': float(np.linalg.norm(shift[state['body']], axis=1).max()),
                                  'added_uv_seam_gap_m': float(np.linalg.norm(shift[pairs[:, 0]] - shift[pairs[:, 1]], axis=1).max()),
                                  'newly_inverted_faces': int(flipped.sum()), 'moved_vertices': int(active.sum()),
                                  'confirmed_source_pixel_barycentric_witnesses': [
                                      {'body_source_face': p['source_face'], 'barycentric': p['barycentric'],
                                       'before_axis_depth_m': h0['signed_depth_m'] if h0 else None,
                                       'after_axis_depth_m': h1['signed_depth_m'] if h1 else None}
                                      for p, h0, h1 in zip(pixels, before, after)]})
    names = mesh['extras']['targetNames']
    names.extend(new_names)
    mesh['weights'] = list(mesh.get('weights', [0] * count)) + [0] * len(phases)
    if 'weights' in node:
        node['weights'] += [0] * len(phases)
    for animation in d['animations']:
        old = next(a for a in state['d']['animations'] if a['name'] == animation['name'])
        channel = next(c for c in old['channels'] if c['target'] == {'node': state['ni'], 'path': 'weights'})
        sampler = old['samplers'][channel['sampler']]
        times = read(state['d'], state['b'], sampler['input']).ravel()
        duration = max(float(read(state['d'], state['b'], item['input']).max()) for item in old['samplers'])
        if animation['name'] == 'run':
            times = np.unique(np.r_[times, np.r_[phases, 1] * duration]).astype(np.float32)
        previous = patch_weights(state['d'], state['b'], old, state['ni'], count, times)
        output = np.c_[previous, np.zeros((len(times), len(phases)))]
        if animation['name'] == 'run':
            for index in range(len(phases)):
                curve = np.zeros(len(phases) + 1)
                curve[index] = 1
                if index == 0:
                    curve[-1] = 1
                output[:, count + index] = np.interp(times / duration, np.r_[phases, 1], curve)
        template = animation['samplers'][0]['input']
        ti = append(d, b, template, times[:, None])
        oi = append(d, b, template, output.reshape(-1, 1))
        si = len(animation['samplers'])
        animation['samplers'].append({'input': ti, 'output': oi, 'interpolation': 'LINEAR'})
        animation['channels'] = [c for c in animation['channels'] if c['target'] != {'node': state['ni'], 'path': 'weights'}]
        animation['channels'].append({'sampler': si, 'target': {'node': state['ni'], 'path': 'weights'}})
    save(d, b, args.output)
    report['output'] = str(args.output)
    report['output_sha256'] = hashlib.sha256(args.output.read_bytes()).hexdigest()
    args.report.write_text(json.dumps(report, indent=2))
    print(args.report)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--native', required=True, type=Path)
    parser.add_argument('--pixel-witnesses', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--offset', type=float, default=.002)
    prepare(parser.parse_args())

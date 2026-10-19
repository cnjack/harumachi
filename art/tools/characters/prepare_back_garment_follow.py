"""Add run-only rear cloth following from a bounded continuous thigh guide.

The guide changes no shipped skin weights. It is sampled under actual final
source-native bone matrices, inverse-skinned into extra action targets, and
keeps existing front drape, fingers, morphs and all non-run clips intact.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy import sparse
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree

from audit_local_garments import mesh_state, pose
from corrective_normals import geometry_normals, rotate_between, unit
from glb_io import load
from prepare_garment_fold_fairing import final_matrices
from prepare_local_garments import read, smooth
from prepare_sleeve_correctives import patch_weights
from repair_head_neck import append, save


def _build_guide(source, thigh_share):
    points = source['positions']
    height = float(points[:, 1].max())
    local_back = [i for i in source['local'] if '_Back_' in source['names'][i]]
    profile = next(n for n in source['d']['nodes'] if n.get('name') == 'Rig') \
        ['extras']['garment_local_clearance']
    mask = np.clip(np.sum([abs(source['shapes'][i][:, 2]) for i in local_back], axis=0)
                   / float(profile['shape_amplitude_m']), 0, 1)
    mask[source['body']] = 0

    pairs = cKDTree(points).query_pairs(1e-6, output_type='ndarray')
    graph = sparse.coo_matrix(
        (np.ones(2 * len(pairs)),
         (np.r_[pairs[:, 0], pairs[:, 1]], np.r_[pairs[:, 1], pairs[:, 0]])),
        shape=(len(points), len(points))).tocsr()
    groups, labels = connected_components(graph, directed=False)
    permitted = np.ones(groups, bool)
    np.logical_and.at(permitted, labels, mask > 0)
    allowed = permitted[labels]
    mask[~allowed] = 0

    amount = mask * (1 - smooth(.34 * height, .53 * height, points[:, 1])) * thigh_share
    share = smooth(-.04 * height, .04 * height, points[:, 0])
    joint_names = [source['d']['nodes'][i]['name'] for i in source['skin']['joints']]
    left = joint_names.index('mixamorig:LeftUpLeg')
    right = joint_names.index('mixamorig:RightUpLeg')

    guide = dict(source)
    guide['joints'] = source['joints'].copy()
    guide['weights'] = source['weights'].copy()
    for vertex in np.flatnonzero(amount > 0):
        influences = {int(joint): float(weight * (1 - amount[vertex]))
                      for joint, weight in zip(source['joints'][vertex], source['weights'][vertex])
                      if weight > 0}
        influences[left] = influences.get(left, 0) + float(amount[vertex] * share[vertex])
        influences[right] = influences.get(right, 0) + float(amount[vertex] * (1 - share[vertex]))
        influences = sorted(influences.items(), key=lambda item: item[1], reverse=True)[
            :source['joints'].shape[1]]
        total = sum(weight for _, weight in influences)
        guide['joints'][vertex] = 0
        guide['weights'][vertex] = 0
        for slot, (joint, weight) in enumerate(influences):
            guide['joints'][vertex, slot] = joint
            guide['weights'][vertex, slot] = weight / total
    return guide, allowed, groups, labels, pairs


def _add_follow_targets(source, document, binary, primitive, names, rows, phases,
                        guide, allowed, groups, labels, pairs, cap):
    points = source['positions']
    faces = read(document, binary, primitive['indices']).reshape(-1, 3)
    normals = unit(read(document, binary, primitive['attributes']['NORMAL']))
    old_normal_deltas = [
        unit(normals + read(document, binary, target['NORMAL'])) - normals
        if 'NORMAL' in target else np.zeros_like(normals)
        for target in primitive['targets']
    ]
    details = []
    for phase in phases:
        row = rows[float(phase)]
        current, _ = pose(source, 'run', row['clip_time'], row, actual_shapes=True, disable_local=True)
        wanted, _ = pose(guide, 'run', row['clip_time'], row, actual_shapes=True, disable_local=True)
        shift = wanted - current
        shift[~allowed] = 0
        sums = np.zeros((groups, 3))
        np.add.at(sums, labels, shift)
        shift = sums[labels] / np.bincount(labels, minlength=groups)[labels, None]
        shift *= np.minimum(1, cap / np.maximum(np.linalg.norm(shift, axis=1), 1e-12))[:, None]

        matrices = final_matrices(source, row)
        blend = np.zeros((len(points), 3, 3))
        for slot in range(source['joints'].shape[1]):
            blend += matrices[source['joints'][:, slot], :3, :3] * source['weights'][:, slot, None, None]
        active = np.linalg.norm(shift, axis=1) > 1e-9
        delta = np.zeros_like(points)
        delta[active] = np.einsum('nij,nj->ni', np.linalg.pinv(blend[active]), shift[active])

        old_geo = geometry_normals(current, faces)
        new_geo = geometry_normals(current + shift, faces)
        mixed_normal = normals.copy()
        table = row['blend_shape_values'][source['node']['name']]
        for name, normal_delta in zip(source['names'], old_normal_deltas):
            if not name.startswith('Garment_Local_'):
                mixed_normal += float(table[name]) * normal_delta
        before_render = unit(np.einsum('nij,nj->ni', blend, unit(mixed_normal)))
        wanted_render = unit(rotate_between(old_geo, new_geo, before_render))
        desired_rest = unit(np.einsum('nij,nj->ni', np.linalg.pinv(blend), wanted_render))
        offset = normals - mixed_normal
        along = np.sum(offset * desired_rest, axis=1)
        scale = -along + np.sqrt(np.maximum(along * along + 1 - np.sum(offset * offset, axis=1), 0))
        normal_delta = unit(offset + scale[:, None] * desired_rest) - normals

        affected = np.zeros(len(points), bool)
        affected[np.unique(faces[np.any(active[faces], axis=1)])] = True
        normal_delta[~affected | ~allowed] = 0
        primitive['targets'].append({
            'POSITION': append(document, binary, primitive['attributes']['POSITION'],
                               delta.astype(np.float32)),
            'NORMAL': append(document, binary, primitive['attributes']['NORMAL'],
                             normal_delta.astype(np.float32)),
        })
        names.append(f'GarmentBackFit_run_{round(phase * 1000):03d}')
        details.append({
            'phase': float(phase),
            'maximum_added_shift_m': float(np.linalg.norm(shift, axis=1).max()),
            'body_shift_m': float(np.linalg.norm(shift[source['body']], axis=1).max()),
            'physical_seam_delta_gap_m': float(np.linalg.norm(delta[pairs[:, 0]] - delta[pairs[:, 1]], axis=1).max()),
        })
    return details


def _rewrite_weight_channels(document, binary, source, node, old_count, phases):
    mesh = document['meshes'][node['mesh']]
    mesh['weights'] = list(mesh.get('weights', [0] * old_count)) + [0] * len(phases)
    if 'weights' in node:
        node['weights'] += [0] * len(phases)

    animation = next(a for a in source['d']['animations'] if a['name'] == 'run')
    duration = max(float(read(source['d'], source['b'], s['input']).max()) for s in animation['samplers'])
    closed = np.r_[phases, 1.]
    for target_animation in document['animations']:
        old_animation = next(a for a in source['d']['animations'] if a['name'] == target_animation['name'])
        channel = next(c for c in old_animation['channels']
                       if c['target'] == {'node': source['ni'], 'path': 'weights'})
        sampler = old_animation['samplers'][channel['sampler']]
        times = read(source['d'], source['b'], sampler['input']).ravel()
        if target_animation['name'] == 'run':
            times = np.unique(np.r_[times, closed * duration]).astype(np.float32)
        output = np.c_[
            patch_weights(source['d'], source['b'], old_animation, source['ni'], old_count, times),
            np.zeros((len(times), len(phases))),
        ]
        if target_animation['name'] == 'run':
            for index in range(len(phases)):
                curve = np.zeros(len(closed))
                curve[index] = 1
                if index == 0:
                    curve[-1] = 1
                output[:, old_count + index] = np.interp(times / duration, closed, curve)
        template = target_animation['samplers'][0]['input']
        input_index = append(document, binary, template, times[:, None])
        output_index = append(document, binary, template, output.reshape(-1, 1))
        sampler_index = len(target_animation['samplers'])
        target_animation['samplers'].append(
            {'input': input_index, 'output': output_index, 'interpolation': 'LINEAR'})
        target_animation['channels'] = [c for c in target_animation['channels']
                                        if c['target'] != {'node': source['ni'], 'path': 'weights'}]
        target_animation['channels'].append(
            {'sampler': sampler_index, 'target': {'node': source['ni'], 'path': 'weights'}})


def prepare(args):
    source = mesh_state(args.input, 'mio')
    expected = json.loads((args.native.parent / 'model-hashes.json').read_text())['CH_mio.glb']
    if hashlib.sha256(args.input.read_bytes()).hexdigest() != expected:
        raise ValueError('Source model differs from actual native companion')
    if any(n.startswith('GarmentBackFit_run_') for n in source['names']):
        raise ValueError('Input already contains rear follow targets')

    rows = [json.loads(line.split(' ', 1)[1]) for line in args.native.read_text().splitlines()
            if line.startswith('GARMENT_FULL_SOURCE ')]
    rows = {round(row['phase'], 8): row['measurement'] for row in rows
            if row['id'] == 'mio' and row['clip'] == 'run' and row['phase'] < 1}
    phases = np.unique(np.r_[np.arange(16) / 16, .2, .8])

    guide, allowed, groups, labels, pairs = _build_guide(source, args.thigh_share)
    document, raw = load(args.input)
    binary = bytearray(raw)
    node = document['nodes'][source['ni']]
    mesh = document['meshes'][node['mesh']]
    primitive = mesh['primitives'][0]
    names = mesh['extras']['targetNames']
    old_count = len(source['names'])

    details = _add_follow_targets(
        source, document, binary, primitive, names, rows, phases,
        guide, allowed, groups, labels, pairs, args.cap)
    _rewrite_weight_channels(document, binary, source, node, old_count, phases)
    save(document, binary, args.output)

    args.report.write_text(json.dumps({
        'source': str(args.input),
        'source_sha256': expected,
        'output': str(args.output),
        'output_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
        'scope': 'Run-only rear garment follow; all actual shipped skin weights and original targets preserved. '
                 'Existing front drape, run fold fairing and dance hem retained. Requires coherent128 stabilization '
                 'and actual proxy re-solve/gap checks.',
        'guide_incremental_thigh_share': args.thigh_share,
        'shift_cap_m': args.cap,
        'samples': details,
    }, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--native', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--thigh-share', type=float, default=.25)
    parser.add_argument('--cap', type=float, default=.05)
    prepare(parser.parse_args())


if __name__ == '__main__':
    main()

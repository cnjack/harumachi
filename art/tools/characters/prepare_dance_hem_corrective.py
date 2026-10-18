"""Add one bounded dance-only lower-hem corrective on top of accepted run folds."""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy import sparse
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree

from audit_local_garments import layer_hits, mesh_state, pose
from corrective_normals import geometry_normals, rotate_between, unit
from glb_io import load
from prepare_garment_fold_fairing import final_matrices, smooth
from prepare_local_garments import read
from prepare_sleeve_correctives import patch_weights
from repair_head_neck import append, save
from audit_garment_surface_witnesses import envelope
from replay_garment_proxy_contact import imported_proxy


def prepare(args):
    source = mesh_state(args.input, 'mio')
    native_source = mesh_state(args.native_source, 'mio')
    native_sha = hashlib.sha256(args.native_source.read_bytes()).hexdigest()
    if json.loads((args.native.parent / 'model-hashes.json').read_text()).get('CH_mio.glb') != native_sha:
        raise ValueError('Native provenance mismatch')
    if not all(np.array_equal(source[key], native_source[key]) for key in ['positions', 'weights', 'joints']):
        raise ValueError('Dance native reference geometry/bindings differ')
    d, raw = load(args.input)
    b = bytearray(raw)
    node = d['nodes'][source['ni']]
    mesh = d['meshes'][node['mesh']]
    p = mesh['primitives'][0]
    count = len(source['names'])
    name = 'GarmentHem_dance'
    if name in source['names']:
        raise ValueError('Dance hem already exists')
    faces = read(d, b, p['indices']).reshape(-1, 3)
    x, y, _ = source['positions'].T
    mask = np.zeros(len(x))
    mask[np.unique(source['layers']['front'])] = 1
    mask *= smooth(-.155, -.125, x) * (1 - smooth(-.075, -.045, x))
    mask *= smooth(.44, .46, y) * (1 - smooth(.50, .55, y))
    pairs = cKDTree(source['positions']).query_pairs(1e-6, output_type='ndarray')
    graph = sparse.coo_matrix((np.ones(len(pairs) * 2), (np.r_[pairs[:, 0], pairs[:, 1]], np.r_[pairs[:, 1], pairs[:, 0]])), shape=(len(x), len(x))).tocsr()
    groups, labels = connected_components(graph, directed=False)
    allowed = np.full(groups, True)
    np.logical_and.at(allowed, labels, mask > 0)
    group_mask = np.zeros(groups)
    np.add.at(group_mask, labels, mask)
    mask = group_mask[labels] / np.bincount(labels)[labels]
    mask *= allowed[labels]
    delta = np.zeros_like(source['positions'])
    delta[:, 2] = mask * args.cap
    valley_report = None
    if args.valley_proxy:
        proxy_faces, _, proxy_info = imported_proxy(source, args.valley_proxy)
        supported = np.flatnonzero(mask > 0)
        outer = envelope(source['positions'], proxy_faces['front'], source['positions'][supported])
        valley_cap = np.zeros(len(mask))
        for vertex, hit in zip(supported, outer):
            if hit is not None:
                valley_cap[vertex] = .9 * max(0., -hit['signed_depth_m'] - .001)
        delta[:, 2] = np.minimum(delta[:, 2], valley_cap)
        proxy_vertices = np.unique(np.concatenate(list(proxy_faces.values())))
        protected_groups = np.zeros(groups, bool)
        protected_groups[np.unique(labels[proxy_vertices])] = True
        delta[protected_groups[labels]] = 0
        sums = np.zeros(groups)
        np.add.at(sums, labels, delta[:, 2])
        delta[:, 2] = sums[labels] / np.bincount(labels)[labels]
        valley_report = {'proxy': str(args.valley_proxy), 'selected': proxy_info,
                         'protected_physical_proxy_groups': int(protected_groups.sum()),
                         'proxy_vertices_with_nonzero_new_delta': int(np.count_nonzero(np.linalg.norm(delta[proxy_vertices], axis=1) > 0)),
                         'source_valley_cap': 'At most90% of(rest coarse outer envelope depth minus1mm), with9mm hard cap; outer physical proxy groups remain fixed'}
    captured = [json.loads(line.split(' ', 1)[1]) for line in args.native.read_text().splitlines() if line.startswith('GARMENT_FULL_SOURCE ')]
    rows = {round(row['phase'], 8): row['measurement'] for row in captured if row['id'] == 'mio' and row['clip'] == 'dance' and row['phase'] < 1}
    keys = np.array(sorted(rows))
    amounts = []
    report = {'input': str(args.input), 'input_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
              'native_source': str(args.native_source), 'native_source_sha256': native_sha,
              'target': name, 'maximum_rest_displacement_m': args.cap,
              'valley_only': valley_report,
              'scope': 'One dance-only local left-front hem patch; original full-source5mm gate retained; all other clips including accepted run folds remain exact',
              'samples': []}
    for phase in keys:
        row = rows[float(phase)]
        original, _ = pose(native_source, 'dance', row['clip_time'], row, actual_shapes=True)
        # The accepted run-only fields are zero throughout dance. Verify this
        # instead of assuming missing native morph values describe another GLB.
        augmented = deepcopy(row)
        values = augmented['blend_shape_values'][source['node']['name']]
        for n in source['names']:
            if n not in values:
                if not n.startswith('GarmentFoldFair_run_'):
                    raise ValueError('Unproven extra target in dance input')
                values[n] = 0
        same, _ = pose(source, 'dance', row['clip_time'], augmented, actual_shapes=True)
        if not np.array_equal(original, same):
            raise ValueError('Native reference is not pointwise identical for dance')
        matrices = final_matrices(source, row)
        B = np.zeros((len(x), 3, 3))
        for slot in range(source['joints'].shape[1]):
            B += matrices[source['joints'][:, slot], :3, :3] * source['weights'][:, slot, None, None]
        shift = np.einsum('nij,nj->ni', B, delta)
        needed = 0.
        failures = []
        for body, triangle, bary, depth in layer_hits(original, source['layers']['front'], source['body'], 1):
            if depth <= .005:
                continue
            slope = float(bary @ shift[triangle, 2])
            if slope <= 0:
                raise ValueError('Original failed cloth triangle lies outside the local patch')
            required = (depth + args.contact_gap) / slope
            needed = max(needed, required)
            failures.append({'body_vertex': body, 'cloth_vertices': triangle.tolist(), 'depth_m': depth, 'required_weight_for_contact_gap': required})
        if needed > 1:
            raise ValueError(f'9mm local cap cannot clear original failed source faces at {phase}: {needed}; {failures}')
        ease = .85 * smooth(.0625, .18, phase) * (1 - smooth(.33, .45, phase))
        amounts.append(max(needed, float(ease)))
        report['samples'].append({'phase': float(phase), 'weight': amounts[-1], 'original_failed_source_hits': failures})
    normals = unit(read(d, b, p['attributes']['NORMAL']))
    old_geo = geometry_normals(source['positions'], faces)
    new_geo = geometry_normals(source['positions'] + delta, faces)
    dn = unit(rotate_between(old_geo, new_geo, normals)) - normals
    dn[mask == 0] = 0
    p['targets'].append({'POSITION': append(d, b, p['attributes']['POSITION'], delta.astype(np.float32)),
                         'NORMAL': append(d, b, p['attributes']['NORMAL'], dn.astype(np.float32))})
    mesh['extras']['targetNames'].append(name)
    mesh['weights'] = list(mesh.get('weights', [0] * count)) + [0]
    if 'weights' in node:
        node['weights'] += [0]
    keys = np.r_[keys, 1]
    amounts = np.r_[amounts, amounts[0]]
    for animation in d['animations']:
        old = next(a for a in source['d']['animations'] if a['name'] == animation['name'])
        channel = next(c for c in old['channels'] if c['target'] == {'node': source['ni'], 'path': 'weights'})
        sampler = old['samplers'][channel['sampler']]
        times = read(source['d'], source['b'], sampler['input']).ravel()
        duration = max(float(read(source['d'], source['b'], item['input']).max()) for item in old['samplers'])
        if animation['name'] == 'dance':
            times = np.unique(np.r_[times, keys * duration]).astype(np.float32)
        previous = patch_weights(source['d'], source['b'], old, source['ni'], count, times)
        values = np.c_[previous, np.zeros(len(times))]
        if animation['name'] == 'dance':
            values[:, -1] = np.interp(times / duration, keys, amounts)
        template = animation['samplers'][0]['input']
        ti = append(d, b, template, times[:, None])
        oi = append(d, b, template, values.reshape(-1, 1))
        si = len(animation['samplers'])
        animation['samplers'].append({'input': ti, 'output': oi, 'interpolation': 'LINEAR'})
        animation['channels'] = [c for c in animation['channels'] if c['target'] != {'node': source['ni'], 'path': 'weights'}]
        animation['channels'].append({'sampler': si, 'target': {'node': source['ni'], 'path': 'weights'}})
    save(d, b, args.output)
    report['output'] = str(args.output)
    report['output_sha256'] = hashlib.sha256(args.output.read_bytes()).hexdigest()
    report['body_delta_max_m'] = float(np.linalg.norm(delta[source['body']], axis=1).max())
    report['body_normal_delta_max'] = float(np.linalg.norm(dn[source['body']], axis=1).max())
    report['added_uv_seam_gap_m'] = float(np.linalg.norm(delta[pairs[:, 0]] - delta[pairs[:, 1]], axis=1).max())
    args.report.write_text(json.dumps(report, indent=2))
    print(args.report)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--native-source', required=True, type=Path)
    parser.add_argument('--native', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--cap', type=float, default=.009)
    parser.add_argument('--contact-gap', type=float, default=.0015)
    parser.add_argument('--valley-proxy', type=Path)
    prepare(parser.parse_args())

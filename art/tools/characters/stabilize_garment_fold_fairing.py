"""Retreat new fold targets coherently until continuous authored faces stay valid.

One physical UV-seam group uses one factor across every phase target, avoiding
phase-dependent vertex pinning. Existing source targets/geometry are untouched.
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
from prepare_local_garments import read
from repair_head_neck import append, save
from prepare_sleeve_correctives import patch_weights


def run(args):
    source = mesh_state(args.source, 'mio')
    candidate = mesh_state(args.input, 'mio')
    prefix = args.prefix
    added = [i for i, n in enumerate(candidate['names']) if n.startswith(prefix)]
    cp = candidate['d']['meshes'][candidate['node']['mesh']]['primitives'][0]
    sp = source['d']['meshes'][source['node']['mesh']]['primitives'][0]
    faces = read(source['d'], source['b'], sp['indices']).reshape(-1, 3)
    active = np.max([np.linalg.norm(candidate['shapes'][i], axis=1) for i in added], axis=0) > 0
    affected = np.flatnonzero(np.any(active[faces], axis=1))
    face_vertices = faces[affected]
    pairs = cKDTree(source['positions']).query_pairs(1e-6, output_type='ndarray')
    graph = sparse.coo_matrix((np.ones(len(pairs) * 2), (np.r_[pairs[:, 0], pairs[:, 1]], np.r_[pairs[:, 1], pairs[:, 0]])), shape=(len(active), len(active))).tocsr()
    groups, labels = connected_components(graph, directed=False)
    factors = np.ones(groups)
    animation = next(a for a in source['d']['animations'] if a['name'] == args.clip)
    duration = max(float(read(source['d'], source['b'], s['input']).max()) for s in animation['samplers'])
    cache = []
    for phase in np.arange(128) / 128:
        before, _ = pose(source, args.clip, float(phase * duration))
        after, _ = pose(candidate, args.clip, float(phase * duration))
        original = before[face_vertices]
        shift = (after - before)[face_vertices]
        cross = np.cross(original[:, 1] - original[:, 0], original[:, 2] - original[:, 0])
        cache.append((original, shift, cross, np.linalg.norm(cross, axis=1)))
    initial_bad = set()
    rounds = []
    for step in range(64):
        bad_faces = set()
        scale = factors[labels[face_vertices]][:, :, None]
        for original, shift, cross, area in cache:
            tri = original + shift * scale
            current_cross = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
            bad = (np.einsum('ij,ij->i', cross, current_cross) <= 0) & (area > 1e-12)
            bad |= (np.linalg.norm(current_cross, axis=1) < area * .15) & (area > 1e-12)
            bad_faces.update(affected[bad].tolist())
        if step == 0:
            initial_bad = set(bad_faces)
        rounds.append({'iteration': step, 'invalid_source_faces': len(bad_faces)})
        print('retreat', step, len(bad_faces), flush=True)
        if not bad_faces:
            break
        factors[np.unique(labels[faces[list(bad_faces)]])] *= .65
    if bad_faces:
        raise ValueError('Could not stabilize the continuous source faces')
    d, raw = load(args.input)
    b = bytearray(raw)
    primitive = d['meshes'][candidate['node']['mesh']]['primitives'][0]
    normals = unit(read(source['d'], source['b'], sp['attributes']['NORMAL']))
    normal_deltas = [unit(normals + read(source['d'], source['b'], t['NORMAL'])) - normals if 'NORMAL' in t else np.zeros_like(normals) for t in sp['targets']]
    rows = [json.loads(line.split(' ', 1)[1]) for line in args.native.read_text().splitlines() if line.startswith('GARMENT_FULL_SOURCE ')]
    rows = {round(row['phase'], 8): row['measurement'] for row in rows if row['id'] == 'mio' and row['clip'] == args.clip and row['phase'] < 1}
    phases = np.unique(np.r_[np.arange(16) / 16, .2, .8]) if len(added) > 1 else [args.normal_reference_phase]
    for phase, index in zip(phases, added):
        delta = candidate['shapes'][index] * factors[labels, None]
        row = rows[float(phase)]
        source_values = row['blend_shape_values'][source['node']['name']]
        curve = patch_weights(source['d'], source['b'], animation, source['ni'], len(source['names']), np.asarray([row['clip_time']]))[0]
        for k, name in enumerate(source['names']):
            if name not in source_values:
                if curve[k] != 0:
                    raise ValueError('Missing nonzero source target in native reference')
                source_values[name] = 0
        before, _ = pose(source, args.clip, row['clip_time'], row, actual_shapes=True)
        matrices = final_matrices(source, row)
        B = np.zeros((len(active), 3, 3))
        for slot in range(source['joints'].shape[1]):
            B += matrices[source['joints'][:, slot], :3, :3] * source['weights'][:, slot, None, None]
        shift = np.einsum('nij,nj->ni', B, delta)
        old_geo = geometry_normals(before, faces)
        new_geo = geometry_normals(before + shift, faces)
        normal = normals.copy()
        values = row['blend_shape_values'][source['node']['name']]
        for name, dn in zip(source['names'], normal_deltas):
            normal += float(values[name]) * dn
        original_render = unit(np.einsum('nij,nj->ni', B, unit(normal)))
        desired_render = unit(rotate_between(old_geo, new_geo, original_render))
        desired_rest = unit(np.einsum('nij,nj->ni', np.linalg.pinv(B), desired_render))
        offset = normals - normal
        along = np.sum(offset * desired_rest, axis=1)
        scale = -along + np.sqrt(np.maximum(along * along + 1 - np.sum(offset * offset, axis=1), 0))
        dn = unit(offset + scale[:, None] * desired_rest) - normals
        dn[~active] = 0
        primitive['targets'][index] = {'POSITION': append(d, b, primitive['attributes']['POSITION'], delta.astype(np.float32)),
                                       'NORMAL': append(d, b, primitive['attributes']['NORMAL'], dn.astype(np.float32))}
    save(d, b, args.output)
    result = {'source': str(args.source), 'source_sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
              'input': str(args.input), 'input_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
              'output': str(args.output), 'output_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
              'scope': f'128 authored {args.clip} phases; shared group factor across all new targets, source payloads untouched; final native poses and surface coverage require separate checks',
              'initial_invalid_source_faces': sorted(initial_bad), 'rounds': rounds,
              'retreated_vertices': int(np.count_nonzero((factors[labels] < 1) & active)),
              'minimum_group_factor': float(factors.min())}
    args.report.write_text(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--native', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--clip', default='run')
    parser.add_argument('--prefix', default='GarmentFoldFair_')
    parser.add_argument('--normal-reference-phase', type=float, default=.25)
    run(parser.parse_args())

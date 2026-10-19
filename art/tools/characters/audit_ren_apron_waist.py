"""Audit a rest-space Ren apron repair without starting Godot.

Checks exact payload preservation and all twelve authored clips at 128 phases
for newly reversed/collapsed affected source triangles. Replays labelled
source-native collision witnesses through unchanged real final bone bases;
those candidate results are counterfactual, not candidate-native acceptance.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

import numpy as np

from audit_local_garments import mesh_state, pose
from prepare_local_garments import read
from source_surface_rays import envelope
from motion_math import world_matrices


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def skin_delta(state, clip, time, delta, row=None):
    animation = next(a for a in state['d']['animations'] if a['name'] == clip)
    if row:
        bones = {b['name'].replace('mixamorig_', 'mixamorig:'): b for b in row['bones']}
        rotations = np.asarray([np.asarray(bones[state['d']['nodes'][j]['name']]['basis']).T
                                for j in state['skin']['joints']])
    else:
        worlds, _ = world_matrices(state['d'], state['b'], animation, time)
        rotations = np.asarray([worlds[j][:3, :3] for j in state['skin']['joints']])
    linear = rotations @ state['binds'][:, :3, :3]
    result = np.zeros_like(delta, dtype=float)
    for slot in range(state['joints'].shape[1]):
        result += np.einsum('nij,nj->ni', linear[state['joints'][:, slot]], delta) * state['weights'][:, slot, None]
    return result


def verify(args):
    old, new = mesh_state(args.source, 'ren'), mesh_state(args.candidate, 'ren')
    d, c, binary, candidate_binary = old['d'], new['d'], old['b'], new['b']
    op = d['meshes'][old['node']['mesh']]['primitives'][0]
    np_ = c['meshes'][new['node']['mesh']]['primitives'][0]
    delta = new['positions'] - old['positions']
    moved = np.any(delta != 0, axis=1)
    faces = read(d, binary, op['indices']).reshape(-1, 3)
    affected_faces = np.any(moved[faces], axis=1)
    face_ids = np.flatnonzero(affected_faces)
    patch_faces = faces[affected_faces]
    normal_changes = [i for i, (ot, nt) in enumerate(zip(op['targets'], np_['targets'])) if ot != nt]
    allowed_primitive = copy.deepcopy(np_)
    for key in ['POSITION', 'NORMAL']:
        allowed_primitive['attributes'][key] = op['attributes'][key]
    for old_target, target in zip(op['targets'], allowed_primitive['targets']):
        if 'NORMAL' in old_target:
            target['NORMAL'] = old_target['NORMAL']
    other_primitive_exact = allowed_primitive == op
    restored = copy.deepcopy(c)
    restored['meshes'][new['node']['mesh']]['primitives'][0] = copy.deepcopy(op)
    restored['accessors'] = restored['accessors'][:len(d['accessors'])]
    restored['bufferViews'] = restored['bufferViews'][:len(d['bufferViews'])]
    restored['buffers'] = copy.deepcopy(d['buffers'])
    exact_other_document = restored == d
    prefix_exact = candidate_binary[:len(binary)] == binary
    accessors_exact = all(np.array_equal(read(d, binary, i), read(c, candidate_binary, i)) for i in range(len(d['accessors'])))
    shape_positions_exact = all(np.array_equal(a, b) for a, b in zip(old['shapes'], new['shapes']))
    body_zero = float(np.linalg.norm(delta[old['body']], axis=1).max()) == 0
    old_normal = read(d, binary, op['attributes']['NORMAL'])
    new_normal = read(c, candidate_binary, np_['attributes']['NORMAL'])
    body_normal_exact = np.array_equal(old_normal[old['body']], new_normal[old['body']])
    target_body_normals_exact = all(np.array_equal(read(d, binary, a['NORMAL'])[old['body']], read(c, candidate_binary, b['NORMAL'])[old['body']])
                                    for a, b in zip(op['targets'], np_['targets']) if 'NORMAL' in a)
    assert exact_other_document and other_primitive_exact and prefix_exact and accessors_exact and shape_positions_exact and body_zero and body_normal_exact and target_body_normals_exact
    assert old['names'] == new['names'] and np.all(delta[:, 1] == 0) and float(np.linalg.norm(delta, axis=1).max()) <= .001
    clips = []
    for animation in ([] if args.only_native_witnesses else d['animations']):
        duration = max(float(read(d, binary, s['input']).max()) for s in animation['samplers'])
        row = {'clip': animation['name'], 'samples': args.phases, 'new_flip_count': 0,
               'new_collapse_count': 0, 'minimum_affected_area_ratio': 1., 'maximum_patch_displacement_m': 0., 'bad': []}
        for phase in np.arange(args.phases) / args.phases:
            base, directions = pose(old, animation['name'], duration * phase, disable_local=True)
            after = base + skin_delta(old, animation['name'], duration * phase, delta)
            a, b = base[patch_faces], after[patch_faces]
            an = np.cross(a[:, 1] - a[:, 0], a[:, 2] - a[:, 0])
            bn = np.cross(b[:, 1] - b[:, 0], b[:, 2] - b[:, 0])
            length = np.linalg.norm(an, axis=1)
            ratio = np.linalg.norm(bn, axis=1) / np.maximum(length, 1e-20)
            valid = length > 1e-12
            flip = valid & (np.sum(an * bn, axis=1) <= 0)
            collapse = valid & (ratio < .15)
            row['new_flip_count'] += int(flip.sum())
            row['new_collapse_count'] += int(collapse.sum())
            row['minimum_affected_area_ratio'] = min(row['minimum_affected_area_ratio'], float(ratio[valid].min()))
            row['maximum_patch_displacement_m'] = max(row['maximum_patch_displacement_m'], float(np.linalg.norm(after - base, axis=1).max()))
            if flip.any() or collapse.any():
                row['bad'].append({'phase': float(phase), 'source_faces': face_ids[flip | collapse].tolist()})
        clips.append(row)
        print(animation['name'], 'flips', row['new_flip_count'], 'collapse', row['new_collapse_count'], flush=True)
    native = []
    if args.native:
        samples = json.loads(args.native.read_text())['samples']
        assert json.loads((args.native.parent / 'model-hashes.json').read_text())['CH_ren.glb'] == sha(args.source)
        for sample in samples:
            measurement = sample['measurement']
            row = {'clip': sample['clip'], 'phase': sample['phase'], 'layers': {}}
            base, directions = pose(old, sample['clip'], measurement['clip_time'], measurement, actual_shapes=True, disable_local=True)
            after = base + skin_delta(old, sample['clip'], measurement['clip_time'], delta, measurement)
            for side, sign in [('front', 1), ('back', -1)]:
                witness = measurement['layers'][side].get('worst_hit', {})
                if not witness:
                    continue
                body = witness['body']
                rest = np.asarray(body['rest_position'])
                matches = np.flatnonzero(np.linalg.norm(old['positions'] - rest, axis=1) < 1e-6)
                if not len(matches):
                    raise ValueError('Native body witness cannot map to source')
                point_ids = np.asarray(matches[:1])
                source_hit = envelope(base, old['layers'][side], base[point_ids], sign)
                new_hit = envelope(after, old['layers'][side], after[point_ids], sign)
                source_depth = float(source_hit['signed_depth_m'][0])
                candidate_depth = float(new_hit['signed_depth_m'][0])
                row['layers'][side] = {'source_native_depth_m': witness['depth_m'],
                                      'source_double_ray_depth_m': source_depth if np.isfinite(source_depth) else None,
                                      'candidate_counterfactual_depth_m': candidate_depth if np.isfinite(candidate_depth) else None,
                                      'candidate_retains_source_ray_coverage': bool(np.isfinite(candidate_depth)),
                                      'source_witness_vertex': int(point_ids[0]),
                                      'actual_imported_cloth_face_id': witness['source_surface_triangle_index']}
            native.append(row)
    replayed_layers = [v for row in native for v in row['layers'].values()]
    replay_gate = bool(replayed_layers) and all(v['candidate_retains_source_ray_coverage'] and v['candidate_counterfactual_depth_m'] <= .005 for v in replayed_layers)
    result = {'scope': __doc__, 'source': str(args.source), 'source_sha256': sha(args.source),
              'candidate': str(args.candidate), 'candidate_sha256': sha(args.candidate),
              'all_other_document_exact': exact_other_document, 'old_binary_prefix_exact': prefix_exact,
              'all_primitive_payload_except_base_P_N_target_N_exact': other_primitive_exact,
              'every_original_accessor_exact': accessors_exact, 'all_animation_bone_tracks_exact': d['animations'] == c['animations'],
              'all_skeleton_nodes_skins_exact': d['nodes'] == c['nodes'] and d['skins'] == c['skins'],
              'all_target_positions_exact': shape_positions_exact, 'target_normal_indices_modified': normal_changes,
              'body_position_delta_m': 0., 'body_base_normals_exact': body_normal_exact,
              'body_target_normals_exact': target_body_normals_exact,
              'affected_source_face_count': len(face_ids), 'clips': clips,
              'native_source_witness_replay': native,
              'source_native_worst_layers_replayed': len(replayed_layers),
              'source_native_worst_layers_over5mm': sum(v['source_native_depth_m'] > .005 for v in replayed_layers),
              'candidate_counterfactual_worst_layers_over5mm': sum(v['candidate_retains_source_ray_coverage'] and v['candidate_counterfactual_depth_m'] > .005 for v in replayed_layers),
              'candidate_source_worst_ray_misses': sum(not v['candidate_retains_source_ray_coverage'] for v in replayed_layers),
              'passes_source_native_worst_witness_5mm': replay_gate,
              'native_scope': 'Candidate counterfactual of exact old final bone poses, not new imported candidate proof.',
              'passes_new_face_validity': all(not row['new_flip_count'] and not row['new_collapse_count'] for row in clips)}
    args.output.write_text(json.dumps(result, indent=2))
    print(args.output)
    if not result['passes_new_face_validity'] or (args.expect_clear and not replay_gate):
        raise SystemExit(1)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', required=True, type=Path)
    p.add_argument('--candidate', required=True, type=Path)
    p.add_argument('--native', type=Path)
    p.add_argument('--phases', type=int, default=128)
    p.add_argument('--only-native-witnesses', action='store_true')
    p.add_argument('--expect-clear', action='store_true')
    p.add_argument('--output', required=True, type=Path)
    verify(p.parse_args())

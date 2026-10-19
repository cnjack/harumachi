"""Independent same-pose surface and exact-preservation check for apron weights.

128 phases of every authored action check newly inverted/collapsed triangles,
original body0 displacement and physical UV seams. No contact-solver acceptance
is inferred: final source-proxy re-solving and actual Euclidean gap remain due.
"""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np

from audit_local_garments import mesh_state, pose
from prepare_local_garments import read
from prepare_kazuko_thigh_weights import physical_groups

PROTECTED_JSON_KEYS = ['nodes', 'skins', 'animations', 'materials', 'images',
                       'textures', 'samplers', 'scenes', 'scene']


def _assert_preserved(source, candidate):
    source_doc, source_bin = source['d'], source['b']
    candidate_doc, candidate_bin = candidate['d'], candidate['b']
    for key in PROTECTED_JSON_KEYS:
        assert source_doc.get(key) == candidate_doc.get(key), 'Protected JSON changed: ' + key
    assert candidate_doc['accessors'][:len(source_doc['accessors'])] == source_doc['accessors'], \
        'Original accessor JSON changed'
    assert candidate_bin[:len(source_bin)] == source_bin, 'Original binary payload modified'

    protected_attributes = 0
    for mesh_index, (source_mesh, candidate_mesh) in enumerate(zip(source_doc['meshes'], candidate_doc['meshes'])):
        assert {k: v for k, v in source_mesh.items() if k != 'primitives'} == \
            {k: v for k, v in candidate_mesh.items() if k != 'primitives'}
        for primitive_index, (source_primitive, candidate_primitive) in enumerate(
                zip(source_mesh['primitives'], candidate_mesh['primitives'])):
            assert {k: v for k, v in source_primitive.items() if k != 'attributes'} == \
                {k: v for k, v in candidate_primitive.items() if k != 'attributes'}, \
                'Original morph/index/material descriptor changed'
            for name, index in source_primitive['attributes'].items():
                if (mesh_index == source['node']['mesh'] and primitive_index == 0
                        and name.startswith(('JOINTS_', 'WEIGHTS_'))):
                    continue
                assert index == candidate_primitive['attributes'][name]
                assert np.array_equal(read(source_doc, source_bin, index),
                                      read(candidate_doc, candidate_bin,
                                           candidate_primitive['attributes'][name])), name
                protected_attributes += 1

    body = source['body']
    assert np.array_equal(source['joints'][body], candidate['joints'][body]), 'Body0 weights changed'
    assert np.array_equal(source['weights'][body], candidate['weights'][body]), 'Body0 weights changed'
    return protected_attributes


def _audit_clip(source, candidate, animation, faces, pairs, body, samples):
    source_doc, source_bin = source['d'], source['b']
    clip = animation['name']
    duration = max(float(read(source_doc, source_bin, s['input']).max()) for s in animation['samplers'])
    flipped = set()
    collapsed = set()
    seam_added = 0.0
    body_shift = 0.0
    shift_max = 0.0
    phase_grid = np.unique(np.r_[np.arange(samples) / samples, .2, .8, 1.])

    for phase in phase_grid:
        before, _ = pose(source, clip, float(phase * duration))
        after, _ = pose(candidate, clip, float(phase * duration))
        delta = after - before
        original = before[faces]
        updated = after[faces]
        original_cross = np.cross(original[:, 1] - original[:, 0], original[:, 2] - original[:, 0])
        updated_cross = np.cross(updated[:, 1] - updated[:, 0], updated[:, 2] - updated[:, 0])
        area = np.linalg.norm(original_cross, axis=1)
        valid = area > 1e-12
        bad = np.flatnonzero(((original_cross * updated_cross).sum(1) <= 0) & valid)
        small = np.flatnonzero((np.linalg.norm(updated_cross, axis=1) < .15 * area) & valid)
        flipped.update(bad.tolist())
        collapsed.update(small.tolist())
        body_shift = max(body_shift, float(np.linalg.norm(delta[body], axis=1).max()))
        shift_max = max(shift_max, float(np.linalg.norm(delta, axis=1).max()))
        if len(pairs):
            seam_added = max(seam_added, float(np.linalg.norm(delta[pairs[:, 0]] - delta[pairs[:, 1]], axis=1).max()))

    return {
        'clip': clip,
        'phases': len(phase_grid),
        'newly_inverted_faces': sorted(flipped),
        'near_collapsed_faces': sorted(collapsed),
        'body0_maximum_displacement_m': body_shift,
        'physical_UV_seam_maximum_added_gap_m': seam_added,
        'maximum_cloth_weight_change_displacement_m': shift_max,
    }


def audit(args):
    source = mesh_state(args.source, 'kazuko')
    candidate = mesh_state(args.candidate, 'kazuko')
    protected_attributes = _assert_preserved(source, candidate)

    body = source['body']
    _, pairs, _, _ = physical_groups(source)
    primitive = source['d']['meshes'][source['node']['mesh']]['primitives'][0]
    faces = read(source['d'], source['b'], primitive['indices']).reshape(-1, 3)
    changed = (np.any(source['joints'] != candidate['joints'], axis=1)
               | np.any(source['weights'] != candidate['weights'], axis=1))
    local_support = np.any(np.asarray(
        [np.linalg.norm(source['shapes'][i], axis=1) > 0 for i in source['local']]), axis=0)
    assert not np.any(changed & ~local_support), 'Skin outside existing apron templates changed'

    rows = []
    bad_union = set()
    maximum_body = 0.0
    maximum_seam_added = 0.0
    max_shift = 0.0
    for animation in source['d']['animations']:
        if args.clips and animation['name'] not in args.clips:
            continue
        row = _audit_clip(source, candidate, animation, faces, pairs, body, args.samples)
        bad_union.update(row['newly_inverted_faces'])
        bad_union.update(row['near_collapsed_faces'])
        maximum_body = max(maximum_body, row['body0_maximum_displacement_m'])
        maximum_seam_added = max(maximum_seam_added, row['physical_UV_seam_maximum_added_gap_m'])
        max_shift = max(max_shift, row['maximum_cloth_weight_change_displacement_m'])
        rows.append(row)
        print(row['clip'], 'flips', len(row['newly_inverted_faces']),
              'collapsed', len(row['near_collapsed_faces']),
              'body', row['body0_maximum_displacement_m'],
              'seam', row['physical_UV_seam_maximum_added_gap_m'], flush=True)

    result = {
        'source': str(args.source),
        'source_sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
        'candidate': str(args.candidate),
        'candidate_sha256': hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
        'scope': '128-phase authored action skin/morph preflight plus .2/.8/1; '
                 'no post-IK contact solver, no native candidate acceptance',
        'all_protected_JSON_accessors_original_binary_exact': True,
        'protected_base_attributes': protected_attributes,
        'body0_skin_rows_exact': True,
        'protected_body0_vertices': len(body),
        'actions': len(rows),
        'full_original_action_set': len(rows) == len(source['d']['animations']),
        'uniform_phases_per_action': args.samples,
        'evaluated_pose_count': sum(r['phases'] for r in rows),
        'samples': rows,
        'unique_problem_faces': sorted(bad_union),
        'maximum_body0_displacement_m': maximum_body,
        'maximum_physical_seam_added_gap_m': maximum_seam_added,
        'maximum_cloth_displacement_m': max_shift,
        'pending': ['actual source-proxy solver re-run', 'Euclidean cloth-to-body gap A/B',
                    'native review on existing desktop only'],
        'pass': not bad_union and maximum_body < 1e-10 and maximum_seam_added < 1e-5,
    }
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(args.output, result['pass'], flush=True)
    if not result['pass']:
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--samples', type=int, default=128)
    parser.add_argument('--clips', nargs='+')
    audit(parser.parse_args())


if __name__ == '__main__':
    main()

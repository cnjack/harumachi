"""Independently test bare GLB legs, without Godot modifiers or repair formulas.

The same gates must fail for the unrepaired input. These checks concern weights,
bone trajectories and immutable source data; they do not certify cloth contact.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json

import numpy as np
from scipy.spatial.transform import Rotation
from scipy.spatial import cKDTree

from glb_io import load, durations
from motion_math import world_matrices
from prepare_local_garments import colours
from repair_head_neck import read
from repair_joint_fit import parts


def measure(path, character):
    doc, blob = load(path)
    rest, parents = world_matrices(doc, blob)
    ids = {node.get('name'): index for index, node in enumerate(doc['nodes'])}
    lengths = durations(path)
    main = parts(doc, blob)[0]
    rgb = colours(doc, blob, main['primitive'])
    red, green, blue = rgb.T
    pants = (red > green * 1.04) & (green > blue * 1.08)
    tests = []
    thigh_reports = []
    for side, sign in [('Left', 1.), ('Right', -1.)]:
        thigh = ids['mixamorig:' + side + 'UpLeg']
        shin = ids['mixamorig:' + side + 'Leg']
        hip, knee = rest[thigh][:3, 3], rest[shin][:3, 3]
        length = np.linalg.norm(hip - knee)
        xyz = main['xyz']
        # A material/geometry region; never use the repaired weight mask to
        # define the acceptance population.
        region = (pants & (xyz[:, 1] > knee[1] + .25 * length)
                  & (xyz[:, 1] < hip[1] - .35 * length)
                  & (xyz[:, 0] * sign > .04) & (np.abs(xyz[:, 0]) < .25))
        assert region.sum() > 50
        hip_share = main['dense'][region, main['joints'].index(ids['mixamorig:Hips'])]
        thigh_share = main['dense'][region, main['joints'].index(thigh)]
        # An independently rotated hip, knee unaltered. Mid-thigh material
        # should follow that thigh instead of remaining attached to the pelvis.
        desired = rest[thigh].copy()
        desired[:3, :3] = Rotation.from_rotvec([-np.pi/3, 0., 0.]).as_matrix() @ desired[:3, :3]
        local = np.linalg.inv(rest[parents[thigh]]) @ desired
        posed, _ = world_matrices(doc, blob, rotations={thigh: Rotation.from_matrix(local[:3, :3]).as_quat()})
        actual = parts(doc, blob, posed)[0]['xyz'][region]
        expected = (desired @ np.linalg.inv(rest[thigh]) @ np.c_[xyz[region], np.ones(region.sum())].T).T[:, :3]
        lag = np.linalg.norm(actual - expected, axis=1)
        thigh_reports.append({'side': side, 'vertices': int(region.sum()),
            'mean_pelvis_share': float(hip_share.mean()), 'mean_thigh_share': float(thigh_share.mean()),
            'hip_flexion_60deg_material_lag_p95_m': float(np.quantile(lag, .95)),
            'hip_flexion_60deg_material_lag_max_m': float(lag.max())})
        if character == 'ren':
            tests.append({'name': side + ' middle trouser thigh follows its own thigh',
                          'passed': bool(thigh_share.mean() > .95 and np.quantile(lag, .95) < .012)})
    walk = next(a for a in doc['animations'] if a['name'] == 'walk')
    offsets = []
    for phase in np.linspace(0., 1., 257):
        world, _ = world_matrices(doc, blob, walk, phase * lengths['walk'])
        for side, sign in [('Left', 1.), ('Right', -1.)]:
            hip, knee, ankle = [world[ids['mixamorig:' + side + suffix]][:3, 3]
                                for suffix in ['UpLeg', 'Leg', 'Foot']]
            axis = (ankle - hip) / np.linalg.norm(ankle - hip)
            deviation = knee - hip - axis * np.dot(knee - hip, axis)
            offsets.append([deviation[0] * sign, deviation[2]])
    if character == 'sora':
        tests.append({'name': 'Bare GLB walk knees bend forward without inward collapse',
                      'passed': bool(np.min(np.asarray(offsets)[:, 0]) >= -.010
                                     and np.min(np.asarray(offsets)[:, 1]) > .001)})
    return {'character': character, 'file': str(path.resolve()),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'thigh_material': thigh_reports,
            'walk_samples': 257, 'walk_minimum_outward_knee_m': float(np.min(np.asarray(offsets)[:, 0])),
            'walk_minimum_forward_knee_m': float(np.min(np.asarray(offsets)[:, 1])),
            'tests': tests, 'passed': all(row['passed'] for row in tests),
            'no_runtime_modifiers': True, 'cloth_contact_acceptance': None}


def invariants(source, candidate, character):
    a, ab = load(source)
    b, bb = load(candidate)
    nodes_a, nodes_b = copy.deepcopy(a['nodes']), copy.deepcopy(b['nodes'])
    for node in nodes_b:
        if node.get('name') == 'Rig':
            node.get('extras', {}).pop('leg_foundation', None)
    assert nodes_a == nodes_b, 'Rest skeleton or mesh transform changed'
    for key in ['skins', 'materials', 'textures', 'images', 'samplers', 'scene', 'scenes']:
        assert a.get(key) == b.get(key), key
    if character == 'sora':
        assert a['meshes'] == b['meshes'], 'Sora mesh and skin-weight accessors changed'
    corrected_template_vertices = set()
    for ma, mb in zip(a['meshes'], b['meshes']):
        for pa, pb in zip(ma['primitives'], mb['primitives']):
            assert pa.get('indices') == pb.get('indices')
            assert ma.get('extras') == mb.get('extras')
            for name, ta, tb in zip(ma.get('extras',{}).get('targetNames',[]),pa.get('targets',[]),pb.get('targets',[])):
                if ta == tb:
                    continue
                assert character == 'ren' and name.startswith('Garment_Local_') and ta.keys() == tb.keys()
                for semantic in ta:
                    if semantic != 'POSITION':
                        assert ta[semantic] == tb[semantic]
                old_values, new_values = read(a, ab, ta['POSITION']), read(b, bb, tb['POSITION'])
                changed = np.flatnonzero(np.any(old_values != new_values,axis=1))
                assert len(changed) and np.all(new_values[changed] == 0.)
                rgb = colours(a,ab,pa)[changed]
                assert np.all((rgb[:,0] > rgb[:,1]) & (rgb[:,1] > rgb[:,2]) & (rgb[:,0]-rgb[:,2] > .065)), 'Changed target is not khaki trouser material'
                points = read(a,ab,pa['attributes']['POSITION'])
                assert np.all((points[changed,1] > .55) & (points[changed,1] < .82) & (np.abs(points[changed,0]) < .25)), 'Target change outside thigh seam region'
                for index in changed:
                    copies = np.flatnonzero(np.linalg.norm(points-points[index],axis=1) < 1e-7)
                    assert len(copies) > 1 and np.any(np.linalg.norm(old_values[copies],axis=1) < 1e-7), 'No original zero-target physical copy'
                    corrected_template_vertices.add(int(index))
            for key, index in pa['attributes'].items():
                if not key.startswith(('WEIGHTS_', 'JOINTS_')):
                    assert np.array_equal(read(a, ab, index), read(b, bb, pb['attributes'][key]))
    assert bytes(bb[:len(ab)]) == ab, 'Original binary payload changed'
    maximum_weight_error = 0.
    for part in parts(b, bb):
        assert np.isfinite(part['weights']).all() and part['weights'].min() >= 0.
        maximum_weight_error = max(maximum_weight_error, float(np.max(np.abs(part['weights'].sum(1)-1.))))
        assert maximum_weight_error < 1e-5
    for animation in b['animations']:
        for sampler in animation['samplers']:
            time = read(b, bb, sampler['input']).ravel()
            # New rotations must have strictly ordered, finite serialized keys.
            if sampler not in next(x for x in a['animations'] if x['name'] == animation['name'])['samplers']:
                assert np.isfinite(time).all() and np.all(np.diff(time) > 0.)
    for original, updated in zip(a['animations'], b['animations']):
        if character != 'sora' or original['name'] != 'walk':
            assert original == updated
        else:
            assert original['channels'] == updated['channels']
            changed = {i for i, (x, y) in enumerate(zip(original['samplers'], updated['samplers'])) if x != y}
            expected = {c['sampler'] for c in original['channels']
                        if c['target']['path'] == 'rotation' and any(a['nodes'][c['target']['node']].get('name') ==
                            'mixamorig:' + side + suffix for side in ['Left', 'Right'] for suffix in ['UpLeg', 'Leg', 'Foot'])}
            assert changed == expected
    max_foot_position_error = 0.
    max_foot_basis_error = 0.
    if character == 'sora':
        old_walk = next(x for x in a['animations'] if x['name'] == 'walk')
        new_walk = next(x for x in b['animations'] if x['name'] == 'walk')
        feet = [i for i, node in enumerate(a['nodes']) if node.get('name') in
                ['mixamorig:' + side + part for side in ['Left', 'Right'] for part in ['Foot', 'ToeBase']]]
        for t in np.linspace(0., durations(source)['walk'], 1025):
            old_world, _ = world_matrices(a, ab, old_walk, t)
            new_world, _ = world_matrices(b, bb, new_walk, t)
            for foot in feet:
                max_foot_position_error = max(max_foot_position_error, float(np.linalg.norm(old_world[foot][:3,3]-new_world[foot][:3,3])))
                max_foot_basis_error = max(max_foot_basis_error, float(np.max(np.abs(old_world[foot][:3,:3]-new_world[foot][:3,:3]))))
        assert max_foot_position_error < .0002 and max_foot_basis_error < .001
    # UV copies that share the same original point and weights must continue
    # to deform together. Compare dense weights, not arbitrary joint ordering.
    old_part, new_part = parts(a, ab)[0], parts(b, bb)[0]
    pairs = cKDTree(old_part['xyz']).query_pairs(1e-7, output_type='ndarray')
    identical = np.max(np.abs(old_part['dense'][pairs[:,0]]-old_part['dense'][pairs[:,1]]),axis=1) < 1e-7
    pairs = pairs[identical]
    seam_weight_error = float(np.max(np.abs(new_part['dense'][pairs[:,0]]-new_part['dense'][pairs[:,1]])))
    assert seam_weight_error < 1e-5, 'New skin weights split previously welded UV copies'
    new_pairs = cKDTree(new_part['xyz']).query_pairs(1e-7, output_type='ndarray')
    new_pairs = new_pairs[np.max(np.abs(new_part['dense'][new_pairs[:,0]]-new_part['dense'][new_pairs[:,1]]),axis=1) < 1e-5]
    local_template_gap = 0.
    for name, target in zip(b['meshes'][0].get('extras',{}).get('targetNames',[]),new_part['primitive'].get('targets',[])):
        if name.startswith('Garment_Local_'):
            values = read(b,bb,target['POSITION'])
            local_template_gap = max(local_template_gap,float(np.max(np.linalg.norm(values[new_pairs[:,0]]-values[new_pairs[:,1]],axis=1))))
    assert local_template_gap < .0001, 'Local garment targets split coincident equal-weight source seams'
    return {'rest_skeleton_bind_matrices_mesh_textures_exact': True,
            'nonlocal_and_unreported_morph_targets_exact': True,
            'khaki_uv_copy_vertices_with_removed_stray_local_deltas': sorted(corrected_template_vertices),
            'original_binary_prefix_exact': True, 'only_permitted_animation_channels_changed': True,
            'new_sampler_times_strictly_increasing': True,
            'maximum_weight_sum_error': maximum_weight_error,
            'matched_uv_copy_pairs': len(pairs), 'maximum_uv_copy_dense_weight_error': seam_weight_error,
            'maximum_equal_weight_uv_copy_local_template_gap_m':local_template_gap,
            'sora_walk_foot_and_toe_comparison_samples': 1025 if character == 'sora' else 0,
            'maximum_foot_or_toe_position_change_m': max_foot_position_error,
            'maximum_foot_or_toe_basis_change': max_foot_basis_error}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--character', choices=['sora', 'ren'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = {'before': measure(args.source, args.character), 'after': measure(args.candidate, args.character),
              'invariants': invariants(args.source, args.candidate, args.character)}
    result['negative_control_failed'] = not result['before']['passed']
    result['passed'] = result['negative_control_failed'] and result['after']['passed']
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['passed'] else 1)

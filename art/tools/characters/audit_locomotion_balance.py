#!/usr/bin/env python3
"""Independent rebuilt-gait torso/arm regression and unchanged-lower-body audit.

Run the current rejected asset as --candidate first; it must fail the torso
limits. This authored audit does not replace final-modifier/native review.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import numpy as np
from glb_io import load
from repair_head_neck import read
from motion_math import world_matrices
from rebuild_locomotion import shoe_sources, shoe_points


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def exact(a, b):
    return a.dtype == b.dtype and a.shape == b.shape and a.tobytes() == b.tobytes()


def names(d):
    return {n.get('name'): i for i, n in enumerate(d['nodes'])}


def action(d, clip):
    return next(a for a in d['animations'] if a['name'] == clip)


def duration(d, b, a):
    return max(float(read(d, b, s['input']).max()) for s in a['samplers'])


def metrics(d, b, samples, clip='walk'):
    ids = names(d)
    rest, _ = world_matrices(d, b)
    a = action(d, clip)
    total = duration(d, b, a)
    rows = []
    worlds = []
    for phase in np.arange(samples) / samples:
        w, _ = world_matrices(d, b, a, float(phase * total))
        worlds.append(w)
        row = {'phase': float(phase)}
        for key in ['Spine2', 'Head']:
            i = ids['mixamorig:' + key]
            deformation = w[i][:3, :3] @ np.linalg.inv(rest[i][:3, :3])
            row[key + '_roll_deg'] = math.degrees(math.atan2(-deformation[0, 1], deformation[1, 1]))
        row['shoulder_height_difference_m'] = float(w[ids['mixamorig:LeftArm']][1, 3] - w[ids['mixamorig:RightArm']][1, 3])
        for side in ['Left', 'Right']:
            row[side + '_hand_forward'] = float(w[ids['mixamorig:' + side + 'Hand']][2, 3] - w[ids['mixamorig:Hips']][2, 3])
            row[side + '_foot_forward'] = float(w[ids['mixamorig:' + side + 'Foot']][2, 3] - w[ids['mixamorig:Hips']][2, 3])
        rows.append(row)
    result = {'chest_roll_peak_deg': max(abs(r['Spine2_roll_deg']) for r in rows),
              'head_roll_peak_deg': max(abs(r['Head_roll_deg']) for r in rows),
              'shoulder_height_oscillation_m': float(np.ptp([r['shoulder_height_difference_m'] for r in rows])),
              'same_side_hand_foot_correlation': {side: float(np.corrcoef([r[side + '_hand_forward'] for r in rows], [r[side + '_foot_forward'] for r in rows])[0, 1]) for side in ['Left', 'Right']}}
    return result, worlds, rows


def audit(before, candidate, samples, clip='walk', allowed_clips=None):
    s, sb = load(before)
    d, b = load(candidate)
    old_metrics, old_worlds, _ = metrics(s, sb, samples, clip)
    new_metrics, new_worlds, rows = metrics(d, b, samples, clip)
    old_walk, new_walk = action(s, clip), action(d, clip)
    changes = []
    times_exact = True
    interpolation_exact = True
    for channel in old_walk['channels']:
        matching = [c for c in new_walk['channels'] if c['target'] == channel['target']]
        if len(matching) != 1:
            raise ValueError('Missing/duplicated original channel')
        other = matching[0]
        os, ns = old_walk['samplers'][channel['sampler']], new_walk['samplers'][other['sampler']]
        times_exact &= exact(read(s, sb, os['input']), read(d, b, ns['input']))
        interpolation_exact &= os.get('interpolation', 'LINEAR') == ns.get('interpolation', 'LINEAR')
        if not exact(read(s, sb, os['output']), read(d, b, ns['output'])):
            changes.append({'node': s['nodes'][channel['target']['node']].get('name'), 'path': channel['target']['path']})
    allowed = [{'node': 'mixamorig:Spine', 'path': 'rotation'}]
    if clip == 'run':
        allowed += [{'node': 'mixamorig:' + side + 'Arm', 'path': 'rotation'} for side in ['Left', 'Right']]
    payload = all(d.get(k) == s.get(k) for k in ['nodes', 'meshes', 'skins', 'images', 'materials', 'textures', 'samplers'])
    allowed_clips = allowed_clips or [clip]
    nonwalk = [a for a in s['animations'] if a['name'] not in allowed_clips] == [a for a in d['animations'] if a['name'] not in allowed_clips]
    prefix = b[:len(sb)] == sb
    accessors = d['accessors'][:len(s['accessors'])] == s['accessors'] and d['bufferViews'][:len(s['bufferViews'])] == s['bufferViews']
    ids = names(d)
    lower = ['Hips'] + [side + key for side in ['Left', 'Right'] for key in ['UpLeg', 'Leg', 'Foot', 'ToeBase']]
    lower_error = max(float(np.max(abs(n[ids['mixamorig:' + name]] - o[ids['mixamorig:' + name]]))) for o, n in zip(old_worlds, new_worlds) for name in lower)
    sources = shoe_sources(d, b)
    shoe_error = 0.0
    for old_w, new_w in zip(old_worlds, new_worlds):
        old_shoes, new_shoes = shoe_points(sources, old_w), shoe_points(sources, new_w)
        shoe_error = max(shoe_error, max(float(np.max(abs(old_shoes[side] - new_shoes[side]))) for side in ['Left', 'Right']))
    a = action(d, clip)
    start, _ = world_matrices(d, b, a, 0)
    end, _ = world_matrices(d, b, a, duration(d, b, a))
    seam_error = max(float(np.max(abs(start[i] - end[i]))) for skin in d['skins'] for i in skin['joints'])
    limits = {'chest_roll_peak_deg': 3.0, 'head_roll_peak_deg': 1.0 if clip == 'walk' else 2.0, 'shoulder_height_oscillation_m': .035,
              'same_side_correlation_max': -.85 if clip == 'walk' else -.75, 'run_correlation_regression_margin': .01}
    old_rest, _ = world_matrices(s, sb)
    new_rest, _ = world_matrices(d, b)
    spine_index = ids['mixamorig:Spine']
    old_rest_inverse = np.linalg.inv(old_rest[spine_index][:3, :3])
    new_rest_inverse = np.linalg.inv(new_rest[spine_index][:3, :3])
    forward_error = max(float(np.linalg.norm((nw[spine_index][:3, :3] @ new_rest_inverse)[:, 2] -
                                           (ow[spine_index][:3, :3] @ old_rest_inverse)[:, 2]))
                        for ow, nw in zip(old_worlds, new_worlds))
    arm_out = {'elbow': 0., 'wrist': 0.}
    arm_vector_error = 0.
    arm_basis_error = 0.
    for w in new_worlds:
        for side in ['Left', 'Right']:
            shoulder = w[ids['mixamorig:' + side + 'Arm']][:3, 3]
            arm_out['elbow'] = max(arm_out['elbow'], abs(float(w[ids['mixamorig:' + side + 'ForeArm']][0, 3] - shoulder[0])))
            arm_out['wrist'] = max(arm_out['wrist'], abs(float(w[ids['mixamorig:' + side + 'Hand']][0, 3] - shoulder[0])))
    for old_w, new_w in zip(old_worlds, new_worlds):
        for side in ['Left', 'Right']:
            arm_index = ids['mixamorig:' + side + 'Arm']
            arm_basis_error = max(arm_basis_error, float(np.max(abs(old_w[arm_index][:3, :3] - new_w[arm_index][:3, :3]))))
            for end_name in ['ForeArm', 'Hand']:
                end_index = ids['mixamorig:' + side + end_name]
                arm_vector_error = max(arm_vector_error, float(np.linalg.norm((new_w[end_index][:3, 3] - new_w[arm_index][:3, 3]) -
                                                                            (old_w[end_index][:3, 3] - old_w[arm_index][:3, 3]))))
    failures = []
    for key in ['chest_roll_peak_deg', 'head_roll_peak_deg', 'shoulder_height_oscillation_m']:
        if new_metrics[key] >= limits[key]:
            failures.append(key)
    if any(v >= limits['same_side_correlation_max'] for v in new_metrics['same_side_hand_foot_correlation'].values()):
        failures.append('opposite arm rhythm')
    if clip == 'run' and any(v > old_metrics['same_side_hand_foot_correlation'][side] + .01 for side, v in new_metrics['same_side_hand_foot_correlation'].items()):
        failures.append('running opposite-arm rhythm regressed')
    if not all([payload, nonwalk, prefix, accessors, times_exact, interpolation_exact]) or any(ch not in allowed for ch in changes):
        failures.append('unrelated payload or channel changed')
    if lower_error != 0 or shoe_error > 1e-12 or seam_error > 1e-6:
        failures.append('leg/shoe trajectory or strict endpoint changed')
    if clip == 'run' and forward_error > .00005:
        failures.append('running forward lean or heading changed')
    if clip == 'run' and (arm_vector_error > .0001 or arm_basis_error > .0005):
        failures.append('accepted world arm/elbow/wrist motion changed')
    rig_id = d['nodes'][ids['Rig']].get('extras', {}).get('character_id')
    if clip == 'run' and rig_id == 'sora' and (arm_out['elbow'] >= .050 or arm_out['wrist'] >= .060):
        failures.append('existing Sora arm-outside-shoulder limit')
    return {'scope': __doc__.strip(), 'before': str(before), 'before_sha256': digest(before), 'candidate': str(candidate), 'candidate_sha256': digest(candidate),
            'tool_sha256': digest(Path(__file__)), 'clip': clip, 'allowed_changed_clips': allowed_clips, 'samples': samples, 'old_metrics': old_metrics, 'new_metrics': new_metrics, 'limits': limits,
            'limits_basis': 'Original body-v2 torso peaks1.81deg/.34deg; shoulder oscillation23.6mm. Limits retain a small margin and reject the actual8.61deg/6.60deg/113mm defect.',
            'changed_walk_channels': changes, 'walk_times_bitwise_exact': bool(times_exact), 'walk_interpolation_exact': bool(interpolation_exact),
            'mesh_rest_skin_morph_and_material_json_exact': payload, 'unselected_animations_json_exact': nonwalk, 'old_bin_prefix_exact': prefix,
            'original_accessors_and_views_exact': accessors, 'lower_world_matrix_max_error': lower_error, 'complete_skinned_shoe_max_error_m': shoe_error,
            'all_joint_seam_matrix_max_error': seam_error, 'Spine_forward_vector_max_difference': forward_error,
            'arm_lateral_outside_shoulder_max_m': arm_out, 'arm_relative_elbow_wrist_vector_max_error_m': arm_vector_error,
            'arm_world_basis_max_error': arm_basis_error, 'phase_metrics': rows, 'failures': failures}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--before', type=Path, required=True)
    p.add_argument('--candidate', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--samples', type=int, default=128)
    p.add_argument('--expect-fixed', action='store_true')
    p.add_argument('--clip', choices=['walk', 'run'], default='walk')
    p.add_argument('--allowed-clips', nargs='+', choices=['walk', 'run'])
    a = p.parse_args()
    result = audit(a.before, a.candidate, a.samples, a.clip, a.allowed_clips)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ['output'] if k in result} | {'report': str(a.output), 'old': result['old_metrics'], 'new': result['new_metrics'], 'failures': result['failures']}))
    if a.expect_fixed and result['failures']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()

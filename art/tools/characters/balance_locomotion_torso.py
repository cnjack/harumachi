#!/usr/bin/env python3
"""Restore balanced torso rotation under a rebuilt pelvis, changing Spine only.

Walk borrows the reference world orientation. Run borrows only lateral roll,
preserving the rebuilt Spine forward direction (its forward lean and heading).
Run also compensates the two Arm rotations to retain their authored world
orientation and elbow/wrist vectors relative to each shoulder. Shoulder,
ForeArm/Hand/fingers remain exact. Only the three rebuilt walks and six rebuilt
runs are eligible. Input times and unrelated channels/payload stay untouched.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import numpy as np
from scipy.spatial.transform import Rotation
from glb_io import load
from repair_head_neck import read, append, save
from motion_math import world_matrices
from rebuild_locomotion import periodic_sources, Pose


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


ELIGIBLE = {'sora': {'run'}, 'ren': {'walk', 'run'}, 'mio': {'run'},
            'aoi': {'walk', 'run'}, 'tanaka': {'walk', 'run'}, 'kazuko': {'run'}}


def forward_frame(deformation):
    forward = deformation[:, 2] / np.linalg.norm(deformation[:, 2])
    right = np.cross([0., 1., 0.], forward)
    if np.linalg.norm(right) < .1:
        raise ValueError('A near-vertical torso cannot use this lateral-only correction')
    right /= np.linalg.norm(right)
    up = np.cross(forward, right)
    frame = np.column_stack([right, up, forward])
    roll = np.arctan2(-np.dot(deformation[:, 1], right), np.dot(deformation[:, 1], up))
    return frame, roll


def balance(source, reference, output, clips=('walk',)):
    if output.exists():
        raise ValueError('Use a new immutable output path')
    d, raw = load(source)
    ref, rb = load(reference)
    original = copy.deepcopy(d)
    names = {n.get('name'): i for i, n in enumerate(d['nodes'])}
    rnames = {n.get('name'): i for i, n in enumerate(ref['nodes'])}
    who = d['nodes'][names['Rig']].get('extras', {}).get('character_id')
    if who != ref['nodes'][rnames['Rig']].get('extras', {}).get('character_id'):
        raise ValueError('Reference character differs')
    if not set(clips) or not set(clips).issubset(ELIGIBLE.get(who, set())):
        raise ValueError('Only rejected rebuilt clips are eligible; accepted walks/Haru run are protected')
    rest, parents = world_matrices(d, raw)
    rrest, rparents = world_matrices(ref, rb)
    for name in ['mixamorig:Hips', 'mixamorig:Spine']:
        if not np.allclose(rest[names[name]], rrest[rnames[name]], atol=1e-7, rtol=0):
            raise ValueError('Reference torso rest differs: ' + name)
    spine = names['mixamorig:Spine']
    b = bytearray(raw)
    expected = copy.deepcopy(original)
    clip_reports = []
    for clip in clips:
        action = next(a for a in d['animations'] if a['name'] == clip)
        reference_action = next(a for a in ref['animations'] if a['name'] == clip)
        matches = [ch for ch in action['channels'] if ch['target'] == {'node': spine, 'path': 'rotation'}]
        if len(matches) != 1:
            raise ValueError('Expected one Spine rotation channel')
        channel = matches[0]
        sampler = action['samplers'][channel['sampler']]
        if sum(ch['sampler'] == channel['sampler'] for ch in action['channels']) != 1:
            raise ValueError('Spine sampler is shared')
        if sampler.get('interpolation', 'LINEAR') != 'LINEAR':
            raise ValueError('Expected rebuilt LINEAR/Slerp Spine channel')
        times = read(d, b, sampler['input']).ravel().astype(float)
        duration = max(float(read(d, b, s['input']).max()) for s in action['samplers'])
        if not np.allclose(times / duration, np.linspace(0, 1, len(times)), atol=1e-7, rtol=0):
            raise ValueError('Expected the existing uniform rebuilt phase grid')
        reference_curves = periodic_sources(ref, rb, reference_action, len(times))
        values = []
        arm_values = {'Left': [], 'Right': []}
        for index, at in enumerate(times):
            # Preserve the already established periodic phase mapping; no
            # reference leg pose or root translation is installed.
            rp = Pose(ref, rrest, rparents, {key: v[index] for key, v in reference_curves.items()})
            desired = rp.world(rnames['mixamorig:Spine'])[:3, :3]
            current, _ = world_matrices(d, b, action, float(at))
            if clip == 'run':
                rest_basis = rest[spine][:3, :3]
                current_deformation = current[spine][:3, :3] @ np.linalg.inv(rest_basis)
                reference_deformation = desired @ np.linalg.inv(rest_basis)
                frame, _ = forward_frame(current_deformation)
                _, reference_roll = forward_frame(reference_deformation)
                desired = frame @ Rotation.from_rotvec([0., 0., reference_roll]).as_matrix() @ rest_basis
            local = np.linalg.inv(current[parents[spine]][:3, :3]) @ desired
            q = Rotation.from_matrix(local).as_quat()
            if values and np.dot(q, values[-1]) < 0:
                q = -q
            values.append(q)
            if clip == 'run':
                # Spine rotates all descendants by this same world delta.
                # Cancel it at each Arm, leaving the newly stable Shoulder
                # origins untouched and retaining the actual accepted arm
                # world basis. Correcting Shoulder instead would still move
                # the Arm root through its long local offset and retain a
                # visible up/down shoulder oscillation.
                spine_delta = desired @ np.linalg.inv(current[spine][:3, :3])
                for side in ['Left', 'Right']:
                    arm = names['mixamorig:' + side + 'Arm']
                    arm_local = np.linalg.inv(spine_delta @ current[parents[arm]][:3, :3]) @ current[arm][:3, :3]
                    arm_q = Rotation.from_matrix(arm_local).as_quat()
                    if arm_values[side] and np.dot(arm_q, arm_values[side][-1]) < 0:
                        arm_q = -arm_q
                    arm_values[side].append(arm_q)
        values = np.asarray(values, dtype='<f4')
        values[-1] = values[0]
        old_output = sampler['output']
        sampler['output'] = append(d, b, old_output, values)
        next(a for a in expected['animations'] if a['name'] == clip)['samplers'][channel['sampler']]['output'] = sampler['output']
        changed_bones = ['mixamorig:Spine']
        if clip == 'run':
            for side in ['Left', 'Right']:
                bone_name = 'mixamorig:' + side + 'Arm'
                arm_channel = next(ch for ch in action['channels'] if ch['target'] == {'node': names[bone_name], 'path': 'rotation'})
                arm_sampler = action['samplers'][arm_channel['sampler']]
                if sum(ch['sampler'] == arm_channel['sampler'] for ch in action['channels']) != 1:
                    raise ValueError('Arm sampler is shared')
                if arm_sampler.get('interpolation', 'LINEAR') != 'LINEAR' or not np.array_equal(read(d, b, arm_sampler['input']).ravel(), times):
                    raise ValueError('Arm must use the same existing LINEAR phase grid')
                arm_array = np.asarray(arm_values[side], dtype='<f4')
                arm_array[-1] = arm_array[0]
                arm_sampler['output'] = append(d, b, arm_sampler['output'], arm_array)
                next(a for a in expected['animations'] if a['name'] == clip)['samplers'][arm_channel['sampler']]['output'] = arm_sampler['output']
                changed_bones.append(bone_name)
        clip_reports.append({'clip': clip, 'mode': 'reference world orientation' if clip == 'walk' else 'reference roll only; current forward direction preserved',
                             'modified_rotation_bones': changed_bones, 'output_keys': len(times), 'duration_s': duration,
                             'endpoint_quaternion_bitwise_equal': bool(np.array_equal(values[0], values[-1]))})
    # Every other existing JSON object and every old binary byte is retained.
    expected['accessors'] = d['accessors']
    expected['bufferViews'] = d['bufferViews']
    assert d == expected and bytes(b[:len(raw)]) == raw
    output.parent.mkdir(parents=True, exist_ok=True)
    save(d, b, output)
    return {'stage': 'rebuilt-spine-balance-only', 'character': who, 'source': str(source), 'source_sha256': sha(source),
            'reference': str(reference), 'reference_sha256': sha(reference), 'output': str(output),
            'output_sha256': sha(output), 'tool_sha256': sha(__file__), 'clips': clip_reports,
            'original_input_times_and_interpolation_exact': True, 'old_bin_prefix_exact': True,
            'mesh_rest_skin_fingers_morphs_and_unselected_actions_exact': True,
            'scope': 'Authored candidate only. Native final-pose, garment proof and visual acceptance must be rerun.'}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--reference', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--report', type=Path, required=True)
    p.add_argument('--clips', nargs='+', choices=['walk', 'run'], default=['walk'])
    a = p.parse_args()
    result = balance(a.input, a.reference, a.output, a.clips)
    a.report.parent.mkdir(parents=True, exist_ok=True)
    a.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()

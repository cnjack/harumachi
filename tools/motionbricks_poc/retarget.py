#!/usr/bin/env python3
"""Retarget actual official G1 FK recordings to isolated copies of seven GLBs.

No model inference, engine, game modifier, procedural gait or source-model write.
Input schema is shared with generate.py: fps, joint_names, global_positions,
global_quaternions_xyzw, reference_global_positions,
reference_global_quaternions_xyzw and original qpos. Motion coordinates are
Y-up/Z-forward. Output clips are non-looping and preserve source frame times.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import sys

import numpy as np
from scipy.spatial.transform import Rotation

ROOT = Path(__file__).resolve().parents[2]
POC = ROOT / 'art/poc/motionbricks_20261018'
sys.path.insert(0, str(ROOT / 'art/tools/characters'))
from glb_io import load as load_glb
from motion_math import world_matrices, sample_channel
from repair_head_neck import read, append, save
from rebuild_locomotion import Pose, aim_matrix, shoe_sources, shoe_points

ACTORS = ('sora', 'ren', 'haru', 'mio', 'aoi', 'tanaka', 'kazuko')
SEMANTIC_TARGETS = ['Hips', 'Spine', 'Spine1', 'Spine2', 'Neck', 'Head'] + [
    side + suffix for side in ['Left', 'Right']
    for suffix in ['Shoulder', 'Arm', 'ForeArm', 'Hand', 'UpLeg', 'Leg', 'Foot', 'ToeBase']]
SIDES = [('Left', 'left'), ('Right', 'right')]
GROUND_Y = .005


def sha(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def json_write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n')


def safe_output(path: Path, category: str) -> Path:
    path = path.resolve()
    allowed = (POC / category).resolve()
    if path != allowed and allowed not in path.parents:
        raise ValueError(f'Output must stay inside {allowed}: {path}')
    return path


def unit(value, fallback=None):
    value = np.asarray(value, dtype=float)
    norm = float(np.linalg.norm(value))
    if norm > 1e-9:
        return value / norm
    if fallback is None:
        raise ValueError('Degenerate direction')
    return unit(fallback)


def orthogonal(value):
    u, _, vt = np.linalg.svd(value)
    result = u @ vt
    if np.linalg.det(result) < 0:
        u[:, -1] *= -1
        result = u @ vt
    return result


def smoothstep(value):
    value = float(np.clip(value, 0., 1.))
    return value * value * (3. - 2. * value)


def array(payload, name, *aliases):
    for key in [name, *aliases]:
        if key in payload:
            return np.asarray(payload[key])
    raise ValueError(f'Missing required input array {name}')


def load_motion(path: Path):
    with np.load(path, allow_pickle=False) as payload:
        data = {key: payload[key].copy() for key in payload.files}
    names = [str(name) for name in array(data, 'joint_names').tolist()]
    if len(names) != len(set(names)) or len(names) != 34:
        raise ValueError(f'Expected34 unique official skeleton joints: {path}')
    fps = float(array(data, 'fps').reshape(-1)[0])
    positions = np.asarray(array(data, 'global_positions'), dtype=float)
    quaternions = np.asarray(array(data, 'global_quaternions_xyzw'), dtype=float)
    ref_positions = np.asarray(array(data, 'reference_global_positions', 'reference_positions'), dtype=float).reshape(34, 3)
    ref_quaternions = np.asarray(array(data, 'reference_global_quaternions_xyzw', 'reference_quaternions_xyzw'), dtype=float).reshape(34, 4)
    qpos = np.asarray(array(data, 'qpos', 'mujoco_qpos'), dtype=float)
    count = len(positions)
    if not (fps > 0 and count >= 4 and positions.shape == (count, 34, 3)
            and quaternions.shape == (count, 34, 4) and qpos.shape == (count, 36)):
        raise ValueError(f'Invalid source shape/fps: {path}')
    for values in [positions, quaternions, ref_positions, ref_quaternions, qpos]:
        if not np.isfinite(values).all():
            raise ValueError(f'Non-finite official input: {path}')
    norm_error = float(max(np.abs(np.linalg.norm(quaternions, axis=-1) - 1).max(),
                           np.abs(np.linalg.norm(ref_quaternions, axis=-1) - 1).max()))
    if norm_error > .001:
        raise ValueError(f'Source quaternion norm error {norm_error}: {path}')
    required = ['pelvis_skel', 'waist_pitch_skel'] + [side + suffix
        for _, side in SIDES for suffix in ['_hip_pitch_skel', '_hip_yaw_skel', '_knee_skel',
        '_ankle_roll_skel', '_toe_base', '_shoulder_yaw_skel', '_elbow_skel', '_wrist_yaw_skel']]
    missing = sorted(set(required) - set(names))
    if missing:
        raise ValueError(f'Missing semantic source joints: {missing}')
    rotations = Rotation.from_quat(quaternions.reshape(-1, 4)).as_matrix().reshape(count, 34, 3, 3)
    ref_rotations = Rotation.from_quat(ref_quaternions).as_matrix()
    root_index = names.index('pelvis_skel')
    forward = ref_rotations[root_index] @ [0., 0., 1.]
    heading = math.atan2(forward[0], forward[2])
    alignment = Rotation.from_rotvec([0., -heading, 0.]).as_matrix()
    # Only remove the reference's fixed heading. Preserve every generated
    # frame's root/facing change and movement direction thereafter.
    positions = np.einsum('ij,tkj->tki', alignment, positions)
    rotations = np.einsum('ab,tkbc,dc->tkad', alignment, rotations, alignment)
    ref_positions = np.einsum('ij,kj->ki', alignment, ref_positions)
    ref_rotations = np.einsum('ab,kbc,dc->kad', alignment, ref_rotations, alignment)
    motion_id = re.sub(r'[^a-zA-Z0-9_]+', '_', path.stem).strip('_')
    if not motion_id:
        raise ValueError('Source file needs an ASCII motion ID')
    return dict(path=path, sha256=sha(path), names=names, ids={name: i for i, name in enumerate(names)},
                fps=fps, frames=count, positions=positions, rotations=rotations,
                ref_positions=ref_positions, ref_rotations=ref_rotations, data=data,
                motion_id=motion_id, clip='motionbricks_poc_' + motion_id,
                fixed_reference_heading_removed_rad=heading, quaternion_norm_error=norm_error)


def contacts(motion):
    count, fps = motion['frames'], motion['fps']
    if 'foot_contacts' in motion['data']:
        supplied = np.asarray(motion['data']['foot_contacts'], dtype=float)
        if supplied.shape != (count, 4) or not np.isfinite(supplied).all():
            raise ValueError('foot_contacts must be finite[T,4]:left ankle,toe,right ankle,toe')
        contact = np.stack([np.max(supplied[:, :2], axis=1) > .5,
                            np.max(supplied[:, 2:], axis=1) > .5], axis=1)
        policy = {'source': 'official supplied foot_contacts', 'channel_order': ['left ankle', 'left toe', 'right ankle', 'right toe']}
    else:
        contact = np.zeros((count, 2), dtype=bool)
        thresholds = {}
        for side_index, (_, side) in enumerate(SIDES):
            flags = []
            for suffix in ['_ankle_roll_skel', '_toe_base']:
                points = motion['positions'][:, motion['ids'][side + suffix]]
                speeds = np.linalg.norm(np.gradient(points, 1. / fps, axis=0), axis=1)
                low_y = float(np.quantile(points[:, 1], .05))
                flags.append((points[:, 1] <= low_y + .025) & (speeds <= .22))
                thresholds[side + suffix] = {'height_5th_percentile_m': low_y,
                    'maximum_height_above_low_m': .025, 'maximum_world_speed_mps': .22}
            contact[:, side_index] = flags[0] | flags[1]
        policy = {'source': 'retarget-derived kinematic low/slow FK contact; not a claim of model contact output', 'thresholds': thresholds}
    # Isolated one/two-frame contacts cannot establish a stable support anchor.
    for side_index in range(2):
        for start, end in segments(contact[:, side_index]):
            if (end - start + 1) / fps < .06:
                contact[start:end + 1, side_index] = False
    return contact, policy


def segments(mask):
    indices = np.flatnonzero(mask)
    if len(indices) == 0:
        return []
    parts = np.split(indices, np.flatnonzero(np.diff(indices) > 1) + 1)
    return [(int(part[0]), int(part[-1])) for part in parts]


class TargetPose(Pose):
    def rotation_world(self, index, wanted):
        parent = self.parents.get(index)
        parent_basis = self.world(parent)[:3, :3] if parent is not None else np.eye(3)
        local = np.linalg.solve(parent_basis, wanted)
        self.values[(index, 'rotation')] = Rotation.from_matrix(orthogonal(local)).as_quat()
        self.cache.clear()

    def origin_world(self, index, wanted):
        parent = self.parents.get(index)
        parent_world = self.world(parent) if parent is not None else np.eye(4)
        self.values[(index, 'translation')] = (np.linalg.inv(parent_world) @ np.r_[wanted, 1.])[:3]
        self.cache.clear()


def target_reference(doc, binary):
    rest, parents = world_matrices(doc, binary)
    idle = next(animation for animation in doc['animations'] if animation['name'] == 'idle')
    values = {}
    for channel in idle['channels']:
        target = channel['target']
        if target['path'] == 'rotation':
            values[(target['node'], 'rotation')] = sample_channel(doc, binary, idle, channel, 0.)
        elif target['path'] == 'translation' and doc['nodes'][target['node']].get('name') == 'mixamorig:Hips':
            values[(target['node'], 'translation')] = sample_channel(doc, binary, idle, channel, 0.)
    pose = TargetPose(doc, rest, parents, values)
    return rest, parents, values, pose.worlds(), idle


def neutral_morphs(doc, binary, idle):
    result = {}
    for index, node in enumerate(doc['nodes']):
        if 'mesh' not in node:
            continue
        mesh = doc['meshes'][node['mesh']]
        target_count = max((len(primitive.get('targets', [])) for primitive in mesh['primitives']), default=0)
        if not target_count:
            continue
        weights = np.asarray(node.get('weights', mesh.get('weights', [0.] * target_count)), dtype=float)
        for channel in idle['channels']:
            if channel['target'].get('node') != index or channel['target']['path'] != 'weights':
                continue
            sampler = idle['samplers'][channel['sampler']]
            times = read(doc, binary, sampler['input']).ravel()
            raw = read(doc, binary, sampler['output'])
            if sampler.get('interpolation', 'LINEAR') == 'CUBICSPLINE':
                weights = raw.reshape(len(times), 3, target_count)[0, 1].copy()
            else:
                weights = raw.reshape(len(times), target_count)[0].copy()
        if len(weights) != target_count or not np.isfinite(weights).all():
            raise ValueError('Invalid idle corrective weights')
        result[index] = weights
    return result


def point(worlds, ids, suffix):
    return worlds[ids['mixamorig:' + suffix]][:3, 3]


def calibrated_rotation(motion, frame, source_name, target_reference_basis):
    index = motion['ids'][source_name]
    delta = motion['rotations'][frame, index] @ motion['ref_rotations'][index].T
    return delta @ orthogonal(target_reference_basis)


def set_generated_body(pose, motion, frame, ids, reference):
    pelvis_source = motion['ids']['pelvis_skel']
    pelvis_delta = motion['rotations'][frame, pelvis_source] @ motion['ref_rotations'][pelvis_source].T
    pose.rotation_world(ids['mixamorig:Hips'], pelvis_delta @ reference[ids['mixamorig:Hips']][:3, :3])
    torso_source = motion['ids']['waist_pitch_skel']
    torso_delta = motion['rotations'][frame, torso_source] @ motion['ref_rotations'][torso_source].T
    independent_torso_delta = orthogonal(pelvis_delta.T @ torso_delta)
    spine_names = ['Spine', 'Spine1', 'Spine2']
    lengths = [np.linalg.norm(point(reference, ids, spine_names[index + 1]) - point(reference, ids, name))
               if index < 2 else np.linalg.norm(point(reference, ids, 'Neck') - point(reference, ids, name))
               for index, name in enumerate(spine_names)]
    fractions = np.cumsum(lengths) / sum(lengths)
    for name, fraction in zip(spine_names, fractions):
        index = ids['mixamorig:' + name]
        share = (Rotation.from_matrix(independent_torso_delta) ** float(fraction)).as_matrix()
        pose.rotation_world(index, pelvis_delta @ share @ reference[index][:3, :3])
    for target_side, source_side in SIDES:
        for target_suffix, source_suffix in [('UpLeg', '_hip_yaw_skel'), ('Leg', '_knee_skel'),
                ('Foot', '_ankle_roll_skel'), ('Arm', '_shoulder_yaw_skel'),
                ('ForeArm', '_elbow_skel'), ('Hand', '_wrist_yaw_skel')]:
            index = ids['mixamorig:' + target_side + target_suffix]
            pose.rotation_world(index, calibrated_rotation(motion, frame, source_side + source_suffix, reference[index][:3, :3]))
    return pelvis_delta


def solve_leg(pose, ids, side, ankle_target, pole, foot_basis, lengths):
    thigh, shin, foot = [ids['mixamorig:' + side + suffix] for suffix in ['UpLeg', 'Leg', 'Foot']]
    hip = pose.world(thigh)[:3, 3].copy()
    current_knee = pose.world(shin)[:3, 3].copy()
    current_ankle = pose.world(foot)[:3, 3].copy()
    upper, lower = lengths
    line = ankle_target - hip
    distance = float(np.linalg.norm(line))
    direction = unit(line, [0., -1., 0.])
    reach = float(np.clip(distance, abs(upper - lower) + 1e-5, upper + lower - 1e-5))
    along = (upper * upper - lower * lower + reach * reach) / (2. * reach)
    bend = math.sqrt(max(0., upper * upper - along * along))
    pole = unit(pole - direction * float(pole @ direction), [0., 0., 1.])
    knee_target = hip + direction * along + pole * bend
    pose.rotation_world(thigh, aim_matrix(pose.world(thigh)[:3, :3], current_knee - hip, knee_target - hip))
    new_knee = pose.world(shin)[:3, 3].copy()
    new_ankle = pose.world(foot)[:3, 3].copy()
    pose.rotation_world(shin, aim_matrix(pose.world(shin)[:3, :3], new_ankle - new_knee, ankle_target - new_knee))
    pose.rotation_world(foot, foot_basis)
    return max(0., distance - upper - lower), float(np.linalg.norm(pose.world(foot)[:3, 3] - ankle_target))


def contact_lock_targets(goals, contact, fps):
    locked = goals.copy()
    weights = np.zeros(contact.shape, dtype=float)
    for side_index in range(2):
        for start, end in segments(contact[:, side_index]):
            fade = max(1., min(2., (end - start) / 3.))
            anchor = goals[start, side_index, [0, 2]].copy()
            for frame in range(start, end + 1):
                weight = min(smoothstep((frame - start) / fade), smoothstep((end - frame) / fade))
                locked[frame, side_index, [0, 2]] = goals[frame, side_index, [0, 2]] * (1. - weight) + anchor * weight
                weights[frame, side_index] = weight
    return locked, weights


def leg_scales(motion, reference, ids):
    scales, lengths = {}, {}
    for target_side, source_side in SIDES:
        upper = float(np.linalg.norm(point(reference, ids, target_side + 'Leg') - point(reference, ids, target_side + 'UpLeg')))
        lower = float(np.linalg.norm(point(reference, ids, target_side + 'Foot') - point(reference, ids, target_side + 'Leg')))
        src = motion['ref_positions']
        hip, knee, ankle = [src[motion['ids'][source_side + suffix]] for suffix in ['_hip_pitch_skel', '_knee_skel', '_ankle_roll_skel']]
        source_length = float(np.linalg.norm(knee - hip) + np.linalg.norm(ankle - knee))
        if source_length < .1:
            raise ValueError('Degenerate source leg chain')
        scales[target_side] = (upper + lower) / source_length
        lengths[target_side] = (upper, lower)
    return scales, lengths


def root_reach_height(pose, ids, goals, contact, lengths, hips):
    maximum = math.inf
    for side_index, (side, _) in enumerate(SIDES):
        if not contact[side_index]:
            continue
        hip = pose.world(ids['mixamorig:' + side + 'UpLeg'])[:3, 3]
        horizontal = float(np.linalg.norm((hip - goals[side_index])[[0, 2]]))
        reach = sum(lengths[side]) - 1e-4
        vertical = math.sqrt(max(0., reach * reach - horizontal * horizontal))
        maximum = min(maximum, goals[side_index, 1] + vertical - (hip[1] - hips[1]))
    return min(float(hips[1]), maximum)


def local_joint_values(pose, joints, path):
    values = []
    for index in joints:
        node = pose.doc['nodes'][index]
        default = node.get(path, [0., 0., 0., 1.] if path == 'rotation' else [0., 0., 0.])
        values.append(pose.values.get((index, path), default))
    return np.asarray(values, dtype=float)


def supported_drift(points, contact, fps):
    values = []
    for side_index in range(2):
        for start, end in segments(contact[:, side_index]):
            if end - start < 2 or (end - start) / fps < .06:
                continue
            material = points[start:end + 1, side_index]
            values.append(float(np.linalg.norm(np.ptp(material[:, [0, 2]], axis=0))))
    return {'segments': len(values), 'maximum_m': max(values, default=None),
            'p95_m': float(np.quantile(values, .95)) if values else None,
            'scope': 'Ankle-center world drift; independent full same-shoe-material-point audit and native visuals remain required'}


def retarget_motion(doc, binary, motion, actor, contact_lock=True, ground_y=GROUND_Y):
    rest, parents, neutral_values, reference, idle = target_reference(doc, binary)
    ids = {node.get('name'): i for i, node in enumerate(doc['nodes'])}
    joints = sorted(set(index for skin in doc['skins'] for index in skin['joints']) -
                    {i for i, node in enumerate(doc['nodes']) if node.get('name', '').startswith('Cloth_')})
    if len(joints) != 54:
        raise ValueError(f'{actor}: expected original54 joints after excluding only12 cloth helpers')
    root = ids['mixamorig:Hips']; root_reference = reference[root][:3, 3]
    root_source = motion['ids']['pelvis_skel']
    scales, lengths = leg_scales(motion, reference, ids)
    root_scale = float(np.mean(list(scales.values())))
    roots = root_reference + root_scale * (motion['positions'][:, root_source] - motion['ref_positions'][root_source])
    contact, contact_policy = contacts(motion)
    goals = np.zeros((motion['frames'], 2, 3), dtype=float)
    for frame in range(motion['frames']):
        delta = motion['rotations'][frame, root_source] @ motion['ref_rotations'][root_source].T
        for side_index, (target_side, source_side) in enumerate(SIDES):
            source_foot = motion['ids'][source_side + '_ankle_roll_skel']
            source_relative = motion['positions'][frame, source_foot] - motion['positions'][frame, root_source]
            source_reference_relative = motion['ref_positions'][source_foot] - motion['ref_positions'][root_source]
            source_local_change = delta.T @ source_relative - source_reference_relative
            target_reference_relative = point(reference, ids, target_side + 'Foot') - root_reference
            goals[frame, side_index] = roots[frame] + delta @ (target_reference_relative + scales[target_side] * source_local_change)
    locked_goals, lock_weights = contact_lock_targets(goals, contact, motion['fps']) if contact_lock else (goals.copy(), np.zeros(contact.shape))
    sources = shoe_sources(doc, binary)
    rotation_tracks = np.zeros((motion['frames'], len(joints), 4), dtype=float)
    root_tracks = np.zeros((motion['frames'], 3), dtype=float)
    semantic_ids = [ids['mixamorig:' + name] for name in SEMANTIC_TARGETS]
    raw_positions, final_positions = [], []
    raw_rotations, final_rotations = [], []
    raw_ankles, final_ankles = [], []
    raw_min_sole, final_min_sole = [], []
    root_y_changes = []
    ik_errors, unreachable = [], []
    max_length_error = 0.
    local_translation_error = 0.
    previous_poles = {side: np.array([0., 0., 1.]) for side, _ in SIDES}
    for frame in range(motion['frames']):
        pose = TargetPose(doc, rest, parents, copy.deepcopy(neutral_values))
        pose.origin_world(root, roots[frame])
        delta = set_generated_body(pose, motion, frame, ids, reference)
        raw_world = pose.worlds()
        raw_shoes = shoe_points(sources, raw_world)
        raw_positions.append(np.stack([raw_world[i][:3, 3] for i in semantic_ids]))
        raw_rotations.append(np.stack([orthogonal(raw_world[i][:3, :3]) for i in semantic_ids]))
        raw_ankles.append(np.stack([point(raw_world, ids, side + 'Foot') for side, _ in SIDES]))
        raw_min_sole.append([float(raw_shoes[side][:, 1].min()) for side, _ in SIDES])
        frame_goals = locked_goals[frame].copy()
        foot_bases, poles = {}, {}
        for side, source_side in SIDES:
            foot_bases[side] = calibrated_rotation(motion, frame, source_side + '_ankle_roll_skel', reference[ids['mixamorig:' + side + 'Foot']][:3, :3])
            src = motion['positions'][frame]
            hip, knee, ankle = [src[motion['ids'][source_side + suffix]] for suffix in ['_hip_pitch_skel', '_knee_skel', '_ankle_roll_skel']]
            line = unit(ankle - hip, [0., -1., 0.])
            pole = knee - hip - line * float((knee - hip) @ line)
            if np.linalg.norm(pole) < .003:
                pole = previous_poles[side]
            pole = unit(pole, delta @ [0., 0., 1.])
            if float(pole @ previous_poles[side]) < -.5 and np.linalg.norm(knee - hip - line * float((knee - hip) @ line)) < .01:
                pole = previous_poles[side]
            poles[side] = pole
            previous_poles[side] = pole
        # Three small position/sole iterations, each using all original skin
        # influences of actual shoe vertices. This is an explicit retarget
        # correction, not a motion model output or a source garment solver.
        for iteration in range(3):
            hips = pose.world(root)[:3, 3].copy()
            hips[1] = root_reach_height(pose, ids, frame_goals, contact[frame], lengths, hips)
            pose.origin_world(root, hips)
            for side_index, (side, _) in enumerate(SIDES):
                beyond, error = solve_leg(pose, ids, side, frame_goals[side_index], poles[side], foot_bases[side], lengths[side])
                if iteration == 2:
                    unreachable.append(beyond)
                    ik_errors.append(error)
            shoes = shoe_points(sources, pose.worlds())
            if iteration < 2:
                for side_index, (side, _) in enumerate(SIDES):
                    lowest = float(shoes[side][:, 1].min())
                    if contact[frame, side_index] or lowest < ground_y:
                        frame_goals[side_index, 1] += ground_y - lowest
        final_world = pose.worlds()
        final_shoes = shoe_points(sources, final_world)
        final_positions.append(np.stack([final_world[i][:3, 3] for i in semantic_ids]))
        final_rotations.append(np.stack([orthogonal(final_world[i][:3, :3]) for i in semantic_ids]))
        final_ankles.append(np.stack([point(final_world, ids, side + 'Foot') for side, _ in SIDES]))
        final_min_sole.append([float(final_shoes[side][:, 1].min()) for side, _ in SIDES])
        root_y_changes.append(float(final_world[root][1, 3] - roots[frame, 1]))
        for side, _ in SIDES:
            for a, b, length in [('UpLeg', 'Leg', lengths[side][0]), ('Leg', 'Foot', lengths[side][1])]:
                actual = float(np.linalg.norm(point(final_world, ids, side + a) - point(final_world, ids, side + b)))
                max_length_error = max(max_length_error, abs(actual - length))
        rotation_tracks[frame] = local_joint_values(pose, joints, 'rotation')
        root_tracks[frame] = pose.values[(root, 'translation')]
        for index in joints:
            if index != root and (index, 'translation') in pose.values:
                local_translation_error = max(local_translation_error, float(np.linalg.norm(pose.values[(index, 'translation')] - doc['nodes'][index].get('translation', [0., 0., 0.]))))
    for joint_index in range(len(joints)):
        for frame in range(1, motion['frames']):
            if rotation_tracks[frame, joint_index] @ rotation_tracks[frame - 1, joint_index] < 0:
                rotation_tracks[frame, joint_index] *= -1
    arrays = dict(fps=np.asarray(motion['fps']), semantic_joint_names=np.asarray(SEMANTIC_TARGETS),
        raw_global_positions=np.asarray(raw_positions), final_global_positions=np.asarray(final_positions),
        raw_global_quaternions_xyzw=Rotation.from_matrix(np.asarray(raw_rotations).reshape(-1, 3, 3)).as_quat().reshape(motion['frames'], -1, 4),
        final_global_quaternions_xyzw=Rotation.from_matrix(np.asarray(final_rotations).reshape(-1, 3, 3)).as_quat().reshape(motion['frames'], -1, 4),
        source_contact_mask=contact, contact_lock_weights=lock_weights,
        source_scaled_ankle_goals=goals, contact_locked_ankle_goals=locked_goals,
        raw_ankles=np.asarray(raw_ankles), final_ankles=np.asarray(final_ankles),
        raw_full_skin_sole_min_y=np.asarray(raw_min_sole), final_full_skin_sole_min_y=np.asarray(final_min_sole),
        retarget_root_y_correction=np.asarray(root_y_changes), local_rotation_tracks_xyzw=rotation_tracks,
        joint_names=np.asarray([doc['nodes'][index]['name'] for index in joints]), root_local_translations=root_tracks)
    if not all(np.isfinite(value).all() for value in arrays.values() if np.issubdtype(value.dtype, np.number)):
        raise ValueError('Retarget produced non-finite tracks')
    correction_sizes = np.linalg.norm(arrays['final_global_positions'] - arrays['raw_global_positions'], axis=-1)
    report = dict(motion_id=motion['motion_id'], clip=motion['clip'], frames=motion['frames'], fps=motion['fps'],
        duration_s=(motion['frames'] - 1) / motion['fps'], looping=False,
        source_npz=str(motion['path']), source_npz_sha256=motion['sha256'],
        source_world_convention='Y-up/Z-forward,metres,quaternion xyzw; official converter FK from original qpos',
        fixed_source_reference_heading_removed_rad=motion['fixed_reference_heading_removed_rad'],
        target_neutral='Original character idle at t=0; original child translations/scales and finger local rotations',
        root_node_name='mixamorig:Hips', root_translation_track='Hips local translation; real world root motion plus explicit vertical reach correction',
        root_scale=root_scale, leg_scales=scales, leg_lengths_m={key:list(value) for key,value in lengths.items()},
        contact_policy=contact_policy, contact_lock_enabled=contact_lock,
        contact_samples={side:int(contact[:, index].sum()) for index,(side,_) in enumerate(SIDES)},
        contact_segments={side:segments(contact[:, index]) for index,(side,_) in enumerate(SIDES)},
        raw_ankle_world_drift=supported_drift(arrays['raw_ankles'], contact, motion['fps']),
        final_ankle_world_drift=supported_drift(arrays['final_ankles'], contact, motion['fps']),
        raw_full_skin_sole_min_y_m=float(np.min(raw_min_sole)), final_full_skin_sole_min_y_m=float(np.min(final_min_sole)),
        maximum_retarget_ik_position_error_m=max(ik_errors,default=0.), maximum_unreachable_target_m=max(unreachable,default=0.),
        maximum_bone_length_error_m=max_length_error, maximum_nonroot_local_translation_error_m=local_translation_error,
        maximum_root_vertical_correction_m=float(np.max(np.abs(root_y_changes))),
        maximum_raw_to_final_joint_position_correction_m=float(correction_sizes.max()),
        corrective_morphs='Frozen to original idle neutral values; original weights payload retained; no claim of new-motion cloth corrective validity',
        unsupported_source_channels='No invented finger curl, neck/head performance, human toe articulation or run mode',
        final_visual_acceptance=False)
    return joints, rotation_tracks, root_tracks, neutral_morphs(doc, binary, idle), arrays, report


def append_accessor(doc, binary, values, kind):
    values = np.asarray(values, dtype='<f4')
    if kind == 'SCALAR':
        values = values.reshape(-1, 1)
    template = next((index for index, accessor in enumerate(doc['accessors'])
                     if accessor['componentType'] == 5126 and accessor['type'] == kind), None)
    if template is None:
        raise ValueError(f'Source GLB lacks FLOAT/{kind} accessor template')
    return append(doc, binary, template, values)


def append_clip(doc, binary, motion, joints, rotations, root_translations, morphs):
    if any(animation['name'] == motion['clip'] for animation in doc['animations']):
        raise ValueError('Refuse to replace existing animation ' + motion['clip'])
    times = np.arange(motion['frames'], dtype=float) / motion['fps']
    time_accessor = append_accessor(doc, binary, times, 'SCALAR')
    animation = {'name': motion['clip'], 'samplers': [], 'channels': [], 'extras': {
        'motionbricks_poc': True, 'loop': False, 'source_recording_sha256': motion['sha256'],
        'source_frames': motion['frames'], 'fps': motion['fps'], 'derived_retarget_corrections': True}}
    def channel(index, path, values, kind):
        output = append_accessor(doc, binary, values, kind)
        animation['samplers'].append({'input': time_accessor, 'output': output, 'interpolation': 'LINEAR'})
        animation['channels'].append({'sampler': len(animation['samplers']) - 1, 'target': {'node': index, 'path': path}})
    for column, index in enumerate(joints):
        channel(index, 'rotation', rotations[:, column], 'VEC4')
    root = next(index for index, node in enumerate(doc['nodes']) if node.get('name') == 'mixamorig:Hips')
    channel(root, 'translation', root_translations, 'VEC3')
    # New clips explicitly carry neutral corrective values. Otherwise AP can
    # retain the preceding original clip's morph values on a clip switch.
    for index, weights in morphs.items():
        channel(index, 'weights', np.tile(weights, (motion['frames'], 1)).ravel(), 'SCALAR')
    doc['animations'].append(animation)


def verify_written_clips(doc, binary, reports):
    # Independent glTF accessor/Slerp evaluator checks serialized data rather
    # than reusing TargetPose or treating an in-memory plan as export proof.
    ids = {node.get('name'): index for index, node in enumerate(doc['nodes'])}
    for report in reports:
        animation = next(a for a in doc['animations'] if a['name'] == report['clip'])
        with np.load(report['audit_npz'], allow_pickle=False) as payload:
            expected_positions = payload['final_global_positions']
            expected_quaternions = payload['final_global_quaternions_xyzw']
            semantic_names = [str(name) for name in payload['semantic_joint_names']]
        samples = np.unique(np.linspace(0, report['frames'] - 1, min(13, report['frames'])).astype(int))
        max_position = max_angle = 0.
        for frame in samples:
            worlds, _ = world_matrices(doc, binary, animation, float(frame) / report['fps'])
            for column, name in enumerate(semantic_names):
                actual = worlds[ids['mixamorig:' + name]]
                max_position = max(max_position, float(np.linalg.norm(actual[:3, 3] - expected_positions[frame, column])))
                actual_rotation = Rotation.from_matrix(orthogonal(actual[:3, :3]))
                wanted_rotation = Rotation.from_quat(expected_quaternions[frame, column])
                max_angle = max(max_angle, float(np.degrees((actual_rotation.inv() * wanted_rotation).magnitude())))
        if max_position > .00005 or max_angle > .02:
            raise AssertionError(f"Written clip differs from planned actual pose:{report['clip']} {max_position}m/{max_angle}deg")
        report['written_glb_independent_accessor_roundtrip'] = {
            'sampled_actual_key_frames': samples.tolist(), 'semantic_joints': len(semantic_names),
            'maximum_position_error_m': max_position, 'maximum_rotation_error_deg': max_angle,
            'limits': {'position_m': .00005, 'rotation_deg': .02},
            'method': 'Existing motion_math.world_matrices glTF accessor/Slerp evaluator; no TargetPose reuse'}


def retarget_character(actor, motions, output_dir, contact_lock, ground_y, source_dir=None):
    source = (source_dir or ROOT / 'game/assets/models') / ('CH_' + actor + '.glb')
    before_sha = sha(source)
    doc, raw = load_glb(source)
    original = copy.deepcopy(doc)
    binary = bytearray(raw)
    output = output_dir / source.name
    if output.exists():
        raise ValueError(f'Use a fresh output directory, already exists: {output}')
    reports = []
    for motion in motions:
        joints, rotations, translations, morphs, arrays, report = retarget_motion(original, raw, motion, actor, contact_lock, ground_y)
        append_clip(doc, binary, motion, joints, rotations, translations, morphs)
        audit_path = output_dir / 'motion_audits' / (actor + '__' + motion['motion_id'] + '.npz')
        audit_path.parent.mkdir(parents=True, exist_ok=True)
        if audit_path.exists():
            raise ValueError('Refuse to replace existing audit recording')
        np.savez_compressed(audit_path, **arrays)
        report.update(audit_npz=str(audit_path), audit_npz_sha256=sha(audit_path))
        reports.append(report)
        print(json.dumps({'actor':actor,'clip':motion['clip'],'frames':motion['frames'],
                          'max_ik_error_m':report['maximum_retarget_ik_position_error_m'],
                          'min_sole_y_m':report['final_full_skin_sole_min_y_m']}, ensure_ascii=False), flush=True)
    for key in ['meshes', 'skins', 'nodes', 'images', 'textures', 'materials', 'scenes', 'scene']:
        if doc.get(key) != original.get(key):
            raise AssertionError('Source payload changed: ' + key)
    if doc['animations'][:len(original['animations'])] != original['animations'] or bytes(binary[:len(raw)]) != raw:
        raise AssertionError('Source animation or original embedded payload changed')
    save(doc, binary, output)
    loaded, loaded_binary = load_glb(output)
    if loaded['nodes'] != original['nodes'] or loaded['skins'] != original['skins'] or loaded_binary[:len(raw)] != raw:
        raise AssertionError('Written GLB payload round-trip mismatch')
    verify_written_clips(loaded, loaded_binary, reports)
    if sha(source) != before_sha:
        raise AssertionError('Production input changed')
    return {'character':actor,'source_glb':str(source),'source_sha256':before_sha,
            'output_glb':str(output),'output_sha256':sha(output),'original_payload_binary_prefix_exact':True,
            'original_nodes_rest_skin_mesh_morphs_textures_materials_json_exact':True,
            'all_original_animations_json_exact':True,'clips':reports}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--motions-dir', '--motion-dir', type=Path, default=POC/'motions')
    parser.add_argument('--output-dir', type=Path, default=POC/'retargeted')
    parser.add_argument('--source-dir', type=Path, default=ROOT/'game/assets/models')
    parser.add_argument('--characters', nargs='+', choices=ACTORS, default=list(ACTORS))
    parser.add_argument('--motions', nargs='+', help='Explicit npz stems; default all complete source npz files')
    parser.add_argument('--no-contact-lock', action='store_true', help='Explicit contact-lock ablation; still reports generated vs IK corrections')
    parser.add_argument('--ground-y', type=float, default=GROUND_Y)
    args = parser.parse_args()
    output_dir = safe_output(args.output_dir, 'retargeted')
    input_dir = args.motions_dir.resolve()
    safe_output(input_dir, 'motions')
    if (output_dir/'manifest.json').exists():
        parser.error('Use a fresh immutable output directory; manifest already exists')
    paths = [input_dir/(name+'.npz') for name in args.motions] if args.motions else sorted(input_dir.glob('*.npz'))
    if not paths:
        parser.error('No actual official source motion recordings found')
    motions = [load_motion(path) for path in paths]
    if len({motion['motion_id'] for motion in motions}) != len(motions):
        parser.error('Motion IDs collide after sanitizing')
    # A shared genuine initialized-idle reference is required. Never calibrate
    # separately against a crouched/style first frame and silently erase style.
    if any(not np.allclose(motion['ref_positions'], motions[0]['ref_positions'], atol=1e-6) or
           not np.allclose(motion['ref_rotations'], motions[0]['ref_rotations'], atol=1e-6) for motion in motions[1:]):
        parser.error('All recordings must share one initialized official idle reference')
    source_hashes_before = {actor:sha(ROOT/'game/assets/models'/('CH_'+actor+'.glb')) for actor in ACTORS}
    output_dir.mkdir(parents=True, exist_ok=True)
    reports = [retarget_character(actor, motions, output_dir, not args.no_contact_lock, args.ground_y, args.source_dir.resolve()) for actor in args.characters]
    source_hashes_after = {actor:sha(ROOT/'game/assets/models'/('CH_'+actor+'.glb')) for actor in ACTORS}
    if source_hashes_before != source_hashes_after:
        raise AssertionError('Production seven-model source identity changed')
    json_write(output_dir/'manifest.json',{'kind':'MotionBricks actual G1 FK → isolated character-copy retarget POC',
        'tool_sha256':sha(Path(__file__)),'source_model_hashes_before':source_hashes_before,
        'source_model_hashes_after':source_hashes_after,'production_models_unchanged':True,
        'coordinate_convention':'Y-up,Z-forward,metres,quaternion xyzw',
        'clip_convention':'One GLB per character; appended motionbricks_poc_<source_npz_stem>; all new clips non-looping',
        'corrections_scope':'Neutral idle calibration, complete source FK chain orientation, target-specific limb scale, reach/foot IK and explicit contact locking; no procedural gait replacement or game modifiers',
        'not_claimed':['Visual acceptance','Human toe/head/finger motion absent from G1','Native cloth corrective validity','A run mode not present in the public G1 clip set'],
        'characters':reports})
    print(output_dir/'manifest.json')


if __name__ == '__main__':
    main()

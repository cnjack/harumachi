"""Author the requested cross-chest front arm and outward rear arm in source GLB.

Only six run rotation tracks change. Upper-arm 15 degrees describes the frontal
adduction towards the chest; the forward lift is solved separately so the elbow
can stay near90 degrees while the forearm rises30-45 degrees above horizontal.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import math
import numpy as np
from scipy.optimize import brentq
from scipy.spatial.transform import Rotation
from glb_io import load
from motion_math import world_matrices, sample_channel, palm_normal
from repair_head_neck import read, save
from rebuild_locomotion import Pose, aim_matrix, append_values

ACTORS = ['sora', 'ren', 'haru', 'mio', 'aoi', 'tanaka', 'kazuko']


def unit(v):
    return v / np.linalg.norm(v)


def blend_direction(a, b, amount):
    angle = math.acos(float(np.clip(a @ b, -1, 1)))
    if angle < 1e-7:
        return unit(a + (b - a) * amount)
    return (a * math.sin((1 - amount) * angle) + b * math.sin(amount * angle)) / math.sin(angle)


def author(source, output, actor, report_path):
    doc, raw = load(source)
    original = copy.deepcopy(doc)
    blob = bytearray(raw)
    rest, parents = world_matrices(doc, raw)
    ids = {n.get('name'): i for i, n in enumerate(doc['nodes'])}
    run = next(a for a in original['animations'] if a['name'] == 'run')
    target = next(a for a in doc['animations'] if a['name'] == 'run')
    extras = next(n for n in doc['nodes'] if n.get('name') == 'Rig')['extras']
    previous = extras['source_running_style']
    if previous.get('pose_revision') != 2:
        raise ValueError('Use the explicit revision2 source as the baseline')
    duration = max(float(read(doc, raw, s['input']).max()) for s in run['samplers'])
    times = read(doc, raw, next(s for c in run['channels'] for s in [run['samplers'][c['sampler']]] if c['target'] == {'node': ids['mixamorig:LeftArm'], 'path': 'rotation'})['input']).ravel()
    bounds = {s: [] for s in ['Left', 'Right']}
    for at in np.linspace(0, duration, 241):
        worlds, _ = world_matrices(original, raw, run, float(at))
        for side in bounds:
            delta = worlds[ids['mixamorig:' + side + 'ForeArm']][:3, 3] - worlds[ids['mixamorig:' + side + 'Arm']][:3, 3]
            bounds[side].append(float(np.arctan2(delta[2], -delta[1])))
    bounds = {s: (min(v), max(v)) for s, v in bounds.items()}
    selected = [ids['mixamorig:' + side + suffix] for side in bounds for suffix in ['Arm', 'ForeArm', 'Hand']]
    tracks = {i: [] for i in selected}
    measured = []
    for at in times:
        values = {(c['target']['node'], c['target']['path']): sample_channel(original, raw, run, c, float(at)) for c in run['channels'] if c['target']['path'] != 'weights'}
        pose = Pose(original, rest, parents, values)
        hip = pose.world(ids['mixamorig:Hips'])[:3, 3]
        chest = pose.world(ids['mixamorig:Spine2'])[:3, 3]
        neck = pose.world(ids['mixamorig:Neck'])[:3, 3]
        across = pose.world(ids['mixamorig:LeftArm'])[:3, 3] - pose.world(ids['mixamorig:RightArm'])[:3, 3]
        up = unit(neck - hip)
        right = unit(across - up * (across @ up))
        forward = unit(np.cross(right, up))
        torso = np.column_stack([right, up, forward])
        horizontal_right = unit(np.array([right[0], 0., right[2]]))
        horizontal_forward = unit(np.cross(horizontal_right, [0., 1., 0.]))
        for side in bounds:
            sign = 1. if side == 'Left' else -1.
            arm, fore, hand = [ids['mixamorig:' + side + suffix] for suffix in ['Arm', 'ForeArm', 'Hand']]
            shoulder = pose.world(arm)[:3, 3].copy()
            elbow = pose.world(fore)[:3, 3].copy()
            old_upper = elbow - shoulder
            pitch = float(np.arctan2(old_upper[2], -old_upper[1]))
            lo, hi = bounds[side]
            phase = float(np.clip((pitch - lo) / (hi - lo), 0, 1))
            # The forward elbow moves gently inward. The forearm then crosses
            # towards the opposite upper chest instead of pointing straight out.
            elevation = math.radians(33.)
            inward_yaw = math.radians(50.)
            front_fore = unit(-sign * horizontal_right * math.cos(elevation) * math.sin(inward_yaw) + np.array([0., math.sin(elevation), 0.]) + horizontal_forward * math.cos(elevation) * math.cos(inward_yaw))
            def upper_direction(angle):
                return unit(torso @ np.array([-sign * math.tan(math.radians(15.)), -1., math.tan(angle)]))
            front_pitch = brentq(lambda angle: upper_direction(angle) @ front_fore - math.cos(math.radians(92.)), math.radians(-75), math.radians(75))
            front_upper = upper_direction(front_pitch)
            back_upper = unit(torso @ np.array([sign * math.tan(math.radians(22.)), -1., -math.tan(math.radians(48.))]))
            rear_preferred = unit(torso @ np.array([sign * .28, -.80, .48]))
            rear_perp = unit(rear_preferred - back_upper * (rear_preferred @ back_upper))
            back_fore = unit(back_upper * math.cos(math.radians(86.)) + rear_perp * math.sin(math.radians(86.)))
            upper_dir = unit(blend_direction(back_upper, front_upper, phase))
            preferred = unit(blend_direction(back_fore, front_fore, phase))
            perpendicular = unit(preferred - upper_dir * (preferred @ upper_dir))
            flex = math.radians(86. + 6. * phase)
            fore_dir = unit(upper_dir * math.cos(flex) + perpendicular * math.sin(flex))
            pose.set_global(arm, basis=aim_matrix(pose.world(arm)[:3, :3], old_upper, upper_dir))
            elbow = pose.world(fore)[:3, 3].copy()
            wrist = pose.world(hand)[:3, 3].copy()
            pose.set_global(fore, basis=aim_matrix(pose.world(fore)[:3, :3], wrist - elbow, fore_dir))
            wrist = pose.world(hand)[:3, 3].copy()
            mcp = np.mean([pose.world(ids['mixamorig:' + side + 'Hand' + f + '1'])[:3, 3] for f in ['Index', 'Middle', 'Ring', 'Pinky']], axis=0)
            inward = unit(chest - wrist - fore_dir * ((chest - wrist) @ fore_dir))
            hand_dir = fore_dir * math.cos(math.radians(5)) + inward * math.sin(math.radians(5))
            pose.set_global(hand, basis=aim_matrix(pose.world(hand)[:3, :3], mcp - wrist, hand_dir))
            normal = palm_normal(original, rest, pose.worlds(), side)
            normal = unit(normal - fore_dir * (normal @ fore_dir))
            roll = float(np.clip(np.arctan2(np.cross(normal, inward) @ fore_dir, normal @ inward), -math.pi / 4, math.pi / 4))
            pose.set_global(hand, basis=Rotation.from_rotvec(fore_dir * roll).as_matrix() @ pose.world(hand)[:3, :3])
            mcp = np.mean([pose.world(ids['mixamorig:' + side + 'Hand' + f + '1'])[:3, 3] for f in ['Index', 'Middle', 'Ring', 'Pinky']], axis=0)
            measured.append({'side': side, 'time': float(at), 'frontness': phase, 'forearm_elevation_deg': math.degrees(math.asin(float(fore_dir[1]))), 'elbow_flex_deg': math.degrees(flex), 'upper_pitch_world_deg': math.degrees(math.atan2(float(upper_dir[2]), -float(upper_dir[1]))), 'upper_front_lateral_deg': math.degrees(math.atan2(float((torso.T @ upper_dir)[0]) * sign, -float((torso.T @ upper_dir)[1]))), 'fist_relative_chest': (torso.T @ (mcp - chest)).tolist()})
        for index in tracks:
            tracks[index].append(pose.values[(index, 'rotation')])
    time_accessor = append_values(doc, blob, times[:, None], 'SCALAR')
    for index, rows in tracks.items():
        rows = np.asarray(rows)
        rows[-1] = rows[0]
        for k in range(1, len(rows)):
            if rows[k] @ rows[k - 1] < 0: rows[k] *= -1
        sampler = {'input': time_accessor, 'output': append_values(doc, blob, rows.astype(np.float32), 'VEC4'), 'interpolation': 'LINEAR'}
        channel = next(c for c in target['channels'] if c['target'] == {'node': index, 'path': 'rotation'})
        target['samplers'][channel['sampler']] = sampler
    extras['source_running_style'] = {**previous, 'pose_revision': 3, 'profile': 'cross_chest_front_outward_rear', 'source_sha256': hashlib.sha256(Path(source).read_bytes()).hexdigest(), 'front_forearm_horizontal_elevation_deg': 33, 'front_upper_frontal_adduction_deg': 15, 'elbow_art_range_deg': [86, 92], 'rear_upper_outward_deg': 22, 'finger_tracks_preserved': True}
    extras['source_running_style']['upper_pitch_art_range_deg'] = [min(r['upper_pitch_world_deg'] for r in measured), max(r['upper_pitch_world_deg'] for r in measured)]
    extras['source_running_style'].pop('additional_outward_clearance_deg', None)
    for key in ['meshes', 'skins', 'materials', 'images', 'textures']:
        assert doc.get(key) == original.get(key)
    for a, b in zip(original['animations'], doc['animations']):
        if a['name'] != 'run': assert a == b
        else:
            for channel in a['channels']:
                if channel['target']['node'] in tracks and channel['target']['path'] == 'rotation': continue
                assert a['samplers'][channel['sampler']] == b['samplers'][channel['sampler']]
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    save(doc, blob, output)
    report = {'actor': actor, 'input_sha256': hashlib.sha256(Path(source).read_bytes()).hexdigest(), 'output_sha256': hashlib.sha256(output.read_bytes()).hexdigest(), 'changed_tracks': 6, 'original_mesh_skin_fingers_legs_and_cloth_exact': True, 'samples': measured, 'front_peak': {side: max((r for r in measured if r['side'] == side), key=lambda r: r['frontness']) for side in bounds}}
    Path(report_path).parent.mkdir(parents=True, exist_ok=True)
    Path(report_path).write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['input', 'output', 'report']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--character', choices=ACTORS, required=True)
    args = parser.parse_args()
    author(args.input, args.output, args.character, args.report)

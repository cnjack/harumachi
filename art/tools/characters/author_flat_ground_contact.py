"""Author flat-ground sole clearance in source leg tracks, preserving knee planes.

Complete skinned shoe vertices determine each correction. Only thigh/shin/foot
rotations change; the current knee plane, ankle XZ, foot world orientation,
hips/torso/arms, skin, geometry, morphs and clip durations are protected.
Terrain and transitions remain runtime responsibilities.
"""
from pathlib import Path
import argparse, copy, hashlib, json, math
import numpy as np
from glb_io import load, durations
from motion_math import world_matrices, sample_channel
from rebuild_locomotion import Pose, aim_matrix, append_values, shoe_sources, shoe_points
from repair_head_neck import read, save


def lift(pose, ids, side, rise):
    thigh, shin, foot = [ids['mixamorig:'+side+part] for part in ['UpLeg', 'Leg', 'Foot']]
    hip, knee, ankle = [pose.world(index)[:3, 3].copy() for index in [thigh, shin, foot]]
    foot_basis = pose.world(foot)[:3, :3].copy()
    upper, lower = np.linalg.norm(knee-hip), np.linalg.norm(ankle-knee)
    target = ankle + [0., min(rise, .22), 0.]
    direction = (target-hip) / np.linalg.norm(target-hip)
    reach = np.clip(np.linalg.norm(target-hip), abs(upper-lower)+1e-7, upper+lower-1e-7)
    along = (upper*upper-lower*lower+reach*reach) / (2*reach)
    bend = np.sqrt(max(0., upper*upper-along*along))
    pole = knee-hip
    pole -= direction * (pole @ direction)
    if np.linalg.norm(pole) < 1e-8:
        pole = np.array([0., 0., 1.])
        pole -= direction * (pole @ direction)
    wanted = hip + direction*along + pole/np.linalg.norm(pole)*bend
    pose.set_global(thigh, basis=aim_matrix(pose.world(thigh)[:3, :3], knee-hip, wanted-hip))
    new_knee, new_ankle = pose.world(shin)[:3, 3], pose.world(foot)[:3, 3]
    pose.set_global(shin, basis=aim_matrix(pose.world(shin)[:3, :3], new_ankle-new_knee, target-new_knee))
    pose.set_global(foot, basis=foot_basis)
    return float(np.linalg.norm(pose.world(foot)[:3, 3]-target))


def author(source, output, clips, report_path):
    original, raw = load(source)
    doc, blob = copy.deepcopy(original), bytearray(raw)
    rest, parents = world_matrices(original, raw)
    ids = {node.get('name'): i for i, node in enumerate(doc['nodes'])}
    shoes = shoe_sources(original, raw)
    lengths = durations(source)
    tracks_to_write = [ids['mixamorig:'+side+part] for side in ['Left', 'Right'] for part in ['UpLeg', 'Leg', 'Foot']]
    reports = []
    for clip in clips:
        source_animation = next(a for a in original['animations'] if a['name'] == clip)
        animation = next(a for a in doc['animations'] if a['name'] == clip)
        count = max(2, math.ceil(lengths[clip]*240))
        times = np.unique(np.r_[np.linspace(0, lengths[clip], count+1),
                               *[read(original, raw, sampler['input']).ravel() for sampler in source_animation['samplers']]].astype(np.float32))
        curves = {index: [] for index in tracks_to_write}
        minimum_before, minimum_after, maximum_ankle_error, maximum_rise = 1., 1., 0., 0.
        for time in times:
            values = {(c['target']['node'], c['target']['path']): sample_channel(original, raw, source_animation, c, float(time))
                      for c in source_animation['channels'] if c['target']['path'] != 'weights'}
            pose = Pose(original, rest, parents, values)
            before = shoe_points(shoes, pose.worlds())
            minimum_before = min(minimum_before, min(float(p[:, 1].min()) for p in before.values()))
            for iteration in range(5):
                changed = False
                for side in ['Left', 'Right']:
                    points = shoe_points(shoes, pose.worlds())[side]
                    rise = max(0., .008-float(points[:, 1].min()))
                    maximum_rise = max(maximum_rise, rise)
                    if rise < .00001:
                        continue
                    maximum_ankle_error = max(maximum_ankle_error, lift(pose, ids, side, rise))
                    changed = True
                if not changed:
                    break
            current = shoe_points(shoes, pose.worlds())
            minimum_after = min(minimum_after, min(float(p[:, 1].min()) for p in current.values()))
            for index in curves:
                curves[index].append(pose.values.get((index, 'rotation'), original['nodes'][index].get('rotation', [0, 0, 0, 1])))
        if minimum_after < .006:
            raise ValueError(f'Full-source shoes still below authored clearance: {clip} {minimum_after}')
        time_id = append_values(doc, blob, times[:, None], 'SCALAR')
        for index, values in curves.items():
            data = np.asarray(values)
            data[-1] = data[0]
            for k in range(1, len(data)):
                if data[k] @ data[k-1] < 0:
                    data[k] *= -1
            sampler = {'input': time_id, 'output': append_values(doc, blob, data.astype(np.float32), 'VEC4'), 'interpolation': 'LINEAR'}
            channel = next(c for c in animation['channels'] if c['target'] == {'node': index, 'path': 'rotation'})
            animation['samplers'][channel['sampler']] = sampler
        reports.append({'clip': clip, 'samples': len(times), 'minimum_sole_before_m': minimum_before,
                        'minimum_sole_after_at_keys_m': minimum_after, 'maximum_single_ankle_rise_m': maximum_rise,
                        'maximum_ankle_target_error_m': maximum_ankle_error})
    verified = {}
    for clip in ['walk', 'run']:
        animation = next(a for a in doc['animations'] if a['name'] == clip)
        lowest = min(min(float(p[:, 1].min()) for p in shoe_points(shoes, world_matrices(doc, blob, animation, float(time))[0]).values())
                     for time in np.linspace(0., lengths[clip], 129))
        if lowest < .006:
            raise ValueError(f'Output flat-floor validation failed: {clip} {lowest}')
        verified[clip] = lowest
    rig = next(n for n in doc['nodes'] if n.get('name') == 'Rig')
    rig.setdefault('extras', {})['source_flat_floor_contact'] = {
        'version': 1, 'authored_clips': list(clips), 'clearance_m': .008,
        'verified_flat_clips': list(verified),
        'knee_plane_preserved': True, 'terrain_baked': False,
        'source_sha256': hashlib.sha256(Path(source).read_bytes()).hexdigest()}
    save(doc, blob, Path(output))
    result = {'source_sha256': hashlib.sha256(Path(source).read_bytes()).hexdigest(),
              'output_sha256': hashlib.sha256(Path(output).read_bytes()).hexdigest(), 'clips': reports,
              'mesh_skin_rest_morphs_unchanged': all(doc.get(key) == original.get(key) for key in ['meshes', 'skins', 'materials', 'textures', 'images']),
              'changed_rotation_bones': [doc['nodes'][i]['name'] for i in tracks_to_write],
              'post_write_129_phase_full_shoe_minima_m': verified}
    Path(report_path).write_text(json.dumps(result, indent=2)+'\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ['source', 'output', 'report']:
        parser.add_argument('--'+key, type=Path, required=True)
    parser.add_argument('--clips', default='walk,run')
    args = parser.parse_args()
    print(author(args.source, args.output, args.clips.split(','), args.report))

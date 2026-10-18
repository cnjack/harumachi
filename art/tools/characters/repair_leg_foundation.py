"""Repair a model's leg deformation and authored walk before runtime assistance.

Ren: correct hip-dominant trouser weights using the actual leg joint heights.
Sora: author the walking knee plane in the GLB, preserving ankle trajectories.
This does not install assets or import MotionBricks actions into the game.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json

import numpy as np
from scipy.spatial.transform import Rotation
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

from glb_io import load
from motion_math import sample_channel, world_matrices
from prepare_local_garments import colours, select_cloth
from rebuild_locomotion import Pose, aim_matrix, append_values
from repair_head_neck import append, read, save
from repair_joint_fit import parts


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def smooth(lo, hi, value):
    t = np.clip((value - lo) / (hi - lo), 0., 1.)
    return t * t * (3. - 2. * t)


def repair_trousers(doc, blob):
    """Change warm trouser material, never the white apron or hands.

    The original single-mesh character has no material-slot separation. Pigment,
    anatomical bounds and existing non-leg influences jointly define this region.
    Repeated UV vertices get the same geometric field. Original foot/toe weights
    and all vertices outside the selected trouser region remain exact.
    """
    rest, _ = world_matrices(doc, blob)
    names = {node.get('name'): index for index, node in enumerate(doc['nodes'])}
    reports = []
    for part in parts(doc, blob, rest):
        xyz = part['xyz']
        rgb = colours(doc, blob, part['primitive'])
        red, green, blue = rgb.T
        # Include desaturated trouser texels as well as the core khaki. The
        # stricter audit's barycentric UV witnesses exposed pale pant corners
        # which otherwise remained stuck to Hips inside an updated triangle.
        warm = (red > green * 1.02) & (green > blue * 1.06) & (red-blue > .065)
        joints = part['joints']
        family_names = ['Hips'] + [side + suffix for side in ['Left', 'Right']
                                    for suffix in ['UpLeg', 'Leg']]
        family = [joints.index(names['mixamorig:' + key]) for key in family_names]
        old = part['dense']
        mass = old[:, family].sum(axis=1)
        hip_height = np.mean([rest[names['mixamorig:' + side + 'UpLeg']][1, 3]
                              for side in ['Left', 'Right']])
        knee_height = np.mean([rest[names['mixamorig:' + side + 'Leg']][1, 3]
                               for side in ['Left', 'Right']])
        selected = (warm & (np.abs(xyz[:, 0]) < .28) & (xyz[:, 1] > knee_height - .17)
                    & (xyz[:, 1] < hip_height) & (mass > .995))
        if not selected.any():
            continue
        dense = old.copy()
        desired = np.zeros((len(xyz), len(family)))
        # Midline blending is restricted to the anatomical crotch. Separate
        # trouser legs below it cannot be dragged by the opposite thigh.
        midline_width = .012 + .028 * smooth(knee_height + .17, hip_height, xyz[:, 1])
        left_share = smooth(-midline_width, midline_width, xyz[:, 0])
        for side, side_share, thigh_column, shin_column in [
                ('Left', left_share, 1, 2), ('Right', 1. - left_share, 3, 4)]:
            hip = rest[names['mixamorig:' + side + 'UpLeg']][:3, 3]
            knee = rest[names['mixamorig:' + side + 'Leg']][:3, 3]
            ankle = rest[names['mixamorig:' + side + 'Foot']][:3, 3]
            length = np.linalg.norm(knee - hip)
            knee_half_width = .20 * min(length, np.linalg.norm(ankle - knee))
            thigh = smooth(knee[1] - knee_half_width, knee[1] + knee_half_width, xyz[:, 1])
            pelvis = smooth(hip[1] - .28 * length, hip[1], xyz[:, 1])
            desired[:, 0] += side_share * pelvis
            desired[:, thigh_column] = side_share * (1. - pelvis) * thigh
            desired[:, shin_column] = side_share * (1. - pelvis) * (1. - thigh)
        # Preserve the source at the lower boundary, where no faulty pelvis
        # dominance was found. This also preserves ankle/foot interpolation.
        influence = smooth(knee_height - .17, knee_height - .09, xyz[:, 1])
        target = desired * mass[:, None]
        dense[np.ix_(selected, family)] = (old[np.ix_(selected, family)]
            * (1. - influence[selected, None]) + target[selected] * influence[selected, None])
        ids = part['ids'].copy()
        weights = part['weights'].copy()
        capacity = ids.shape[1]
        # A selected vertex can have at most the five leg/pelvis influences;
        # retain any tiny original non-family influence without truncation.
        nonzero = np.count_nonzero(dense[selected] > 1e-9, axis=1)
        if nonzero.max() > capacity:
            raise ValueError('Leg weights exceed the existing influence capacity')
        order = np.argsort(dense[selected], axis=1)[:, -capacity:][:, ::-1]
        values = np.take_along_axis(dense[selected], order, axis=1)
        values /= values.sum(axis=1, keepdims=True)
        ids[selected] = order
        weights[selected] = values
        attrs = part['primitive']['attributes']
        for group in range(capacity // 4):
            attrs['JOINTS_' + str(group)] = append(doc, blob, attrs['JOINTS_' + str(group)], ids[:, group*4:group*4+4])
            attrs['WEIGHTS_' + str(group)] = append(doc, blob, attrs['WEIGHTS_' + str(group)], weights[:, group*4:group*4+4])
        assert np.array_equal(ids[~selected], part['ids'][~selected])
        assert np.array_equal(weights[~selected], part['weights'][~selected])
        reports.append({'mesh': part['name'], 'selected_vertices': int(selected.sum()),
                        'knee_height_m': float(knee_height), 'hip_height_m': float(hip_height),
                        'original_nontrouser_and_ankle_weights_exact': True,
                        'selected_vertex_ids': np.flatnonzero(selected).tolist()})
    if not reports:
        raise ValueError('No Ren trouser region was identified')
    return reports


def author_walk_knees(doc, blob):
    original = copy.deepcopy(doc)
    raw = bytes(blob)
    rest, parents = world_matrices(original, raw)
    ids = {node.get('name'): index for index, node in enumerate(doc['nodes'])}
    source = next(a for a in original['animations'] if a['name'] == 'walk')
    target = next(a for a in doc['animations'] if a['name'] == 'walk')
    duration = max(float(read(original, raw, sampler['input']).max()) for sampler in source['samplers'])
    # glTF stores float32 timestamps. Deduplicate after conversion so nearly
    # coincident source and regular samples never serialize as repeated keys.
    times = np.unique(np.r_[np.linspace(0., duration, int(np.ceil(duration * 120)) + 1),
                           *[read(original, raw, s['input']).ravel() for s in source['samplers']]].astype(np.float32))
    watched = [ids['mixamorig:' + side + suffix] for side in ['Left', 'Right']
               for suffix in ['UpLeg', 'Leg', 'Foot']]
    tracks = {node: [] for node in watched}
    max_ankle_error = 0.
    for time in times:
        values = {(channel['target']['node'], channel['target']['path']):
                  sample_channel(original, raw, source, channel, time)
                  for channel in source['channels'] if channel['target']['path'] != 'weights'}
        pose = Pose(original, rest, parents, values)
        for side, sign in [('Left', 1.), ('Right', -1.)]:
            thigh, shin, foot = [ids['mixamorig:' + side + suffix] for suffix in ['UpLeg', 'Leg', 'Foot']]
            hip, knee, ankle = [pose.world(node)[:3, 3].copy() for node in [thigh, shin, foot]]
            basis = pose.world(foot)[:3, :3].copy()
            upper, lower = np.linalg.norm(knee - hip), np.linalg.norm(ankle - knee)
            direction = (ankle - hip) / np.linalg.norm(ankle - hip)
            reach = np.clip(np.linalg.norm(ankle - hip), abs(upper - lower) + 1e-7, upper + lower - 1e-7)
            along = (upper*upper - lower*lower + reach*reach) / (2. * reach)
            bend = np.sqrt(max(0., upper*upper - along*along))
            pole = np.array([.08 * sign, 0., 1.])
            pole -= direction * np.dot(pole, direction)
            pole /= np.linalg.norm(pole)
            wanted_knee = hip + direction * along + pole * bend
            pose.set_global(thigh, basis=aim_matrix(pose.world(thigh)[:3, :3], knee - hip, wanted_knee - hip))
            new_knee, new_ankle = pose.world(shin)[:3, 3].copy(), pose.world(foot)[:3, 3].copy()
            pose.set_global(shin, basis=aim_matrix(pose.world(shin)[:3, :3], new_ankle - new_knee, ankle - new_knee))
            pose.set_global(foot, basis=basis)
            max_ankle_error = max(max_ankle_error, float(np.linalg.norm(pose.world(foot)[:3, 3] - ankle)))
        for node in watched:
            tracks[node].append(pose.values[(node, 'rotation')])
    for node, values in tracks.items():
        values = np.asarray(values)
        for index in range(1, len(values)):
            if values[index] @ values[index - 1] < 0:
                values[index] *= -1
        channel = next(c for c in target['channels'] if c['target'] == {'node': node, 'path': 'rotation'})
        target['samplers'][channel['sampler']] = {
            'input': append_values(doc, blob, times.reshape(-1, 1), 'SCALAR'),
            'output': append_values(doc, blob, values, 'VEC4'), 'interpolation': 'LINEAR'}
    return {'clip': 'walk', 'rotation_tracks': [doc['nodes'][node]['name'] for node in watched],
            'samples': len(times), 'duration_s': duration, 'maximum_ankle_position_error_m': max_ankle_error,
            'all_other_animation_channels_unchanged': True, 'runtime_knee_plane_required': False}


def repair_apron_weights(doc, blob):
    """Transfer lower panels to the leg field while keeping the waist attached."""
    rest, _ = world_matrices(doc, blob)
    names = {node.get('name'): index for index, node in enumerate(doc['nodes'])}
    rows = []
    for part in parts(doc, blob, rest):
        xyz = part['xyz']
        rgb = colours(doc, blob, part['primitive'])
        normals = read(doc, blob, part['primitive']['attributes']['NORMAL'])
        height = float(xyz[:, 1].max())
        split = float(rest[names['mixamorig:Hips']][2, 3])
        masks, edges = select_cloth(xyz, normals, rgb, part['faces'], 'ren', height, split)
        coverage = np.maximum(masks[0], masks[1])
        family_names = ['Hips'] + [side + suffix for side in ['Left', 'Right'] for suffix in ['UpLeg', 'Leg']]
        family = [part['joints'].index(names['mixamorig:' + name]) for name in family_names]
        mass = part['dense'][:, family].sum(axis=1)
        red, green, blue = rgb.T
        khaki = (red > green*1.02) & (green > blue*1.06) & (red-blue > .065)
        eligible = ((rgb.min(1) > .36) & (np.ptp(rgb,axis=1) < .10) & ~khaki
                    & (np.abs(xyz[:,0]) < .24*height) & (xyz[:,1] > .20*height)
                    & (xyz[:,1] < .59*height) & (mass > .995))
        # The corrective-shape mask intentionally fades near the side opening.
        # Skin weights must cover the actual connected white panel there too:
        # a faded 99%-Hips rear edge otherwise stays behind its moving trousers.
        copies = cKDTree(xyz).query_pairs(1e-6,output_type='ndarray')
        edges = np.r_[edges,copies]
        edges = edges[np.all(eligible[edges],axis=1)]
        graph = coo_matrix((np.ones(len(edges)),(edges[:,0],edges[:,1])),shape=(len(xyz),len(xyz))).tocsr()
        _, labels = connected_components(graph,directed=False)
        selected = eligible & np.isin(labels,np.unique(labels[(coverage > 0.) & eligible]))
        if not selected.any():
            continue
        desired = np.zeros((len(xyz), len(family)))
        left = smooth(-.07, .07, xyz[:, 0])
        for side, side_share, thigh_column, shin_column in [('Left', left, 1, 2), ('Right', 1.-left, 3, 4)]:
            hip = rest[names['mixamorig:' + side + 'UpLeg']][:3, 3]
            knee = rest[names['mixamorig:' + side + 'Leg']][:3, 3]
            ankle = rest[names['mixamorig:' + side + 'Foot']][:3, 3]
            half = .20 * min(np.linalg.norm(hip-knee), np.linalg.norm(knee-ankle))
            thigh = smooth(knee[1]-half, knee[1]+half, xyz[:, 1])
            pelvis = smooth(hip[1]-.14, hip[1]+.06, xyz[:, 1])
            desired[:, 0] += side_share * pelvis
            desired[:, thigh_column] = side_share * (1.-pelvis) * thigh
            desired[:, shin_column] = side_share * (1.-pelvis) * (1.-thigh)
        dense = part['dense'].copy()
        dense[np.ix_(selected, family)] = desired[selected] * mass[selected,None]
        source_capacity = part['ids'].shape[1]
        required = int(np.count_nonzero(dense[selected] > 1e-9, axis=1).max())
        capacity = max(source_capacity, 8 if required > source_capacity else source_capacity)
        order = np.argsort(dense[selected],axis=1)[:,-capacity:][:,::-1]
        values = np.take_along_axis(dense[selected],order,axis=1)
        if np.max(np.abs(values.sum(axis=1)-dense[selected].sum(axis=1))) > 1e-7:
            raise ValueError('Apron transfer would discard an influence')
        values /= values.sum(axis=1,keepdims=True)
        ids = np.pad(part['ids'], ((0,0),(0,capacity-source_capacity)))
        weights = np.pad(part['weights'], ((0,0),(0,capacity-source_capacity)))
        ids[selected], weights[selected] = order, values
        attrs = part['primitive']['attributes']
        for group in range(capacity//4):
            attrs['JOINTS_'+str(group)] = append(doc,blob,attrs.get('JOINTS_'+str(group),attrs['JOINTS_0']),ids[:,group*4:group*4+4])
            attrs['WEIGHTS_'+str(group)] = append(doc,blob,attrs.get('WEIGHTS_'+str(group),attrs['WEIGHTS_0']),weights[:,group*4:group*4+4])
        rows.append({'mesh':part['name'],'vertices':int(selected.sum()),'source_geometry_unchanged':True,'influence_capacity':capacity})
    return rows


def weld_weight_copies(source_doc, source_blob, doc, blob):
    """Keep originally coincident skin seams together across pigment boundaries."""
    reports = []
    for original, updated in zip(parts(source_doc, source_blob), parts(doc, blob)):
        pairs = cKDTree(original['xyz']).query_pairs(1e-7, output_type='ndarray')
        if not len(pairs):
            continue
        pairs = pairs[np.max(np.abs(original['dense'][pairs[:,0]]-original['dense'][pairs[:,1]]),axis=1) < 1e-7]
        parents = np.arange(len(original['xyz']))
        def root(index):
            while parents[index] != index:
                parents[index] = parents[parents[index]]
                index = parents[index]
            return index
        for first, second in pairs:
            parents[root(second)] = root(first)
        groups = {}
        for index in np.unique(pairs):
            groups.setdefault(root(index), []).append(index)
        dense = updated['dense'].copy()
        changed = []
        for members in groups.values():
            if np.max(np.abs(dense[members]-dense[members[0]])) <= 1e-7:
                continue
            # A UV seam can carry a different texel on each copy. Use the
            # corrected copy for the whole physical point, rather than leave
            # its unselected twin attached to the original pelvis weights.
            difference = np.sum(np.abs(dense[members]-original['dense'][members]),axis=1)
            source = members[int(np.argmax(difference))]
            dense[members] = dense[source]
            changed.extend(members)
        if not changed:
            continue
        indices = np.array(sorted(set(changed)))
        ids, weights = updated['ids'].copy(), updated['weights'].copy()
        capacity = ids.shape[1]
        assert np.count_nonzero(dense[indices] > 1e-9, axis=1).max() <= capacity
        order = np.argsort(dense[indices],axis=1)[:,-capacity:][:,::-1]
        values = np.take_along_axis(dense[indices],order,axis=1)
        ids[indices], weights[indices] = order, values / values.sum(1,keepdims=True)
        attrs = updated['primitive']['attributes']
        for group in range(capacity//4):
            attrs['JOINTS_'+str(group)] = append(doc,blob,attrs['JOINTS_'+str(group)],ids[:,group*4:group*4+4])
            attrs['WEIGHTS_'+str(group)] = append(doc,blob,attrs['WEIGHTS_'+str(group)],weights[:,group*4:group*4+4])
        reports.append({'mesh':updated['name'],'synchronized_uv_copy_vertices':len(indices)})
    return reports


def repair_trouser_template_seams(doc, blob):
    """Remove old cloth-only displacements from reunited trouser UV seams.

    Reweighting reveals coincident khaki copies whose former unequal weights
    hid inconsistent Local targets. These are trousers, not apron panels: one
    copy already has zero Local displacement. Both copies must stay undeformed
    by those cloth-only targets. Other vertices and shape targets stay exact.
    """
    reports = []
    rest, _ = world_matrices(doc, blob)
    node_names = {node.get('name'):index for index,node in enumerate(doc['nodes'])}
    hip_y = np.mean([rest[node_names['mixamorig:'+side+'UpLeg']][1,3] for side in ['Left','Right']])
    knee_y = np.mean([rest[node_names['mixamorig:'+side+'Leg']][1,3] for side in ['Left','Right']])
    for part in parts(doc, blob):
        primitive = part['primitive']
        mesh = next(mesh for mesh in doc['meshes'] if any(p is primitive for p in mesh['primitives']))
        names = mesh.get('extras', {}).get('targetNames', [])
        targets = [(name, target) for name, target in zip(names, primitive.get('targets', []))
                   if name.startswith('Garment_Local_')]
        if not targets:
            continue
        rgb = colours(doc, blob, primitive)
        red, green, blue = rgb.T
        khaki = (red > green*1.02) & (green > blue*1.06) & (red-blue > .065)
        trousers = khaki & (part['xyz'][:,1] > knee_y) & (part['xyz'][:,1] < hip_y)
        pairs = cKDTree(part['xyz']).query_pairs(1e-7, output_type='ndarray')
        # Physical trouser copies remain one seam even when float weights
        # differ slightly. Godot can import such weights identically; using
        # exact weight equality here hid a2.4e-7 source difference.
        pairs = pairs[np.all(trousers[pairs],axis=1)]
        changed_vertices = set()
        for name, target in targets:
            values = read(doc, blob, target['POSITION'])
            different = pairs[np.linalg.norm(values[pairs[:,0]]-values[pairs[:,1]], axis=1) > 1e-4]
            if not len(different):
                continue
            if not np.all(khaki[different]):
                raise ValueError('Unexpected non-trouser shape seam; inspect manually')
            if not np.all(np.minimum(np.linalg.norm(values[different[:,0]],axis=1),
                                     np.linalg.norm(values[different[:,1]],axis=1)) < 1e-7):
                raise ValueError('Both seam copies have nonzero targets; inspect manually')
            selected = np.unique(different)
            changed_vertices.update(int(i) for i in selected)
            values[selected] = 0.
            target['POSITION'] = append(doc, blob, target['POSITION'], values)
        if changed_vertices:
            reports.append({'mesh':part['name'], 'physical_seam_vertices':sorted(changed_vertices),
                            'scope':'Only inconsistent Garment_Local POSITION deltas on coincident khaki trouser UV copies are zeroed'})
    return reports


def repair(source, output, character, report, apron_follow=False):
    if source.resolve() == output.resolve() or output.exists():
        raise ValueError('Write a new candidate; never overwrite the input or an existing candidate')
    doc, raw = load(source)
    before = copy.deepcopy(doc)
    blob = bytearray(raw)
    rows = repair_trousers(doc, blob) if character == 'ren' else []
    apron = repair_apron_weights(doc, blob) if character == 'ren' and apron_follow else []
    seams = weld_weight_copies(before, raw, doc, blob) if character == 'ren' else []
    template_seams = repair_trouser_template_seams(doc, blob) if character == 'ren' else []
    walk = author_walk_knees(doc, blob) if character == 'sora' else None
    for key in ['skins', 'materials', 'textures', 'images', 'samplers', 'scenes', 'scene']:
        assert doc.get(key) == before.get(key), key
    for old_mesh, new_mesh in zip(before['meshes'], doc['meshes']):
        for old, new in zip(old_mesh['primitives'], new_mesh['primitives']):
            if not template_seams:
                assert old.get('targets') == new.get('targets')
            assert old.get('indices') == new.get('indices')
            for key in old['attributes']:
                if not key.startswith(('JOINTS_', 'WEIGHTS_')):
                    assert old['attributes'][key] == new['attributes'][key], key
    rig = next(node for node in doc['nodes'] if node.get('name') == 'Rig')
    rig.setdefault('extras', {})['leg_foundation'] = {
        'version': 1, 'character': character,
        'walk_knee_plane_authored': character == 'sora',
        'trouser_weights_rebuilt': character == 'ren',
        'apron_weights_transferred': bool(apron),
        'source_sha256': digest(source)}
    if template_seams:
        rig['extras']['leg_foundation']['trouser_local_template_seams_repaired'] = True
    save(doc, blob, output)
    assert output.read_bytes() != source.read_bytes()
    data = {'character': character, 'source': str(source.resolve()), 'source_sha256': digest(source),
            'output': str(output.resolve()), 'output_sha256': digest(output), 'trousers': rows, 'apron': apron, 'walk': walk, 'seams': seams,
            'trouser_template_seams': template_seams,
            'rest_joints_bind_matrices_geometry_textures_unchanged': True,
            'morph_targets_unchanged_except_reported_trouser_local_seams': True,
            'production_installed': False}
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: value for key, value in data.items() if key != 'trousers'}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--character', choices=['sora', 'ren'], required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--apron-follow', action='store_true', help='Candidate experiment; requires native cloth inspection')
    args = parser.parse_args()
    repair(args.input, args.output, args.character, args.report, args.apron_follow)

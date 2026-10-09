"""Repair head skinning and neck pivots without changing the exterior or UVs.

Coordinates, images, indices, morphs, clip times and limb channels stay untouched.
The neck and head inverse bind matrices move with the measured skull depth;
their translation tracks receive the same rest-space adjustment.
"""
from pathlib import Path
import argparse, copy, io, json, struct, sys
import numpy as np
from PIL import Image
from scipy.spatial.transform import Rotation, Slerp
from scipy.spatial import cKDTree

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'art/poc/character_pipeline_20261003/appearance_preserved'))
from retime_glb import load, durations

HEAD_START = {'sora': .855, 'mio': .81, 'ren': .86, 'haru': .815,
              'tanaka': .835, 'aoi': .80, 'kazuko': .835}
DTYPE = {5121: '<u1', 5123: '<u2', 5125: '<u4', 5126: '<f4'}
WIDTH = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read(d, b, index):
    a = d['accessors'][index]; v = d['bufferViews'][a['bufferView']]
    dtype = np.dtype(DTYPE[a['componentType']]); width = WIDTH[a['type']]
    return np.ndarray((a['count'], width), dtype=dtype, buffer=b,
                      offset=v.get('byteOffset', 0) + a.get('byteOffset', 0),
                      strides=(v.get('byteStride', width * dtype.itemsize), dtype.itemsize)).copy()


def append(d, b, old_index, values):
    a = copy.deepcopy(d['accessors'][old_index])
    data = np.asarray(values, dtype=DTYPE[a['componentType']])
    a['count'] = len(data)
    b.extend(b'\0' * ((-len(b)) % 4))
    view = len(d['bufferViews'])
    d['bufferViews'].append({'buffer': 0, 'byteOffset': len(b), 'byteLength': data.nbytes})
    b.extend(data.tobytes()); a['bufferView'] = view; a.pop('byteOffset', None)
    if 'min' in a: a['min'] = data.min(axis=0).tolist()
    if 'max' in a: a['max'] = data.max(axis=0).tolist()
    d['accessors'].append(a)
    return len(d['accessors']) - 1


def save(d, b, path):
    d['buffers'][0]['byteLength'] = len(b)
    encoded = json.dumps(d, separators=(',', ':')).encode()
    encoded += b' ' * ((-len(encoded)) % 4); b.extend(b'\0' * ((-len(b)) % 4))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(struct.pack('<III', 0x46546c67, 2, 28 + len(encoded) + len(b)) +
                     struct.pack('<II', len(encoded), 0x4e4f534a) + encoded +
                     struct.pack('<II', len(b), 0x004e4942) + b)


def repair(source, target, who, height_offset=0, head_start_override=None):
    head_start = HEAD_START[who] if head_start_override is None else head_start_override
    d, original = load(source); b = bytearray(original)
    parents = {c: i for i, n in enumerate(d['nodes']) for c in n.get('children', [])}
    world = {}
    def matrix(i):
        if i in world: return world[i]
        n = d['nodes'][i]
        if 'matrix' in n: m = np.array(n['matrix']).reshape(4, 4).T
        else:
            m = np.eye(4)
            m[:3, :3] = Rotation.from_quat(n.get('rotation', [0, 0, 0, 1])).as_matrix() @ np.diag(n.get('scale', [1, 1, 1]))
            m[:3, 3] = n.get('translation', [0, 0, 0])
        world[i] = matrix(parents[i]) @ m if i in parents else m
        return world[i]
    names = {n.get('name'): i for i, n in enumerate(d['nodes'])}
    head, neck = names['mixamorig:Head'], names['mixamorig:Neck']
    mesh_nodes = [(i, n) for i, n in enumerate(d['nodes']) if 'mesh' in n and 'skin' in n]
    all_points = []
    for i, n in mesh_nodes:
        if d['meshes'][n['mesh']].get('name', '').startswith('HiddenArm'): continue
        for p in d['meshes'][n['mesh']]['primitives']:
            points = read(d, b, p['attributes']['POSITION'])
            all_points.extend((np.c_[points, np.ones(len(points))] @ matrix(i).T)[:, :3])
    points = np.asarray(all_points); H = float(np.ptp(points[:, 1])); floor = points[:, 1].min()
    skull = points[(points[:, 1] > floor + .88 * H) & (abs(points[:, 0]) < .15 * H)]
    desired_depth = float(np.quantile(skull[:, 2], [.05, .95]).mean())
    offset = np.array([0., height_offset, desired_depth - matrix(head)[2, 3]])
    if abs(offset[2]) < .02 * H: offset[2] = 0
    new_neck = matrix(neck).copy(); new_neck[:3, 3] += offset
    local = np.linalg.inv(matrix(parents[neck])) @ new_neck
    old_local = np.linalg.inv(matrix(parents[neck])) @ matrix(neck)
    delta = local[:3, 3] - old_local[:3, 3]
    d['nodes'][neck]['translation'] = local[:3, 3].tolist()
    for animation in d['animations']:
        for channel in animation['channels']:
            if channel['target'] != {'node': neck, 'path': 'translation'}: continue
            sampler = animation['samplers'][channel['sampler']]
            values = read(d, b, sampler['output']).astype(float)
            if sampler.get('interpolation') == 'CUBICSPLINE': values[1::3] += delta
            else: values += delta
            sampler['output'] = append(d, b, sampler['output'], values)
    for skin in d['skins']:
        binds = read(d, b, skin['inverseBindMatrices']).astype(float)
        for j, node in enumerate(skin['joints']):
            if node not in [head, neck]: continue
            new = matrix(node).copy(); new[:3, 3] += offset
            binds[j] = (np.linalg.inv(new) @ matrix(node) @ binds[j].reshape(4, 4).T).T.reshape(-1)
        skin['inverseBindMatrices'] = append(d, b, skin['inverseBindMatrices'], binds)
    changed = 0; neck_count = 0
    for i, n in mesh_nodes:
        if d['meshes'][n['mesh']].get('name', '').startswith('HiddenArm'): continue
        skin = d['skins'][n['skin']]; hj = skin['joints'].index(head); nj = skin['joints'].index(neck)
        for primitive in d['meshes'][n['mesh']]['primitives']:
            attrs = primitive['attributes']; pp = read(d, b, attrs['POSITION'])
            pp = (np.c_[pp, np.ones(len(pp))] @ matrix(i).T)[:, :3]
            ids = np.concatenate([read(d, b, attrs[k]) for k in ['JOINTS_0', 'JOINTS_1'] if k in attrs], axis=1)
            weights = np.concatenate([read(d, b, attrs[k]) for k in ['WEIGHTS_0', 'WEIGHTS_1'] if k in attrs], axis=1).astype(float)
            uv = read(d, b, attrs['TEXCOORD_0']); material = d['materials'][primitive['material']]
            tex = d['textures'][material['pbrMetallicRoughness']['baseColorTexture']['index']]
            image_info = d['images'][tex['source']]
            if 'bufferView' in image_info:
                view = d['bufferViews'][image_info['bufferView']]; start = view.get('byteOffset', 0)
                image = Image.open(io.BytesIO(b[start:start+view['byteLength']])).convert('RGB')
            else: image = Image.open(source.parent / image_info['uri']).convert('RGB')
            rgb = np.array(image)[np.minimum((uv[:, 1] % 1 * image.height).astype(int), image.height-1),
                                  np.minimum((uv[:, 0] % 1 * image.width).astype(int), image.width-1)] / 255
            y = pp[:, 1]; centre = abs(pp[:, 0]) < .15 * H
            r, g, blue = rgb.T
            pale = (rgb.min(axis=1) > .17) & (np.ptp(rgb, axis=1) < .16)
            garment = np.zeros(len(pp), dtype=bool)
            if who == 'haru':
                garment = ((g > r*.95) & (g > blue*1.2) & (r > blue*1.12)) | ((blue > g*1.12) & (r > g*1.07) & (abs(pp[:, 0]) < .075*H))
                garment &= y < floor+.86*H
            elif who == 'tanaka':
                beard = (y > floor+.855*H) & (abs(pp[:, 0]) < .065*H) & (pp[:, 2] > desired_depth+.04*H)
                garment = pale & (y < floor+.865*H) & (~beard)
            elif who == 'sora': garment = ((g > r*1.07) & (g > blue*.96)) | (pale & (y < floor+.855*H))
            elif who == 'mio': garment = (pale | (blue > r*1.08)) & (y < floor+.845*H)
            elif who == 'ren':
                peach = (g / np.maximum(r,1e-8) > .55) & (blue / np.maximum(r,1e-8) > .32)
                garment = (r > .25) & (r > g*1.4) & (g > blue*1.5) & (blue < .33) & (y < floor+.855*H) & (~peach)
            elif who == 'kazuko': garment = (((r > g*1.1) & (blue > g*1.02)) | pale) & (y < floor+.855*H)
            rigid = centre & (y > floor + head_start * H)
            head_weight = np.sum(weights * (ids == hj), axis=1)
            hair = ((rgb[:, 0] > rgb[:, 1] * 1.18) & (rgb.mean(axis=1) < .4)) | ((np.ptp(rgb, axis=1) < .1) & (rgb.mean(axis=1) > .5))
            rigid |= centre & (y > floor + (head_start - .05) * H) & hair & (head_weight > .65)
            rigid &= ~garment
            rigid |= centre & (y > floor+.86*H)
            skin_colour = (rgb[:, 0] > .45) & (rgb[:, 1] > .40) & (rgb[:, 2] > .27) & (rgb[:, 0] > rgb[:, 1]+.055) & (rgb[:, 1] > rgb[:, 2]+.04)
            base = matrix(neck)[1, 3] + offset[1]
            band = (~rigid) & (~garment) & skin_colour & (abs(pp[:, 0]) < .065*H) & (y > base) & (y < floor+head_start*H)
            collar = garment & centre & (~rigid) & (y > base-.035*H)
            affected = rigid | band | collar
            ids[affected] = 0; weights[affected] = 0
            ids[rigid, 0] = hj; weights[rigid, 0] = 1
            u = np.clip((y[band]-base) / (floor+head_start*H-base), 0, 1); u = u*u*(3-2*u)
            ids[band, 0] = nj; ids[band, 1] = hj; weights[band, 0] = 1-u; weights[band, 1] = u
            ids[collar, 0] = skin['joints'].index(names['mixamorig:Spine2']); weights[collar, 0] = 1
            # Blend across duplicated UV seams and the lower collar boundary.
            # Colour alone must never leave alternating head/chest strips.
            smooth = centre & (~rigid) & (y > base-.025*H) & (y < floor+.87*H)
            if np.any(smooth):
                dense = np.zeros((len(pp)+1, len(skin['joints'])), dtype=np.float32)
                np.add.at(dense, (np.repeat(np.arange(len(pp)), ids.shape[1]), ids.reshape(-1)), weights.reshape(-1))
                distances, neighbours = cKDTree(pp).query(pp[smooth], k=12, distance_upper_bound=.012*H)
                valid = np.isfinite(distances).astype(float); normalizer = np.maximum(valid.sum(axis=1), 1)
                for _ in range(12):
                    mean = (dense[neighbours] * valid[:, :, None]).sum(axis=1) / normalizer[:, None]
                    dense[:len(pp)][smooth] = dense[:len(pp)][smooth] * .45 + mean * .55
                order = np.argsort(dense[:len(pp)][smooth], axis=1)[:, -ids.shape[1]:][:, ::-1]
                value = np.take_along_axis(dense[:len(pp)][smooth], order, axis=1)
                value /= np.maximum(value.sum(axis=1, keepdims=True), 1e-12)
                ids[smooth] = order; weights[smooth] = value
            for k in range(ids.shape[1]//4):
                attrs['JOINTS_'+str(k)] = append(d, b, attrs['JOINTS_'+str(k)], ids[:, k*4:(k+1)*4])
                attrs['WEIGHTS_'+str(k)] = append(d, b, attrs['WEIGHTS_'+str(k)], weights[:, k*4:(k+1)*4])
            changed += int(rigid.sum()); neck_count += int(band.sum())
    if who == 'haru':
        limits = {'look': {'mixamorig:Head': .6, 'mixamorig:Neck': .5, 'mixamorig:Spine2': .8},
                  'bow': {'mixamorig:Head': .7, 'mixamorig:Spine': .8, 'mixamorig:Spine2': .8},
                  'stretch': {'mixamorig:Head': .5, 'mixamorig:Spine': .7, 'mixamorig:Spine2': .7}}
        for animation in d['animations']:
            for channel in animation['channels']:
                node = channel['target']['node']; path = channel['target']['path']
                factor = limits.get(animation['name'], {}).get(d['nodes'][node].get('name'))
                if factor is None or path != 'rotation': continue
                sampler = animation['samplers'][channel['sampler']]
                assert sampler.get('interpolation', 'LINEAR') != 'CUBICSPLINE'
                q = read(d, b, sampler['output']); rest = d['nodes'][node].get('rotation', [0,0,0,1])
                values = np.array([Slerp([0,1], Rotation.from_quat([rest, v]))([factor]).as_quat()[0] for v in q])
                sampler['output'] = append(d, b, sampler['output'], values)
    rig = d['nodes'][names['Rig']]
    rig.setdefault('extras', {}).update(character_id=who, reference_pose='A 45 degrees below horizontal')
    rig.setdefault('extras', {})['head_neck_repair'] = {'head_start_fraction': head_start, 'pivot_offset_m': offset.tolist(), 'head_rigid_vertices': changed, 'neck_blend_vertices': neck_count, 'elderly_gestures': who == 'haru'}
    save(d, b, target)
    before, after = durations(source), durations(target)
    assert before == after
    report = {'character': who, 'source': str(source), 'target': str(target), **rig['extras']['head_neck_repair'], 'clip_times_preserved': True}
    target.with_suffix('.head-neck.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--source', type=Path, required=True); p.add_argument('--target', type=Path, required=True)
    p.add_argument('--character', choices=list(HEAD_START), required=True); p.add_argument('--height-offset', type=float, default=0);p.add_argument('--head-start', type=float)
    a = p.parse_args(); print(json.dumps(repair(a.source, a.target, a.character, a.height_offset, a.head_start)))

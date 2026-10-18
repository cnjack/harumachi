"""Bake modest thigh-follow drape only into run, preserving original skin weights.

This action corrective lifts/follows the existing skirt before final post-IK
contact. Every other action and every original target payload is preserved.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from scipy.spatial import cKDTree
from scipy import sparse
from scipy.sparse.csgraph import connected_components
from glb_io import load
from prepare_local_garments import read
from audit_local_garments import mesh_state, pose
from prepare_sleeve_correctives import patch_weights
from corrective_normals import unit, geometry_normals, rotate_between
from motion_math import world_matrices
from repair_head_neck import append, save


def prepare(args):
    source = mesh_state(args.input, 'mio')
    fitted = mesh_state(args.fitted_input, 'mio')
    d, raw = load(args.input)
    b = bytearray(raw)
    ni = source['ni']; node = d['nodes'][ni]; mesh = d['meshes'][node['mesh']]
    p = mesh['primitives'][0]; attributes = p['attributes']
    pos = source['positions']; joints = source['joints']; weights = source['weights']
    normals = unit(read(d, b, attributes['NORMAL']))
    names = mesh['extras']['targetNames']; count = len(names)
    if any(n.startswith('GarmentDrape_') for n in names): raise ValueError('Drape already applied')
    if not np.array_equal(pos, fitted['positions']): raise ValueError('Fitted source geometry differs')
    body = source['body']
    if not np.array_equal(joints[body], fitted['joints'][body]) or not np.array_equal(weights[body], fitted['weights'][body]):
        raise ValueError('Fitted guide changes real body bindings')
    cloth = np.maximum.reduce([np.linalg.norm(source['shapes'][i], axis=1) for i in source['local']]) > 1e-8
    faces = read(d, b, p['indices']).reshape(-1, 3)
    pairs = cKDTree(pos).query_pairs(1e-6, output_type='ndarray')
    graph = sparse.coo_matrix((np.ones(2*len(pairs)), (np.r_[pairs[:, 0], pairs[:, 1]], np.r_[pairs[:, 1], pairs[:, 0]])), shape=(len(pos), len(pos))).tocsr()
    groups, labels = connected_components(graph, directed=False)
    sizes = np.bincount(labels, minlength=groups)
    permit = np.full(groups, True)
    np.logical_and.at(permit, labels, cloth)
    cloth = permit[labels]
    animation = next(a for a in d['animations'] if a['name'] == 'run')
    duration = max(float(read(d, b, s['input']).max()) for s in animation['samplers'])
    phases = np.arange(args.samples)/args.samples
    source_normals = [unit(normals+read(d, b, t['NORMAL']))-normals if 'NORMAL' in t else np.zeros_like(pos) for t in p['targets']]
    report = {'input': str(args.input), 'source_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
              'fitted_guide': str(args.fitted_input), 'scope': 'run only; source weights and all other actions exact',
              'samples': [], 'maximum_drape_shift_m': args.cap}
    new_names = []
    for phase in phases:
        time = duration*phase
        current, _ = pose(source, 'run', time, disable_global=True)
        wanted, _ = pose(fitted, 'run', time, disable_global=True)
        shift = wanted-current
        shift[~cloth] = 0
        sums = np.zeros((groups, 3)); np.add.at(sums, labels, shift)
        shift = sums[labels]/sizes[labels, None]
        shift *= np.minimum(1, args.cap/np.maximum(np.linalg.norm(shift, axis=1), 1e-12))[:, None]
        old_tri = current[faces]
        old_cross = np.cross(old_tri[:, 1]-old_tri[:, 0], old_tri[:, 2]-old_tri[:, 0])
        old_area = np.linalg.norm(old_cross, axis=1)
        for retreat in range(80):
            tri = (current+shift)[faces]
            cross = np.cross(tri[:, 1]-tri[:, 0], tri[:, 2]-tri[:, 0])
            bad = ((old_cross*cross).sum(1) <= 0) & (old_area > 1e-12)
            bad |= (np.linalg.norm(cross, axis=1) < old_area*.15) & (old_area > 1e-12)
            if not bad.any(): break
            multiplier = np.ones(groups); multiplier[np.unique(labels[faces[bad]])] = .65
            shift *= multiplier[labels, None]
        if bad.any(): raise ValueError('Drape inverted/collapsed a source triangle')
        worlds, _ = world_matrices(d, b, animation, time)
        matrices = np.array([worlds[j]@ib for j, ib in zip(source['skin']['joints'], source['binds'])])
        B = np.zeros((len(pos), 3, 3))
        for slot in range(joints.shape[1]): B += matrices[joints[:, slot], :3, :3]*weights[:, slot, None, None]
        active = np.linalg.norm(shift, axis=1) > 1e-8
        delta = np.zeros_like(pos); delta[active] = np.einsum('nij,nj->ni', np.linalg.pinv(B[active]), shift[active])
        affected = np.zeros(len(pos), bool); affected[np.unique(faces[np.any(active[faces], axis=1)])] = True
        values = patch_weights(source['d'], source['b'], next(a for a in source['d']['animations'] if a['name']=='run'), ni, count, np.array([time]))[0]
        normal = normals.copy()
        for value, dn in zip(values, source_normals): normal += value*dn
        old_geo = geometry_normals(current, faces); new_geo = geometry_normals(current+shift, faces)
        original_render = unit(np.einsum('nij,nj->ni', B, unit(normal)))
        wanted_render = unit(rotate_between(old_geo, new_geo, original_render))
        desired_rest = unit(np.einsum('nij,nj->ni', np.linalg.pinv(B), wanted_render))
        offset = normals-normal; along = np.sum(offset*desired_rest, axis=1)
        disc = along*along+1-np.sum(offset*offset, axis=1)
        scale = -along+np.sqrt(np.maximum(disc, 0))
        dn = unit(offset+scale[:, None]*desired_rest)-normals
        dn[~affected | ~cloth] = 0
        p['targets'].append({'POSITION': append(d, b, attributes['POSITION'], delta.astype(np.float32)),
                             'NORMAL': append(d, b, attributes['NORMAL'], dn.astype(np.float32))})
        name = f'GarmentDrape_run_{round(phase*1000):03d}'; new_names.append(name)
        report['samples'].append({'phase': float(phase), 'target': name, 'maximum_shift_m': float(np.linalg.norm(shift, axis=1).max()),
                                  'body_shift_max_m': float(np.linalg.norm(shift[body], axis=1).max()),
                                  'uv_added_gap_m': float(np.linalg.norm(shift[pairs[:, 0]]-shift[pairs[:, 1]], axis=1).max()),
                                  'newly_inverted_faces': int(bad.sum()), 'moved_vertices': int(active.sum())})
    names.extend(new_names); mesh['weights'] = list(mesh.get('weights', [0]*count))+[0]*len(phases)
    if 'weights' in node: node['weights'] += [0]*len(phases)
    closed_phases = np.r_[phases, 1.]
    for target_animation in d['animations']:
        old_animation = next(a for a in source['d']['animations'] if a['name']==target_animation['name'])
        old_channel = next(c for c in old_animation['channels'] if c['target']=={'node': ni, 'path': 'weights'})
        times = read(source['d'], source['b'], old_animation['samplers'][old_channel['sampler']]['input']).ravel()
        if target_animation['name']=='run': times = np.unique(np.r_[times, closed_phases*duration]).astype(np.float32)
        previous = patch_weights(source['d'], source['b'], old_animation, ni, count, times)
        output = np.c_[previous, np.zeros((len(times), len(phases)))]
        if target_animation['name']=='run':
            for index in range(len(phases)):
                curve = np.zeros(len(phases)+1); curve[index] = 1
                if index==0: curve[-1] = 1
                output[:, count+index] = np.interp(times/duration, closed_phases, curve)
        template = target_animation['samplers'][0]['input']
        ti = append(d, b, template, times[:, None]); oi = append(d, b, template, output.reshape(-1, 1))
        si = len(target_animation['samplers']); target_animation['samplers'].append({'input': ti, 'output': oi, 'interpolation': 'LINEAR'})
        target_animation['channels'] = [c for c in target_animation['channels'] if c['target']!={'node': ni, 'path': 'weights'}]
        target_animation['channels'].append({'sampler': si, 'target': {'node': ni, 'path': 'weights'}})
    save(d, b, args.output)
    report['output'] = str(args.output); report['output_sha256'] = hashlib.sha256(args.output.read_bytes()).hexdigest()
    args.report.write_text(json.dumps(report, indent=2)); print(args.report)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path); parser.add_argument('--fitted-input', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path); parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--samples', type=int, default=16); parser.add_argument('--cap', type=float, default=.05)
    prepare(parser.parse_args())

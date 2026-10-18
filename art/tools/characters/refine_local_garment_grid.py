"""Refine existing garment controls while preserving the exact source envelope.

Candidate-only: no skin, skeleton, geometry, authored non-local corrective, or
skeletal animation changes. Old local columns are replaced by a sparse smooth
hat partition on the same physical bounds. This proves payload/mask equivalence,
not final contact, orientation, or native visual acceptance.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json

import numpy as np
from scipy.spatial import cKDTree

from audit_local_garments import mesh_state
from corrective_normals import geometry_normals, rotate_between, unit
from glb_io import load
from prepare_local_garments import PREFIX, read, smooth
from repair_head_neck import append, save


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def sparse_vec3(document, binary, values):
    """Append exact float32 nonzero rows; old accessors and bytes stay intact."""
    values = np.asarray(values, dtype='<f4')
    selected = np.flatnonzero(np.any(values != 0, axis=1))
    accessor = {'componentType': 5126, 'count': len(values), 'type': 'VEC3',
                'min': values.min(axis=0).astype(float).tolist(),
                'max': values.max(axis=0).astype(float).tolist()}
    if len(selected):
        views = []
        index_type = 5123 if len(values) <= 65536 else 5125
        arrays = [selected.astype('<u2' if index_type == 5123 else '<u4'), values[selected]]
        for array in arrays:
            while len(binary) % 4:
                binary.append(0)
            start = len(binary)
            binary.extend(array.tobytes())
            views.append(len(document['bufferViews']))
            document['bufferViews'].append({'buffer': 0, 'byteOffset': start, 'byteLength': len(binary)-start})
        accessor['sparse'] = {'count': len(selected),
                              'indices': {'bufferView': views[0], 'componentType': index_type},
                              'values': {'bufferView': views[1]}}
    index = len(document['accessors'])
    document['accessors'].append(accessor)
    return index


def hats(coordinates, low, high, count):
    """The original cubic smoothstep hats, with endpoint continuation."""
    grid = np.linspace(low, high, count)
    values = smooth(0, 1, np.clip(1-abs(coordinates[:, None]-grid)/(grid[1]-grid[0]), 0, 1))
    values[coordinates < low, 0] = 1
    values[coordinates > high, -1] = 1
    assert np.max(abs(values.sum(axis=1)-1)) < 2e-13
    return values


def local_ids(names, side):
    return [i for i, name in enumerate(names) if name.startswith(PREFIX+side+'_')]


def seam_pairs(state):
    pairs = cKDTree(state['positions']).query_pairs(1e-6, output_type='ndarray')
    dense = np.zeros((len(state['positions']), len(state['skin']['joints'])))
    for slot in range(state['joints'].shape[1]):
        np.add.at(dense, (np.arange(len(dense)), state['joints'][:, slot]), state['weights'][:, slot])
    if len(pairs):
        pairs = pairs[np.max(abs(dense[pairs[:, 0]]-dense[pairs[:, 1]]), axis=1) < 1e-7]
    return pairs


def geometric_normal_delta(points, normals, faces, old_geo, delta, body):
    moved = np.linalg.norm(delta, axis=1) > 1e-8
    affected = np.zeros(len(points), bool)
    affected[np.unique(faces[np.any(moved[faces], axis=1)])] = True
    result = unit(rotate_between(old_geo, geometry_normals(points+delta, faces), normals))-normals
    result[~affected] = 0
    result[body] = 0
    return result.astype(np.float32)


def verify(source, output, who, expected, selected_sides):
    """Reread and compare independently by target name and original payload."""
    original = mesh_state(source, who)
    candidate = mesh_state(output, who)
    sd, sb = original['d'], original['b']
    d, b = candidate['d'], candidate['b']
    assert b[:len(sb)] == sb
    assert d['accessors'][:len(sd['accessors'])] == sd['accessors']
    assert d['bufferViews'][:len(sd['bufferViews'])] == sd['bufferViews']
    assert d['skins'] == sd['skins']
    for key in ['materials', 'images', 'textures', 'samplers', 'scenes', 'scene', 'asset', 'extensions', 'extensionsUsed', 'extensionsRequired']:
        assert d.get(key) == sd.get(key), key
    ni = original['ni']
    rig_id = next(i for i, n in enumerate(sd['nodes']) if n.get('name') == 'Rig')
    protected_nodes = 0
    for i, (old, new) in enumerate(zip(sd['nodes'], d['nodes'])):
        old, new = copy.deepcopy(old), copy.deepcopy(new)
        if i == ni:
            old.pop('weights', None)
            new.pop('weights', None)
        if i == rig_id:
            for node in [old, new]:
                profile = node['extras']['garment_local_clearance']
                for key in ['rows', 'columns', 'panel_grids']:
                    profile.pop(key, None)
        assert old == new, ('node', i)
        protected_nodes += 1
    old_mesh = sd['meshes'][original['node']['mesh']]
    new_mesh = d['meshes'][candidate['node']['mesh']]
    old_names = old_mesh['extras']['targetNames']
    new_names = new_mesh['extras']['targetNames']
    assert len(set(new_names)) == len(new_names)
    keep_names = [name for name in old_names if not any(name.startswith(PREFIX+s+'_') for s in selected_sides)]
    assert [name for name in new_names if name in keep_names] == keep_names
    for key in ['weights']:
        for name in keep_names:
            assert old_mesh[key][old_names.index(name)] == new_mesh[key][new_names.index(name)]
    if 'weights' in original['node']:
        for name in keep_names:
            assert original['node']['weights'][old_names.index(name)] == candidate['node']['weights'][new_names.index(name)]
    else:
        assert 'weights' not in candidate['node']
    for name in new_names:
        if name not in keep_names:
            assert new_mesh['weights'][new_names.index(name)] == 0
            if 'weights' in candidate['node']:
                assert candidate['node']['weights'][new_names.index(name)] == 0
    protected_target_payloads = 0
    for mi, (old_m, new_m) in enumerate(zip(sd['meshes'], d['meshes'])):
        if mi != original['node']['mesh']:
            assert old_m == new_m
            continue
        old_meta, new_meta = copy.deepcopy(old_m), copy.deepcopy(new_m)
        for m in [old_meta, new_meta]:
            m.pop('primitives')
            m.pop('weights', None)
            m['extras'].pop('targetNames')
        assert old_meta == new_meta
        for old_p, new_p in zip(old_m['primitives'], new_m['primitives']):
            assert {k:v for k,v in old_p.items() if k != 'targets'} == {k:v for k,v in new_p.items() if k != 'targets'}
            for name in keep_names:
                assert old_p['targets'][old_names.index(name)] == new_p['targets'][new_names.index(name)]
                protected_target_payloads += len(old_p['targets'][old_names.index(name)])
    animation_rows = []
    for old_a, new_a in zip(sd['animations'], d['animations']):
        assert {k:v for k,v in old_a.items() if k != 'samplers'} == {k:v for k,v in new_a.items() if k != 'samplers'}
        body_samplers = {c['sampler'] for c in old_a['channels'] if c['target'] == {'node': ni, 'path': 'weights'}}
        for si, (old_s, new_s) in enumerate(zip(old_a['samplers'], new_a['samplers'])):
            if si not in body_samplers:
                assert old_s == new_s
                continue
            assert {k:v for k,v in old_s.items() if k != 'output'} == {k:v for k,v in new_s.items() if k != 'output'}
            old_values = read(sd, sb, old_s['output']).reshape(-1, len(old_names))
            new_values = read(d, b, new_s['output']).reshape(-1, len(new_names))
            for name in keep_names:
                assert np.array_equal(old_values[:, old_names.index(name)], new_values[:, new_names.index(name)])
            assert not np.any(new_values[:, [new_names.index(n) for n in new_names if n not in keep_names]])
            animation_rows.append({'clip': old_a['name'], 'key_rows_including_cubic_tangents': len(old_values),
                                   'input_accessor_exact': old_s['input'] == new_s['input'],
                                   'preserved_target_columns': len(keep_names), 'nonlocal_values_bit_exact': True})
    pairs = seam_pairs(original)
    panels = []
    for side in ['Front', 'Back']:
        old_sum = np.sum([original['shapes'][i].astype(float) for i in local_ids(old_names, side)], axis=0)
        new_ids = local_ids(new_names, side)
        new_sum = np.sum([candidate['shapes'][i].astype(float) for i in new_ids], axis=0)
        error = float(np.max(abs(old_sum-new_sum)))
        assert error < 2e-8, (side, error)
        support_max = np.max(np.sum(np.stack([np.any(candidate['shapes'][i] != 0, axis=1) for i in new_ids]), axis=0))
        assert support_max <= 4
        seam = max((float(np.linalg.norm(candidate['shapes'][i][pairs[:, 0]]-candidate['shapes'][i][pairs[:, 1]], axis=1).max()) for i in new_ids), default=0.) if len(pairs) else 0.
        assert seam < 1e-7
        body_position = max((float(np.max(abs(candidate['shapes'][i][original['body']]))) for i in new_ids), default=0.)
        assert body_position == 0
        if side in selected_sides:
            for i in new_ids:
                assert np.max(abs(read(d,b,new_mesh['primitives'][0]['targets'][i]['NORMAL'])[original['body']])) == 0
        panels.append({'side': side, 'local_target_count': len(new_ids), 'sum_position_envelope_maximum_error_m': error,
                       'maximum_simultaneous_point_support': int(support_max), 'body0_position_delta_max_m': body_position,
                       'physical_UV_seam_position_delta_gap_max_m': seam})
    assert d['nodes'][rig_id]['extras']['garment_local_clearance']['rows'] == expected[0]
    assert d['nodes'][rig_id]['extras']['garment_local_clearance']['columns'] == expected[1]
    return {'reread_pass': True, 'original_binary_and_accessor_view_prefix_exact': True,
            'protected_nodes': protected_nodes, 'inverse_bind_skin_base_attributes_indices_images_exact': True,
            'protected_target_payload_descriptors_exact': protected_target_payloads,
            'all_other_meshes_exact': True, 'physical_skin_equivalent_seam_pairs': len(pairs),
            'protected_body0_vertices': len(original['body']), 'panels': panels,
            'animation_weight_channels': animation_rows,
            'authored_skeletal_channels_and_input_times_exact': True,
            'local_channels_zero': True}


def refine(args):
    state = mesh_state(args.input, args.character)
    sd, sb = state['d'], state['b']
    d, b = copy.deepcopy(sd), bytearray(sb)
    ni = state['ni']
    node = d['nodes'][ni]
    mesh = d['meshes'][node['mesh']]
    old_names = list(mesh['extras']['targetNames'])
    assert len(set(old_names)) == len(old_names)
    selected = ['Front', 'Back'] if args.panels == 'both' else [args.panels.title()]
    keep = [i for i,n in enumerate(old_names) if not any(n.startswith(PREFIX+s+'_') for s in selected)]
    for side in ['Front', 'Back']:
        assert len(local_ids(old_names, side)) == 12, 'Input must have the existing 4x3 controls per side'
    assert args.rows >= 2 and args.columns >= 2
    new_names = [old_names[i] for i in keep]+[f'{PREFIX}{side}_{row}_{col}' for side in selected for row in range(args.rows) for col in range(args.columns)]
    count_new = len(new_names)-len(keep)
    rig = next(n for n in d['nodes'] if n.get('name') == 'Rig')
    profile = rig['extras']['garment_local_clearance']
    amplitude = float(profile['shape_amplitude_m'])
    assert amplitude == .12
    report = {'stage': 'refined-local-garment-basis-candidate-only', 'character': args.character,
              'input': str(args.input), 'source_sha256': sha(args.input), 'output': str(args.output),
              'selected_panels': selected, 'rows': args.rows, 'columns': args.columns,
              'old_local_targets': 24, 'new_total_local_targets': sum(12 if s not in selected else args.rows*args.columns for s in ['Front','Back']),
              'shape_amplitude_m': amplitude, 'maximum_weight': profile['maximum_weight'],
              'new_target_normal_policy': 'rotate authored unit normals by old-to-new rest geometric normal rotation, preserve hard-edge offsets; body0 pinned',
              'endpoint_policy': 'extend endpoint hats; old top taper already lives in recovered mask, no second taper',
              'primitives': [], 'acceptance': 'payload and envelope equivalence only; actual solver, final-pose fold/collapse, Euclidean gap and native review pending'}
    for primitive in mesh['primitives']:
        attrs = primitive['attributes']
        points = read(sd,sb,attrs['POSITION'])
        faces = read(sd,sb,primitive['indices']).reshape(-1,3)
        normals = unit(read(sd,sb,attrs['NORMAL']))
        old_geo = geometry_normals(points, faces)
        old_targets = primitive['targets']
        masks = {side: np.sum([np.abs(read(sd,sb,old_targets[i]['POSITION'])[:,2]).astype(float) for i in local_ids(old_names,side)],axis=0)/amplitude for side in ['Front','Back']}
        for side in selected:
            for i in local_ids(old_names,side):
                assert np.max(abs(read(sd,sb,old_targets[i]['POSITION'])[:,:2])) == 0
            assert np.max(masks[side][state['body']]) == 0
        allmask = np.maximum(masks['Front'],masks['Back'])
        active = allmask > 1e-5
        height = float(points[:,1].max())
        lower = float(np.quantile(points[active,1],.01))
        upper = .56*height
        maxx = float(np.quantile(abs(points[active,0]),.98))
        xx = hats(points[:,0],-maxx,maxx,args.columns)
        yy = hats(points[:,1],lower,upper,args.rows)
        targets = [copy.deepcopy(old_targets[i]) for i in keep]
        for side in selected:
            sign = 1 if side == 'Front' else -1
            for row in range(args.rows):
                for col in range(args.columns):
                    delta = np.zeros_like(points)
                    delta[:,2] = sign*amplitude*masks[side]*xx[:,col]*yy[:,row]
                    normal_delta = geometric_normal_delta(points,normals,faces,old_geo,delta,state['body'])
                    targets.append({'POSITION': sparse_vec3(d,b,delta), 'NORMAL': sparse_vec3(d,b,normal_delta)})
        primitive['targets'] = targets
        report['primitives'].append({'vertices':len(points),'physical_bounds_m':{'x':[-maxx,maxx],'y':[lower,upper]},
                                     'mask_recovery':'per-side sum(abs(old local deltaZ)) / 0.12 in float64, no recolour/reclassification',
                                     'front_mask_maximum':float(masks['Front'].max()),'back_mask_maximum':float(masks['Back'].max())})
    mesh['extras']['targetNames'] = new_names
    mesh['weights'] = [mesh['weights'][i] for i in keep]+[0]*count_new
    if 'weights' in node:
        node['weights'] = [node['weights'][i] for i in keep]+[0]*count_new
    for animation in d['animations']:
        touched = set()
        for channel in animation['channels']:
            if channel['target'] != {'node':ni,'path':'weights'}:
                continue
            sampler_index = channel['sampler']
            assert not any(c['sampler']==sampler_index and c['target']!={'node':ni,'path':'weights'} for c in animation['channels']), 'Shared body/nonbody sampler requires explicit splitting'
            if sampler_index in touched:
                continue
            touched.add(sampler_index)
            sampler = animation['samplers'][sampler_index]
            values = read(sd,sb,sampler['output']).reshape(-1,len(old_names))
            new_values = np.c_[values[:,keep],np.zeros((len(values),count_new),values.dtype)]
            sampler['output'] = append(d,b,sampler['output'],new_values.reshape(-1,1))
    profile['rows'],profile['columns'] = args.rows,args.columns
    if selected != ['Front','Back']:
        profile['panel_grids'] = {s:{'rows':args.rows if s in selected else 3,'columns':args.columns if s in selected else 4} for s in ['Front','Back']}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    save(d,b,args.output)
    report['output_sha256'] = sha(args.output)
    report['tool_sha256'] = sha(__file__)
    report['verification'] = verify(args.input,args.output,args.character,(args.rows,args.columns),selected)
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(args.report,report['output_sha256'],flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--character',required=True,choices=['mio','kazuko'])
    parser.add_argument('--report',required=True,type=Path)
    parser.add_argument('--rows',type=int,default=6)
    parser.add_argument('--columns',type=int,default=8)
    parser.add_argument('--panels',choices=['both','front','back'],default='both')
    refine(parser.parse_args())

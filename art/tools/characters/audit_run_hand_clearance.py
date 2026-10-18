#!/usr/bin/env python3
"""Audit Tanaka's run hand/jacket overlap without confusing rear occlusion with entry.

Uses source semantic skin and blue torso triangles. A bad query must lie behind
its near-side jacket sheet AND between distinct actual front/back blue sheets.
This is a local paired-surface relation, not a watertight-volume assertion. It
rejects ordinary rear-hand visibility occlusion. All seven barycentric samples
of every semantic hand triangle plus every semantic vertex are checked.

With --native-manifest, skin the unchanged full source mesh using captured final
world bone bases and actual morph scalars. This is a separate post-modifier audit;
it does not reconstruct the runtime arm correction or seek the source animation.
"""
import os
for name in ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'VECLIB_MAXIMUM_THREADS'):
    os.environ[name] = '1'
import argparse
import copy
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation
from audit_local_garments import mesh_state
from prepare_local_garments import colours
from repair_head_neck import read
from motion_math import world_matrices
from source_surface_rays import envelope

BARY = np.array([[1,0,0],[0,1,0],[0,0,1],[.5,.5,0],[0,.5,.5],[.5,0,.5],[1/3,1/3,1/3]])


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def prepare(path, require_zero_run_morphs=True):
    s = mesh_state(path, 'tanaka')
    doc, raw = s['d'], s['b']
    primitive = doc['meshes'][s['node']['mesh']]['primitives'][0]
    rgb = colours(doc, raw, primitive)
    faces = read(doc, raw, primitive['indices']).reshape(-1, 3)
    names = [doc['nodes'][node]['name'] for node in s['skin']['joints']]
    torso = np.array([name.startswith('mixamorig:Spine') or name == 'mixamorig:Hips' for name in names])
    share = (s['weights'] * torso[s['joints']]).sum(1)
    blue = (rgb[:,2] > rgb[:,0]*1.12) & (rgb[:,2] > rgb[:,1]*1.05)
    torso_ids = np.flatnonzero(np.all(blue[faces] & (share[faces] > .5), axis=1))
    skin = (rgb[:,0] > rgb[:,1]*1.1) & (rgb[:,1] > rgb[:,2]*1.02) & (rgb[:,0] > .3)
    hands = {}
    for side in ['Left', 'Right']:
        selected = np.array([name.startswith('mixamorig:'+side) and any(part in name for part in ['ForeArm', 'Hand']) for name in names])
        skin_share = (s['weights'] * selected[s['joints']]).sum(1)
        mask = skin & (skin_share > .9)
        hand_faces = faces[np.all(mask[faces], axis=1)]
        edges = np.unique(np.sort(np.concatenate([hand_faces[:,[0,1]],hand_faces[:,[1,2]],hand_faces[:,[2,0]]]),axis=1),axis=0)
        hands[side] = dict(vertices=np.flatnonzero(mask), faces=hand_faces, edges=edges)
    action = next(action for action in doc['animations'] if action['name'] == 'run')
    duration = max(float(read(doc, raw, sampler['input']).max()) for sampler in action['samplers'])
    # No source/candidate run morph may be silently omitted from the LBS audit.
    for channel in action['channels'] if require_zero_run_morphs else []:
        if channel['target']['path'] == 'weights':
            if np.any(read(doc, raw, action['samplers'][channel['sampler']]['output']) != 0):
                raise ValueError('This audit requires the measured run-zero morph fixture')
    return dict(s=s, doc=doc, raw=raw, action=action, duration=duration, faces=faces,
                torso_faces=faces[torso_ids], torso_ids=torso_ids, hands=hands,
                ids={node.get('name'): index for index,node in enumerate(doc['nodes'])})


def skin_points(state, world, positions=None):
    s = state['s']
    mats = np.array([world[joint] @ bind for joint,bind in zip(s['skin']['joints'], s['binds'])])
    source = s['positions'] if positions is None else np.asarray(positions, dtype=float)
    if source.shape != s['positions'].shape or not np.isfinite(source).all():
        raise ValueError('Skin positions must be complete finite source-mesh vertices')
    homogeneous = np.c_[source, np.ones(len(source))]
    points = np.zeros_like(source, dtype=float)
    for column in range(s['joints'].shape[1]):
        points += np.einsum('nij,nj->ni', mats[s['joints'][:,column],:3,:], homogeneous) * s['weights'][:,column,None]
    return points


def native_bone_worlds(doc, required_nodes, row):
    """World capture -> original GLB model frame, retaining real basis/scale.

    Godot stores basis columns as three XYZ arrays. Actor position is deliberately
    unused: the visual model may have its own offset, heading or scale. Every skin
    joint must come from the final capture; missing joints never use source tracks.
    """
    def array(value, shape, label):
        result = np.asarray(value, dtype=float)
        if result.shape != shape or not np.isfinite(result).all():
            raise ValueError('Native capture needs finite ' + label)
        return result

    if 'model_basis' not in row or 'model_position' not in row:
        raise ValueError('Native capture needs model_basis and model_position')
    basis = array(row['model_basis'], (3, 3), 'model_basis').T
    origin = array(row['model_position'], (3,), 'model_position')
    try:
        inverse = np.linalg.inv(basis)
    except np.linalg.LinAlgError as error:
        raise ValueError('Native model_basis is singular') from error
    if not np.isfinite(inverse).all():
        raise ValueError('Native model_basis inverse is not finite')
    bones = row.get('bones')
    if not isinstance(bones, list) or not bones:
        raise ValueError('Native capture lacks final bone bases')
    by_name = {}
    for bone in bones:
        name = bone.get('name', '')
        if name.startswith('mixamorig_'):
            name = 'mixamorig:' + name[len('mixamorig_'):]
        if not name or name in by_name:
            raise ValueError('Native capture has an empty or duplicate bone: ' + name)
        by_name[name] = bone
    worlds = {}
    for node in required_nodes:
        name = doc['nodes'][node].get('name', '')
        if name not in by_name:
            raise ValueError('Native capture lacks required skin joint: ' + name)
        bone = by_name[name]
        if 'basis' not in bone or 'position' not in bone:
            raise ValueError('Native capture lacks complete final transform: ' + name)
        world = np.eye(4)
        world[:3, :3] = inverse @ array(bone['basis'], (3, 3), name + ' basis').T
        world[:3, 3] = inverse @ (array(bone['position'], (3,), name + ' position') - origin)
        if abs(float(np.linalg.det(world[:3, :3]))) < 1e-12:
            raise ValueError('Native final bone basis is singular: ' + name)
        worlds[node] = world
    return worlds


def native_morph_positions(mesh, row):
    """Apply every actual captured morph, including nonzero runtime residuals."""
    names = mesh['names']
    shapes = mesh['shapes']
    if len(names) != len(shapes) or len(set(names)) != len(names):
        raise ValueError('Source mesh target names and position deltas differ')
    actual = row.get('blend_shape_values')
    if not isinstance(actual, dict):
        raise ValueError('Native capture lacks actual blend_shape_values')
    mesh_name = mesh['node'].get('name', '')
    table = actual.get(mesh_name)
    if not isinstance(table, dict) or set(table) != set(names):
        raise ValueError('Native shape table does not cover source mesh: ' + mesh_name)
    values = np.asarray([table[name] for name in names], dtype=float)
    if values.shape != (len(names),) or not np.isfinite(values).all():
        raise ValueError('Native morph values must be finite scalar values')
    positions = mesh['positions'].astype(float, copy=True)
    for value, delta in zip(values, shapes):
        positions += value * delta
    return positions, dict(zip(names, values.tolist()))


def native_points(state, row):
    """Independent source LBS from all final native joints and actual shapes."""
    worlds = native_bone_worlds(state['doc'], state['s']['skin']['joints'], row)
    positions, values = native_morph_positions(state['s'], row)
    return skin_points(state, worlds, positions=positions), values


def native_domain_coverage(state):
    """Missing semantic coverage is unqualified, never a zero-intersection pass."""
    torso_faces = len(state['torso_faces'])
    if not torso_faces:
        raise ValueError('Native semantic blue-torso face domain is empty')
    hands = {}
    for side in ['Left', 'Right']:
        hand = state['hands'][side]
        counts = {key: len(hand[key]) for key in ['vertices', 'faces', 'edges']}
        if not all(counts.values()):
            raise ValueError('Native semantic hand domain is empty or incomplete: ' + side)
        hands[side] = counts
    return dict(blue_torso_faces=torso_faces, hands=hands)


def native_sample_clock(row):
    """Require a finite, same-frame acknowledgement for the captured pose."""
    ack = row.get('pose_sample', {})
    if (not ack or ack.get('request_id') is None or ack.get('request_id') != ack.get('acknowledged_request') or
            ack.get('applied_frame') is None or ack.get('applied_frame') != ack.get('captured_frame') or
            ack.get('clip') != 'run'):
        raise ValueError('Native run shot lacks a matching same-frame final-pose acknowledgement')
    try:
        time, phase, acknowledged_time = float(row['clip_time']), float(row['phase']), float(ack['clip_time'])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError('Native run shot lacks numeric clip time/phase/acknowledgement') from error
    if (not np.isfinite([time, phase, acknowledged_time]).all() or time < 0 or
            not 0 <= phase <= 1 or abs(acknowledged_time - time) > 1e-6):
        raise ValueError('Native run shot has invalid or inconsistent clip time/phase')
    return time, phase


def audit_native(candidate_path, manifest_path):
    """Audit every captured Tanaka run shot; retain distinct camera samples."""
    state = prepare(candidate_path, require_zero_run_morphs=False)
    rig = next(node for node in state['doc']['nodes'] if node.get('name') == 'Rig')
    if rig.get('extras', {}).get('character_id') != 'tanaka':
        raise ValueError('Native blue-coat/hand semantic domain is qualified for Tanaka only')
    coverage = native_domain_coverage(state)
    provenance = manifest_path.parent.parent / 'model-hashes.json'
    if not provenance.is_file():
        raise ValueError('Native audit requires capture companion model-hashes.json')
    expected = json.loads(provenance.read_text()).get('CH_tanaka.glb')
    candidate_hash = sha(candidate_path)
    if expected != candidate_hash:
        raise ValueError('Native capture model SHA differs from candidate GLB; recapture this candidate')
    manifest = json.loads(manifest_path.read_text())
    shots = manifest.get('shots', [])
    if not isinstance(shots, list) or not shots or manifest.get('failures'):
        raise ValueError('Native manifest is incomplete or contains capture failures')
    for field in ['images', 'expected_images']:
        if field in manifest and manifest[field] != len(shots):
            raise ValueError('Native manifest count differs from completed shots: ' + field)
    selected = [row for row in shots if row.get('id') == 'tanaka' and row.get('clip') == 'run']
    if not selected:
        raise ValueError('Native manifest has no Tanaka run shots')
    samples = []
    image_files = set()
    for row in selected:
        time, phase = native_sample_clock(row)
        relative = row.get('file', '')
        image = (manifest_path.parent / relative).resolve()
        if (not relative or image == manifest_path.parent.resolve() or
                manifest_path.parent.resolve() not in image.parents or
                not image.is_file() or image.stat().st_size == 0 or relative in image_files):
            raise ValueError('Native shot needs a unique nonempty capture image within its folder')
        image_files.add(relative)
        points, values = native_points(state, row)
        intersections = exact_edge_intersections(state, points)
        for side in ['Left', 'Right']:
            samples.append(dict(phase=phase, clip='run', clip_time=time, view=row.get('view'),
                                source_file=relative, image_sha256=sha(image), side=side,
                                actual_morph_values=values, **measure(state, points, side), **intersections[side]))
    summary = {}
    for side in ['Left', 'Right']:
        rows = [row for row in samples if row['side'] == side]
        summary[side] = dict(samples=len(rows),
            exact_crossing_samples=sum(row['exact_hand_edge_crossing_count'] > 0 for row in rows),
            maximum_exact_edge_crossing_count=max(row['exact_hand_edge_crossing_count'] for row in rows),
            paired_samples=sum(row['paired_queries'] > 0 for row in rows),
            reliable_paired_samples=sum(row['reliable_paired_queries'] > 0 for row in rows),
            maximum_paired_depth_m=max(row['max_all_paired_depth_m'] for row in rows),
            same_side_occluded_samples=sum(row['one_sided_occluded_queries'] > 0 for row in rows),
            maximum_same_side_occluded_queries=max(row['one_sided_occluded_queries'] for row in rows),
            pass_hand_clearance=all(row['paired_queries'] == 0 and row['exact_hand_edge_crossing_count'] == 0 for row in rows),
            pass_same_side_blue_sheet_visibility=all(row['one_sided_occluded_queries'] == 0 for row in rows))
    return dict(pass_audit=all(side['pass_hand_clearance'] for side in summary.values()),
        mode='captured-final-native-bones-and-morphs',
        scope='Original full source GLB mesh, inverse binds and skin weights, actual final world bones and every captured body morph scalar. Model transform removed with its full inverse. Original semantic bare-hand / blue-torso domains and original exact edge and paired-sheet gates; not a GPU pixel visibility or whole-body intersection assertion. Same-side blue-sheet visibility is reported separately because rear occlusion alone is not physical entry.',
        candidate_sha256=candidate_hash, native_manifest=str(manifest_path), native_manifest_sha256=sha(manifest_path),
        native_model_hashes_sha256=sha(provenance), tool_sha256=sha(__file__),
        native_shots=len(selected), phases=sorted({row['phase'] for row in selected}),
        views=sorted({str(row.get('view')) for row in selected}),
        semantic_domain_coverage=coverage,
        limits=dict(near_sheet_depth_m=.0005, normal_abs_dot_axis=.35),
        summary=summary, samples=samples)


def measure(state, points, side):
    hand = state['hands'][side]
    q = np.concatenate([points[hand['vertices']], np.einsum('bk,fkj->fbj', BARY, points[hand['faces']]).reshape(-1,3)])
    sign = 1 if side == 'Left' else -1
    near = envelope(points[:,[1,2,0]], state['torso_faces'], q[:,[1,2,0]], sign)
    front = envelope(points, state['torso_faces'], q, 1)
    back = envelope(points, state['torso_faces'], q, -1)
    # Front/back must actually be different faces. A single one-sided sheet
    # can occlude a hand, but cannot enclose it along that axis.
    one_sided = near['signed_depth_m'] < -.0005
    paired = one_sided & (front['signed_depth_m'] < -.0005) & (back['signed_depth_m'] < -.0005) & (front['face_ids'] != back['face_ids'])
    reliable = paired & (near['normal_abs_dot_ray'] >= .35) & (front['normal_abs_dot_ray'] >= .35) & (back['normal_abs_dot_ray'] >= .35)
    worst = int(np.argmax(np.where(reliable, -near['signed_depth_m'], -np.inf))) if reliable.any() else None
    return dict(query_count=len(q), hand_vertices=len(hand['vertices']), hand_triangles=len(hand['faces']),
                one_sided_occluded_queries=int(one_sided.sum()), paired_queries=int(paired.sum()),
                reliable_paired_queries=int(reliable.sum()),
                max_reliable_near_sheet_depth_m=float(-near['signed_depth_m'][reliable].min()) if reliable.any() else 0.,
                max_all_paired_depth_m=float(-near['signed_depth_m'][paired].min()) if paired.any() else 0.,
                worst_query_model=q[worst].tolist() if worst is not None else None,
                worst_torso_source_triangles={key:int(state['torso_ids'][value['face_ids'][worst]]) for key,value in [('near',near),('front',front),('back',back)]} if worst is not None else None)


def exact_edge_intersections(state, points):
    """Independent actual 3D skin-edge/jacket-face crossings (no view/ray normal gate)."""
    tri = points[state['torso_faces']]
    a = tri[:,0]; first = tri[:,1]-a; second = tri[:,2]-a
    lo = np.floor(tri.min(1)/.025).astype(int); hi = np.floor(tri.max(1)/.025).astype(int)
    bins = {}
    for face in range(len(tri)):
        for x in range(lo[face,0], hi[face,0]+1):
            for y in range(lo[face,1], hi[face,1]+1):
                for z in range(lo[face,2], hi[face,2]+1):
                    bins.setdefault((x,y,z), []).append(face)
    results = {}
    for side, hand in state['hands'].items():
        edges = hand['edges']
        examples = []; count = 0
        for u,v in edges:
            start,end=points[[u,v]]; direction=end-start
            el=np.floor(np.minimum(start,end)/.025).astype(int); eh=np.floor(np.maximum(start,end)/.025).astype(int)
            candidates=[]
            for x in range(el[0],eh[0]+1):
                for y in range(el[1],eh[1]+1):
                    for z in range(el[2],eh[2]+1):
                        candidates += bins.get((x,y,z), [])
            if not candidates: continue
            ix=np.unique(candidates); h=np.cross(direction,second[ix]); determinant=np.einsum('ij,ij->i',first[ix],h)
            valid=abs(determinant)>1e-14
            inv=np.divide(1.,determinant,out=np.zeros(len(ix)),where=valid)
            start_delta=start-a[ix]; b1=np.einsum('ij,ij->i',start_delta,h)*inv
            q=np.cross(start_delta,first[ix]); b2=np.einsum('j,ij->i',direction,q)*inv
            t=np.einsum('ij,ij->i',second[ix],q)*inv
            valid &= (b1>1e-8)&(b2>1e-8)&(b1+b2<1-1e-8)&(t>1e-7)&(t<1-1e-7)
            count += int(valid.sum())
            for hit in np.flatnonzero(valid):
                if len(examples)<3:
                    examples.append(dict(hand_edge=[int(u),int(v)],torso_source_face=int(state['torso_ids'][ix[hit]]),
                                         intersection_model=(start+t[hit]*direction).tolist()))
        results[side]=dict(exact_hand_edge_crossing_count=count, crossing_examples=examples)
    return results


def content_contract(reference, candidate):
    a, b = reference, candidate
    old, new = a['doc'], b['doc']
    # Every pre-existing accessor remains in the original binary prefix.
    old_prefix = b['raw'][:len(a['raw'])] == a['raw']
    allowed = {a['ids']['mixamorig:'+side+'ForeArm'] for side in ['Left','Right']}
    changed = []
    expected = copy.deepcopy(old)
    exact = len(old['animations']) == len(new['animations'])
    for ai, (old_action, new_action) in enumerate(zip(old['animations'], new['animations'])):
        exact &= len(old_action['channels']) == len(new_action['channels']) and len(old_action['samplers']) == len(new_action['samplers'])
        for old_channel, new_channel in zip(old_action['channels'], new_action['channels']):
            os = old_action['samplers'][old_channel['sampler']]
            ns = new_action['samplers'][new_channel['sampler']]
            same = old_channel == new_channel and np.array_equal(read(old,a['raw'],os['input']), read(new,b['raw'],ns['input'])) and os.get('interpolation','LINEAR') == ns.get('interpolation','LINEAR')
            output_same = np.array_equal(read(old,a['raw'],os['output']), read(new,b['raw'],ns['output']))
            if not output_same:
                target = old_channel['target']
                changed.append([old_action['name'], old['nodes'][target['node']]['name'], target['path']])
                allowed_change = old_action['name'] == 'run' and target['node'] in allowed and target['path'] == 'rotation'
                same &= allowed_change
                if allowed_change:
                    expected['animations'][ai]['samplers'][old_channel['sampler']]['output'] = ns['output']
            exact &= same
    for key in ['accessors','bufferViews','buffers']:
        expected[key] = new[key]
    exact &= expected == new
    fixed_keys = ['nodes','meshes','skins','materials','textures','images','scenes','scene']
    payload_exact = all(old.get(key) == new.get(key) for key in fixed_keys) and old_prefix
    return dict(pass_contract=bool(exact and payload_exact and len(changed)==2), changed_channels=changed,
                all_original_binary_bytes_exact=old_prefix, mesh_skin_rest_uv_morph_material_json_exact=payload_exact,
                every_other_animation_channel_and_all_input_times_exact=bool(exact))


def audit(reference_path, candidate_path, phases):
    reference, candidate = prepare(reference_path), prepare(candidate_path)
    all_rows = []
    motion = {'reference':[], 'candidate':[]}
    max_leg_position_difference = 0.
    max_upper_arm_position_difference = 0.
    max_bone_length_difference = 0.
    maxima = dict(shoulder_basis_difference_deg=0., upper_arm_basis_difference_deg=0., elbow_position_difference_m=0., wrist_position_difference_m=0., forearm_basis_difference_deg=0., forearm_direction_difference_deg=0.)
    ids = reference['ids']
    for index in range(phases):
        phase = index / phases
        worlds = {}
        for label,state in [('reference',reference),('candidate',candidate)]:
            world,_ = world_matrices(state['doc'],state['raw'],state['action'],phase*state['duration'])
            worlds[label] = world
            points = skin_points(state, world)
            crossings = exact_edge_intersections(state, points)
            for side in ['Left','Right']:
                all_rows.append(dict(version=label, phase=phase, side=side, **measure(state,points,side), **crossings[side]))
            motion[label].append({name:world[node][:3,3].tolist() for name,node in ids.items() if name and name.startswith('mixamorig:')})
        wa, wb = worlds['reference'], worlds['candidate']
        for side in ['Left','Right']:
            def bone(part): return ids['mixamorig:'+side+part]
            for parent,child in [('Arm','ForeArm'),('ForeArm','Hand')]:
                la=np.linalg.norm(wa[bone(child)][:3,3]-wa[bone(parent)][:3,3]);lb=np.linalg.norm(wb[bone(child)][:3,3]-wb[bone(parent)][:3,3])
                max_bone_length_difference=max(max_bone_length_difference,abs(la-lb))
            for part in ['UpLeg','Leg','Foot','ToeBase']:
                max_leg_position_difference=max(max_leg_position_difference,float(np.linalg.norm(wa[bone(part)][:3,3]-wb[bone(part)][:3,3])))
            for part,key in [('Shoulder','shoulder_basis_difference_deg'),('Arm','upper_arm_basis_difference_deg'),('ForeArm','forearm_basis_difference_deg')]:
                r=Rotation.from_matrix(wb[bone(part)][:3,:3] @ np.linalg.inv(wa[bone(part)][:3,:3])).magnitude()*180/np.pi
                maxima[key]=max(maxima[key],float(r))
            for part,key in [('ForeArm','elbow_position_difference_m'),('Hand','wrist_position_difference_m')]:
                maxima[key]=max(maxima[key],float(np.linalg.norm(wb[bone(part)][:3,3]-wa[bone(part)][:3,3])))
            a=wa[bone('Hand')][:3,3]-wa[bone('ForeArm')][:3,3];b=wb[bone('Hand')][:3,3]-wb[bone('ForeArm')][:3,3]
            maxima['forearm_direction_difference_deg']=max(maxima['forearm_direction_difference_deg'],float(np.degrees(np.arccos(np.clip(a@b/(np.linalg.norm(a)*np.linalg.norm(b)),-1,1)))))
        if index % 24 == 0:
            print(json.dumps(dict(sample=index,total=phases,candidate_bad=sum(row['reliable_paired_queries']>0 for row in all_rows if row['version']=='candidate'))),flush=True)
    summary={}
    for label,state in [('reference',reference),('candidate',candidate)]:
        rows=[row for row in all_rows if row['version']==label]
        series=motion[label]
        def values(name):return np.array([frame['mixamorig:'+name] for frame in series])
        hip=values('Hips')
        rhythm={side:float(np.corrcoef((values(side+'Hand')-hip)[:,2],(values(side+'Foot')-hip)[:,2])[0,1]) for side in ['Left','Right']}
        amplitude={side:{part:{axis:float(np.ptp((values(side+part)-hip)[:,i])) for i,axis in enumerate('XYZ')} for part in ['Arm','ForeArm','Hand']} for side in ['Left','Right']}
        start,_=world_matrices(state['doc'],state['raw'],state['action'],0);end,_=world_matrices(state['doc'],state['raw'],state['action'],state['duration'])
        summary[label]=dict(pass_hand_clearance=all(row['paired_queries']==0 and row['exact_hand_edge_crossing_count']==0 for row in rows),
            exact_crossing_phase_side_count=sum(row['exact_hand_edge_crossing_count']>0 for row in rows),
            maximum_exact_edge_crossing_count=max(row['exact_hand_edge_crossing_count'] for row in rows), bad_phase_side_count=sum(row['reliable_paired_queries']>0 for row in rows),
            max_reliable_depth_m=max(row['max_reliable_near_sheet_depth_m'] for row in rows),
            all_paired_bad_phase_side_count=sum(row['paired_queries']>0 for row in rows),
            max_all_paired_depth_m=max(row['max_all_paired_depth_m'] for row in rows),
            same_side_hand_foot_z_correlation=rhythm,root_relative_arm_path_amplitude_m=amplitude,
            max_endpoint_bone_matrix_difference=float(max(np.max(np.abs(start[node]-end[node])) for node in state['s']['skin']['joints'])))
    contract=content_contract(reference,candidate)
    good=(contract['pass_contract'] and summary['reference']['bad_phase_side_count']>0 and summary['candidate']['pass_hand_clearance'] and
          max_bone_length_difference<1e-7 and max_leg_position_difference<1e-7 and maxima['elbow_position_difference_m']<1e-7 and
          summary['candidate']['max_endpoint_bone_matrix_difference']<1e-6 and
          all(v<-.75 for v in summary['candidate']['same_side_hand_foot_z_correlation'].values()))
    return dict(pass_audit=bool(good),scope=__doc__,reference_sha256=sha(reference_path),candidate_sha256=sha(candidate_path),tool_sha256=sha(__file__),
        phases=phases,phase_step=1/phases,includes_96_uniform_phases_and_midpoints=(phases==192),
        limits=dict(near_sheet_depth_m=.0005,normal_abs_dot_axis=.35),contract=contract,summary=summary,
        geometry=dict(max_arm_bone_length_difference_m=max_bone_length_difference,max_leg_bone_position_difference_m=max_leg_position_difference,**maxima),samples=all_rows)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--reference',type=Path);p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--native-manifest',type=Path,help='Audit actual Tanaka run final bones/morphs instead of comparing source clips')
    p.add_argument('--report',type=Path,required=True);p.add_argument('--phases',type=int,default=192)
    args=p.parse_args()
    if args.native_manifest:
        if args.reference:p.error('--reference is for source comparison; use --candidate with --native-manifest')
        result=audit_native(args.candidate,args.native_manifest)
    else:
        if not args.reference:p.error('--reference is required unless --native-manifest is supplied')
        result=audit(args.reference,args.candidate,args.phases)
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({key:value for key,value in result.items() if key!='samples'}),flush=True)
    raise SystemExit(0 if result['pass_audit'] else 1)
if __name__=='__main__':main()

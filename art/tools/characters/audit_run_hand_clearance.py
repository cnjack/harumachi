#!/usr/bin/env python3
"""Audit Tanaka's run hand/jacket overlap without confusing rear occlusion with entry.

Uses source semantic skin and blue torso triangles. A bad query must lie behind
its near-side jacket sheet AND between distinct actual front/back blue sheets.
This is a local paired-surface relation, not a watertight-volume assertion. It
rejects ordinary rear-hand visibility occlusion. All seven barycentric samples
of every semantic hand triangle plus every semantic vertex are checked.
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


def prepare(path):
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
    for channel in action['channels']:
        if channel['target']['path'] == 'weights':
            if np.any(read(doc, raw, action['samplers'][channel['sampler']]['output']) != 0):
                raise ValueError('This audit requires the measured run-zero morph fixture')
    return dict(s=s, doc=doc, raw=raw, action=action, duration=duration, faces=faces,
                torso_faces=faces[torso_ids], torso_ids=torso_ids, hands=hands,
                ids={node.get('name'): index for index,node in enumerate(doc['nodes'])})


def skin_points(state, world):
    s = state['s']
    mats = np.array([world[joint] @ bind for joint,bind in zip(s['skin']['joints'], s['binds'])])
    homogeneous = np.c_[s['positions'], np.ones(len(s['positions']))]
    points = np.zeros_like(s['positions'], dtype=float)
    for column in range(s['joints'].shape[1]):
        points += np.einsum('nij,nj->ni', mats[s['joints'][:,column],:3,:], homogeneous) * s['weights'][:,column,None]
    return points


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
    p.add_argument('--reference',type=Path,required=True);p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True);p.add_argument('--phases',type=int,default=192)
    args=p.parse_args();result=audit(args.reference,args.candidate,args.phases)
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({key:value for key,value in result.items() if key!='samples'}),flush=True)
    raise SystemExit(0 if result['pass_audit'] else 1)
if __name__=='__main__':main()

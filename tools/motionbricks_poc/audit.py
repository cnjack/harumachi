#!/usr/bin/env python3
"""Independent, read-only source/FK/GLB audit for the isolated MotionBricks POC.

No neural inference, production writer import, Godot, Blender or physics rollout.
MuJoCo mj_forward independently checks actual exported qpos against source FK.
Technical invariants have gates. Artistic naturalness has no automatic PASS.
"""
from __future__ import annotations
import argparse
import collections
import copy
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

import numpy as np
from scipy.spatial.transform import Rotation

ROOT = Path(__file__).resolve().parents[2]
POC = ROOT / 'art/poc/motionbricks_20261018'
VENDOR = POC / 'vendor/GR00T-WholeBodyControl'
EXPECTED_COMMIT = '45c03facbf848e0c743091b7d9c17952096ff908'
sys.path.insert(0, str(ROOT / 'art/tools/characters'))
from glb_io import load as load_glb
from motion_math import world_matrices, sample_channel
from repair_head_neck import read

P = np.array([[0., 1., 0.], [0., 0., 1.], [1., 0., 0.]])
SIDES = [('Left', 'left'), ('Right', 'right')]
ACTIVE_CORE = ['pelvis_skel'] + [side + suffix for _, side in SIDES
    for suffix in ['_hip_pitch_skel', '_hip_yaw_skel', '_knee_skel', '_ankle_roll_skel', '_elbow_skel', '_wrist_yaw_skel']]


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def load_json(path): return json.loads(Path(path).read_text())


def finite(values): return bool(np.isfinite(np.asarray(values)).all())


def stats(values):
    values = np.asarray(values, dtype=float).reshape(-1)
    return {'count': int(values.size), 'minimum': float(values.min()) if values.size else None,
            'median': float(np.median(values)) if values.size else None,
            'p95': float(np.quantile(values, .95)) if values.size else None,
            'maximum': float(values.max()) if values.size else None}


def rotation_error(first, second):
    relative = np.swapaxes(first, -1, -2) @ second
    return np.degrees(Rotation.from_matrix(relative.reshape(-1, 3, 3)).magnitude()).reshape(relative.shape[:-2])


def parts(mask):
    indices = np.flatnonzero(mask)
    if not len(indices): return []
    return np.split(indices, np.flatnonzero(np.diff(indices) > 1) + 1)


def source_arrays(path):
    with np.load(path, allow_pickle=False) as payload:
        result = {key: payload[key].copy() for key in payload.files}
    return result


def kinematic_mujoco_model(xml_path):
    """Retain original physical joint/body frames; omit only unused render assets.

    No inferred axes, hand-written chain, timestep integration or changed inertias.
    Keeping the XML in memory avoids importing/downloads of visual STL geometry.
    """
    import mujoco
    root = ET.parse(xml_path).getroot()
    world = root.find('worldbody')
    if world is None: raise ValueError('Official XML has no worldbody')
    hinges = [joint.get('name') for joint in world.findall('.//joint')]
    if len(hinges) != 29: raise ValueError('Expected29 official hinge joints')
    original_frames = [(body.get('name'), body.get('pos'), body.get('quat'),
        [(joint.tag, dict(joint.attrib)) for joint in body if joint.tag in ['joint', 'freejoint']])
        for body in world.iter('body')]
    removed = collections.Counter()
    for parent in list(root.iter()):
        for child in list(parent):
            if child.tag in ['geom', 'asset', 'actuator', 'sensor', 'contact', 'equality', 'tendon', 'keyframe']:
                removed[child.tag] += 1
                parent.remove(child)
    # Missing mesh/material defaults are unused once geoms are stripped. Their
    # joint defaults remain intact, including physical axes and joint limits.
    copied_frames = [(body.get('name'), body.get('pos'), body.get('quat'),
        [(joint.tag, dict(joint.attrib)) for joint in body if joint.tag in ['joint', 'freejoint']])
        for body in root.find('worldbody').iter('body')]
    if copied_frames != original_frames: raise AssertionError('Physical frame changed while removing visuals')
    serialized = ET.tostring(root, encoding='unicode')
    model = mujoco.MjModel.from_xml_string(serialized)
    if model.nq != 36 or model.nv != 35: raise ValueError(f'Unexpected compiled G1:{model.nq}/{model.nv}')
    joint_ids = [mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_JOINT, name) for name in hinges]
    if min(joint_ids) < 0: raise ValueError('Compiled MuJoCo model lost a source hinge')
    for order, joint_id in enumerate(joint_ids):
        if int(model.jnt_qposadr[joint_id]) != order + 7: raise ValueError('Official qpos/body tree ordering differs')
    free_ids = np.flatnonzero(model.jnt_type == mujoco.mjtJoint.mjJNT_FREE)
    if len(free_ids) != 1: raise ValueError('Expected single floating root')
    mapping = {'pelvis_skel': ('body', int(model.jnt_bodyid[free_ids[0]]))}
    for name, joint_id in zip(hinges, joint_ids):
        mapping[name.replace('_joint', '_skel')] = ('joint', joint_id)
    return model, mapping, {'official_xml': str(xml_path), 'xml_sha256': digest(xml_path),
        'stripped_xml_sha256': hashlib.sha256(serialized.encode()).hexdigest(),
        'removed_render_only_nodes': dict(removed), 'all_body_joint_pos_quat_and_inertials_retained': True,
        'compiled_nq': int(model.nq), 'compiled_nv': int(model.nv), 'hinge_order': hinges,
        'purpose': 'MuJoCo mj_forward kinematic reference, no physics stepping or rendering'}


def native_fk(qpos, model, mapping):
    import mujoco
    data = mujoco.MjData(model)
    names = list(mapping)
    positions = np.zeros((len(qpos), len(names), 3))
    rotations = np.zeros((len(qpos), len(names), 3, 3))
    for frame, row in enumerate(qpos):
        data.qpos[:] = row
        mujoco.mj_forward(model, data)
        for column, name in enumerate(names):
            kind, index = mapping[name]
            body = index if kind == 'body' else int(model.jnt_bodyid[index])
            position = data.xpos[body] if kind == 'body' else data.xanchor[index]
            positions[frame, column] = P @ position
            rotations[frame, column] = P @ data.xmat[body].reshape(3, 3) @ P.T
    return names, positions, rotations


def source_provenance(folder):
    manifest = load_json(folder/'manifest.json')
    receipt_path = folder/'cpu-source/receipt.json'
    receipt = load_json(receipt_path)
    if manifest['upstream_commit'] != EXPECTED_COMMIT or manifest['device'] != 'cpu':
        raise AssertionError('Unexpected upstream/device')
    if manifest['source_receipt_sha256'] != digest(receipt_path): raise AssertionError('CPU source receipt changed')
    upstream = receipt['upstream']; repository = Path(upstream['repository'])
    commit = subprocess.check_output(['git','-C',str(repository),'rev-parse','HEAD'],text=True).strip()
    if commit != EXPECTED_COMMIT or upstream['commit'] != EXPECTED_COMMIT: raise AssertionError('Vendor is not pinned')
    if any(digest(repository/relative) != expected for relative,expected in upstream['python_files'].items()):
        raise AssertionError('Official Python source changed')
    if any(digest(repository/relative) != expected for relative,expected in upstream['configs_stats_skeletons_xml'].items()):
        raise AssertionError('Official model config/stats/skeleton changed')
    overlay = Path(receipt['overlay_package'])
    allowed = {'motion_backbone/models/pose_model.py','motion_backbone/demo/clips.py',
        'motionlib/core/skeletons/base.py','motionlib/core/motion_reps/tools/changing_t_pose.py'}
    changed = []
    package = repository/'motionbricks/motionbricks'
    for relative, expected in upstream['python_files'].items():
        name = str(Path(relative).relative_to('motionbricks/motionbricks'))
        target = overlay/name
        if digest(target) != expected:
            changed.append(name)
            restored = target.read_text().replace(', map_location="cpu", weights_only=False', '')
            if hashlib.sha256(restored.encode()).hexdigest() != expected:
                raise AssertionError('CPU overlay contains more than deserialization adaptation:'+name)
    if set(changed) != allowed: raise AssertionError('Unexpected CPU overlay changed-file set')
    checkpoints = {}
    for name,row in manifest['checkpoints'].items():
        path = Path(row['path'])
        if digest(path) != row['sha256'] or path.stat().st_size != row['bytes']:
            raise AssertionError('Official checkpoint changed:'+name)
        checkpoints[name] = {'sha256':row['sha256'],'bytes':row['bytes']}
    return {'upstream_commit':commit,'official_python_files':len(upstream['python_files']),
        'all_official_source_configs_stats_skeleton_hashes_match':True,
        'CPU_overlay_only_deserialization_files':sorted(changed),'checkpoints':checkpoints,
        'manifest_sha256':digest(folder/'manifest.json'),'receipt_sha256':digest(receipt_path)}


def audit_source(path, model, mapping):
    source = source_arrays(path); metadata = load_json(path.with_suffix('.json'))
    names = [str(value) for value in source['joint_names']]; ids = {name:i for i,name in enumerate(names)}
    frames, joints = source['global_positions'].shape[:2]; fps = float(source['fps'])
    expected = {'qpos':(frames,36),'global_positions':(frames,34,3),
        'global_quaternions_xyzw':(frames,34,4),'reference_qpos':(36,),
        'reference_global_positions':(34,3),'reference_global_quaternions_xyzw':(34,4)}
    if joints!=34 or len(set(names))!=34 or fps!=30 or frames<2: raise AssertionError('Invalid source clock/joint coverage')
    for key,shape in expected.items():
        if source[key].shape != shape or not finite(source[key]): raise AssertionError('Invalid finite source shape:'+key)
    numeric_arrays = [key for key,value in source.items() if np.issubdtype(value.dtype,np.number)]
    if not all(finite(source[key]) for key in numeric_arrays): raise AssertionError('Nonfinite numeric source array')
    norms = np.linalg.norm(source['global_quaternions_xyzw'],axis=-1)
    qnorm = np.linalg.norm(source['qpos'][:,3:7],axis=-1)
    refnorm = np.linalg.norm(source['reference_global_quaternions_xyzw'],axis=-1)
    if max(np.abs(norms-1).max(),np.abs(qnorm-1).max(),np.abs(refnorm-1).max())>1e-5:
        raise AssertionError('Source quaternion norm invariant')
    if metadata['npz_sha256']!=digest(path): raise AssertionError('Source NPZ differs from generated receipt')
    counts=metadata['neural_forward_counts']
    if any(counts.get(name,0)<=0 for name in ['pose','root','vq_decoder']): raise AssertionError('Missing real neural forward evidence')
    roles=collections.Counter(str(value) for value in source['buffer_roles'])
    if dict(roles)!=metadata['frame_provenance_counts'] or roles.get('predicted_interior',0)==0:
        raise AssertionError('Frame source-role evidence missing/mismatched')
    if sum(roles.values())!=frames or metadata['finite_export_frames']!=frames:
        raise AssertionError('Source frame count mismatch')
    commands=metadata['commands']
    if commands[0]['start_frame']!=0 or commands[-1]['end_frame_exclusive']!=frames or any(
        commands[i]['end_frame_exclusive']!=commands[i+1]['start_frame'] for i in range(len(commands)-1)):
        raise AssertionError('Command clock coverage has gaps')
    if 'run' in str(source['mode']) or metadata['official_mode']=='run': raise AssertionError('Public G1 mode must not be called run')
    fk_names, positions, rotations=native_fk(source['qpos'],model,mapping)
    native_indices=[ids[name] for name in fk_names]
    exported_rotations=Rotation.from_quat(source['global_quaternions_xyzw'][:,native_indices].reshape(-1,4)).as_matrix().reshape(frames,-1,3,3)
    per_joint={}
    for column,name in enumerate(fk_names):
        position_errors=np.linalg.norm(positions[:,column]-source['global_positions'][:,ids[name]],axis=-1)
        angles=rotation_error(rotations[:,column],exported_rotations[:,column])
        per_joint[name]={'position_error_m':stats(position_errors),'rotation_error_deg':stats(angles)}
    maximum_position=max(row['position_error_m']['maximum'] for row in per_joint.values())
    maximum_rotation=max(row['rotation_error_deg']['maximum'] for row in per_joint.values())
    if maximum_position>.00002 or maximum_rotation>.02:
        raise AssertionError(f'Official FK versus independent MuJoCo mismatch:{path.name} {maximum_position}m/{maximum_rotation}deg')
    _,refp,refr=native_fk(source['reference_qpos'][None],model,mapping)
    refpe=np.linalg.norm(refp[0]-source['reference_global_positions'][native_indices],axis=-1)
    refr_export=Rotation.from_quat(source['reference_global_quaternions_xyzw'][native_indices]).as_matrix()
    refre=rotation_error(refr[0],refr_export)
    if refpe.max()>.00002 or refre.max()>.02: raise AssertionError('Shared idle reference differs from independent native FK')
    root=ids['pelvis_skel'];root_forward=exported_rotations[:,fk_names.index('pelvis_skel')]@np.array([0.,0.,1.])
    root_delta=source['global_positions'][-1,root]-source['global_positions'][0,root]
    result={'motion_id':path.stem,'source_npz':str(path),'sha256':digest(path),'frames':frames,'fps':fps,
        'declared_sample_times_s':{'first':0.,'last':(frames-1)/fps,'step':1/fps},
        'clock_scope':'Offline declared30fps sample clock; inference wall times are separate, no constant real-time inference claim',
        'numeric_arrays_finite':numeric_arrays,'all_34_unit_quaternion_norm_max_error':float(np.abs(norms-1).max()),
        'MuJoCo_root_wxyz_unit_norm_max_error':float(np.abs(qnorm-1).max()),
        'source_frame_roles':dict(roles),'neural_forward_counts':counts,'official_mode':metadata['official_mode'],
        'independent_native_fk':{'all_30_active_joints_all_frames_checked':True,'selected_named_core_joints':ACTIVE_CORE,
            'maximum_position_error_m':maximum_position,'maximum_rotation_error_deg':maximum_rotation,
            'reference_position_max_error_m':float(refpe.max()),'reference_rotation_max_error_deg':float(refre.max()),
            'per_joint':per_joint,'limits':{'position_m':.00002,'rotation_deg':.02},
            'dead_endpoints':'All34finite/unit checked; dummy hand/toe orientation is not independently treated as actuated FK.'},
        'source_root_world_delta_m':root_delta.tolist(),'root_forward_first_last':[root_forward[0].tolist(),root_forward[-1].tolist()],
        'raw_model_contact_scalars':{'range':stats(source['foot_contacts']),
            'scope':'Raw neural feature contacts can differ from filtered qpos; not ground-contact truth'},
        'technical_invariants_pass':True,'artistic_naturalness':'Not automatically qualified'}
    return source,result


def attribute(doc,binary,index):
    value=read(doc,binary,index)
    accessor=doc['accessors'][index]
    if accessor.get('normalized'):
        if accessor['componentType']==5121:value=value.astype(float)/255.
        elif accessor['componentType']==5123:value=value.astype(float)/65535.
        elif accessor['componentType']==5120:value=np.maximum(value.astype(float)/127.,-1.)
        elif accessor['componentType']==5122:value=np.maximum(value.astype(float)/32767.,-1.)
    return value


def morph_weights(doc,binary,animation,time):
    weights={index:np.asarray(node.get('weights',doc['meshes'][node['mesh']].get('weights',[])),float)
             for index,node in enumerate(doc['nodes']) if 'mesh' in node}
    for channel in animation['channels']:
        if channel['target']['path']!='weights':continue
        index=channel['target']['node'];mesh=doc['meshes'][doc['nodes'][index]['mesh']]
        count=max(len(primitive.get('targets',[])) for primitive in mesh['primitives'])
        sampler=animation['samplers'][channel['sampler']];times=read(doc,binary,sampler['input']).reshape(-1)
        values=read(doc,binary,sampler['output']).reshape(len(times),count)
        if sampler.get('interpolation','LINEAR') not in ['LINEAR','STEP']:raise ValueError('Audit new weights interpolation explicitly')
        step=int(np.searchsorted(times,time,side='right')-1);step=int(np.clip(step,0,len(times)-1))
        if step==len(times)-1 or sampler.get('interpolation')=='STEP' or time<=times[0]:weights[index]=values[step]
        else:
            u=(time-times[step])/(times[step+1]-times[step]);weights[index]=values[step]*(1-u)+values[step+1]*u
    return weights


def shoe_geometry(doc,binary,weights):
    shoes={'Left':[],'Right':[]}
    for node_index,node in enumerate(doc['nodes']):
        if 'mesh' not in node or 'skin' not in node:continue
        skin=doc['skins'][node['skin']];joint_ids=skin['joints']
        binds=read(doc,binary,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
        for primitive_index,primitive in enumerate(doc['meshes'][node['mesh']]['primitives']):
            attr=primitive['attributes'];positions=attribute(doc,binary,attr['POSITION']).astype(float)
            for morph_index,target in enumerate(primitive.get('targets',[])):
                value=weights.get(node_index,[])
                if len(value)>morph_index and value[morph_index]!=0 and 'POSITION' in target:
                    positions+=float(value[morph_index])*attribute(doc,binary,target['POSITION'])
            slots=np.concatenate([attribute(doc,binary,attr[k]).astype(int) for k in ['JOINTS_0','JOINTS_1'] if k in attr],axis=1)
            skin_weights=np.concatenate([attribute(doc,binary,attr[k]).astype(float) for k in ['WEIGHTS_0','WEIGHTS_1'] if k in attr],axis=1)
            for side in shoes:
                active=[index for index,joint in enumerate(joint_ids) if doc['nodes'][joint].get('name','').endswith((side+'Foot',side+'ToeBase'))]
                selected=np.flatnonzero(np.sum(skin_weights*np.isin(slots,active),axis=1)>=.35)
                if not len(selected):continue
                shoes[side].append({'ids':[node_index,primitive_index], 'vertex_ids':selected,
                    'positions':np.c_[positions[selected],np.ones(len(selected))],
                    'slots':slots[selected],'weights':skin_weights[selected],'joint_ids':joint_ids,'binds':binds})
    if not all(shoes.values()):raise ValueError('No complete weighted shoe geometry')
    return shoes


def skin_shoes(shoes,worlds):
    result={}
    for side,pieces in shoes.items():
        points=[]
        for piece in pieces:
            matrices=np.asarray([worlds[index]@bind for index,bind in zip(piece['joint_ids'],piece['binds'])])
            out=np.zeros((len(piece['positions']),3))
            for influence in range(piece['slots'].shape[1]):
                selected=matrices[piece['slots'][:,influence],:3,:]
                out+=np.einsum('vij,vj->vi',selected,piece['positions'])*piece['weights'][:,influence,None]
            points.append(out)
        result[side]=np.concatenate(points)
    return result


def material_contact_metrics(points,source_contact,fps,maximum_y=.020):
    low=points[:,:,1]<=maximum_y
    # Same indexed material vertex through time, >=60ms low support. Keep
    # negative heights in coverage and report penetration independently.
    drift=[];velocity=[];durations=[];predicted_segments=0
    for vertex in range(points.shape[1]):
        for segment in parts(low[:,vertex]):
            if len(segment)<3 or (segment[-1]-segment[0])/fps<.06:continue
            path=points[segment,vertex][:,[0,2]]
            drift.append(float(np.linalg.norm(np.ptp(path,axis=0))))
            velocity.extend(np.linalg.norm(np.diff(path,axis=0)*fps,axis=-1).tolist())
            durations.append(float((segment[-1]-segment[0])/fps))
            predicted_segments+=bool(np.any(source_contact[segment]))
    return {'same_material_low_support_drift_m':stats(drift),'same_material_world_speed_mps':stats(velocity),
        'support_segment_seconds':stats(durations),'segments_overlapping_raw_model_contact':predicted_segments,
        'complete_original_shoe_vertices':int(points.shape[1]),'actual_minimum_y_m':float(points[:,:,1].min()),
        'below_zero_vertex_frame_fraction':float(np.mean(points[:,:,1]<0)),
        'low_support_definition':f'Same original vertex index; Y<={maximum_y*1000:g}mm; >=60ms; no gait-phase or fixed-speed assumption',
        'naturalness_pass':None}


def audit_target(character,clip_report,source,model_report):
    output=Path(character['output_glb']);original=Path(character['source_glb'])
    if digest(output)!=character['output_sha256'] or digest(original)!=character['source_sha256']:
        raise AssertionError('Target/source GLB changed')
    doc,binary=load_glb(output);base,basebinary=load_glb(original)
    for key in ['meshes','skins','nodes','images','textures','materials','scenes','scene']:
        if doc.get(key)!=base.get(key):raise AssertionError('Source geometry/rest payload changed:'+key)
    if binary[:len(basebinary)]!=basebinary or doc['animations'][:len(base['animations'])]!=base['animations']:
        raise AssertionError('Original binary or actions changed')
    animation=next(row for row in doc['animations'] if row['name']==clip_report['clip'])
    frames=len(source['qpos']);fps=float(source['fps']);times=np.arange(frames)/fps
    node_ids={node.get('name'):index for index,node in enumerate(doc['nodes'])}
    source_ids={str(name):i for i,name in enumerate(source['joint_names'])}
    idle=next(row for row in base['animations'] if row['name']=='idle')
    baseline,_=world_matrices(base,basebinary,idle,0.)
    rest,parents=world_matrices(base,basebinary)
    hips=node_ids['mixamorig:Hips'];rp=source['reference_global_positions'];rq=Rotation.from_quat(source['reference_global_quaternions_xyzw']).as_matrix()
    source_rot=Rotation.from_quat(source['global_quaternions_xyzw'].reshape(-1,4)).as_matrix().reshape(frames,34,3,3)
    root_id=source_ids['pelvis_skel'];forward=rq[root_id]@[0.,0.,1.];heading=math.atan2(forward[0],forward[2]);align=Rotation.from_rotvec([0.,-heading,0.]).as_matrix()
    target_lengths={};scales=[]
    for target_side,source_side in SIDES:
        target_points=[rest[node_ids['mixamorig:'+target_side+suffix]][:3,3] for suffix in ['UpLeg','Leg','Foot']]
        target_lengths[target_side]=[float(np.linalg.norm(target_points[1]-target_points[0])),float(np.linalg.norm(target_points[2]-target_points[1]))]
        src=[rp[source_ids[source_side+suffix]] for suffix in ['_hip_pitch_skel','_knee_skel','_ankle_roll_skel']]
        scales.append(sum(target_lengths[target_side])/(np.linalg.norm(src[1]-src[0])+np.linalg.norm(src[2]-src[1])))
    expected_root_scale=float(np.mean(scales))
    morph= morph_weights(doc,binary,animation,0.);shoes=shoe_geometry(doc,binary,morph)
    all_shoes={side:[] for side,_ in SIDES};all_world=[];bone_error=[];map_errors=collections.defaultdict(list)
    preservation=collections.defaultdict(list);root_errors=[];finger_ids=[]
    hand_ids=[node_ids['mixamorig:'+side+'Hand'] for side,_ in SIDES]
    for index in range(len(doc['nodes'])):
        parent=index
        while parent in parents:
            parent=parents[parent]
            if parent in hand_ids:finger_ids.append(index);break
    constant_ids=set(finger_ids+[node_ids['mixamorig:'+side+'Shoulder'] for side,_ in SIDES])
    baseline_local={index:(np.linalg.inv(baseline[parents[index]])@baseline[index]) for index in constant_ids}
    original_translations={index:np.asarray(node.get('translation',[0.,0.,0.]),float) for index,node in enumerate(base['nodes'])}
    for channel in animation['channels']:
        path=channel['target']['path'];index=channel['target']['node'];sampler=animation['samplers'][channel['sampler']]
        ts=read(doc,binary,sampler['input']).reshape(-1)
        if len(ts)!=frames or not np.allclose(ts,times,atol=1e-6,rtol=0):raise AssertionError('Target sample clock changed')
        if path=='translation' and index!=hips:raise AssertionError('Retarget adds nonroot translation')
        if path=='scale':raise AssertionError('Retarget adds scale animation')
    for frame,time in enumerate(times):
        worlds,_=world_matrices(doc,binary,animation,float(time));all_world.append(worlds)
        points=skin_shoes(shoes,worlds)
        for side in all_shoes:all_shoes[side].append(points[side])
        for side,_ in SIDES:
            for pair,length in zip([['UpLeg','Leg'],['Leg','Foot']],target_lengths[side]):
                a,b=[worlds[node_ids['mixamorig:'+side+suffix]][:3,3] for suffix in pair]
                bone_error.append(abs(float(np.linalg.norm(a-b))-length))
        expected_root=baseline[hips][:3,3]+expected_root_scale*(align@(source['global_positions'][frame,root_id]-rp[root_id]))
        root_errors.append(float(np.linalg.norm((worlds[hips][:3,3]-expected_root)[[0,2]])))
        for target_name,source_name in [('Hips','pelvis_skel'),('Spine2','waist_pitch_skel')]+[
            (ts+suffix,ss+src_suffix) for ts,ss in SIDES for suffix,src_suffix in [('Arm','_shoulder_yaw_skel'),('ForeArm','_elbow_skel'),('Hand','_wrist_yaw_skel')]]:
            index=node_ids['mixamorig:'+target_name];src_index=source_ids[source_name]
            source_delta=align@source_rot[frame,src_index]@rq[src_index].T@align.T
            expected=source_delta@baseline[index][:3,:3]
            map_errors[target_name].append(float(rotation_error(expected[None],worlds[index][:3,:3][None])[0]))
        for index in constant_ids:
            local=np.linalg.inv(worlds[parents[index]])@worlds[index]
            preservation['local_position_m'].append(float(np.linalg.norm(local[:3,3]-original_translations[index])))
            preservation['local_rotation_deg'].append(float(rotation_error(baseline_local[index][None,:3,:3],local[None,:3,:3])[0]))
            preservation['local_scale_delta'].append(float(np.linalg.norm(np.linalg.norm(local[:3,:3],axis=0)-np.linalg.norm(baseline_local[index][:3,:3],axis=0))))
    if max(bone_error)>.00001 or max(root_errors)>.00005 or max(max(v) for v in map_errors.values())>.03:
        raise AssertionError('Target mapping/root/bone-length invariant failed')
    if max(preservation['local_position_m'])>.00005 or max(preservation['local_rotation_deg'])>.03 or max(preservation['local_scale_delta'])>.0001:
        raise AssertionError('Target neutral fingers/shoulders local articulation changed')
    contacts=source['foot_contacts'];quality={}
    for column,(side,_) in enumerate(SIDES):
        points=np.asarray(all_shoes[side]);raw_mask=np.any(contacts[:,column*2:column*2+2]>.5,axis=1)
        quality[side]=material_contact_metrics(points,raw_mask,fps)
        quality[side]['near_ground_7mm_sensitivity']=material_contact_metrics(points,raw_mask,fps,.007)
        quality[side]['contact_truth_note']='Both are geometric low-height windows, not physical force/contact truth;20mm includes rolling/lift margins,7mm tests near5mm target floor without conditioning on low velocity.'
    audit_path=Path(clip_report['audit_npz'])
    if digest(audit_path)!=clip_report['audit_npz_sha256']:raise AssertionError('Retarget correction receipt changed')
    arrays=source_arrays(audit_path)
    semantic_names=[str(name) for name in arrays['semantic_joint_names']]
    actual_positions=np.asarray([[worlds[node_ids['mixamorig:'+name]][:3,3] for name in semantic_names] for worlds in all_world])
    stored_errors=np.linalg.norm(actual_positions-arrays['final_global_positions'],axis=-1)
    if stored_errors.max()>.00005:raise AssertionError('Retarget NPZ differs from actual serialized GLB pose')
    correction=np.linalg.norm(actual_positions-arrays['raw_global_positions'],axis=-1)
    mode=str(source['mode'])
    observations=[]
    for side in quality:
        row=quality[side]
        if row['actual_minimum_y_m']<0:observations.append(f'{side} complete shoe crossesY=0; depth={-row["actual_minimum_y_m"]:.6f}m')
        if row['same_material_low_support_drift_m']['count']==0:observations.append(f'{side} no>=60ms low-material support window; contact quality is unqualified')
    return {'character':character['character'],'clip':clip_report['clip'],'source_motion_id':clip_report['motion_id'],
        'frames':frames,'fps':fps,'all_frames_original_GLTF_accessor_FK_and_full_morph_skin_evaluated':True,
        'root_horizontal_error_m':stats(root_errors),'independently_measured_leg_scale_mean':expected_root_scale,
        'bone_length_error_m':stats(bone_error),'active_source_to_target_world_rotation_errors_deg':{k:stats(v) for k,v in map_errors.items()},
        'neutral_local_preservation':{'finger_bones':len(finger_ids),'clavicle_bones':2,**{k:stats(v) for k,v in preservation.items()}},
        'actual_GLTF_vs_stored_final_pose_error_m':stats(stored_errors),'raw_calibrated_to_actual_final_joint_correction_m':stats(correction),
        'root_vertical_retarget_correction_m':stats(arrays['retarget_root_y_correction']),
        'contact_lock_ankle_goal_correction_m':stats(np.linalg.norm(arrays['contact_locked_ankle_goals']-arrays['source_scaled_ankle_goals'],axis=-1)),
        'complete_same_material_shoe_quality':quality,'source_mode':mode,'observations':observations,
        'original_binary_mesh_skin_rest_morph_UV_textures_and_all_original_actions_exact':True,
        'technical_invariants_pass':True,'artistic_naturalness_pass':None,
        'scope':'Source naming/axis/scale/root and serialization invariants qualified; contact drift/correction size are observations, never automatic art acceptance.'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir',type=Path,required=True)
    parser.add_argument('--retarget-manifest',type=Path)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--skeleton-xml',type=Path,default=VENDOR/'motionbricks/assets/skeletons/g1/g1.xml')
    parser.add_argument('--characters',nargs='+')
    parser.add_argument('--motions',nargs='+',help='Source NPZ stems')
    args=parser.parse_args();folder=args.source_dir.resolve();out=args.out.resolve()
    if out.exists():raise ValueError('Preserve completed evidence, choose a new audit output')
    original_hashes={p.name:digest(p) for p in sorted((ROOT/'game/assets/models').glob('CH_*.glb'))}
    result={'scope':'Read-only independent POC source/native-FK/retarget audit; no inference/render/physics rollout','status':'auditing','auditor_sha256':digest(Path(__file__)),'source':[],'retargeted':[],'failures':[],'artistic_naturalness_pass':None}
    try:
        result['provenance']=source_provenance(folder)
        model,mapping,result['independent_native_model']=kinematic_mujoco_model(args.skeleton_xml)
        paths=[folder/(name+'.npz') for name in args.motions] if args.motions else sorted(folder.glob('*.npz'))
        if not paths:raise ValueError('No actual source motions')
        sources={}
        for path in paths:
            source,report=audit_source(path,model,mapping);sources[path.stem]=source;result['source'].append(report)
        if args.retarget_manifest:
            manifest=load_json(args.retarget_manifest)
            if not manifest['production_models_unchanged'] or manifest['source_model_hashes_before']!=manifest['source_model_hashes_after']:
                raise AssertionError('Writer reported production mutation')
            result['retarget_manifest_sha256']=digest(args.retarget_manifest)
            for character in manifest['characters']:
                if args.characters and character['character'] not in args.characters:continue
                for clip in character['clips']:
                    if clip['motion_id'] not in sources:continue
                    result['retargeted'].append(audit_target(character,clip,sources[clip['motion_id']],result['independent_native_model']))
            if not result['retargeted']:raise ValueError('No selected retarget clips audited')
        result['status']='technical-invariants-qualified-artistic-quality-not-automatically-accepted'
    except Exception as error:
        import traceback
        result['status']='incomplete-or-failed-technical-audit'
        result['failures'].append({'error':repr(error),'traceback':traceback.format_exc()})
    finally:
        after={p.name:digest(p) for p in sorted((ROOT/'game/assets/models').glob('CH_*.glb'))}
        result['production_models_before']=original_hashes;result['production_models_after']=after
        result['production_models_unchanged']=original_hashes==after
        if original_hashes!=after:result['failures'].append({'error':'Production seven-model hashes changed'})
        out.parent.mkdir(parents=True,exist_ok=True)
        out.write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
    print(json.dumps({'status':result['status'],'source_motions':len(result['source']),
        'target_clips':len(result['retargeted']),'failures':len(result['failures']),'out':str(out)},ensure_ascii=False))
    if result['failures']:raise SystemExit(1)


if __name__=='__main__':main()

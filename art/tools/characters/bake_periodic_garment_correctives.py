"""Bake periodic POSITION/NORMAL targets from hash-bound solved field inputs.

Inputs are a source GLB, references/controls.json, poses.json and per-reference
NPZ files containing rest_delta/base/posed. No solver is imported or executed.
This reconstructs the bake stage, not the original field optimization or its
native acceptance. Run the separate lossless packer afterwards if desired.
"""
import os
for key in ['OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','VECLIB_MAXIMUM_THREADS']:
    os.environ[key]='1'
from pathlib import Path
import json,copy,argparse
import numpy as np
from scipy.spatial import cKDTree
from glb_io import load
from prepare_local_garments import read
from repair_head_neck import append,save
from audit_local_garments import mesh_state,pose
from garment_bake_support import actual_skin_basis, digest, circular_weights, circular_weights_batch, complete_source_domain, extend_original_curve
from corrective_normals import unit,geometry_normals,rotate_between,angle

def main(args):
    expected=args.expected_source_sha256
    if digest(args.input)!=expected:
        raise ValueError('Source GLB SHA256 does not match the explicit expected identity')
    state=mesh_state(args.input,args.character)
    source,binary=state['d'],state['b']
    controls_path=args.controls/('references.json' if args.curve_policy=='resample' else 'controls.json')
    controls=json.loads(controls_path.read_text())
    if controls['source_sha256']!=expected:
        raise ValueError('Solved reference source identity does not match the GLB')
    references=sorted([r for r in controls['references' if args.curve_policy=='resample' else 'frames'] if r['clip'] in args.clip],key=lambda r:(r['clip'],r['phase']))
    if not references or {r['clip'] for r in references}!=set(args.clip):
        raise ValueError('Every explicitly selected clip needs solved references')
    if any(not r['diagnostics']['found_conservative_gate_passing_candidate'] for r in references):
        raise ValueError('Refuse to package a failed source reference')
    if args.curve_policy=='zero' and any(not r['full_solver_profile_original_gate_pass'] for r in references):
        raise ValueError('Zero-source format requires its original profile gate result')
    for clip in args.clip:
        phases=np.array([r['phase'] for r in references if r['clip']==clip])
        if len(phases)<2 or phases[0]<0 or phases[-1]>=1 or not np.all(np.diff(phases)>0):
            raise ValueError('Each clip requires unique sorted phases in [0,1)')
    pose_document=json.loads((args.controls/'poses.json').read_text())
    if pose_document['source_sha256']!=expected:
        raise ValueError('Pose source identity does not match')
    if 'native_sha256' in controls and pose_document.get('native_sha256')!=controls['native_sha256']:
        raise ValueError('Controls and poses name different native captures')
    poses=pose_document['poses']
    document=copy.deepcopy(source);buffer=bytearray(binary)
    node=document['nodes'][state['ni']];mesh=document['meshes'][node['mesh']]
    primitive=mesh['primitives'][0];attrs=primitive['attributes']
    faces=read(source,binary,primitive['indices']).reshape(-1,3)
    normals=unit(read(source,binary,attrs['NORMAL']))
    old_count=len(state['names'])
    old_dn=[unit(normals+read(source,binary,target['NORMAL']))-normals if 'NORMAL' in target else np.zeros_like(normals) for target in primitive['targets']]
    complete_faces,support,complete_counts=complete_source_domain(state,args.colour)
    pairs=cKDTree(state['positions']).query_pairs(1e-6,output_type='ndarray')
    args.out.mkdir(parents=True,exist_ok=False)
    report={'scope':__doc__,'source_sha256':expected,'controls_sha256':digest(controls_path),'poses_sha256':digest(args.controls/'poses.json'),
        'tool_sha256':digest(__file__),'normal_policy':'Actual geometric-normal rotation with unit-target equation, authored hard-edge shading preserved. Dense shader/native review remains necessary.',
        'shapes':[],'zero_reference_knots':[],'curves':[],'complete_cloth_source_domain':complete_counts}
    target_indices={}
    for ref in references:
        clip,phase=ref['clip'],ref['phase']
        data=np.load(args.controls/ref['file'])
        delta=data['rest_delta'].astype(np.float32)
        if not np.any(delta) and args.curve_policy=='resample':
            report['zero_reference_knots'].append({'clip':clip,'phase':phase,'reference_npz_sha256':digest(args.controls/ref['file'])})
            continue
        row=next(r for r in poses if r['clip']==clip and abs(r['phase']-phase)<1e-10)
        table=row['blend_shape_values'][state['node']['name']]
        values=np.array([table[n] for n in state['names']]);values[state['local']]=0
        base,_=pose(state,clip,row['clip_time'],row,actual_shapes=True,disable_local=True)
        B=actual_skin_basis(state,row)
        actual=base+np.einsum('nij,nj->ni',B,delta)
        assert np.max(np.linalg.norm(base-data['base'],axis=1))<1e-10
        assert np.max(np.linalg.norm(actual-data['posed'],axis=1))<1e-7
        assert not np.any(delta[state['body']]) and not np.any(delta[~support])
        normal=normals.copy()
        for value,dn in zip(values,old_dn):
            normal+=value*dn
        moved=np.linalg.norm(delta,axis=1)>1e-8
        affected=np.zeros(len(delta),bool);affected[np.unique(faces[np.any(moved[faces],axis=1)])]=True
        affected&=support
        old_render=unit(np.einsum('nij,nj->ni',B,unit(normal)))
        wanted_render=unit(rotate_between(geometry_normals(base,faces),geometry_normals(actual,faces),old_render))
        wanted_rest=unit(np.einsum('nij,nj->ni',np.linalg.pinv(B),wanted_render))
        offset=normals-normal;along=np.sum(offset*wanted_rest,axis=1)
        disc=along*along+1-np.sum(offset*offset,axis=1)
        dn=unit(offset+(-along+np.sqrt(np.maximum(disc,0)))[:,None]*wanted_rest)-normals
        dn[~affected]=0
        assert not np.any(dn[state['body']])
        rendered=unit(np.einsum('nij,nj->ni',B,unit(normal+unit(normals+dn)-normals)))
        normal_error=angle(rendered[affected],wanted_render[affected])
        name=f'{args.prefix}{clip}_{round(phase*1000000):06d}'
        if name in mesh['extras']['targetNames']:
            raise ValueError('New target name already exists: '+name)
        target_indices[(clip,phase)]=len(primitive['targets'])
        primitive['targets'].append({'POSITION':append(document,buffer,attrs['POSITION'],delta),
                                    'NORMAL':append(document,buffer,attrs['NORMAL'],dn.astype(np.float32))})
        mesh['extras']['targetNames'].append(name)
        report['shapes'].append({'name':name,'clip':clip,'phase':phase,
            'world_shift_max_m':float(np.linalg.norm(actual-base,axis=1).max()),
            'reference_npz_sha256':digest(args.controls/ref['file']),
            'physical_uv_position_delta_gap_m':float(np.linalg.norm(delta[pairs[:,0]]-delta[pairs[:,1]],axis=1).max()),
            'body_POSITION_NORMAL_delta_max_m':0.,'out_of_support_POSITION_NORMAL_delta_max_m':0.,
            'unreachable_unit_normal_count':int(((disc<0)&affected).sum()),
            'normal_equation_error_max_deg':float(normal_error.max(initial=0)),
            'float32_reconstruction_error_max_m':float(np.linalg.norm(actual-data['posed'],axis=1).max())})
    new_count=len(mesh['extras']['targetNames']);added=new_count-old_count
    mesh['weights']=list(mesh.get('weights',[0.]*old_count))+[0.]*added
    if 'weights' in node:node['weights']+=[0.]*added
    for animation,original in zip(document['animations'],source['animations']):
        for channel in animation['channels']:
            if channel['target']!={'node':state['ni'],'path':'weights'}:continue
            sampler=animation['samplers'][channel['sampler']]
            assert sampler.get('interpolation','LINEAR')=='LINEAR'
            previous=read(source,binary,sampler['output']).reshape(-1,old_count)
            old_times=read(source,binary,sampler['input']).ravel()
            times=old_times.copy();old_values=previous.copy()
            replacement=dict(sampler)
            if animation['name'] in args.clip:
                duration=max(float(read(source,binary,s['input']).max()) for s in original['samplers'])
                refs=[r for r in references if r['clip']==animation['name']]
                knot_times=np.array([r['phase']*duration for r in refs],dtype=np.float32)
                if args.curve_policy=='zero':
                    if np.any(previous):
                        raise ValueError('Zero-source curve policy cannot discard an existing nonzero column')
                    times=np.unique(np.r_[old_times,np.array([r['phase'] for r in refs])*duration,0.,duration].astype(np.float32))
                    old_values=np.zeros((len(times),old_count),np.float32)
                    curve_error={'old_weight_function_max_absolute_error':0.,'maximum_f32_ulp_error':0.}
                else:
                    times,old_values,curve_error=extend_original_curve(old_times,previous,knot_times,state['shapes'])
                if not np.array_equal(times,old_times):
                    replacement['input']=append(document,buffer,sampler['input'],times[:,None])
                expanded=np.c_[old_values,np.zeros((len(times),added),np.float32)]
                phases=[r['phase'] for r in refs]
                if args.curve_policy=='zero':
                    weights=circular_weights_batch(phases,times/duration)
                    for ref,values in zip(refs,weights.T):
                        expanded[:,target_indices[(ref['clip'],ref['phase'])]]=values.astype(np.float32)
                else:
                    for index,at in enumerate(times/duration):
                        weights=circular_weights(phases,at)
                        for ref,value in zip(refs,weights):
                            target=target_indices.get((ref['clip'],ref['phase']))
                            if target is not None:expanded[index,target]=value
                report['curves'].append({'clip':animation['name'],'knots':phases,
                    'old_times_exact_payload_preserved':bool(np.array_equal(times,old_times)),'old_function_f32_error_bound':curve_error,
                    'old_curve_identically_zero':bool(not np.any(previous)),
                    'old_timestamp_rows_all_retained':bool(np.all(np.isin(old_times,times))),
                    'new_max_active_targets':int((expanded[:,old_count:]>1e-7).sum(1).max()),
                    'endpoint_new_weight_gap':float(abs(expanded[0,old_count:]-expanded[-1,old_count:]).max())})
            else:
                expanded=np.c_[previous,np.zeros((len(previous),added),np.float32)]
            replacement['output']=append(document,buffer,sampler['output'],expanded.reshape(-1,1))
            channel['sampler']=len(animation['samplers']);animation['samplers'].append(replacement)
    rig=next(n for n in document['nodes'] if n.get('name')=='Rig')
    rig.setdefault('extras',{})['garment_phase_drape']={'source_sha256':expected,'clips':sorted(set(args.clip)),
        'controls_sha256':digest(controls_path),'curves':report['curves'],
        'scope':'Candidate source periodic corrections; dense actual-source, residual, native visual and performance acceptance pending.'}
    output=args.out/args.output_name;save(document,buffer,output)
    verified,vb=load(output)
    for index in range(len(source['accessors'])):
        assert np.array_equal(read(source,binary,index),read(verified,vb,index)),index
    for old,new in zip(source['animations'],verified['animations']):
        for oc,nc in zip(old['channels'],new['channels']):
            assert oc['target']==nc['target']
            osamp=old['samplers'][oc['sampler']];nsamp=new['samplers'][nc['sampler']]
            ot=read(source,binary,osamp['input']).ravel();nt=read(verified,vb,nsamp['input']).ravel()
            ov=read(source,binary,osamp['output']);nv=read(verified,vb,nsamp['output'])
            if oc['target']=={'node':state['ni'],'path':'weights'}:
                ov=ov.reshape(-1,old_count);nv=nv.reshape(-1,new_count)
                for at,value in zip(ot,ov):
                    assert np.array_equal(nv[np.flatnonzero(nt==at)[0],:old_count],value)
                if not np.array_equal(ot,nt):
                    if args.curve_policy=='zero' and old['name'] in args.clip:
                        assert not np.any(ov) and not np.any(nv[:,:old_count])
                    else:
                        _,resampled,bound=extend_original_curve(ot,ov,nt,state['shapes'])
                        assert np.array_equal(resampled,nv[:,:old_count])
                        assert bound['maximum_f32_ulp_error']<=1.
                if old['name'] not in args.clip:assert np.array_equal(ot,nt) and not np.any(nv[:,old_count:])
            else:
                assert np.array_equal(ot,nt) and np.array_equal(ov,nv)
    report.update({'output_sha256':digest(output),'all_old_decoded_accessors_exact':True,
        'all_old_key_time_value_payloads_exact':True,'all_old_shape_curve_functions_exact':all(c['old_function_f32_error_bound']['old_weight_function_max_absolute_error']==0 for c in report['curves']),'all_skeletal_tracks_exact':True,'new_target_count':added,
        'new_targets_only_explicit_clips':sorted(set(args.clip)),'dense_float32_POSITION_NORMAL_storage_bytes_upper_estimate':int(len(state['positions'])*new_count*6*4),'storage_estimate_scope':'Raw six-float per vertex per morph upper estimate only; actual Godot GPU allocation and native frame time remain to measure'})
    (args.out/'manifest.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--controls',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--expected-source-sha256',required=True)
    parser.add_argument('--character',choices=['mio','kazuko'],required=True,help='Original fixed-body classification policy')
    parser.add_argument('--colour',choices=['blue','yellow'],required=True,help='Independent complete painted-cloth policy')
    parser.add_argument('--curve-policy',choices=['resample','zero'],required=True,help='resample: references.json and bounded old f32 curves; zero: controls.json and all old selected-clip columns must be zero')
    parser.add_argument('--clip',action='append',required=True)
    parser.add_argument('--output-name',default='character.glb')
    parser.add_argument('--prefix',default='GarmentDrape_')
    args=parser.parse_args()
    if Path(args.output_name).name!=args.output_name:parser.error('--output-name must be a filename')
    main(args)

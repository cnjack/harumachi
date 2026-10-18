"""Regression checks against actual source/output GLBs, independent of manifests.

Run with --after-dir equal to --before-dir to demonstrate that the original
assets fail the new body/finger checks. This does not run or claim Godot QA.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from scipy.spatial import cKDTree
from repair_joint_fit import PEOPLE, HANDS, FINGERS, P, RAYS, load, read, parts, triangles, world_matrices, ray_inside, leg_targets, shoulder_target, diagnose, hand_frame, hand_cloud


def accessor_payload(doc,blob,index):
    accessor=doc['accessors'][index];views=[]
    if 'bufferView' in accessor:views.append(accessor['bufferView'])
    if 'sparse' in accessor:
        views.extend([accessor['sparse']['indices']['bufferView'],accessor['sparse']['values']['bufferView']])
    output=json.dumps(accessor,sort_keys=True).encode()
    for i in views:
        view=doc['bufferViews'][i];start=view.get('byteOffset',0);output+=bytes(blob[start:start+view['byteLength']])
    return output


def protected_payloads(doc,blob):
    result=[]
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            result.append(('indices',read(doc,blob,primitive['indices']).tobytes()))
            for key,index in primitive['attributes'].items():
                if key.startswith(('JOINTS_','WEIGHTS_')):continue
                result.append((key,read(doc,blob,index).tobytes()))
            for target in primitive.get('targets',[]):
                for key,index in target.items():result.append(('morph_'+key,accessor_payload(doc,blob,index)))
    for image in doc.get('images',[]):
        view=doc['bufferViews'][image['bufferView']];start=view.get('byteOffset',0)
        result.append(('image',bytes(blob[start:start+view['byteLength']])))
    for animation in doc.get('animations',[]):
        for channel in animation['channels']:
            sampler=animation['samplers'][channel['sampler']]
            result.append(('time_'+animation['name'],read(doc,blob,sampler['input']).tobytes()))
            if channel['target']['path']=='weights':result.append(('morph_animation',read(doc,blob,sampler['output']).tobytes()))
    return result


def finger_scope(a,ab,d,b,who,old,new):
    allowed={i for i,n in enumerate(a['nodes']) if n.get('name') in
             {P+side+'Hand'+finger+str(k) for side in HANDS.get(who,[]) for finger in FINGERS for k in [1,2,3]}}
    preserved_nodes=0;preserved_binds=0;preserved_channels=0
    assert len(a['nodes'])==len(d['nodes']) and len(a['skins'])==len(d['skins'])
    for i,(source,target) in enumerate(zip(a['nodes'],d['nodes'])):
        if i in allowed:
            assert {k:v for k,v in source.items() if k not in ['translation','rotation','scale']}=={k:v for k,v in target.items() if k not in ['translation','rotation','scale']}
        elif source.get('name')=='Rig':
            assert {k:v for k,v in source.items() if k!='extras'}=={k:v for k,v in target.items() if k!='extras'}
            for key,value in source.get('extras',{}).items():assert target['extras'].get(key)==value,who+': upstream Rig provenance overwritten'
            preserved_nodes+=1
        else:
            assert source==target,who+': non-finger node JSON changed: '+str(source.get('name'))
            preserved_nodes+=1
    for source,target in zip(a['skins'],d['skins']):
        assert source['joints']==target['joints']
        sa=read(a,ab,source['inverseBindMatrices']);ta=read(d,b,target['inverseBindMatrices'])
        selected=[i for i,node in enumerate(source['joints']) if node not in allowed]
        assert sa[selected].tobytes()==ta[selected].tobytes(),who+': non-finger inverse-bind row changed'
        preserved_binds+=len(selected)
    for source,target in zip(a['animations'],d['animations']):
        assert source['name']==target['name'] and len(source['channels'])==len(target['channels'])
        for sc,tc in zip(source['channels'],target['channels']):
            assert sc==tc,who+': animation channel map changed'
            if sc['target']['node'] in allowed and sc['target']['path'] in ['translation','rotation']:continue
            ss=source['samplers'][sc['sampler']];ts=target['samplers'][tc['sampler']]
            assert ss==ts,who+': non-finger animation sampler JSON changed'
            for key in ['input','output']:assert accessor_payload(a,ab,ss[key])==accessor_payload(d,b,ts[key]),who+': protected animation accessor changed'
            preserved_channels+=1
    protected_vertices=0;mutable_vertices=0;maximum_other_influence_error=0.;outside_finger_mass=0.
    for source,target in zip(old,new):
        family=[i for i,name in enumerate(source['names']) if any(name.startswith(P+side+'Hand') for side in HANDS.get(who,[]))]
        mutable=source['dense'][:,family].sum(1)>.5
        outside=~mutable;protected_vertices+=int(outside.sum());mutable_vertices+=int(mutable.sum())
        assert np.array_equal(source['ids'][outside],target['ids'][outside]) and np.array_equal(source['weights'][outside],target['weights'][outside]),who+': skin outside selected hands changed'
        other=[i for i in range(len(source['joints'])) if i not in family]
        error=float(np.max(abs(source['dense'][:,other]-target['dense'][:,other]),initial=0));maximum_other_influence_error=max(maximum_other_influence_error,error)
        assert error<2e-7,who+': non-hand skin influence changed'
        finger_ids=[i for i,node in enumerate(source['joints']) if node in allowed]
        mass=float(np.max(source['dense'][outside][:,finger_ids].sum(1),initial=0));outside_finger_mass=max(outside_finger_mass,mass)
    # Some source finger weights already reach the wrist/forearm and even a
    # sleeve's fringe. Their source rows stay exact, but changed finger pivots
    # can change their posed surface. Record that limitation and measure the
    # actual clip effect below, rather than claiming a false all-body proof.
    return {'allowed_finger_bones':len(allowed),'nonfinger_node_JSON_exact_except_added_Rig_metadata':preserved_nodes,
            'nonfinger_inverse_bind_rows_byte_exact':preserved_binds,'protected_animation_samplers_and_accessor_payloads_exact':preserved_channels,
            'vertices_outside_hands_with_exact_skin_rows':protected_vertices,'selected_hand_vertices':mutable_vertices,
            'maximum_nonhand_influence_rounding_error':maximum_other_influence_error,'maximum_changed_finger_influence_outside_hands':outside_finger_mass,
            'body_deformation_scope':'non-finger bones/binds and protected skin rows exact; existing finger-influence fringe measured in authored samples'}


def authored_scope(a,ab,d,b,who,old):
    from audit_joint_fit import animated_parts
    from prepare_local_garments import colours
    from prepare_sleeve_weights import cloth_mask
    from scipy.spatial.transform import Rotation
    samples=[];fringe=[];maximum_angles={'source_thumb_deg':0.,'candidate_thumb_deg':0.,'source_long_finger_deg':0.,'candidate_long_finger_deg':0.}
    for label,doc,blob in [('source',a,ab),('candidate',d,b)]:
        for animation in doc['animations']:
            for channel in animation['channels']:
                if channel['target']['path']!='rotation':continue
                node=doc['nodes'][channel['target']['node']];name=node.get('name','')
                if not any(name.startswith(P+side+'Hand'+finger) for side in ['Left','Right'] for finger in FINGERS):continue
                sampler=animation['samplers'][channel['sampler']];values=read(doc,blob,sampler['output'])
                relative=Rotation.from_quat(node.get('rotation',[0,0,0,1])).inv()*Rotation.from_quat(values)
                key=label+('_thumb_deg' if 'Thumb' in name else '_long_finger_deg')
                maximum_angles[key]=max(maximum_angles[key],float(np.degrees(relative.magnitude()).max()))
    assert abs(maximum_angles['source_thumb_deg']-maximum_angles['candidate_thumb_deg'])<.0001
    assert abs(maximum_angles['source_long_finger_deg']-maximum_angles['candidate_long_finger_deg'])<.0001
    height=max(float(p['raw'][:,1].max()) for p in old)
    for clip,phase in [('idle',0),('walk',.625),('run',.625),('wave',.875),('stretch',.625)]:
        source_anim=next(x for x in a['animations'] if x['name']==clip);anim=next(x for x in d['animations'] if x['name']==clip)
        duration=max(float(read(a,ab,s['input']).max()) for s in source_anim['samplers'])
        before=animated_parts(a,ab,source_anim,duration*phase);after=animated_parts(d,b,anim,duration*phase)
        maximum_fringe=0.;maximum_cloth=0.
        for rest,source,target in zip(old,before,after):
            family=[i for i,name in enumerate(rest['names']) if any(name.startswith(P+s+'Hand') for s in HANDS.get(who,[]))]
            protected=rest['dense'][:,family].sum(1)<=.5;displacement=np.linalg.norm(target['xyz']-source['xyz'],axis=1)
            maximum_fringe=max(maximum_fringe,float(np.max(displacement[protected],initial=0)))
            colour=colours(a,ab,rest['primitive']);skin=(colour[:,0]>colour[:,1]*1.10)&(colour[:,1]>colour[:,2]*1.02)&(colour[:,0]>.30)
            selected_colour=cloth_mask(who,colour) if who!='ren' else ~skin
            # Pale finger skin can satisfy Aoi's white-blouse colour. The hand
            # selection and upper-body band must exclude that false clothing.
            cloth=selected_colour&~skin&protected&(rest['xyz'][:,1]>.52*height)
            maximum_cloth=max(maximum_cloth,float(np.max(displacement[cloth],initial=0)))
        fringe.append({'clip':clip,'phase':phase,'maximum_existing_finger_influence_fringe_displacement_m':maximum_fringe,'maximum_colour_selected_cloth_displacement_m':maximum_cloth})
        if clip not in ['idle','wave']:continue
        for side in HANDS.get(who,[]):
            seam_gap=0.;before_ratios=[];after_ratios=[];count=0
            for rest,source,target in zip(old,before,after):
                family=[i for i,name in enumerate(rest['names']) if name.startswith(P+side+'Hand')]
                chosen=rest['dense'][:,family].sum(1)>.999;selected=np.where(chosen)[0]
                pairs=cKDTree(rest['xyz'][selected]).query_pairs(2e-6,output_type='ndarray');pairs=selected[pairs]
                if len(pairs):seam_gap=max(seam_gap,float(np.linalg.norm(target['xyz'][pairs[:,0]]-target['xyz'][pairs[:,1]],axis=1).max()))
                f=rest['faces'];edges=np.unique(np.sort(np.r_[f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]],axis=1),axis=0)
                lengths=np.linalg.norm(rest['xyz'][edges[:,1]]-rest['xyz'][edges[:,0]],axis=1)
                eligible=chosen[edges].all(1)&(lengths>.001)&(lengths<.03);edges=edges[eligible];lengths=lengths[eligible];count+=int(chosen.sum())
                if len(edges):
                    before_ratios.extend(np.linalg.norm(source['xyz'][edges[:,1]]-source['xyz'][edges[:,0]],axis=1)/lengths)
                    after_ratios.extend(np.linalg.norm(target['xyz'][edges[:,1]]-target['xyz'][edges[:,0]],axis=1)/lengths)
            assert seam_gap<2e-6,who+': actual authored clip opens a hand seam'
            samples.append({'side':side,'clip':clip,'phase':phase,'evaluated_with_actual_morph_streams':True,'hand_vertices':count,'UV_seam_gap_m':seam_gap,
                            'source_hand_edge_length_ratio_p99':float(np.percentile(before_ratios,99)),
                            'candidate_hand_edge_length_ratio_p99':float(np.percentile(after_ratios,99))})
    return {'hands':samples,'maximum_authored_joint_angles':maximum_angles,'existing_influence_fringe':fringe,'scope':'actual authored GLB bones and morph streams; colour-selected upper clothing diagnostic; not runtime final-pose proof'}


def verify(source_dir,output_dir,scope,people,ren_shoulders=False,authored_hands=False):
    rows=[]
    for who in people:
        a,ab=load(source_dir/('CH_'+who+'.glb'));d,b=load(output_dir/('CH_'+who+'.glb'))
        assert protected_payloads(a,ab)==protected_payloads(d,b),who+': source geometry/UV/image/morph/timing modified'
        old=parts(a,ab);new=parts(d,b);maximum=max(float(np.linalg.norm(x['xyz']-y['xyz'],axis=1).max()) for x,y in zip(old,new))
        assert maximum<2e-6,who+': rest surface changed'
        for part in new:
            assert np.max(abs(part['weights'].sum(axis=1)-1))<1e-5 and part['weights'].min()>=0,who+': invalid normalized weight'
            assert part['ids'].max()<len(part['joints']),who+': invalid joint index'
        row={'character':who,'rest_surface_max_error_m':maximum}
        w,_=world_matrices(d,b);names={n.get('name'):i for i,n in enumerate(d['nodes'])}
        if scope in ['body','both']:
            # Body stage must keep the accepted skin semantics byte-identical.
            if scope=='body':
                for x,y in zip(old,new):
                    assert np.array_equal(x['ids'],y['ids']) and np.array_equal(x['weights'],y['weights']),who+': body-only changed skin weights'
            if who in ['tanaka','sora']:
                tri=triangles(new)
                for side in ['Left','Right']:
                    point=w[names[P+side+'ForeArm']][:3,3]
                    assert all(ray_inside(tri,point,r) for r in RAYS),who+': elbow not inside shell'
            if who in ['sora','ren','aoi','tanaka','kazuko']:
                targets,details=leg_targets(new,w,names,who)
                delta=max([v['offset_m'] for v in details.values()]+[0])
                # A fitted knee/ankle must coincide with the measured section;
                # checking mere containment misses the original 5 cm error.
                assert delta<.004,who+': leg pivot off shell center by '+str(delta)
                row['maximum_leg_center_residual_m']=delta
            if ren_shoulders and who=='ren':
                residual=[]
                for side in ['Left','Right']:
                    target,detail=shoulder_target(new,w,names,side,factors=(1.05,1.1,1.15),maximum_drop=.15)
                    error=float(np.linalg.norm(target-w[names[P+side+'Arm']][:3,3]));residual.append(error)
                    assert error<.004,who+': shoulder off upper-arm tube center by '+str(error)
                row['maximum_shoulder_center_residual_m']=max(residual)
                asymmetry=abs(w[names[P+'LeftArm']][1,3]-w[names[P+'RightArm']][1,3])
                assert asymmetry<.001,who+': asymmetric shoulder heads on symmetric upper-arm shell'
                row['shoulder_height_asymmetry_m']=float(asymmetry)
        if scope in ['fingers','both']:
            from audit_joint_fit import curl_world
            if scope=='fingers':row['composition_preservation']=finger_scope(a,ab,d,b,who,old,new)
            numeric=diagnose(d,b);bad={name:v for name,v in numeric['fingers'].items() if v['vertices_over_025']<4 or v['vertices_moving_over_1mm']<4}
            assert not bad,who+': functionally unbound fingers '+str(bad)
            row['meaningfully_weighted_finger_joints']=len(numeric['fingers'])
            tri=triangles(new);inside_counts=[];curl_displacements=[];seam_gaps=[]
            for side in HANDS.get(who,[]):
                wrist=w[names[P+side+'Hand']][:3,3]
                _,_,_,palm_normal=hand_frame(d,w,names,side,hand_cloud(new,side))
                curled=curl_world(d,b,side,10)
                # Coincident UV vertices on a hand must stay coincident when
                # curled. Otherwise smooth-looking weights can open a seam.
                seam_pairs=[]
                for part in new:
                    family=[i for i,name in enumerate(part['names']) if name.startswith(P+side+'Hand')]
                    selected=np.where(part['dense'][:,family].sum(axis=1)>.999)[0]
                    pairs=np.array(list(cKDTree(part['xyz'][selected]).query_pairs(2e-6)),dtype=int).reshape(-1,2)
                    seam_pairs.append(selected[pairs])
                for amount in [35,65]:
                    posed=parts(d,b,curl_world(d,b,side,amount))
                    for part,pairs in zip(posed,seam_pairs):
                        if not len(pairs):continue
                        gap=float(np.linalg.norm(part['xyz'][pairs[:,0]]-part['xyz'][pairs[:,1]],axis=1).max())
                        assert gap<2e-6,who+': curled hand opens a UV seam'
                        seam_gaps.append(gap)
                for finger in ['Thumb','Index','Middle','Ring','Pinky']:
                    second=names[P+side+'Hand'+finger+'2']
                    signed_displacement=float(np.dot(curled[second][:3,3]-w[second][:3,3],palm_normal))
                    assert signed_displacement>0,who+': diagnostic curl moves away from palm'
                    curl_displacements.append(signed_displacement)
                    chain=[w[names[P+side+'Hand'+finger+str(k)]][:3,3] for k in [1,2,3]]
                    lengths=np.linalg.norm(np.diff(np.array(chain),axis=0),axis=1)
                    assert lengths.min()>.003 and lengths.max()<.055,who+': nonlocal finger segment'
                    for point in chain:
                        assert np.linalg.norm(point-wrist)<.16,who+': joint outside hand neighborhood'
                        count=sum(ray_inside(tri,point,r) for r in RAYS);inside_counts.append(count)
                        assert count>=5,who+': finger pivot outside real exterior'
            row['minimum_repaired_finger_inside_rays']=min(inside_counts,default=None)
            row['minimum_curl_10deg_toward_palm_m']=min(curl_displacements,default=None)
            row['maximum_curl_35_65_seam_gap_m']=max(seam_gaps,default=None)
            if authored_hands:row['actual_authored_hand_samples']=authored_scope(a,ab,d,b,who,old)
        rows.append(row);print(who,'passed',flush=True)
    return {'scope':scope,'characters':rows,'result':'passed'}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--before-dir',type=Path,required=True);parser.add_argument('--after-dir',type=Path,required=True);parser.add_argument('--scope',choices=['body','fingers','both'],required=True);parser.add_argument('--characters',nargs='+',choices=PEOPLE,default=PEOPLE);parser.add_argument('--out',type=Path,required=True);parser.add_argument('--ren-shoulders',action='store_true');parser.add_argument('--authored-hands',action='store_true');args=parser.parse_args()
    try:result=verify(args.before_dir,args.after_dir,args.scope,args.characters,args.ren_shoulders,args.authored_hands)
    except Exception as error:
        args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps({'scope':args.scope,'result':'failed','error':str(error)},indent=2)+'\n');raise
    args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(json.dumps(result,indent=2)+'\n')

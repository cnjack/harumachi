"""Measure all changed sleeve/upper-cloth vertices against available posed skin.

Uses actual native final bones/scalars and the source's own old control curve.
Distances are unsigned exact closest-triangle distances. HiddenArm is separately
labelled a filler proxy; an absent hidden torso is not invented by this audit.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from glb_io import load
from prepare_local_garments import read
from sew_arm_seams import dense_part
from audit_sleeve_support_surface import curve, control, native_rows
from triangle_distance import closest_points


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args):
    d,b=load(args.candidate);sd,sb=load(args.source)
    identity=json.loads((args.native/'model-hashes.json').read_text())
    assert identity[f'CH_{args.character}.glb']==sha(args.candidate)
    selected=['CharacterBody','Sleeve_Left','Sleeve_Right']
    models={}; oldmodels={}
    for doc,binary,out in [(d,b,models),(sd,sb,oldmodels)]:
        for node in doc['nodes']:
            if 'skin' in node and 'mesh' in node:
                out[node['name']]=dense_part(doc,binary,node)
    prepared={};scope={}
    bone_names=[d['nodes'][i].get('name','') for i in d['skins'][0]['joints']]
    for name in selected:
        p,old=models[name],oldmodels[name]
        assert np.array_equal(p['pos'],old['pos']) and np.array_equal(p['j'],old['j']) and np.array_equal(p['w'],old['w'])
        ot,ov=curve(sd,sb,old,'stretch');nt,nv=curve(d,b,p,'stretch')
        changed=np.zeros(len(p['pos']))
        for time in np.union1d(ot,nt):
            delta=np.zeros_like(p['pos'])
            for sign,part,ts,vs in [(1,p,nt,nv),(-1,old,ot,ov)]:
                for n in part['names']:
                    if control(n):delta+=sign*float(np.interp(time,ts,vs[:,part['names'].index(n)]))*part['shapes'][n]
            changed=np.maximum(changed,np.linalg.norm(delta,axis=1))
        at=np.flatnonzero(changed>args.support_epsilon)
        arm_share=np.maximum.reduce([p['dense'][:,[i for i,n in enumerate(bone_names) if n in [f'mixamorig:{side}Arm',f'mixamorig:{side}ForeArm',f'TWIST_{side}'] or n.startswith(f'Cloth_{side}_')]].sum(1) for side in ['Left','Right']])
        prepared[name]=(ot,ov,nt,nv,at,arm_share)
        scope[name]={'changed_source_vertices':len(at),'source_ids':at.tolist()}
    warm=models['CharacterBody']['rgb'];r,g,blue=warm.T
    warm=(r>g*1.10)&(g>blue*1.02)&(r>.30)
    mainfaces=read(d,b,models['CharacterBody']['p']['indices']).reshape(-1,3)
    skinfaces=mainfaces[warm[mainfaces].all(1)]
    if args.arm_surface_only:
        p=models['CharacterBody']
        arm_ids=[i for i,n in enumerate(bone_names) if any(n in [f'mixamorig:{side}Arm',f'mixamorig:{side}ForeArm',f'TWIST_{side}'] or n.startswith(f'Cloth_{side}_') or n.startswith(f'mixamorig:{side}Hand') for side in ['Left','Right'])]
        arm=(p['dense'][:,arm_ids].sum(1)>=.5)
        skinfaces=skinfaces[arm[skinfaces].all(1)]
    ids={n.get('name'):i for i,n in enumerate(d['nodes'])}
    binds={si:read(d,b,s['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1) for si,s in enumerate(d['skins'])}
    rows=list(native_rows(args.native));samples=[];maximum_body_source_difference=0.
    for ri,row in enumerate(rows):
        world={i:np.eye(4) for s in d['skins'] for i in s['joints']}
        for bone in row['bones']:
            i=ids[bone['name'].replace('mixamorig_','mixamorig:')];world[i][:3,:3]=np.asarray(bone['basis']).T;world[i][:3,3]=bone['position']
        matrices={si:np.array([world[j]@ib for j,ib in zip(s['joints'],binds[si])])for si,s in enumerate(d['skins'])}
        posed={}; oldposed={}
        for name,p in models.items():
            m=matrices[p['node']['skin']];transform=np.einsum('vj,jab->vab',p['dense'],m)
            values=dict(row['values'].get(name,{}));position=p['pos'].copy()
            for n,value in values.items():
                if value:position+=value*p['shapes'][n]
            posed[name]=np.einsum('vab,vb->va',transform[:,:3,:3],position)+transform[:,:3,3]
            if name not in selected:continue
            old=oldmodels[name];ot,ov,nt,nv,_,_=prepared[name]
            oldvalues={n:values.get(n,0.)for n in old['names']}
            envelope=sum(value for n,value in values.items()if control(n))
            pure=sum(float(np.interp(row['clip_time'],nt,nv[:,p['names'].index(n)]))for n in p['names']if control(n))if row['clip']=='stretch'else 0.
            for n in old['names']:
                if control(n):oldvalues[n]=float(np.interp(row['clip_time'],ot,ov[:,old['names'].index(n)]))*envelope/pure if pure>1e-9 else 0.
            position=old['pos'].copy()
            for n,value in oldvalues.items():
                if value:position+=value*old['shapes'][n]
            oldposed[name]=np.einsum('vab,vb->va',transform[:,:3,:3],position)+transform[:,:3,3]
        maximum_body_source_difference=max(maximum_body_source_difference,float(np.linalg.norm(posed['CharacterBody'][warm]-oldposed['CharacterBody'][warm],axis=1).max()))
        bodypoints=[posed['CharacterBody']];bodyfaces=[skinfaces];labels=['exposed_arm_warm_surface' if args.arm_surface_only else 'warm_surface_candidate']*len(skinfaces);offset=len(bodypoints[0])
        for name,p in models.items():
            if name.startswith('HiddenArm'):
                f=read(d,b,p['p']['indices']).reshape(-1,3);bodypoints.append(posed[name]);bodyfaces.append(f+offset);offset+=len(posed[name]);labels.extend([name+'_filler_proxy']*len(f))
        bodypoints=np.concatenate(bodypoints);bodyfaces=np.concatenate(bodyfaces)
        query=[];tags=[]
        for name in selected:
            at=prepared[name][4]
            query.extend([oldposed[name][at],posed[name][at]]);tags.extend([(name,'old',at),(name,'new',at)])
        distances,face_indices,nearest=closest_points(bodypoints,bodyfaces,np.concatenate(query))
        values={};offset=0
        for name,kind,at in tags:
            count=len(at);values[name,kind]=(distances[offset:offset+count],face_indices[offset:offset+count]);offset+=count
        sample={k:row[k]for k in ['kind','view','frame','clip','phase']};sample['parts']=[]
        for name in selected:
            at=prepared[name][4];before,oldface=values[name,'old'];after,newface=values[name,'new'];delta=after-before
            if not len(at):continue
            worst=np.argsort(delta)[-5:][::-1]
            regions={}
            for label,mask in [('arm_dominant_share_ge50pct',prepared[name][5][at]>=.5),('strong_arm_share_ge80pct',prepared[name][5][at]>=.8),('torso_transition_share_lt50pct',prepared[name][5][at]<.5)]:
                if not mask.any():continue
                q=np.flatnonzero(mask);i=q[np.argmax(delta[q])]
                regions[label]={'vertices':len(q),'added_distance_p50_p95_max_m':np.percentile(delta[q],[50,95,100]).tolist(),
                    'new_distance_p50_p95_max_m':np.percentile(after[q],[50,95,100]).tolist(),
                    'worst_source_vertex':int(at[i]),'source_arm_share':float(prepared[name][5][at[i]]),
                    'old_distance_m':float(before[i]),'new_distance_m':float(after[i]),'nearest_body':labels[newface[i]]}
            sample['parts'].append({'mesh':name,'vertices':len(at),'regions_by_original_skin':regions,'old_distance_p50_p95_max_m':np.percentile(before,[50,95,100]).tolist(),
                'new_distance_p50_p95_max_m':np.percentile(after,[50,95,100]).tolist(),
                'added_distance_p50_p95_max_m':np.percentile(delta,[50,95,100]).tolist(),
                'vertex_fraction_added_over10mm':float((delta>.01).mean()),'vertex_fraction_added_over30mm':float((delta>.03).mean()),
                'worst':[{'source_vertex':int(at[i]),'old_distance_m':float(before[i]),'new_distance_m':float(after[i]),'added_m':float(delta[i]),
                    'old_nearest_body':labels[oldface[i]],'new_nearest_body':labels[newface[i]]}for i in worst]})
        samples.append(sample)
        if ri%100==0:print(ri,'of',len(rows),flush=True)
    report={'source':str(args.source),'source_sha256':sha(args.source),'candidate':str(args.candidate),'candidate_sha256':sha(args.candidate),
        'native':str(args.native),'tool_sha256':sha(Path(__file__)),'scope':scope,'available_warm_skin_faces':len(skinfaces),
        'available_skin_and_hidden_arm_proxy_faces':len(bodyfaces),'maximum_actual_warm_body_difference_m':maximum_body_source_difference,'samples':samples,
        'arm_surface_only':args.arm_surface_only,
        'limits':['Unsigned closest distance is not a signed penetration or cloth-body collision certificate.',
        'HiddenArm filler proxy and pigment candidates are separately labelled; arm-only mode also requires original Arm/ForeArm/Hand skin share>=50pct for all three triangle corners. No hidden torso is invented.',
        'Statistics count source vertex copies, not area or deduplicated physical vertices; all changed P support is included.',
        'Same-frame actual final bones/scalars; old control curve uses its own AP function and shared blend envelope.',
        'Raw decoded GLB skin, not a fresh GPU UNORM/octahedral export.']}
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(args.output,flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for n in ['source','candidate','native','output']:p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--character',default='mio');p.add_argument('--support-epsilon',type=float,default=1e-6)
    p.add_argument('--arm-surface-only',action='store_true')
    run(p.parse_args())

"""Check decoded action-only elbow GLBs against the actual source and native pose.

The same command with the unmodified source as candidate must fail. Numeric
surface checks complement, and do not replace, native screenshot acceptance.
"""
from pathlib import Path
import argparse, json
import numpy as np
from scipy.spatial import cKDTree
from audit_sleeve_weights import assets, evaluate
from prepare_local_garments import read, colours
from motion_math import world_matrices
from corrective_normals import unit, angle


def native(asset,part,row):
    doc,blob=asset[:2];animation=next(a for a in doc['animations'] if a['name']==row['clip'])
    world,_=world_matrices(doc,blob,animation,row['clip_time']);ids={n.get('name'):i for i,n in enumerate(doc['nodes'])}
    for bone in row['bones']:
        name=bone['name'].replace('mixamorig_','mixamorig:')
        if name in ids:
            world[ids[name]][:3,:3]=np.array(bone['basis']).T
            world[ids[name]][:3,3]=np.array(bone['position'])-row['position']
    count=len(part['names']);values=np.zeros(count)
    for channel in animation['channels']:
        if channel['target']!={'node':part['ni'],'path':'weights'}:continue
        sampler=animation['samplers'][channel['sampler']];times=read(doc,blob,sampler['input']).ravel();vs=read(doc,blob,sampler['output']).reshape(-1,count)
        values=np.array([np.interp(row['clip_time'],times,vs[:,i]) for i in range(count)])
    table=row['blend_shape_values'][doc['nodes'][part['ni']]['name']]
    for i,name in enumerate(part['names']):
        if name in table:values[i]=table[name]
    pos=part['pos'].copy()
    for v,delta in zip(values,part['shapes']):pos+=v*delta
    matrices=np.array([world[j]@bind for j,bind in zip(part['skin']['joints'],part['binds'])]);out=np.zeros_like(pos)
    for slot in range(part['joints'].shape[1]):out+=np.einsum('nij,nj->ni',matrices[part['joints'][:,slot],:3,:],np.c_[pos,np.ones(len(pos))])*part['weights'][:,slot,None]
    return out


def verify(args):
    before=assets(args.source,'sora');after=assets(args.candidate,'sora');bd,bb=before[:2];ad,ab=after[:2]
    assert len(bd['nodes'])==len(ad['nodes']) and len(bd['skins'])==len(ad['skins'])
    for old,new in zip(bd['nodes'],ad['nodes']):
        assert {k:v for k,v in old.items() if k!='weights'}=={k:v for k,v in new.items() if k!='weights'},'node/skeleton changed'
    for old,new in zip(bd['skins'],ad['skins']):
        assert old['joints']==new['joints'] and np.array_equal(read(bd,bb,old['inverseBindMatrices']),read(ad,ab,new['inverseBindMatrices'])),'binding changed'
    for old,new in zip(bd['images'],ad['images']):
        def data(doc,blob,image):
            view=doc['bufferViews'][image['bufferView']];start=view.get('byteOffset',0);return blob[start:start+view['byteLength']]
        assert data(bd,bb,old)==data(ad,ab,new),'texture changed'
    for om,nm in zip(bd['meshes'],ad['meshes']):
        for op,np_ in zip(om['primitives'],nm['primitives']):
            assert np.array_equal(read(bd,bb,op['indices']),read(ad,ab,np_['indices']))
            for key,index in op['attributes'].items():assert np.array_equal(read(bd,bb,index),read(ad,ab,np_['attributes'][key])),'base attribute changed: '+key
            for ot,nt in zip(op.get('targets',[]),np_.get('targets',[])):
                for key,index in ot.items():assert np.array_equal(read(bd,bb,index),read(ad,ab,nt[key])),'existing target changed'
    # All transform animation data must be exact, including unreviewed gestures.
    for oa,na in zip(bd['animations'],ad['animations']):
        assert oa['name']==na['name']
        for channel in oa['channels']:
            if channel['target']['path']=='weights':continue
            nc=next(c for c in na['channels'] if c['target']==channel['target']);os=oa['samplers'][channel['sampler']];ns=na['samplers'][nc['sampler']]
            for field in ['input','output']:assert np.array_equal(read(bd,bb,os[field]),read(ad,ab,ns[field])),'skeletal animation changed'
    samples=[]
    for key,p in before[2].items():
        q=after[2][key]
        for clip in [a['name'] for a in bd['animations'] if a['name']!='stretch']:
            for phase in [0,.125,.375,.625,.875,1]:
                gap=float(np.linalg.norm(evaluate(bd,bb,p,clip,phase)-evaluate(ad,ab,q,clip,phase),axis=1).max())
                assert gap<1e-7,clip+': previously accepted geometry changed'
    p=before[2][('CharacterBody',0)];q=after[2][('CharacterBody',0)]
    assert sum(n.startswith('SkinElbow_stretch_') for n in q['names'])==4,'missing elbow correctives'
    faces=read(bd,bb,p['p']['indices']).reshape(-1,3);edges={}
    for fi,face in enumerate(faces):
        for a,b in zip(face,np.roll(face,-1)):edges.setdefault(tuple(sorted((int(a),int(b)))),[]).append(fi)
    pairs=np.array([indices for indices in edges.values() if len(indices)==2])
    seams=cKDTree(p['pos']).query_pairs(1e-6,output_type='ndarray')
    colour=colours(bd,bb,p['p']);skin_colour=(colour[:,0]>colour[:,1]*1.10)&(colour[:,1]>colour[:,2]*1.02)&(colour[:,0]>.30)
    rows=[r for r in json.loads(args.manifest.read_text())['shots'] if r['id']=='sora' and r['clip']=='stretch' and r['view']=='front']
    for row in rows:
        old=native(before,p,row);new=native(after,q,row);shift=new-old;distance=np.linalg.norm(shift,axis=1);active=distance>.0002
        assert distance.max()<.01201 and np.count_nonzero(active)>500,'missing or unbounded surface correction'
        assert distance[~skin_colour].max()<1e-6,'clothing changed by skin corrective'
        t0=old[faces];t1=new[faces];n0=np.cross(t0[:,1]-t0[:,0],t0[:,2]-t0[:,0]);n1=np.cross(t1[:,1]-t1[:,0],t1[:,2]-t1[:,0])
        valid=np.linalg.norm(n0,axis=1)>1e-12
        flips=((n0*n1).sum(1)<=0)&valid
        assert not flips.any(),'newly inverted triangle'
        added=float(np.linalg.norm(shift[seams[:,0]]-shift[seams[:,1]],axis=1).max())
        assert added<1e-5,'corrective opens a seam'
        selected=active[faces[pairs]].all(axis=(1,2));chosen=pairs[selected]
        old_turn=angle(n0[chosen[:,0]],n0[chosen[:,1]]);new_turn=angle(n1[chosen[:,0]],n1[chosen[:,1]])
        old95=float(np.percentile(old_turn,95));new95=float(np.percentile(new_turn,95))
        assert new95<old95*.9,'elbow creases did not measurably improve'
        samples.append({'phase':row['phase'],'newly_inverted_faces':int(flips.sum()),'maximum_shift_m':float(distance.max()),'added_seam_gap_m':added,'source_neighbor_face_turn_p95_deg':old95,'candidate_neighbor_face_turn_p95_deg':new95})
    assert len(samples)>=2,'need actual final native .125 and .625 samples'
    return {'result':'passed','base_attributes_skin_textures_existing_targets_exact':True,'skeletal_animation_exact':True,'all_11_other_clips_6phases_geometry_identical':True,'native_samples':samples,'native_screenshot_acceptance':'pending'}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',required=True,type=Path);p.add_argument('--candidate',required=True,type=Path);p.add_argument('--manifest',required=True,type=Path);p.add_argument('--out',required=True,type=Path);args=p.parse_args()
    try:result=verify(args)
    except Exception as error:args.out.write_text(json.dumps({'result':'failed','error':str(error)},indent=2)+'\n');raise
    args.out.write_text(json.dumps(result,indent=2)+'\n');print(args.out)

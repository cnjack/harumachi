"""Compare original and sleeve-candidate deformation using original triangle edges.

Reports a diagnostic, not a replacement for five-view native visual acceptance.
It proves UV/texture/geometry preservation and detects newly stretched cloth edges.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from prepare_local_garments import read, colours
from prepare_sleeve_weights import cloth_mask
from glb_io import load
from motion_math import world_matrices


def assets(path,who):
    d,b=load(path);parts={};height=0.
    for ni,n in enumerate(d['nodes']):
        if 'skin' not in n or 'mesh' not in n or n['name'].startswith('HiddenArm'):continue
        for pi,p in enumerate(d['meshes'][n['mesh']]['primitives']):
            a=p['attributes'];pos=read(d,b,a['POSITION']);height=max(height,float(pos[:,1].max()));j=read(d,b,a['JOINTS_0']);w=read(d,b,a['WEIGHTS_0'])
            if 'JOINTS_1' in a:j=np.c_[j,read(d,b,a['JOINTS_1'])];w=np.c_[w,read(d,b,a['WEIGHTS_1'])]
            faces=read(d,b,p['indices']).reshape(-1,3);edges=np.unique(np.sort(np.r_[faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]],axis=1),axis=0);skin=d['skins'][n['skin']];binds=read(d,b,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1);mesh=d['meshes'][n['mesh']];names=mesh.get('extras',{}).get('targetNames',[]);shapes=[read(d,b,t['POSITION']) for t in p.get('targets',[])];colour=colours(d,b,p);cloth=cloth_mask(who,colour)&~((colour[:,0]>colour[:,1]*1.1)&(colour[:,1]>colour[:,2]*1.02)&(colour[:,0]>.3));parts[(n['name'],pi)]={'ni':ni,'p':p,'pos':pos,'joints':j,'weights':w,'skin':skin,'binds':binds,'names':names,'shapes':shapes,'cloth':cloth,'edges':edges}
    return d,b,parts,height


def evaluate(d,b,part,clip,phase):
    animation=next(a for a in d['animations'] if a['name']==clip);duration=max(float(read(d,b,s['input']).max()) for s in animation['samplers']);time=duration*phase;worlds,_=world_matrices(d,b,animation,time);rest=part['pos'].copy();count=len(part['names']);shapeweights=np.zeros(count)
    for c in animation['channels']:
        if c['target']!={'node':part['ni'],'path':'weights'}:continue
        sampler=animation['samplers'][c['sampler']];times=read(d,b,sampler['input']).ravel();values=read(d,b,sampler['output']).reshape(-1,count);shapeweights=np.array([np.interp(time,times,values[:,i]) for i in range(count)])
    for amount,delta in zip(shapeweights,part['shapes']):rest+=amount*delta
    mats=np.array([worlds[ji]@bind for ji,bind in zip(part['skin']['joints'],part['binds'])]);posed=np.zeros_like(rest,dtype=float);pos4=np.c_[rest,np.ones(len(rest))]
    for k in range(part['joints'].shape[1]):posed+=np.einsum('nij,nj->ni',mats[part['joints'][:,k],:3,:],pos4)*part['weights'][:,k,None]
    return posed


def audit(args):
    old=assets(args.before,args.character);new=assets(args.after,args.character);preserved=[];samples=[]
    for key,op in old[2].items():
        npart=new[2][key];same={field:np.array_equal(read(old[0],old[1],op['p']['attributes'][field]),read(new[0],new[1],npart['p']['attributes'][field])) for field in ['POSITION','NORMAL','TEXCOORD_0']};same['indices']=np.array_equal(read(old[0],old[1],op['p']['indices']),read(new[0],new[1],npart['p']['indices']));same['skeleton_bind']=np.array_equal(op['binds'],npart['binds']);preserved.append({'mesh':key[0],**same})
        pos=op['pos'];H=old[3];cloth=op['cloth']&(abs(pos[:,0])>.06*H)&(pos[:,1]>.52*H)&(pos[:,1]<.89*H);edges=op['edges'];selected=np.all(cloth[edges],axis=1);rest_length=np.linalg.norm(pos[edges[:,1]]-pos[edges[:,0]],axis=1);selected&=(rest_length>.001)&(rest_length<.03);chosen=edges[selected];lengths=rest_length[selected]
        if not len(chosen):continue
        for clip in ['wave','stretch']:
            for phase in [.125,.375,.625,.875]:
                before=evaluate(old[0],old[1],op,clip,phase);after=evaluate(new[0],new[1],npart,clip,phase);a=np.linalg.norm(before[chosen[:,1]]-before[chosen[:,0]],axis=1)/lengths;b=np.linalg.norm(after[chosen[:,1]]-after[chosen[:,0]],axis=1)/lengths;delta=np.linalg.norm(after-before,axis=1);samples.append({'mesh':key[0],'clip':clip,'phase':phase,'cloth_edges':len(chosen),'before_stretch_p95':float(np.percentile(a,95)),'after_stretch_p95':float(np.percentile(b,95)),'before_stretch_p99':float(np.percentile(a,99)),'after_stretch_p99':float(np.percentile(b,99)),'before_stretch_max':float(a.max()),'after_stretch_max':float(b.max()),'before_edges_over_2x':int(np.count_nonzero(a>2)),'after_edges_over_2x':int(np.count_nonzero(b>2)),'max_candidate_surface_shift_m':float(delta[cloth].max())})
    result={'character':args.character,'before':str(args.before),'after':str(args.after),'after_sha256':hashlib.sha256(args.after.read_bytes()).hexdigest(),'scope':'authored rotation samples; spring final poses need native screenshots','preserved':preserved,'source_geometry_uv_and_bind_preserved':all(all(v for k,v in p.items() if k!='mesh') for p in preserved),'samples':samples};args.output.write_text(json.dumps(result,indent=2));print(args.output)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--before',type=Path,required=True);p.add_argument('--after',type=Path,required=True);p.add_argument('--character',required=True);p.add_argument('--output',type=Path,required=True);audit(p.parse_args())

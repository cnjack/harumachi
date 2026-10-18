"""Limit a synchronized sleeve field against its same-pose unmorphed surface.

A physical vertex uses one factor shared by all four corrective targets. This
retains closed seams at interpolated times and leaves every animation exact.
The reference is the existing mesh skinned without these four targets, not the
rest-pose normal and not a newly reconstructed sleeve tube.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from scipy.sparse import coo_matrix, diags
from glb_io import load
from prepare_local_garments import read
from sew_arm_seams import dense_part
from synchronize_sleeve_corrective_seams import posed_part, physical_groups
from corrective_normals import unit, geometry_normals, rotate_between
from motion_math import world_matrices
from repair_head_neck import append, save


def authored_rows(d, b, parts, clip, samples):
    animation = next(a for a in d['animations'] if a['name'] == clip)
    length = max(float(read(d,b,s['input']).max()) for s in animation['samplers'])
    for phase in np.linspace(0,1,samples+1):
        world,_ = world_matrices(d,b,animation,phase*length)
        values={}
        for name,part in parts.items():
            ni=d['nodes'].index(part['node']);count=len(part['names']);amount=np.zeros(count)
            for channel in animation['channels']:
                if channel['target']!={'node':ni,'path':'weights'}:continue
                sampler=animation['samplers'][channel['sampler']];ts=read(d,b,sampler['input']).ravel();vs=read(d,b,sampler['output']).reshape(-1,count);amount=np.array([np.interp(phase*length,ts,vs[:,i])for i in range(count)])
            values[name]=dict(zip(part['names'],map(float,amount)))
        bones=[{'name':d['nodes'][ji]['name'],'basis':world[ji][:3,:3].T.tolist(),'position':world[ji][:3,3].tolist()}for ji in d['skins'][0]['joints']]
        yield {'phase':float(phase),'clip':clip,'clip_time':float(phase*length),'position':[0.,0.,0.],'bones':bones,'blend_shape_values':values,'kind':'authored'}


def cross(points,faces):
    t=points[faces]
    return np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0])


def build(args):
    d,raw=load(args.input);b=bytearray(raw)
    parts={n['name']:dense_part(d,b,n)for n in d['nodes']if n.get('name')in ['CharacterBody','Sleeve_Left','Sleeve_Right']}
    order,offsets,groups,pairs=physical_groups(parts,args.character)
    labels=np.arange(int(offsets[-1]))
    for g in groups:labels[g]=g[0]
    _,physical=np.unique(labels,return_inverse=True);size=int(physical.max())+1
    factor=np.ones(size)
    edges=np.concatenate([parts[name]['edges']+offsets[i]for i,name in enumerate(order)]);edgeids=np.unique(np.sort(physical[edges],axis=1),axis=0);edgeids=edgeids[edgeids[:,0]!=edgeids[:,1]]
    graph=coo_matrix((np.ones(2*len(edgeids)),(np.r_[edgeids[:,0],edgeids[:,1]],np.r_[edgeids[:,1],edgeids[:,0]])),shape=(size,size)).tocsr();degree=np.asarray(graph.sum(1)).ravel();mean=diags(1/np.maximum(degree,1))@graph
    names=[n for n in parts['CharacterBody']['names']if n.startswith(f'SleeveFit_{args.clip}_')]
    native=[r for r in json.loads(args.manifest.read_text())['shots']if r['id']==args.character and r['clip']==args.clip and r['view']=='front']
    samples=native+list(authored_rows(d,b,parts,args.clip,args.samples))
    cache=[]
    for row in samples:
        for pi,name in enumerate(order):
            part=parts[name];field=sum((row['blend_shape_values'][name][n]*part['shapes'][n]for n in names),start=np.zeros_like(part['pos']))
            if not np.any(field):continue
            zero={n:np.zeros_like(v)if n in names else v for n,v in part['shapes'].items()}
            base,B,_=posed_part(d,b,part,row,shapes=zero)
            shift=np.einsum('nij,nj->ni',B,field)
            faces=read(d,b,part['p']['indices']).reshape(-1,3);selected=np.any(np.linalg.norm(shift[faces],axis=2)>1e-10,axis=1);faces=faces[selected]
            used,tri=np.unique(faces,return_inverse=True);tri=tri.reshape(-1,3);ref=cross(base[used],tri);area=np.linalg.norm(ref,axis=1);valid=area>1e-12
            cache.append({'name':name,'phase':row['phase'],'kind':row.get('kind','native'),'base':base[used],'shift':shift[used],'tri':tri,'ref':ref,'area':area,'valid':valid,'ids':physical[offsets[pi]+used]})
    iterations=[]
    for iteration in range(100):
        bad_ids=[];bad_count=0;minratio=1.
        for item in cache:
            points=item['base']+item['shift']*factor[item['ids'],None];current=cross(points,item['tri']);dot=(current*item['ref']).sum(1);ratio=np.linalg.norm(current,axis=1)/np.maximum(item['area'],1e-20);bad=item['valid']&((dot<.02*item['area']**2)|(ratio<.16));bad_count+=int(bad.sum())
            if bad.any():bad_ids.append(item['ids'][np.unique(item['tri'][bad])])
        iterations.append({'iteration':iteration,'bad_surface_samples':bad_count})
        if not bad_count:break
        at=np.unique(np.concatenate(bad_ids));factor[at]*=.65
        for _ in range(3):
            averaged=mean@factor;factor[degree>0]=np.minimum(factor[degree>0],averaged[degree>0])
        factor[factor<1e-5]=0
    if bad_count:raise ValueError('Could not stabilize the physical field')
    report={'input':str(args.input),'input_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),'scope':f'{len(native)} native-source peak poses + {args.samples+1} authored stretch poses; candidate native rendering remains required','same_physical_factor_for_every_target':True,'iterations':iterations,'physical_factors_percentiles':np.percentile(factor,[0,5,50,95,100]).tolist(),'targets':[]}
    for target in names:
        phase=int(target.rsplit('_',1)[1])/1000;row=next(r for r in native if abs(r['phase']-phase)<1e-6)
        for pi,name in enumerate(order):
            part=parts[name];old=part['shapes'][target];new=old*factor[physical[offsets[pi]:offsets[pi+1]],None]
            before,B,rest_normal=posed_part(d,b,part,row);delta=np.einsum('nij,nj->ni',B,new-old);after=before+delta;moved=np.linalg.norm(delta,axis=1)>1e-10
            faces=read(d,b,part['p']['indices']).reshape(-1,3);af=np.any(moved[faces],axis=1);affected=np.zeros(len(old),bool);affected[np.unique(faces[af])]=True
            base_normal=unit(read(d,b,part['a']['NORMAL']));old_render=unit(np.einsum('nij,nj->ni',B,unit(rest_normal)));wanted=unit(rotate_between(geometry_normals(before,faces),geometry_normals(after,faces),old_render));wanted_rest=unit(np.einsum('nij,nj->ni',np.linalg.pinv(B),wanted));ti=part['names'].index(target);old_dn=unit(base_normal+read(d,b,part['p']['targets'][ti]['NORMAL']))-base_normal;offset=base_normal-(rest_normal-old_dn);along=(offset*wanted_rest).sum(1);disc=along**2+1-(offset**2).sum(1)
            if np.any(disc[affected]<-1e-8):raise ValueError('Unit normal target unreachable')
            dn=unit(offset+(-along+np.sqrt(np.maximum(disc,0)))[:,None]*wanted_rest)-base_normal;dn[~affected]=read(d,b,part['p']['targets'][ti]['NORMAL'])[~affected]
            part['p']['targets'][ti]={'POSITION':append(d,b,part['a']['POSITION'],new.astype(np.float32)),'NORMAL':append(d,b,part['a']['NORMAL'],dn.astype(np.float32))}
            report['targets'].append({'target':target,'mesh':name,'remaining_delta_max_m':float(np.linalg.norm(new,axis=1).max()),'world_change_max_m':float(np.linalg.norm(delta,axis=1).max())})
    args.output.parent.mkdir(parents=True,exist_ok=True);save(d,b,args.output);report['output']=str(args.output);report['output_sha256']=hashlib.sha256(args.output.read_bytes()).hexdigest();report['tool_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest();args.report.write_text(json.dumps(report,indent=2)+'\n');print(args.report)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--manifest',required=True,type=Path);p.add_argument('--report',required=True,type=Path);p.add_argument('--character',default='mio');p.add_argument('--clip',default='stretch');p.add_argument('--samples',type=int,default=128);build(p.parse_args())

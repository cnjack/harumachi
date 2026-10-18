"""Round reviewed sleeve folds only in stretch; retain every other action exactly.

This is a bounded pose-space cloth fairing, not a new cylindrical sleeve. Source
geometry/skin/UVs and old targets are retained, with four new action targets.
"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from scipy import sparse
from scipy.spatial import cKDTree
from scipy.sparse.csgraph import connected_components
from glb_io import load
from prepare_local_garments import read,colours,smooth
from prepare_sleeve_weights import cloth_mask
from prepare_sleeve_correctives import patch_weights
from prepare_elbow_correctives import final_worlds
from corrective_normals import geometry_normals,rotate_between,unit,angle
from motion_math import world_matrices
from repair_head_neck import append,save

PHASES=[.375,.5,.625,.875]


def prepare(args):
    d,raw=load(args.input);b=bytearray(raw);source,sb=load(args.input);ni=max((i for i,n in enumerate(d['nodes']) if 'skin' in n and 'mesh' in n),key=lambda i:d['accessors'][d['meshes'][d['nodes'][i]['mesh']]['primitives'][0]['attributes']['POSITION']]['count']);node=d['nodes'][ni];mesh=d['meshes'][node['mesh']];skin=d['skins'][node['skin']];names=mesh.setdefault('extras',{}).setdefault('targetNames',[]);count=len(names);prefix='ClothFair_stretch_'
    if any(n.startswith(prefix) for n in names):raise ValueError('Input already contains this stage')
    hashes=json.loads((args.manifest.parent.parent/'model-hashes.json').read_text())
    if hashes[f'CH_{args.character}.glb']!=hashlib.sha256(args.input.read_bytes()).hexdigest():raise ValueError('Native fairing references must match this source model SHA')
    rows=[r for r in json.loads(args.manifest.read_text())['shots'] if r['id']==args.character and r['clip']=='stretch'];animation=next(a for a in d['animations'] if a['name']=='stretch');duration=max(float(read(d,b,s['input']).max()) for s in animation['samplers']);rest,_=world_matrices(d,b);ids={n.get('name'):i for i,n in enumerate(d['nodes'])};bind=read(d,b,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1);report={'input':str(args.input),'input_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),'character':args.character,'new_action':'stretch only','old_targets_skin_uv_geometry_preserved':True,'maximum_world_shift_m':args.cap,'iterations':args.iterations,'samples':[]}
    for p in mesh['primitives']:
        a=p['attributes'];pos=read(d,b,a['POSITION']);normals=unit(read(d,b,a['NORMAL']));faces=read(d,b,p['indices']).reshape(-1,3);rgb=colours(d,b,p);height=float(pos[:,1].max());j=read(d,b,a['JOINTS_0']);w=read(d,b,a['WEIGHTS_0'])
        if 'JOINTS_1' in a:j=np.c_[j,read(d,b,a['JOINTS_1'])];w=np.c_[w,read(d,b,a['WEIGHTS_1'])]
        cloth=cloth_mask(args.character,rgb);mask=np.zeros(len(pos));joint_names=[d['nodes'][x].get('name','') for x in skin['joints']]
        for side in ['Left','Right']:
            A=rest[ids['mixamorig:'+side+'Arm']][:3,3];E=rest[ids['mixamorig:'+side+'ForeArm']][:3,3];W=rest[ids['mixamorig:'+side+'Hand']][:3,3];up=E-A;lo=W-E;ul=np.linalg.norm(up);ll=np.linalg.norm(lo);ua=up/ul;la=lo/ll;t=(pos-A)@ua;u=(pos-E)@la;ur=np.linalg.norm(pos-A-t[:,None]*ua,axis=1);lr=np.linalg.norm(pos-E-u[:,None]*la,axis=1);lower=(u>0)&(lr<ur);arc=np.where(lower,ul+u,t);rad=np.where(lower,lr,ur);own=np.array([n in ['mixamorig:'+side+'Arm','mixamorig:'+side+'ForeArm','TWIST_'+side] or n.startswith('Cloth_'+side+'_') for n in joint_names]);share=np.sum(w*own[j],axis=1)
            sleeve=cloth*(pos[:,1]>.52*height)*smooth(.30,.75,share)*smooth(.025,.065,arc)*(1-smooth(ul+ll-.050,ul+ll-.020,arc))*(1-smooth(.12*height,.15*height,rad));mask=np.maximum(mask,sleeve)
        edges=np.unique(np.sort(np.r_[faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]],axis=1),axis=0);seams=cKDTree(pos).query_pairs(1e-6,output_type='ndarray');all_edges=np.r_[edges,seams];graph=sparse.coo_matrix((np.ones(2*len(all_edges)),(np.r_[all_edges[:,0],all_edges[:,1]],np.r_[all_edges[:,1],all_edges[:,0]])),shape=(len(pos),len(pos))).tocsr();mean=sparse.diags(1/np.maximum(np.asarray(graph.sum(1)).ravel(),1))@graph;sg=sparse.coo_matrix((np.ones(2*len(seams)),(np.r_[seams[:,0],seams[:,1]],np.r_[seams[:,1],seams[:,0]])),shape=(len(pos),len(pos))).tocsr();components,labels=connected_components(sg,directed=False);sizes=np.bincount(labels,minlength=components);minimum=np.full(components,np.inf);np.minimum.at(minimum,labels,mask);mask=minimum[labels];source_shapes=[read(d,b,t['POSITION']) for t in p.get('targets',[])];source_normals=[unit(normals+read(d,b,t['NORMAL']))-normals if 'NORMAL' in t else np.zeros_like(pos) for t in p.get('targets',[])]
        for phase in PHASES:
            row=next(r for r in rows if abs(r['phase']-phase)<1e-6);values=np.array([row['blend_shape_values'][node['name']][name] for name in names[:count]]);base=pos.copy();normal=normals.copy()
            for value,dp,dn in zip(values,source_shapes,source_normals):base+=value*dp;normal+=value*dn
            worlds=final_worlds(d,b,animation,duration*phase,row);matrices=np.array([worlds[joint]@ib for joint,ib in zip(skin['joints'],bind)]);B=np.zeros((len(pos),3,3));T=np.zeros_like(pos)
            for slot in range(j.shape[1]):B+=matrices[j[:,slot],:3,:3]*w[:,slot,None,None];T+=matrices[j[:,slot],:3,3]*w[:,slot,None]
            posed=np.einsum('nij,nj->ni',B,base)+T;fair=posed.copy()
            for iteration in range(args.iterations):
                for coefficient in [.5,-.53]:
                    fair+=coefficient*mask[:,None]*(mean@fair-fair);delta=fair-posed;sums=np.zeros((components,3));np.add.at(sums,labels,delta);delta=sums[labels]/sizes[labels,None];delta*=np.minimum(1,args.cap/np.maximum(np.linalg.norm(delta,axis=1),1e-12))[:,None];fair=posed+delta
            # The reported defect is an outward radial fold. Preserve arc
            # placement and fill no concavity: only retain inward radial fairing.
            radial_direction=np.zeros_like(pos);radial_distance=np.full(len(pos),np.inf)
            for side in ['Left','Right']:
                for start,end in [('Arm','ForeArm'),('ForeArm','Hand')]:
                    A=worlds[ids['mixamorig:'+side+start]][:3,3];E=worlds[ids['mixamorig:'+side+end]][:3,3];axis=E-A;factor=np.clip(((posed-A)@axis)/np.dot(axis,axis),0,1);radial=posed-A-factor[:,None]*axis;distance=np.linalg.norm(radial,axis=1);closer=distance<radial_distance;radial_direction[closer]=radial[closer]/np.maximum(distance[closer,None],1e-12);radial_distance[closer]=distance[closer]
            shift=fair-posed;inward=np.minimum(np.sum(shift*radial_direction,axis=1),0);shift=radial_direction*inward[:,None];shift[mask==0]=0;sums=np.zeros((components,3));np.add.at(sums,labels,shift);shift=sums[labels]/sizes[labels,None];before_tri=posed[faces];old_cross=np.cross(before_tri[:,1]-before_tri[:,0],before_tri[:,2]-before_tri[:,0]);old_area=np.linalg.norm(old_cross,axis=1)
            for retreat in range(80):
                tri=(posed+shift)[faces];cross=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);bad=((old_cross*cross).sum(1)<=0)&(old_area>1e-12);bad|=(np.linalg.norm(cross,axis=1)<old_area*.15)&(old_area>1e-12)
                if not bad.any():break
                multiplier=np.ones(components);multiplier[np.unique(labels[faces[bad]])]=.65;shift*=multiplier[labels,None]
            if bad.any():raise ValueError('Cloth fairing introduced an inverted/collapsed face')
            fair=posed+shift;active=np.linalg.norm(shift,axis=1)>1e-8;delta=np.zeros_like(pos);delta[active]=np.einsum('nij,nj->ni',np.linalg.pinv(B[active]),shift[active]);affected_faces=np.any(active[faces],axis=1);affected=np.zeros(len(pos),bool);affected[np.unique(faces[affected_faces])]=True;old_geo=geometry_normals(posed,faces);new_geo=geometry_normals(fair,faces);old_render=unit(np.einsum('nij,nj->ni',B,unit(normal)));wanted=unit(rotate_between(old_geo,new_geo,old_render));wanted_rest=unit(np.einsum('nij,nj->ni',np.linalg.pinv(B),wanted));offset=normals-normal;along=np.sum(offset*wanted_rest,axis=1);disc=along*along+1-np.sum(offset*offset,axis=1);scale=-along+np.sqrt(np.maximum(disc,0));dn=unit(offset+scale[:,None]*wanted_rest)-normals;dn[~affected]=0;p.setdefault('targets',[]).append({'POSITION':append(d,b,a['POSITION'],delta.astype(np.float32)),'NORMAL':append(d,b,a['NORMAL'],dn.astype(np.float32))});length=np.linalg.norm(shift,axis=1);curvature_before=np.linalg.norm(mean@posed-posed,axis=1);curvature_after=np.linalg.norm(mean@fair-fair,axis=1);selected=mask>.5
            report['samples'].append({'phase':phase,'native_final_basis':True,'cloth_vertices':int((mask>0).sum()),'moved_vertices':int(active.sum()),'maximum_shift_m':float(length.max()),'maximum_outward_radial_shift_m':float(np.maximum(0,np.sum(shift*radial_direction,axis=1)).max()),'shift_p95_m':float(np.percentile(length[active],95)),'outside_cloth_shift_max_m':float(length[mask==0].max()),'newly_inverted_faces':int(bad.sum()),'uv_added_gap_max_m':float(np.linalg.norm(shift[seams[:,0]]-shift[seams[:,1]],axis=1).max()),'posed_cloth_laplacian_p95_before_m':float(np.percentile(curvature_before[selected],95)),'posed_cloth_laplacian_p95_after_m':float(np.percentile(curvature_after[selected],95)),'normal_turn_p95_deg':float(np.percentile(angle(old_geo[affected],new_geo[affected]),95))})
    new_names=[prefix+f'{round(phase*1000):03d}' for phase in PHASES];names.extend(new_names);mesh['weights']=list(mesh.get('weights',[0]*count))+[0]*len(PHASES)
    if 'weights' in node:node['weights']+=[0]*len(PHASES)
    for animation in d['animations']:
        old_animation=next(a for a in source['animations'] if a['name']==animation['name']);old_channel=next((c for c in old_animation['channels'] if c['target']=={'node':ni,'path':'weights'}),None)
        if old_channel:times=read(source,sb,old_animation['samplers'][old_channel['sampler']]['input']).ravel()
        else:times=np.array([0,max(float(read(d,b,s['input']).max()) for s in animation['samplers'])])
        if animation['name']=='stretch':times=np.unique(np.r_[times,np.array([0]+PHASES+[1])*duration]).astype(np.float32)
        previous=patch_weights(source,sb,old_animation,ni,count,times);output=np.c_[previous,np.zeros((len(times),len(PHASES)))]
        if animation['name']=='stretch':
            for index in range(len(PHASES)):
                hat=np.zeros(6);hat[index+1]=1;output[:,count+index]=np.interp(times/duration,[0]+PHASES+[1],hat)
        template=animation['samplers'][0]['input'];ti=append(d,b,template,times[:,None]);oi=append(d,b,template,output.reshape(-1,1));si=len(animation['samplers']);animation['samplers'].append({'input':ti,'output':oi,'interpolation':'LINEAR'});animation['channels']=[c for c in animation['channels'] if c['target']!={'node':ni,'path':'weights'}];animation['channels'].append({'sampler':si,'target':{'node':ni,'path':'weights'}})
    save(d,b,args.output);report['output']=str(args.output);report['output_sha256']=hashlib.sha256(args.output.read_bytes()).hexdigest();args.report.write_text(json.dumps(report,indent=2));print(args.report)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--manifest',required=True,type=Path);p.add_argument('--report',required=True,type=Path);p.add_argument('--character',default='haru');p.add_argument('--cap',type=float,default=.012);p.add_argument('--iterations',type=int,default=100);prepare(p.parse_args())

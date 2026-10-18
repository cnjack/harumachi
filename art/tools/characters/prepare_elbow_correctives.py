"""Fair Sora's exposed elbow surface only during the reviewed stretch action.

The original mesh, skin weights, skeleton and existing morph targets are retained.
New local morphs round the posed elbow through welded source topology; clothing,
hands and every other animation have zero displacement from this stage.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from scipy import sparse
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree
from glb_io import load
from repair_head_neck import append, save
from prepare_local_garments import read, colours, smooth
from prepare_sleeve_correctives import patch_weights
from motion_math import world_matrices
from corrective_normals import geometry_normals, rotate_between, unit, angle

PHASES=[.125,.375,.625,.875]
PREFIX='SkinElbow_stretch_'


def final_worlds(doc,blob,animation,time,row=None):
    worlds,_=world_matrices(doc,blob,animation,time)
    if row:
        ids={n.get('name'):i for i,n in enumerate(doc['nodes'])}
        for bone in row['bones']:
            name=bone['name'].replace('mixamorig_','mixamorig:')
            if name in ids:
                worlds[ids[name]][:3,:3]=np.array(bone['basis']).T
                worlds[ids[name]][:3,3]=np.array(bone['position'])-row['position']
    return worlds


def prepare(args):
    doc,binary=load(args.input);blob=bytearray(binary);source_doc,source_blob=load(args.input)
    rest,_=world_matrices(doc,blob);ids={n.get('name'):i for i,n in enumerate(doc['nodes'])}
    rows=[] if not args.manifest else json.loads(args.manifest.read_text())['shots']
    rows=[r for r in rows if r['id']=='sora' and r['clip']=='stretch']
    ni=next(i for i,n in enumerate(doc['nodes']) if n.get('name')=='CharacterBody')
    node=doc['nodes'][ni];mesh=doc['meshes'][node['mesh']];skin=doc['skins'][node['skin']]
    names=mesh.setdefault('extras',{}).setdefault('targetNames',[]);count=len(names)
    if any(n.startswith(PREFIX) for n in names):raise ValueError('Input already has this elbow stage')
    animation=next(a for a in doc['animations'] if a['name']=='stretch')
    duration=max(float(read(doc,blob,s['input']).max()) for s in animation['samplers'])
    bind=read(doc,blob,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
    report={'input':str(args.input),'source_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),
            'stage':'sora-exposed-elbow-stretch-only','maximum_world_shift_m':args.cap,
            'original_skin_weights_unchanged':True,'other_clips_zero_corrective':True,'samples':[]}
    for primitive in mesh['primitives']:
        attrs=primitive['attributes'];pos=read(doc,blob,attrs['POSITION']);n0=unit(read(doc,blob,attrs['NORMAL']))
        faces=read(doc,blob,primitive['indices']).reshape(-1,3);colour=colours(doc,blob,primitive)
        joints=read(doc,blob,attrs['JOINTS_0']);weights=read(doc,blob,attrs['WEIGHTS_0'])
        if 'JOINTS_1' in attrs:joints=np.c_[joints,read(doc,blob,attrs['JOINTS_1'])];weights=np.c_[weights,read(doc,blob,attrs['WEIGHTS_1'])]
        dense=np.zeros((len(pos),len(skin['joints'])))
        for slot in range(joints.shape[1]):np.add.at(dense,(np.arange(len(pos)),joints[:,slot]),weights[:,slot])
        skin_colour=(colour[:,0]>colour[:,1]*1.10)&(colour[:,1]>colour[:,2]*1.02)&(colour[:,0]>.30)
        mask=np.zeros(len(pos));side_masks={}
        for side in ['Left','Right']:
            A=rest[ids['mixamorig:'+side+'Arm']][:3,3];E=rest[ids['mixamorig:'+side+'ForeArm']][:3,3];W=rest[ids['mixamorig:'+side+'Hand']][:3,3]
            axis=(W-A)/np.linalg.norm(W-A);along=(pos-E)@axis;radial=np.linalg.norm(pos-E-along[:,None]*axis,axis=1)
            own=[skin['joints'].index(ids['mixamorig:'+side+x]) for x in ['Arm','ForeArm']]
            share=dense[:,own].sum(1)
            own_mask=skin_colour*smooth(.85,.98,share)*(1-smooth(.075,.125,abs(along)))*(1-smooth(.048,.065,radial))
            side_masks[side]=own_mask;mask=np.maximum(mask,own_mask)
        edges=np.unique(np.sort(np.r_[faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]],axis=1),axis=0)
        seams=cKDTree(pos).query_pairs(1e-6,output_type='ndarray');edges=np.r_[edges,seams]
        seam_graph=sparse.coo_matrix((np.ones(2*len(seams)),(np.r_[seams[:,0],seams[:,1]],np.r_[seams[:,1],seams[:,0]])),shape=(len(pos),len(pos))).tocsr()
        components,labels=connected_components(seam_graph,directed=False);sizes=np.bincount(labels,minlength=components)
        minima=np.full(components,np.inf);np.minimum.at(minima,labels,mask);mask=minima[labels]
        adjacent=sparse.coo_matrix((np.ones(2*len(edges)),(np.r_[edges[:,0],edges[:,1]],np.r_[edges[:,1],edges[:,0]])),shape=(len(pos),len(pos))).tocsr()
        mean=sparse.diags(1/np.maximum(np.asarray(adjacent.sum(1)).ravel(),1))@adjacent
        source_shapes=[read(doc,blob,t['POSITION']) for t in primitive.get('targets',[])]
        source_normals=[unit(n0+read(doc,blob,t['NORMAL']))-n0 if 'NORMAL' in t else np.zeros_like(pos) for t in primitive.get('targets',[])]
        for phase in PHASES:
            native=next((r for r in rows if abs(r.get('phase',-1)-phase)<1e-6),None)
            values=patch_weights(source_doc,source_blob,animation,ni,count,np.array([duration*phase]))[0]
            if native:
                table=native['blend_shape_values']['CharacterBody'];values=np.array([table[n] for n in names[:count]])
            base=pos.copy();normal=n0.copy()
            for v,dp,dn in zip(values,source_shapes,source_normals):base+=v*dp;normal+=v*dn
            worlds=final_worlds(doc,blob,animation,duration*phase,native)
            matrices=np.array([worlds[j]@ib for j,ib in zip(skin['joints'],bind)])
            B=np.zeros((len(pos),3,3));T=np.zeros_like(pos)
            for slot in range(joints.shape[1]):B+=matrices[joints[:,slot],:3,:3]*weights[:,slot,None,None];T+=matrices[joints[:,slot],:3,3]*weights[:,slot,None]
            posed=np.einsum('nij,nj->ni',B,base)+T;fair=posed.copy()
            for iteration in range(args.iterations):
                for coefficient in [.5,-.53]:
                    fair+=coefficient*mask[:,None]*(mean@fair-fair)
                    shift=fair-posed;sums=np.zeros((components,3));np.add.at(sums,labels,shift)
                    # Equal displacement keeps any pre-existing intentional seam
                    # gap, while adding no gap at a welded UV boundary.
                    fair=posed+sums[labels]/sizes[labels,None]
                shift=fair-posed;shift*=np.minimum(1,args.cap/np.maximum(np.linalg.norm(shift,axis=1),1e-9))[:,None];fair=posed+shift
            shift=fair-posed
            original_tri=posed[faces];original_cross=np.cross(original_tri[:,1]-original_tri[:,0],original_tri[:,2]-original_tri[:,0])
            original_area=np.linalg.norm(original_cross,axis=1)
            # Tiny triangles near a generated crease can turn inside out under
            # an otherwise smooth field. Locally retreat those vertices and
            # their seam copies, rather than accepting a new fold or shrinking
            # the whole corrective until its visible effect disappears.
            for retreat in range(60):
                current_tri=(posed+shift)[faces];current_cross=np.cross(current_tri[:,1]-current_tri[:,0],current_tri[:,2]-current_tri[:,0])
                bad=((original_cross*current_cross).sum(1)<=0)&(original_area>1e-12)
                bad|=(np.linalg.norm(current_cross,axis=1)<original_area*.15)&(original_area>1e-12)
                if not bad.any():break
                multiplier=np.ones(components);multiplier[np.unique(labels[faces[bad]])]=.65
                shift*=multiplier[labels,None]
            assert not bad.any(),'Elbow corrective creates an inverted or collapsed face'
            fair=posed+shift;active=np.linalg.norm(shift,axis=1)>1e-8
            delta=np.zeros_like(pos);delta[active]=np.einsum('nij,nj->ni',np.linalg.pinv(B[active]),shift[active])
            affected_faces=np.any(active[faces],axis=1);affected=np.zeros(len(pos),bool);affected[np.unique(faces[affected_faces])]=True
            old_geo=geometry_normals(posed,faces);new_geo=geometry_normals(fair,faces)
            rendered=unit(np.einsum('nij,nj->ni',B,unit(normal)))
            wanted=unit(rotate_between(old_geo,new_geo,rendered));wanted_rest=unit(np.einsum('nij,nj->ni',np.linalg.pinv(B),wanted))
            offset=n0-normal;along=np.sum(offset*wanted_rest,axis=1);disc=along*along+1-np.sum(offset*offset,axis=1)
            scale=-along+np.sqrt(np.maximum(disc,0));normal_delta=unit(offset+scale[:,None]*wanted_rest)-n0;normal_delta[~affected]=0
            target={'POSITION':append(doc,blob,attrs['POSITION'],delta.astype(np.float32)),
                    'NORMAL':append(doc,blob,attrs['NORMAL'],normal_delta.astype(np.float32))}
            primitive.setdefault('targets',[]).append(target)
            report['samples'].append({'phase':phase,'final_native_basis':native is not None,'moved_vertices':int(active.sum()),
                'skin_vertices':int((mask>0).sum()),'maximum_shift_m':float(np.linalg.norm(shift,axis=1).max()),
                'newly_inverted_faces':int(bad.sum()),'orientation_retreat_iterations':retreat,
                'shift_p95_m':float(np.percentile(np.linalg.norm(shift[active],axis=1),95)),
                'normal_turn_p95_deg':float(np.percentile(angle(old_geo[affected],new_geo[affected]),95)),
                'outside_skin_shift_max_m':float(np.linalg.norm(shift[mask==0],axis=1).max()),
                'uv_seam_gap_before_max_m':float(np.linalg.norm(posed[seams[:,0]]-posed[seams[:,1]],axis=1).max()) if len(seams) else 0,
                'uv_seam_added_gap_max_m':float(np.linalg.norm(shift[seams[:,0]]-shift[seams[:,1]],axis=1).max()) if len(seams) else 0})
    new_names=[PREFIX+f'{round(p*1000):03d}' for p in PHASES];names.extend(new_names)
    mesh['weights']=list(mesh.get('weights',[0]*count))+[0]*len(PHASES)
    if 'weights' in node:node['weights']+=([0]*len(PHASES))
    source_animations={a['name']:a for a in source_doc['animations']}
    for a in doc['animations']:
        old_a=source_animations[a['name']];old_c=next((c for c in old_a['channels'] if c['target']=={'node':ni,'path':'weights'}),None)
        if old_c:
            sampler=old_a['samplers'][old_c['sampler']];times=read(source_doc,source_blob,sampler['input']).ravel()
        else:times=np.array([0,max(float(read(doc,blob,s['input']).max()) for s in a['samplers'])])
        if a['name']=='stretch':times=np.unique(np.r_[times,np.array([0]+PHASES+[1])*duration]).astype(np.float32)
        previous=patch_weights(source_doc,source_blob,old_a,ni,count,times);output=np.c_[previous,np.zeros((len(times),len(PHASES)))]
        if a['name']=='stretch':
            for k in range(len(PHASES)):
                hat=np.zeros(6);hat[k+1]=1;output[:,count+k]=np.interp(times/duration,[0]+PHASES+[1],hat)
        template=a['samplers'][0]['input'];ti=append(doc,blob,template,times[:,None]);oi=append(doc,blob,template,output.reshape(-1,1));si=len(a['samplers'])
        a['samplers'].append({'input':ti,'output':oi,'interpolation':'LINEAR'});a['channels']=[c for c in a['channels'] if c['target']!={'node':ni,'path':'weights'}];a['channels'].append({'sampler':si,'target':{'node':ni,'path':'weights'}})
    save(doc,blob,args.output);report['output']=str(args.output);report['output_sha256']=hashlib.sha256(args.output.read_bytes()).hexdigest()
    args.report.write_text(json.dumps(report,indent=2)+'\n');print(args.report)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--manifest',type=Path);p.add_argument('--report',required=True,type=Path);p.add_argument('--cap',type=float,default=.012);p.add_argument('--iterations',type=int,default=60);prepare(p.parse_args())

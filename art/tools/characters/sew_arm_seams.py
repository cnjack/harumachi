"""Sew the original arm-cut garment edges by sharing their skin and morph fields.

No vertices/faces, UVs, textures, skeleton or animation are added or removed.
Only the short cloth-to-cloth seam and a bounded cloth geodesic neighbourhood
change. Source skin/cuff openings are outside the seam selection.
"""
from pathlib import Path
import argparse,hashlib,heapq,json
import numpy as np
from scipy.spatial import cKDTree
from scipy import sparse
from glb_io import load
from prepare_local_garments import read,colours,smooth
from prepare_sleeve_weights import cloth_mask
from repair_head_neck import append,save
from motion_math import world_matrices


def dense_part(d,b,node):
    mesh=d['meshes'][node['mesh']];p=mesh['primitives'][0];a=p['attributes'];j=read(d,b,a['JOINTS_0']);w=read(d,b,a['WEIGHTS_0'])
    if 'JOINTS_1' in a:j=np.c_[j,read(d,b,a['JOINTS_1'])];w=np.c_[w,read(d,b,a['WEIGHTS_1'])]
    skin=d['skins'][node['skin']];dense=np.zeros((len(j),len(skin['joints'])))
    for slot in range(j.shape[1]):np.add.at(dense,(np.arange(len(j)),j[:,slot]),w[:,slot])
    pos=read(d,b,a['POSITION']);faces=read(d,b,p['indices']).reshape(-1,3);edges=np.unique(np.sort(np.r_[faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]],axis=1),axis=0)
    return dict(node=node,mesh=mesh,p=p,a=a,pos=pos,j=j,w=w,dense=dense,edges=edges,names=mesh.get('extras',{}).get('targetNames',[]),shapes={name:read(d,b,target['POSITION']) for name,target in zip(mesh.get('extras',{}).get('targetNames',[]),p.get('targets',[]))},rgb=colours(d,b,p))


def field(part,anchors,allowed,radius):
    """Nearest boundary data propagated through actual cloth topology only."""
    points=part['pos'];edges=np.r_[part['edges'],cKDTree(points).query_pairs(1e-6,output_type='ndarray')];adj=[[] for _ in points]
    for a,b in edges:
        if not allowed[a] or not allowed[b]:continue
        length=float(np.linalg.norm(points[a]-points[b]));adj[a].append((int(b),length));adj[b].append((int(a),length))
    distance=np.full(len(points),np.inf);owner=np.full(len(points),-1,int);queue=[]
    for index in anchors:distance[index]=0;owner[index]=index;queue.append((0.,index,index))
    heapq.heapify(queue)
    while queue:
        dist,index,source=heapq.heappop(queue)
        if dist!=distance[index] or dist>radius:continue
        for target,length in adj[index]:
            candidate=dist+length
            if candidate<distance[target] and candidate<radius:distance[target]=candidate;owner[target]=source;heapq.heappush(queue,(candidate,target,source))
    envelope=1-smooth(0,radius,distance);envelope[~allowed]=0
    return owner,envelope


def sew(args):
    d,raw=load(args.input);b=bytearray(raw);nodes={n.get('name'):n for n in d['nodes']};parts={name:dense_part(d,b,nodes[name]) for name in ['CharacterBody','Sleeve_Left','Sleeve_Right']};body=parts['CharacterBody'];height=float(body['pos'][:,1].max());rest,_=world_matrices(d,b);ids={n.get('name'):i for i,n in enumerate(d['nodes'])};tree=cKDTree(body['pos']);groups=[];report={'input':str(args.input),'input_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),'character':args.character,'method':'same-position cloth seam copies share skin and morph deltas; geodesic feather into original cloth','feather_m':args.feather,'preserved':['all base POSITION/NORMAL','all UVs','all indices and triangle topology','all textures','skeleton/inverse binds','animations','bare skin and hand skinning'],'seams':[],'parts':[]}
    for side,sign in [('Left',1),('Right',-1)]:
        sleeve=parts['Sleeve_'+side]
        if sleeve['node']['skin']!=body['node']['skin']:raise ValueError('Sewing requires the shared original skin; never silently remap binds')
        shoulder=rest[ids['mixamorig:'+side+'Arm']][:3,3];matches=tree.query_ball_point(sleeve['pos'],1e-6);seen={}
        for si,members in enumerate(matches):
            if not members:continue
            point=sleeve['pos'][si]
            # The extraction boundary at the elbow includes the sleeve's
            # intentional cuff/skin opening. Sew only the medial shoulder seam.
            if abs(point[0])>abs(shoulder[0])+args.root_width*height or point[1]<shoulder[1]-.14*height:continue
            for bi in members:
                bc=body['rgb'][bi:bi+1];sc=sleeve['rgb'][si:si+1]
                if not (cloth_mask(args.character,bc)[0] and cloth_mask(args.character,sc)[0]):continue
                key=body['pos'][bi].tobytes();entry=seen.setdefault(key,{'CharacterBody':set(),'Sleeve_'+side:set()});entry['CharacterBody'].add(int(bi));entry['Sleeve_'+side].add(int(si))
        for entry in seen.values():
            # Include UV duplicates at this exact garment seam, even if their
            # atlas seam samples a slightly different shade of the same fabric.
            point=body['pos'][next(iter(entry['CharacterBody']))]
            for name,part in [('CharacterBody',body),('Sleeve_'+side,sleeve)]:
                copies=np.flatnonzero(np.all(part['pos']==point,axis=1));entry[name].update(map(int,copies))
            groups.append(entry)
        report['seams'].append({'side':side,'physical_seam_vertices':len(seen),'medial_boundary_max_abs_x_m':abs(float(shoulder[0]))+args.root_width*height})
    if not groups or any(s['physical_seam_vertices']<10 for s in report['seams']):raise ValueError('Not enough original cloth-to-cloth shoulder seam vertices')
    names=set.intersection(*(set(part['names']) for part in parts.values()))
    destinations={name:{} for name in parts};shape_destinations={name:{} for name in parts}
    for group in groups:
        per_part=[parts[name]['dense'][list(indices)].mean(0) for name,indices in group.items()];common=np.mean(per_part,axis=0);common/=common.sum()
        # Retain the original maximum influence count, using one shared row
        # before assigning it to every seam copy.
        count=min(parts[name]['j'].shape[1] for name in group);keep=np.argsort(common)[-count:];pruned=np.zeros_like(common);pruned[keep]=common[keep];common=pruned/pruned.sum()
        common_shapes={target:np.mean([parts[name]['shapes'][target][list(indices)].mean(0) for name,indices in group.items()],axis=0) for target in names}
        for name,indices in group.items():
            for target in set(parts[name]['names'])-names:
                if np.max(abs(parts[name]['shapes'][target][list(indices)]))>1e-7:raise ValueError('Mesh-only morph moves sewn edge; propagate its target/animation explicitly first: '+target)
            for index in indices:destinations[name][index]=common;shape_destinations[name][index]=common_shapes
    for name,part in parts.items():
        anchors=destinations[name]
        if not anchors:continue
        allowed=cloth_mask(args.character,part['rgb'])&(part['pos'][:,1]>.55*height)
        allowed[list(anchors)]=True;owner,envelope=field(part,anchors,allowed,args.feather);active=np.flatnonzero(envelope>1e-7);target=part['dense'].copy()
        for index in active:
            source=int(owner[index]);target[index]=np.maximum(0,part['dense'][index]+(destinations[name][source]-part['dense'][source])*envelope[index])
        target[active]/=np.maximum(target[active].sum(1,keepdims=True),1e-12)
        chosen=part['j'].copy();weights=part['w'].copy();active_joints=np.argsort(target[active],axis=1)[:,-part['j'].shape[1]:][:,::-1];active_weights=np.take_along_axis(target[active],active_joints,axis=1);active_weights/=np.maximum(active_weights.sum(1,keepdims=True),1e-12);chosen[active]=active_joints;weights[active]=active_weights
        # The exact boundary rows must use identical ordering and normalization.
        for index,common in anchors.items():
            row=np.argsort(common)[-part['j'].shape[1]:][::-1];chosen[index]=row;weights[index]=common[row]
        a=part['a'];a['JOINTS_0']=append(d,b,a['JOINTS_0'],chosen[:,:4].astype(part['j'].dtype));a['WEIGHTS_0']=append(d,b,a['WEIGHTS_0'],weights[:,:4].astype(part['w'].dtype))
        if 'JOINTS_1' in a:a['JOINTS_1']=append(d,b,a['JOINTS_1'],chosen[:,4:].astype(part['j'].dtype));a['WEIGHTS_1']=append(d,b,a['WEIGHTS_1'],weights[:,4:].astype(part['w'].dtype))
        changed_targets=[]
        for ti,target_name in enumerate(part['names']):
            if target_name not in names:continue
            old=part['shapes'][target_name];new=old.copy()
            for index in active:
                source=int(owner[index]);new[index]=old[index]+(shape_destinations[name][source][target_name]-old[source])*envelope[index]
            if np.max(abs(new-old))>1e-8:part['p']['targets'][ti]['POSITION']=append(d,b,part['a']['POSITION'],new.astype(np.float32));changed_targets.append(target_name)
        report['parts'].append({'mesh':name,'seam_vertices':len(anchors),'feathered_cloth_vertices':len(active),'changed_morph_positions':changed_targets,'skin_weight_max_change':float(abs(target-part['dense']).max())})
    next(n for n in d['nodes'] if n.get('name')=='Rig').setdefault('extras',{})['arm_seam_revision']={'version':1,'method':'shared medial garment seam skin and morph field','feather_m':args.feather}
    save(d,b,args.output);report['output']=str(args.output);report['output_sha256']=hashlib.sha256(args.output.read_bytes()).hexdigest();args.report.write_text(json.dumps(report,indent=2));print(args.report)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--report',required=True,type=Path);p.add_argument('--character',default='sora');p.add_argument('--feather',type=float,default=.065);p.add_argument('--root-width',type=float,default=.04);sew(p.parse_args())

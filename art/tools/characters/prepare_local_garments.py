"""Add bounded local garment correctives without changing vertices, UVs or textures.

Run with the project's numpy/scipy Python, not Blender. The output is a candidate
GLB; pass the structural/gait candidate as --input so independent fixes compose.
The runtime solver follows final leg IK and activates only contacted local panels.
"""
from pathlib import Path
import argparse, copy, hashlib, heapq, io, json, sys
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from repair_head_neck import append, save
from glb_io import load

def read(d, b, index):
    a=d['accessors'][index]; dtype=np.dtype({5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']]); width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    def fetch(view_id,offset,count,kind,cols):
        view=d['bufferViews'][view_id]
        return np.ndarray((count,cols),dtype=kind,buffer=b,offset=view.get('byteOffset',0)+offset,strides=(view.get('byteStride',cols*kind.itemsize),kind.itemsize)).copy()
    values=fetch(a['bufferView'],a.get('byteOffset',0),a['count'],dtype,width) if 'bufferView' in a else np.zeros((a['count'],width),dtype)
    if 'sparse' in a:
        sparse=a['sparse']; ids=sparse['indices']; kind=np.dtype({5121:'u1',5123:'<u2',5125:'<u4'}[ids['componentType']]); indices=fetch(ids['bufferView'],ids.get('byteOffset',0),sparse['count'],kind,1).ravel(); source=sparse['values'];values[indices]=fetch(source['bufferView'],source.get('byteOffset',0),sparse['count'],dtype,width)
    return values

PREFIX = 'Garment_Local_'
ROWS, COLUMNS = 3, 4
AMPLITUDE = .12


def smooth(a, b, x):
    t = np.clip((x-a)/(b-a), 0, 1)
    return t*t*(3-2*t)


def colours(d, b, p):
    m = d['materials'][p['material']]['pbrMetallicRoughness']
    image = d['images'][d['textures'][m['baseColorTexture']['index']]['source']]
    view = d['bufferViews'][image['bufferView']]
    texture = np.asarray(Image.open(io.BytesIO(b[view.get('byteOffset', 0):view.get('byteOffset', 0)+view['byteLength']])).convert('RGB'))/255.
    uv = read(d,b,p['attributes']['TEXCOORD_0'])
    return texture[(uv[:,1]*texture.shape[0]).astype(int)%texture.shape[0], (uv[:,0]*texture.shape[1]).astype(int)%texture.shape[1]]


def select_cloth(points, normals, colour, faces, who, height, split_depth):
    x,y,z = points.T; r,g,b = colour.T
    band = (abs(x)<.24*height)&(y>.20*height)&(y<.59*height)
    if who == 'mio':
        seeds = (b>r*1.08)&(b>g*1.04)&(r+g+b<1.)
        # Legs must never be part of the corrective, including border smoothing.
        skin = (r>g*1.10)&(g>b*1.02)&(r>.30)
        eligible = band&~skin
    elif who == 'kazuko':
        seeds = (r>g*.95)&(r<g*1.9)&(b<g*.65)&(g>.18)
        # Deep folds of yellow cloth can be darker than black-pants' old
        # brightness cutoff. Real trousers are neutral, unlike these folds.
        dark_trousers=(colour.max(1)<.36)&(colour.max(1)-colour.min(1)<.08)
        eligible = band&~dark_trousers
    else:
        # Ren's khaki trousers are bright, too. Luminance alone included
        # thousands of pants vertices in the old white-apron patches.
        spread=colour.max(1)-colour.min(1)
        trousers=(r>g*1.04)&(g>b*1.08)
        seeds = (colour.min(1)>.50)&(spread<.08)&~trousers
        eligible = band&(colour.min(1)>.36)&(spread<.10)&~trousers
    seeds &= band
    # A front/back panel is selected by orientation and connected garment colour.
    # The folded undersides stay with the panel by their actual rest depth.
    # Anatomical hip depth defines the front/back half, not the median of an
    # asymmetric pleated or apron mesh. The old median was 45mm off for Mio.
    split = float(split_depth)
    sides = []
    edges = np.unique(np.sort(np.r_[faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]],axis=1),axis=0)
    adjacency = [[] for _ in points]
    for a,b in edges:
        length = float(np.linalg.norm(points[a]-points[b]))
        adjacency[a].append((int(b),length)); adjacency[b].append((int(a),length))
    # Seam copies share garment masks so a UV split never creates a crack.
    duplicates = cKDTree(points).query_pairs(1e-6,output_type='ndarray')
    for a,b in duplicates:
        adjacency[a].append((int(b),0.)); adjacency[b].append((int(a),0.))
    for sign in [1,-1]:
        fold=(normals[:,1]<-.60)&(abs(normals[:,0])<.50)&((z-split)*sign>.01)&(y<.36*height)
        # A pleat's inward-facing wall is still the same physical panel. The
        # old normal-facing filter pinned those walls while the neighboring
        # outer folds moved, exposing thin strips of the leg through the fold.
        panel = eligible&((z-split)*sign>.008)
        seed = seeds&panel
        distance=np.full(len(points),np.inf);distance[seed]=0
        queue=[(0.,int(i)) for i in np.flatnonzero(seed)];heapq.heapify(queue)
        while queue:
            value,i=heapq.heappop(queue)
            if value!=distance[i]:continue
            for j,length in adjacency[i]:
                candidate=value+length
                if panel[j] and candidate<distance[j] and (who=='ren' or candidate<.016):
                    distance[j]=candidate;heapq.heappush(queue,(candidate,j))
        # Low-chroma warm shadows remain connected white apron material; an
        # arbitrary 16mm pigment-seed radius must not pin their inner folds.
        mask=np.isfinite(distance).astype(float) if who=='ren' else 1-smooth(0,.016,distance)
        # Gradually pin the waist and leave the source side slit intact.
        waist=1-smooth(.44*height,.59*height,y)
        # Feather at the real side opening, independent of local face normal.
        # This keeps inner pleats and turned-under hems attached to the panel.
        side=smooth(.008,.025,(z-split)*sign)
        mask*=waist*side
        sides.append(mask)
    return sides, edges


def equalize_seams(points,joints,weights,masks,protected):
    """Keep coincident UV/hard-edge copies closed without welding any source data."""
    pairs=cKDTree(points).query_pairs(1e-6,output_type='ndarray');parent=np.arange(len(points));changed=0
    def root(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    for a,b in pairs:
        if protected[a] or protected[b] or not np.array_equal(joints[a],joints[b]) or np.max(abs(weights[a]-weights[b]))>1e-7:continue
        parent[root(int(b))]=root(int(a))
    groups={}
    for i in np.unique(pairs):groups.setdefault(root(int(i)),[]).append(int(i))
    for group in groups.values():
        if len(group)<2:continue
        for mask in masks:
            maximum=float(mask[group].max())
            if np.ptp(mask[group])>1e-7:changed+=1
            mask[group]=maximum
    return changed


def prepare(source, output, who, report_path, mio_follow=0., amplitude=AMPLITUDE, clearance_margin=.006):
    d, binary=load(source); b=bytearray(binary)
    rig=next(n for n in d['nodes'] if n.get('name')=='Rig')
    if rig.setdefault('extras',{}).get('garment_local_clearance'):
        raise ValueError('Input already has local garment correctives; use the unpatched merged structural/gait candidate')
    body_node=next(n for n in d['nodes'] if 'mesh' in n and 'skin' in n and not n.get('name','').startswith(('HiddenArm','Sleeve')))
    mesh=d['meshes'][body_node['mesh']]; skin=d['skins'][body_node['skin']]
    target_names=mesh.setdefault('extras',{}).setdefault('targetNames',[])
    original_count=len(mesh.get('weights',target_names)); assert original_count==len(target_names)
    local_names=[f'{PREFIX}{side}_{row}_{col}' for side in ['Front','Back'] for row in range(ROWS) for col in range(COLUMNS)]
    names={n.get('name'):i for i,n in enumerate(d['nodes'])}
    hip=skin['joints'].index(names['mixamorig:Hips']); left=skin['joints'].index(names['mixamorig:LeftUpLeg']); right=skin['joints'].index(names['mixamorig:RightUpLeg'])
    from motion_math import world_matrices
    rest_world,_=world_matrices(d,b)
    split_depth=float(rest_world[names['mixamorig:Hips']][2,3])
    report={'character':who,'input':str(source),'input_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'preserved':['POSITION','NORMAL','TANGENT','TEXCOORD_0','indices','images','joint hierarchy','inverseBindMatrices','skeletal animation'],'local_patch_rows':ROWS,'local_patch_columns':COLUMNS,'maximum_local_displacement_m':amplitude,'removed_global_inflation':True,'primitives':[]}
    for p in mesh['primitives']:
        attrs=p['attributes'];points=read(d,b,attrs['POSITION']);normals=read(d,b,attrs['NORMAL']);faces=read(d,b,p['indices']).reshape(-1,3);height=float(points[:,1].max());colour=colours(d,b,p)
        joints=read(d,b,attrs['JOINTS_0']); weights=read(d,b,attrs['WEIGHTS_0'])
        if 'JOINTS_1' in attrs:joints=np.c_[joints,read(d,b,attrs['JOINTS_1'])];weights=np.c_[weights,read(d,b,attrs['WEIGHTS_1'])]
        masks,edges=select_cloth(points,normals,colour,faces,who,height,split_depth)
        cr,cg,cb=colour.T
        if who=='mio':
            leg_binds=np.array([any(part in d['nodes'][ji].get('name','') for part in ['UpLeg','Leg','Foot','Toe']) for ji in skin['joints']]);leg_share=np.sum(weights*leg_binds[joints],axis=1);protected=(cr>cg*1.10)&(cg>cb*1.02)&(cr>.30)&(leg_share>.65)
        elif who=='kazuko':
            protected=(colour.max(1)<.36)&(colour.max(1)-colour.min(1)<.08)
            # One UV copy can sample a dark texel while its identical physical
            # cloth vertex samples yellow. Classify the physical seam together.
            keys=lambda i:points[i].tobytes()+joints[i].tobytes()+weights[i].tobytes()
            non_black_keys={keys(i) for i in np.flatnonzero(~protected)}
            for i in np.flatnonzero(protected):
                if keys(i) in non_black_keys:protected[i]=False
        else:protected=(cr>cg*1.04)&(cg>cb*1.08)
        seam_groups=equalize_seams(points,joints,weights,masks,protected)
        if max(np.count_nonzero(m) for m in masks)<200:raise ValueError('Not enough real garment coverage')
        allmask=np.maximum(*masks)
        active=allmask>1e-5;lower=float(np.quantile(points[active,1],.01));upper=.56*height
        maxx=float(np.quantile(abs(points[active,0]),.98));gx=np.linspace(-maxx,maxx,COLUMNS);gy=np.linspace(lower,upper,ROWS)
        targets=[]
        for sign,mask in zip([1,-1],masks):
            for cy in gy:
                yy=np.clip(1-abs(points[:,1]-cy)/((upper-lower)/(ROWS-1)),0,1)
                yy=smooth(0,1,yy)
                # Below the lowest row, continue the hem's own row, not zero.
                if cy==gy[0]:yy[points[:,1]<lower]=1
                for cx in gx:
                    xx=np.clip(1-abs(points[:,0]-cx)/(2*maxx/(COLUMNS-1)),0,1);xx=smooth(0,1,xx)
                    if cx==gx[0]:xx[points[:,0]<gx[0]]=1
                    if cx==gx[-1]:xx[points[:,0]>gx[-1]]=1
                    delta=np.zeros_like(points);delta[:,2]=sign*amplitude*mask*xx*yy
                    target={'POSITION':append(d,b,attrs['POSITION'],delta)}
                    if 'NORMAL' in attrs:target['NORMAL']=append(d,b,attrs['NORMAL'],np.zeros_like(normals))
                    if 'TANGENT' in attrs:target['TANGENT']=append(d,b,attrs['NORMAL'],np.zeros_like(normals))
                    targets.append(target)
        p.setdefault('targets',[]).extend(targets)
        # Continuous modest thigh sharing adds drape; no independent stiff halves.
        bottom=1-smooth(.34*height,.53*height,points[:,1]);amount=bottom*({'mio':mio_follow,'ren':.30,'kazuko':.34}[who]);share=smooth(-.04*height,.04*height,points[:,0]) if who=='mio' else smooth(-.12*height,.12*height,points[:,0])
        newweights=weights.copy();newjoints=joints.copy()
        for i in np.flatnonzero(active if who == "ren" or (who=="mio" and mio_follow>0) else np.zeros_like(active)):
            alpha=float(allmask[i]); desired={hip:1-float(amount[i]),left:float(amount[i]*share[i]),right:float(amount[i]*(1-share[i]))}
            row={int(j):float(w*(1-alpha)) for j,w in zip(joints[i],weights[i]) if w>0}
            for j,w in desired.items():row[j]=row.get(j,0)+w*alpha
            row=sorted(row.items(),key=lambda kv:kv[1],reverse=True)[:joints.shape[1]];total=sum(w for _,w in row)
            newweights[i]=0;newjoints[i]=0
            for k,(j,w) in enumerate(row):newjoints[i,k]=j;newweights[i,k]=w/total
        attrs['JOINTS_0']=append(d,b,attrs['JOINTS_0'],newjoints[:,:4]);attrs['WEIGHTS_0']=append(d,b,attrs['WEIGHTS_0'],newweights[:,:4])
        if 'JOINTS_1' in attrs:
            attrs['JOINTS_1']=append(d,b,attrs['JOINTS_1'],newjoints[:,4:]);attrs['WEIGHTS_1']=append(d,b,attrs['WEIGHTS_1'],newweights[:,4:])
        report['primitives'].append({'vertices':len(points),'front_vertices':int(np.count_nonzero(masks[0])),'back_vertices':int(np.count_nonzero(masks[1])),'uv_seam_groups_equalized':seam_groups,'protected_body_patch_overlap_vertices':int(np.count_nonzero(protected&active)),'weight_changed_vertices':int(np.count_nonzero(np.any(newweights!=weights,axis=1))),'patches':len(targets),'max_thigh_share':float(amount[active].max()) if who=='ren' or mio_follow>0 else 'source weights preserved','source_envelope_unchanged':True})
    target_names.extend(local_names);mesh['weights']=list(mesh.get('weights',[0]*original_count))+[0]*len(local_names)
    if 'weights' in body_node:body_node['weights']+=([0]*len(local_names))
    for a in d.get('animations',[]):
        for c in a['channels']:
            if c['target']!={'node':d['nodes'].index(body_node),'path':'weights'}:continue
            sampler=a['samplers'][c['sampler']];values=read(d,b,sampler['output']).reshape(-1,original_count)
            values=np.c_[values,np.zeros((len(values),len(local_names)),np.float32)]
            for i,name in enumerate(target_names[:original_count]):
                if name in ['Skirt_Clearance','Apron_Clearance']:values[:,i]=0
            sampler['output']=append(d,b,sampler['output'],values.reshape(-1,1))
    body_reference={}
    if who=='mio':
        body_p=mesh['primitives'][0];body_pos=read(d,b,body_p['attributes']['POSITION']);body_colour=colours(d,b,body_p);cr,cg,cb=body_colour.T;h=float(body_pos[:,1].max());visible=(body_pos[:,1]>.20*h)&(body_pos[:,1]<.36*h)&(cr>cg*1.10)&(cg>cb*1.02)&(cr>.30)
        body_reference={'body_rgb_reference':np.median(body_colour[visible],axis=0).tolist(),'body_rgb_tolerance':.12}
    rig['extras']['garment_local_clearance']={'version':1,'character':who,'rows':ROWS,'columns':COLUMNS,'shape_prefix':PREFIX,'shape_amplitude_m':amplitude,'maximum_weight':1.,'clearance_margin_m':clearance_margin,'disable_global_shapes':['Skirt_Clearance','Apron_Clearance'],**body_reference}
    save(d,b,output);report['output']=str(output);report['output_sha256']=hashlib.sha256(output.read_bytes()).hexdigest()
    report_path.parent.mkdir(parents=True,exist_ok=True);report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--input',required=True,type=Path);parser.add_argument('--output',required=True,type=Path);parser.add_argument('--character',required=True,choices=['mio','ren','kazuko']);parser.add_argument('--report',required=True,type=Path);parser.add_argument('--mio-follow',type=float,default=0.);parser.add_argument('--maximum-displacement',type=float,default=AMPLITUDE);parser.add_argument('--clearance-margin',type=float,default=.006)
    args=parser.parse_args();prepare(args.input,args.output,args.character,args.report,args.mio_follow,args.maximum_displacement,args.clearance_margin)

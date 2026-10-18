"""Geometry-following corrective normals preserving authored hard-edge offsets.

Only new corrective NORMAL accessors change. Base NORMAL, UVs, indices, positions,
textures, skin and all shape position deltas stay exact. Godot's pinned skeleton
shader uses the weighted bone basis for both normals and vertices:
https://raw.githubusercontent.com/godotengine/godot/c971f93e7/servers/rendering/renderer_rd/shaders/skeleton.glsl
"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from glb_io import load
from prepare_local_garments import read
from repair_head_neck import append,save
from motion_math import world_matrices


def unit(v):return v/np.maximum(np.linalg.norm(v,axis=1,keepdims=True),1e-12)


def geometry_normals(points,faces):
    t=points[faces];norm=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);result=np.zeros_like(points,dtype=float)
    for corner in range(3):np.add.at(result,faces[:,corner],norm)
    return unit(result)


def rotate_between(old,new,vectors):
    old=unit(old);new=unit(new);cross=np.cross(old,new);dot=np.sum(old*new,axis=1);first=np.cross(cross,vectors);second=np.cross(cross,first);result=vectors+first+second/np.maximum(1+dot[:,None],1e-8)
    singular=dot<-.9999
    if singular.any():
        axis=np.cross(old[singular],np.array([1.,0,0]));small=np.linalg.norm(axis,axis=1)<1e-6;axis[small]=np.cross(old[singular][small],np.array([0.,1,0]));axis=unit(axis);result[singular]=2*axis*np.sum(axis*vectors[singular],axis=1,keepdims=True)-vectors[singular]
    return result


def angle(a,b):return np.degrees(np.arccos(np.clip(np.sum(unit(a)*unit(b),axis=1),-1,1)))


def shape_values(d,b,animation,ni,count,time):
    result=np.zeros(count)
    for c in animation['channels']:
        if c['target']!={'node':ni,'path':'weights'}:continue
        s=animation['samplers'][c['sampler']];ts=read(d,b,s['input']).ravel();vs=read(d,b,s['output']).reshape(-1,count);result=np.array([np.interp(time,ts,vs[:,i]) for i in range(count)])
    return result


def fix(args):
    d,binary=load(args.input);b=bytearray(binary);report={'input':str(args.input),'input_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),'preserved':['base NORMAL','POSITION','target POSITION','indices','UVs','textures','skin','joint hierarchy','animations'],'normal_policy':'rotate authored normal by old-to-new geometric face-normal rotation; never weld UV or hard-edge normals','targets':[]}
    prefixes=tuple(args.prefixes.split(','))
    for ni,node in enumerate(d['nodes']):
        if 'mesh' not in node or 'skin' not in node:continue
        mesh=d['meshes'][node['mesh']];names=mesh.get('extras',{}).get('targetNames',[]);skin=d['skins'][node['skin']];bind=read(d,b,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
        for primitive in mesh['primitives']:
            attrs=primitive['attributes'];points=read(d,b,attrs['POSITION']);normals=unit(read(d,b,attrs['NORMAL']));faces=read(d,b,primitive['indices']).reshape(-1,3);j=read(d,b,attrs['JOINTS_0']);w=read(d,b,attrs['WEIGHTS_0'])
            if 'JOINTS_1' in attrs:j=np.c_[j,read(d,b,attrs['JOINTS_1'])];w=np.c_[w,read(d,b,attrs['WEIGHTS_1'])]
            source_shapes=[read(d,b,t['POSITION']) for t in primitive.get('targets',[])];source_normals=[unit(normals+read(d,b,t['NORMAL']))-normals if 'NORMAL' in t else np.zeros_like(points) for t in primitive.get('targets',[])]
            for target_index,name in enumerate(names):
                if not name.startswith(prefixes):continue
                delta=source_shapes[target_index]
                moved=np.linalg.norm(delta,axis=1)>1e-8;affected_faces=np.any(moved[faces],axis=1);affected=np.zeros(len(points),bool);affected[np.unique(faces[affected_faces])]=True
                if not moved.any():continue
                base=points.copy();rest_normal=normals.copy();linear=np.broadcast_to(np.eye(3),(len(points),3,3)).copy()
                if name.startswith('SleeveFit_'):
                    _,clip,phase_text=name.split('_');phase=int(phase_text)/1000.;animation=next(a for a in d['animations'] if a['name']==clip);duration=max(float(read(d,b,s['input']).max()) for s in animation['samplers']);values=shape_values(d,b,animation,ni,len(names),duration*phase)
                    for index,value in enumerate(values):
                        if names[index].startswith(('SleeveFit_','Garment_Local_')):continue
                        base+=value*source_shapes[index];rest_normal+=value*source_normals[index]
                    worlds,_=world_matrices(d,b,animation,duration*phase);matrices=np.array([worlds[ji]@ib for ji,ib in zip(skin['joints'],bind)]);linear=np.zeros((len(points),3,3));translation=np.zeros_like(points)
                    for slot in range(j.shape[1]):linear+=matrices[j[:,slot],:3,:3]*w[:,slot,None,None];translation+=matrices[j[:,slot],:3,3]*w[:,slot,None]
                    before=np.einsum('nij,nj->ni',linear,base)+translation;after=before+np.einsum('nij,nj->ni',linear,delta)
                else:before=base;after=base+delta
                old_geo=geometry_normals(before,faces);new_geo=geometry_normals(after,faces);old_render=unit(np.einsum('nij,nj->ni',linear,unit(rest_normal)));wanted_world=unit(rotate_between(old_geo,new_geo,old_render));wanted_rest=unit(np.einsum('nij,nj->ni',np.linalg.pinv(linear),wanted_world))
                # Godot oct-encodes each normalized target's normal separately.
                # Solve its unit-vector length before adding the other active
                # source targets; this mirrors the pinned import/shader order.
                offset=normals-rest_normal;along=np.sum(offset*wanted_rest,axis=1);discriminant=along*along+1-np.sum(offset*offset,axis=1);unreachable=discriminant<0;scale=-along+np.sqrt(np.maximum(discriminant,0));target_normal=unit(offset+scale[:,None]*wanted_rest);normal_delta=target_normal-normals;normal_delta[~affected]=0
                # This keeps every seam vertex's authored offset. It does not
                # replace the asset's normals with generic smooth vertex normals.
                primitive['targets'][target_index]['NORMAL']=append(d,b,attrs['NORMAL'],normal_delta.astype(np.float32));source_normals[target_index]=unit(normals+normal_delta)-normals;turn=angle(old_geo[affected],new_geo[affected]);previous_error=angle(old_render[affected],wanted_world[affected]);corrected_world=unit(np.einsum('nij,nj->ni',linear,unit(rest_normal+(unit(normals+normal_delta)-normals))));new_error=angle(corrected_world[affected],wanted_world[affected]);tri_before=before[faces];tri_after=after[faces];face_old=np.cross(tri_before[:,1]-tri_before[:,0],tri_before[:,2]-tri_before[:,0]);face_new=np.cross(tri_after[:,1]-tri_after[:,0],tri_after[:,2]-tri_after[:,0]);face_turn=angle(face_old,face_new);areas=np.linalg.norm(face_old,axis=1)*.5;total_area=float(areas[affected_faces].sum())
                report['targets'].append({'unreachable_unit_normal_vertices':int(np.count_nonzero(unreachable&affected)),'over90_degree_geometric_turn_area_fraction':float(areas[affected_faces&(face_turn>90)].sum()/max(total_area,1e-12)),'mesh':node['name'],'target':name,'affected_vertices':int(affected.sum()),'geometric_turn_p95_deg':float(np.percentile(turn,95)),'geometric_turn_max_deg':float(turn.max()),'zero_delta_shading_error_p95_deg':float(np.percentile(previous_error,95)),'corrected_error_p95_deg':float(np.percentile(new_error,95)),'max_normal_delta':float(np.linalg.norm(normal_delta,axis=1).max())})
    save(d,b,args.output);report['output']=str(args.output);report['output_sha256']=hashlib.sha256(args.output.read_bytes()).hexdigest();args.report.write_text(json.dumps(report,indent=2));print(args.report)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--prefixes',default='SleeveFit_,Garment_Local_');fix(p.parse_args())

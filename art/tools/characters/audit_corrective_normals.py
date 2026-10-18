"""Audit actual native morph weights/final bases against geometric normal changes."""
from pathlib import Path
import argparse,json,hashlib
import numpy as np
from corrective_normals import geometry_normals,rotate_between,unit,angle
from prepare_local_garments import read
from glb_io import load
from motion_math import world_matrices


def audit(args):
    d,b=load(args.before);fixed,fb=load(args.after);rows=[r for r in json.loads(args.manifest.read_text())['shots'] if r['id']==args.character];out=[]
    provenance=args.manifest.parent.parent/'model-hashes.json'
    if not provenance.exists() or json.loads(provenance.read_text()).get(f'CH_{args.character}.glb')!=hashlib.sha256(args.before.read_bytes()).hexdigest():raise ValueError('Before model must match the native capture model SHA, not only target names')
    for row in rows:
        animation=next(a for a in d['animations'] if a['name']==row['clip']);worlds,_=world_matrices(d,b,animation,row['clip_time']);ids={n.get('name'):i for i,n in enumerate(d['nodes'])}
        for bone in row['bones']:
            name=bone['name'].replace('mixamorig_','mixamorig:')
            if name not in ids:continue
            worlds[ids[name]][:3,:3]=np.array(bone['basis']).T;worlds[ids[name]][:3,3]=np.array(bone['position'])-np.array(row['position'])
        for node in d['nodes']:
            if 'skin' not in node or 'mesh' not in node:continue
            mesh=d['meshes'][node['mesh']];names=mesh.get('extras',{}).get('targetNames',[])
            if not any(n.startswith(('SleeveFit_','Garment_Local_')) for n in names):continue
            native=row.get('blend_shape_values',{}).get(node.get('name'),{})
            if any(name not in native for name in names):raise ValueError('Native morph table does not match candidate')
            values=np.array([native[name] for name in names]);skin=d['skins'][node['skin']];bind=read(d,b,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1);matrices=np.array([worlds[j]@ib for j,ib in zip(skin['joints'],bind)]);fixed_node=next(n for n in fixed['nodes'] if n.get('name')==node.get('name'))
            fixed_mesh=fixed['meshes'][fixed_node['mesh']];fixed_skin=fixed['skins'][fixed_node['skin']]
            if names!=fixed_mesh.get('extras',{}).get('targetNames',[]) or skin['joints']!=fixed_skin['joints'] or not np.array_equal(read(d,b,skin['inverseBindMatrices']),read(fixed,fb,fixed_skin['inverseBindMatrices'])):raise ValueError('Normal-only audit requires the same target layout and bind matrices')
            for pi,p in enumerate(mesh['primitives']):
                fp=fixed['meshes'][fixed_node['mesh']]['primitives'][pi];a=p['attributes'];pos=read(d,b,a['POSITION']);n0=unit(read(d,b,a['NORMAL']));faces=read(d,b,p['indices']).reshape(-1,3);j=read(d,b,a['JOINTS_0']);w=read(d,b,a['WEIGHTS_0'])
                for field,accessor in a.items():
                    if not np.array_equal(read(d,b,accessor),read(fixed,fb,fp['attributes'][field])):raise ValueError(f'Normal-only audit cannot compare changed base attribute {field}')
                for old_target,new_target in zip(p['targets'],fp['targets']):
                    if not np.array_equal(read(d,b,old_target['POSITION']),read(fixed,fb,new_target['POSITION'])):raise ValueError('Normal-only audit cannot compare changed corrective POSITION geometry')
                if 'JOINTS_1' in a:j=np.c_[j,read(d,b,a['JOINTS_1'])];w=np.c_[w,read(d,b,a['WEIGHTS_1'])]
                base=pos.copy();posed=pos.copy();old_rest=n0.copy();new_rest=n0.copy();reference_rest=n0.copy();active=np.zeros(len(pos),bool)
                for index,value in enumerate(values):
                    delta=read(d,b,p['targets'][index]['POSITION']);posed+=value*delta;new_shape=names[index].startswith(('SleeveFit_','Garment_Local_'))
                    if not new_shape:base+=value*delta
                    elif abs(value)>1e-8:active|=np.linalg.norm(delta,axis=1)>1e-8
                    previous=unit(n0+read(d,b,p['targets'][index]['NORMAL']))-n0 if 'NORMAL' in p['targets'][index] else np.zeros_like(pos);new=unit(n0+read(fixed,fb,fp['targets'][index]['NORMAL']))-n0 if 'NORMAL' in fp['targets'][index] else np.zeros_like(pos);old_rest+=value*previous;new_rest+=value*new
                    if not new_shape:reference_rest+=value*previous
                if not active.any():continue
                af=np.any(active[faces],axis=1);affected=np.zeros(len(pos),bool);affected[np.unique(faces[af])]=True;B=np.zeros((len(pos),3,3));translation=np.zeros_like(pos)
                for slot in range(j.shape[1]):B+=matrices[j[:,slot],:3,:3]*w[:,slot,None,None];translation+=matrices[j[:,slot],:3,3]*w[:,slot,None]
                before=np.einsum('nij,nj->ni',B,base)+translation;actual=np.einsum('nij,nj->ni',B,posed)+translation;reference=unit(np.einsum('nij,nj->ni',B,unit(reference_rest)));wanted=unit(rotate_between(geometry_normals(before,faces),geometry_normals(actual,faces),reference));old_render=unit(np.einsum('nij,nj->ni',B,unit(old_rest)));new_render=unit(np.einsum('nij,nj->ni',B,unit(new_rest)));old_error=angle(old_render[affected],wanted[affected]);new_error=angle(new_render[affected],wanted[affected]);turn=angle(geometry_normals(before,faces)[affected],geometry_normals(actual,faces)[affected]);out.append({'file':row['file'],'clip':row['clip'],'phase':row.get('phase'),'mesh':node['name'],'affected_vertices':int(affected.sum()),'geometric_turn_p95_deg':float(np.percentile(turn,95)),'old_error_p95_deg':float(np.percentile(old_error,95)),'fixed_error_p95_deg':float(np.percentile(new_error,95)),'fixed_error_max_deg':float(new_error.max())})
    args.output.write_text(json.dumps({'before':str(args.before),'after':str(args.after),'scope':'native final world bases and actual morph values; Godot normalized-target normal composition mirrored','samples':out},indent=2));print(args.output)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--before',type=Path,required=True);p.add_argument('--after',type=Path,required=True);p.add_argument('--character',required=True);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True);audit(p.parse_args())

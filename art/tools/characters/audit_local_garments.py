"""Independent full source-triangle rays for local post-IK cloth candidates.

For exact native validation pass --manifest with final world basis on every bone.
Without it, the report explicitly describes authored skeleton sampling only.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from motion_math import world_matrices, sample_channel
from glb_io import load
from prepare_local_garments import colours, select_cloth, read


def template_seam_gap(state):
    from scipy.spatial import cKDTree
    if not state['local']:return 0.
    pairs=cKDTree(state['positions']).query_pairs(1e-6,output_type='ndarray')
    if not len(pairs):return 0.
    same=np.all(state['joints'][pairs[:,0]]==state['joints'][pairs[:,1]],axis=1)&(np.max(abs(state['weights'][pairs[:,0]]-state['weights'][pairs[:,1]]),axis=1)<1e-7)
    pairs=pairs[same]
    return max((float(np.linalg.norm(state['shapes'][i][pairs[:,0]]-state['shapes'][i][pairs[:,1]],axis=1).max()) for i in state['local']),default=0.) if len(pairs) else 0.


def layer_hits(points,faces,body,sign,cell=.035,normal_min=.35):
    tris=points[faces];cross=np.cross(tris[:,1]-tris[:,0],tris[:,2]-tris[:,0]);length=np.linalg.norm(cross,axis=1);normal_z=np.divide(abs(cross[:,2]),length,out=np.zeros_like(length),where=length>1e-12)
    lo=tris[:,:,:2].min(1);hi=tris[:,:,:2].max(1);bins={}
    # Select the actual exterior face before applying the legacy normal gate.
    # Filtering steep outer pleats first would raycast a hidden inner wall and
    # invent penetration even when the entire leg is behind the exterior cloth.
    for i in np.flatnonzero(length>1e-12):
        first=np.floor(lo[i]/cell).astype(int);last=np.floor(hi[i]/cell).astype(int)
        for x in range(first[0],last[0]+1):
            for y in range(first[1],last[1]+1):bins.setdefault((x,y),[]).append(i)
    hits=[]
    for body_id in body:
        point=points[body_id];key=tuple(np.floor(point[:2]/cell).astype(int));possible=bins.get(key)
        if not possible:continue
        ids=np.asarray(possible);triangle=tris[ids];a=triangle[:,0];first=triangle[:,1]-a;second=triangle[:,2]-a;at=point-a
        determinant=first[:,0]*second[:,1]-first[:,1]*second[:,0];valid=abs(determinant)>1e-10
        u=np.divide(at[:,0]*second[:,1]-at[:,1]*second[:,0],determinant,out=np.full(len(ids),-1.),where=valid);v=np.divide(first[:,0]*at[:,1]-first[:,1]*at[:,0],determinant,out=np.full(len(ids),-1.),where=valid)
        valid&=(u>=-1e-6)&(v>=-1e-6)&(u+v<=1+1e-6)
        selected=np.flatnonzero(valid)
        if not len(selected):continue
        z=a[:,2]+u*first[:,2]+v*second[:,2];chosen=selected[np.argmax(z[selected]*sign)];weights=np.array([1-u[chosen]-v[chosen],u[chosen],v[chosen]])
        if normal_min is not None and normal_z[ids[chosen]]<normal_min:continue
        hits.append((int(body_id),faces[ids[chosen]],weights,float(sign*(point[2]-z[chosen]))))
    return hits


def mesh_state(path,who):
    d,b=load(path);node=next(n for n in d['nodes'] if 'mesh' in n and 'skin' in n and not n.get('name','').startswith(('HiddenArm','Sleeve')));ni=d['nodes'].index(node);mesh=d['meshes'][node['mesh']];p=mesh['primitives'][0];attrs=p['attributes'];skin=d['skins'][node['skin']]
    positions=read(d,b,attrs['POSITION']);normals=read(d,b,attrs['NORMAL']);joints=read(d,b,attrs['JOINTS_0']);weights=read(d,b,attrs['WEIGHTS_0'])
    if 'JOINTS_1' in attrs:joints=np.c_[joints,read(d,b,attrs['JOINTS_1'])];weights=np.c_[weights,read(d,b,attrs['WEIGHTS_1'])]
    texture=colours(d,b,p);height=positions[:,1].max();x,y,z=positions.T;r,g,blue=texture.T
    region=(abs(x)<.16*height)&(y>.20*height)&(y<.55*height)
    joint_names=[d['nodes'][ji].get('name','') for ji in skin['joints']];leg_binds=np.array([('UpLeg' in name or name.endswith('Leg') or 'Foot' in name or 'Toe' in name) for name in joint_names]);leg_share=np.sum(weights*leg_binds[joints],axis=1)
    skin_hue=(r>g*1.1)&(g>blue*1.02)&(r>.30)
    visible=region&(y<.36*height)&skin_hue&(leg_share>.95)
    reference=np.median(texture[visible],axis=0) if visible.any() else np.array([.92,.73,.63])
    palette_match=np.linalg.norm(texture-reference,axis=1)<.12
    # Ren's original upper trousers are hips-dominant, so a leg-only test
    # would silently omit most thighs. Their warm khaki pigment separates
    # them from the low-chroma white apron, including its shaded folds.
    khaki=(r>g*1.04)&(g>blue*1.08)
    neutral_dark=(texture.max(1)<.36)&(texture.max(1)-texture.min(1)<.08)
    if who=='kazuko':
        def signature(i):return positions[i].tobytes()+joints[i].tobytes()+weights[i].tobytes()
        non_black_keys={signature(i) for i in np.flatnonzero(~neutral_dark)}
        for i in np.flatnonzero(neutral_dark):
            if signature(i) in non_black_keys:neutral_dark[i]=False
    body=np.flatnonzero(region&((skin_hue&(leg_share>.65)&palette_match) if who=='mio' else khaki if who=='ren' else neutral_dark))
    # Independently retain every full-mesh body vertex, not runtime LOD vertices.
    names=mesh.get('extras',{}).get('targetNames',[]);shapes=[read(d,b,t['POSITION']) for t in p.get('targets',[])];local=[i for i,n in enumerate(names) if n.startswith('Garment_Local_')];faces=read(d,b,p['indices']).reshape(-1,3)
    # Independent source-pigment coverage: corrective support must never define
    # the audit's cloth coverage. Otherwise a missed inner pleat disappears from
    # both solver and test. Match the full-source native probe's source labels.
    from motion_math import world_matrices
    rest,_=world_matrices(d,b)
    hip=next(i for i,n in enumerate(d['nodes']) if n.get('name')=='mixamorig:Hips')
    hip_z=float(rest[hip][2,3])
    garment=(blue>r*1.08)&(blue>g*1.04)&(texture.sum(1)<1.) if who=='mio' else (r>g*.95)&(r<g*1.9)&(blue<g*.65)&(g>.18) if who=='kazuko' else (texture.min(1)>.50)&(texture.max(1)-texture.min(1)<.10)&~khaki
    if who=='kazuko':
        def cloth_signature(i):return positions[i].tobytes()+joints[i].tobytes()+weights[i].tobytes()
        yellow_keys={cloth_signature(i) for i in np.flatnonzero(garment)}
        for i in np.flatnonzero(~garment):
            if cloth_signature(i) in yellow_keys:garment[i]=True
    garment&=(abs(x)<.24*height)&(y>.20*height)&(y<.59*height)
    masks=[garment&((z-hip_z)*sign>.025) for sign in [1,-1]]
    layers={side:faces[np.all(mask[faces],axis=1)] for side,mask in zip(['front','back'],masks)}
    binds=read(d,b,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
    cloth_faces=np.concatenate(list(layers.values()));cloth_vertices=np.unique(cloth_faces)
    body_faces=faces[np.all(np.isin(faces,body),axis=1)]
    return dict(d=d,b=b,node=node,ni=ni,positions=positions,joints=joints,weights=weights,shapes=shapes,names=names,local=local,body=body,body_faces=body_faces,layers=layers,binds=binds,skin=skin,cloth_faces=cloth_faces,cloth_vertices=cloth_vertices)


def pose(state,clip,time,row=None,disable_global=False,actual_shapes=False,disable_local=False,counterfactual_new_shapes=False):
    d=state['d'];b=state['b'];animation=next(a for a in d['animations'] if a['name']==clip);worlds,_=world_matrices(d,b,animation,time)
    if row:
        ids={n.get('name'):i for i,n in enumerate(d['nodes'])}
        for bone in row['bones']:
            name=bone['name'].replace('mixamorig_','mixamorig:')
            if name not in ids:continue
            if 'basis' not in bone:raise ValueError('Manifest lacks exact final world bases')
            worlds[ids[name]][:3,:3]=np.array(bone['basis']).T;worlds[ids[name]][:3,3]=np.array(bone['position'])-np.array(row['position'])
    matrices=np.array([worlds[j]@bind for j,bind in zip(state['skin']['joints'],state['binds'])]);rest=state['positions'].copy();count=len(state['names']);values=np.array(state['d']['meshes'][state['node']['mesh']].get('weights',[0]*count),float)
    for channel in animation['channels']:
        if channel['target']!={'node':state['ni'],'path':'weights'}:continue
        sampler=animation['samplers'][channel['sampler']];ts=read(d,b,sampler['input']).ravel();vs=read(d,b,sampler['output']).reshape(-1,count);values=np.array([np.interp(time,ts,vs[:,i]) for i in range(count)])
    if actual_shapes and row and 'blend_shape_values' in row:
        actual=row['blend_shape_values']
        # Each entry carries mesh, target name and the native node's real value.
        mesh_name=state['node'].get('name','')
        table=actual.get(mesh_name,{}) if isinstance(actual,dict) else {}
        missing=[name for name in state['names'] if name not in table] if isinstance(table,dict) else state['names']
        if not isinstance(table,dict) or (missing and not (counterfactual_new_shapes and all(name.startswith('GarmentDrape_') for name in missing))):raise ValueError('Native mesh/shape table does not match input GLB; do not combine native values from a different candidate')
        # Explicit source-native counterfactuals may evaluate newly authored
        # drape tracks from candidate animation. Exact-native audits never use
        # this option and still require every native scalar plus matching SHA.
        values=np.array([float(table[name]) if name in table else values[i] for i,name in enumerate(state['names'])])
    for i,(v,delta) in enumerate(zip(values,state['shapes'])):
        if (i in state['local'] and (not actual_shapes or disable_local)) or (disable_global and state['names'][i] in ['Skirt_Clearance','Apron_Clearance']):continue
        rest+=v*delta
    base=np.zeros_like(rest,dtype=float);direction=np.zeros_like(rest,dtype=float);pos4=np.c_[rest,np.ones(len(rest))]
    for k in range(state['joints'].shape[1]):
        transform=matrices[state['joints'][:,k]];weight=state['weights'][:,k,None];base+=np.einsum('nij,nj->ni',transform[:,:3,:],pos4)*weight;direction+=transform[:,:3,2]*weight
    return base,direction


def solve(state,base,directions):
    profile=next((node.get('extras',{}).get('garment_local_clearance',{}) for node in state['d']['nodes'] if node.get('name')=='Rig'),{})
    ids=state['local'];coeff=np.stack([state['shapes'][i][:,2] for i in ids],axis=1);amount=np.zeros(len(ids));margin=float(profile.get('clearance_margin_m',.003));saturated=0
    for iteration in range(4):
        start=amount.copy();posed=base+directions*(coeff@amount)[:,None];increased=False
        for sign,side in [(1,'front'),(-1,'back')]:
            for body,triangle,bary,depth in layer_hits(posed,state['layers'][side],state['body'],sign):
                if depth < -margin+.00025:continue
                slopes=bary@(coeff[triangle]*(directions[triangle,2]*sign)[:,None]);required=depth+margin-slopes@(amount-start)
                if required<=.0001:continue
                movable=(slopes>0)&(amount<1);divisor=float(slopes[movable]@slopes[movable])
                if divisor<1e-8:saturated+=1;continue
                new=np.minimum(1,amount+np.maximum(slopes,0)*required/divisor)
                increased|=np.max(new-amount)>1e-6;amount=new
        if not increased:break
    return base+directions*(coeff@amount)[:,None],amount,saturated


def measure(state,points):
    panels={};depth=0.;covered=0
    for sign,side in [(1,'front'),(-1,'back')]:
        hits=layer_hits(points,state['layers'][side],state['body'],sign);values=np.array([h[3] for h in hits]);maxdepth=float(max(0,values.max())) if len(values) else 0.;depth=max(depth,maxdepth);covered+=len(hits)
        panels[side]={'cloth_triangles':len(state['layers'][side]),'covered_body_vertices':len(hits),'penetrations_over_5mm':int(np.count_nonzero(values>.005)),'max_penetration_m':maxdepth,'gap_p50_m':float(np.percentile(-values,50)) if len(values) else None,'gap_p95_m':float(np.percentile(-values,95)) if len(values) else None,'gap_sample_scope':'all body vertices including hidden back/interior surfaces; these percentiles are not garment fit measurements; use --measure-gap for outer-body surface clearance'}
    return {'max_penetration_m':depth,'covered_body_vertices':covered,'panels':panels}


def surface_gap(state,points):
    """Area-weighted cloth-centre to outer-body depth along each panel's axis.

    Empty cloth spanning between legs has no underlying body ray, and is
    explicitly excluded from this distance statistic, with coverage reported.
    This is a directional surface clearance, never an interior-body percentile.
    """
    out={}
    for side,sign in [('front',1),('back',-1)]:
        faces=state['layers'][side];tri=points[faces];centres=tri.mean(1);areas=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)*.5;query=np.r_[points,centres];hits=layer_hits(query,state['body_faces'],np.arange(len(points),len(query)),sign,normal_min=None);values=np.array([hit[3] for hit in hits]);selected=np.array([hit[0]-len(points) for hit in hits],int);weight=areas[selected]
        def quantile(q):
            order=np.argsort(values);return float(np.interp(q*weight.sum(),np.cumsum(weight[order]),values[order])) if len(values) else None
        out[side]={'full_source_body_triangles':len(state['body_faces']),'covered_cloth_centres':len(hits),'body_covered_cloth_area_fraction':float(weight.sum()/max(areas.sum(),1e-12)),'signed_axis_gap_p05_m':quantile(.05),'signed_axis_gap_median_m':quantile(.5),'signed_axis_gap_p95_m':quantile(.95),'maximum_axis_gap_m':float(values.max()) if len(values) else None,'cloth_area_inside_body_fraction':float(weight[values<-.005].sum()/max(areas.sum(),1e-12))}
    return out


def audit(args):
    state=mesh_state(args.input,args.character);rows=[]
    if args.manifest:
        if args.actual_native_shapes:
            provenance=args.manifest.parent.parent/'model-hashes.json'
            if not provenance.exists():raise ValueError('Actual-native audit requires the capture companion model-hashes.json; matching target names alone cannot establish identical morph geometry')
            expected=json.loads(provenance.read_text()).get(f'CH_{args.character}.glb');actual=hashlib.sha256(args.input.read_bytes()).hexdigest()
            if expected!=actual:raise ValueError(f'Native capture model SHA differs from audit input ({expected} != {actual}); recapture this candidate instead of reusing weights from another model')
        data=json.loads(args.manifest.read_text());rows=[r for r in data['shots'] if r['id']==args.character and all('basis' in bone for bone in r['bones'])]
        if not rows:raise ValueError('No exact final-basis character samples')
        unique={}
        for row in rows:
            signature=(row['clip'],row['clip_time'],json.dumps(row['bones'],sort_keys=True))
            # Cameras alter only screen coords, so use final transforms as identity.
            signature=(row['clip'],row['clip_time'],json.dumps([{k:b[k] for k in ['name','basis','position']} for b in row['bones']],sort_keys=True))
            if signature not in unique:unique[signature]=row
        rows=list(unique.values())
    else:
        for clip in ['idle','walk','run','wave','stretch','bow','dance']:
            a=next(a for a in state['d']['animations'] if a['name']==clip);length=max(float(read(state['d'],state['b'],s['input']).max()) for s in a['samplers'])
            for phase in np.linspace(0,1,args.phases):rows.append({'clip':clip,'clip_time':float(length*phase),'phase':float(phase)})
    samples=[]
    for row in rows:
        base,direction=pose(state,row['clip'],row['clip_time'],row if args.manifest else None,disable_global=bool(state['local']),actual_shapes=args.actual_native_shapes,disable_local=True);before=measure(state,base)
        if args.actual_native_shapes:
            if not args.manifest or not row.get('blend_shape_values'):raise ValueError('Actual shape audit requires native shape values in manifest')
            posed,_=pose(state,row['clip'],row['clip_time'],row,disable_global=False,actual_shapes=True);weights=[];saturated=0
        elif state['local']:posed,weights,saturated=solve(state,base,direction)
        else:posed=base;weights=[];saturated=0
        after=measure(state,posed);moved=np.linalg.norm(posed-base,axis=1);selected=moved>1e-7;cloth=state['cloth_vertices'];triangles=state['cloth_faces'];source_tris=base[triangles];areas=np.linalg.norm(np.cross(source_tris[:,1]-source_tris[:,0],source_tris[:,2]-source_tris[:,0]),axis=1)*.5;area_moved=areas[np.max(moved[triangles],axis=1)>.001].sum();delta_z=np.ptp(posed[cloth,2])-np.ptp(base[cloth,2]);sample={'clip':row['clip'],'phase':row.get('phase'),'time':row['clip_time'],'source_file':row.get('file'),'before':before,'after':after,'maximum_local_displacement_m':float(moved.max()),'local_displacement_p95_m':float(np.percentile(moved[selected],95)) if selected.any() else 0.,'front_back_envelope_change_m':float(delta_z),'affected_cloth_vertex_fraction_over_1mm':float(np.count_nonzero(moved[cloth]>.001)/len(cloth)),'affected_cloth_area_fraction_over_1mm':float(area_moved/areas.sum()),'cloth_bounds_before':{'min':base[cloth].min(0).tolist(),'max':base[cloth].max(0).tolist()},'cloth_bounds_after':{'min':posed[cloth].min(0).tolist(),'max':posed[cloth].max(0).tolist()},'active_local_targets':int(np.count_nonzero(np.asarray(weights)>.0001)),'saturated_constraints':saturated,'local_weights':list(weights)};samples.append(sample);print(row['clip'],row.get('phase'),round(before['max_penetration_m']*1000,2),'->',round(after['max_penetration_m']*1000,2),'mm',flush=True)
    overlap=len(np.intersect1d(state['body'],state['cloth_vertices']))
    body_delta=max((float(np.linalg.norm(state['shapes'][i][state['body']],axis=1).max()) for i in state['local']),default=0.) if len(state['body']) else 0.
    seam_gap=template_seam_gap(state)
    coverage=bool(samples) and len(state['body'])>500 and all(len(f)>200 for f in state['layers'].values()) and all(r['after']['covered_body_vertices']>100 for r in samples) and overlap==0 and body_delta<1e-7 and seam_gap<.0001
    if args.measure_gap:
        for sample,row in zip(samples,rows):
            base,direction=pose(state,row['clip'],row['clip_time'],row if args.manifest else None,disable_global=bool(state['local']),actual_shapes=args.actual_native_shapes,disable_local=True)
            if args.actual_native_shapes:actual,_=pose(state,row['clip'],row['clip_time'],row,actual_shapes=True)
            elif state['local']:actual,_,_=solve(state,base,direction)
            else:actual=base
            sample['outer_body_axis_clearance']={'before':surface_gap(state,base),'after':surface_gap(state,actual),'scope':'area-weighted cloth face centres against actual outermost source body triangles along front/back Z; not a nearest Euclidean distance or hidden interior-body gap percentile'}
    result={'input':str(args.input),'input_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),'character':args.character,'scope':'exact native final-world-basis skinning' if args.manifest else 'authored skeleton only; not final IK proof','body_vertices':len(state['body']),'body_cloth_vertex_overlap':overlap,'body_local_template_delta_max_m':body_delta,'uv_seam_template_gap_max_m':seam_gap,'source_panel_triangles':{name:len(faces) for name,faces in state['layers'].items()},'coverage_valid':coverage,'samples':samples,'passes_5mm':coverage and all(r['after']['max_penetration_m']<=.005 for r in samples),'bounded_12cm':all(r['maximum_local_displacement_m']<=.12001 for r in samples)}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,indent=2));print(args.output)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--character',required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--manifest',type=Path);p.add_argument('--phases',type=int,default=9);p.add_argument('--actual-native-shapes',action='store_true');p.add_argument('--measure-gap',action='store_true');args=p.parse_args();audit(args)

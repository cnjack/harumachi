"""Inventory game GLBs in world metres; UV density is a diagnostic, not visual acceptance.

Use the project's numpy/Pillow Python. Reports albedo pixels per metre weighted
by triangle world area (p10/median), bounds, material flags and file hashes.
Uniform enlargement lowers density but does not change model proportions.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from PIL import Image
from edit_model_atlas import load


def accessor(g, binary, index):
    a = g['accessors'][index]; v = g['bufferViews'][a['bufferView']]
    dtype = {5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']]
    width = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    dt = np.dtype(dtype); start = v.get('byteOffset',0)+a.get('byteOffset',0)
    stride = v.get('byteStride',dt.itemsize*width)
    return np.ndarray((a['count'],width),dtype=dt,buffer=binary,offset=start,strides=(stride,dt.itemsize)).copy()


def local_matrix(n):
    if 'matrix' in n:return np.array(n['matrix']).reshape(4,4).T
    x,y,z,w = n.get('rotation',[0,0,0,1])
    r = np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                  [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                  [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
    m = np.eye(4); m[:3,:3] = r @ np.diag(n.get('scale',[1,1,1]))
    m[:3,3] = n.get('translation',[0,0,0]); return m


def primitives(g, binary):
    def walk(i,parent):
        n=g['nodes'][i]; m=parent@local_matrix(n)
        if 'mesh' in n:
            for p in g['meshes'][n['mesh']]['primitives']:
                if p.get('mode',4)!=4:continue
                v=accessor(g,binary,p['attributes']['POSITION']);v=v@m[:3,:3].T+m[:3,3]
                idx=accessor(g,binary,p['indices']).ravel() if 'indices' in p else np.arange(len(v))
                uv=accessor(g,binary,p['attributes']['TEXCOORD_0']) if 'TEXCOORD_0' in p['attributes'] else None
                yield {**p,'_node_name':n.get('name','')},v,idx.reshape(-1,3),uv
        for c in n.get('children',[]):yield from walk(c,m)
    for i in g['scenes'][g.get('scene',0)]['nodes']:yield from walk(i,np.eye(4))


def weighted_quantile(values,weights,q):
    if not len(values):return None
    order=np.argsort(values);cum=np.cumsum(weights[order]);i=np.searchsorted(cum,q*cum[-1])
    return round(float(values[order[min(i,len(order)-1)]]),2)


def measure(path):
    g,b=load(path); images={}
    for i,im in enumerate(g.get('images',[])):
        if 'bufferView' not in im:continue
        bv=g['bufferViews'][im['bufferView']];off=bv.get('byteOffset',0)
        with Image.open(io.BytesIO(b[off:off+bv['byteLength']])) as image:images[i]=list(image.size)
    mins=[];maxs=[]; densities=[];weights=[];area=0.;tris=0;untextured=0.;materials=set();corners_all=[];areas_all=[];albedo_sizes=[];per_material={};per_node={}
    for p,v,idx,uv in primitives(g,b):
        corners=v[idx];cross=np.cross(corners[:,1]-corners[:,0],corners[:,2]-corners[:,0]);ar=np.linalg.norm(cross,axis=1)*.5
        corners_all.append(corners);areas_all.append(ar)
        mins.append(corners.min(axis=(0,1)));maxs.append(corners.max(axis=(0,1)));tris+=len(idx);area+=ar.sum()
        mat=g.get('materials',[{}])[p.get('material',0)];materials.add(p.get('material',0));pbr=mat.get('pbrMetallicRoughness',{})
        tex=pbr.get('baseColorTexture',{}).get('index');size=images.get(g['textures'][tex]['source']) if tex is not None else None
        if uv is None or size is None:untextured+=ar.sum();continue
        if size not in albedo_sizes:albedo_sizes.append(size)
        t=uv[idx]*size;du=t[:,1]-t[:,0];dv=t[:,2]-t[:,0];ua=np.abs(du[:,0]*dv[:,1]-du[:,1]*dv[:,0])*.5
        valid=(ar>1e-12)&(ua>1e-12);densities.extend(np.sqrt(ua[valid]/ar[valid]));weights.extend(ar[valid])
        name=mat.get('name',str(p.get('material',0)));part=per_material.setdefault(name,{'values':[],'weights':[]})
        part['values'].extend(np.sqrt(ua[valid]/ar[valid]));part['weights'].extend(ar[valid])
        node=per_node.setdefault(p.get('_node_name',''),{'values':[],'weights':[]})
        node['values'].extend(np.sqrt(ua[valid]/ar[valid]));node['weights'].extend(ar[valid])
    lo=np.min(mins,axis=0);hi=np.max(maxs,axis=0)
    points=np.concatenate(corners_all).reshape(-1,3);ar=np.concatenate(areas_all)
    # Weld only for measurement, never mutate the model. glTF splits vertices
    # at UV seams; rounding relative to physical size reconnects those copies.
    tolerance=max(float((hi-lo).max())*1e-6,1e-8)
    unique,inverse=np.unique(np.round(points/tolerance).astype(np.int64),axis=0,return_inverse=True)
    faces=inverse.reshape(-1,3);edges=np.concatenate([faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]]);edges.sort(axis=1)
    distinct,counts=np.unique(edges,axis=0,return_counts=True)
    graph=coo_matrix((np.ones(len(distinct)),(distinct[:,0],distinct[:,1])),shape=(len(unique),len(unique)))
    ncomp,labels=connected_components(graph,directed=False)
    component_areas=np.bincount(labels[faces[:,0]],weights=ar,minlength=ncomp)
    return {'id':path.stem,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'source_mtime':path.stat().st_mtime,
            'triangles':tris,'bounds_godot':{'min':lo.tolist(),'max':hi.tolist()},'size_m':(hi-lo).tolist(),
            'surface_area_m2':round(float(area),3),'albedo_image_sizes':albedo_sizes,
            'topology':{'components':int(ncomp),'largest_component_area_fraction':round(float(component_areas.max()/area),4),
                        'boundary_edge_fraction':round(float(np.count_nonzero(counts==1)/len(counts)),4)},
            'uv_density_px_m':{'p10':weighted_quantile(np.array(densities),np.array(weights),.1),'median':weighted_quantile(np.array(densities),np.array(weights),.5)},
            'material_density_px_m':{name:{'p10':weighted_quantile(np.array(p['values']),np.array(p['weights']),.1),'median':weighted_quantile(np.array(p['values']),np.array(p['weights']),.5)} for name,p in per_material.items()},
            'node_density_px_m':{name:weighted_quantile(np.array(p['values']),np.array(p['weights']),.5) for name,p in per_node.items()},
            'untextured_area_fraction':round(float(untextured/max(area,1e-12)),4),
            'inherited_pbr_maps':sum('normalTexture' in g['materials'][i] or 'metallicRoughnessTexture' in g['materials'][i].get('pbrMetallicRoughness',{}) for i in materials),
            'metallic_max':max((g['materials'][i].get('pbrMetallicRoughness',{}).get('metallicFactor',1.) for i in materials),default=0)}


if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('model_dir',type=Path);ap.add_argument('output',type=Path)
    ap.add_argument('--contracts',type=Path);args=ap.parse_args()
    report={'models':{},'errors':{}}
    for path in sorted(args.model_dir.glob('*.glb')):
        try:report['models'][path.stem]=measure(path)
        except Exception as e:report['errors'][path.stem]=str(e)
    if args.contracts:
        contract=json.loads(args.contracts.read_text());models=report['models'];checks={};details={}
        details['matte']=[k for k,m in models.items() if m['inherited_pbr_maps'] or m['metallic_max']>0]
        checks['matte_materials']=not details['matte']
        details['fragmented']=[]
        for k in contract['continuous_meshes']:
            topo=models.get(k,{}).get('topology',{})
            if topo.get('boundary_edge_fraction',1)>.03 or topo.get('largest_component_area_fraction',0)<.85:details['fragmented'].append(k)
        checks['continuous_surfaces']=not details['fragmented']
        details['density']=[]
        for k,minimum in contract['building_density_px_m'].items():
            m=models.get(k,{});d=m.get('uv_density_px_m',{}).get('median') or 0
            if d<minimum:details['density'].append(k)
        checks['building_density']=not details['density']
        modules={name:value for name,value in models.get('H02',{}).get('node_density_px_m',{}).items() if name.startswith('Rodin_tenant_') and not name.endswith('_curtain')}
        details['apartment_modules']=modules
        checks['apartment_modular_detail']=len(modules)==6 and all(value is not None and value>=280 for value in modules.values())
        details['bounds']=[]
        for k,bounds in contract['bounds_godot'].items():
            actual=models.get(k,{}).get('bounds_godot',{})
            if not actual or max(abs(actual[side][axis]-bounds[side][axis]) for side in ['min','max'] for axis in range(3))>.012:details['bounds'].append(k)
        checks['physical_bounds']=not details['bounds']
        report.update(checks=checks,details=details,contract_sha256=hashlib.sha256(args.contracts.read_bytes()).hexdigest())
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2))
    print('AUDIT',len(report['models']),'models;',report['errors'])

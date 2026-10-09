"""Independent geometry guards for the approved architectural identity changes.

Project numpy/Pillow Python: MODEL_DIR REPORT. Read actual exported triangles,
not the builder's member counts. The former repeated facades must fail.
Visual four-side, close-up and street comparison is still mandatory.
"""
import sys,json,hashlib
from pathlib import Path
import numpy as np
from model_audit import load,primitives

IDS=['H01','H02','H03','S06','S01','S02','S03','S05','S08','M01_timber_machiya','M03_gable_house','M05_residential']

def inspect(path):
    g,b=load(path);parts={};nodes={};all_points=[]
    for primitive,vertices,indices,uv in primitives(g,b):
        material=g['materials'][primitive.get('material',0)].get('name','')
        triangles=vertices[indices];all_points.append(triangles.reshape(-1,3))
        parts.setdefault(material,[]).append(triangles)
        nodes.setdefault(primitive.get('_node_name',''),[]).append(triangles)
    return {'parts':{k:np.concatenate(v) for k,v in parts.items()},'nodes':{k:np.concatenate(v) for k,v in nodes.items()},'points':np.concatenate(all_points),'source_mtime':path.stat().st_mtime,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}

def bounds(points):return {'min':points.reshape(-1,3).min(axis=0).tolist(),'max':points.reshape(-1,3).max(axis=0).tolist()}

def run(directory):
    models={asset:inspect(directory/(asset+'.glb')) for asset in IDS};checks={};metrics={}
    heights={asset:float(models[asset]['points'][:,1].max()) for asset in IDS}
    metrics['heights_m']=heights
    checks['distinct_shop_heights']=heights['S02']-heights['S01']>1.0 and heights['S02']-heights['S03']>.8 and heights['S02']-heights['S08']>.35
    if 'Rodin_main_house' in models['H01']['nodes']:
        front=models['H01']['nodes']['Rodin_engawa'].reshape(-1,3)
        rear=models['H01']['nodes']['Rodin_main_house'].reshape(-1,3)
    else:
        home_roof=np.concatenate([tri for name,tri in models['H01']['parts'].items() if name.startswith('kawara')]).reshape(-1,3)
        front=home_roof[home_roof[:,2]>.8];rear=home_roof[home_roof[:,2]<-.7]
    step=float(rear[:,1].max()-front[:,1].max()) if len(front) and len(rear) else 0.
    metrics['home_roof_step_m']=step;checks['home_separate_low_wing']=step>1.8
    rodin_florist=any(n.startswith('Rodin_S03') for n in models['S03']['nodes'])
    if rodin_florist:
        tri=np.concatenate(list(models['S03']['nodes'].values()));c=tri.mean(1)
        annex=tri[(c[:,0]>.0)&(c[:,0]<2.65)&(c[:,1]>.2)&(c[:,1]<3.6)&(c[:,2]>2.85)]
    else:annex=models['S03']['parts'].get('greenhouse_glass',np.empty((0,3,3)))
    annex_bounds=bounds(annex) if len(annex) else {}
    metrics['florist_glass_annex']=annex_bounds
    if rodin_florist:
        # The new lean-to sits in front of the building, not along its side.
        checks['florist_real_glass_annex']=bool(annex_bounds) and annex_bounds['max'][0]-annex_bounds['min'][0]>2.3 and annex_bounds['max'][1]-annex_bounds['min'][1]>2.8 and annex_bounds['max'][2]-annex_bounds['min'][2]>1.0
    else:checks['florist_real_glass_annex']=bool(annex_bounds) and annex_bounds['min'][0]>1.9 and annex_bounds['max'][1]-annex_bounds['min'][1]>2.35 and annex_bounds['max'][2]-annex_bounds['min'][2]>4.1
    produce_metrics={};produce_ok=True
    for name in ['produce_cabbage','produce_tomato','produce_cucumber']:
        matching=[v for k,v in models['S01']['parts'].items() if k==name or k.startswith(name+'_pixal')]
        tri=np.concatenate(matching) if matching else np.empty((0,3,3))
        if not len(tri):produce_ok=False;continue
        bb=bounds(tri);cross=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);area=np.linalg.norm(cross,axis=1)*.5
        normal=cross/np.maximum(np.linalg.norm(cross,axis=1)[:,None],1e-9)
        angled=float(area[np.abs(normal[:,1])<.75].sum()/max(area.sum(),1e-9))
        produce_metrics[name]={'bounds':bb,'nonplanar_area_fraction':angled,'triangles':len(tri)}
        produce_ok &= bb['max'][1]-bb['min'][1]>.20 and angled>.25 and len(tri)>200
    metrics['produce_geometry']=produce_metrics;checks['produce_has_real_volume']=bool(produce_ok)
    apartment=models['H02']['parts'];tenant_parts={k:bounds(v) for k,v in apartment.items() if k in ['cloth_towel','cloth_laundry']}
    metrics['tenant_cloth']=tenant_parts
    checks['different_tenant_cloth']=len(tenant_parts)==2 and all(v['min'][1]>2.9 for v in tenant_parts.values())
    if any(n.startswith('Rodin_M03') for n in models['M03_gable_house']['nodes']):
        tri=np.concatenate(list(models['M03_gable_house']['nodes'].values()));roof=tri[tri.mean(1)[:,1]>4.65]
    else:roof=np.concatenate([tri for name,tri in models['M03_gable_house']['parts'].items() if name=='kawara'])
    cross=np.cross(roof[:,1]-roof[:,0],roof[:,2]-roof[:,0]);length=np.linalg.norm(cross,axis=1);n=cross/np.maximum(length[:,None],1e-9);area=length*.5
    upward=n[:,1]>.20;total=max(float(area[upward].sum()),1e-9);sectors={}
    for key,axis,sign in [('front',2,1),('back',2,-1),('left',0,-1),('right',0,1)]:
        other=0 if axis==2 else 2
        keep=upward&(n[:,axis]*sign>.12)&(np.abs(n[:,axis])>np.abs(n[:,other])*1.8)
        sectors[key]=float(area[keep].sum()/total)
    metrics['hip_roof_area_sectors']=sectors;checks['modern_four_hip_slopes']=all(v>.08 for v in sectors.values())
    return {'models':{k:{'source_mtime':m['source_mtime'],'sha256':m['sha256']} for k,m in models.items()},'checks':checks,'metrics':metrics,'passed':all(checks.values()),'scope':'actual exported triangles; visual review required separately'}

if __name__=='__main__':
    directory,output=map(Path,sys.argv[1:3]);report=run(directory)
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n')
    print('IDENTITY',report['checks'])

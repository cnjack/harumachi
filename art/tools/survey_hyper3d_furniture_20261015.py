"""Measure generated furniture supports and source provenance without changing GLBs."""
from pathlib import Path
import json,sys,hashlib
import numpy as np
from model_audit import primitives,measure
from edit_model_atlas import load
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'evidence/hyper3d_furniture_20261015/source-survey';OUT.mkdir(parents=True,exist_ok=True)

def survey(row,candidate='a'):
 path=ROOT/'art/models/raw/hyper3d_furniture_20261015'/row['id']/candidate/'model.glb'
 if not path.exists() and row.get('source_glb'):path=ROOT/row['source_glb']
 if not path.exists():return
 g,b=load(path);items=list(primitives(g,b));points=np.concatenate([v for _,v,_,_ in items]);lo=points.min(0);hi=points.max(0);size=hi-lo;target=np.array(row['nominal_size_m_xyz']);scale=target/size
 planes={};allfaces=[]
 for _,vertices,indices,_ in items:
  v=(vertices-lo)*scale-target*np.array([.5,0,.5]);faces=v[indices];allfaces.append(faces)
  cross=np.cross(faces[:,1]-faces[:,0],faces[:,2]-faces[:,0]);length=np.linalg.norm(cross,axis=1);up=np.divide(cross[:,1],length,out=np.zeros_like(length),where=length>1e-12)
  for height,area in zip(faces.mean(1)[up>.96,1],length[up>.96]*.5):
   key=round(float(height)/.005)*.005;planes[key]=planes.get(key,0)+float(area)
 ranked=sorted(planes.items(),key=lambda x:-x[1])[:24]
 material_summary=[dict(name=m.get('name'),alpha_mode=m.get('alphaMode','OPAQUE'),base_color=m.get('pbrMetallicRoughness',{}).get('baseColorFactor',[1,1,1,1]),normal_texture='normalTexture' in m) for m in g.get('materials',[])]
 report=dict(asset=row['id'],candidate=candidate,source=str(path.relative_to(ROOT)),source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),source_audit=measure(path),nominal_size_m_xyz=target.tolist(),diagnostic_affine_scale=scale.tolist(),horizontal_up_face_area_histogram=[dict(height_m=round(h,4),area_m2=round(area,5)) for h,area in ranked],materials=material_summary,stage='Diagnostic affine normalization only; source file unchanged; no game acceptance')
 (OUT/(row['id']+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 print(row['id'],'planes',[(round(h,3),round(area,3)) for h,area in ranked[:6]],flush=True)

if __name__=='__main__':
 rows=json.loads((ROOT/'art/manifests/hyper3d_furniture_20261015.json').read_text())['assets'];only=set(sys.argv[1:])
 for row in rows:
  if not only or row['id'] in only:survey(row)

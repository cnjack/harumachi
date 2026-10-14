"""Check actual provenance, original atlas pixels, UVs and closed support seams.

Offline only. Does not replace native scene, seating or glass acceptance.
"""
from pathlib import Path
import argparse,json,hashlib,io,sys
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from edit_model_atlas import load
from model_audit import primitives,measure
ROOT=Path(__file__).resolve().parents[2]
TIMBER=['HFF01_cafe_chair','HFF02_round_table','HFF03_rect_table','HFF04_low_table','HFF05_utility_stand','HFF06_indoor_bench','HFF07_sage_counter','HFF08_bread_rack4','HFF09_bread_rack3','HFF10_wall_shelf','HFF12_reading_armchair','HFF14_outdoor_bench']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def geometry(path):
 g,b=load(path);uv=[];triangles=0;pixels=set()
 for p,v,indices,coords in primitives(g,b):
  triangles+=len(indices)
  if coords is not None:uv.append(coords[indices].reshape(-1,2))
  material=g['materials'][p.get('material',0)];texture=material.get('pbrMetallicRoughness',{}).get('baseColorTexture',{}).get('index')
  if texture is not None:
   image=g['images'][g['textures'][texture]['source']];view=g['bufferViews'][image['bufferView']];offset=view.get('byteOffset',0)
   im=Image.open(io.BytesIO(b[offset:offset+view['byteLength']])).convert('RGB');pixels.add(hashlib.sha256(im.tobytes()).hexdigest())
 return triangles,np.concatenate(uv) if uv else np.empty((0,2)),pixels
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--stage',choices=['ready','assembled','game'],default='game');ap.add_argument('--only');ap.add_argument('--game-dir',type=Path,default=ROOT/'game/assets/models');ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
 ledger=json.loads((ROOT/'art/library/hyper3d_furniture_20261015/provenance.json').read_text());ids=a.only.split(',') if a.only else TIMBER;rows={}
 for aid in ids:
  record=ledger['assets'][aid];source=ROOT/record['source_glb'];target=(a.game_dir if a.stage=='game' else ROOT/'art/models/raw/hyper3d_furniture_20261015'/a.stage)/(aid+'.glb')
  if not target.exists():rows[aid]={'passed':False,'checks':{'exists':False}};continue
  assert sha(source)==record['sha256'],'Immutable generation source changed'
  st,suv,sp=geometry(source);tt,tuv,tp=geometry(target)
  uv_error=max(float(cKDTree(suv).query(tuv)[0].max()),float(cKDTree(tuv).query(suv)[0].max())) if len(suv) and len(tuv) else float('inf')
  before=measure(source)['topology'];after=measure(target)['topology'];boundary_excess=after['boundary_edge_fraction']-before['boundary_edge_fraction']
  checks={'original_source_triangle_count':st==tt,'original_uv_coordinates':uv_error<.000002,'original_atlas_rgb_pixels':sp==tp,'no_new_support_uv_seam_tears':boundary_excess<=.0005}
  rows[aid]={'passed':all(checks.values()),'checks':checks,'source_triangles':st,'actual_triangles':tt,'max_uv_error':uv_error,'source_topology':before,'actual_topology':after,'actual_sha256':sha(target)}
 report={'passed':all(row['passed'] for row in rows.values()),'stage':a.stage,'assets':rows,'native_acceptance':False};a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'passed':report['passed'],'assets':len(rows),'failures':{k:[name for name,ok in row['checks'].items() if not ok] for k,row in rows.items() if not row['passed']}}));sys.exit(0 if report['passed'] else 1)
if __name__=='__main__':main()

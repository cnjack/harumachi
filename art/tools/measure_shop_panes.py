"""Measure native shop glass from exported GLB triangles, retaining 12 mm clearance.

Run with project numpy/Pillow Python. Does not guess from the building bounds.
"""
import json,sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).parent))
from model_audit import load,primitives
ROOT=Path(__file__).resolve().parents[2]
OLD={
'S01':[[-2.7,3.4,.25,2.05,2.42,'store',2.6,1.,1.25]],
'S02':[[-2.55,.12,1.02,2.42,1.825,'bakery',2.4,.8,1.15],[1.65,2.45,.4,2.25,1.528,'bakery',2.4,.8,1.15]],
'S03':[[-2.85,1.7,.3,2.45,1.994,'florist',2.4,.8,1.3],[2.035,3.745,.24,2.70,2.63,'florist',1.7,.6,1.1]],
'S05':[[-2.,.3,.35,2.43,3.68,'post',2.2,.7,1.1]],
'S08':[[-.95,1.3,.16,2.55,2.833,'zakka',2.6,.9,1.2]]}
report={};new={}
spec=json.loads((ROOT/'art/models/game_assets.json').read_text())['assets']
for aid,windows in OLD.items():
    g,b=load(ROOT/'game/assets/models'/f'{aid}.glb');data=[]
    for p,v,indices,uv in primitives(g,b):
        if g['materials'][p.get('material',0)].get('name')!='glass':continue
        tri=v[indices];c=tri.mean(1);normal=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);normal/=np.maximum(np.linalg.norm(normal,axis=1)[:,None],1e-9)
        data.append((tri,c,normal))
    source=ROOT/'art/models'/spec[aid]['src']
    fit=json.loads(source.with_name(f'{aid}_members.json').read_text())['fit_scale_blender'];sx,sy=fit[0],fit[2]
    rows=[];measurements=[]
    for old in windows:
        points=[]
        for tri,c,n in data:
            keep=(n[:,2]>.9)&(c[:,0]>old[0]-.09)&(c[:,0]<old[1]+.09)&(c[:,1]>old[2]-.09)&(c[:,1]<old[3]+.09)&(abs(c[:,2]-(old[4]-.012))<.18)
            points.extend(tri[keep].reshape(-1,3))
        if len(points)<6:raise RuntimeError('Cannot measure window '+aid)
        points=np.array(points);lo=points.min(0);hi=points.max(0);plane=float(np.percentile(points[:,2],99))
        row=[float(lo[0]-.0275*sx),float(hi[0]+.0275*sx),float(lo[1]-.0275*sy),float(hi[1]+.0275*sy),plane+.012,*old[5:]]
        rows.append(row);measurements.append({'glass_bounds':[lo.tolist(),hi.tolist()],'samples':len(points),'glass_z99':plane,'quad_z':plane+.012})
    new[aid]=rows;report[aid]=measurements
path=ROOT/'game/scripts/world/shop_windows.gd';source=path.read_text();start=source.index('const WINDOWS := {');end=source.index('\nconst MID_ASPECT',start)
lines=['const WINDOWS := {']
for aid,rows in new.items():
    literals=[]
    for row in rows:
        literals.append('['+', '.join(json.dumps(x) if isinstance(x,str) else f'{x:.5f}' for x in row)+']')
    lines.append('\t"'+aid+'": ['+', '.join(literals)+'],')
lines.append('}')
path.write_text(source[:start]+'\n'.join(lines)+source[end:])
(ROOT/'evidence/architecture_identity_20261002/shop-pane-measurements.json').write_text(json.dumps({'panes':report,'windows':new},indent=2))
print('Measured',sum(len(v) for v in new.values()),'panes; 12 mm clearance')

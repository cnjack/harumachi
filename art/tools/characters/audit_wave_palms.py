"""Palm-side source landmarks must face the greeting recipient during a wave.

Use project numpy Python: audit_wave_palms.py --out REPORT GLB... [--require-pass]
Neutral/walk clips are outside this check and must retain their inward palms.
"""
from pathlib import Path
import argparse,json,sys
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
from repair_head_neck import read
from retime_glb import load
from motion_math import world_matrices,palm_normal

p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--require-pass',action='store_true');p.add_argument('models',type=Path,nargs='+');a=p.parse_args();rows=[]
for path in a.models:
    d,b=load(path);rest,_=world_matrices(d,b);wave=next(x for x in d['animations'] if x['name']=='wave')
    end=max(float(read(d,b,s['input']).max()) for s in wave['samplers']);samples=[]
    for phase in np.linspace(.22,.75,23):
        posed,_=world_matrices(d,b,wave,end*phase);normal=palm_normal(d,rest,posed)
        hand=next(i for i,n in enumerate(d['nodes']) if n.get('name')=='mixamorig:RightHand')
        samples.append({'phase':float(phase),'palm_forward_dot':float(normal[2]),'normal_gltf':normal.tolist(),'wrist':posed[hand][:3,3].tolist()})
    row={'source':str(path),'passed':min(s['palm_forward_dot'] for s in samples)>.75,'min_forward_dot':min(s['palm_forward_dot'] for s in samples),'samples':samples};rows.append(row);print(json.dumps({k:v for k,v in row.items() if k!='samples'}),flush=True)
result={'passed':all(r['passed'] for r in rows),'criterion':'right palm source normal dot character forward > 0.75 at phases 0.22..0.75','characters':rows};a.out.write_text(json.dumps(result,indent=2)+'\n')
if a.require_pass:assert result['passed'], 'Wave exposes hand back or palm edge to recipient'

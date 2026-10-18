#!/usr/bin/env python3
"""Independent GLB locomotion regression audit; does not claim a visual pass.

All skin influences and all shoe vertices are evaluated, including between keys.
Run --expect-fixed against legacy input first to demonstrate the regression fails.
"""
from pathlib import Path
import argparse, hashlib, json, math
import numpy as np
from motion_math import world_matrices
from repair_head_neck import read
from glb_io import load
from rebuild_locomotion import ROSTER, REBUILD, shoe_sources, shoe_points

def flex(a,b,c):
 u=a-b;v=c-b
 return 180-math.degrees(math.acos(float(np.clip(np.dot(u,v)/(np.linalg.norm(u)*np.linalg.norm(v)),-1,1))))

def audit(path,who,samples=129):
 d,b=load(path);ids={n.get('name'):i for i,n in enumerate(d['nodes'])};rig=d['nodes'][ids['Rig']]['extras'];sources=shoe_sources(d,b);out={'character':who,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'clips':{}}
 for clip in ['walk','run']:
  animation=next(a for a in d['animations'] if a['name']==clip);duration=max(float(read(d,b,s['input']).max()) for s in animation['samplers']);rows=[];first=None;last=None;elbows=[];wrists=[];knees=[];knee_forward=[];feet_span=[];shoe_cache=[]
  for phase in np.linspace(0,1,samples):
   w,_=world_matrices(d,b,animation,float(phase)*duration);first=w if first is None else first;last=w;shoes=shoe_points(sources,w);mins={s:float(v[:,1].min()) for s,v in shoes.items()};rows.append(mins);shoe_cache.append(shoes)
   feet_span.append(abs(w[ids['mixamorig:LeftFoot']][0,3]-w[ids['mixamorig:RightFoot']][0,3]))
   for side in ['Left','Right']:
    def p(suffix):return w[ids['mixamorig:'+side+suffix]][:3,3]
    hip,knee,ankle=p('UpLeg'),p('Leg'),p('Foot');knees.append(flex(hip,knee,ankle));line=ankle-hip;plane=knee-hip-line*np.dot(knee-hip,line)/np.dot(line,line);knee_forward.append(float(plane[2]));elbows.append(abs(float(p('ForeArm')[0]-p('Arm')[0])));wrists.append(abs(float(p('Hand')[0]-p('Arm')[0])))
  loop=max(float(np.linalg.norm(last[i][:3,3]-first[i][:3,3])) for i in set(j for skin in d['skins'] for j in skin['joints']))
  # The same skinned material point must remain still in world space during
  # established low support. Exclude roll/strike transitions and require >=60ms.
  drift=[];speed=float(rig[clip+'_speed']);duty=.30 if clip=='run' else .56
  for side,offset in [('Left',0),('Right',.5)]:
   points=np.stack([s[side] for s in shoe_cache]);points[:,:,2]+=np.linspace(0,duration,samples)[:,None]*speed;phase=(np.linspace(0,1,samples)+offset)%1;mask=(points[:,:,1]>=-.004)&(points[:,:,1]<=.020)&((phase[:,None]>.04)&(phase[:,None]<duty-.04))
   for vertex in range(points.shape[1]):
    indices=np.flatnonzero(mask[:,vertex]);parts=np.split(indices,np.flatnonzero(np.diff(indices)>1)+1)
    for part in parts:
     if len(part)<4 or (part[-1]-part[0])*duration/(samples-1)<.06:continue
     pp=points[part,vertex][:,[0,2]];drift.append(float(np.linalg.norm(np.ptp(pp,axis=0))))
  out['clips'][clip]={'duration_s':duration,'nominal_speed_mps':speed,'cadence_steps_min':120/duration,'loop_joint_error_m':loop,'shoe_min_y_m':min(min(r.values()) for r in rows),'double_flight_over25mm_fraction':sum(r['Left']>.025 and r['Right']>.025 for r in rows[:-1])/(samples-1),'knee_flex_deg':{'min':min(knees),'max':max(knees)},'knee_forward_plane_min_m':min(knee_forward),'elbow_outside_shoulder_max_m':max(elbows),'wrist_outside_shoulder_max_m':max(wrists),'ankle_span_min_m':min(feet_span),'ankle_span_max_m':max(feet_span),'low_sole_material_drift_p95_m':float(np.quantile(drift,.95)) if drift else None,'grounded_material_segments':len(drift)}
 return out

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--input-dir',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--characters',nargs='+',choices=ROSTER,default=list(ROSTER));parser.add_argument('--samples',type=int,default=129);parser.add_argument('--expect-fixed',action='store_true');args=parser.parse_args();rows=[];failures=[]
 for who in args.characters:
  row=audit(args.input_dir/f'CH_{who}.glb',who,args.samples);rows.append(row)
  for clip,c in row['clips'].items():
   if c['loop_joint_error_m']>.0005:failures.append(f'{who}/{clip}: loop {c["loop_joint_error_m"]:.4f}m')
   if clip in REBUILD[who]:
    if c['shoe_min_y_m']<.003:failures.append(f'{who}/{clip}: raw sole {c["shoe_min_y_m"]:.4f}m')
    if c['knee_forward_plane_min_m']<-.004:failures.append(f'{who}/{clip}: backward knee {c["knee_forward_plane_min_m"]:.4f}m')
    if clip=='run' and c['double_flight_over25mm_fraction']<.07:failures.append(f'{who}/{clip}: missing flight')
    if clip=='run' and c['elbow_outside_shoulder_max_m']>.06:failures.append(f'{who}/{clip}: outward elbow {c["elbow_outside_shoulder_max_m"]:.4f}m')
   print(who,clip,{k:v for k,v in c.items() if k not in ['grounded_material_segments']},flush=True)
 result={'scope':'offline complete skinned shoes and joint kinematics; runtime terrain/modifiers and native visual review remain independent','samples_per_clip':args.samples,'characters':rows,'failures':failures};args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(f'failures={len(failures)}')
 if args.expect_fixed and failures:raise SystemExit(1)
if __name__=='__main__':main()

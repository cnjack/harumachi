#!/usr/bin/env python3
"""Independently compare accepted motion, seam closure and peak foot velocity."""
import sys,json,numpy as np
from pathlib import Path
from scipy.spatial.transform import Rotation,Slerp
sys.path.insert(0,str(Path(__file__).resolve().parent))
from glb_io import load
from repair_head_neck import read

def positions(d,b,a,ts):
 values={}; parents={c:i for i,n in enumerate(d['nodes']) for c in n.get('children',[])}
 for c in a['channels']:
  if c['target']['path']=='weights':continue
  s=a['samplers'][c['sampler']];x=read(d,b,s['input']).ravel();y=read(d,b,s['output']);at=np.clip(ts,x[0],x[-1]);path=c['target']['path']
  v=y[np.clip(np.searchsorted(x,at,side='right')-1,0,len(y)-1)] if s.get('interpolation')=='STEP' else Slerp(x,Rotation.from_quat(y))(at).as_quat() if path=='rotation' else np.stack([np.interp(at,x,y[:,i]) for i in range(y.shape[1])],axis=-1)
  values[(c['target']['node'],path)]=v
 worlds={}
 def w(i):
  if i in worlds:return worlds[i]
  n=d['nodes'][i];m=np.broadcast_to(np.eye(4),(len(ts),4,4)).copy()
  if 'matrix' in n:m[:]=np.asarray(n['matrix']).reshape(4,4).T
  else:
   q=values.get((i,'rotation'),np.broadcast_to(n.get('rotation',[0,0,0,1]),(len(ts),4)));scale=values.get((i,'scale'),np.broadcast_to(n.get('scale',[1,1,1]),(len(ts),3)))
   m[:,:3,:3]=Rotation.from_quat(q).as_matrix()*scale[:,None,:]
   m[:,:3,3]=values.get((i,'translation'),n.get('translation',[0,0,0]))
  worlds[i]=w(parents[i])@m if i in parents else m;return worlds[i]
 return {n.get('name'):w(i)[:,:3,3] for i,n in enumerate(d['nodes']) if n.get('name','').startswith('mixamorig:')}

def metric(pos,ts,playback=1.45):
 dt=np.diff(ts);names=['mixamorig:'+s+x for s in ['Left','Right'] for x in ['Foot','ToeBase']]
 return {name:{'peak_vertical_mps':float(np.max(abs(np.diff(pos[name][:,1])/dt)))*playback,'peak_speed_mps':float(np.max(np.linalg.norm(np.diff(pos[name],axis=0),axis=1)/dt))*playback,'loop_endpoint_m':float(np.linalg.norm(pos[name][-1]-pos[name][0]))} for name in names}

def main():
 import argparse,hashlib
 parser=argparse.ArgumentParser(description="Audit preservation and joint velocities for a local loop-seal candidate; native final support is separate.")
 parser.add_argument('--reference',type=Path,required=True)
 parser.add_argument('--previous',type=Path,required=True)
 parser.add_argument('--candidate',type=Path,required=True)
 parser.add_argument('--output',type=Path,required=True)
 parser.add_argument('--clip',default='run')
 parser.add_argument('--before',type=float,default=.08)
 parser.add_argument('--after',type=float,default=.06)
 parser.add_argument('--playback',type=float,default=1.45)
 parser.add_argument('--expect-fixed',action='store_true')
 args=parser.parse_args()
 paths={'accepted_reference':args.reference,'previous':args.previous,'candidate':args.candidate};out={'scope':'Independent authored joint kinematics at2049 phases; final-modifier/native visual acceptance remains separate. Peak comparisons exclude the original endpoint discontinuity itself.','playback_scale':args.playback,'sources':{},'metrics':{}};poses={};docs={}
 for label,path in paths.items():
  d,b=load(path);a=next(a for a in d['animations'] if a['name']==args.clip);T=max(float(read(d,b,s['input']).max()) for s in a['samplers']);ts=np.linspace(0,T,2049);pos=positions(d,b,a,ts);poses[label]=pos;docs[label]=(d,b);out['sources'][label]={'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()};out['metrics'][label]=metric(pos,ts,args.playback)
 old,new=poses['accepted_reference'],poses['candidate'];mask=(ts>args.after)&(ts<T-args.before)
 delta={k:float(np.max(np.linalg.norm(new[k]-old[k],axis=1))) for k in old};outside={k:float(np.max(np.linalg.norm(new[k][mask]-old[k][mask],axis=1))) for k in old}
 current,cb=docs['previous'];candidate,nb=docs['candidate']
 out.update({'bridge_intervals_s':[[0,args.after],[T-args.before,T]],'unchanged_absolute_curve_fraction':1-(args.before+args.after)/T,'outside_bridge_max_joint_error_m':max(outside.values()),'maximum_joint_changes_m':dict(sorted(delta.items(),key=lambda x:x[1],reverse=True)),'all_other_animation_json_exact':[a for a in current['animations'] if a['name']!=args.clip]==[a for a in candidate['animations'] if a['name']!=args.clip],'recipient_nodes_meshes_skins_exact':all(current[k]==candidate[k] for k in ['nodes','meshes','skins']),'recipient_original_binary_prefix_exact':nb[:len(cb)]==cb})
 failures=[]
 if max(v['loop_endpoint_m'] for v in out['metrics']['candidate'].values())>.0005:failures.append('foot/toe loop endpoint exceeds0.5mm')
 if out['outside_bridge_max_joint_error_m']>.0000005:failures.append('accepted original joint motion changed outside local seam window')
 for suffixes in [('LeftFoot','RightFoot'),('LeftToeBase','RightToeBase')]:
  baseline=max(out['metrics']['accepted_reference']['mixamorig:'+s]['peak_vertical_mps'] for s in suffixes)
  newpeak=max(out['metrics']['candidate']['mixamorig:'+s]['peak_vertical_mps'] for s in suffixes)
  if newpeak>baseline*1.01:failures.append('vertical speed increased above original peak by more than1%: '+','.join(suffixes))
 for key in ['all_other_animation_json_exact','recipient_nodes_meshes_skins_exact','recipient_original_binary_prefix_exact']:
  if not out[key]:failures.append('recipient preservation failed: '+key)
 out.update({'failures':failures,'tool_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()});args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(out,indent=2)+'\n')
 print(json.dumps({'output':str(args.output),'failures':failures,'outside_bridge_max_joint_error_m':out['outside_bridge_max_joint_error_m'],'metrics':out['metrics']},indent=2))
 if args.expect_fixed and failures:raise SystemExit(1)
if __name__=='__main__':main()

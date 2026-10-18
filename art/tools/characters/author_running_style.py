"""Bake compact running arms, neutral wrists and a relaxed grip into source GLB.

Keeps the source phase/leg animation and mesh/skin/rest payloads. Replaces only
run upper-arm, forearm, Hand and finger rotation tracks; other clips stay exact.
No game modifier is executed. These are character art targets, not medical limits.
"""
from pathlib import Path
import argparse,copy,json,hashlib,math
import numpy as np
from scipy.spatial.transform import Rotation
from glb_io import load
from motion_math import world_matrices,sample_channel,palm_normal
from repair_head_neck import save,read
from rebuild_locomotion import Pose,aim_matrix,rotation,append_values

STYLE={
 'sora':(-16,19,68,81),'ren':(-15,18,68,80),'haru':(-18,13,70,80),
 'mio':(-16,19,70,82),'aoi':(-18,21,72,84),'tanaka':(-15,18,72,82),'kazuko':(-16,19,70,82),
}
# A quieter jog: elbows pass behind the torso instead of carrying both fists
# in front. Applied explicitly to an already-authored source, retaining fingers.
REFINED_STYLE={
 'sora':(-30,7,74,84),'ren':(-29,6,74,84),'haru':(-29,3,76,86),
 'mio':(-28,8,74,84),'aoi':(-27,11,76,86),'tanaka':(-27,7,76,86),'kazuko':(-28,8,74,84),
}
FINGERS=['Index','Middle','Ring','Pinky','Thumb']

def author(source,output,actor,report_path=None,fps=120,refine_existing=False):
 doc,raw=load(source);original=copy.deepcopy(doc);blob=bytearray(raw);rest,parents=world_matrices(doc,raw);ids={n.get('name'):i for i,n in enumerate(doc['nodes'])};run=next(a for a in original['animations'] if a['name']=='run');animation=next(a for a in doc['animations'] if a['name']=='run');duration=max(float(read(doc,raw,s['input']).max()) for s in run['samplers']);times=np.linspace(0,duration,max(2,math.ceil(duration*fps))+1,dtype=np.float32)
 rig=next(n for n in doc['nodes'] if n.get('name')=='Rig');extras=rig.setdefault('extras',{})
 previous_style=copy.deepcopy(extras.get('source_running_style',{}))
 if bool(previous_style)!=bool(refine_existing):raise ValueError('Use --refine-existing only with an explicitly authored running source')
 if refine_existing and previous_style.get('pose_revision',1)>=2:raise ValueError('Revision2 is already refined; use its explicit revision1 baseline')
 def values_at(time):return {(c['target']['node'],c['target']['path']):sample_channel(original,raw,run,c,float(time)) for c in run['channels'] if c['target']['path']!='weights'}
 bounds={side:[] for side in ['Left','Right']}
 for at in np.linspace(0,duration,241):
  w,_=world_matrices(original,raw,run,float(at))
  for side in bounds:
   v=w[ids['mixamorig:'+side+'ForeArm']][:3,3]-w[ids['mixamorig:'+side+'Arm']][:3,3];bounds[side].append(np.degrees(np.arctan2(v[2],-v[1])))
 bounds={s:(min(v),max(v)) for s,v in bounds.items()};axes={};grip={};selected=[]
 for side in ['Left','Right']:
  n=np.asarray(extras['palm_normal_'+side],float);n=np.array([n[0],n[2],-n[1]]);n/=np.linalg.norm(n)
  for finger in FINGERS:
   for k in [1,2,3]:
    i=ids['mixamorig:'+side+'Hand'+finger+str(k)];j=ids.get('mixamorig:'+side+'Hand'+finger+str(k+1));direction=rest[j][:3,3]-rest[i][:3,3] if j is not None else rest[i][:3,:3]@np.array([0.,1,0]);axis=np.cross(direction,n);axis/=np.linalg.norm(axis);local=np.linalg.inv(rest[i][:3,:3])@axis;local/=np.linalg.norm(local);axes[i]=local
    amount=([10,13,8] if finger=='Thumb' else [34,46,28])[k-1];grip[i]=(Rotation.from_quat(doc['nodes'][i].get('rotation',[0,0,0,1]))*Rotation.from_rotvec(local*np.deg2rad(amount))).as_quat()
    if not refine_existing:selected.append(i)
  selected.extend(ids['mixamorig:'+side+s] for s in ['Arm','ForeArm','Hand'])
 tracks={i:[] for i in selected};statistics={s:{'pitch':[],'wrist_y':[],'wrist_z':[],'elbow':[]} for s in ['Left','Right']};lo,hi,front_flex,back_flex=(REFINED_STYLE if refine_existing else STYLE)[actor]
 for at in times:
  p=Pose(original,rest,parents,values_at(at))
  for side in ['Left','Right']:
   upper,fore,hand=[ids['mixamorig:'+side+s] for s in ['Arm','ForeArm','Hand']];shoulder=p.world(upper)[:3,3].copy();elbow=p.world(fore)[:3,3].copy();v=elbow-shoulder;pitch=np.degrees(np.arctan2(v[2],-v[1]));minimum,maximum=bounds[side];phase=float(np.clip((pitch-minimum)/(maximum-minimum),0,1));desired=lo+(hi-lo)*phase;target=rotation([1,0,0],pitch-desired)@v;p.set_global(upper,basis=aim_matrix(p.world(upper)[:3,:3],v,target))
   shoulder=p.world(upper)[:3,3].copy();elbow=p.world(fore)[:3,3].copy();wrist=p.world(hand)[:3,3].copy();u=elbow-shoulder;f=wrist-elbow;hinge=np.cross(u,f);hinge/=np.linalg.norm(hinge);flex=np.degrees(np.arccos(np.clip(u@f/np.linalg.norm(u)/np.linalg.norm(f),-1,1)));wanted=back_flex+(front_flex-back_flex)*phase;p.set_global(fore,basis=rotation(hinge,wanted-flex)@p.world(fore)[:3,:3])
   if actor=='tanaka':p.set_global(upper,basis=rotation([0,0,1],3 if side=='Left' else -3)@p.world(upper)[:3,:3])
   wrist=p.world(hand)[:3,3].copy();elbow=p.world(fore)[:3,3].copy();fore_direction=wrist-elbow;fore_direction/=np.linalg.norm(fore_direction);mcp=np.mean([p.world(ids['mixamorig:'+side+'Hand'+finger+'1'])[:3,3] for finger in ['Index','Middle','Ring','Pinky']],axis=0);chest=p.world(ids['mixamorig:Spine2'])[:3,3];inward=chest-wrist;inward-=fore_direction*(inward@fore_direction);inward/=np.linalg.norm(inward);amount=np.deg2rad(4+3*phase);hand_direction=fore_direction*np.cos(amount)+inward*np.sin(amount);p.set_global(hand,basis=aim_matrix(p.world(hand)[:3,:3],mcp-wrist,hand_direction))
   # Roll the palm towards the body instead of presenting an upward flat hand.
   normal=palm_normal(original,rest,p.worlds(),side);normal-=fore_direction*(normal@fore_direction);normal/=np.linalg.norm(normal);angle=np.arctan2(np.cross(normal,inward)@fore_direction,normal@inward);angle=float(np.clip(angle,-np.deg2rad(40),np.deg2rad(40)));p.set_global(hand,basis=Rotation.from_rotvec(fore_direction*angle).as_matrix()@p.world(hand)[:3,:3])
   for finger in [] if refine_existing else FINGERS:
    for k in [1,2,3]:p.values[(ids['mixamorig:'+side+'Hand'+finger+str(k)],'rotation')]=grip[ids['mixamorig:'+side+'Hand'+finger+str(k)]]
   p.cache.clear();shoulder=p.world(upper)[:3,3];elbow=p.world(fore)[:3,3];wrist=p.world(hand)[:3,3];u=elbow-shoulder;f=wrist-elbow;statistics[side]['pitch'].append(float(np.degrees(np.arctan2(u[2],-u[1]))));statistics[side]['wrist_y'].append(float(wrist[1]-shoulder[1]));statistics[side]['wrist_z'].append(float(wrist[2]-shoulder[2]));statistics[side]['elbow'].append(float(np.degrees(np.arccos(np.clip(u@f/np.linalg.norm(u)/np.linalg.norm(f),-1,1)))))
  for i in tracks:tracks[i].append(p.values.get((i,'rotation'),doc['nodes'][i].get('rotation',[0,0,0,1])))
 ti=append_values(doc,blob,times[:,None],'SCALAR')
 for i,data in tracks.items():
  data=np.asarray(data,float);data[-1]=data[0]
  for k in range(1,len(data)):
   if data[k]@data[k-1]<0:data[k]*=-1
  accessor=append_values(doc,blob,data.astype(np.float32),'VEC4');sampler={'input':ti,'output':accessor,'interpolation':'LINEAR'};channel=next((c for c in animation['channels'] if c['target']=={'node':i,'path':'rotation'}),None)
  if channel:animation['samplers'][channel['sampler']]=sampler
  else:slot=len(animation['samplers']);animation['samplers'].append(sampler);animation['channels'].append({'sampler':slot,'target':{'node':i,'path':'rotation'}})
 extras['source_running_style']={'version':1,'source_sha256':hashlib.sha256(Path(source).read_bytes()).hexdigest(),'arms_authored':True,'wrists_authored':True,'grip_authored':True,'source_fps':fps,'upper_pitch_art_range_deg':[lo,hi],'elbow_art_range_deg':[front_flex,back_flex],'runtime_arm_style_required':False,'nonrun_animations_preserved':True}
 if refine_existing:extras['source_running_style'].update({'pose_revision':2,'profile':'quieter_backward_elbow_swing','finger_tracks_preserved':True,'previous_upper_pitch_art_range_deg':previous_style['upper_pitch_art_range_deg']})
 if refine_existing and actor=='tanaka':extras['source_running_style']['additional_outward_clearance_deg']=3
 if refine_existing:
  assert len(tracks)==6
  for c in run['channels']:
   if c['target']['path']=='rotation' and c['target']['node'] in tracks:continue
   assert animation['samplers'][c['sampler']]==run['samplers'][c['sampler']]
 for name in ['meshes','skins','materials','images','textures']:assert doc.get(name)==original.get(name)
 for a,b in zip(original['animations'],doc['animations']):
  if a['name']!='run':assert a==b
 output=Path(output);output.parent.mkdir(parents=True,exist_ok=True);save(doc,blob,output)
 report={'actor':actor,'input_sha256':hashlib.sha256(Path(source).read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'run_rotation_tracks':len(tracks),'samples':len(times),'source_pitch_bounds':bounds,'mesh_skin_rest_unchanged':True,'nonrun_animations_exact':True,'statistics':{side:{k:[min(v),max(v)] for k,v in data.items()} for side,data in statistics.items()}}
 if report_path:Path(report_path).write_text(json.dumps(report,indent=2)+'\n')
 return report

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__)
 for name in ['input','output','report']:p.add_argument('--'+name,type=Path,required=True)
 p.add_argument('--character',choices=list(STYLE),required=True);p.add_argument('--refine-existing',action='store_true');a=p.parse_args();print(author(a.input,a.output,a.character,a.report,refine_existing=a.refine_existing))

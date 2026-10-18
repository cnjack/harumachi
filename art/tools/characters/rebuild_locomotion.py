#!/usr/bin/env python3
"""Rebuild periodic, shoe-calibrated character walk/run clips in an arbitrary GLB folder.

Walk/run accessors, one explicitly flagged Kazuko wave, and Rig locomotion metadata
change. Meshes, skins,
rest joints, texture bytes, UVs and every other action are retained. The contact path
is expressed in metres and its derivative matches the declared root speed. Foot and
toe rotations are separate: heel strike -> flat support -> toe roll -> swing.

Use after structural skeleton changes and before clothing repair:
  python rebuild_locomotion.py --input-dir DIR --output-dir DIR
"""
from pathlib import Path
import argparse, copy, hashlib, json, math, sys
import numpy as np
from scipy.spatial.transform import Rotation, Slerp
from scipy.interpolate import CubicSpline, CubicHermiteSpline
from repair_head_neck import read, append, save
from motion_math import world_matrices, palm_normal, sample_channel
from glb_io import load

ROSTER = ('sora','ren','haru','mio','aoi','tanaka','kazuko')
REBUILD = {'sora': {'run'}, 'ren': {'walk','run'}, 'haru': set(), 'mio': {'run'}, 'aoi': {'walk','run'}, 'tanaka': {'walk','run'}, 'kazuko': {'run'}}
# Duration is one complete left/right stride. Older neighbours take shorter,
# quicker steps with quieter arms; Aoi has a child-sized stride and extra arm swing.
PROFILES = {
 'sora': dict(walk_speed=1.8, walk_t=.74, run_speed=3.7, run_t=.65, run_duty=.27, arm=1.0, run_arm=1.0, width=.76, sway=.010, lift=.065, run_lift=.25, lean=8.0),
 'ren': dict(walk_speed=1.5, walk_t=.78, walk_duty=.52, walk_center=-.065, run_speed=3.2, run_t=.67, arm=.94, run_arm=.94, width=.76, sway=.010, lift=.061, run_lift=.18, lean=8.5),
 'haru': dict(walk_speed=1.5, walk_t=.75, run_speed=4.5, run_t=.57, arm=.62, run_arm=.72, width=.84, sway=.008, lift=.046, run_lift=.21, lean=5.5),
 'mio': dict(walk_speed=1.25, walk_t=.91, run_speed=3.2, run_t=.67, arm=.68, run_arm=.88, width=.76, sway=.007, lift=.049, run_lift=.14, lean=7.0),
 'aoi': dict(walk_speed=1.15, walk_t=.68, walk_duty=.52, walk_center=-.045, run_speed=3.1, run_t=.57, run_duty=.24, flight_rise=.035, arm=1.12, run_arm=1.10, width=.81, sway=.011, lift=.056, run_lift=.14, lean=7.0),
 'tanaka': dict(walk_speed=1.5, walk_t=.77, walk_duty=.52, walk_center=-.065, run_speed=3.4, run_t=.64, run_duty=.28, flight_rise=.045, arm=.65, run_arm=.74, width=.85, sway=.008, lift=.045, run_lift=.15, lean=5.0),
 'kazuko': dict(walk_speed=1.5, walk_t=.83, run_speed=3.6, run_t=.64, run_duty=.28, flight_rise=.05, arm=.84, run_arm=.86, width=.82, sway=.009, lift=.055, run_lift=.18, lean=6.5),
}

def rotation(axis, degrees):
 axis=np.asarray(axis,dtype=float);return Rotation.from_rotvec(axis/max(np.linalg.norm(axis),1e-12)*math.radians(degrees)).as_matrix()
def aim_matrix(basis, vector, desired):
 a=vector/np.linalg.norm(vector);b=desired/np.linalg.norm(desired)
 axis=np.cross(a,b);dot=float(np.clip(np.dot(a,b),-1,1))
 if np.linalg.norm(axis)<1e-10:return basis.copy()
 return rotation(axis,math.degrees(math.acos(dot)))@basis

def shoe_sources(doc,binary):
 result=[]
 for node in doc['nodes']:
  if 'mesh' not in node or 'skin' not in node:continue
  skin=doc['skins'][node['skin']];joints=skin['joints'];bind=read(doc,binary,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
  for prim in doc['meshes'][node['mesh']]['primitives']:
   attr=prim['attributes'];vertices=read(doc,binary,attr['POSITION']);js=np.concatenate([read(doc,binary,attr[k]) for k in ['JOINTS_0','JOINTS_1'] if k in attr],axis=1);ws=np.concatenate([read(doc,binary,attr[k]) for k in ['WEIGHTS_0','WEIGHTS_1'] if k in attr],axis=1)
   for side in ['Left','Right']:
    foot_ids=[i for i,j in enumerate(joints) if doc['nodes'][j].get('name','').endswith((side+'Foot',side+'ToeBase'))]
    mask=np.sum(ws*np.isin(js,foot_ids),axis=1)>=.35
    if np.any(mask):result.append((side,np.c_[vertices[mask],np.ones(mask.sum())],js[mask],ws[mask],joints,bind))
 return result

def shoe_points(sources,worlds):
 result={'Left':[],'Right':[]}
 for side,vertices,js,ws,joints,bind in sources:
  matrices=np.array([worlds[j]@m for j,m in zip(joints,bind)])
  points=np.zeros((len(vertices),3))
  for index in range(js.shape[1]):points+=np.einsum('nij,nj->ni',matrices[js[:,index],:3,:],vertices)*ws[:,index,None]
  result[side].append(points)
 return {s:np.concatenate(a) for s,a in result.items()}

class Pose:
 def __init__(self,doc,rest,parents,values):
  self.doc=doc;self.rest=rest;self.parents=parents;self.values=values;self.cache={}
 def world(self,i):
  if i in self.cache:return self.cache[i]
  n=self.doc['nodes'][i];m=np.eye(4)
  if 'matrix' in n:m=np.array(n['matrix']).reshape(4,4).T
  else:
   m[:3,:3]=Rotation.from_quat(self.values.get((i,'rotation'),n.get('rotation',[0,0,0,1]))).as_matrix()@np.diag(self.values.get((i,'scale'),n.get('scale',[1,1,1])))
   m[:3,3]=self.values.get((i,'translation'),n.get('translation',[0,0,0]))
  self.cache[i]=(self.world(self.parents[i])@m if i in self.parents else m);return self.cache[i]
 def set_global(self,i,basis=None,origin=None):
  world=self.world(i).copy()
  if basis is not None:world[:3,:3]=basis
  if origin is not None:world[:3,3]=origin
  local=np.linalg.inv(self.world(self.parents[i]))@world if i in self.parents else world
  self.values[(i,'rotation')]=Rotation.from_matrix(local[:3,:3]).as_quat()
  self.values[(i,'translation')]=local[:3,3].copy();self.cache.clear()
 def set_hips_y(self,i,y):
  value=self.world(i)[:3,3].copy();value[1]=y;self.set_global(i,origin=value)
 def worlds(self):return {i:self.world(i) for i in range(len(self.doc['nodes']))}

def place_leg(pose,ids,side,ankle,foot_basis,toe_basis):
 thigh,shin,foot,toe=[ids['mixamorig:'+side+suffix] for suffix in ['UpLeg','Leg','Foot','ToeBase']]
 hip=pose.world(thigh)[:3,3].copy();current_knee=pose.world(shin)[:3,3].copy();current_ankle=pose.world(foot)[:3,3].copy()
 upper=np.linalg.norm(pose.rest[shin][:3,3]-pose.rest[thigh][:3,3]);lower=np.linalg.norm(pose.rest[foot][:3,3]-pose.rest[shin][:3,3]);line=ankle-hip;distance=np.linalg.norm(line);direction=line/max(distance,1e-12)
 reach=np.clip(distance,abs(upper-lower)+1e-5,upper+lower-1e-5);along=(upper*upper-lower*lower+reach*reach)/(2*reach);bend=math.sqrt(max(0,upper*upper-along*along))
 pole=np.array([.035 if side=='Left' else -.035,0,1.]);pole-=direction*np.dot(pole,direction);pole/=np.linalg.norm(pole)
 knee=hip+direction*along+pole*bend
 pose.set_global(thigh,basis=aim_matrix(pose.world(thigh)[:3,:3],current_knee-hip,knee-hip))
 new_knee=pose.world(shin)[:3,3].copy();new_ankle=pose.world(foot)[:3,3].copy()
 pose.set_global(shin,basis=aim_matrix(pose.world(shin)[:3,:3],new_ankle-new_knee,ankle-new_knee))
 pose.set_global(foot,basis=foot_basis);pose.set_global(toe,basis=toe_basis)
 return float(max(0,distance-upper-lower))

def foot_curve(phase,duty,speed,duration,lift,running,center=None):
 """C1 path: constant stance speed and smooth swing with continuous end velocity."""
 phase=phase%1.;travel=speed*duration*duty;centre=(-.12 if running else 0.0) if center is None else center
 if phase<duty:
  c=phase/duty;z=centre+travel*(.5-c);height=0.
  if running:pitch=-4*(max(0,1-c/.20)**2)+36*(max(0,(c-.48)/.52)**1.7)
  else:pitch=-10*(max(0,1-c/.20)**2)+27*(max(0,(c-.64)/.36)**1.7)
  toe=-pitch*.82 if pitch>0 else 0.
  return z,height,pitch,toe,True
 u=(phase-duty)/(1-duty);end=centre+travel*.5;start=centre-travel*.5;derivative=-speed*duration*(1-duty)
 if running:
  z=float(CubicHermiteSpline([0,.10,.35,.65,.85,1],[start,start-.035,start+travel*.18,start+travel*.46,start+travel*.74,end],[derivative,0,travel*.9,travel*1.4,travel*1.6,derivative])(u))
 else:
  # The former single cubic sent the leading foot past its landing target.
  # Recover behind the body first, then keep the final overshoot to millimetres.
  z=float(CubicHermiteSpline([0,.15,.45,.75,.95,1],[start,start-.025,start+travel*.30,start+travel*.75,end+.004,end],[derivative,0,travel*1.4,travel*1.6,0,derivative])(u))
 # Recovery peaks early for running, bringing the heel up under the body.
 shape=(u**1.5*(1-u)**4.5)/(.25**1.5*.75**4.5) if running else math.sin(math.pi*u)**2*(1.0-.12*math.sin(2*math.pi*u))
 height=lift*shape+(.09*math.sin(math.pi*u)**2 if running else 0)
 start_pitch=36 if running else 27;end_pitch=-4 if running else -10
 smooth=u*u*(3-2*u);pitch=start_pitch*(1-smooth)+end_pitch*smooth-12*math.sin(math.pi*u)
 toe=-start_pitch*.82*(1-min(1,u/.20))**2
 return z,height,pitch,toe,False

def append_values(d,b,values,kind):
 values=np.asarray(values,dtype='<f4');values=values.reshape(-1,1) if kind=='SCALAR' else values
 template=next(i for i,a in enumerate(d['accessors']) if a['componentType']==5126 and a['type']==kind)
 return append(d,b,template,values)

def periodic_sources(d,b,animation,count):
 """Close every source upper-body channel before fitting a periodic spline."""
 duration=max(float(read(d,b,s['input']).max()) for s in animation['samplers']);phases=np.linspace(0,1,count)
 result={}
 for channel in animation['channels']:
  if channel['target']['path']=='weights':continue
  sampler=animation['samplers'][channel['sampler']];times=read(d,b,sampler['input']).ravel()/duration;values=read(d,b,sampler['output']).astype(float);key=(channel['target']['node'],channel['target']['path'])
  if key[1]=='rotation':
   for j in range(1,len(values)):
    if np.dot(values[j-1],values[j])<0:values[j]*=-1
  times=(times-times[0])/(times[-1]-times[0])
  values[-1]=values[0];spline=CubicSpline(times,values,bc_type='periodic');data=spline(phases)
  if key[1]=='rotation':data/=np.linalg.norm(data,axis=1)[:,None]
  result[key]=data
 return result

def rebuild(source,target,who,samples=121,selected_clips=None):
 d,old=load(source);b=bytearray(old);rest,parents=world_matrices(d,b);ids={n.get('name'):i for i,n in enumerate(d['nodes'])};sources=shoe_sources(d,b);reference_shoes=shoe_points(sources,rest);profile=PROFILES[who];hips=ids['mixamorig:Hips'];rig=ids['Rig'];before_geometry=geometry_digest(d,b)
 hip_midpoint=(rest[ids['mixamorig:LeftUpLeg']][:3,3]+rest[ids['mixamorig:RightUpLeg']][:3,3])*.5
 ankle_x={side:float(rest[ids['mixamorig:'+side+'Foot']][0,3]-np.median(reference_shoes[side][:,0])+rest[ids['mixamorig:'+side+'UpLeg']][0,3]*profile['width']) for side in ['Left','Right']}
 idle=next(a for a in d['animations'] if a['name']=='idle');idle_values=periodic_sources(d,b,idle,3)
 selected_clips=set(selected_clips or ['walk','run']);previous_metadata=copy.deepcopy(d['nodes'][rig].get('extras',{}).get('locomotion_rebuild',{}));previous_rebuilt=set(previous_metadata.get('rebuilt_clips',[]));checks={}
 for clip in ['walk','run']:
  running=clip=='run';animation=next(a for a in d['animations'] if a['name']==clip)
  if clip not in selected_clips:
   checks[clip]={'mode':'source clip and accessors retained unchanged'};continue
  if clip not in REBUILD[who]:
   duration=max(float(read(d,b,s['input']).max()) for s in animation['samplers']);values_out=periodic_sources(d,b,animation,samples);time_index=append_values(d,b,np.linspace(0,duration,samples),'SCALAR');channels=[];samplers=[]
   for (node,path),data in sorted(values_out.items()):
    output=append_values(d,b,data,'VEC4' if path=='rotation' else 'VEC3');samplers.append({'input':time_index,'output':output,'interpolation':'LINEAR'});channels.append({'sampler':len(samplers)-1,'target':{'node':node,'path':path}})
   animation['samplers']=samplers;animation['channels']=channels;checks[clip]={'mode':'preserve accepted motion; periodic spline seam only','duration_s':duration,'speed_mps':d['nodes'][rig]['extras'][clip+'_speed']};continue
  duration=profile[clip+'_t'];speed=profile[clip+'_speed'];duty=float(profile.get('run_duty',.30)) if running else float(profile.get('walk_duty',.56));curves=periodic_sources(d,b,animation,samples);values_out={};phase_rows=[];last_worlds=None
  for index,phase in enumerate(np.linspace(0,1,samples)):
   p=phase%1.;values={k:v[index].copy() for k,v in curves.items()};pose=Pose(d,rest,parents,values)
   # Person-specific upper-body amplitude, retaining the source's opposite-arm rhythm.
   for side in ['Left','Right']:
    for suffix in ['Shoulder','Arm','ForeArm','Hand']:
     node=ids.get('mixamorig:'+side+suffix);key=(node,'rotation')
     if node is None or key not in values:continue
     baseline=idle_values.get(key,[np.array(d['nodes'][node].get('rotation',[0,0,0,1]))])[0]
     amount=1.0 if clip in previous_rebuilt else profile['run_arm' if running else 'arm']
     if suffix=='ForeArm' and running and who in ['haru','tanaka']:amount*=.90
     values[key]=Slerp([0,1],Rotation.from_quat([baseline,values[key]]))([amount])[0].as_quat() if amount<=1 else (Rotation.from_quat(baseline)*(Rotation.from_quat(baseline).inv()*Rotation.from_quat(values[key]))**amount).as_quat()
   pose.cache.clear()
   hip_origin=rest[hips][:3,3].copy();hip_origin[0]+=profile['sway']*math.sin(2*math.pi*p)
   hip_basis=rotation([0,1,0],(-3.0 if running else -2.2)*math.cos(2*math.pi*p))@rotation([0,0,1],(-1.5 if running else -2.0)*math.sin(2*math.pi*p))@rest[hips][:3,:3]
   pose.set_global(hips,basis=hip_basis,origin=hip_origin)
   # Keep the authored anatomy; add a restrained whole torso forward pitch.
   spine=ids.get('mixamorig:Spine')
   if spine is not None and running:
    torso=pose.world(spine)[:3,:3].copy();pose.set_global(spine,basis=rotation([1,0,0],-profile['lean']*.45)@torso)
   targets={};bases={};toe_bases={};stance={};heights={};pitches={}
   for side,offset in [('Left',0),('Right',.5)]:
    z,height,pitch,toe,contact=foot_curve(p+offset,duty,speed,duration,profile['run_lift' if running else 'lift'],running,None if running else profile.get('walk_center',0.0))
    foot=ids['mixamorig:'+side+'Foot'];toe_node=ids['mixamorig:'+side+'ToeBase'];base=rotation([1,0,0],pitch)@rest[foot][:3,:3];toe_base=rotation([1,0,0],pitch+toe)@rest[toe_node][:3,:3]
    # Rotate the original sole around the ankle to get its actual flat/rolled height.
    reference_pose=Pose(d,rest,parents,{})
    reference_pose.set_global(foot,basis=base);reference_pose.set_global(toe_node,basis=toe_base)
    rotated=shoe_points(sources,reference_pose.worlds())[side]
    ankle_y=rest[foot][1,3]+.008+height-float(rotated[:,1].min())
    targets[side]=np.array([ankle_x[side],ankle_y,hip_midpoint[2]+z]);bases[side]=base;toe_bases[side]=toe_base;stance[side]=contact;heights[side]=height;pitches[side]=pitch
   # Solve pelvis height from leg reach, rather than lifting ankles under a low pelvis.
   # The stance knee extends in late support; running compresses under load and rises
   # into the two explicitly airborne intervals.
   available=[]
   for side,offset in [('Left',0),('Right',.5)]:
    if not stance[side]:continue
    contact_phase=((p+offset)%1)/duty;thigh=ids['mixamorig:'+side+'UpLeg'];shin=ids['mixamorig:'+side+'Leg'];foot=ids['mixamorig:'+side+'Foot'];a=np.linalg.norm(rest[shin][:3,3]-rest[thigh][:3,3]);bb=np.linalg.norm(rest[foot][:3,3]-rest[shin][:3,3]);flex=(18+33*math.sin(math.pi*contact_phase)**1.4) if running else (10+5*math.sin(math.pi*contact_phase)**2)
    reach=math.sqrt(a*a+bb*bb+2*a*bb*math.cos(math.radians(flex)));hip=pose.world(thigh)[:3,3];horizontal=np.linalg.norm((targets[side]-hip)[[0,2]]);dy=math.sqrt(max(.02,reach*reach-horizontal*horizontal));available.append(targets[side][1]+dy-(hip[1]-pose.world(hips)[1,3]))
   if available:hip_y=min(available)
   else:
    # Interpolate the landing/take-off pelvis heights continuously through flight.
    landing=[]
    for side,offset in [('Left',0),('Right',.5)]:
     thigh=ids['mixamorig:'+side+'UpLeg'];shin=ids['mixamorig:'+side+'Leg'];foot=ids['mixamorig:'+side+'Foot'];a=np.linalg.norm(rest[shin][:3,3]-rest[thigh][:3,3]);bb=np.linalg.norm(rest[foot][:3,3]-rest[shin][:3,3]);reach=math.sqrt(a*a+bb*bb+2*a*bb*math.cos(math.radians(18)))
     ends=[]
     for edge in [duty-1e-9,0.]:
      zz,hh,pp,tt,cc=foot_curve(edge,duty,speed,duration,profile['run_lift'],True);delta=reference_shoes[side]-rest[foot][:3,3];yy=.008-float((delta@rotation([1,0,0],pp).T)[:,1].min());hip=pose.world(thigh)[:3,3];horizontal=np.linalg.norm(np.array([ankle_x[side],hip_midpoint[2]+zz])-hip[[0,2]]);ends.append(yy+math.sqrt(max(.02,reach*reach-horizontal*horizontal))-(hip[1]-pose.world(hips)[1,3]))
     landing.append(ends)
    fp=(p%.5-duty)/(.5-duty);before_side=0 if p<.5 else 1;after_side=1-before_side;hip_y=(1-fp)*landing[before_side][0]+fp*landing[after_side][1]+profile.get('flight_rise',.065)*math.sin(math.pi*fp)
   pose.set_hips_y(hips,hip_y)
   # Swing endpoints must also remain reachable; a long leading leg cannot
   # be silently clamped while the opposite leg determines the pelvis.
   for side in ['Left','Right']:
    thigh=ids['mixamorig:'+side+'UpLeg'];shin=ids['mixamorig:'+side+'Leg'];foot=ids['mixamorig:'+side+'Foot'];a=np.linalg.norm(rest[shin][:3,3]-rest[thigh][:3,3]);bb=np.linalg.norm(rest[foot][:3,3]-rest[shin][:3,3]);hip=pose.world(thigh)[:3,3];horizontal=np.linalg.norm((targets[side]-hip)[[0,2]]);reach=(a+bb)*(.987 if running else .996)
    hip_y=min(hip_y,targets[side][1]+math.sqrt(max(.002,reach*reach-horizontal*horizontal))-(hip[1]-pose.world(hips)[1,3]))
   pose.set_hips_y(hips,hip_y)
   max_unreach=0
   for side in ['Left','Right']:max_unreach=max(max_unreach,place_leg(pose,ids,side,targets[side],bases[side],toe_bases[side]))
   # Complete skinned shoes, including secondary weights, determine the final target.
   # Iteration is offline only. Runtime keeps its sparse safety envelope for terrain.
   for iteration in range(10):
    shoes=shoe_points(sources,pose.worlds());errors={s:.008+heights[s]-float(v[:,1].min()) for s,v in shoes.items()}
    if max(abs(v) for v in errors.values())<.00008:break
    for side in ['Left','Right']:
     targets[side][1]+=errors[side]
    root_limit=float(pose.world(hips)[1,3])
    for side in ['Left','Right']:
     thigh=ids['mixamorig:'+side+'UpLeg'];shin=ids['mixamorig:'+side+'Leg'];foot=ids['mixamorig:'+side+'Foot'];a=np.linalg.norm(rest[shin][:3,3]-rest[thigh][:3,3]);bb=np.linalg.norm(rest[foot][:3,3]-rest[shin][:3,3]);hip=pose.world(thigh)[:3,3];horizontal=np.linalg.norm((targets[side]-hip)[[0,2]]);reach=(a+bb)*(.990 if running else .998)
     root_limit=min(root_limit,targets[side][1]+math.sqrt(max(.002,reach*reach-horizontal*horizontal))-(hip[1]-pose.world(hips)[1,3]))
    pose.set_hips_y(hips,root_limit)
    for side in ['Left','Right']:place_leg(pose,ids,side,targets[side],bases[side],toe_bases[side])
   # Running elbows stay beside the ribs and forearms move in the sagittal
   # plane. The source's broad outward wrists caused Sora's rejected pose.
   if running:
    for side,offset in [('Left',0),('Right',.5)]:
     upper=ids['mixamorig:'+side+'Arm'];fore=ids['mixamorig:'+side+'ForeArm'];hand=ids['mixamorig:'+side+'Hand'];shoulder=pose.world(upper)[:3,3].copy();arm_length=np.linalg.norm(rest[fore][:3,3]-rest[upper][:3,3]);fore_length=np.linalg.norm(rest[hand][:3,3]-rest[fore][:3,3]);sg=1 if side=='Left' else -1;swing=-math.cos(2*math.pi*(p+offset));angle=math.radians(5+34*profile['run_arm']*swing);elbow_angle=math.radians(83 if who in ['haru','tanaka'] else 92 if who=='aoi' else 88);out=.026 if who=='aoi' else .035;upper_vector=np.array([sg*out,-math.cos(angle)*arm_length,math.sin(angle)*arm_length]);upper_vector*=arm_length/np.linalg.norm(upper_vector);elbow=shoulder+upper_vector;fore_vector=np.array([-sg*.020,-math.cos(angle+elbow_angle)*fore_length,math.sin(angle+elbow_angle)*fore_length]);fore_vector*=fore_length/np.linalg.norm(fore_vector);wrist=elbow+fore_vector;current_elbow=pose.world(fore)[:3,3].copy();pose.set_global(upper,basis=aim_matrix(pose.world(upper)[:3,:3],current_elbow-shoulder,elbow-shoulder));new_elbow=pose.world(fore)[:3,3].copy();new_wrist=pose.world(hand)[:3,3].copy();pose.set_global(fore,basis=aim_matrix(pose.world(fore)[:3,:3],new_wrist-new_elbow,wrist-new_elbow))
   # Relaxed fingers follow the measured palm frame instead of one shared fist.
   if running:
    for side in ['Left','Right']:
     hand=ids['mixamorig:'+side+'Hand'];normal=palm_normal(d,rest,pose.worlds(),side)
     for digit in ['Index','Middle','Ring','Pinky']:
      for segment in [1,2,3]:
       node=ids.get(f'mixamorig:{side}Hand{digit}{segment}')
       if node is None:continue
       children=d['nodes'][node].get('children',[])
       if not children:continue
       current=pose.world(node);direction=pose.world(children[0])[:3,3]-current[:3,3];axis=np.cross(direction,normal)
       amount=(8+segment*3)*(0.70 if who in ['haru','tanaka'] else 1.12 if who=='aoi' else 1.)
       pose.set_global(node,basis=rotation(axis,amount)@current[:3,:3])
   worlds=pose.worlds();shoes=shoe_points(sources,worlds);max_unreach=max(float(np.linalg.norm(worlds[ids['mixamorig:'+s+'Foot']][:3,3]-targets[s])) for s in ['Left','Right']);phase_rows.append({'phase':float(phase),'stance':stance,'shoe_min_y_m':{s:float(v[:,1].min()) for s,v in shoes.items()},'hips_y_m':float(worlds[hips][1,3]),'unreachable_m':max_unreach})
   for key,value in pose.values.items():values_out.setdefault(key,[]).append(value.copy())
   if index==0:first_worlds={i:m.copy() for i,m in worlds.items()}
   last_worlds=worlds
  # Exact endpoint equality also covers source upper body and toe/finger channels.
  for key,values in values_out.items():values[-1]=values[0].copy()
  channels=[];samplers=[];time_index=append_values(d,b,np.linspace(0,duration,samples),'SCALAR')
  for (node,path),values in sorted(values_out.items()):
   if path=='rotation':
    for i in range(1,len(values)):
     if np.dot(values[i-1],values[i])<0:values[i]=-values[i]
   output=append_values(d,b,values,'VEC4' if path=='rotation' else 'VEC3');samplers.append({'input':time_index,'output':output,'interpolation':'LINEAR'});channels.append({'sampler':len(samplers)-1,'target':{'node':node,'path':path}})
  animation['samplers']=samplers;animation['channels']=channels
  checks[clip]={'duration_s':duration,'speed_mps':speed,'cadence_steps_min':120/duration,'stance_duty':duty,'double_flight_fraction':float(np.mean([r['shoe_min_y_m']['Left']>.025 and r['shoe_min_y_m']['Right']>.025 for r in phase_rows[:-1]])),'shoe_min_m':min(min(r['shoe_min_y_m'].values()) for r in phase_rows),'hips_range_m':float(np.ptp([r['hips_y_m'] for r in phase_rows])),'max_unreachable_m':max(r['unreachable_m'] for r in phase_rows),'phase_samples':phase_rows}
 if who=='kazuko' and 'run' in selected_clips:
  wave=next(a for a in d['animations'] if a['name']=='wave');source_wave=copy.deepcopy(wave);duration=max(float(read(d,b,s['input']).max()) for s in source_wave['samplers']);tracks={};times=np.linspace(0,duration,81)
  for time in times:
   values={(ch['target']['node'],ch['target']['path']):sample_channel(d,b,source_wave,ch,float(time)) for ch in source_wave['channels'] if ch['target']['path']!='weights'};pose=Pose(d,rest,parents,values);hand=ids['mixamorig:RightHand'];original_hand=pose.world(hand)[:3,:3].copy()
   for suffix,amount in [('Shoulder',.80),('Arm',.88)]:
    node=ids.get('mixamorig:Right'+suffix);key=(node,'rotation')
    if node is None or key not in values:continue
    baseline=idle_values.get(key,[np.array(d['nodes'][node].get('rotation',[0,0,0,1]))])[0];values[key]=Slerp([0,1],Rotation.from_quat([baseline,values[key]]))([amount])[0].as_quat();pose.cache.clear()
   pose.set_global(hand,basis=original_hand)
   for suffix in ['Shoulder','Arm','Hand']:
    key=(ids['mixamorig:Right'+suffix],'rotation');tracks.setdefault(key,[]).append(pose.values[key].copy())
  time_index=append_values(d,b,times,'SCALAR')
  for key,values in tracks.items():
   channel=next(ch for ch in wave['channels'] if ch['target']=={'node':key[0],'path':key[1]});output=append_values(d,b,values,'VEC4');wave['samplers'].append({'input':time_index,'output':output,'interpolation':'LINEAR'});channel['sampler']=len(wave['samplers'])-1
  checks['wave']={'mode':'Kazuko right shoulder .80 / upper arm .88 amplitude; palm orientation retained','duration_s':duration}
 d['nodes'][rig].setdefault('extras',{}).update({**{clip+'_speed':profile[clip+'_speed'] for clip in REBUILD[who]&selected_clips},'locomotion_rebuild':{**previous_metadata,'version':2,'character':who,'rebuilt_clips':sorted(previous_rebuilt|(REBUILD[who]&selected_clips)),'contact_calibration':'all skinned shoe vertices, 8mm terrain safety margin','walk_stance_duty':profile.get('walk_duty',.56),'run_stance_duty':profile.get('run_duty',.30),'profile':profile,'walk_phase_origin':'Left heel strike','run_phase_origin':'Left landing','periodic_endpoint':True}})
 assert geometry_digest(d,b)==before_geometry,'Geometry changed during locomotion rebuild'
 save(d,b,target)
 report={'character':who,'source':str(source),'output':str(target),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'geometry_digest':before_geometry,'clips':checks}
 return report

def geometry_digest(d,b):
 h=hashlib.sha256()
 for node in d['nodes']:
  if 'mesh' not in node:continue
  for primitive in d['meshes'][node['mesh']]['primitives']:
   for key,index in sorted(primitive['attributes'].items()):h.update(key.encode());h.update(read(d,b,index).tobytes())
   if 'indices' in primitive:h.update(read(d,b,primitive['indices']).tobytes())
 for image in d.get('images',[]):
  if 'bufferView' in image:
   view=d['bufferViews'][image['bufferView']];start=view.get('byteOffset',0);h.update(b[start:start+view['byteLength']])
 return h.hexdigest()

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--input-dir',type=Path,required=True);parser.add_argument('--output-dir',type=Path,required=True);parser.add_argument('--characters',nargs='+',choices=ROSTER,default=list(ROSTER));parser.add_argument('--clips',nargs='+',choices=['walk','run'],default=['walk','run']);parser.add_argument('--samples',type=int,default=121);args=parser.parse_args()
 if any((args.output_dir/f'CH_{who}.glb').exists() for who in args.characters):parser.error('Output GLBs already exist. Use a fresh immutable versioned output directory.')
 args.output_dir.mkdir(parents=True,exist_ok=True);reports=[]
 for who in args.characters:
  report=rebuild(args.input_dir/f'CH_{who}.glb',args.output_dir/f'CH_{who}.glb',who,args.samples,args.clips);reports.append(report);print(who,{k:{key:value for key,value in c.items() if key!='phase_samples'} for k,c in report['clips'].items()},flush=True)
 (args.output_dir/'locomotion-rebuild.json').write_text(json.dumps({'scope':'offline geometry; native rendering required separately','characters':reports},ensure_ascii=False,indent=2)+'\n')
 manifest={'stage':'body-structure-to-compact-locomotion','tool_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'input_directory':str(args.input_dir.resolve()),'output_directory':str(args.output_dir.resolve()),'selected_clips':args.clips,'samples_per_clip':args.samples,'characters':[{k:r[k] for k in ['character','source','output','source_sha256','output_sha256','geometry_digest']} for r in reports]}
 (args.output_dir/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
if __name__=='__main__':main()

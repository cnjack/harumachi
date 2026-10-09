"""Measure hand proportions from rest meshes, excluding thumb from palm width."""
from pathlib import Path
import argparse,json,sys
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
from repair_head_neck import read
from retime_glb import load
from motion_math import world_matrices

p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('models',type=Path,nargs='+');a=p.parse_args();rows=[]
for path in a.models:
 d,b=load(path);world,_=world_matrices(d,b);rig=next(n for n in d['nodes'] if n.get('name')=='Rig');names={n.get('name'):i for i,n in enumerate(d['nodes'])};parts=[]
 for ni,node in enumerate(d['nodes']):
  if 'mesh' not in node or 'skin' not in node:continue
  if d['meshes'][node['mesh']].get('name','').startswith('HiddenArm'):continue
  joints=d['skins'][node['skin']]['joints'];bone_names=[d['nodes'][j].get('name','') for j in joints]
  for primitive in d['meshes'][node['mesh']]['primitives']:
   at=primitive['attributes'];pp=read(d,b,at['POSITION']);pp=(np.c_[pp,np.ones(len(pp))]@world[ni].T)[:,:3]
   ids=np.c_[tuple(read(d,b,at[k]) for k in ['JOINTS_0','JOINTS_1'] if k in at)];weights=np.c_[tuple(read(d,b,at[k]) for k in ['WEIGHTS_0','WEIGHTS_1'] if k in at)]
   dense=np.zeros((len(pp),len(joints)));np.add.at(dense,(np.repeat(np.arange(len(pp)),ids.shape[1]),ids.ravel()),weights.ravel());parts.append((pp,dense,bone_names))
 points=np.concatenate([p[0] for p in parts]);height=float(np.ptp(points[:,1]));head=points[(points[:,1]>.84*height)&(abs(points[:,0])<.2*height)];head_width=float(np.diff(np.quantile(head[:,0],[.01,.99]))[0]);hands=[]
 for side in ['Left','Right']:
  hi=names['mixamorig:'+side+'Hand'];wrist=world[hi][:3,3]
  x,y,z=rig['extras']['palm_normal_'+side];normal=np.array([x,z,-y]);cloud=[];palm_candidates=[]
  for pp,dense,bone_names in parts:
   family=dense[:,[i for i,n in enumerate(bone_names) if n.startswith('mixamorig:'+side+'Hand')]].sum(axis=1)
   thumb=dense[:,[i for i,n in enumerate(bone_names) if n.startswith('mixamorig:'+side+'HandThumb')]].sum(axis=1)
   keep=family>.65;cloud.extend(pp[keep]);palm_candidates.extend(pp[keep&(thumb<.2)])
  cloud=np.asarray(cloud);candidate=np.asarray(palm_candidates)
  # A glTF joint's local Y is not guaranteed to be the anatomical long axis.
  _,_,basis=np.linalg.svd(candidate-candidate.mean(axis=0),full_matrices=False);axis=basis[0];axis-=normal*np.dot(axis,normal);axis/=np.linalg.norm(axis)
  if np.dot(axis,candidate.mean(axis=0)-wrist)<0:axis*=-1
  cross=np.cross(axis,normal);cross/=np.linalg.norm(cross);along=(candidate-wrist)@axis;palms=candidate[(along>.008*height)&(along<.045*height)]
  length=float(np.quantile(np.linalg.norm(cloud-wrist,axis=1),.99));width=float(np.diff(np.quantile((palms-wrist)@cross,[.01,.99]))[0]);hands.append({'side':side,'hand_vertices':len(cloud),'palm_vertices':len(palms),'wrist_to_tip_m':length,'palm_width_without_thumb_m':width,'length_height_ratio':length/height,'palm_head_width_ratio':width/head_width})
 row={'source':str(path),'height_m':height,'head_width_including_hair_m':head_width,'hands':hands};rows.append(row);print(json.dumps(row),flush=True)
a.out.write_text(json.dumps({'method':'rest mesh skin-group regions; 1/99 percentiles; hair-inclusive head width is a style reference, not an anatomical norm','characters':rows},indent=2)+'\n')

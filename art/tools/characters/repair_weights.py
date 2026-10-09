"""Repair garment semantics on the accepted exterior; no mesh, UV or image edits."""
import bpy,sys,json,math,numpy as np
from pathlib import Path
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[3];who=sys.argv[sys.argv.index('--')+1];base=ROOT/'art/models/character_roster_apose_20261004/binding';path=base/'authoring'/f'{who}_proxy.blend'
original=base/'original_authoring'/f'{who}_proxy.blend'
bpy.ops.wm.open_mainfile(filepath=str(original if original.exists() else path));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
rig.animation_data.action=None
for track in rig.animation_data.nla_tracks:track.mute=True
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update();H=max(v.co.z for v in mesh.data.vertices)
image=next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image);pixels=np.empty(len(image.pixels),dtype=np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4))
colours=np.zeros((len(mesh.data.vertices),3));counts=np.zeros(len(mesh.data.vertices))
for loop in mesh.data.loops:
 uv=mesh.data.uv_layers.active.data[loop.index].uv;colours[loop.vertex_index]+=pixels[int(uv.y*image.size[1])%image.size[1],int(uv.x*image.size[0])%image.size[0],:3];counts[loop.vertex_index]+=1
colours/=np.maximum(counts[:,None],1)
body_names=['mixamorig:Hips','mixamorig:Spine','mixamorig:Spine1','mixamorig:Spine2'];body_z=[rig.data.bones[n].head_local.z for n in body_names]
def smooth(a,b,t):
 u=max(0,min(1,(t-a)/(b-a)));return u*u*(3-2*u)
def torso(z):
 if z<=body_z[0]:return {body_names[0]:1}
 for i in range(len(body_z)-1):
  if z<=body_z[i+1]:
   u=(z-body_z[i])/(body_z[i+1]-body_z[i]);return {body_names[i]:1-u,body_names[i+1]:u}
 return {body_names[-1]:1}
def add(weights,name,value):weights[name]=weights.get(name,0)+value
def is_white(c):return min(c)>.4 and max(c)-min(c)<.12
report={'character':who,'torso':0,'sleeve':0,'apron':0,'shoulder_smoothed':0};new_weights=[];smooth_mask=[]
for vertex in mesh.data.vertices:
 p=vertex.co;r,g,b=colours[vertex.index];weights={mesh.vertex_groups[x.group].name:x.weight for x in vertex.groups};modified=False;root_smooth=False
 neck=rig.data.bones['mixamorig:Neck'].head_local.z
 eligible=.20*H<p.z<neck+.01*H
 for side in ['Left','Right']:
  hand_head=rig.data.bones['mixamorig:'+side+'Hand'].head_local
  finger_share=sum(value for name,value in weights.items() if name.startswith('mixamorig:'+side+'Hand'))
  if finger_share>.50:eligible=False
 # A vest, apron or draped cardigan has no arm attachment, even when its
 # nearest anatomical proxy triangle belongs to an arm.
 vest=who=='haru' and abs(p.x)<.20*H and .37*H<p.z<.80*H and ((g>r*.98 and g>b*1.18 and r>b*1.10) or p.y<rig.data.bones['mixamorig:Hips'].head_local.y-.005*H)
 apron=who=='ren' and .27*H<p.z<.76*H and abs(p.x)<.17*H and (is_white((r,g,b)) or (min(r,g,b)>.34 and p.y<rig.data.bones['mixamorig:Hips'].head_local.y-.05*H))
 yellow=who=='kazuko' and abs(p.x)<.17*H and .25*H<p.z<.80*H and ((r>.30 and g>.22 and b<g*.86) or p.y<rig.data.bones['mixamorig:Hips'].head_local.y-.045*H)
 pink=who=='kazuko' and abs(p.x)<.21*H and r>g*1.05 and b>g*.98 and r>.4 and p.z>.46*H
 if eligible and (vest or apron or yellow or pink):
  weights=torso(p.z);modified=True;report['apron' if apron or yellow else 'torso']+=1
 else:
  for side,sign in [('Left',1),('Right',-1)]:
   arm=rig.data.bones['mixamorig:'+side+'Arm'];fore=rig.data.bones['mixamorig:'+side+'ForeArm'];hand=rig.data.bones['mixamorig:'+side+'Hand'];a=arm.head_local;e=fore.head_local;w=hand.head_local
   upper=e-a;lower=w-e;t=(p-a).dot(upper)/upper.length_squared
   if t<=1:s=t*upper.length;closest=a+t*upper
   else:u=(p-e).dot(lower)/lower.length_squared;s=upper.length+u*lower.length;closest=e+u*lower
   radius=(p-closest).length
   cloth=(r>g*1.20 and g>b*1.12 and not (r>.6 and g/r>.64 and b/r>.46)) if who=='ren' else (b>g*1.03 and b>r*.95) if who=='haru' else (b>r*1.08 and b>g*1.01) if who=='tanaka' else is_white((r,g,b))
   arm_surface=cloth or (radius<.09*H and s>.02*H and s<upper.length+lower.length-.035*H)
   if not eligible or not arm_surface or sign*p.x<sign*a.x-.035*H:continue
   # Torso-facing jacket panels stay on the torso. Only the close, lateral
   # tube follows the upper-arm / elbow interpolation.
   on_sleeve=(who=='haru') or radius<=.13*H
   if s<-.02*H or not on_sleeve or s>upper.length+lower.length-.03*H:
    if who in ['ren','haru','tanaka'] and abs(p.x)<.14*H:weights=torso(p.z);modified=True;report['torso']+=1
    continue
   attach=smooth(-.020*H,.040*H,s)
   elbow_mix=smooth(upper.length-.035*H,upper.length+.035*H,s)
   weights={n:weight*(1-attach) for n,weight in torso(p.z).items()}
   add(weights,'mixamorig:'+side+'Arm',attach*(1-elbow_mix))
   twist_u=smooth(upper.length,upper.length+lower.length,s)
   add(weights,'mixamorig:'+side+'ForeArm',attach*elbow_mix*(1-twist_u));add(weights,'TWIST_'+side,attach*elbow_mix*twist_u)
   modified=True;root_smooth=s<.065*H;report['sleeve']+=1;break
 new_weights.append(weights);smooth_mask.append(root_smooth)
# Smooth the projected sleeve roots on actual connected topology; locked
# torso garment labels are not allowed to receive arm weights again.
names=[g.name for g in mesh.vertex_groups];lookup={n:i for i,n in enumerate(names)};values=np.zeros((len(mesh.data.vertices),len(names)),dtype=np.float32)
for i,weights in enumerate(new_weights):
 for name,weight in weights.items():values[i,lookup[name]]=weight
edges=np.array([e.vertices[:] for e in mesh.data.edges],dtype=np.int32);degree=np.bincount(edges.reshape(-1),minlength=len(values));mask=np.array(smooth_mask,dtype=bool)
for iteration in range(8):
 sums=np.zeros_like(values);np.add.at(sums,edges[:,0],values[edges[:,1]]);np.add.at(sums,edges[:,1],values[edges[:,0]]);average=sums/np.maximum(degree[:,None],1);values[mask]=values[mask]*.75+average[mask]*.25
report['shoulder_smoothed']=int(mask.sum())
for vertex in mesh.data.vertices:
 row=values[vertex.index];best=np.argsort(row)[-4:];total=float(row[best].sum())
 for group in mesh.vertex_groups:group.remove([vertex.index])
 for i in best:
  if row[i]>1e-6:mesh.vertex_groups[int(i)].add([vertex.index],float(row[i]/total),'REPLACE')
sys.path.insert(0,str(Path(__file__).resolve().parent))
from arm_seams import separate_arm_seams
report['arm_seams']=[] # regular sleeve reconstruction follows instead of ragged caps
bpy.ops.wm.save_as_mainfile(filepath=str(path))
for track in rig.animation_data.nla_tracks:track.mute=False
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
output=base/'godot/assets'/f'{who}_proxy.glb';bpy.ops.export_scene.gltf(filepath=str(output),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_bake_animation=True,export_extras=True)
sys.path.insert(0,str(ROOT/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import match_durations
match_durations(ROOT/f'art/models/archive/characters_before_apose_20261004/CH_{who}.glb',output)
(ROOT/f'evidence/character_roster_apose_20261004/{who}-weight-repair.json').write_text(json.dumps(report,indent=2));print('GARMENT_WEIGHT_REPAIR',report,flush=True)

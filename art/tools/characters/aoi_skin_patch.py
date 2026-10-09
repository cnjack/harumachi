"""Correct only the actual skin rim of Aoi's sleeves; preserve the fitted cloth and fingers."""
import bpy,sys,numpy as np
from pathlib import Path
from mathutils import Matrix
root=Path(__file__).resolve().parents[3];base=root/'art/models/character_roster_apose_20261004';bpy.ops.wm.open_mainfile(filepath=str(base/'binding_v2/authoring/aoi_proxy.blend'));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
rig.animation_data.action=None
for t in rig.animation_data.nla_tracks:t.mute=True
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
H=max(v.co.z for v in mesh.data.vertices);image=next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image);pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4));colours=np.zeros((len(mesh.data.vertices),3));counts=np.zeros(len(mesh.data.vertices))
for lp in mesh.data.loops:
 uv=mesh.data.uv_layers.active.data[lp.index].uv;colours[lp.vertex_index]+=pixels[int(uv.y*image.size[1])%image.size[1],int(uv.x*image.size[0])%image.size[0],:3];counts[lp.vertex_index]+=1
colours/=np.maximum(counts[:,None],1);changed=0
for v in mesh.data.vertices:
 r,g,b=colours[v.index]
 if not(r>g*1.08 and g>b*1.08):continue
 for side,sign in [('Left',1),('Right',-1)]:
  a=rig.data.bones['mixamorig:'+side+'Arm'].head_local;e=rig.data.bones['mixamorig:'+side+'ForeArm'].head_local;w=rig.data.bones['mixamorig:'+side+'Hand'].head_local;upper=e-a;fore=w-e
  if sign*v.co.x<sign*a.x+.015*H or sum(x.weight for x in v.groups if 'Hand' in mesh.vertex_groups[x.group].name)>.65:continue
  t=(v.co-a).dot(upper)/upper.length_squared;s=t*upper.length if t<=1 else upper.length+(v.co-e).dot(fore)/fore.length
  closest=a+upper*t if t<=1 else e+fore*((s-upper.length)/fore.length)
  if (v.co-closest).length>.09*H or s<.02*H:continue
  mix=max(0,min(1,(s-(upper.length-.025*H))/(.05*H)));u=max(0,min(1,(s-upper.length)/fore.length));u=u*u*(3-2*u)
  for group in mesh.vertex_groups:group.remove([v.index])
  for name,value in [('mixamorig:'+side+'Arm',1-mix),('mixamorig:'+side+'ForeArm',mix*(1-u)),('TWIST_'+side,mix*u)]:
   if value>1e-6:mesh.vertex_groups[name].add([v.index],value,'REPLACE')
  changed+=1;break
out=base/'final-binding';(out/'authoring').mkdir(exist_ok=True,parents=True);(out/'godot/assets').mkdir(exist_ok=True,parents=True);bpy.ops.wm.save_as_mainfile(filepath=str(out/'authoring/aoi_proxy.blend'))
for t in rig.animation_data.nla_tracks:t.mute=False
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig;export=out/'godot/assets/aoi_proxy.glb';bpy.ops.export_scene.gltf(filepath=str(export),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_bake_animation=True,export_extras=True)
sys.path.insert(0,str(root/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import match_durations;match_durations(root/'art/models/archive/characters_before_apose_20261004/CH_aoi.glb',export);print('AOI_SKIN_PATCH',changed)

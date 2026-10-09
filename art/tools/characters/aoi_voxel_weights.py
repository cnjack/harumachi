"""Use a watertight temporary volume for automatic weights; export only original Aoi exterior."""
import bpy,bmesh,sys,json,numpy as np
from pathlib import Path
from mathutils import Matrix,Vector,geometry
from mathutils.bvhtree import BVHTree
root=Path(__file__).resolve().parents[3];base=root/'art/models/character_roster_apose_20261004';bpy.ops.wm.open_mainfile(filepath=str(base/'binding/original_authoring/aoi_proxy.blend'));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');original=next(o for o in bpy.context.scene.objects if o.type=='MESH')
rig.animation_data.action=None
for t in rig.animation_data.nla_tracks:t.mute=True
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
original_weights={v.index:{original.vertex_groups[g.group].name:g.weight for g in v.groups} for v in original.data.vertices};proxy=original.copy();proxy.data=original.data.copy();bpy.context.collection.objects.link(proxy);proxy.name='TemporaryVolume'
for m in list(proxy.modifiers):proxy.modifiers.remove(m)
proxy.vertex_groups.clear();proxy.parent=None;H=max(v.co.z for v in original.data.vertices)
bpy.ops.object.select_all(action='DESELECT');proxy.select_set(True);bpy.context.view_layer.objects.active=proxy
remesh=proxy.modifiers.new('Watertight volume','REMESH');remesh.mode='VOXEL';remesh.voxel_size=.004*H;remesh.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier=remesh.name)
for bone in rig.data.bones:bone.use_deform=bone.name in ['mixamorig:LeftArm','mixamorig:LeftForeArm','mixamorig:RightArm','mixamorig:RightForeArm']
print('VOXEL_BOUNDS',list(proxy.dimensions),list(proxy.matrix_world.translation),flush=True)
for name in ['mixamorig:LeftArm','mixamorig:LeftForeArm','mixamorig:RightArm','mixamorig:RightForeArm']:print(name,list(rig.data.bones[name].head_local),list(rig.data.bones[name].tail_local),flush=True)
rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.parent_set(type='ARMATURE_AUTO')
if sum(sum(g.weight for g in v.groups)<1e-5 for v in proxy.data.vertices)>len(proxy.data.vertices)*.01:raise RuntimeError('Voxel heat weights failed')
proxy.data.calc_loop_triangles();triangles=[tuple(t.vertices) for t in proxy.data.loop_triangles];points=[v.co.copy() for v in proxy.data.vertices];tree=BVHTree.FromPolygons(points,triangles,all_triangles=True);weights=[{proxy.vertex_groups[g.group].name:g.weight for g in v.groups} for v in proxy.data.vertices]
original.vertex_groups.clear();groups={n:original.vertex_groups.new(name=n) for n in [b.name for b in rig.data.bones]}
for v in original.data.vertices:
 original_arm_share=sum(w for n,w in original_weights[v.index].items() if n.endswith(('Arm','ForeArm')) or n.startswith('TWIST_'))
 if sum(w for n,w in original_weights[v.index].items() if 'Hand' in n)>.6 or original_arm_share<.35:result=original_weights[v.index]
 else:
  hit=tree.find_nearest(v.co);tri=triangles[hit[2]];bary=geometry.barycentric_transform(hit[0],*[points[i] for i in tri],Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1)));result={}
  for i,amount in zip(tri,bary):
   for n,w in weights[i].items():result[n]=result.get(n,0)+w*max(0,amount)
 best=sorted(result.items(),key=lambda x:x[1],reverse=True)[:4];total=sum(w for n,w in best)
 for n,w in best:
  if w>1e-6:groups[n].add([v.index],w/total,'REPLACE')
for bone in rig.data.bones:bone.use_deform=True
bpy.data.objects.remove(proxy,do_unlink=True);out=base/'heat';(out/'authoring').mkdir(exist_ok=True,parents=True);(out/'godot/assets').mkdir(exist_ok=True,parents=True);bpy.ops.wm.save_as_mainfile(filepath=str(out/'authoring/aoi_proxy.blend'))
for t in rig.animation_data.nla_tracks:t.mute=False
bpy.ops.object.select_all(action='DESELECT');original.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.export_scene.gltf(filepath=str(out/'godot/assets/aoi_proxy.glb'),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_bake_animation=True,export_extras=True)
sys.path.insert(0,str(root/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import match_durations;match_durations(root/'art/models/archive/characters_before_apose_20261004/CH_aoi.glb',out/'godot/assets/aoi_proxy.glb');print('AOI_VOXEL_WEIGHT_TRANSFER_COMPLETE',len(original.data.vertices))

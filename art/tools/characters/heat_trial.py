"""Alternate offline automatic weights on the same generated exterior and fitted skeleton."""
import bpy,bmesh,sys,json
from pathlib import Path
from mathutils import Matrix
root=Path(__file__).resolve().parents[3];arguments=sys.argv[sys.argv.index('--')+1:];who=arguments[0];base=root/'art/models/character_roster_apose_20261004';source=Path(arguments[arguments.index('--source')+1]) if '--source' in arguments else base/f'binding_v2/authoring/{who}_proxy.blend' if who=='aoi' else base/f'binding/original_authoring/{who}_proxy.blend';bpy.ops.wm.open_mainfile(filepath=str(source));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
rig.animation_data.action=None
for t in rig.animation_data.nla_tracks:t.mute=True
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
for m in list(mesh.modifiers):mesh.modifiers.remove(m)
bm=bmesh.new();bm.from_mesh(mesh.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6);bm.to_mesh(mesh.data);bm.free();mesh.data.update()
old_weights={v.index:{mesh.vertex_groups[g.group].name:g.weight for g in v.groups} for v in mesh.data.vertices};mesh.vertex_groups.clear()
for bone in rig.data.bones:
 if bone.name.startswith('TWIST_') or 'Hand' in bone.name or 'Toe' in bone.name or 'Shoulder' in bone.name:bone.use_deform=False
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.parent_set(type='ARMATURE_AUTO')
bad=sum(sum(g.weight for g in v.groups)<1e-5 for v in mesh.data.vertices)
if bad>len(mesh.data.vertices)*.01:raise RuntimeError('Heat left unweighted vertices '+str(bad))
for v in mesh.data.vertices:
 if sum(g.weight for g in v.groups)<1e-5:
  for n,w in old_weights[v.index].items():group=mesh.vertex_groups.get(n) or mesh.vertex_groups.new(name=n);group.add([v.index],w,'REPLACE')
for bone in rig.data.bones:bone.use_deform=True
for v in mesh.data.vertices:
 old=old_weights[v.index];finger=sum(w for n,w in old.items() if 'Hand' in n)
 if finger>.6:
  for g in mesh.vertex_groups:g.remove([v.index])
  for n,w in old.items():group=mesh.vertex_groups.get(n) or mesh.vertex_groups.new(name=n);group.add([v.index],w,'REPLACE')
for v in mesh.data.vertices:
 values=sorted([(g.group,g.weight) for g in v.groups if g.weight>1e-6],key=lambda x:x[1],reverse=True)[:4];total=sum(w for i,w in values)
 for g in mesh.vertex_groups:g.remove([v.index])
 for i,w in values:mesh.vertex_groups[i].add([v.index],w/total,'REPLACE')
out=Path(arguments[arguments.index('--destination')+1]) if '--destination' in arguments else base/'heat';(out/'authoring').mkdir(exist_ok=True,parents=True);(out/'godot/assets').mkdir(exist_ok=True,parents=True);bpy.ops.wm.save_as_mainfile(filepath=str(out/'authoring'/f'{who}_proxy.blend'))
for t in rig.animation_data.nla_tracks:t.mute=False
bpy.ops.export_scene.gltf(filepath=str(out/'godot/assets'/f'{who}_proxy.glb'),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_bake_animation=True,export_extras=True)
sys.path.insert(0,str(root/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import match_durations;match_durations(root/f'art/models/archive/characters_before_apose_20261004/CH_{who}.glb',out/'godot/assets'/f'{who}_proxy.glb');print('HEAT_TRIAL_EXPORTED',who)

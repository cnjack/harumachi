"""Restore an original face removed by duplicate-vertex welding, with its exact UVs."""
import bpy,bmesh,numpy as np,json,sys
from pathlib import Path
from mathutils import Matrix
root=Path(__file__).resolve().parents[3];base=root/'art/models/character_leads_apose_20261005';rows=json.loads((root/'evidence/character_leads_apose_20261005/mio-missing-source-faces.json').read_text())
for version in ['modular','spring']:
 path=base/f'clothing/authoring/mio_{version}.blend';bpy.ops.wm.open_mainfile(filepath=str(path));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');body=max((o for o in bpy.context.scene.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices));points=np.array([tuple(v.co) for v in body.data.vertices]);bm=bmesh.new();bm.from_mesh(body.data);bm.verts.ensure_lookup_table();uv_layer=bm.loops.layers.uv.active
 for row in rows:
  vertices=[]
  for x,y,z,u,v in row:
   wanted=np.array([x,-z,y]);dist=np.linalg.norm(points-wanted,axis=1);index=int(np.argmin(dist));assert dist[index]<1e-5;vertices.append(bm.verts[index])
  # Welding may merge two source faces with separate UVs. Keep separate
  # coincident vertices for the restored source corner data.
  original_vertices=vertices;vertices=[]
  deform=bm.verts.layers.deform.active
  for original in original_vertices:
   duplicate=bm.verts.new(original.co.copy())
   if deform:
    for group,weight in original[deform].items():duplicate[deform][group]=weight
   for layer in bm.verts.layers.shape.values():duplicate[layer]=original[layer].copy()
   vertices.append(duplicate)
  face=bm.faces.new(vertices);face.material_index=0;face.smooth=True
  for loop,corner in zip(face.loops,row):loop[uv_layer].uv=(corner[3],1-corner[4])
 bm.to_mesh(body.data);bm.free();body.data.update()
 rig.animation_data.action=None
 for track in rig.animation_data.nla_tracks:track.mute=True
 for bone in rig.pose.bones:bone.matrix_basis=Matrix.Identity(4)
 for obj in bpy.context.scene.objects:
  if obj.type=='MESH' and obj.data.shape_keys:
   obj.data.shape_keys.animation_data.action=None
   for track in obj.data.shape_keys.animation_data.nla_tracks:track.mute=True
   for key in obj.data.shape_keys.key_blocks:key.value=0
 bpy.ops.wm.save_as_mainfile(filepath=str(path))
 for track in rig.animation_data.nla_tracks:track.mute=False
 for obj in bpy.context.scene.objects:
  if obj.type=='MESH' and obj.data.shape_keys:
   for track in obj.data.shape_keys.animation_data.nla_tracks:track.mute=False
 bpy.ops.object.select_all(action='DESELECT')
 for obj in bpy.context.scene.objects:
  if obj.type in ['MESH','ARMATURE']:obj.select_set(True)
 bpy.context.view_layer.objects.active=rig;target=base/f'clothing/godot/assets/mio_{version}.glb'
 bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_merge_animation='NLA_TRACK',export_bake_animation=True,export_morph=True,export_morph_animation=True,export_extras=True,export_vertex_color='ACTIVE',export_influence_nb=8 if version=='spring' else 4)
 sys.path.insert(0,str(root/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import match_durations;match_durations(root/'art/models/archive/characters_before_apose_20261004/CH_mio.glb',target);print('RESTORED_SOURCE_FACE',version,len(rows))

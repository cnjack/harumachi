"""Make editable Blender downloads open at their reference pose, with all clips retained."""
import bpy,json
from pathlib import Path
from mathutils import Matrix
root=Path(__file__).resolve().parents[3];manifest=json.loads((root/'art/manifests/character_roster_20261004.json').read_text());out=root/'art/library/characters/authoring';out.mkdir(exist_ok=True)
for person in manifest['characters']:
 bpy.ops.wm.open_mainfile(filepath=str(root/person['authoring_path']))
 for obj in bpy.context.scene.objects:
  if obj.type=='ARMATURE':
   if obj.animation_data:
    obj.animation_data.action=None
    for track in obj.animation_data.nla_tracks:track.mute=True
   for bone in obj.pose.bones:bone.matrix_basis=Matrix.Identity(4)
  if obj.type=='MESH' and obj.data.shape_keys:
   keys=obj.data.shape_keys
   if keys.animation_data:
    keys.animation_data.action=None
    for track in keys.animation_data.nla_tracks:track.mute=True
   for key in keys.key_blocks:key.value=0
 bpy.context.scene.frame_set(1);bpy.context.view_layer.update()
 target=out/(person['id']+'.blend');bpy.ops.wm.save_as_mainfile(filepath=str(target),compress=True)
 print('AUTHORING_LIBRARY',person['id'],flush=True)

"""Rejected experiment: this trouser deletion exposes gaps during motion.

Not used by the current game or character library. Keep only to reproduce the
failed candidate; the approved pipeline uses kazuko_apron_clearance.py.
"""
import bpy,bmesh,sys,numpy as np,json
from pathlib import Path
from mathutils import Vector,Matrix
root=Path(__file__).resolve().parents[3];base=root/'art/models/character_roster_apose_20261004';path=base/'final-binding/authoring/kazuko_proxy.blend';bpy.ops.wm.open_mainfile(filepath=str(path));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH');H=max(v.co.z for v in mesh.data.vertices)
image=next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image);pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4));remove=[]
for f in mesh.data.polygons:
 p=sum((mesh.data.vertices[i].co for i in f.vertices),Vector())/len(f.vertices);uv=sum((mesh.data.uv_layers.active.data[i].uv for i in f.loop_indices),Vector((0,0)))/len(f.loop_indices);r,g,b=pixels[int(uv.y*image.size[1])%image.size[1],int(uv.x*image.size[0])%image.size[0],:3]
 if .255*H<p.z<.55*H and abs(p.x)<.135*H and p.y<rig.data.bones['mixamorig:Hips'].head_local.y and max(r,g,b)<.36 and max(r,g,b)-min(r,g,b)<.16:remove.append(f.index)
coverage=[]
for index in remove:
 f=mesh.data.polygons[index];corners=[]
 for loop_index in f.loop_indices:
  loop=mesh.data.loops[loop_index];p=mesh.data.vertices[loop.vertex_index].co;uv=mesh.data.uv_layers.active.data[loop_index].uv
  corners.append([p.x,p.z,-p.y,uv.x,1-uv.y])
 coverage.append(corners)
(base/'kazuko_covered_body_mask.json').write_text(json.dumps({'character':'kazuko','purpose':'Covered front trouser faces behind the fixed apron; original authoring source remains intact','source':str(path.relative_to(root)),'removed_triangles':len(remove),'corners_position_uv':coverage},indent=2))
if '--audit-only' in sys.argv:
 print('APRON_COVERAGE_AUDIT_ONLY',len(remove));sys.exit(0)
if '--reproduce-rejected' not in sys.argv:raise RuntimeError('Rejected body mask: use --audit-only, or --reproduce-rejected for the archived experiment')
bm=bmesh.new();bm.from_mesh(mesh.data);bm.faces.ensure_lookup_table();bmesh.ops.delete(bm,geom=[bm.faces[i] for i in remove],context='FACES');bm.to_mesh(mesh.data);bm.free()
bpy.ops.wm.save_as_mainfile(filepath=str(base/'final-binding/authoring/kazuko_game.blend'))
for t in rig.animation_data.nla_tracks:t.mute=False
rig.animation_data.action=None;bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig;out=base/'final-binding/godot/assets/kazuko_proxy.glb';bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_bake_animation=True,export_extras=True)
sys.path.insert(0,str(root/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import match_durations;match_durations(root/'art/models/archive/characters_before_apose_20261004/CH_kazuko.glb',out);print('APRON_COVERAGE_BODY_MASK',len(remove))

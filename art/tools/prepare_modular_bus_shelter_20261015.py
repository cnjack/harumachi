"""Remove only the measured disconnected old sign pole; keep the shelter and its UVs."""
from pathlib import Path
import bpy,bmesh,json,hashlib
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'art/models/raw/modular_props_20261015/ready'
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(ROOT/'art/library/modular_props_20261015/source/R06.glb'))
OUT.mkdir(parents=True,exist_ok=True)
removed=0
for o in [x for x in bpy.context.scene.objects if x.type=='MESH']:
 bm=bmesh.new();bm.from_mesh(o.data);old=[v for v in bm.verts if (o.matrix_world@v.co).x>1.60]
 removed+=len(old);bmesh.ops.delete(bm,geom=old,context='VERTS');bm.to_mesh(o.data);bm.free()
assert removed>300,'Measured separate old pole must exist; do not cut other geometry'
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'R06.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'R06.glb'),export_format='GLB',export_yup=True,export_apply=True,export_image_format='AUTO',export_animations=False)
(OUT/'R06.preparation.json').write_text(json.dumps({'removed_vertices':removed,'removed_component_bounds_godot':{'min':[1.6623,.0045,-.3523],'max':[2.2221,2.5713,.0699]},'retained_shelter_max_x':1.5275,'source_geometry':'existing Hunyuan R06 shelter','atlas_repainted':False},indent=2)+'\n')

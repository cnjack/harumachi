"""Fit selected CC0 models and split material roles, preserving original UVs and alpha."""
import bpy,json,sys
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[2]
SPEC=json.loads((ROOT/'art/library/integration.json').read_text())
RAW=ROOT/'art/models/raw/free_foliage_20261004'
OUT=RAW/'ready';OUT.mkdir(exist_ok=True)
selected=set(sys.argv[sys.argv.index('--')+1:]) if '--' in sys.argv else set(SPEC['assets'])
for aid,entry in SPEC['assets'].items():
 if aid not in selected:continue
 bpy.ops.wm.read_factory_settings(use_empty=True)
 path=RAW/'quaternius_standard/unpacked/glTF'/(entry['source']+'.gltf')
 bpy.ops.import_scene.gltf(filepath=str(path));meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
 bpy.ops.object.select_all(action='DESELECT')
 for ob in meshes:
  world=ob.matrix_world.copy();ob.parent=None;ob.matrix_world=world;ob.select_set(True)
 bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();ob=bpy.context.object
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 points=[v.co for v in ob.data.vertices];lo=Vector([min(p[a] for p in points) for a in range(3)]);hi=Vector([max(p[a] for p in points) for a in range(3)])
 factor=float(entry['height'])/(hi.z-lo.z)
 ob.data.transform(Matrix.Translation(Vector((-(lo.x+hi.x)/2,-(lo.y+hi.y)/2,-lo.z))));ob.data.transform(Matrix.Scale(factor,4))
 for mat in ob.data.materials:
  if not mat.use_nodes:continue
  bs=mat.node_tree.nodes.get('Principled BSDF')
  if not bs:continue
  for key in ['Normal','Metallic','Roughness']:
   for link in list(bs.inputs[key].links):mat.node_tree.links.remove(link)
  bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0
 bpy.context.view_layer.objects.active=ob;bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.separate(type='MATERIAL');bpy.ops.object.mode_set(mode='OBJECT')
 counters={}
 for mesh in [o for o in bpy.context.scene.objects if o.type=='MESH']:
  material_name=' '.join(m.name for m in mesh.data.materials).lower()
  role='Trunk' if 'bark' in material_name else 'Foliage'
  counters[role]=counters.get(role,0)+1;mesh.name=role+'_'+str(counters[role])
 bpy.ops.export_scene.gltf(filepath=str(OUT/(aid+'.glb')),export_format='GLB',export_image_format='AUTO',export_yup=True,export_animations=False)
 print('READY',aid,entry['source'],entry['height'],counters,flush=True)

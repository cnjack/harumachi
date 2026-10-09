"""Render actual free-pack examples without changing any source file."""
import bpy,math,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
PACK=ROOT/'art/models/raw/free_foliage_20261004'
OUT=ROOT/'evidence/free_foliage_20261004';OUT.mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
examples=[('CommonTree_1','quaternius_standard/unpacked/glTF/CommonTree_1.gltf',6.0),('CommonTree_4','quaternius_standard/unpacked/glTF/CommonTree_4.gltf',6.0),('Pine_3','quaternius_standard/unpacked/glTF/Pine_3.gltf',6.0),('Bush_Common','quaternius_standard/unpacked/glTF/Bush_Common.gltf',1.7),('Plant_7','quaternius_standard/unpacked/glTF/Plant_7.gltf',.45),('Grass_Wispy_Tall','quaternius_standard/unpacked/glTF/Grass_Wispy_Tall.gltf',1.0),('Flower_3_Group','quaternius_standard/unpacked/glTF/Flower_3_Group.gltf',1.2),('Grass_Common_Short','quaternius_standard/unpacked/glTF/Grass_Common_Short.gltf',.6)]
report=[]
for index,(name,path,height) in enumerate(examples):
 bpy.ops.object.select_all(action='DESELECT');before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(PACK/path));new=[o for o in bpy.context.scene.objects if o not in before];meshes=[o for o in new if o.type=='MESH']
 pts=[o.matrix_world@v.co for o in meshes for v in o.data.vertices];lo=Vector([min(p[a] for p in pts) for a in range(3)]);hi=Vector([max(p[a] for p in pts) for a in range(3)])
 triangles=sum(sum(len(poly.vertices)-2 for poly in ob.data.polygons) for ob in meshes)
 bpy.ops.object.select_all(action='DESELECT')
 for ob in meshes:
  world_matrix=ob.matrix_world.copy();ob.parent=None;ob.matrix_world=world_matrix;ob.select_set(True)
 bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();parent=bpy.context.object
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 scale=height/(hi.z-lo.z);parent.scale=(scale,scale,scale)
 row_y=7.0 if index<4 else 0.0
 parent.location=Vector((index%4*8.0,row_y,0))-Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))*scale
 bpy.context.view_layer.update()
 report.append({'name':name,'source':path,'triangles':triangles,'native_blender_size':[round(v,3) for v in hi-lo],'preview_height':height})
 text=bpy.data.curves.new(name+'Label','FONT');text.body=name;text.align_x='CENTER';text.size=.34
 label=bpy.data.objects.new(name+'Label',text);bpy.context.collection.objects.link(label);label.location=(index%4*8.0,row_y-1.5,.06);label.rotation_euler=(0,0,0)
for mat in bpy.data.materials:
 if mat.use_nodes:
  bs=mat.node_tree.nodes.get('Principled BSDF')
  if bs:bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0
bpy.ops.mesh.primitive_plane_add(size=200,location=(10,4,-.05));floor=bpy.context.object
mat=bpy.data.materials.new('NeutralGround');mat.diffuse_color=(.83,.83,.76,1);floor.data.materials.append(mat)
sc=bpy.context.scene;world=bpy.data.worlds.new('Day');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.55,.66,.80,1);world.node_tree.nodes['Background'].inputs[1].default_value=.75;sc.world=world
sun=bpy.data.objects.new('Sun',bpy.data.lights.new('Sun','SUN'));sc.collection.objects.link(sun);sun.data.energy=1.5;sun.rotation_euler=(.65,-.3,-.6)
cam=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera'));sc.collection.objects.link(cam);cam.data.type='ORTHO';cam.data.ortho_scale=30;cam.location=(12,-22,24);focus=Vector((12,3.5,2.3));cam.rotation_euler=(focus-cam.location).to_track_quat('-Z','Y').to_euler();sc.camera=cam
sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x=1800;sc.render.resolution_y=1000;sc.render.resolution_percentage=100;sc.view_settings.view_transform='Standard';sc.view_settings.look='None';sc.render.filepath=str(OUT/'quaternius_examples.png');bpy.ops.render.render(write_still=True)
(OUT/'examples.json').write_text(json.dumps(report,indent=2)+'\n');print('RENDERED',len(report),'real model examples')

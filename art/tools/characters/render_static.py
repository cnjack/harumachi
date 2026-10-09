"""Four orthographic source views; inspect identity and armpit separation before binding."""
import bpy,sys,math,json
from pathlib import Path
from mathutils import Vector
src,out=sys.argv[sys.argv.index('--')+1:];out=Path(out);out.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=src)
points=[o.matrix_world@v.co for o in bpy.context.scene.objects if o.type=='MESH' for v in o.data.vertices];H=max(v.z for v in points)-min(v.z for v in points)
sc=bpy.context.scene;sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x=640;sc.render.resolution_y=800;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG';sc.world=bpy.data.worlds.new('World');sc.world.use_nodes=True;sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.70,.75,.82,1);sc.world.node_tree.nodes['Background'].inputs[1].default_value=.7
sc.view_settings.view_transform='Standard';sc.view_settings.look='None'
light=bpy.data.objects.new('Soft sun',bpy.data.lights.new('Soft sun','SUN'));bpy.context.collection.objects.link(light);light.rotation_euler=(math.radians(30),math.radians(-20),math.radians(-25));light.data.energy=1.3
cam=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera'));bpy.context.collection.objects.link(cam);cam.data.type='ORTHO';cam.data.ortho_scale=H*1.20;sc.camera=cam;target=Vector((0,0,H*.5))
for name,angle in [('front',0),('left',90),('back',180),('right',270)]:
 a=math.radians(angle);cam.location=(math.sin(a)*4,-math.cos(a)*4,H*.5);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
print('STATIC_CHARACTER_VIEWS',src,str(out),flush=True)

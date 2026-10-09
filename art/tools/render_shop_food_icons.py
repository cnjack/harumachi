"""Transparent icons from the actual 3D food meshes, stored in the common UI kit."""
import bpy
from mathutils import Vector
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'game/ui_kit/assets/shop_food';OUT.mkdir(parents=True,exist_ok=True)
ASSETS={'shop_donut':'B07_iced_donut','shop_cream_bun':'B11_cream_bun','shop_sushi':'B09_sushi_tray','shop_bento':'B10_bento_box'}
for icon,asset in ASSETS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'game/assets/models'/f'{asset}.glb'))
    points=[obj.matrix_world@vertex.co for obj in scene.objects if obj.type=='MESH' for vertex in obj.data.vertices]
    lo=Vector([min(point[i] for point in points) for i in range(3)]);hi=Vector([max(point[i] for point in points) for i in range(3)])
    center=(lo+hi)/2;size=hi-lo
    world=bpy.data.worlds.new('Soft_lavender');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.75,.79,.88,1);world.node_tree.nodes['Background'].inputs[1].default_value=.8;scene.world=world
    sun=bpy.data.objects.new('Warm_sun',bpy.data.lights.new('Warm_sun','SUN'));scene.collection.objects.link(sun);sun.data.energy=1.4;sun.rotation_euler=(.5,-.3,-.5)
    camera=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera'));scene.collection.objects.link(camera);scene.camera=camera
    camera.data.type='ORTHO';camera.data.ortho_scale=max(size)*1.4;camera.location=center+Vector((.5,-1.4,1.05)).normalized()*size.length*2
    camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=512;scene.render.resolution_y=512;scene.render.resolution_percentage=100
    scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
    scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.render.filepath=str(OUT/(icon+'.png'))
    bpy.ops.render.render(write_still=True)
print('RENDERED_SHOP_ICONS',list(ASSETS))

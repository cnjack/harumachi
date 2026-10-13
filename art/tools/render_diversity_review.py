"""Render actual source/game meshes, four sides plus colour/clay oblique views.

Blender -b --factory-startup -P art/tools/render_diversity_review.py -- GLB OUT HEIGHT
Preview only: uniformly normalizes height, never edits or exports the source mesh.
"""
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Matrix,Vector

source,output,height=sys.argv[sys.argv.index('--')+1:]
source=Path(source).resolve();output=Path(output).resolve();height=float(height)
output.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))
scene=bpy.context.scene
meshes=[ob for ob in scene.objects if ob.type=='MESH']
points=[ob.matrix_world@v.co for ob in meshes for v in ob.data.vertices]
low=Vector([min(p[k] for p in points) for k in range(3)])
high=Vector([max(p[k] for p in points) for k in range(3)])
original_size=high-low
scale=height/original_size.z
base=Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z))
for ob in meshes:
    matrix=ob.matrix_world.copy()
    for v in ob.data.vertices:v.co=(matrix@v.co-base)*scale
    ob.parent=None;ob.matrix_world=Matrix.Identity(4)
for ob in list(scene.objects):
    if ob.type not in ['MESH']:bpy.data.objects.remove(ob,do_unlink=True)

texture_sizes=[]
for mat in bpy.data.materials:
    if not mat.use_nodes:continue
    bs=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if not bs:continue
    for node in mat.node_tree.nodes:
        if node.type=='TEX_IMAGE' and node.image:
            texture_sizes.append(dict(name=node.image.name,size=list(node.image.size)))
    for name,value in [('Normal',None),('Metallic',0.),('Roughness',1.),('Specular IOR Level',0.)]:
        for link in list(bs.inputs[name].links):mat.node_tree.links.remove(link)
        if value is not None:bs.inputs[name].default_value=value
world=bpy.data.worlds.new('Review_neutral');world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.68,.73,.79,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.7
scene.world=world
sun=bpy.data.objects.new('Review_sun',bpy.data.lights.new('Review_sun','SUN'))
scene.collection.objects.link(sun);sun.data.energy=1.8;sun.rotation_euler=(.65,-.25,-.6)
camera=bpy.data.objects.new('Review_camera',bpy.data.cameras.new('Review_camera'))
scene.collection.objects.link(camera);scene.camera=camera;camera.data.type='ORTHO'
scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=896;scene.render.resolution_y=896
scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='Standard';scene.view_settings.look='None'
size=original_size*scale;centre=Vector((0,0,height/2))
if any(aid in str(source) for aid in ['C13_pumpkin','C14_watermelon']):
    bpy.ops.mesh.primitive_plane_add(size=max(size)*3,location=(0,0,-.001))
    floor=bpy.context.object;floor.name='Inspection_soil_contact_plane'
    floor_material=bpy.data.materials.new('Neutral_contact_floor');floor_material.diffuse_color=(.35,.39,.42,1)
    floor.data.materials.append(floor_material)
camera.data.ortho_scale=max(size)*1.28
clay=bpy.data.materials.new('Review_clay');clay.use_nodes=True
bs=clay.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(.57,.61,.69,1)
bs.inputs['Roughness'].default_value=1.;bs.inputs['Specular IOR Level'].default_value=0.
backup={ob.name:list(ob.data.materials) for ob in meshes}
material_indices={ob.name:[poly.material_index for poly in ob.data.polygons] for ob in meshes}
clay_slots={}
for ob in meshes:
    slots=[]
    for material in backup[ob.name]:
        bs=next((n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None) if material and material.use_nodes else None
        if bs and bs.inputs['Alpha'].is_linked:
            masked=material.copy();masked.name='Clay_with_original_leaf_cutout'
            masked_bs=next(n for n in masked.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
            for link in list(masked_bs.inputs['Base Color'].links):masked.node_tree.links.remove(link)
            masked_bs.inputs['Base Color'].default_value=(.67,.70,.73,1)
            slots.append(masked)
        else:slots.append(clay)
    clay_slots[ob.name]=slots
views=[('front',(0,-1,.16)),('back',(0,1,.16)),('left',(-1,0,.16)),('right',(1,0,.16)),
       ('oblique',(1,-1,.55)),('clay_front',(0,-1,.16)),('clay_oblique',(1,-1,.55))]
for name,direction in views:
    for ob in meshes:
        ob.data.materials.clear()
        for material in (clay_slots[ob.name] if name.startswith('clay') else backup[ob.name]):ob.data.materials.append(material)
        # Clearing material slots resets polygon indices in Blender. Restore
        # them for colour views; otherwise joined timber inherits produce UVs.
        for poly,index in zip(ob.data.polygons,material_indices[ob.name]):
            poly.material_index=index
    camera.location=centre+Vector(direction).normalized()*size.length*2.2
    camera.rotation_euler=(centre-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(output/(name+'.png'));bpy.ops.render.render(write_still=True)
report=dict(source=str(source),sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
            raw_dimensions_blender=list(original_size),preview_dimensions_godot=[size.x,size.z,size.y],
            normalization='uniform scale for inspection only; no source mutation',
            meshes=len(meshes),triangles=sum(len(poly.vertices)-2 for ob in meshes for poly in ob.data.polygons),
            textures=texture_sizes,views=[v[0]+'.png' for v in views])
(output/'review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('REVIEW_RENDER',json.dumps(report),flush=True)

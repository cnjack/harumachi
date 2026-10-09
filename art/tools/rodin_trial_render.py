"""Render unmodified provider geometry with uniform human-scale normalization.

Blender -b --factory-startup -P ... -- RAW_GLB OUT HEIGHT_M
Colour plus clay closeups distinguish painted texture from actual geometry.
Never overwrites a game asset or stretches the mesh to a different aspect ratio.
"""
import bpy,json,math,sys,hashlib
from pathlib import Path
from mathutils import Vector
source,out,height=sys.argv[sys.argv.index('--')+1:];source=Path(source).resolve();out=Path(out).resolve();height=float(height);out.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True);sc=bpy.context.scene
bpy.ops.import_scene.gltf(filepath=str(source))
objects=[o for o in sc.objects if o.type=='MESH'];points=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
lo=Vector([min(v[i] for v in points) for i in range(3)]);hi=Vector([max(v[i] for v in points) for i in range(3)])
original_size=hi-lo;scale=height/original_size.z;base=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
for ob in objects:
    matrix=ob.matrix_world.copy()
    for v in ob.data.vertices:v.co=(matrix@v.co-base)*scale
    ob.parent=None;ob.matrix_world.identity()
for material in bpy.data.materials:
    if not material.use_nodes:continue
    bs=next((n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if not bs:continue
    for name,value in [('Normal',None),('Metallic',0.),('Roughness',1.),('Specular IOR Level',0.)]:
        for link in list(bs.inputs[name].links):material.node_tree.links.remove(link)
        if value is not None:bs.inputs[name].default_value=value
world=bpy.data.worlds.new('Neutral');world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.63,.70,.82,1);world.node_tree.nodes['Background'].inputs[1].default_value=.65;sc.world=world
light=bpy.data.objects.new('Sun',bpy.data.lights.new('Sun','SUN'));sc.collection.objects.link(light);light.data.energy=1.6;light.rotation_euler=(.65,-.25,-.6)
camera=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera'));sc.collection.objects.link(camera);sc.camera=camera;camera.data.type='ORTHO'
sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x=1440;sc.render.resolution_y=1080;sc.render.resolution_percentage=100;sc.view_settings.view_transform='Standard';sc.view_settings.look='None'
size=original_size*scale;centre=Vector((0,0,height/2));whole_scale=max(size.x,size.y,height)*1.60
for name,direction in [('front',Vector((1,-1.6,.55))),('back',Vector((-1,1.6,.55))),('left',Vector((-1.6,-1,.55))),('right',Vector((1.6,1,.55)))]:
    camera.data.ortho_scale=whole_scale;camera.location=centre+direction.normalized()*size.length*1.6
    camera.rotation_euler=(centre-camera.location).to_track_quat('-Z','Y').to_euler();sc.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
clay=bpy.data.materials.new('Diagnostic_clay');clay.use_nodes=True;bs=clay.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(.55,.59,.67,1);bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0
backups={o.name:list(o.data.materials) for o in objects}
for name,focus,offset,viewsize in [
    ('front_joinery',Vector((0,-size.y/2+.25,1.35)),Vector((.75,-3.1,.34)),3.4),
    ('front_eaves',Vector((0,-size.y/2+.35,min(height-.55,2.85))),Vector((.5,-3.0,.35)),3.8)]:
    camera.data.ortho_scale=viewsize;camera.location=focus+offset;camera.rotation_euler=(focus-camera.location).to_track_quat('-Z','Y').to_euler()
    for mode in ['albedo','clay']:
        for ob in objects:
            ob.data.materials.clear()
            for material in backups[ob.name] if mode=='albedo' else [clay]:ob.data.materials.append(material)
        sc.render.filepath=str(out/f'{name}_{mode}.png');bpy.ops.render.render(write_still=True)
    for ob in objects:
        ob.data.materials.clear()
        for material in backups[ob.name]:ob.data.materials.append(material)
report={'source':str(source),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'original_size_blender':list(original_size),'preview_size_godot':[size.x,size.z,size.y],'uniform_scale':scale,'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),'stage':'provider source, matte preview; no reduction, remeshing, nonuniform fit or game replacement','views':sorted(p.name for p in out.glob('*.png'))}
(out/'render.json').write_text(json.dumps(report,indent=2)+'\n');print('TRIAL_RENDER',json.dumps(report),flush=True)

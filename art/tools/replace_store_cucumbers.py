"""Replace the old simplified cucumber discs with independent Pixal crate meshes."""
import bpy,json,sys,math,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/models/raw/window_cavities_20261003'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'S01.blend'))
removed=[]
for ob in list(bpy.context.scene.objects):
    if 'produce_cucumber' in ob.name:
        removed.append(ob.name);bpy.data.objects.remove(ob,do_unlink=True)
support=bpy.data.objects.get('cedar__display')
if support is None:raise RuntimeError('No reviewed exterior display support')
points=[support.matrix_world@v.co for v in support.data.vertices];faces=[list(p.vertices) for p in support.data.polygons]
tree=BVHTree.FromPolygons(points,faces)
samples=[]
for z in [3.14,3.57]:
    hit,_,_,_=tree.ray_cast(Vector((-.78,-z,2.0)),Vector((0,0,-1)),2.0)
    if hit is None:raise RuntimeError('No measured produce shelf top')
    samples.append((z,hit.z))
angle=math.atan2(samples[0][1]-samples[1][1],samples[1][0]-samples[0][0])
rotation=Matrix.Rotation(angle,3,'X')
source=ROOT/'game/assets/models/W03_cucumber_crate.glb'
for index,x in enumerate([-1.105,-.455]):
    before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(source))
    parts=[o for o in bpy.context.scene.objects if o not in before and o.type=='MESH']
    for ob in parts:
        mw=ob.matrix_world.copy()
        # Godot +Z forward corresponds to Blender -Y; pitch around X is the same.
        for v in ob.data.vertices:v.co=rotation@(mw@v.co)
        ob.parent=None;ob.matrix_world.identity();ob.name='Pixal_whole_cucumbers_%d__display'%index
        centre_z=3.35
        hit,_,_,_=tree.ray_cast(Vector((x,-centre_z,2)),Vector((0,0,-1)),2)
        base=hit.z if hit else sum(p[1] for p in samples)*.5
        for v in ob.data.vertices:v.co+=Vector((x,-centre_z,base+.014))
        for material in ob.data.materials:
            material.name='produce_cucumber_pixal__display'
            bs=material.node_tree.nodes.get('Principled BSDF')
            bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0
for image in bpy.data.images:
    if image.size[0]>0:image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'S01_cucumbers.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'S01.glb'),export_format='GLB',export_yup=True,export_apply=True,export_image_format='JPEG',export_jpeg_quality=96)
report={'removed_nodes':removed,'provider':'Pixal3D independent cucumber crates','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'support_samples':samples,'pitch_degrees':math.degrees(angle),'crate_centres_x':[-1.105,-.455]}
(OUT/'S01_cucumbers.json').write_text(json.dumps(report,indent=2)+'\n');print('CUCUMBERS',report)

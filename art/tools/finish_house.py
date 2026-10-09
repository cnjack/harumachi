"""Finish measured H03 architecture after Rodin export: human-scale shoji and lattice.

Blender -b --factory-startup -P art/tools/finish_house.py -- input.glb output.glb
Works in Blender coordinates. Keeps the original footprint and ridge height.
"""
import bpy
import json
import sys
from pathlib import Path

source, output = sys.argv[sys.argv.index('--')+1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(Path(source).resolve()))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
ob=meshes[0]
bpy.context.view_layer.objects.active=ob
ob.select_set(True)
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
ridge=max(v.co.z for v in ob.data.vertices)
anchors=[(0.,0.),(.96,.45),(2.46,2.7),(3.04,3.3),(ridge,ridge)]

def height(value):
    for (a,b),(c,d) in zip(anchors,anchors[1:]):
        if value<=c:return b+(value-a)/(c-a)*(d-b)
    return value

for v in ob.data.vertices:v.co.z=height(v.co.z)

mat=bpy.data.materials.new('Shoji_Lattice');mat.use_nodes=True
shader=mat.node_tree.nodes.get('Principled BSDF')
shader.inputs['Base Color'].default_value=(.48,.30,.15,1.)
shader.inputs['Roughness'].default_value=1.
shader.inputs['Metallic'].default_value=0.
shader.inputs['Specular IOR Level'].default_value=0.
pieces=[]

def bar(name,centre,size):
    bpy.ops.mesh.primitive_cube_add(size=1,location=centre)
    p=bpy.context.object;p.name=name;p.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    p.data.materials.append(mat);pieces.append(p)

# Measured white paper lies at Godot z=1.63..1.75. The lattice is in front
# of the paper while the existing solid timber frames still stand proud.
panes=[(-1.78,-1.10),(-.85,-.14),(.15,.96),(1.20,1.98)]
for n,(left,right) in enumerate(panes):
    for row in range(1,7):
        z=.62+row*(1.77/7)
        bar('Shoji_%d_row_%d'%(n,row),((left+right)/2,-1.78,z),(right-left,.014,.016))
    bar('Shoji_%d_centre'%n,((left+right)/2,-1.78,1.505),(.014,.014,1.77))

bpy.ops.object.select_all(action='DESELECT');ob.select_set(True)
for p in pieces:p.select_set(True)
bpy.context.view_layer.objects.active=ob;bpy.ops.object.join()
bpy.ops.object.shade_smooth_by_angle(angle=.61)
ob.name='H03'
Path(output).parent.mkdir(parents=True,exist_ok=True)
for img in bpy.data.images:
    if img.size[0]>0:img.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(Path(output).with_suffix('.blend').resolve()))
bpy.ops.export_scene.gltf(filepath=str(Path(output).resolve()),export_format='GLB',use_selection=True,
                          export_yup=True,export_apply=True,export_image_format='JPEG',export_jpeg_quality=92,
                          export_animations=False,export_extras=False)
Path(output).with_name('finish.json').write_text(json.dumps({'source':source,'height_remap':anchors,
    'paper_bounds_before_y_m':[1.04088569,2.3211329],
    'paper_bounds_after_y_m':[height(1.04088569),height(2.3211329)],'lattice_bars':len(pieces),
    'footprint_and_ridge_unchanged':True},indent=2))

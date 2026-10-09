"""Fit a generated visual mesh to a landmark's existing physical bounds.

Blender -b --factory-startup -P art/tools/normalize_landmark.py -- ID SOURCE BOUNDS OUTPUT
No replacement geometry is created. The original high mesh remains untouched.
"""
import bpy
import json
import sys
from pathlib import Path
from mathutils import Vector

aid, source, bounds, output = sys.argv[sys.argv.index('--') + 1:]
spec = json.loads(Path(bounds).read_text())[aid]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(Path(source).resolve()))
objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
for obj in objects:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
points = [obj.matrix_world @ vertex.co for obj in objects for vertex in obj.data.vertices]
low = Vector([min(p[k] for p in points) for k in range(3)])
high = Vector([max(p[k] for p in points) for k in range(3)])
target_low = Vector(spec['blender_min'])
target_size = Vector(spec['blender_size'])
size = high - low
for obj in objects:
    for vertex in obj.data.vertices:
        world = obj.matrix_world @ vertex.co
        vertex.co = Vector([target_low[k] + (world[k]-low[k])/size[k]*target_size[k] for k in range(3)])
    obj.matrix_world.identity()
destination = Path(output).resolve()
destination.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(destination.with_suffix('.blend')))
bpy.ops.export_scene.gltf(filepath=str(destination), export_format='GLB', export_yup=True,
                          export_apply=True, export_animations=False)
report = {'id':aid, 'source':source, 'source_size_blender':list(size),
          'target_size_blender':list(target_size), 'target_min_blender':list(target_low),
          'scale_xyz':[target_size[k]/size[k] for k in range(3)]}
destination.with_suffix('.fit.json').write_text(json.dumps(report,indent=2))
print('FIT', json.dumps(report))

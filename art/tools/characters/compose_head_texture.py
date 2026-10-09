"""Sora A-pose POC: bake a new head albedo with the approved body albedo.

Both textures must already use the original static mesh's UV layout. The
height transition is explicitly character-specific, not a generic segmenter.
This tool writes only a texture and an evidence report.
"""
import argparse
import json
from pathlib import Path
import sys
import bpy
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument('--original-static', type=Path, required=True)
parser.add_argument('--head-texture', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--report', type=Path, required=True)
parser.add_argument('--size', type=int, default=4096)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(args.original_static.resolve()))
mesh = next(obj for obj in bpy.context.scene.objects if obj.type == 'MESH')
original = next(node.image for node in mesh.data.materials[0].node_tree.nodes
                if node.type == 'TEX_IMAGE' and node.image)
head = bpy.data.images.load(str(args.head_texture.resolve()))
points = [mesh.matrix_world @ Vector(v.co) for v in mesh.data.vertices]
bottom = min(p.z for p in points)
height = max(p.z for p in points) - bottom
attribute = mesh.data.color_attributes.new(name='HeadAlbedoRegion', type='FLOAT_COLOR', domain='POINT')
for vertex, point in zip(mesh.data.vertices, points):
    factor = max(0., min(1., ((point.z - bottom) / height - .805) / .030))
    factor = factor * factor * (3. - 2. * factor)
    attribute.data[vertex.index].color = (factor, factor, factor, 1.)
material = bpy.data.materials.new('ApprovedBody_NewHead')
material.use_nodes = True
mesh.data.materials.clear()
mesh.data.materials.append(material)
nodes = material.node_tree.nodes
nodes.clear()
body_node = nodes.new('ShaderNodeTexImage')
body_node.image = original
head_node = nodes.new('ShaderNodeTexImage')
head_node.image = head
mask = nodes.new('ShaderNodeVertexColor')
mask.layer_name = attribute.name
mix = nodes.new('ShaderNodeMixRGB')
emission = nodes.new('ShaderNodeEmission')
output = nodes.new('ShaderNodeOutputMaterial')
links = material.node_tree.links
links.new(mask.outputs['Color'], mix.inputs[0])
links.new(body_node.outputs['Color'], mix.inputs[1])
links.new(head_node.outputs['Color'], mix.inputs[2])
links.new(mix.outputs[0], emission.inputs['Color'])
links.new(emission.outputs[0], output.inputs['Surface'])
baked = bpy.data.images.new('Head4K_ApprovedBody', width=args.size, height=args.size, alpha=False)
baked.colorspace_settings.name = 'sRGB'
bake_node = nodes.new('ShaderNodeTexImage')
bake_node.image = baked
nodes.active = bake_node
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 1
scene.render.bake.margin = 16
scene.render.bake.use_selected_to_active = False
bpy.ops.object.select_all(action='DESELECT')
mesh.select_set(True)
bpy.context.view_layer.objects.active = mesh
bpy.ops.object.bake(type='EMIT')
args.out.parent.mkdir(parents=True, exist_ok=True)
baked.filepath_raw = str(args.out.resolve())
baked.file_format = 'PNG'
baked.save()
report = {'character': 'sora', 'body_source_pixels': list(original.size),
          'head_source_pixels': list(head.size), 'output_pixels': list(baked.size),
          'transition_normalized_height': [.805, .835],
          'original_static': str(args.original_static), 'head_texture': str(args.head_texture),
          'output': str(args.out), 'geometry_exported': False,
          'requires_visual_neck_transition_review': True}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps(report, ensure_ascii=False))

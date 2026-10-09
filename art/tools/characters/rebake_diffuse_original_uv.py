"""Bake a generator's diffuse onto an approved static character's original UVs.

Run with Blender. Output is only an image; both input model files stay intact.
Alignment uses height, floor and horizontal bounding-box centers. Inspect all
views afterwards: this is suitable only for models with matching silhouettes.
"""
import argparse
from array import array
import json
import sys
from pathlib import Path
import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree


def import_mesh(path, name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [obj for obj in set(bpy.data.objects) - before if obj.type == 'MESH']
    assert len(meshes) == 1
    obj = meshes[0]
    obj.name = name
    return obj


def bounds(obj):
    points = [obj.matrix_world @ Vector(point) for point in obj.bound_box]
    low = Vector([min(p[i] for p in points) for i in range(3)])
    high = Vector([max(p[i] for p in points) for i in range(3)])
    return low, high


parser = argparse.ArgumentParser()
parser.add_argument('--approved', type=Path, required=True)
parser.add_argument('--generated', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--report', type=Path, required=True)
parser.add_argument('--size', type=int, default=4096)
parser.add_argument('--restore-hands-from', type=Path)
parser.add_argument('--hand-albedo', choices=['approved', 'face-median', 'wrist-median'], default='approved')
parser.add_argument('--hand-mask', choices=['joint-plane', 'apose-extent'], default='joint-plane')
parser.add_argument('--cage-extrusion', type=float, default=.025)
parser.add_argument('--ray-distance', type=float, default=.05)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
target = import_mesh(args.approved, 'Original_UV_Target')
source = import_mesh(args.generated, 'Generated_Diffuse_Source')
bpy.context.view_layer.update()
tl, th = bounds(target)
sl, sh = bounds(source)
scale = (th.z - tl.z) / (sh.z - sl.z)
source.scale *= scale
bpy.context.view_layer.update()
sl, sh = bounds(source)
source.location += Vector(((tl.x + th.x - sl.x - sh.x) / 2,
                           (tl.y + th.y - sl.y - sh.y) / 2,
                           tl.z - sl.z))
bpy.context.view_layer.update()
source_material = source.data.materials[0]
diffuse_node = next(node for node in source_material.node_tree.nodes
                    if node.type == 'TEX_IMAGE' and 'diffuse' in node.image.name.lower())
diffuse_image = diffuse_node.image
source_material.node_tree.nodes.clear()
nodes = source_material.node_tree.nodes
texture = nodes.new('ShaderNodeTexImage')
texture.image = diffuse_image
texture.interpolation = 'Linear'
emission = nodes.new('ShaderNodeEmission')
output = nodes.new('ShaderNodeOutputMaterial')
source_material.node_tree.links.new(texture.outputs['Color'], emission.inputs['Color'])
source_material.node_tree.links.new(emission.outputs[0], output.inputs['Surface'])
target.data.materials.clear()
target_material = bpy.data.materials.new('Original_UV_Diffuse_Bake')
target_material.use_nodes = True
target.data.materials.append(target_material)
image = bpy.data.images.new('Original_UV_Diffuse', width=args.size, height=args.size,
                            alpha=False, float_buffer=False)
image.colorspace_settings.name = 'sRGB'
active_texture = target_material.node_tree.nodes.new('ShaderNodeTexImage')
active_texture.image = image
target_material.node_tree.nodes.active = active_texture
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 1
scene.render.bake.use_selected_to_active = True
scene.render.bake.cage_extrusion = args.cage_extrusion
scene.render.bake.max_ray_distance = args.ray_distance
scene.render.bake.margin = max(16, args.size // 256)
bpy.ops.object.select_all(action='DESELECT')
source.select_set(True)
target.select_set(True)
bpy.context.view_layer.objects.active = target
print(json.dumps({'status': 'baking', 'pixels': args.size,
                  'generated_texture_pixels': list(diffuse_image.size), 'alignment_scale': scale}), flush=True)
bpy.ops.object.bake(type='EMIT')
restored_vertices = 0
hand_face_colour = None
if args.restore_hands_from:
    # Only use the approved rig's hand weights to identify a colour region.
    # The imported rig is never exported or adopted by this image-only tool.
    previous_objects = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(args.restore_hands_from.resolve()))
    bpy.context.view_layer.update()
    rig_meshes = [obj for obj in set(bpy.data.objects) - previous_objects if obj.type == 'MESH']
    rig_armatures = [obj for obj in set(bpy.data.objects) - previous_objects if obj.type == 'ARMATURE']
    wrist_planes = []
    for armature in rig_armatures:
        for side in ['Left', 'Right']:
            hand_bone = armature.data.bones.get('mixamorig:' + side + 'Hand')
            forearm_bone = armature.data.bones.get('mixamorig:' + side + 'ForeArm')
            if hand_bone and forearm_bone:
                wrist = armature.matrix_world @ hand_bone.head_local
                elbow = armature.matrix_world @ forearm_bone.head_local
                wrist_planes.append((wrist, (wrist - elbow).normalized()))
    assert len(wrist_planes) == 2, 'The approved rig must contain both wrist joints.'
    approved_body = max(rig_meshes, key=lambda obj: len(obj.data.vertices))
    approved_hand_diffuse = next(node.image for node in approved_body.data.materials[0].node_tree.nodes
                                if node.type == 'TEX_IMAGE' and node.image)
    samples = []
    for obj in rig_meshes:
        hand_groups = {group.index for group in obj.vertex_groups
                       if 'Hand' in group.name or 'ForeArm' in group.name}
        for vertex in obj.data.vertices:
            weight = sum(group.weight for group in vertex.groups if group.group in hand_groups)
            samples.append((obj.matrix_world @ vertex.co, weight))
    gl = Vector([min(point[i] for point, _ in samples) for i in range(3)])
    gh = Vector([max(point[i] for point, _ in samples) for i in range(3)])
    tree = KDTree(len(samples))
    for index, (point, _) in enumerate(samples):
        tree.insert(point, index)
    tree.balance()
    target_to_game_scale = (gh.z - gl.z) / (th.z - tl.z)
    target_center = (tl + th) / 2
    game_center = (gl + gh) / 2
    target_half_width = (th.x - tl.x) / 2
    attribute = target.data.color_attributes.new(name='ApprovedHandColour', type='FLOAT_COLOR', domain='POINT')
    for vertex in target.data.vertices:
        world = target.matrix_world @ vertex.co
        mapped = (world - target_center) * target_to_game_scale + game_center
        _, nearest, _ = tree.find(mapped)
        arm_weight = max(0., min(1., (samples[nearest][1] - .10) / .50))
        distal = max((mapped - wrist).dot(direction) for wrist, direction in wrist_planes)
        wrist_fade = max(0., min(1., (distal + .035) / .035))
        value = arm_weight * wrist_fade
        if args.hand_mask == 'apose-extent':
            # Explicit Sora A-pose fallback. It is not a general segmenter for
            # dressed characters whose clothes extend beyond the hands.
            value = max(0., min(1., (abs(world.x - target_center.x) / target_half_width - .70) / .12))
        value = value * value * (3. - 2. * value)
        attribute.data[vertex.index].color = (value, value, value, 1.)
        restored_vertices += int(value > .01)
    for obj in set(bpy.data.objects) - previous_objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    if args.hand_albedo in ['face-median', 'wrist-median']:
        # Sample the freshly baked face in scene-linear space. A flat skin
        # albedo suits the existing anime renderer; mesh lighting supplies
        # the hand's form without coloured creases in the diffuse.
        face_colours = []
        # Read the baked buffer once; individual RNA pixel accesses can copy
        # the entire image for every colour sample.
        baked_pixels = array('f', [0.]) * (args.size * args.size * 4)
        image.pixels.foreach_get(baked_pixels)
        uv_layer = target.data.uv_layers.active
        target_height = th.z - tl.z
        for loop in target.data.loops:
            point = target.matrix_world @ target.data.vertices[loop.vertex_index].co
            is_face = (.015 * target_height < abs(point.x - target_center.x) < .05 * target_height
                       and tl.z + .81 * target_height < point.z < tl.z + .87 * target_height)
            is_wrist = (.72 < abs(point.x - target_center.x) / target_half_width < .79)
            if not (is_face if args.hand_albedo == 'face-median' else is_wrist):
                continue
            uv = uv_layer.data[loop.index].uv
            ix = max(0, min(args.size - 1, int(uv.x * args.size)))
            iy = max(0, min(args.size - 1, int(uv.y * args.size)))
            pixel = (iy * args.size + ix) * 4
            colour = tuple(baked_pixels[pixel + channel] for channel in range(3))
            if (colour[0] > .20 and colour[0] > colour[1] > colour[2]
                    and colour[1] / colour[0] > .60 and colour[2] / colour[0] > .50):
                face_colours.append(colour)
        assert face_colours, 'No valid cheek colour samples; inspect the candidate.'
        cheek_rgb = tuple(sorted(c[channel] for c in face_colours)[len(face_colours) // 2]
                          for channel in range(3))
        # The byte image's sRGB pixel values need scene-linear conversion
        # when assigned directly to an emission shader colour input.
        hand_face_colour = tuple(value / 12.92 if value <= .04045
                                 else ((value + .055) / 1.055) ** 2.4 for value in cheek_rgb)
    # Mix the approved hand albedo into the generated albedo and bake that
    # material on the same original UVs. No image-space painting or UV edits.
    target_material.node_tree.nodes.clear()
    nodes = target_material.node_tree.nodes
    generated_tex = nodes.new('ShaderNodeTexImage')
    generated_tex.image = image
    approved_tex = nodes.new('ShaderNodeTexImage')
    approved_tex.image = approved_hand_diffuse
    mask = nodes.new('ShaderNodeVertexColor')
    mask.layer_name = attribute.name
    mix = nodes.new('ShaderNodeMixRGB')
    emit = nodes.new('ShaderNodeEmission')
    out_node = nodes.new('ShaderNodeOutputMaterial')
    links = target_material.node_tree.links
    links.new(mask.outputs['Color'], mix.inputs[0])
    links.new(generated_tex.outputs['Color'], mix.inputs[1])
    if hand_face_colour:
        mix.inputs[2].default_value = (*hand_face_colour, 1.)
    else:
        links.new(approved_tex.outputs['Color'], mix.inputs[2])
    links.new(mix.outputs[0], emit.inputs['Color'])
    links.new(emit.outputs[0], out_node.inputs['Surface'])
    clean = bpy.data.images.new('Original_UV_Clean_Hands', width=args.size, height=args.size,
                               alpha=False, float_buffer=False)
    clean.colorspace_settings.name = 'sRGB'
    bake_tex = nodes.new('ShaderNodeTexImage')
    bake_tex.image = clean
    nodes.active = bake_tex
    bpy.ops.object.select_all(action='DESELECT')
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    scene.render.bake.use_selected_to_active = False
    bpy.ops.object.bake(type='EMIT')
    image = clean
args.out.parent.mkdir(parents=True, exist_ok=True)
image.filepath_raw = str(args.out.resolve())
image.file_format = 'PNG'
image.save()
report = {'approved': str(args.approved), 'generated': str(args.generated),
          'output': str(args.out), 'pixels': list(image.size), 'alignment_scale': scale,
          'alignment_translation': list(source.location), 'method': 'selected-to-active emission',
          'cage_extrusion': args.cage_extrusion, 'max_ray_distance': args.ray_distance,
          'hand_albedo_source': str(args.restore_hands_from) if args.restore_hands_from else None,
          'hand_albedo_mode': args.hand_albedo if args.restore_hands_from else None,
          'hand_mask_mode': args.hand_mask if args.restore_hands_from else None,
          'hand_face_colour_linear': hand_face_colour,
          'hand_mask_vertices': restored_vertices,
          'output_only_image': True, 'visual_acceptance_required': True}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2))
print(json.dumps(report), flush=True)

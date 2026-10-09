"""Inspect a generator's unmodified palm colours before texture transfer."""
from pathlib import Path
import argparse
import json
import math
import sys
import bpy
from mathutils import Vector, Matrix

parser = argparse.ArgumentParser()
parser.add_argument('--model', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--include-body-face', action='store_true')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(args.model.resolve()))
mesh = max((obj for obj in bpy.data.objects if obj.type == 'MESH'),
           key=lambda obj: len(obj.data.vertices))
for obj in bpy.context.scene.objects:
    if obj.animation_data:
        obj.animation_data.action = None
        for track in obj.animation_data.nla_tracks:
            track.mute = True
    if obj.type == 'ARMATURE':
        for bone in obj.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        factor = float(obj.get('hand_size_review', {}).get('scale', 1.))
        for side in ['Left', 'Right']:
            bone = obj.pose.bones.get('mixamorig:' + side + 'Hand')
            if bone:
                bone.scale = (factor, factor, factor)
    if obj.type == 'MESH' and obj.data.shape_keys:
        keys = obj.data.shape_keys
        for key in keys.key_blocks:
            key.value = 0
        if keys.animation_data:
            keys.animation_data.action = None
            for track in keys.animation_data.nla_tracks:
                track.mute = True
material = mesh.data.materials[0]
diffuse = next(node.image for node in material.node_tree.nodes
               if node.type == 'TEX_IMAGE' and 'diffuse' in node.image.name.lower())
material.node_tree.nodes.clear()
tex = material.node_tree.nodes.new('ShaderNodeTexImage')
tex.image = diffuse
emission = material.node_tree.nodes.new('ShaderNodeEmission')
output = material.node_tree.nodes.new('ShaderNodeOutputMaterial')
material.node_tree.links.new(tex.outputs['Color'], emission.inputs['Color'])
material.node_tree.links.new(emission.outputs[0], output.inputs['Surface'])
points = [mesh.matrix_world @ vertex.co for vertex in mesh.data.vertices]
height = max(point.z for point in points) - min(point.z for point in points)
max_x = max(abs(point.x) for point in points)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 1
scene.cycles.device = 'CPU'
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.world.color = (.15, .15, .15)
scene.view_settings.view_transform = 'Standard'
camera_data = bpy.data.cameras.new('PalmCamera')
camera_data.type = 'ORTHO'
camera_data.ortho_scale = height * .24
camera = bpy.data.objects.new('PalmCamera', camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
args.out.mkdir(parents=True, exist_ok=True)
views = [('front', 0, 0), ('back', 180, 0), ('left', 90, 0), ('right', -90, 0),
         ('above', 0, 35), ('below', 0, -25), ('top', 0, 75), ('bottom', 0, -60)]
centers = {}
for side, sign in [('left', -1), ('right', 1)]:
    hand_points = [point for point in points if point.x * sign > max_x * .80]
    center = sum(hand_points, Vector()) / len(hand_points)
    centers[side] = list(center)
    for name, yaw_deg, pitch_deg in views:
        yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
        camera.location = center + Vector((math.sin(yaw) * math.cos(pitch),
                                           -math.cos(yaw) * math.cos(pitch), math.sin(pitch))) * height * 2
        camera.rotation_euler = (center - camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str((args.out / f'{side}-{name}.png').resolve())
        bpy.ops.render.render(write_still=True)
if args.include_body_face:
    low = Vector([min(point[i] for point in points) for i in range(3)])
    high = Vector([max(point[i] for point in points) for i in range(3)])
    for focus, ratio, size in [('body', .52, height * 1.25), ('face', .92, height * .32)]:
        center = Vector(((low.x + high.x) / 2, (low.y + high.y) / 2, low.z + height * ratio))
        camera_data.ortho_scale = size
        for name, yaw_deg, pitch_deg in views:
            yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
            camera.location = center + Vector((math.sin(yaw) * math.cos(pitch),
                                               -math.cos(yaw) * math.cos(pitch), math.sin(pitch))) * height * 3
            camera.rotation_euler = (center - camera.location).to_track_quat('-Z', 'Y').to_euler()
            scene.render.filepath = str((args.out / f'{focus}-{name}.png').resolve())
            bpy.ops.render.render(write_still=True)
(args.out / 'inspection.json').write_text(json.dumps({'model': str(args.model),
    'diffuse_pixels': list(diffuse.size), 'palm_centers': centers,
    'material': 'unlit emission, no geometry or colour edits'}, indent=2))

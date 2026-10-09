"""Prepare the owned Hyper3D boughs and a continuous, layered anime crown.

Blender -b --factory-startup -P art/tools/plaza_hero_tree.py
Only writes authoring sources under art/models/raw; game export stays separate.
"""
import json
import math
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "art/models/raw/T05_plaza_full_hyper3d_20261010"
OUT = RAW / "prepared"
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(RAW / "model.glb"))
meshes = [ob for ob in bpy.context.scene.objects if ob.type == "MESH"]
points = np.concatenate([np.array([ob.matrix_world @ v.co for v in ob.data.vertices]) for ob in meshes])
lo, hi = points.min(axis=0), points.max(axis=0)
base = Vector(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]))
scale = 6.8 / (hi[2] - lo[2])
yaw = Matrix.Rotation(math.radians(-90), 4, "Z")
for ob in meshes:
    world = ob.matrix_world.copy()
    for vertex in ob.data.vertices:
        vertex.co = yaw @ ((world @ vertex.co - base) * scale)
        if vertex.co.z < .85:
            height_weight = max(0, min(1, vertex.co.z / .85))
            root_weight = 1 - (3 * height_weight ** 2 - 2 * height_weight ** 3)
            vertex.co.x *= 1 - .28 * root_weight
            vertex.co.y *= 1 - .28 * root_weight
    ob.parent = None
    ob.matrix_world = Matrix.Identity(4)
    ob.name = "Trunk_Hyper3D"
    bpy.context.view_layer.objects.active = ob
    # Provider vertices are split at UV seams. Collapse them physically before
    # reducing faces; per-loop UVs remain intact, while the bark stays closed.
    welded = bmesh.new()
    welded.from_mesh(ob.data)
    bmesh.ops.remove_doubles(welded, verts=list(welded.verts), dist=.00001)
    welded.to_mesh(ob.data)
    welded.free()
    reduce = ob.modifiers.new("Retain knots and flowing boughs", "DECIMATE")
    reduce.ratio = .34
    bpy.ops.object.modifier_apply(modifier=reduce.name)
    for poly in ob.data.polygons:
        poly.use_smooth = True
    for material in ob.data.materials:
        if not material.use_nodes:
            continue
        shader = material.node_tree.nodes.get("Principled BSDF")
        for name in ["Normal", "Metallic", "Roughness", "Specular IOR Level"]:
            for link in list(shader.inputs[name].links):
                material.node_tree.links.remove(link)
        shader.inputs["Metallic"].default_value = 0
        shader.inputs["Roughness"].default_value = 1
        shader.inputs["Specular IOR Level"].default_value = 0

foliage_material = bpy.data.materials.new("PaintedOldTreeSprigs")
foliage_material.use_nodes = True
shader = foliage_material.node_tree.nodes.get("Principled BSDF")
shader.inputs["Roughness"].default_value = 1
shader.inputs["Specular IOR Level"].default_value = 0
texture = foliage_material.node_tree.nodes.new("ShaderNodeTexImage")
texture.image = bpy.data.images.load(str(ROOT / "art/references/plaza_paintover_20261009/plaza_leaf_sprigs_atlas.png"))
foliage_material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
foliage_material.node_tree.links.new(texture.outputs["Alpha"], shader.inputs["Alpha"])
foliage_material.surface_render_method = "DITHERED"
foliage_material.use_transparency_overlap = False
rng = np.random.default_rng(61010)
vertices, faces, uv_values = [], [], []

def sprig(position, normal, half_width):
    normal = Vector(normal).normalized()
    right = normal.cross(Vector((0, 0, 1)))
    if right.length < .1:
        right = Vector((1, 0, 0))
    right.normalize()
    up = normal.cross(right).normalized()
    angle = rng.uniform(-math.pi, math.pi)
    right, up = right * math.cos(angle) + up * math.sin(angle), up * math.cos(angle) - right * math.sin(angle)
    point = Vector(position)
    half_height = half_width * .85
    first = len(vertices)
    vertices.extend([(point - right * half_width - up * half_height)[:],
                     (point + right * half_width - up * half_height)[:],
                     (point + right * half_width + up * half_height)[:],
                     (point - right * half_width + up * half_height)[:]])
    faces.extend([(first, first + 1, first + 2), (first, first + 2, first + 3)])
    # Only the top two cells contain old-tree foliage; the lower cells are grapes.
    u = int(rng.integers(0, 2)) * .5
    uv_values.extend([(u + .025, .525), (u + .475, .525), (u + .475, .975), (u + .025, .975)])

count = 0
while count < 4200:
    x, y = rng.uniform(-6.25, 6.0), rng.uniform(-5.1, 5.05)
    radius = (x / 6.15) ** 2 + (y / 5.0) ** 2
    edge = 1 + .08 * math.sin(x * 2.1 + y * .7) + .045 * math.sin(y * 3.0)
    if radius > edge:
        continue
    # Two narrow oblique apertures retain sky between the layered branches.
    if ((x + 1.65) / .40) ** 2 + ((y - 1.35) / .58) ** 2 < 1:
        continue
    if ((x - 2.45) / .32) ** 2 + ((y + 1.9) / .45) ** 2 < 1:
        continue
    shape = max(0, 1 - radius)
    lower = 4.05 + 1.25 * shape + .16 * math.sin(x + y)
    upper = 6.25 + 2.35 * shape + .15 * math.sin(x * .8 - y)
    z = rng.uniform(lower, upper)
    normal = rng.normal(size=3)
    normal[2] = abs(normal[2]) * .7 + .25
    sprig((x, y, z), normal, rng.uniform(.30, .49))
    count += 1

leaf_mesh = bpy.data.meshes.new("ContinuousAsymmetricCrown")
leaf_mesh.from_pydata(vertices, [], faces)
leaf_mesh.update()
foliage = bpy.data.objects.new("Foliage_PlazaOldTree", leaf_mesh)
bpy.context.collection.objects.link(foliage)
foliage.data.materials.append(foliage_material)
uv = leaf_mesh.uv_layers.new(name="OldTreeSprigAtlas")
for poly in leaf_mesh.polygons:
    for loop_index in poly.loop_indices:
        uv.data[loop_index].uv = uv_values[leaf_mesh.loops[loop_index].vertex_index]

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=str(OUT / "T05_old_shade_tree.glb"), export_format="GLB", export_image_format="AUTO", export_yup=True, export_animations=False)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "T05_old_shade_tree.blend"))
all_points = np.concatenate([np.array([v.co for v in ob.data.vertices]) for ob in [*meshes, foliage]])
size = all_points.max(axis=0) - all_points.min(axis=0)
report = {"generation_id": "e958a9cb-fd96-430b-9881-5c05490505fb", "uniform_source_height": 6.8,
          "yaw_degrees": -90, "root_radial_reduction_at_ground": .28, "leaf_sprigs": count, "godot_size_m_xyz": [float(size[0]), float(size[2]), float(size[1])],
          "triangles": sum(sum(len(p.vertices) - 2 for p in ob.data.polygons) for ob in [*meshes, foliage]),
          "method": "Owned Hyper3D boughs with original UVs, matte finish, independent alpha crown; no new paid generation."}
(OUT / "preparation.json").write_text(json.dumps(report, indent=2) + "\n")
print("PLAZA_TREE", json.dumps(report), flush=True)

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
OUT = ROOT / "art/models/raw/T05_canopy_depth_20261010"
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
vertices, faces, uv_values, leaf_layers = [], [], [], []

def sprig(position, normal, half_width, layer):
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
    leaf_layers.extend([layer, layer])
    # Only the top two cells contain old-tree foliage; the lower cells are grapes.
    u = int(rng.integers(0, 2)) * .5
    uv_values.extend([(u + .025, .525), (u + .475, .525), (u + .475, .975), (u + .025, .975)])

# Branch-supported shelves overlap at different heights. Their edges remain
# irregular, with broad gaps rather than a uniformly filled spherical volume.
clusters = [
    ((-3.9, .4, 5.7), (2.4, 2.35, .65)),
    ((-2.3, 2.0, 6.95), (2.65, 2.25, .8)),
    ((.4, .7, 8.0), (2.4, 2.0, .8)),
    ((3.65, -.4, 6.55), (2.3, 2.55, .8)),
    ((2.45, 2.85, 7.25), (2.35, 2.15, .7)),
    ((.6, -2.7, 6.25), (2.3, 2.1, .7)),
    ((-3.0, -2.6, 5.45), (2.6, 2.15, .65)),
    ((-2.5, 3.25, 5.95), (2.5, 1.8, .7)),
    ((.7, 3.75, 6.2), (2.1, 1.5, .65)),
]
count = 0
while count < 1900:
    centre, extent = clusters[int(rng.integers(len(clusters)))]
    vector = rng.normal(size=3)
    vector /= np.linalg.norm(vector)
    point = np.array(centre) + vector * np.array(extent) * rng.uniform(.18, 1.0) ** (1 / 3)
    x, y, z = point
    # Reserve irregular light shafts along the real late-morning sun vector.
    projected_x = x - .5165 * (6.5 - z)
    projected_y = y - .7375 * (6.5 - z)
    if ((projected_x + 1.7) / .90) ** 2 + ((projected_y - .8) / 1.12) ** 2 < 1:
        continue
    if ((projected_x - 1.9) / .80) ** 2 + ((projected_y + 1.3) / .95) ** 2 < 1:
        continue
    normal = rng.normal(size=3)
    normal[2] = normal[2] * .65 + .4
    layer = 2 if z > 7.5 else (0 if z < 5.8 else 1)
    sprig((x, y, z), normal, rng.uniform(.22, .36), layer)
    count += 1

leaf_mesh = bpy.data.meshes.new("LayeredOpenCrown")
leaf_mesh.from_pydata(vertices, [], faces)
leaf_mesh.update()
foliage = bpy.data.objects.new("Foliage_PlazaOldTree", leaf_mesh)
bpy.context.collection.objects.link(foliage)
for index, tint in enumerate([(.78, .86, .82, 1), (.94, .98, .91, 1), (1, 1, .90, 1)]):
    material = foliage_material.copy()
    material.name = "OldTreeLeafLayer_%d" % index
    node = material.node_tree.nodes.get("Principled BSDF")
    image_node = next(n for n in material.node_tree.nodes if n.type == "TEX_IMAGE")
    multiply = material.node_tree.nodes.new("ShaderNodeMixRGB")
    multiply.blend_type = "MULTIPLY"
    multiply.inputs[0].default_value = 1
    multiply.inputs[2].default_value = tint
    material.node_tree.links.new(image_node.outputs["Color"], multiply.inputs[1])
    material.node_tree.links.new(multiply.outputs[0], node.inputs["Base Color"])
    foliage.data.materials.append(material)
uv = leaf_mesh.uv_layers.new(name="OldTreeSprigAtlas")
for poly in leaf_mesh.polygons:
    poly.material_index = leaf_layers[poly.index]
    for loop_index in poly.loop_indices:
        uv.data[loop_index].uv = uv_values[leaf_mesh.loops[loop_index].vertex_index]

# Eight closely spaced surfaces form a short pile. The runtime material opens
# progressively finer gaps through the upper layers, producing a soft rim.
trunk = meshes[0]
trunk.data.calc_loop_triangles()
positions = np.array([vertex.co[:] for vertex in trunk.data.vertices])
vertex_normals = np.array([vertex.normal[:] for vertex in trunk.data.vertices])
triangles = np.array([triangle.vertices[:] for triangle in trunk.data.loop_triangles])
centres = positions[triangles].mean(axis=1)
selected = triangles[(centres[:, 2] > .025) & (centres[:, 2] < 2.4)]
used, inverse = np.unique(selected.reshape(-1), return_inverse=True)
shell_faces = inverse.reshape(-1, 3).tolist()
material = bpy.data.materials.new("VelvetMossSurface")
material.use_nodes = True
node = material.node_tree.nodes.get("Principled BSDF")
node.inputs["Roughness"].default_value = 1
node.inputs["Specular IOR Level"].default_value = 0
moss_texture = material.node_tree.nodes.new("ShaderNodeTexImage")
moss_texture.image = bpy.data.images.load(str(ROOT / "art/references/canopy_depth_20261010/moss_velvet.png"))
material.node_tree.links.new(moss_texture.outputs["Color"], node.inputs["Base Color"])
moss_objects = []
for layer in range(8):
    height = .001 + layer * .003
    shell_points = positions[used] + vertex_normals[used] * height
    shell_mesh = bpy.data.meshes.new("MossReliefLayer_%02d" % layer)
    shell_mesh.from_pydata(shell_points.tolist(), [], shell_faces)
    shell_mesh.update()
    shell_mesh.materials.append(material)
    shell_uv = shell_mesh.uv_layers.new()
    for polygon in shell_mesh.polygons:
        polygon.use_smooth = True
        for loop in polygon.loop_indices:
            point = shell_mesh.vertices[shell_mesh.loops[loop].vertex_index].co
            shell_uv.data[loop].uv = (point.x, point.z)
    moss = bpy.data.objects.new("Moss_Shell_%02d" % layer, shell_mesh)
    bpy.context.collection.objects.link(moss)
    moss_objects.append(moss)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=str(OUT / "T05_old_shade_tree.glb"), export_format="GLB", export_image_format="AUTO", export_yup=True, export_animations=False)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "T05_old_shade_tree.blend"))
all_points = np.concatenate([np.array([v.co for v in ob.data.vertices]) for ob in [*meshes, foliage, *moss_objects]])
size = all_points.max(axis=0) - all_points.min(axis=0)
report = {"generation_id": "e958a9cb-fd96-430b-9881-5c05490505fb", "uniform_source_height": 6.8,
          "yaw_degrees": -90, "root_radial_reduction_at_ground": .28, "leaf_sprigs": count, "godot_size_m_xyz": [float(size[0]), float(size[2]), float(size[1])],
          "triangles": sum(sum(len(p.vertices) - 2 for p in ob.data.polygons) for ob in [*meshes, foliage, *moss_objects]),
          "moss_shell_layers": 8, "moss_pile_height_m": [.001, .022],
          "crown_shelves": clusters,
          "method": "Owned Hyper3D boughs with original UVs, matte finish, layered alpha shelves and sun-aligned gaps; no new paid generation."}
(OUT / "preparation.json").write_text(json.dumps(report, indent=2) + "\n")
print("PLAZA_TREE", json.dumps(report), flush=True)

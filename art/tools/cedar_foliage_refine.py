"""Replace Pine_3's broad flat foliage planes with irregular cedar needle sprays."""
import bpy
import json
import math
import numpy as np
from mathutils import Vector
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/models/raw/T04_cedar_depth_20261010"
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT / "art/models/raw/free_foliage_20261004/ready/T04_slender_cedar.glb"))
for ob in list(bpy.context.scene.objects):
    if ob.type != "MESH" or not ob.name.startswith("Trunk"):
        bpy.data.objects.remove(ob, do_unlink=True)
wood = next(ob for ob in bpy.context.scene.objects if ob.type == "MESH")
wood.name = "Trunk_Cedar"
material = bpy.data.materials.new("CedarNeedleSprigs")
material.use_nodes = True
shader = material.node_tree.nodes.get("Principled BSDF")
shader.inputs["Roughness"].default_value = 1
shader.inputs["Specular IOR Level"].default_value = 0
texture = material.node_tree.nodes.new("ShaderNodeTexImage")
texture.image = bpy.data.images.load(str(ROOT / "art/references/canopy_depth_20261010/cedar_sprigs.png"))
material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
material.node_tree.links.new(texture.outputs["Alpha"], shader.inputs["Alpha"])
material.surface_render_method = "DITHERED"
material.use_transparency_overlap = False
rng = np.random.default_rng(741010)
vertices, faces, uvs = [], [], []
def spray(point, normal, width):
    point, normal = Vector(point), Vector(normal).normalized()
    right = normal.cross(Vector((0, 0, 1)))
    if right.length < .1:
        right = Vector((1, 0, 0))
    right.normalize()
    up = normal.cross(right).normalized()
    first = len(vertices)
    vertices.extend([(point - right * width - up * width * .8)[:], (point + right * width - up * width * .8)[:],
                     (point + right * width + up * width * .8)[:], (point - right * width + up * width * .8)[:]])
    faces.extend([(first, first + 1, first + 2), (first, first + 2, first + 3)])
    cell = int(rng.integers(4));u, v = (cell % 2) * .5, (cell // 2) * .5
    uvs.extend([(u + .025, v + .025), (u + .475, v + .025), (u + .475, v + .475), (u + .025, v + .475)])

for branch in range(36):
    height = 1.85 + branch * .215
    angle = branch * 2.39996
    reach = 2.3 * max(.04, 1 - (height - 1.8) / 8.1) ** .6
    reach *= 1 + .13 * math.sin(branch * 1.7)
    for leaf in range(42):
        distance = reach * rng.uniform(.18, 1)
        spread = angle + rng.uniform(-.52, .52)
        position = (math.cos(spread) * distance, math.sin(spread) * distance,
                    height + .26 * distance / max(reach, .1) + rng.uniform(-.26, .26))
        normal = (math.cos(spread), math.sin(spread), rng.uniform(-.2, .4))
        spray(position, normal, rng.uniform(.38, .49) * (1 - .20 * height / 10))
for leaf in range(320):
    height = rng.uniform(2.5, 9.75)
    radius = .6 * (1 - height / 11)
    angle = rng.uniform(0, math.tau)
    spray((math.cos(angle) * radius, math.sin(angle) * radius, height), (math.cos(angle), math.sin(angle), .1), rng.uniform(.25, .42))
for leaf in range(90):
    angle = rng.uniform(0, math.tau)
    spray((math.cos(angle) * .13, math.sin(angle) * .13, rng.uniform(9.35, 9.92)), (math.cos(angle), math.sin(angle), .15), rng.uniform(.16, .27))
mesh = bpy.data.meshes.new("CedarFeatheredSprays")
mesh.from_pydata(vertices, [], faces);mesh.update()
foliage = bpy.data.objects.new("Foliage_CedarSprays", mesh);bpy.context.collection.objects.link(foliage)
mesh.materials.append(material);uv = mesh.uv_layers.new()
for polygon in mesh.polygons:
    for index in polygon.loop_indices:
        uv.data[index].uv = uvs[mesh.loops[index].vertex_index]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=str(OUT / "T04_slender_cedar.glb"), export_format="GLB", export_yup=True, export_image_format="AUTO", export_animations=False)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "T04_slender_cedar.blend"))
(OUT / "preparation.json").write_text(json.dumps({"retained_source": "CC0 Quaternius Pine_3 trunk and boughs", "sprigs": len(vertices) // 4, "foliage_triangles": len(faces), "texture": "art/references/canopy_depth_20261010/cedar_sprigs.png"}, indent=2) + "\n")

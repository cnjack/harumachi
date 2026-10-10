"""Measure actual foliage triangle size, crown profile and alpha-aware sunlight paths.

Blender -b --factory-startup -P this.py -- OUTPUT.json MODEL.glb ...
The sun vector matches the town's 11:30 light (-48 pitch, -35 yaw).
"""
import bpy
import hashlib
import json
import math
import numpy as np
from pathlib import Path
import sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree

arguments = sys.argv[sys.argv.index("--") + 1:]
output = Path(arguments[0])
reports = {}
for name in arguments[1:]:
    path = Path(name).resolve()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    vertices, triangles, triangle_uvs, texture_ids = [], [], [], []
    textures = {}
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH" or not ob.name.startswith("Foliage"):
            continue
        ob.data.calc_loop_triangles()
        first = len(vertices)
        vertices.extend([ob.matrix_world @ vertex.co for vertex in ob.data.vertices])
        for triangle in ob.data.loop_triangles:
            triangles.append(tuple(first + index for index in triangle.vertices))
            uv = ob.data.uv_layers.active
            triangle_uvs.append(np.array([uv.data[index].uv[:] for index in triangle.loops]) if uv else np.zeros((3, 2)))
            material = ob.data.materials[triangle.material_index]
            shader = material.node_tree.nodes.get("Principled BSDF") if material.use_nodes else None
            links = shader.inputs["Base Color"].links if shader else []
            image = links[0].from_node.image if links and links[0].from_node.type == "TEX_IMAGE" else None
            if image is None and shader:
                alpha_links = shader.inputs["Alpha"].links
                if alpha_links and alpha_links[0].from_node.type == "TEX_IMAGE":
                    image = alpha_links[0].from_node.image
            key = image.name if image else "opaque"
            if image and key not in textures:
                textures[key] = np.array(image.pixels[:], dtype=np.float32).reshape(image.size[1], image.size[0], 4)[:, :, 3]
            texture_ids.append(key)
    points = np.array(vertices)
    corners = points[np.array(triangles)]
    lengths = np.linalg.norm(corners - np.roll(corners, 1, axis=1), axis=2)
    radius = np.linalg.norm(points[:, :2], axis=1)
    angles = np.arctan2(points[:, 1], points[:, 0])
    profile = []
    for sector in range(12):
        selected = points[(radius > 2.5) & (radius < 4.8) & (angles >= -math.pi + sector * math.tau / 12) & (angles < -math.pi + (sector + 1) * math.tau / 12)]
        if len(selected):
            profile.append(float(np.quantile(selected[:, 2], .96)))
    tree = BVHTree.FromPolygons(vertices, triangles, all_triangles=True)
    sun = Vector((math.sin(math.radians(-35)) * math.cos(math.radians(-48)),
                  -math.cos(math.radians(-35)) * math.cos(math.radians(-48)),
                  -math.sin(math.radians(-48)))).normalized()
    def reaches_sky(point):
        for _ in range(180):
            hit, normal, index, distance = tree.ray_cast(point, sun, 40.0)
            if hit is None:
                return True
            alpha = textures.get(texture_ids[index])
            if alpha is None:
                return False
            a, b, c = corners[index]
            ab, ac, ah = b - a, c - a, np.array(hit) - a
            d00, d01, d11 = ab.dot(ab), ab.dot(ac), ac.dot(ac)
            denominator = d00 * d11 - d01 * d01
            if abs(denominator) > 1e-14:
                v = (d11 * ah.dot(ab) - d01 * ah.dot(ac)) / denominator
                w = (d00 * ah.dot(ac) - d01 * ah.dot(ab)) / denominator
                uv = triangle_uvs[index][0] * (1 - v - w) + triangle_uvs[index][1] * v + triangle_uvs[index][2] * w
                x, y = int((uv[0] % 1) * alpha.shape[1]), int((uv[1] % 1) * alpha.shape[0])
                if alpha[y, x] >= .42:
                    return False
            point = hit + sun * .0005
        return False
    transmitted = 0
    samples = []
    for x in np.linspace(-3.2, 3.2, 21):
        for y in np.linspace(-3.2, 3.2, 21):
            point = Vector((float(x) - sun.x / sun.z * 6.5, float(y) - sun.y / sun.z * 6.5, .02))
            opened = reaches_sky(point)
            samples.append({"ground_xy": [round(point.x, 3), round(point.y, 3)], "sunlit": opened})
            transmitted += int(opened)
    reports[path.stem] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "source_mtime": path.stat().st_mtime,
        "foliage_triangles": len(triangles), "max_leaf_triangle_edge_m": round(float(lengths.max()), 4),
        "foliage_height_min_m": round(float(points[:, 2].min()), 4),
        "outer_crown_top_profile_m": profile, "outer_crown_height_range_m": round(max(profile) - min(profile), 4) if profile else 0,
        "sun_direction_blender": list(sun), "sunlit_paths": transmitted, "sample_count": len(samples),
        "sunlight_transmission": round(transmitted / len(samples), 4), "samples": samples}
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({"models": reports}, indent=2) + "\n")
print(json.dumps({key: {k: v for k, v in item.items() if k != "samples"} for key, item in reports.items()}))

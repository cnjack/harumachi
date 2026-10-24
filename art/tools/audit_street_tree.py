"""Measure the exported street tree's actual branch sections and pedestrian clearance.

Blender -b -P art/tools/audit_street_tree.py -- tree.glb report.json [--scale=.42]
The same checks deliberately reject the old courtyard tree at its street scale.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


def section_loops(objects, height, scale):
    """Intersect real mesh faces, then weld the resulting closed contours."""
    segments = []
    for obj in objects:
        obj.data.calc_loop_triangles()
        vertices = [obj.matrix_world @ vertex.co * scale for vertex in obj.data.vertices]
        for face in obj.data.loop_triangles:
            points = [vertices[index] for index in face.vertices]
            hits = []
            for first, second in zip(points, points[1:] + points[:1]):
                if (first.z < height <= second.z) or (second.z < height <= first.z):
                    hits.append(first.lerp(second, (height-first.z)/(second.z-first.z)))
            if len(hits) == 2 and (hits[0]-hits[1]).length > .000001:
                segments.append(hits)
    groups = []
    while segments:
        group = segments.pop()
        changed = True
        while changed:
            changed = False
            for index in range(len(segments)-1, -1, -1):
                line = segments[index]
                if any((point-end).length < .0015 for point in group for end in line):
                    group.extend(segments.pop(index))
                    changed = True
        low = Vector((min(p.x for p in group), min(p.y for p in group)))
        high = Vector((max(p.x for p in group), max(p.y for p in group)))
        groups.append({"centre": list((low+high)*.5), "diameter": max(high-low),
                       "width_xy": list(high-low)})
    return sorted(groups, key=lambda row: row["diameter"], reverse=True)


def measure(source, scale=1.0):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    trunks = [obj for obj in meshes if obj.name.startswith("Trunk")]
    leaves = [obj for obj in meshes if obj.name.startswith("Foliage")]
    points = [obj.matrix_world @ vertex.co * scale for obj in meshes for vertex in obj.data.vertices]
    foliage = [obj.matrix_world @ vertex.co * scale for obj in leaves for vertex in obj.data.vertices]
    low = Vector([min(p[axis] for p in points) for axis in range(3)])
    high = Vector([max(p[axis] for p in points) for axis in range(3)])
    sections = {str(height): section_loops(trunks, height, scale) for height in [.35, .6, 1.05, 1.4, 1.75, 2.05, 2.3]}
    diameter = lambda height: sections[str(height)][0]["diameter"] if sections[str(height)] else 0.0
    crown_low = min(p.z for p in foliage) if foliage else 0.0
    crown_width = max(max(p.x for p in foliage)-min(p.x for p in foliage), max(p.y for p in foliage)-min(p.y for p in foliage)) if foliage else 0.0
    bark_islands, open_edges = 0, 0
    for trunk in trunks:
        topology = bmesh.new()
        topology.from_mesh(trunk.data)
        bmesh.ops.remove_doubles(topology, verts=topology.verts[:], dist=.00001)
        open_edges += sum(edge.is_boundary for edge in topology.edges)
        remaining = set(topology.verts)
        while remaining:
            stack = [remaining.pop()]
            bark_islands += 1
            while stack:
                vertex = stack.pop()
                for edge in vertex.link_edges:
                    other = edge.other_vert(vertex)
                    if other in remaining:
                        remaining.remove(other)
                        stack.append(other)
        topology.free()
    facts = {"source": str(source), "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
             "scale": scale, "bounds_xyz_blender": [list(low), list(high)],
             "height_m": high.z-low.z, "crown_width_m": crown_width,
             "lowest_foliage_m": crown_low, "sections": sections,
             "bark_connected_components": bark_islands, "bark_boundary_edges": open_edges}
    facts["soil_contact_sections"] = {str(height): section_loops(trunks, height, scale) for height in [.008, .02, .04]}
    facts["bark_base_colors"] = [{"name": mat.name,
                                   "linear_rgba": list(mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value)}
                                  for obj in trunks for mat in obj.data.materials
                                  if mat and mat.use_nodes and mat.node_tree.nodes.get("Principled BSDF")]
    facts["checks"] = [
        {"name": "street tree stays between 3.0 and 3.65 metres", "passed": 3.0 <= high.z-low.z <= 3.65},
        {"name": "standing trunk is slender rather than a scaled heavy stump", "passed": .08 <= diameter(.6) <= .20},
        {"name": "main stem tapers by at least 18 percent before the fork", "passed": 0 < diameter(1.05) <= diameter(.35)*.82},
        {"name": "foliage clears the pedestrian head zone", "passed": crown_low >= 1.85},
        {"name": "crown spreads sideways instead of a narrow vertical topiary", "passed": crown_width >= 2.0 and crown_width/(high.z-low.z) >= .60},
        {"name": "separate forked branches cross the lower crown", "passed": len([row for row in sections["2.05"] if row["diameter"] > .012]) >= 3},
        {"name": "three dimensional roots meet the authored ground plane", "passed": abs(low.z) <= .003},
        {"name": "branch crotches form one connected closed bark surface", "passed": bark_islands == 1 and open_edges == 0},
    ]
    facts["passed"] = all(row["passed"] for row in facts["checks"])
    return facts


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--")+1:]
    source, target = Path(args[0]), Path(args[1])
    scale = next((float(item.split("=", 1)[1]) for item in args[2:] if item.startswith("--scale=")), 1.0)
    result = measure(source, scale)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, indent=2)+"\n")
    print(json.dumps({"passed": result["passed"], "height": result["height_m"],
                      "crown_width": result["crown_width_m"], "lowest_foliage": result["lowest_foliage_m"],
                      "checks": result["checks"]}, indent=2), flush=True)
    raise SystemExit(0 if result["passed"] else 1)

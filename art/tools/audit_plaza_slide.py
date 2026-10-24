"""Measure P05's real slide geometry, including the rejected predecessor.

Blender -b --factory-startup -P art/tools/audit_plaza_slide.py -- model.glb report.json
The tests ray-cast exported triangles, not vertex counts or authored metadata.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def geometry_tree(objects, role):
    vertices, triangles = [], []
    for obj in objects:
        obj.data.calc_loop_triangles()
        offset = len(vertices)
        vertices.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
        for triangle in obj.data.loop_triangles:
            material = obj.data.materials[triangle.material_index]
            if role(material.name):
                triangles.append(tuple(offset + index for index in triangle.vertices))
    return BVHTree.FromPolygons(vertices, triangles, all_triangles=True)


def cast(tree, origin, direction):
    point, normal, index, distance = tree.ray_cast(Vector(origin), Vector(direction), 20)
    return point


def top(tree, x, y, ceiling=4):
    point = cast(tree, (x, y, ceiling), (0, 0, -1))
    return point.z if point is not None else None


def inside(tree, position):
    direction = Vector((.927, .213, .308)).normalized()
    cursor = Vector(position)
    winding = 0
    for _ in range(100):
        point, normal, index, distance = tree.ray_cast(cursor, direction, 20)
        if point is None:
            # Joined frame members overlap at mortises. Signed crossings accept
            # that solid union; an odd/even test wrongly calls double wood empty.
            return abs(winding) >= 1
        winding += 1 if normal.dot(direction) > 0 else -1
        cursor = point + direction * .00003
    return False


def audit(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    points = [obj.matrix_world @ vertex.co for obj in objects for vertex in obj.data.vertices]
    low = [min(point[axis] for point in points) for axis in range(3)]
    high = [max(point[axis] for point in points) for axis in range(3)]
    blue = geometry_tree(objects, lambda name: name.startswith('SlideIndigoBlue'))
    wood = geometry_tree(objects, lambda name: name.startswith('CedarAge_'))
    complete = geometry_tree(objects, lambda name: True)

    # Measured surface tangents. Merely subdividing a straight plane does not
    # change these values, nor do smooth-shading normals hide a sharp join.
    ys = [-.26 - index * .005 for index in range(347)]
    heights = [top(blue, 0, y) for y in ys]
    tangents = [math.degrees(math.atan2(a - b, .005))
                for a, b in zip(heights[:-1], heights[1:])
                if a is not None and b is not None]
    tangent_jumps = [abs(a - b) for a, b in zip(tangents[:-1], tangents[1:])]
    buffer_heights = [top(blue, 0, -1.74 - index * .01) for index in range(24)]
    buffer_rise = max(buffer_heights) - min(buffer_heights)
    rim_sections = []
    for y in (-.60, -1.05, -1.55):
        floor = top(blue, 0, y)
        for side in (-1, 1):
            section = [(abs(side * (.39 + index * .0005)),
                        top(blue, side * (.39 + index * .0005), y))
                       for index in range(280)]
            section = [(x, z) for x, z in section if z is not None]
            crest = max(z for x, z in section)
            crown = [x for x, z in section if z >= crest - .012]
            rim_sections.append({'y': y, 'side': side, 'rise_m': crest - floor,
                                 'rounded_crown_width_m': max(crown) - min(crown)})

    # All six useful tread tops must be exposed behind the deck. Measure the
    # centre of each plateau, then require wood at the two load-bearing ends.
    plateaus = {}
    for index in range(139):
        y = .72 + index * .005
        z = top(wood, 0, y, 1.64)
        if z is not None and .18 <= z <= 1.62:
            # Avoid splitting a perfectly flat .765 m tread across .76/.77 due
            # to exported floating-point noise; use a 6 mm surface cluster.
            key = next((level for level in plateaus if abs(level-z)<.006), z)
            plateaus.setdefault(key, []).append(y)
    plateau_rows = sorted([(round(z,4), sum(positions) / len(positions), len(positions) * .005)
                           for z, positions in plateaus.items() if len(positions) >= 5])
    side_connections = []
    for z, y, depth in plateau_rows:
        for side in (-1, 1):
            connection = top(wood, side * .54, y, 1.64)
            # A broad tread alone must not satisfy this test: require a second
            # load-bearing member 105 mm below its top, beyond its 80 mm depth.
            underneath = inside(wood, (side*.54,y-.07,z-.105))
            side_connections.append({'step_z': z, 'side': side, 'y': y,
                                     'joint_z': connection,
                                     'stringer_below_tread': underneath,
                                     'connected': connection is not None and abs(connection-z) < .045 and underneath})
    deck_bearers = [inside(wood, (x, y, 1.59)) for x in (-.40, .40) for y in (-.18, .59)]
    side_guard = [inside(wood, (x, y, 1.89)) for x in (-.66, .66) for y in (-.05, .23, .49)]
    braces = [inside(wood, (x, .20, .95)) for x in (-.66, .66)]
    ladder_ground = [cast(wood, (x,1.34,-.1),(0,0,1)) for x in (-.54,.54)]
    obstructions = []
    for x in (-.30,0,.30):
        for index in range(100):
            y = -.31-index*.0167
            bed = top(blue,x,y)
            surface = top(complete,x,y)
            if surface-bed > .004:
                obstructions.append([x,y,surface-bed])
    shell_thickness = []
    for y in (-.50, -1.0, -1.90):
        upper, normal, index, distance = blue.ray_cast(Vector((0,y,4)),Vector((0,0,-1)),20)
        normal = normal if normal.z > 0 else -normal
        lower = cast(blue,upper-normal*.0001,-normal)
        shell_thickness.append((upper-lower).length if lower is not None else 0)
    checks = {
        'preserves_original_footprint_and_platform_height':
            1.40 <= high[0]-low[0] <= 1.46 and 3.38 <= high[1]-low[1] <= 3.46
            and 2.09 <= high[2] <= 2.15 and abs(low[2]) < .002,
        'continuous_ramp_tangents_no_coarse_kinks': bool(tangent_jumps) and max(tangent_jumps) <= 3.8,
        'buffer_exit_has_at_least_23cm_near_horizontal_surface': buffer_rise <= .006,
        'rolled_edge_has_actual_wide_rounded_crown': all(row['rounded_crown_width_m'] >= .039 for row in rim_sections),
        'sidewalls_remain_above_sliding_bed': all(.11 <= row['rise_m'] <= .21 for row in rim_sections),
        'closed_slide_sheet_has_real_thickness': all(.014 <= thickness <= .024 for thickness in shell_thickness),
        'six_exposed_regular_treads': len(plateau_rows) == 6 and all(.22 <= b[0]-a[0] <= .27 for a,b in zip(plateau_rows[:-1], plateau_rows[1:])),
        'every_tread_connects_to_both_ladder_stringers': len(side_connections) == 12 and all(row['connected'] for row in side_connections),
        'platform_has_four_real_bearing_contacts': all(deck_bearers),
        'platform_side_guards_have_geometry_below_handrail': all(side_guard),
        'platform_frame_has_diagonal_support_on_both_sides': all(braces),
        'sliding_bed_is_clear_of_supports_and_fasteners': not obstructions,
        'both_ladder_feet_are_grounded': all(point is not None and abs(point.z)<.002 for point in ladder_ground),
    }
    return {'model': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'passed': all(checks.values()), 'checks': checks,
            'measurements': {'blender_bounds_min': low, 'blender_bounds_max': high,
                             'max_tangent_jump_degrees_per_5mm': max(tangent_jumps),
                             'steepest_slope_degrees': max(tangents), 'exit_buffer_rise_m': buffer_rise,
                             'rim_cross_sections': rim_sections, 'tread_plateaus_z_y_depth_m': plateau_rows,
                             'tread_stringer_connections': side_connections,
                             'deck_bearing_probe_occupancy': deck_bearers,
                             'side_guard_probe_occupancy': side_guard,
                             'diagonal_brace_probe_occupancy': braces,
                             'sliding_bed_obstructions': obstructions,
                             'ladder_ground_height_m':[point.z if point is not None else None for point in ladder_ground],
                             'shell_thickness_m': shell_thickness}}


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--')+1:]
    result = audit(Path(args[0]).resolve())
    output = Path(args[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({'passed': result['passed'], 'checks': result['checks']}, ensure_ascii=False))
    if not result['passed']:
        sys.exit(1)

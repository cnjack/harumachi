"""Measure the actual freezer shell, transparent aperture and recessed stock.

Blender -b --factory-startup -P art/tools/audit_ice_freezer.py -- model.glb report.json
The same checks intentionally fail the old solid box with its flat product image.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def audit(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    all_points = [obj.matrix_world @ vert.co for obj in meshes for vert in obj.data.vertices]
    low = Vector(tuple(min(point[i] for point in all_points) for i in range(3)))
    high = Vector(tuple(max(point[i] for point in all_points) for i in range(3)))
    triangles = []
    glass_objects = []
    product_objects = []
    for obj in meshes:
        obj.data.calc_loop_triangles()
        if obj.name.startswith('Stock_'):
            product_objects.append(obj)
        for tri in obj.data.loop_triangles:
            material = obj.data.materials[tri.material_index]
            bsdf = material.node_tree.nodes.get('Principled BSDF') if material.use_nodes else None
            alpha = bsdf.inputs['Alpha'].default_value if bsdf else 1.0
            points = [obj.matrix_world @ obj.data.vertices[index].co for index in tri.vertices]
            cross = (points[1] - points[0]).cross(points[2] - points[0])
            # Count upward-facing projection once, not both sides of a solid rail.
            triangles.append((points, alpha, max(cross.z, 0) * .5, material.name))
        if any(mat.name == 'freezer_glass' for mat in obj.data.materials):
            glass_objects.append(obj)
    transparent_aperture = sum(area for points, alpha, area, role in triangles
                               if alpha <= .16 and min(p.z for p in points) > .80)
    opaque_roof = sum(area for points, alpha, area, role in triangles
                      if alpha >= .95 and min(p.z for p in points) >= .79)

    def top_hit(x, y, transparent=False):
        hits = []
        for points, alpha, area, role in triangles:
            if not transparent and alpha < .95:
                continue
            a, b, c = points
            denominator = (b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y)
            if abs(denominator) < 1e-9:
                continue
            first = ((b.y-c.y)*(x-c.x)+(c.x-b.x)*(y-c.y))/denominator
            second = ((c.y-a.y)*(x-c.x)+(a.x-c.x)*(y-c.y))/denominator
            third = 1-first-second
            if min(first,second,third) >= -1e-6:
                hits.append((first*a.z+second*b.z+third*c.z, role))
        return max(hits, default=(-1, 'none'))

    # These rays lie in the real open central aisle between all four baskets.
    # A solid body or an opaque lid picture hits around .82 m; the inner floor is .44 m.
    floor_hits = [top_hit(x, 0.0) for x in [-.42, -.22, .22, .42]]
    aperture_rays = [top_hit(-.55+column*1.10/15, -.245+row*.49/7)[0]
                     for column in range(16) for row in range(8)]
    opaque_roof_fraction = sum(height >= .79 for height in aperture_rays)/len(aperture_rays)
    product_bounds = []
    for obj in product_objects:
        points = [obj.matrix_world @ vert.co for vert in obj.data.vertices]
        product_bounds.append([min(p.z for p in points), max(p.z for p in points)])
    glass_height = min((min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
                        for obj in glass_objects), default=-1)
    stock_hits = [top_hit(x,y) for x,y in [(-.45,-.15),(-.25,-.15),(-.45,.15),(-.25,.15),(.24,-.15),(.50,.15)]]
    checks = {
        'preserves_footprint_and_height': 1.28 <= high.x-low.x <= 1.34 and .70 <= high.y-low.y <= .76 and .85 <= high.z-low.z <= .91,
        'standing_base_is_zero': abs(low.z) < .002,
        'two_actual_separate_transparent_lids': len(glass_objects) == 2 and transparent_aperture >= .54,
        'no_opaque_roof_or_top_photo': opaque_roof_fraction <= .15 and not any(role == 'icecream' for _,_,_,role in triangles),
        'open_inner_cavity_at_least_30cm_deep': all(.40 <= height <= .48 for height,role in floor_hits) and glass_height - max(h[0] for h in floor_hits) >= .30,
        'solid_packages_recessed_below_sliding_glass': len(product_bounds) >= 12 and all(top-bottom >= .045 and glass_height-top >= .10 for bottom,top in product_bounds),
        'products_have_visible_relief_above_inner_floor': all(.53 <= height <= .73 for height,role in stock_hits),
        'no_emissive_product_poster': not any(mat.use_nodes and any(node.type == 'TEX_IMAGE' for node in mat.node_tree.nodes)
                                              for mat in bpy.data.materials),
    }
    return {'model': str(path), 'passed': all(checks.values()), 'checks': checks,
            'measurements': {'blender_bounds_min': list(low), 'blender_bounds_max': list(high),
                             'transparent_aperture_m2': transparent_aperture, 'opaque_roof_projected_m2': opaque_roof,
                             'opaque_roof_fraction_of_inner_aperture': opaque_roof_fraction,
                             'inner_floor_rays': floor_hits, 'glass_height_m': glass_height,
                             'stock_height_ranges_m': product_bounds, 'stock_rays': stock_hits,
                             'triangles': len(triangles)}}


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--')+1:]
    report = audit(Path(args[0]).resolve())
    Path(args[1]).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'passed':report['passed'],'checks':report['checks']},ensure_ascii=False))
    if not report['passed']:
        sys.exit(1)

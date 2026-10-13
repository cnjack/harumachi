"""Measured, offline repairs of individually rejected provider prop structures.

The raw A/B meshes remain intact. Rebuilt parts are recorded in ready provenance.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector


def bounds(ob):
    p = np.asarray([v.co[:] for v in ob.data.vertices])
    return p.min(axis=0), p.max(axis=0)


def material(name, colour):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bs = mat.node_tree.nodes['Principled BSDF']
    bs.inputs['Base Color'].default_value = (*colour, 1)
    bs.inputs['Roughness'].default_value = 1
    bs.inputs['Specular IOR Level'].default_value = 0
    return mat


def keep_colours(ob, predicate, region=None):
    atlas = next(n.image for m in ob.data.materials if m and m.use_nodes
                 for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image
                 and 'diffuse' in n.image.name.lower())
    pixels = np.empty(len(atlas.pixels), dtype=np.float32)
    atlas.pixels.foreach_get(pixels)
    pixels = pixels.reshape(atlas.size[1], atlas.size[0], 4)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    uv_layer = bm.loops.layers.uv.active
    reject = []
    for face in bm.faces:
        uv = sum((l[uv_layer].uv for l in face.loops), Vector((0, 0))) / len(face.loops)
        x = min(atlas.size[0] - 1, max(0, int(uv.x * atlas.size[0])))
        y = min(atlas.size[1] - 1, max(0, int(uv.y * atlas.size[1])))
        if not predicate(*pixels[y, x, :3]) or (region is not None and not region(face.calc_center_median())):
            reject.append(face)
    bmesh.ops.delete(bm, geom=reject, context='FACES')
    unused = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=unused, context='VERTS')
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    return len(reject)


def join(model, parts):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in [model] + parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = model
    bpy.ops.object.join()


def solid_path(name, points, width, depth, mat, closed=False):
    """A rectangular strip with actual thickness, rather than an opaque card."""
    pts = [Vector(p) for p in points]
    verts, faces = [], []
    for i, p in enumerate(pts):
        before = pts[(i - 1) % len(pts)] if closed or i else p
        after = pts[(i + 1) % len(pts)] if closed or i < len(pts) - 1 else p
        tangent = (after - before).normalized()
        reference = Vector((0, 0, 1))
        if abs(tangent.dot(reference)) > .95:
            reference = Vector((0, 1, 0))
        wide = tangent.cross(reference).normalized() * width * .5
        thick = tangent.cross(wide).normalized() * depth * .5
        verts.extend([p + wide + thick, p - wide + thick, p - wide - thick, p + wide - thick])
    for i in range(len(pts) if closed else len(pts) - 1):
        j = (i + 1) % len(pts)
        for k in range(4):
            faces.append((i * 4 + k, i * 4 + (k + 1) % 4, j * 4 + (k + 1) % 4, j * 4 + k))
    if not closed:
        faces += [(3, 2, 1, 0), tuple((len(pts) - 1) * 4 + k for k in range(4))]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    return ob


def box(name, size, at, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    ob = bpy.context.object
    ob.name = name
    ob.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(mat)
    return ob


def basket(model, aid):
    lo, hi = bounds(model)
    size, centre = hi - lo, (lo + hi) * .5
    sewing = aid == 'N05_sewing_basket'
    empty = aid == 'N09_shopping_basket'
    if empty:
        removed = len(model.data.polygons)
        model.data.clear_geometry()
    elif sewing:
        removed = keep_colours(model, lambda r, g, b: b > g * 1.15 or r > g * 1.65
                               or (g > r * .85 and b > g * .78))
    else:
        removed = keep_colours(model, lambda r, g, b: r > g * 1.65 or b > g * 1.15
                               or g > r * 1.05 or (r > g * .9 and g > b * 2.8))
    wood = material('Basket_bamboo_honey', (.54, .32, .13))
    light = material('Basket_bamboo_light', (.68, .45, .23))
    parts = []
    a, b = size[0] * .51, size[1] * .51
    height = size[2] * (.45 if sewing else .55)
    z0 = lo[2]
    # Regular tapered bands and uprights, with physical rectangular air gaps.
    band = height * .105
    for row in range(6):
        t = row / 5
        factor = .82 + .18 * t
        z = z0 + band * .5 + t * (height - band)
        pts = [(centre[0] + a * factor * math.cos(q), centre[1] + b * factor * math.sin(q), z)
               for q in np.linspace(0, 2 * math.pi, 48, endpoint=False)]
        # Horizontal path's cross-section width lies radially; depth is vertical.
        parts.append(solid_path('Basket_horizontal_%02d' % row, pts, band * .38, band,
                                light if row in [0, 5] else wood, True))
    for column in range(24):
        q = column * 2 * math.pi / 24
        pts = []
        for row in range(7):
            t = row / 6
            # Small alternating offset describes weave without noisy texture.
            factor = .82 + .18 * t + (.007 if row % 2 else -.007)
            pts.append((centre[0] + a * factor * math.cos(q), centre[1] + b * factor * math.sin(q),
                        z0 + band * .25 + t * (height - band * .5)))
        parts.append(solid_path('Basket_upright_%02d' % column, pts, min(a, b) * .065,
                                min(a, b) * .025, light if column % 3 else wood))
    # Closed load-bearing bottom with a restrained 48-sided outline.
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=1, depth=band * .5,
                                       location=(centre[0], centre[1], z0 + band * .25))
    bottom = bpy.context.object
    bottom.name = 'Basket_solid_bottom'
    bottom.scale = (a * .82, b * .82, 1)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bottom.data.materials.append(wood)
    parts.append(bottom)
    if sewing:
        # Hinged lid stands at the back; a simple regular lattice has real holes.
        back = centre[1] + b
        for i in range(9):
            x = -a + 2 * a * i / 8
            span = b * math.sqrt(max(0, 1 - (x / a) ** 2))
            pts = [(centre[0] + x, back + v * .22, z0 + height + (v + b) * .9)
                   for v in [-span, span]]
            parts.append(solid_path('Lid_vertical_%02d' % i, pts, a * .07, band * .45, light))
        for i in range(7):
            v = -b + 2 * b * i / 6
            span = a * math.sqrt(max(0, 1 - (v / b) ** 2))
            pts = [(centre[0] + x, back + v * .22, z0 + height + (v + b) * .9)
                   for x in [-span, span]]
            parts.append(solid_path('Lid_horizontal_%02d' % i, pts, band * .65, band * .45, wood))
        outline = [(centre[0] + a * math.cos(q), back + b * math.sin(q) * .22,
                    z0 + height + (b * math.sin(q) + b) * .9)
                   for q in np.linspace(0, 2 * math.pi, 48, endpoint=False)]
        parts.append(solid_path('Lid_closed_frame', outline, band, band * .7, light, True))
    else:
        # One harvest bail, two shopping bails, securely anchored to the rim.
        for handle in range(2 if empty else 1):
            yy = centre[1] + ((-1 if handle == 0 else 1) * b * .72 if empty else 0)
            half_width = a * (math.sqrt(1 - .72 ** 2) if empty else .98)
            pts = [(centre[0] + half_width * math.cos(q), yy,
                    z0 + height * .95 + size[2] * .45 * math.sin(q))
                   for q in np.linspace(0, math.pi, 33)]
            parts.append(solid_path('Basket_handle_%d' % handle, pts, band * .75, band * .65, light))
    join(model, parts)
    return dict(kind='regular_physical_woven_basket', removed_faces=removed,
                retained=('provider cloth and thread spools with original UVs' if sewing else
                          'provider harvested fruit and vegetables with original UVs' if not empty else
                          'measured oval silhouette and intended dimensions only; defective source shell rejected'),
                rebuilt='24 upright strips, six separate elliptical bands, solid bottom and anchored handle/lid',
                method='matte 3D bamboo strips with real gaps; no painted or randomly torn holes')


def radish_crate(model):
    lo, hi = bounds(model)
    size, centre = hi - lo, (lo + hi) * .5
    removed = keep_colours(model, lambda r, g, b: g > r * 1.03 or (b > r * .75 and g > r * .78))
    # Fit retained vegetables inside the measured wall footprint as a group.
    p_lo, p_hi = bounds(model)
    inset = min(size[:2]) * .075
    factor = min(1., (size[0] - 2 * inset) / (p_hi[0] - p_lo[0]),
                 (size[1] - 2 * inset) / (p_hi[1] - p_lo[1]))
    p_centre = (p_lo + p_hi) * .5
    for vertex in model.data.vertices:
        vertex.co = Vector((np.asarray(vertex.co) - p_centre) * factor + p_centre)
        vertex.co.x += centre[0] - p_centre[0]
        vertex.co.y += centre[1] - p_centre[1]
    # Preserve a solid floor beneath the actual produce, not beneath stray leaves.
    p_lo, _ = bounds(model)
    wall = inset * .55
    z0 = min(lo[2], p_lo[2] - wall)
    h = size[2] * .46
    mat = material('Diversity_clean_cedar', (.58, .37, .20))
    parts = [box('Daikon_crate_bottom', (size[0], size[1], wall),
                 (centre[0], centre[1], z0 + wall / 2), mat)]
    for sx in [-1, 1]:
        for sy in [-1, 1]:
            parts.append(box('Daikon_crate_corner', (wall, wall, h),
                             (centre[0] + sx * (size[0] - wall) / 2,
                              centre[1] + sy * (size[1] - wall) / 2, z0 + h / 2), mat))
    for row in range(3):
        z = z0 + h * (.16 + row * .32)
        for sign in [-1, 1]:
            parts.append(box('Daikon_crate_rail', (size[0] - wall, wall, h * .24),
                             (centre[0], centre[1] + sign * (size[1] - wall) / 2, z), mat))
            if row == 2:
                span = size[1] * .32
                for side in [-1, 1]:
                    parts.append(box('Daikon_crate_hand_cheek', (wall, span, h * .24),
                                     (centre[0] + sign * (size[0] - wall) / 2,
                                      centre[1] + side * size[1] * .31, z), mat))
                parts.append(box('Daikon_crate_hand_lip', (wall, size[1] * .30, h * .065),
                                 (centre[0] + sign * (size[0] - wall) / 2, centre[1], z + h * .09), mat))
            else:
                parts.append(box('Daikon_crate_end', (wall, size[1] - wall, h * .24),
                                 (centre[0] + sign * (size[0] - wall) / 2, centre[1], z), mat))
    join(model, parts)
    return dict(kind='straight_daikon_crate', removed_timber_faces=removed, produce_uniform_scale=factor,
                retained='white radish bodies and green leaves with original UVs',
                rebuilt='closed bottom, straight slats and true side hand holes with produce inside wall inset')


def paper_net_tray(model):
    lo, hi = bounds(model)
    size, centre = hi - lo, (lo + hi) * .5
    mat = material('Paper_net_tray_pale_blue', (.48, .68, .80))
    a, b = size[0] * .56, size[1] * .60
    rim_h = max(size[:2]) * .025
    parts = []
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=1, depth=rim_h * .3,
                                       location=(centre[0], centre[1], lo[2] - rim_h * .25))
    bottom = bpy.context.object
    bottom.name = 'Net_tray_closed_bottom'
    bottom.scale = (a, b, 1)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bottom.data.materials.append(mat)
    parts.append(bottom)
    pts = [(centre[0] + a * math.cos(q), centre[1] + b * math.sin(q), lo[2] + rim_h * .25)
           for q in np.linspace(0, 2 * math.pi, 64, endpoint=False)]
    parts.append(solid_path('Net_tray_continuous_rim', pts, rim_h * .6, rim_h, mat, True))
    join(model, parts)
    return dict(kind='omitted_paper_net_tray_restored', retained='all three generated coloured paper scoops and UVs',
                added='pale blue elliptical tray with actual solid bottom and continuous raised rim')


def potting_bench(model):
    """Keep generated accessories; rebuild timber to the existing gameplay envelope."""
    lo, hi = bounds(model)
    height = float(hi[2] - lo[2])
    model.data.transform(Matrix.Scale(1.9 / height, 4) @
                         Matrix.Translation(Vector((-(lo[0] + hi[0]) / 2,
                                                    -(lo[1] + hi[1]) / 2, -lo[2]))))
    parts = []
    definitions = [
        ('Terracotta_pot', lambda r, g, b: r > g * 1.5,
         lambda p: p.z > .9 and p.x < -.3, (-.96, -.17, 1.03)),
        ('Trowel_blade', lambda r, g, b: b > r * .8 and g > r * .9,
         lambda p: p.z > 1.1 and p.x > .4, (.94, .51, 1.35)),
    ]
    retained = {}
    for name, colour, region, at in definitions:
        ob = model.copy()
        ob.data = model.data.copy()
        bpy.context.collection.objects.link(ob)
        ob.name = name
        keep_colours(ob, colour, region)
        # Colour separation also catches scraps of the old timber. Weld UV
        # seams before keeping the single complete accessory component.
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.0003)
        unseen, components = set(bm.verts), []
        while unseen:
            stack, component = [unseen.pop()], set()
            while stack:
                vertex = stack.pop()
                component.add(vertex)
                for edge in vertex.link_edges:
                    other = edge.other_vert(vertex)
                    if other in unseen:
                        unseen.remove(other)
                        stack.append(other)
            area = sum(f.calc_area() for f in {f for v in component for f in v.link_faces})
            components.append((area, component))
        keep = max(components, key=lambda item: item[0])[1]
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v not in keep], context='VERTS')
        bm.to_mesh(ob.data)
        bm.free()
        if len(ob.data.polygons) < 30:
            raise RuntimeError('P08: missing reviewed accessory ' + name)
        low, high = bounds(ob)
        centre = (low + high) / 2
        ob.data.transform(Matrix.Translation(Vector((at[0] - centre[0], at[1] - centre[1], at[2] - low[2]))))
        retained[name] = len(ob.data.polygons)
        parts.append(ob)
    model.data.clear_geometry()
    wood = material('Diversity_clean_cedar', (.58, .37, .20))
    width, depth, worktop = 2.8068, 1.4048, 1.03
    parts.append(box('Level_worktop', (width, depth, .08), (0, 0, worktop - .04), wood))
    for sx in [-1, 1]:
        for sy in [-1, 1]:
            parts.append(box('Bench_leg', (.13, .13, worktop - .08),
                             (sx * (width - .15) / 2, sy * (depth - .15) / 2, (worktop - .08) / 2), wood))
    parts.append(box('Lower_shelf', (width - .16, depth - .16, .05), (0, 0, .30), wood))
    tray = material('Seed_tray_slate', (.12, .20, .16))
    soil = material('Seed_tray_soil', (.20, .12, .065))
    parts.append(box('Seed_tray_base', (.40, .28, .025), (-.85, -.05, .3375), tray))
    for sx in [-1, 1]:
        parts.append(box('Seed_tray_rim', (.018, .28, .065), (-.85 + sx * .191, -.05, .365), tray))
    for sy in [-1, 1]:
        parts.append(box('Seed_tray_rim', (.40, .018, .065), (-.85, -.05 + sy * .131, .365), tray))
    for x in range(4):
        for y in range(2):
            parts.append(box('Seed_tray_cell', (.077, .10, .025), (-.85 + (x - 1.5) * .093, -.05 + (y - .5) * .12, .3625), soil))
    for sx in [-1, 1]:
        parts.append(box('Back_upright', (.12, .12, 1.9),
                         (sx * (width - .12) / 2, (depth - .12) / 2, .95), wood))
    parts.append(box('Back_header', (width, .12, .10), (0, (depth - .12) / 2, 1.85), wood))
    # Restore the wooden grip omitted by colour separation, keeping the generated blade.
    parts.append(box('Trowel_grip', (.035, .035, .19), (.94, .51, 1.62), wood))
    cord = material('Tool_hanging_cord', (.30, .22, .13))
    parts.append(solid_path('Trowel_hanging_loop', [(.94, .51, 1.715), (.94, .64, 1.80),
                                                  (.94, .67, 1.715)], .012, .012, cord))
    join(model, parts)
    return dict(kind='potting_bench_gameplay_envelope',
                retained='generated complete terracotta pot and metal trowel blade with their original UVs; colour-separated timber scraps discarded',
                retained_faces=retained,
                rebuilt='straight timber top, shelf, four legs and open back rail; real hanging grip/cord; lower eight-cell seed tray with solid base and rims',
                footprint_m=[width, depth], height_m=1.9, worktop_m=worktop,
                reason='restore the original measured footprint, E approaches and 0.9–1.1m working height; no test tolerance changes')


def repair(model, aid):
    if aid == 'P08':
        return potting_bench(model)
    if aid in ['N05_sewing_basket', 'N09_shopping_basket', 'N18_harvest_basket']:
        return basket(model, aid)
    if aid == 'N11_daikon_crate':
        return radish_crate(model)
    if aid == 'N23_goldfish_scoops':
        return paper_net_tray(model)
    if aid == 'N02_kyusu':
        lo, hi = bounds(model)
        # Reviewed B: the side handle points along -Y; the spout is along -X.
        pivot = lo[1] + (hi[1] - lo[1]) * .48
        changed = 0
        for vertex in model.data.vertices:
            if vertex.co.y < pivot:
                vertex.co.y = pivot + (vertex.co.y - pivot) * .55
                changed += 1
        return dict(kind='local_kyusu_handle_shortening', pivot_y=float(pivot), length_ratio=.55,
                    changed_vertices=changed, retained='body, lid and spout; original UVs')
    if aid == 'N21_tool_basket':
        # Full-resolution back view confirms the green dots are fingertip
        # patches on a complete white glove, not stray geometry. Keep it intact.
        return dict(kind='glove_back_review_no_geometry_change',
                    retained='whole generated wooden carrier, tools, white glove back and green fingertips with UVs',
                    observation='896-pixel back view confirms a complete glove; no debris removal or duplicate backing')
    if aid == 'N24_bamboo_lantern':
        paper = material('Lantern_warm_paper', (.94, .88, .69))
        bs = paper.node_tree.nodes['Principled BSDF']
        bs.inputs['Emission Color'].default_value = (1., .62, .23, 1)
        bs.inputs['Emission Strength'].default_value = .35
        model.data.materials.append(paper)
        slot = len(model.data.materials) - 1
        atlas = next(n.image for m in model.data.materials if m and m != paper and m.use_nodes
                     for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image
                     and 'diffuse' in n.image.name.lower())
        pixels = np.empty(len(atlas.pixels), dtype=np.float32)
        atlas.pixels.foreach_get(pixels)
        pixels = pixels.reshape(atlas.size[1], atlas.size[0], 4)
        uv = model.data.uv_layers.active
        selected = 0
        for face in model.data.polygons:
            u, v = np.mean([uv.data[i].uv[:] for i in face.loop_indices], axis=0)
            r, g, b = pixels[min(atlas.size[1] - 1, max(0, int(v * atlas.size[1]))),
                             min(atlas.size[0] - 1, max(0, int(u * atlas.size[0])))][:3]
            if min(r, g, b) > .55 and b > r * .75:
                face.material_index = slot
                selected += 1
        return dict(kind='separate_lantern_paper', paper_faces=selected,
                    retained='generated bamboo cage, handle, paper cylinder and UVs',
                    changed='warm emission on paper only; bamboo remains matte and unlit')
    return None

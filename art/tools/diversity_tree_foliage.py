"""Complete omitted summer foliage around retained Hyper3D trunks.

The generated originals stay intact. Each species uses a different crown habit
and a distinct cell in the shared, imagegen-authored transparent sprig atlas.
"""
import hashlib
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector


def complete_crown(model, aid, row, root):
    species = {'T07_summer_maple': (1, .35, .19, .62),
               'T08_green_cherry': (0, .38, .23, .68),
               'T10_weeping_willow': (2, .35, .28, .61),
               'T11_young_zelkova': (3, .23, .25, .73)}
    if aid not in species:
        return [model], None
    cell, reach, vertical, lower = species[aid]
    rng = random.Random(aid)
    low = Vector([min(v.co[k] for v in model.data.vertices) for k in range(3)])
    high = Vector([max(v.co[k] for v in model.data.vertices) for k in range(3)])
    height = row['size_m']
    model.data.transform(Matrix.Scale(height / (high.z - low.z), 4) @
                         Matrix.Translation(Vector((-(low.x + high.x) / 2, -(low.y + high.y) / 2, -low.z))))
    # Raw GLB vertices split at UV seams. Collapsing those disconnected seams
    # tears holes through the bark, visible in the native root close-ups.
    # Bark is flat-coloured here; weld coincident positions before reduction.
    before_vertices = len(model.data.vertices)
    bm = bmesh.new()
    bm.from_mesh(model.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=height * .000005)
    boundary = [edge for edge in bm.edges if edge.is_boundary]
    caps = bmesh.ops.holes_fill(bm, edges=boundary, sides=0) if boundary else {'faces': []}
    capped_faces = len(caps['faces'])
    seen, islands = set(), []
    for start in bm.verts:
        if start in seen:
            continue
        stack, faces = [start], set()
        seen.add(start)
        while stack:
            vertex = stack.pop()
            faces.update(vertex.link_faces)
            for edge in vertex.link_edges:
                other = edge.other_vert(vertex)
                if other not in seen:
                    seen.add(other)
                    stack.append(other)
        if faces:
            islands.append(faces)
    main_island = max(islands, key=lambda faces: sum(face.calc_area() for face in faces))
    removed_faces = [face for faces in islands if faces is not main_island for face in faces]
    removed_area = sum(face.calc_area() for face in removed_faces)
    total_area = sum(face.calc_area() for face in bm.faces)
    discarded_branches = max(0, len(islands) - 1)
    bmesh.ops.delete(bm, geom=removed_faces, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(model.data)
    bm.free()
    welded_vertices = len(model.data.vertices)
    bark = bpy.data.materials.new('Diversity_warm_tree_bark')
    bark.use_nodes = True
    bs = bark.node_tree.nodes['Principled BSDF']
    bs.inputs['Base Color'].default_value = (.24, .155, .09, 1)
    bs.inputs['Roughness'].default_value = 1
    bs.inputs['Specular IOR Level'].default_value = 0
    model.data.materials.clear()
    model.data.materials.append(bark)
    for face in model.data.polygons:
        face.material_index = 0
        face.use_smooth = True
    count = sum(len(p.vertices) - 2 for p in model.data.polygons)
    limit = int(row['triangle_budget'] * .46)
    if count > limit:
        bpy.context.view_layer.objects.active = model
        mod = model.modifiers.new('Budgeted_retained_bark', 'DECIMATE')
        mod.ratio = limit / count
        bpy.ops.object.modifier_apply(modifier=mod.name)
    model.name = 'Trunk_' + aid

    # Complete secondary branches into the crown's depth. Their joins start in
    # the retained generated trunk, rather than floating foliage around a pole.
    centres = []
    if cell == 2:
        for i in range(9):
            angle = math.tau * i / 9
            centres.append(Vector((math.cos(angle) * reach * height,
                                   math.sin(angle) * reach * height,
                                   height * (lower + rng.uniform(-.045, .12)))))
        centres.append(Vector((0, 0, height * .89)))
    else:
        for i in range(7):
            angle = math.tau * i / 7
            radius = reach * height * rng.uniform(.65, .95)
            centres.append(Vector((math.cos(angle) * radius, math.sin(angle) * radius,
                                   height * (lower + rng.uniform(-.04, .17)))))
        centres.append(Vector((0, 0, height * .9)))
    branch_vertices, branch_faces = [], []
    for centre in centres:
        start = Vector((0, 0, height * .48))
        mid = start.lerp(centre, .55)
        mid.z += height * .08
        points = [start, mid, centre]
        rings = []
        for i, point in enumerate(points):
            direction = (points[min(i + 1, 2)] - points[max(i - 1, 0)]).normalized()
            right = direction.cross(Vector((0, 0, 1)))
            if right.length < .01:
                right = Vector((1, 0, 0))
            right.normalize()
            up = direction.cross(right).normalized()
            radius = height * [.023, .013, .003][i]
            ring = []
            for side in range(10):
                angle = math.tau * side / 10
                ring.append(len(branch_vertices))
                branch_vertices.append(tuple(point + (right * math.cos(angle) + up * math.sin(angle)) * radius))
            rings.append(ring)
        for first, second in zip(rings, rings[1:]):
            for side in range(10):
                following = (side + 1) % 10
                branch_faces.append((first[side], first[following], second[following], second[side]))
        branch_faces.append(tuple(reversed(rings[0])))
        branch_faces.append(tuple(rings[-1]))
    mesh = bpy.data.meshes.new('Secondary_boughs_' + aid)
    mesh.from_pydata(branch_vertices, [], branch_faces)
    mesh.update()
    branches = bpy.data.objects.new('Trunk_Secondary_' + aid, mesh)
    bpy.context.collection.objects.link(branches)
    mesh.materials.append(bark)
    for face in mesh.polygons:
        face.use_smooth = True

    atlas_path = root / 'art/references/model_diversity_20261013/foliage_atlas.png'
    material = bpy.data.materials.new('Diversity_summer_sprigs')
    material.use_nodes = True
    bs = material.node_tree.nodes['Principled BSDF']
    bs.inputs['Roughness'].default_value = 1
    bs.inputs['Specular IOR Level'].default_value = 0
    tex = material.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(str(atlas_path))
    material.node_tree.links.new(tex.outputs['Color'], bs.inputs['Base Color'])
    material.node_tree.links.new(tex.outputs['Alpha'], bs.inputs['Alpha'])
    material.surface_render_method = 'DITHERED'
    material.use_backface_culling = False
    vertices, faces, uvs = [], [], []
    # UV V starts at the image bottom. Cells are authored top-left, top-right,
    # bottom-left, bottom-right; the centre seam has a transparent gutter.
    u0 = (cell % 2) * .5 + .007
    v0 = (1 - cell // 2) * .5 + .007
    for centre in centres:
        for index in range(42 if cell != 2 else 65):
            direction = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, .8))).normalized()
            radius = Vector((height * reach * .55, height * reach * .55, height * vertical * .65))
            position = centre + Vector((direction.x * radius.x, direction.y * radius.y, direction.z * radius.z)) * rng.uniform(.5, 1)
            if cell == 2:
                position.z -= height * rng.uniform(0, .20)
                normal = Vector((direction.x, direction.y, rng.uniform(-.1, .3))).normalized()
            else:
                normal = Vector((direction.x, direction.y, direction.z * .7 + .35)).normalized()
            right = normal.cross(Vector((0, 0, 1)))
            if right.length < .01:
                right = Vector((1, 0, 0))
            right.normalize()
            up = normal.cross(right).normalized()
            half_width = height * rng.uniform(.045, .065)
            half_height = half_width * (1.6 if cell == 2 else 1)
            first = len(vertices)
            for y in range(2):
                for x in range(3):
                    bend = half_width * .18 if x == 1 else 0
                    vertices.append(tuple(position + right * ((x - 1) * half_width)
                                          + up * ((y * 2 - 1) * half_height) + normal * bend))
                    uvs.append((u0 + x * .243, v0 + y * .486))
            faces.extend([(first, first + 1, first + 4, first + 3),
                          (first + 1, first + 2, first + 5, first + 4)])
    mesh = bpy.data.meshes.new('Curved_leaf_sprigs_' + aid)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    foliage = bpy.data.objects.new('Foliage_' + aid, mesh)
    bpy.context.collection.objects.link(foliage)
    mesh.materials.append(material)
    uv = mesh.uv_layers.new(name='SharedSprigAtlas')
    for polygon in mesh.polygons:
        for index in polygon.loop_indices:
            uv.data[index].uv = uvs[mesh.loops[index].vertex_index]
    objects = [model, branches, foliage]
    points = [vertex.co for ob in objects for vertex in ob.data.vertices]
    low = min(p.z for p in points)
    high = max(p.z for p in points)
    transform = Matrix.Scale(height / (high - low), 4) @ Matrix.Translation(Vector((0, 0, -low)))
    for ob in objects:
        ob.data.transform(transform)
    report = dict(kind='completed_omitted_summer_canopy',
                  retained='Hyper3D generated trunk and primary branch geometry',
                  added='secondary boughs and species-specific full-depth crown of curved alpha sprigs',
                  atlas=str(atlas_path.relative_to(root)), atlas_sha256=hashlib.sha256(atlas_path.read_bytes()).hexdigest(),
                  atlas_cell=cell, foliage_cards=len(faces) // 2,
                  final_height_m=height, material_cleanup='warm matte bark replaces green-painted bare branches',
                  bark_seam_vertices_before=before_vertices, bark_vertices_after_weld=welded_vertices,
                  bark_holes_capped=capped_faces,
                  disconnected_source_fragments_removed=discarded_branches,
                  disconnected_source_area_fraction=removed_area / max(total_area, 1e-12),
                  preserve_parts=True, note='Leaf sprigs use alpha cutouts; the tree has a complete three-dimensional branch/crown volume')
    return objects, report

"""Refine the existing serving stall and oven; no bitmap synthesis or rebake.

Blender -b --factory-startup -P art/tools/refine_stall_oven_20261011.py -- --draft
Blender -b --factory-startup -P art/tools/refine_stall_oven_20261011.py -- --build

The source copies are immutable metre-scale game exports. The stall keeps its
counter/frame. The oven retains its feet/base and complete upper flue; its
self-intersecting middle casing is rebuilt as a closed insulated cabinet with
two actual chambers, control compartments and through ventilation openings.
Imagegen supplies colour maps.
"""
import bpy
import bmesh
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / 'art/models/raw/material_refine_stall_oven_20261011'
TEXTURES = ROOT / 'game/assets/textures/material_refine_20261011'
EVIDENCE = ROOT / 'evidence/material_detail_review_20261011/stall-oven'
ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
DRAFT = '--draft' in ARGS
MATERIALS = {}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATERIALS.clear()


def material(name, color, texture=None, alpha=1, emission=0):
    if name in MATERIALS:
        return MATERIALS[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, alpha)
    mat.use_backface_culling = False
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = 1
    bsdf.inputs['Metallic'].default_value = 0
    bsdf.inputs['Specular IOR Level'].default_value = 0
    bsdf.inputs['Alpha'].default_value = alpha
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*color, 1)
        bsdf.inputs['Emission Strength'].default_value = emission
    if texture:
        path = TEXTURES / texture
        if path.exists():
            tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
            tex.image = bpy.data.images.load(str(path), check_existing=True)
            tex.image.pack()
            tex.extension = 'REPEAT'
            mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
        elif not DRAFT:
            raise FileNotFoundError(path)
    MATERIALS[name] = mat
    return mat


def cube(name, size, at, mat, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new('Small maintained edge', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(mat)
    planar_uv(obj)
    return obj


def planar_uv(obj, grain=False):
    """Metric projection per surface; posts and boards follow their long axis."""
    uv = obj.data.uv_layers.active or obj.data.uv_layers.new(name='UVMap')
    for face in obj.data.polygons:
        axis = max(range(3), key=lambda k: abs(face.normal[k]))
        for loop_id in face.loop_indices:
            p = obj.data.vertices[obj.data.loops[loop_id].vertex_index].co
            if grain:
                # Cedar map has its grain along V. Counter grain runs X;
                # standing posts run Z, without world-axis texture stretching.
                post = 'Rail' not in obj.name and (face.center.z > .84 or (face.center.z < .74 and abs(face.center.x) > 1.1 and abs(face.center.y) > .30))
                if post and axis == 2:
                    uv.data[loop_id].uv = (p.x * 2, p.y * 2)
                elif post:
                    uv.data[loop_id].uv = ((p.y if axis == 0 else p.x) * 1.8, p.z * .65)
                elif axis == 0:
                    uv.data[loop_id].uv = (p.y * 2, p.z * 2)
                else:
                    uv.data[loop_id].uv = ((p.y if axis == 2 else p.z) * 1.8, p.x * .65)
            elif axis == 0:
                uv.data[loop_id].uv = (p.y, p.z)
            elif axis == 1:
                uv.data[loop_id].uv = (p.x, p.z)
            else:
                uv.data[loop_id].uv = (p.x, p.y)


def tube(name, points, radius, mat, sides=6, cyclic=False):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 1
    curve.bevel_depth = radius
    curve.bevel_resolution = 0
    curve.use_fill_caps = True
    curve.resolution_u = 1
    spline = curve.splines.new('POLY')
    spline.points.add(len(points) - 1)
    for p, co in zip(spline.points, points):
        p.co = (*co, 1)
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')
    return obj


def cylinder(name, radius, depth, at, mat, axis='Z', vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=at)
    obj = bpy.context.object
    obj.name = name
    if axis == 'Y':
        obj.rotation_euler.x = math.pi / 2
    elif axis == 'X':
        obj.rotation_euler.y = math.pi / 2
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.materials.append(mat)
    bevel = obj.modifiers.new('Round machined edge', 'BEVEL')
    bevel.width = min(.0018, radius / 8)
    bevel.segments = 2
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    planar_uv(obj)
    return obj


def label(name, body, at, size, mat):
    curve = bpy.data.curves.new(name, 'FONT')
    curve.body = body
    curve.size = size
    curve.align_x = 'CENTER'
    curve.align_y = 'CENTER'
    curve.resolution_u = 3
    curve.extrude = .00008
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.location = at
    obj.rotation_euler.x = math.pi / 2
    obj.data.materials.append(mat)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')
    return obj


def merge(objects, name):
    if not objects:
        return None
    if len(objects) == 1:
        objects[0].name = name
        return objects[0]
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    return obj


def load_original(aid):
    path = RAW / (aid + '_input.glb')
    if not path.exists():
        shutil.copy2(ROOT / 'game/assets/models' / (aid + '.glb'), path)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    for obj in meshes:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        obj.data.transform(world)
    for obj in list(bpy.context.scene.objects):
        if obj.type != 'MESH':
            bpy.data.objects.remove(obj)
    return merge(meshes, aid + '_RetainedSource')


def cut(obj, point, normal):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    # Imported glTF UV/normal seams are duplicated vertices. Join coincident
    # geometry before cutting, preserving loop UVs; otherwise cap operators
    # see disconnected chains instead of the real cross-section perimeter.
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.000001)
    result = bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                                  plane_co=point, plane_no=normal, dist=.000001,
                                  clear_outer=True)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.000001)
    plane = Vector(point)
    axis = Vector(normal).normalized()
    edges = [edge for edge in bm.edges if edge.is_boundary and all(abs((v.co-plane).dot(axis))<.000003 for v in edge.verts)]
    if edges:
        # A hollow casing can have nested inner/outer cut loops. Scan-fill the
        # cross-section as an annulus; filling each loop as a separate ngon
        # creates overlapping cap disks and invalid Boolean volumes.
        bmesh.ops.triangle_fill(bm, edges=edges, use_beauty=True, normal=axis)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()


def union_solids(objects, name):
    """Join real contacting solids, with material transfer and no hidden links."""
    materials = []
    for obj in objects:
        for mat in obj.data.materials:
            if mat not in materials:
                materials.append(mat)
    for obj in objects:
        old = list(obj.data.materials)
        indices = [materials.index(old[poly.material_index]) for poly in obj.data.polygons]
        obj.data.materials.clear()
        for mat in materials:
            obj.data.materials.append(mat)
        for poly, index in zip(obj.data.polygons, indices):
            poly.material_index = index
    target = objects[0]
    for operand in objects[1:]:
        if name == 'Oven_OriginalBaseSideRearFlue':
            for debug in [target, operand]:
                measure = bmesh.new(); measure.from_mesh(debug.data)
                print('STRUCTURE_BEFORE_UNION',debug.name,'faces',len(measure.faces),'boundary',sum(edge.is_boundary for edge in measure.edges),'volume',measure.calc_volume(signed=True))
                measure.free()
        bpy.ops.object.select_all(action='DESELECT')
        target.select_set(True)
        bpy.context.view_layer.objects.active = target
        modifier = target.modifiers.new('Real mechanical joint', 'BOOLEAN')
        modifier.operation = 'UNION'
        modifier.solver = 'EXACT'
        modifier.object = operand
        if hasattr(modifier, 'material_mode'):
            modifier.material_mode = 'INDEX'
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        if not target.data.polygons:
            raise RuntimeError('Boolean removed complete structural shell')
        if name == 'Oven_ClosedPhysicalAssembly':
            debug=bmesh.new();debug.from_mesh(target.data)
            print('CORE_CONTACT_STEP',operand.name,'boundary',sum(edge.is_boundary for edge in debug.edges),'nonmanifold',sum(not edge.is_manifold for edge in debug.edges))
            debug.free()
        bpy.data.objects.remove(operand, do_unlink=True)
    target.name = name
    bm = bmesh.new(); bm.from_mesh(target.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.000001)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=.00000005)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if name == 'Oven_ClosedPhysicalAssembly':
        print('STRUCTURAL_CORE_TOPOLOGY', 'boundary',sum(edge.is_boundary for edge in bm.edges),
              'nonmanifold',sum(not edge.is_manifold for edge in bm.edges),
              'volume',bm.calc_volume(signed=True))
    bm.to_mesh(target.data); bm.free()
    target.data.validate(verbose=True, clean_customdata=False)
    return target


def split_render_materials(obj):
    """Material boundaries share exact positions; glass stays in two panes."""
    source = obj.data
    for index, mat in enumerate(list(source.materials)):
        groups = [0, 1] if mat.name == 'Oven_HeatGlass' else [None]
        for deck in groups:
            mesh = source.copy()
            bm = bmesh.new()
            bm.from_mesh(mesh)
            unwanted = [face for face in bm.faces if face.material_index != index or
                        (deck is not None and (0 if face.calc_center_median().z < 1.20 else 1) != deck)]
            bmesh.ops.delete(bm, geom=unwanted, context='FACES')
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
            if not bm.faces:
                bm.free()
                bpy.data.meshes.remove(mesh)
                continue
            for face in bm.faces:
                face.material_index = 0
            bm.to_mesh(mesh)
            bm.free()
            mesh.validate(verbose=True, clean_customdata=False)
            mesh.materials.clear()
            mesh.materials.append(mat)
            part = bpy.data.objects.new('Oven_Deck%d_Glass' % deck if deck is not None else mat.name + '_Geometry', mesh)
            bpy.context.collection.objects.link(part)
            part.matrix_world = obj.matrix_world.copy()
    bpy.data.objects.remove(obj, do_unlink=True)


def subtract_solid(target, cutter):
    materials = list(target.data.materials)
    old = list(cutter.data.materials)
    for mat in old:
        if mat not in materials:
            materials.append(mat)
    # Keep existing face material indices. Clearing the slots silently resets
    # every old face to index 0, erasing seals/cavity finish on later vent cuts.
    for mat in materials[len(target.data.materials):]:
        target.data.materials.append(mat)
    indices = [materials.index(old[face.material_index]) for face in cutter.data.polygons]
    cutter.data.materials.clear()
    for mat in materials:cutter.data.materials.append(mat)
    for face, index in zip(cutter.data.polygons, indices):face.material_index = index
    bpy.ops.object.select_all(action='DESELECT')
    target.select_set(True);bpy.context.view_layer.objects.active=target
    modifier=target.modifiers.new('Actual chamber or ventilation opening','BOOLEAN')
    modifier.operation='DIFFERENCE';modifier.solver='EXACT';modifier.object=cutter
    if hasattr(modifier,'material_mode'):modifier.material_mode='INDEX'
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter,do_unlink=True)
    if not target.data.polygons:raise RuntimeError('Cabinet subtraction removed complete body')


def assign_baking_floors(obj, material, heights):
    mats=list(obj.data.materials)
    if material not in mats:obj.data.materials.append(material);mats.append(material)
    index=mats.index(material)
    for face in obj.data.polygons:
        centre=obj.matrix_world@face.center
        normal=obj.matrix_world.to_3x3()@face.normal
        if normal.z>.9 and any(abs(centre.z-level)<.00001 for level in heights):face.material_index=index


def canopy_z(x, y):
    # Four-centimetre camber sheds rain front/back; millimetre-scale fabric
    # tension remains visible in grazing light without separate slat geometry.
    return 1.83303499 - .042 * (y / .49677181) ** 2 - .0020 * math.sin(math.pi * x / 1.3) ** 2 * math.sin(8 * math.pi * y / .99354362) ** 2


def build_stall():
    old = load_original('P09')
    cut(old, (0, 0, 1.776), (0, 0, 1))
    old.name = 'P09_OriginalCounterAndTimber'
    cedar = material('P09_Cedar_Maintained', (.64, .47, .30), 'cedar_weathered.png')
    old.data.materials.clear()
    old.data.materials.append(cedar)
    for face in old.data.polygons:
        face.material_index = 0
    planar_uv(old, grain=True)
    canvas = material('P09_BlueIvory_Canvas', (.45, .68, .78), 'canvas_blue_ivory.png')
    hem = material('P09_FoldedIvoryHem', (.80, .77, .66))
    rope = material('P09_LinenTie', (.63, .55, .40))
    dark = material('P09_JoineryIron', (.25, .29, .30))
    nx, ny = 64, 24
    verts = [(x, y, canopy_z(x, y)) for j in range(ny + 1) for i in range(nx + 1)
             for x, y in [(-1.3 + 2.6 * i / nx, -.49677181 + .99354362 * j / ny)]]
    faces = [(j * (nx + 1) + i, j * (nx + 1) + i + 1,
              (j + 1) * (nx + 1) + i + 1, (j + 1) * (nx + 1) + i)
             for j in range(ny) for i in range(nx)]
    # The valances share the roof edge vertices. One folded textile surface
    # gives a genuinely closed shell after solidify, without intersecting CSG
    # islands or sub-micrometre sliver triangles along the fold.
    for sign in [-1, 1]:
        row = 0 if sign < 0 else ny
        lower = len(verts)
        for i in range(nx + 1):
            x = -1.3 + 2.6 * i / nx
            y = sign * .49677181
            verts.append((x, y, canopy_z(x,y) - .037 - .0015 * math.sin(i*.8)))
        for i in range(nx):
            top = row*(nx+1)+i
            faces.append((lower+i,lower+i+1,top+1,top) if sign < 0 else
                         (top,top+1,lower+i+1,lower+i))
    mesh = bpy.data.meshes.new('Continuous tensioned canvas')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new('P09_ContinuousCanvas', mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(canvas)
    uv = mesh.uv_layers.new(name='UVMap')
    for face in mesh.polygons:
        face.use_smooth = True
        for loop_id in face.loop_indices:
            point = mesh.vertices[mesh.loops[loop_id].vertex_index].co
            uv.data[loop_id].uv = ((point.x + 1.3) / 2.6, (point.y + .49677181) / .99354362)
    bpy.context.view_layer.objects.active = obj
    solid = obj.modifiers.new('Three millimetre cloth fold thickness', 'SOLIDIFY')
    solid.thickness = .003
    solid.offset = -1
    bpy.ops.object.modifier_apply(modifier=solid.name)
    stitches = []
    bindings = []
    for sign in [-1, 1]:
        y = sign * .484
        pts = [(x, y, canopy_z(x, y) - .0015) for i in range(65) for x in [-1.286 + 2.572 * i / 64]]
        bindings.append(tube('Folded long hem', pts, .0032, hem))
        for i in range(63):
            x = -1.25 + i * .04
            stitches.append(tube('Short hem stitch', [(x, y - sign * .006, canopy_z(x, y) + .0007), (x + .009, y - sign * .006, canopy_z(x + .009, y) + .0007)], .00075, hem))
    for sign in [-1, 1]:
        x = sign * 1.285
        pts = [(x, y, canopy_z(x, y) - .0018) for i in range(25) for y in [-.482 + .964 * i / 24]]
        bindings.append(tube('Folded end hem', pts, .003, hem))
    merge(stitches, 'P09_HemStitches')
    merge(bindings, 'P09_FoldedHem')
    ties, pegs = [], []
    for sx in [-1, 1]:
        for sy in [-1, 1]:
            x, y = sx * 1.225, sy * .39
            # Post lashings sit inside the original footprint and below roof.
            ties.append(tube('Canopy corner tie', [(sx * 1.274, sy * .474, 1.789), (x, y, 1.744), (x + .024, y, 1.727), (x, y - .026, 1.716)], .0034, rope))
            for z in [1.717, 1.729, 1.741]:
                ties.append(tube('Post rope turn', [(x - .032, y - .032, z), (x + .032, y - .032, z + .002), (x + .032, y + .032, z + .004), (x - .032, y + .032, z + .006)], .0027, rope, cyclic=True))
            pegs.append(cylinder('Canopy peg', .008, .014, (x, sy * .425, 1.713), dark, 'Y', 12))
    merge(ties, 'P09_CornerLashings')
    merge(pegs, 'P09_JoineryPegs')
    for sign in [-1, 1]:
        rail = cube('P09_CanopyRail_' + str(sign), (2.47, .035, .035), (0, sign * .39, 1.756), cedar, .0015)
        planar_uv(rail, grain=True)
        # A visible shaped roof batten bears on the existing eave rail. Its
        # upper face follows the cloth underside; the old rail alone was
        # 19--31mm below the stretched fabric, leaving it unsupported.
        bv=[];bf=[];segments=32
        for i in range(segments+1):
            x=-1.235+2.47*i/segments
            for y,z in [(sign*.39-.014,1.768),(sign*.39+.014,1.768),
                        (sign*.39+.014,canopy_z(x,sign*.39+.014)-.0022),
                        (sign*.39-.014,canopy_z(x,sign*.39-.014)-.0022)]:
                bv.append((x,y,z))
        for i in range(segments):
            for q in range(4):
                r=(q+1)%4
                bf.append((4*i+q,4*i+r,4*(i+1)+r,4*(i+1)+q))
        bf.extend([(3,2,1,0),(4*segments,4*segments+1,4*segments+2,4*segments+3)])
        bmsh=bpy.data.meshes.new('Shaped eave roof bearing')
        bmsh.from_pydata(bv,[],bf);bmsh.update()
        batten=bpy.data.objects.new('P09_ShapedBearingRail_'+str(sign),bmsh)
        bpy.context.collection.objects.link(batten);bmsh.materials.append(cedar)
        bm=bmesh.new();bm.from_mesh(bmsh)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(bmsh);bm.free()
        planar_uv(batten,grain=True)
    obj.name = 'P09_ContinuousClosedCanvas'
    check=bmesh.new();check.from_mesh(obj.data)
    print('CLOSED_CANVAS_TOPOLOGY','boundary',sum(edge.is_boundary for edge in check.edges),'nonmanifold',sum(not edge.is_manifold for edge in check.edges))
    check.free()
    wood_parts = [part for part in bpy.context.scene.objects if part.type == 'MESH' and part.data.materials and part.data.materials[0] == cedar]
    union_solids(wood_parts, 'P09_ClosedTimberAndCounter')


def frame(name, x, z, width, height, thickness, y, depth, mat, bevel=.0015):
    return ring(name, x, z, width, height, width - thickness * 2,
                height - thickness * 2, z, y, depth, mat, bevel)


def ring(name, x, z, width, height, inner_width, inner_height, inner_z, y, depth, mat, bevel=.0015):
    # One manifold annular solid. Four merely touching bevelled boxes can leave
    # corner cracks and duplicate internal cap faces even when they look joined.
    outer = [(x - width / 2, z - height / 2), (x + width / 2, z - height / 2),
             (x + width / 2, z + height / 2), (x - width / 2, z + height / 2)]
    inner = [(x - inner_width / 2, inner_z - inner_height / 2), (x + inner_width / 2, inner_z - inner_height / 2),
             (x + inner_width / 2, inner_z + inner_height / 2), (x - inner_width / 2, inner_z + inner_height / 2)]
    verts = [(xx, yy, zz) for yy in [y - depth / 2, y + depth / 2] for contour in [outer, inner] for xx, zz in contour]
    faces = []
    for i in range(4):
        j = (i + 1) % 4
        faces.extend([(i, j, j + 4, i + 4), (i + 8, i + 12, j + 12, j + 8),
                      (i, i + 8, j + 8, j), (i + 4, j + 4, j + 12, i + 12)])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    bm = bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces)); bm.to_mesh(mesh); bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    if bevel:
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new('Folded frame edge', 'BEVEL'); mod.width = bevel; mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    planar_uv(obj)
    return obj


def build_oven():
    old = load_original('P_deck_oven')
    upper = old.copy()
    upper.data = old.data.copy()
    bpy.context.collection.objects.link(upper)
    cut(old, (0, 0, .5855), (0, 0, 1))
    cut(upper, (0, 0, 1.8995), (0, 0, -1))
    old.name='Oven_PreservedOriginalBase'
    upper.name='Oven_PreservedCompleteFlue'
    enamel = material('Oven_MaintainedEnamel', (.72, .73, .72), 'enamel_metal.png')
    charcoal = material('Oven_HeatSeal', (.045, .050, .056))
    panel = material('Oven_ControlPanel', (.105, .13, .15))
    handle = material('Oven_HeatproofHandle', (.12, .135, .145))
    tick = material('Oven_DialMarkings', (.82, .82, .74))
    tray = material('Oven_StoneDeck', (.58, .44, .28))
    cavity = material('Oven_WarmCavity', (.40, .245, .12), emission=.07)
    warm = material('Oven_HeatingElement', (.91, .43, .13), emission=.6)
    glass = material('Oven_HeatGlass', (.30, .40, .44), alpha=.16)
    for retained in [old,upper]:
        retained.data.materials.clear();retained.data.materials.append(enamel)
        for face in retained.data.polygons:face.material_index=0
        planar_uv(retained)
    # Replace the self-intersecting generated middle shell with a regular
    # insulated cabinet. Every cavity is an actual opening in this one solid.
    cabinet=cube('Oven_RegularCabinet',(1.458,.870,1.3355),(0,.010,1.25225),enamel,.002)
    subtract_solid(cabinet,cube('Rear ventilation plenum',(1.40,.535,1.27),(0,.1425,1.255),enamel))
    floor_levels=[]
    for deck,z in enumerate([.905,1.465]):
        wz=z-.037
        subtract_solid(cabinet,cube('Baking chamber void'+str(deck),(.783,.350,.188),(-.115,-.326,wz+.004),cavity))
        subtract_solid(cabinet,cube('Control compartment void'+str(deck),(.17,.34,.47),(.585,-.29,z),enamel))
        floor_levels.append(wz-.090)
    assign_baking_floors(cabinet,tray,floor_levels)
    for sign in [-1, 1]:
        cube('Oven_RepairedFrontSide_' + str(sign), (.018, .326, 1.335), (sign * .721, -.283, 1.2525), enamel, .001)
    cube('Oven_RepairedHoodFrontTop', (1.46, .326, .018), (0, -.283, 1.911), enamel, .001)
    # The monolithic cabinet already supplies its front jambs and shelves.
    # Redundant coplanar overlay boxes create internal nonconforming seams;
    # the door rings instead embed directly into this actual cabinet wall.
    for deck, z in enumerate([.905, 1.465]):
        name = 'Oven_Deck' + str(deck)
        x = -.115
        # Four real strips surround a true opening rather than a painted window.
        outer_w, outer_h = 1.13, .49
        window_w, window_h = .80, .205
        wz = z - .037
        ring(name + '_StraightDoorFrame', x, z, outer_w, outer_h, window_w, window_h, wz, -.429, .034, enamel, .0015)
        frame(name + '_WindowSeal', x, wz, .829, .234, .014, -.441, .026, charcoal, .001)
        # Back/side/ceiling/floor belong to the actual cabinet void, rather than
        # separate floating slabs. The visible back plane stays at -.151m.
        cube(name + '_Glass', (.803, .002, .208), (x, -.431, wz), glass)
        cube(name + '_WarmElement', (.58, .008, .007), (x, -.154, wz + .079), warm, .001)
        for i in range(4):
            tube(name + '_Rack_' + str(i), [(x - .393, -.389 + i * .055, wz - .073), (x + .393, -.389 + i * .055, wz - .073)], .0018, panel)
        hz = z + .170
        cylinder(name + '_LevelHandle', .0138, .84, (x, -.496, hz), handle, 'X', 32)
        for sign in [-1, 1]:
            cube(name + '_HandleMount' + str(sign), (.030, .055, .026), (x + sign * .406, -.470, hz), panel, .002)
            cylinder(name + '_Hinge' + str(sign), .012, .068, (-.691, -.448, z + sign * .14), panel, 'Z', 16)
        cube(name + '_ControlPanel', (.18, .020, .49), (.585, -.430, z), panel, .003)
        # Its 180mm panel overlaps the 170mm compartment opening by 5mm on
        # both sides. The control bay walls are part of the cabinet solid.
        cylinder(name + '_HeatIndicator', .007, .009, (.646, -.4415, z + .198), warm, 'Y', 16)
        label(name + '_HeatLabel', 'HEAT', (.582, -.44002, z + .197), .014, tick)
        marks = []
        for q, kz in enumerate([z + .071, z - .112]):
            cylinder(name + '_Knob' + str(q), .037, .040, (.585, -.457, kz), handle, 'Y', 32)
            cylinder(name + '_KnobFace' + str(q), .0315, .0022, (.585, -.4779, kz), panel, 'Y', 32)
            for mark in range(9):
                a = math.radians(-210 + mark * 30)
                points = [( .585 + radius * math.cos(a), -.4406, kz + radius * math.sin(a)) for radius in [.048, .055]]
                marks.append(tube('Engraved dial tick', points, .0009, tick))
            pointer_angle = math.radians(60 if q == 0 else 120)
            marks.append(tube('Knob pointer', [(.585, -.480, kz), (.585 + .022 * math.cos(pointer_angle), -.480, kz + .022 * math.sin(pointer_angle))], .0015, tick))
            label(name + '_Units' + str(q), 'C' if q == 0 else 'min', (.585, -.44002, kz - .068), .013, tick)
            for text, dx in [('50' if q == 0 else '0', -.060), ('250' if q == 0 else '60', .060)]:
                label(name + '_Scale_' + str(q) + text, text, (.585 + dx, -.44002, kz + .025), .011, tick)
        merge(marks, name + '_DialTicksAndPointers')
        screws = []
        for sx in [-1, 1]:
            for sz in [-1, 1]:
                screws.append(cylinder('Panel screw', .003, .002, (.585 + sx * .078, -.4405, z + sz * .23), tick, 'Y', 12))
        merge(screws, name + '_PanelScrews')
    # All joined structural solids genuinely overlap through normal casing,
    # hinges, handle mounts, gasket lips or shafts. Tiny printed legends remain
    # independent render decoration; no artificial connecting thread is added.
    # Glass, rotary controls and removable pull bars are proper closed fitted
    # parts. Keep them independent; CSG through their thin coplanar caps can
    # erase a valid control face. The casing/hinges/door/chamber form the real
    # continuous structural core without any artificial connection geometry.
    structure = [part for part in bpy.context.scene.objects if part.type == 'MESH' and
                 (all(mat in [enamel,cavity,tray,charcoal] for mat in part.data.materials)
                  or '_Hinge' in part.name)]
    structure.sort(key=lambda part:0 if part==cabinet else 1)
    assembled = union_solids(structure, 'Oven_ClosedPhysicalAssembly')
    # Straight, genuinely through-cut ventilation grilles join outside air to
    # the closed rear plenum. A real solid louver sits across each side opening.
    for sign in [-1,1]:
        for column,y in enumerate([-.05,.22]):
            for row,z in enumerate([.82,.85,.88,1.38,1.41,1.44]):
                subtract_solid(assembled,cube('Side vent opening',(.055,.09,.012),(sign*.7085,y,z),panel))
                slat=cube('Oven_VentLouver_%s_%s_%s'%(sign,column,row),(.0015,.094,.016),(sign*.724,y,z),enamel)
                slat.rotation_euler.y=sign*math.radians(25)
    for i in range(11):
        subtract_solid(assembled,cube('Front hood vent opening',(.066,.34,.011),(-.56+.112*i,-.285,1.875),panel))
    assign_baking_floors(assembled,tray,floor_levels)
    bm=bmesh.new();bm.from_mesh(assembled.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.00000005)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    print('REGULAR_CABINET_TOPOLOGY','boundary',sum(edge.is_boundary for edge in bm.edges),'nonmanifold',sum(not edge.is_manifold for edge in bm.edges),'volume',bm.calc_volume(signed=True))
    bm.to_mesh(assembled.data);bm.free();assembled.data.validate(verbose=True,clean_customdata=False)
    split_render_materials(assembled)


def scene_bounds():
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    points = [obj.matrix_world @ vertex.co for obj in meshes for vertex in obj.data.vertices]
    low = [min(p[k] for p in points) for k in range(3)]
    high = [max(p[k] for p in points) for k in range(3)]
    return {'min_blender': low, 'max_blender': high, 'godot_size_m_xyz': [high[0] - low[0], high[2] - low[2], high[1] - low[1]],
            'triangles': sum(len(face.vertices) - 2 for obj in meshes for face in obj.data.polygons),
            'mesh_nodes': [obj.name for obj in meshes], 'materials': sorted({mat.name for obj in meshes for mat in obj.data.materials if mat})}


def export(aid):
    bounds = scene_bounds()
    expected = {'P09': ([-1.3,-.49677181,0], [1.3,.49677181,1.83303499]),
                'P_deck_oven': ([-.73,-.51,0],[.73,.445,2.08])}[aid]
    if max(abs(bounds[key][axis]-expected[side][axis]) for side,key in enumerate(['min_blender','max_blender']) for axis in range(3))>.012:
        raise RuntimeError('Refusing to export altered physical envelope: '+str(bounds))
    # All render groups share the same metre-space origin. Re-batching into a
    # small panel's local frame and back would quantize shared material-boundary
    # vertices twice, creating inventory-only cracks after glTF's float32 save.
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            obj.data.transform(obj.matrix_world)
            obj.matrix_world = Matrix.Identity(4)
    source_parts = [obj.name for obj in bpy.context.scene.objects if obj.type == 'MESH']
    # The editable file retains hardware as individual objects. The game GLB
    # batches opaque pieces by material; two glass panes remain separate for
    # correct transparent sorting, instead of adding seventy tiny draw calls.
    if not DRAFT:
        bpy.ops.wm.save_as_mainfile(filepath=str(RAW / (aid + '.blend')))
    groups = {}
    for obj in list(bpy.context.scene.objects):
        if obj.type != 'MESH' or len(obj.data.materials) != 1:
            continue
        mat = obj.data.materials[0]
        if mat.name == 'Oven_HeatGlass':
            continue
        groups.setdefault(mat.name, []).append(obj)
    for name, objects in groups.items():
        merge(objects, name + '_Geometry')
    filename = aid + ('_draft.glb' if DRAFT else '.glb')
    path = RAW / filename
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', export_yup=True,
                              use_selection=True, export_apply=True, export_animations=False,
                              export_image_format='AUTO')
    report = {'id': aid, 'draft': DRAFT, 'input_sha256': sha(RAW / (aid + '_input.glb')),
              'output_sha256': sha(path), 'editable_source_parts': source_parts, **scene_bounds()}
    (EVIDENCE / (aid + ('-draft' if DRAFT else '') + '-geometry.json')).write_text(json.dumps(report, indent=2) + '\n')
    print('REFINED_MODEL', json.dumps(report))


RAW.mkdir(parents=True, exist_ok=True)
EVIDENCE.mkdir(parents=True, exist_ok=True)
for aid, builder in [('P09', build_stall), ('P_deck_oven', build_oven)]:
    if any(arg.startswith('--only=') for arg in ARGS) and '--only='+aid not in ARGS:
        continue
    reset()
    builder()
    export(aid)

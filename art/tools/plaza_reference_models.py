"""Build clean plaza joinery against the accepted imagegen screenshot paintover.

Blender -b --factory-startup -P art/tools/plaza_reference_models.py
Sources retain metre dimensions, native alpha, material roles and separate parts.
"""
import json
import math
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'art/models/raw/plaza_paintover_20261009'
REF = ROOT / 'art/references/plaza_paintover_20261009'
OUT.mkdir(parents=True, exist_ok=True)
MATS = {}


def linear(rgb):
    return tuple(v / 12.92 if v < .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb)


def material(name, rgb, cell=None, alpha=1):
    if name in MATS:
        return MATS[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bs = mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*linear(rgb), alpha)
    bs.inputs['Roughness'].default_value = 1
    bs.inputs['Alpha'].default_value = alpha
    bs.inputs['Metallic'].default_value = 0
    bs.inputs['Specular IOR Level'].default_value = 0
    if cell is not None:
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = bpy.data.images.load(str(REF / 'plaza_cedar_atlas.png'), check_existing=True)
        mat.node_tree.links.new(tex.outputs['Color'], bs.inputs['Base Color'])
        mat['atlas_cell'] = cell
    if alpha < 1:
        mat.surface_render_method = 'DITHERED'
    MATS[name] = mat
    return mat


def wood(age=0):
    return material('CedarAge_%d' % age, (1, 1, 1), age)


def uv_board(ob, mat):
    if 'atlas_cell' not in mat:
        return
    cell = int(mat['atlas_cell'])
    uv = ob.data.uv_layers.active or ob.data.uv_layers.new()
    # Grain follows the longest local board axis; map every face into one cell.
    bounds = [max(v.co[i] for v in ob.data.vertices) - min(v.co[i] for v in ob.data.vertices) for i in range(3)]
    long_axis = max(range(3), key=lambda i: bounds[i])
    low = [min(v.co[i] for v in ob.data.vertices) for i in range(3)]
    for poly in ob.data.polygons:
        face_axis = max(range(3), key=lambda i: abs(poly.normal[i]))
        axes = [i for i in range(3) if i != face_axis]
        vertical = long_axis if long_axis in axes else axes[1]
        horizontal = next(i for i in axes if i != vertical)
        for loop in poly.loop_indices:
            co = ob.data.vertices[ob.data.loops[loop].vertex_index].co
            u = (co[horizontal] - low[horizontal]) / max(bounds[horizontal], .0001)
            v = (co[vertical] - low[vertical]) / max(bounds[vertical], .0001)
            uv.data[loop].uv = ((cell % 2) * .5 + .025 + u * .45, (1 - cell // 2) * .5 + .025 + v * .45)


def box(name, size, at, mat, bevel=.009):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    ob = bpy.context.object
    ob.name = name
    ob.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(mat)
    uv_board(ob, mat)
    if bevel:
        mod = ob.modifiers.new('Soft readable timber edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return ob


def rod(name, a, b, radius, mat, sides=12):
    delta = Vector(b) - Vector(a)
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=delta.length, location=(Vector(a) + Vector(b)) * .5)
    ob = bpy.context.object
    ob.name = name
    ob.rotation_euler = delta.to_track_quat('Z', 'Y').to_euler()
    ob.data.materials.append(mat)
    uv_board(ob, mat)
    for face in ob.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    return ob


def ball(name, at, scale, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, location=at)
    ob = bpy.context.object
    ob.name = name
    ob.scale = scale
    ob.data.materials.append(mat)
    for face in ob.data.polygons:
        face.use_smooth = True
    return ob


def bench(prefix, width=1.8, at=(0, 0, 0), yaw=0, back=False):
    existing = set(bpy.context.scene.objects)
    for x in (-width * .38, width * .38):
        for y in (-.21, .21):
            box(prefix + 'Leg', (.09, .10, .47), (x, y, .235), wood(3))
        box(prefix + 'MortiseRail', (.105, .56, .11), (x, 0, .44), wood(2))
    box(prefix + 'StretchRail', (width * .76, .07, .09), (0, 0, .23), wood(3))
    for row in range(3):
        box(prefix + 'SeatBoard', (width, .178, .065), (0, (row - 1) * .19, .525), wood(row % 2))
    if back:
        for x in (-width * .38, width * .38):
            box(prefix + 'BackPost', (.075, .085, .50), (x, .26, .71), wood(2))
        for z in (.73, .91):
            box(prefix + 'BackBoard', (width, .058, .14), (0, .28, z), wood(0))
    for ob in set(bpy.context.scene.objects) - existing:
        p = ob.location.copy()
        ob.location = Vector((p.x * math.cos(yaw) - p.y * math.sin(yaw), p.x * math.sin(yaw) + p.y * math.cos(yaw), p.z)) + Vector(at)
        ob.rotation_euler.z += yaw


def leaf_cards(positions):
    mat = material('Foliage_GrapeSprigs', (1, 1, 1))
    bs = mat.node_tree.nodes.get('Principled BSDF')
    tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(str(REF / 'plaza_leaf_sprigs_atlas.png'), check_existing=True)
    mat.node_tree.links.new(tex.outputs['Color'], bs.inputs['Base Color'])
    mat.node_tree.links.new(tex.outputs['Alpha'], bs.inputs['Alpha'])
    mat.surface_render_method = 'DITHERED'
    mat.use_transparency_overlap = False
    vertices, faces, uvs = [], [], []
    for index, (at, width, tilt, angle) in enumerate(positions):
        center = Vector(at)
        side = Vector((math.cos(angle), math.sin(angle), 0)) * width
        up = Vector((-math.sin(angle) * math.cos(tilt), math.cos(angle) * math.cos(tilt), math.sin(tilt))) * width
        start = len(vertices)
        vertices += [tuple(center - side - up), tuple(center + side - up), tuple(center + side + up), tuple(center - side + up)]
        faces += [(start, start + 1, start + 2, start + 3)]
        u = .5 * (index % 2)
        uvs += [(u + .01, .01), (u + .49, .01), (u + .49, .49), (u + .01, .49)]
    mesh = bpy.data.meshes.new('GrapeSprigCards')
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(mat)
    layer = mesh.uv_layers.new()
    for face in mesh.polygons:
        for loop in face.loop_indices:
            layer.data[loop].uv = uvs[mesh.loops[loop].vertex_index]
    ob = bpy.data.objects.new('Foliage_GrapeSprigs', mesh)
    bpy.context.collection.objects.link(ob)


def pergola():
    stone = material('FootingStone', (.64, .65, .63))
    for x in (-1.72, 1.72):
        for y in (-1.65, 1.65):
            box('StoneFoot', (.38, .38, .26), (x, y, .13), stone)
            box('CedarPost', (.17, .17, 2.63), (x, y, 1.575), wood(2))
            for direction in (-1, 1):
                rod('Brace', (x, y, 2.18), (x + direction * .38, y, 2.70), .055, wood(3), 8)
    for y in (-1.65, 1.65):
        box('MainBeam', (4.12, .16, .18), (0, y, 2.79), wood(2))
    for index in range(11):
        x = -1.91 + index * .382
        box('OpenRoofSlat', (.09, 4.0, .10), (x, 0, 2.925), wood(index % 2))
    for y in (-1.82, -.92, 0, .92, 1.82):
        box('RoofCrossbar', (4.16, .055, .065), (0, y, 2.98), wood(3))
    bench('RearBench', 2.60, (0, 1.12, 0), back=True)
    bench('SideBench', 2.55, (-1.13, -.12, 0), math.pi / 2, True)
    cards = []
    for index in range(140):
        x = math.sin(index * 2.399) * (1.35 + .45 * math.sin(index * .8))
        y = math.cos(index * 2.399) * (1.35 + .4 * math.cos(index * .6))
        cards.append(((x, y, 3.015 + .055 * math.sin(index)), .43 + .09 * math.sin(index * 1.3), .20 + .2 * math.sin(index), index * .37))
    for index in range(24):
        side = -1 if index % 2 else 1
        x = side * (1.72 + .07 * math.sin(index))
        y = (-1.65 if index < 12 else 1.65) + .10 * math.sin(index * 2)
        z = 2.90 - (index % 12) * .13
        cards.append(((x, y, z), .33, 1.3, index * .73))
        if index % 12:
            rod('ClimbingVine', (x, y, z), (x - .035, y + .06, z + .17), .011, wood(3), 8)
    leaf_cards(cards)


def stage():
    dark = material('SpeakerCharcoal', (.23, .27, .32))
    for x in (-1.8, 0, 1.8):
        for y in (-.85, .85):
            box('StageFoot', (.14, .14, .30), (x, y, .15), wood(3))
    for x in (-1.95, 1.95):
        box('DeckSideFrame', (.14, 2.2, .18), (x, 0, .29), wood(2))
        box('BuntingPost', (.085, .085, 2.15), (x, .90, 1.075), wood(2))
    for index in range(12):
        box('DeckBoard', (4.14, .177, .065), (0, -1.01 + index * .183, .41), wood(1 if index in (3, 10) else 0))
    for x in (-1.45, 1.45):
        rod('SpeakerStand', (x, .59, .46), (x, .59, 1.12), .022, dark)
        for angle in (0, 2.094, 4.189):
            rod('TripodFoot', (x, .59, .64), (x + math.cos(angle) * .22, .59 + math.sin(angle) * .22, .45), .019, dark)
        box('SpeakerCabinet', (.28, .19, .43), (x, .59, 1.28), dark, .012)
        for z, radius in ((1.19, .085), (1.39, .044)):
            rod('SpeakerCone', (x, .489, z), (x, .483, z), radius, material('SpeakerCone', (.10, .14, .19)), 20)
    rod('MicStand', (0, -.04, .47), (0, -.04, 1.26), .017, dark)
    rod('Microphone', (0, -.08, 1.29), (0, .03, 1.29), .03, dark)
    for angle in (0, 2.094, 4.189):
        rod('MicTripod', (0, -.04, .61), (math.cos(angle) * .18, -.04 + math.sin(angle) * .18, .45), .015, dark)
    colours = [(.87, .42, .31), (.90, .68, .24), (.28, .65, .61), (.39, .55, .73)]
    line = []
    for index in range(15):
        t = index / 14
        at = Vector((-1.91 + t * 3.82, .9, 2.12 - .13 * math.sin(math.pi * t)))
        line.append(at)
        if index:
            rod('BuntingCord', line[index - 1], at, .008, wood(3), 8)
        if index == 14:
            continue
        verts = [at + Vector((.014, 0, -.02)), at + Vector((.245, 0, -.025)), at + Vector((.13, -.025, -.31))]
        mesh = bpy.data.meshes.new('ClothPennant')
        mesh.from_pydata(verts, [], [(0, 1, 2)])
        mesh.materials.append(material('Pennant_%d' % (index % 4), colours[index % 4]))
        ob = bpy.data.objects.new('ClothPennant', mesh)
        bpy.context.collection.objects.link(ob)


def drum():
    skin = material('WarmDrumHide', (.91, .83, .65))
    dark = material('TaikoStuds', (.23, .21, .20))
    centre = .76
    vertices, faces = [], []
    for row in range(17):
        t = row / 16
        radius = .31 + .045 * math.sin(math.pi * t)
        for index in range(40):
            angle = index * math.tau / 40
            vertices.append((radius * math.cos(angle), -.22 + t * .44, centre + radius * math.sin(angle)))
    for row in range(16):
        for index in range(40):
            a = row * 40 + index
            b = row * 40 + (index + 1) % 40
            faces.append((a, b, b + 40, a + 40))
    shell = bpy.data.meshes.new('ContinuousTaikoShell')
    shell.from_pydata(vertices, [], faces)
    shell.materials.append(wood(2))
    shell.update()
    uv = shell.uv_layers.new()
    for face in shell.polygons:
        face.use_smooth = True
        for loop in face.loop_indices:
            vertex = shell.loops[loop].vertex_index
            uv.data[loop].uv = (.025 + (vertex % 40) / 39 * .45, .025 + (vertex // 40) / 16 * .45)
    body = bpy.data.objects.new('ContinuousTaikoShell', shell)
    bpy.context.collection.objects.link(body)
    for y in (-.245, .245):
        rod('HideHead', (0, y - .008, centre), (0, y + .008, centre), .317, skin, 48)
        for index in range(24):
            angle = index * math.tau / 24
            ball('RimStud', (math.cos(angle) * .308, y, centre + math.sin(angle) * .308), (.012, .009, .012), dark)
    for y in (-.27, .27):
        for direction in (-1, 1):
            rod('StandLeg', (direction * .33, y, .02), (direction * .25, y, .58), .045, wood(3), 8)
        box('DrumCradle', (.65, .085, .09), (0, y, .495), wood(2))
        rod('StandCrossrail', (-.29, y, .22), (.29, y, .22), .035, wood(2), 8)
    for x in (-.15, .15):
        rod('RestingDrumstick', (x, -.13, 1.12), (x + .045, .24, 1.11), .017, wood(1))


def fish_tank():
    water = material('ClearAnimeWater', (.36, .73, .86), alpha=.28)
    blue = material('TankBlueLiner', (.28, .63, .74))
    red = material('GoldfishVermilion', (.95, .21, .08))
    orange = material('GoldfishAmber', (.96, .65, .24))
    for x in (-.64, .64):
        for y in (-.49, .49):
            box('TankFoot', (.10, .10, .30), (x, y, .15), wood(3))
    box('TankBottom', (1.36, 1.055, .045), (0, 0, .32), blue)
    for x in (-.716, .716):
        box('SideBoard', (.068, 1.19, .16), (x, 0, .408), wood(0))
    for y in (-.56, .56):
        box('EndBoard', (1.5, .068, .16), (0, y, .408), wood(1))
    for index in range(8):
        x = -.47 + (index % 4) * .29
        y = -.27 + (index // 4) * .49 + .065 * math.sin(index * 2)
        fish_objects = set(bpy.context.scene.objects)
        ball('GoldfishBody', (0, 0, 0), (.075, .028, .025), orange if index % 3 == 0 else red)
        ball('GoldfishTail', (-.080, 0, 0), (.025, .045, .012), red)
        for side in (-1, 1):
            ball('GoldfishEye', (.044, side * .021, .012), (.006, .004, .006), material('FishEyes', (.12, .13, .14)))
        rotation = Matrix.Rotation(index * .71, 4, 'Z')
        bpy.context.view_layer.update()
        for ob in set(bpy.context.scene.objects) - fish_objects:
            ob.matrix_world = rotation @ ob.matrix_world
            ob.location += Vector((x, y, .385))
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, .435))
    surface = bpy.context.object
    surface.name = 'WaterSurface'
    surface.scale = (1.36, 1.055, 1)
    surface.data.materials.append(water)
    water.use_backface_culling = True


def slide():
    blue = material('SlideIndigoBlue', (.21, .52, .78))
    gold = material('WarmYellowRails', (.91, .70, .27))
    for x in (-.66, .66):
        for y in (-.25, .65):
            box('TimberSupport', (.12, .12, 2.10), (x, y, 1.05), wood(2))
    for index in range(6):
        box('LadderTread', (1.06, .25, .075), (0, .59 + index * .14, 1.57 - index * .245), wood(index % 2))
    box('TopDeck', (1.42, .96, .09), (0, .23, 1.70), wood(0))
    for x in (-.62, .62):
        rod('LadderRail', (x, .65, 2.12), (x, 1.40, .45), .025, gold)
        rod('PlatformRail', (x, -.26, 2.10), (x, .65, 2.10), .028, gold)
    points = [(-.25, 1.74), (-.55, 1.66), (-.88, 1.30), (-1.18, .88), (-1.52, .49), (-1.80, .27), (-2.00, .24)]
    vertices, faces = [], []
    for y, z in points:
        vertices += [(-.49, y, z + .13), (-.42, y, z), (.42, y, z), (.49, y, z + .13)]
    for index in range(len(points) - 1):
        for strip in range(3):
            a = index * 4 + strip
            faces.append((a, a + 1, a + 5, a + 4))
    mesh = bpy.data.meshes.new('CurvedSlideChute')
    mesh.from_pydata(vertices, [], faces)
    mesh.materials.append(blue)
    ob = bpy.data.objects.new('CurvedSlideChute', mesh)
    bpy.context.collection.objects.link(ob)
    solid = ob.modifiers.new('EnamelShellThickness', 'SOLIDIFY')
    solid.thickness = .018
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=solid.name)
    bevel = ob.modifiers.new('RolledSlideEdges', 'BEVEL')
    bevel.width = .018
    bevel.segments = 3
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    for face in ob.data.polygons:
        face.use_smooth = True
    box('FrontSlideSkid', (.96, .18, .10), (0, -1.92, .05), wood(3))
    for x in (-.35, .35):
        rod('FrontSlideSupport', (x, -1.92, .09), (x, -1.90, .25), .035, wood(2), 8)


def save(asset):
    # Join by material role to avoid hundreds of runtime nodes and draw calls.
    groups = {}
    for ob in list(bpy.context.scene.objects):
        if ob.type == 'MESH':
            groups.setdefault(ob.data.materials[0].name, []).append(ob)
    for name, group in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for ob in group:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        bpy.ops.object.join()
        group[0].name = name
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(OUT / (asset + '.glb')), export_format='GLB', export_yup=True, export_animations=False)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / (asset + '.blend')))


for asset, build in {'A12_bench': bench, 'P01': pergola, 'P10': stage, 'G09_taiko': drum, 'G02_goldfish_tank': fish_tank, 'P05': slide}.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    if asset == 'A12_bench':
        bench('OldTreeBench')
    else:
        build()
    save(asset)
    print('PLAZA_MODEL', asset, flush=True)

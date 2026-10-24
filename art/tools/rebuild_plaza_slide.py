"""Rebuild only P05 with a continuous chute and physically joined cedar frame.

Blender -b --factory-startup -P art/tools/rebuild_plaza_slide.py [-- --preview]
No other plaza asset or shared configuration is changed by this generator.
"""
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
LIBRARY = ROOT / 'art/library/plaza'
RAW = ROOT / 'art/models/raw/P05_slide_20261024'
EVIDENCE = ROOT / 'evidence/visual_rework_20261024/slide'
SOURCE_REL = '../library/plaza/source/P05.glb'
PARTS = {}


def linear(hex_color):
    values = [int(hex_color[i:i+2], 16) / 255 for i in (0, 2, 4)]
    return tuple(v / 12.92 if v < .04045 else ((v + .055) / 1.055) ** 2.4 for v in values)


def material(name, color, roughness=.85, specular=.12):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*linear(color), 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = mat.diffuse_color
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Specular IOR Level'].default_value = specular
    mat['authored_srgb'] = color
    return mat


def register(obj, name, mat, group):
    obj.name = name
    obj.data.materials.append(mat)
    obj['construction_group'] = group
    PARTS.setdefault(group, []).append(obj)
    return obj


def box(name, size, location, mat, group, radius=.009, segments=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = register(bpy.context.object, name, mat, group)
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if radius:
        bevel = obj.modifiers.new('Actual softened timber edge', 'BEVEL')
        bevel.width = radius
        bevel.segments = segments
        bpy.ops.object.modifier_apply(modifier=bevel.name)
        normal = obj.modifiers.new('Keep broad timber faces planar', 'WEIGHTED_NORMAL')
        normal.keep_sharp = True
        bpy.ops.object.modifier_apply(modifier=normal.name)
    return obj


def beam(name, a, b, width, depth, mat, group, radius=.008):
    delta = Vector(b) - Vector(a)
    obj = box(name, (width, depth, delta.length), (Vector(a)+Vector(b))*.5,
              mat, group, radius)
    obj.rotation_euler = delta.to_track_quat('Z', 'Y').to_euler()
    return obj


def bearing_post(name, x, y, center_height, slope, mat):
    # The post is cut to the actual inclined underside of the cradle. A flat
    # post cap would leave a visible wedge of air under half the joint.
    vertices = [(x+dx,y+dy,0) for dx,dy in ((-.04,-.04),(.04,-.04),(.04,.04),(-.04,.04))]
    vertices += [(x+dx,y+dy,center_height+slope*dy)
                 for dx,dy in ((-.04,-.04),(.04,-.04),(.04,.04),(-.04,.04))]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices,[],[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
    obj = bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(obj)
    register(obj,name,mat,'ChuteSupports')
    bpy.context.view_layer.objects.active = obj
    bevel = obj.modifiers.new('Small bearing arris', 'BEVEL')
    bevel.width = .006
    bevel.segments = 3
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def tube(name, points, radius, mat, group, sides=16):
    vertices, faces = [], []
    for index, center in enumerate(points):
        before = Vector(points[max(0, index-1)])
        after = Vector(points[min(len(points)-1, index+1)])
        tangent = (after-before).normalized()
        side = Vector((1, 0, 0))
        if abs(tangent.dot(side)) > .95:
            side = Vector((0, 1, 0))
        normal = tangent.cross(side).normalized()
        side = normal.cross(tangent).normalized()
        for step in range(sides):
            angle = step * math.tau / sides
            vertices.append(Vector(center) + radius * (side*math.cos(angle)+normal*math.sin(angle)))
    for row in range(len(points)-1):
        for step in range(sides):
            a = row*sides+step
            b = row*sides+(step+1) % sides
            faces.append((a, b, b+sides, a+sides))
    faces += [tuple(reversed(range(sides))), tuple((len(points)-1)*sides+i for i in range(sides))]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    register(obj, name, mat, group)
    for face in mesh.polygons:
        face.use_smooth = len(face.vertices) == 4
    return obj


def bolt(name, at, mat, axis='X'):
    # Embedded washer and small domed hex head, never a decorative scatter.
    rotation = (0, math.pi/2, 0) if axis == 'X' else (math.pi/2, 0, 0)
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=.021, depth=.004,
                                       location=at, rotation=rotation)
    register(bpy.context.object, name+'_washer', mat, 'JointHardware')
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=.012, depth=.009,
                                       location=at, rotation=rotation)
    obj = register(bpy.context.object, name+'_head', mat, 'JointHardware')
    bevel = obj.modifiers.new('Bolt crown chamfer', 'BEVEL')
    bevel.width = .003
    bevel.segments = 2
    bpy.ops.object.modifier_apply(modifier=bevel.name)


def chute_height(distance):
    # C2 transitions: zero entry slope, sustained descent, then a 30 cm buffer.
    entry, straight, exit_curve = .25, .82, .40
    slope = 1.49 / (straight + (entry+exit_curve)*.5)
    if distance <= entry:
        t = max(0, distance/entry)
        drop = slope*entry*(t**3-.5*t**4)
    elif distance <= entry+straight:
        drop = slope*(distance-entry*.5)
    elif distance <= entry+straight+exit_curve:
        t = (distance-entry-straight)/exit_curve
        drop = slope*(straight+entry*.5+exit_curve*(t-t**3+.5*t**4))
    else:
        drop = 1.49
    return 1.745-drop


def chute(blue):
    cross = [(-.452,.153),(-.450,.100),(-.445,.060),(-.435,.030),(-.418,.010),
             (-.395,.002),(-.370,0),(0,0),(.370,0),(.395,.002),(.418,.010),
             (.435,.030),(.445,.060),(.450,.100),(.452,.153)]
    rows, width = 161, len(cross)
    vertices, faces = [], []
    for index in range(rows):
        distance = 1.77*index/(rows-1)
        y, z = -.23-distance, chute_height(distance)
        # Lower cheeks ease towards the buffer but retain a safe rolled lip.
        scale = 1-.22*max(0, (distance-1.30)/.47)
        vertices.extend((x, y, z+height*scale) for x,height in cross)
    for row in range(rows-1):
        for col in range(width-1):
            a = row*width+col
            faces.append((a, a+width, a+width+1, a+1))
    mesh = bpy.data.meshes.new('Continuous curved enamel shell')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new('SlideChuteShell', mesh)
    bpy.context.collection.objects.link(obj)
    register(obj, obj.name, blue, 'SlideChuteShell')
    # Offset along the real surface normal, including side cheeks. A vertical
    # displacement gives the steep bed a thinner sheet than the flat buffer.
    bpy.context.view_layer.objects.active = obj
    solid = obj.modifiers.new('Closed twenty millimetre enamel shell', 'SOLIDIFY')
    solid.thickness = .020
    solid.offset = -1
    solid.use_even_offset = True
    solid.use_quality_normals = True
    bpy.ops.object.modifier_apply(modifier=solid.name)
    for face in obj.data.polygons:
        face.use_smooth = True
    for side in (-1, 1):
        path = []
        for index in range(rows):
            distance = 1.77*index/(rows-1)
            scale = 1-.22*max(0, (distance-1.30)/.47)
            path.append((side*.454,-.23-distance,chute_height(distance)+.153*scale))
        tube('ContinuousRolledLip_'+str(side),path,.032,blue,'SlideRolledRims',24)
    # A rounded terminal nose closes the front edge, below the sliding surface.
    tube('RoundedExitNose',[(-.37,-2.0,.245),(.37,-2.0,.245)],.010,blue,'SlideChuteShell',12)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for folder in (RAW, LIBRARY/'source', LIBRARY/'authoring', EVIDENCE):
        folder.mkdir(parents=True, exist_ok=True)
    wood = [material('CedarAge_'+str(i),color) for i,color in enumerate(('be8b55','ba8752','b78350','ac794a'))]
    blue = material('SlideIndigoBlue','3585c7',.50,.20)
    fastener = material('SlideJointSteel','71858c',.62,.22)
    chute(blue)

    for x in (-.66,.66):
        for y in (-.25,.65):
            box('GroundedCedarPost',(.12,.12,2.08),(x,y,1.04),wood[2],'TimberPosts',.014,4)
            box('RoundedPostCrown',(.12,.12,.075),(x,y,2.0925),wood[2],'TimberPosts',.030,5)
        # Side guards have a lower rail, two upright divisions and a round handhold.
        box('LowerPlatformGuard',(.075,.80,.10),(x,.20,1.89),wood[0],'PlatformGuards',.014,4)
        for y in (.02,.38):
            box('GuardUpright',(.060,.045,.23),(x,y,1.97),wood[1],'PlatformGuards',.010,3)
        box('PlatformHandhold',(.080,.91,.075),(x,.20,2.09),wood[0],'PlatformGuards',.032,5)
        for a,b in [((x-.018,-.25,.40),(x-.018,.65,1.50)),((x+.018,-.25,1.50),(x+.018,.65,.40))]:
            beam('SideCrossBrace',a,b,.073,.068,wood[3],'FrameBraces',.007)
        bolt('CrossBraceJoint',(x+math.copysign(.055,x),.20,.95),fastener)
        for y in (-.25,.65):
            for z in (.42,1.48,1.60,1.89):
                bolt('PostJoint',(x+math.copysign(.055,x),y,z),fastener)

    # Five distinct deck boards share two bearers and the four original posts.
    for index in range(5):
        box('PlatformDeckBoard',(1.42,.183,.090),(0,-.154+index*.188,1.700),wood[0],'PlatformDeck',.007,3)
    for y in (-.18,.59):
        box('DeckBearingBeam',(1.40,.14,.13),(0,y,1.590),wood[2],'DeckBearers',.008)
    for x in (-.61,.61):
        box('SideDeckJoist',(.11,.91,.12),(x,.20,1.59),wood[2],'DeckBearers',.008)

    # Real, load-bearing ladder stringers sit under both ends of all six treads.
    for side in (-1,1):
        x = side*.54
        beam('LadderStringer',(x,1.35,.032),(x,.66,1.64),.105,.15,wood[2],'LadderStringers',.012)
        box('GroundedLadderShoe',(.11,.15,.065),(x,1.34,.0325),wood[2],'LadderStringers',.009)
        rail = [(side*.62,1.35,.54),(side*.62,.70,2.02),(side*.62,.65,2.09)]
        tube('LadderHandrail',rail,.029,wood[0],'LadderHandrails',16)
        for y in (1.27,.97):
            rail_z = .54+(1.35-y)*1.48/.65
            stringer_z = .032+(1.35-y)*1.608/.69
            beam('HandrailStandoff',(x,y,stringer_z),(side*.62,y,rail_z),
                 .058,.058,wood[2],'LadderHandrails',.008)
        for y,z in ((1.30,.275),(.97,1.01),(.75,1.50)):
            bolt('LadderPeg',(side*.583,y,z-.035),fastener)
    for index in range(6):
        y,z = 1.30-index*.11,.275+index*.245
        box('LadderTread',(1.17,.23,.080),(0,y,z-.040),wood[0],'LadderTreads',.014,4)
        # The softly rounded nosing is part of the actual tread, not a painted line.
        tube('TreadRoundedNosing',[(-.54,y+.101,z-.018),(.54,y+.101,z-.018)],.018,wood[0],'LadderTreads',12)

    # Transverse cradles and ground-connected feet support the descending shell.
    for y in (-.47,-1.08,-1.90):
        distance = -.23-y
        slope = (chute_height(distance-.001)-chute_height(distance+.001))/.002
        angle = math.atan(slope)
        z = chute_height(distance)-.020/math.cos(angle)-.003
        normal = Vector((0,-math.sin(angle),math.cos(angle)))
        cradle = box('ChuteCrossCradle',(.84,.10,.080),Vector((0,y,z))-normal*.040,
                     wood[2],'ChuteSupports',.009)
        cradle.rotation_euler.x = angle
        if y < -.60:
            for x in (-.35,.35):
                height = z-.080/math.cos(angle)
                bearing_post('ChuteSupportFoot',x,y,height,slope,wood[2])
    box('FrontGroundSkid',(.96,.18,.10),(0,-1.92,.05),wood[3],'ChuteSupports',.018,4)
    # Side blocking connects the entry crossmember to the existing platform legs.
    for side in (-1,1):
        beam('EntryKneeBrace',(side*.62,-.25,1.28),(side*.39,-.47,chute_height(.24)-.07),
             .085,.085,wood[3],'ChuteSupports',.008)

    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(LIBRARY/'authoring/P05.blend'))
    # Keep editable components in .blend; game/source GLBs join related construction
    # parts to cap node/draw-call cost while retaining material and geometry roles.
    for group, parts in PARTS.items():
        bpy.ops.object.select_all(action='DESELECT')
        for obj in parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        if len(parts)>1:
            bpy.ops.object.join()
        parts[0].name = group
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    source = LIBRARY/'source/P05.glb'
    bpy.ops.export_scene.gltf(filepath=str(source),export_format='GLB',export_yup=True,
                              export_apply=True,export_animations=False)
    shutil.copy2(source,RAW/'P05.glb')
    shutil.copy2(source,ROOT/'game/assets/models/P05.glb')
    points = [obj.matrix_world @ vertex.co for obj in meshes for vertex in obj.data.vertices]
    low = [min(point[axis] for point in points) for axis in range(3)]
    high = [max(point[axis] for point in points) for axis in range(3)]
    stats = {'id':'P05','src':SOURCE_REL,'provider':'Blender authored continuous slide and cedar joinery (2026-10-24)',
             'preserve_parts':True,'origin_preserved':True,
             'tris':sum(sum(len(face.vertices)-2 for face in obj.data.polygons) for obj in meshes),
             'tex':0,'bytes':source.stat().st_size,
             'godot_size_m_xyz':[round(high[0]-low[0],4),round(high[2]-low[2],4),round(high[1]-low[1],4)],
             'mesh_nodes':sorted(obj.name for obj in meshes)}
    (ROOT/'game/assets/models/_stats/P05.json').write_text(json.dumps(stats,indent=1)+'\n')
    manifest = {'date':'2026-10-24','asset':'P05','tool':'art/tools/rebuild_plaza_slide.py',
                'source':'art/library/plaza/source/P05.glb','authoring':'art/library/plaza/authoring/P05.blend',
                'raw_copy':'art/models/raw/P05_slide_20261024/P05.glb',
                'game':'game/assets/models/P05.glb','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                'config':{'src':SOURCE_REL,'preserve_parts':True,'preserve_origin':True,'level':False,
                          'tex':2048,'image_format':'AUTO','provider':stats['provider'],'license':'项目自制'},
                'license':'项目自制','reference':'evidence/visual_rework_20261024/references/10.png',
                'construction':'Continuous C2 chute profile, closed 20 mm shell, swept 64 mm rolled edges, 30 cm horizontal buffer, deck bearers, six joined ladder treads, cedar guards, cross braces and inset fasteners.',
                'placement':{'unchanged_world_xyz':[-10.4,0,7],'unchanged_yaw_degrees':90},
                'materials_srgb':{mat.name:mat['authored_srgb'] for mat in [*wood,blue,fastener]},
                'material_note':'CedarAge_0..3 use narrowly grouped warm cedar swatches; compatible with the outdoor timber palette pass. Blue enamel and embedded steel fasteners retain separate materials.',
                'stats':stats,'verification':'evidence/visual_rework_20261024/slide/',
                'native_acceptance':'pending root-agent Godot capture and placement verification'}
    (ROOT/'art/manifests/models_slide_20261024.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print('SLIDE_EXPORTED',json.dumps(stats),flush=True)


def preview():
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 48
    scene.render.resolution_x = 1300
    scene.render.resolution_y = 1100
    scene.render.resolution_percentage = 100
    scene.world = bpy.data.worlds.new('PreviewWorld')
    scene.world.color = (.22,.25,.30)
    scene.view_settings.view_transform = 'Standard'
    bpy.ops.mesh.primitive_plane_add(size=200)
    ground = bpy.context.object
    ground.name = 'PreviewGroundOnly'
    ground.data.materials.append(material('PreviewGround','dce2d4',1,0))
    bpy.ops.object.light_add(type='AREA',location=(-3,-4,7))
    light = bpy.context.object
    light.data.energy = 650
    light.data.size = 5
    light.rotation_euler = (Vector((0,-.3,.9))-light.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    scene.camera = camera
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 4.8
    for name,location in [('front',(4.2,-6.5,4.1)),('rear',(-4.7,5.3,3.6)),('profile',(5,-.2,2.4))]:
        camera.location = location
        camera.rotation_euler = (Vector((0,-.35,1.0))-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath = str(EVIDENCE/('blender_'+name+'.png'))
        bpy.ops.render.render(write_still=True)


if __name__ == '__main__':
    if '--preview-only' in sys.argv:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(LIBRARY/'source/P05.glb'))
    else:
        build()
    if '--preview' in sys.argv or '--preview-only' in sys.argv:
        preview()

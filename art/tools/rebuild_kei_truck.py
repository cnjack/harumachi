"""Rebuild the kei truck's cab, chassis and wheels; retain the textured produce bed.

Blender -b --factory-startup -P art/tools/rebuild_kei_truck.py
Dimensions are authored in Godot metres (+Z is the nose). Windows are actual
openings with separate thin glazing, not painted seats on an opaque windscreen.
"""
import json
import math
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'art/library/vehicles/textures/D07_kei_truck'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'art/library/vehicles/source/D07_textured_predecessor.glb'))
old = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
bpy.context.view_layer.objects.active = old
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# Exact plane cuts preserve the predecessor's UVs on the good cargo and bed.
bm = bmesh.new(); bm.from_mesh(old.data)
for point, normal in [((0, -.17, 0), (0, 1, 0)), ((0, 0, .72), (0, 0, 1))]:
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                          plane_co=point, plane_no=normal, clear_inner=True, dist=.00001)
bm.to_mesh(old.data); bm.free()
old.name = 'TexturedBedAndCargo'
old.data.materials[0].name = 'Original_textured_produce_and_bed'


def srgb(values):
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in values)


def material(name, colour, textured=False, alpha=1.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    p = m.node_tree.nodes['Principled BSDF']
    p.inputs['Base Color'].default_value = (*srgb(colour), alpha)
    p.inputs['Roughness'].default_value = .85
    p.inputs['Specular IOR Level'].default_value = 0
    p.inputs['Alpha'].default_value = alpha
    if alpha < 1:
        m.surface_render_method = 'DITHERED'
    if textured:
        # A deterministic, low contrast painted wash, baked to a real UV image.
        # Large quiet areas keep the truck in the existing anime palette.
        y, x = np.mgrid[0:512, 0:512].astype(np.float32) / 511
        border = np.minimum(np.minimum(x, 1-x), np.minimum(y, 1-y))
        wash = .972 + .022 * np.clip(border * 20, 0, 1) + .005*np.sin(x*23+y*6)
        rgba = np.ones((512, 512, 4), np.float32)
        rgba[:, :, :3] = np.array(colour)[None, None, :] * wash[:, :, None]
        img = bpy.data.images.new(name + '_paint', width=512, height=512, alpha=False)
        img.pixels.foreach_set(rgba.ravel()); img.filepath_raw = str(OUT / (name + '.png'))
        img.file_format = 'PNG'; img.save(); img.pack()
        tex = m.node_tree.nodes.new('ShaderNodeTexImage'); tex.image = img
        m.node_tree.links.new(tex.outputs['Color'], p.inputs['Base Color'])
    return m


paint = material('Ivory_painted_body', (.94, .945, .92), True)
trim = material('Blue_grey_trim', (.30, .40, .45), True)
rubber = material('Tyre_rubber', (.20, .235, .25), True)
cloth = material('Blue_woven_seats', (.34, .44, .51), True)
silver = material('Matte_wheel_steel', (.76, .80, .80), True)
dark = material('Rubber_seals_and_grille', (.16, .22, .25))
lamp = material('Cream_headlamp', (.94, .94, .77), True)
amber = material('Amber_signal', (.94, .57, .17))
red = material('Red_tail_lamp', (.78, .22, .19))
glass = material('Thin_blue_glass', (.66, .83, .91), alpha=.16)
plate = material('Yellow_local_plate', (.93, .78, .32))


def pos(v):
    return Vector((v[0], -v[2], v[1]))


def finish(o, name, mat, bevel=0, segments=4):
    o.name = name; o.data.materials.append(mat)
    if bevel:
        modifier = o.modifiers.new('Small_pressed_edge', 'BEVEL')
        modifier.width = bevel; modifier.segments = segments
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        for polygon in o.data.polygons:
            polygon.use_smooth=True
        normal = o.modifiers.new('Panel_normals', 'WEIGHTED_NORMAL')
        normal.keep_sharp = True
        bpy.ops.object.modifier_apply(modifier=normal.name)
    return o


def box(name, size, at, mat=paint, bevel=.015):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos(at))
    o = bpy.context.object; o.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, name, mat, bevel)


def beam(name, start, end, width, mat=paint):
    a, b = pos(start), pos(end)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(a+b)/2)
    o = bpy.context.object; o.dimensions = (width, width, (b-a).length)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    return finish(o, name, mat, width*.19)


def quad(name, corners, mat):
    mesh = bpy.data.meshes.new(name); mesh.from_pydata([pos(v) for v in corners], [], [(0, 1, 2, 3)])
    mesh.update(); o = bpy.data.objects.new(name, mesh); bpy.context.collection.objects.link(o)
    uv = mesh.uv_layers.new(name='UVMap')
    for loop, co in zip(uv.data, [(0, 0), (1, 0), (1, 1), (0, 1)]): loop.uv = co
    o.data.materials.append(mat)
    return o


def cylinder(name, at, radius, depth, mat, axis='X', vertices=32):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=pos(at))
    o = bpy.context.object
    if axis == 'X': o.rotation_euler.y = math.pi/2
    elif axis == 'Z': o.rotation_euler.x = math.pi/2
    return finish(o, name, mat, 0 if name == 'Rim_vent' else .008, 1)


def mesh_object(name, verts, faces, mat, smooth=False):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([pos(v) for v in verts], [], faces)
    mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(mesh);bm.free()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    uv=mesh.uv_layers.new(name='UVMap')
    for poly in mesh.polygons:
        poly.use_smooth=smooth
        for loop_index in poly.loop_indices:
            v=mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv=(v.x*.35+.5,v.y*.25+.5)
    obj.data.materials.append(mat)
    return obj


def round_rect(width, depth, radius, segments=8):
    points=[]
    for cx,cz,start in [(width/2-radius,depth/2-radius,0),(-width/2+radius,depth/2-radius,90),
                         (-width/2+radius,-depth/2+radius,180),(width/2-radius,-depth/2+radius,270)]:
        for i in range(segments+1):
            angle=math.radians(start+90*i/segments)
            points.append((cx+radius*math.cos(angle),cz+radius*math.sin(angle)))
    return points


def roof_shell():
    outline=round_rect(1.65,1.285,.12)
    verts=[];faces=[];count=len(outline)
    for scale,height in [(1,1.793),(1,1.816),(.96,1.835),(.87,1.850),(.61,1.867),(.30,1.881)]:
        verts += [(x*scale,height,z*scale+.811) for x,z in outline]
    for row in range(5):
        for i in range(count):
            a=row*count+i;b=row*count+(i+1)%count
            faces.append((a,b,b+count,a+count))
    faces += [tuple(reversed(range(count))),tuple(range(5*count,6*count))]
    return mesh_object('CrownedRoof',verts,faces,paint,True)


def pressed_nose():
    # The bow is shaped across the entire panel, not a bevel on a flat box.
    xs=[-.82+i*1.64/32 for i in range(33)]
    levels=[(.715,-.025),(.742,0),(1.145,0),(1.201,-.028)]
    verts=[];faces=[]
    for y,offset in levels:
        verts += [(x,y,1.699-.067*(abs(x)/.82)**3+offset) for x in xs]
    for row in range(3):
        for i in range(32):
            a=row*33+i;faces.append((a,a+1,a+34,a+33))
    verts += [(x,y,1.523) for y,_ in levels for x in xs]
    for row in range(3):
        for i in range(32):
            a=132+row*33+i;faces.append((a+33,a+34,a+1,a))
    for row in range(3):
        for index in [0,32]:
            a=row*33+index;faces.append((a,a+33,a+165,a+132))
    for row in [0,3]:
        for i in range(32):
            a=row*33+i;faces.append((a,a+1,a+133,a+132))
    return mesh_object('PressedNose',verts,faces,paint,True)


def cut(obj, cutter, name):
    bpy.context.view_layer.objects.active=obj
    mod=obj.modifiers.new(name,'BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter,do_unlink=True)


def arc_fender(name,side,z):
    verts=[];faces=[];steps=48
    # A full solid rolled lip, with an inner return and a broad painted outer face.
    for x,r in [(side*.78,.348),(side*.892,.348),(side*.901,.361),
                (side*.893,.386),(side*.775,.386)]:
        for i in range(steps+1):
            angle=math.radians(7+166*i/steps)
            verts.append((x,.325+r*math.sin(angle),z+r*math.cos(angle)))
    count=steps+1
    for row in range(5):
        for i in range(steps):
            a=row*count+i;b=((row+1)%5)*count+i
            faces.append((a,a+1,b+1,b))
    faces += [tuple(row*count for row in range(5)),tuple(row*count+steps for row in reversed(range(5)))]
    return mesh_object(name,verts,faces,paint,True)


def tyre(name,side,z):
    verts=[];faces=[];steps=64
    # Cross-section closes at the bead. Broad sidewall curves produce a
    # ballooned rubber silhouette and leave the rim truly inset.
    profile=[(-.095,.205),(-.118,.230),(-.126,.263),(-.118,.285),(-.101,.310),
             (-.070,.322),(-.034,.325),(.034,.325),(.070,.322),(.101,.310),
             (.118,.285),(.126,.263),(.118,.230),(.095,.205)]
    for axial,radius in profile:
        for i in range(steps):
            angle=math.tau*i/steps
            verts.append((side*.746+axial,.325+radius*math.cos(angle),z+radius*math.sin(angle)))
    for row in range(len(profile)):
        for i in range(steps):
            faces.append((row*steps+i,row*steps+(i+1)%steps,
                          ((row+1)%len(profile))*steps+(i+1)%steps,((row+1)%len(profile))*steps+i))
    return mesh_object(name,verts,faces,rubber,True)


def cylinder_link(name,start,end,radius,mat):
    a,b=pos(start),pos(end)
    bpy.ops.mesh.primitive_cylinder_add(vertices=20,radius=radius,depth=(b-a).length,location=(a+b)*.5)
    obj=bpy.context.object;obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return finish(obj,name,mat,.003,3)


def join_named(objects,name):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join();bpy.context.object.name=name
    return bpy.context.object


box('Chassis', (1.31, .14, 3.17), (0, .44, -.01), dark)
box('Cab_floor', (1.52, .065, 1.43), (0, .703, .91), trim)
box('Cab_back_lower', (1.60, .51, .07), (0, .93, .23))
box('Rear_window_sill', (1.58, .12, .07), (0, 1.205, .23))
box('Rear_window_header', (1.58, .10, .07), (0, 1.755, .23))
for side in [-1, 1]:
    box('Rear_window_side', (.22, .47, .065), (side*.69, 1.49, .23))
    label='Left' if side<0 else 'Right'
    panel = box('Door_lower', (.080, .64, 1.37), (side*.795, .89, .975),paint,.032)
    # True wheel arch removes the panel behind each front tyre.
    cutter = cylinder('Wheel_arch_cutter', (side*.795, .325, 1.075), .352, .3, dark,vertices=64)
    cut(panel,cutter,'Open_wheel_arch')
    box('Door_handle_recess', (.012, .076, .235), (side*.839, 1.083, .49),trim,.022)
    for dz in [-.078,.078]:
        box('Door_handle_foot', (.045,.031,.031), (side*.855,1.083,.49+dz),dark,.012)
    box('Door_handle_pull', (.024,.029,.182), (side*.883,1.083,.49),dark,.013)
    box('Door_moulding', (.016, .022, 1.19), (side*.842, 1.157, .965), paint, .007)
    for a,b in [((side*.838,.74,.335),(side*.838,1.18,.335)),
                ((side*.838,1.18,.335),(side*.838,1.18,1.55)),
                ((side*.838,.765,1.55),(side*.838,1.18,1.55))]:
        beam('Door_shut_line',a,b,.0065,trim)
    box('Cab_step', (.19, .075, .43), (side*.765, .535, .455), trim,.024)
    for dz in [-.11,0,.11]:
        box('Step_tread',(.16,.008,.024),(side*.77,.576,.455+dz),dark,.003)
    window = [(side*.802, 1.225, .30), (side*.802, 1.225, 1.59),
              (side*.752, 1.752, 1.354), (side*.752, 1.752, .30)]
    quad('Glass_Left' if side < 0 else 'Glass_Right', window, glass)
    for i in range(4):
        beam('Side_window_seal', window[i], window[(i+1)%4], .045, dark)
    beam('Cab_A_pillar', (side*.798, 1.19, 1.63), (side*.752, 1.79, 1.37), .080)
    beam('Cab_B_pillar', (side*.795, 1.17, .255), (side*.75, 1.79, .255), .090)
    beam('Quarter_window_divider', (side*.801, 1.225, 1.39), (side*.766, 1.695, 1.376), .026, dark)
    box('Mirror_door_mount',(.035,.065,.080),(side*.832,1.20,1.42),dark,.014)
    cylinder_link('Mirror_arm', (side*.837,1.22,1.42),(side*.954,1.245,1.44),.014,dark)
    shell=box('Mirror_'+label+'_Shell',(.125,.230,.082),(side*.955,1.345,1.44),dark,.030)
    cutter=box('Mirror_recess',(.095,.178,.037),(side*.955,1.345,1.389),dark,.025)
    cut(shell,cutter,'Inset_reflecting_glass')
    box('Mirror_'+label+'_Lens',(.090,.170,.005),(side*.955,1.345,1.406),silver,.022)

wind = [(-.758, 1.215, 1.638), (.758, 1.215, 1.638), (.714, 1.763, 1.392), (-.714, 1.763, 1.392)]
quad('Glass_Windshield', wind, glass)
for i in range(4): beam('Windshield_seal', wind[i], wind[(i+1)%4], .036, dark)
quad('Glass_Rear', [(-.56, 1.265, .231), (.56, 1.265, .231), (.56, 1.70, .231), (-.56, 1.70, .231)], glass)
roof_shell()
for side in [-1,1]:
    box('Roof_rain_gutter',(.018,.021,1.035),(side*.817,1.807,.80),paint,.008)
nose=pressed_nose()
box('Front_bumper', (1.71, .18, .20), (0, .62, 1.61), paint, .065)
box('Bumper_upper_seal',(1.63,.014,.025),(0,.715,1.683),dark,.006)
box('Grille_recess', (.69, .13, .022), (0, .895, 1.701), dark, .028)
for row in [-1, 1]: box('Grille_slat', (.65, .018, .016), (0, .895+row*.035, 1.718), silver, .006)
box('Front_badge',(.068,.050,.014),(0,1.085,1.702),silver,.017)
for side in [-1, 1]:
    label='Left' if side<0 else 'Right'
    cutter=box('Lamp_body_aperture',(.345,.218,.25),(side*.542,.947,1.675),dark,.038)
    cut(nose,cutter,'Recessed_headlamp_'+label)
    reflector=box('Headlight_'+label+'_Reflector',(.335,.205,.084),(side*.542,.947,1.648),silver,.037)
    bucket_cut=box('Reflector_cavity',(.275,.145,.064),(side*.542,.947,1.699),dark,.030)
    cut(reflector,bucket_cut,'Reflector_bowl')
    # The warm opaque lens is recessed inside a physical border. Its broad
    # restrained highlights read as enamel-era glass in the game's toon light.
    box('Headlight_'+label+'_Lens',(.275,.145,.020),(side*.542,.947,1.699),lamp,.030)
    for dx in [-.072,-.024,.024,.072]:
        box('Headlight_flute',(.004,.108,.003),(side*.542+dx,.947,1.710),silver,.001)
    box('Front_indicator_socket',(.082,.145,.042),(side*.753,.94,1.665),dark,.021)
    box('Front_indicator', (.061, .119, .026), (side*.753, .94, 1.695), amber, .015)
    box('Bumper_insert', (.30, .065, .021), (side*.55, .609, 1.708), trim,.019)
    beam('Wiper', (side*.51, 1.222, 1.669), (side*.20, 1.26, 1.650), .018, dark)
# Booleans must not borrow rounded cutter normals across the entire sheet.
# Keep the authored broad bow normal continuous around each lamp aperture.
nose_normals=[Vector((0,0,1)) for _ in nose.data.loops]
for polygon in nose.data.polygons:
    for index in polygon.loop_indices:
        vertex=nose.data.vertices[nose.data.loops[index].vertex_index].co
        if polygon.normal.y<-.55 and vertex.y< -1.59:
            dx=-.067*3*(abs(vertex.x)/.82)**2*(1 if vertex.x>=0 else -1)/.82
            dy=0.0
            if vertex.z>1.145:dy=-.5
            elif vertex.z<.742:dy=.025/.027
            nose_normals[index]=Vector((-dx,-1,-dy)).normalized()
        else:nose_normals[index]=polygon.normal.copy()
nose.data.normals_split_custom_set(nose_normals)
box('Front_plate', (.30, .135, .019), (0, .647, 1.712), plate, .009)
# Embossed simple number glyphs are real shallow geometry, not a tiny noisy decal.
for x in [-.074, .015, .082]:
    box('Plate_mark', (.019, .057, .004), (x, .642, 1.724), dark, .002)

box('Dashboard', (1.43, .18, .24), (0, 1.123, 1.353), trim, .038)
box('Dashboard_instruments', (.38, .095, .035), (.38, 1.22, 1.238), dark)
for side, label in [(-1, 'Left'), (1, 'Right')]:
    box('Seat_'+label, (.52, .14, .48), (side*.405, .845, .69), cloth, .057)
    back = box('Seatback_'+label, (.52, .49, .105), (side*.405, 1.12, .424), cloth, .05)
    back.rotation_euler.x = math.radians(-7)
    box('Headrest_'+label, (.30, .19, .10), (side*.405, 1.445, .397), cloth, .045)
    beam('Seatbelt', (side*.668, 1.49, .385), (side*.18, .85, .60), .026, dark)
beam('Steering_column', (.405, 1.035, 1.32), (.405, 1.195, 1.10), .045, dark)
bpy.ops.mesh.primitive_torus_add(major_radius=.15, minor_radius=.019, major_segments=28, minor_segments=8, location=pos((.405, 1.225, 1.055)))
steering=bpy.context.object;steering.rotation_euler.x=math.radians(48);finish(steering,'SteeringWheel',dark)
beam('Steering_spoke', (.27, 1.22, 1.055), (.54, 1.22, 1.055), .019, dark)
beam('Gear_lever', (.02, .73, 1.04), (.02, .975, 1.0), .027, dark)

# Formed steel gates enclose the retained painted vegetable crates. Each gate
# rests on the floor rim and has a top return, shallow pressings and fasteners.
box('Cargo_floor',(1.715,.065,1.845),(0,.723,-.764),trim,.018)
for side in [-1,1]:
    gate=box('Cargo_sidegate',(.060,.345,1.80),(side*.858,.878,-.765),paint,.018)
    cutter=cylinder('Bed_wheel_aperture',(side*.83,.325,-1.11),.352,.35,dark,vertices=64)
    cut(gate,cutter,'Rear_arch_clearance')
    box('Cargo_top_return',(.071,.041,1.814),(side*.86,1.059,-.765),paint,.015)
    box('Cargo_lower_return',(.074,.039,1.803),(side*.86,.718,-.765),paint,.013)
    for z in [-1.39,-.76,-.12]:
        box('Cargo_pressing',(.012,.18,.43),(side*.895,.876,z),paint,.026)
    for z in [-1.57,.05]:
        box('Cargo_corner_socket',(.065,.285,.079),(side*.86,.895,z),paint,.012)
        parts=[box('Latch_mount',(.026,.093,.073),(side*.902,.984,z),trim,.009),
               box('Latch_lever',(.040,.071,.020),(side*.921,.976,z),silver,.008)]
        join_named(parts,'SidegateLatch_'+('Left' if side<0 else 'Right')+('_Back' if z<0 else '_Front'))
    for z in [-1.35,-.32]:
        cylinder_link('Tie_down_anchor',(side*.904,.763,z-.035),(side*.904,.763,z+.035),.010,trim)
        for dz in [-.035,.035]:
            cylinder_link('Tie_down_mount',(side*.880,.76,z+dz),(side*.904,.763,z+dz),.008,trim)
box('Cargo_tailgate',(1.71,.342,.055),(0,.878,-1.685),paint,.018)
box('Tailgate_top_return',(1.736,.042,.073),(0,1.060,-1.687),paint,.014)
for x in [-.51,0,.51]:
    box('Tailgate_pressed_panel',(.40,.18,.014),(x,.876,-1.718),paint,.026)
for index,x in enumerate([-.55,.55]):
    pieces=[box('Hinge_upper_leaf',(.13,.067,.022),(x,.776,-1.720),silver,.007),
            box('Hinge_lower_leaf',(.13,.059,.025),(x,.704,-1.722),silver,.007),
            cylinder('Hinge_pin',(x,.741,-1.727),.023,.176,silver,vertices=24)]
    join_named(pieces,'TailgateHinge_'+str(index))
    for y in [.696,.790]:
        cylinder('Hinge_rivet',(x,y,-1.737),.007,.004,dark,axis='Z',vertices=12)
# Protect the cab at its header and side pillars. A mid-height crossbar would
# occlude the clear rear glass; all three members stay outside that aperture.
box('Cab_cargo_guard',(1.47,.045,.045),(0,1.755,.125),paint,.013)
for side in [-1,1]:
    box('Cargo_guard_leg',(.045,1.025,.048),(side*.713,1.2425,.125),paint,.012)

for side in [-1, 1]:
    for axle, z in [('Front', 1.075), ('Rear', -1.11)]:
        label='Left' if side<0 else 'Right'
        tyre('Tyre_'+axle+'_'+label,side,z)
        arc_fender('WheelArch_'+axle+'_'+label,side,z)
        cylinder('Brake_drum',(side*.831,.325,z),.199,.032,dark,vertices=48)
        rim=cylinder('Pressed_steel_rim', (side*.862, .325, z), .212, .022, silver, vertices=48)
        for index in range(6):
            a=index*math.tau/6
            cutter=cylinder('Vent_cutter',(side*.862,.325+math.cos(a)*.148,z+math.sin(a)*.148),.023,.075,dark,vertices=16)
            cut(rim,cutter,'Pressed_vent_'+str(index))
        for polygon in rim.data.polygons:polygon.use_smooth=False
        bpy.ops.mesh.primitive_torus_add(major_radius=.202,minor_radius=.010,major_segments=48,minor_segments=8,
                                        location=pos((side*.874,.325,z)))
        rim_roll=bpy.context.object;rim_roll.rotation_euler.y=math.pi/2
        finish(rim_roll,'Rolled_rim_edge',silver)
        cylinder('Hub', (side*.881, .325, z), .069, .028, trim, vertices=32)
        for index in range(4):
            angle=index*math.tau/4
            cylinder('Wheel_lug',(side*.882,.325+math.cos(angle)*.094,z+math.sin(angle)*.094),.012,.019,silver,vertices=6)
    box('Rear_mudflap', (.24, .24, .028), (side*.75, .35, -1.49), rubber, .009)
box('Rear_bumper', (1.51, .075, .07), (0, .50, -1.643), trim)
for side in [-1, 1]:
    box('Tail_lamp_surround', (.28, .12, .045), (side*.60, .65, -1.676), dark, .014)
    box('Tail_lamp_red', (.19, .078, .018), (side*.574, .65, -1.706), red, .009)
    box('Tail_lamp_amber', (.055, .078, .018), (side*.706, .65, -1.706), amber, .008)
box('Rear_plate', (.30, .135, .018), (0, .65, -1.711), plate, .009)
for x in [-.074, .015, .082]:
    box('Rear_plate_mark', (.019, .057, .004), (x, .646, -1.723), dark, .002)

# Keep independently inspectable glass, seat, tyre and steering meshes; batch
# the remaining trim by material so two trucks do not add hundreds of draws.
protected=('TexturedBedAndCargo','Glass_', 'Seat_', 'Seatback_', 'Headrest_', 'Tyre_', 'SteeringWheel',
           'WheelArch_', 'Headlight_Left_', 'Headlight_Right_', 'Mirror_', 'TailgateHinge_', 'SidegateLatch_')
groups={}
for o in list(bpy.context.scene.objects):
    if o.type=='MESH' and not o.name.startswith(protected):
        groups.setdefault(o.data.materials[0].name, []).append(o)
for name, objects in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
    bpy.context.object.name='Body_'+name
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
for m in bpy.data.materials:
    if m.use_nodes:
        for node in m.node_tree.nodes:
            if node.type=='TEX_IMAGE' and node.image:node.image.pack()
authoring = ROOT / 'art/library/vehicles/authoring/D07_kei_truck.blend'
authoring.parent.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(authoring))
source=ROOT/'art/library/vehicles/source/D07_kei_truck.glb'
bpy.ops.export_scene.gltf(filepath=str(source),export_format='GLB',export_yup=True,export_apply=True,export_animations=False)
manifest={'model':'D07_kei_truck','date':'2026-10-24','source':str(source.relative_to(ROOT)),
          'authoring':str(authoring.relative_to(ROOT)), 'builder':'art/tools/rebuild_kei_truck.py',
          'predecessor':'art/library/vehicles/source/D07_textured_predecessor.glb',
          'retained':'Original UV texture on produce crates and flatbed; no opaque original cab remains',
          'rebuilt':['broad crowned roof and bowed pressed nose','four rolled wheel-arch returns',
                     'curved tyre cross-sections and vented steel rims','shut lines and stood-off door pulls',
                     'inset lamp bowls and lenses','rear-facing inset mirror lenses',
                     'formed drop-side gates, rolled rails, hinges, latches and tie-down anchors'],
          'nose_axis':'+Z','wheel_radius_m':.325,'glass':'Four thin separate quads with clear apertures',
          'rear_guard':'Crossbar follows the cab header at 1.755 m; side legs reach the cargo floor, outside the rear-glass aperture',
          'new_paid_generations':0,
          'audit':'art/tools/audit_kei_truck_detail.py','native_visual_review_required':True}
(ROOT/'art/manifests/models_kei_truck_20261024.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')

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
OUT = ROOT / 'art/models/raw/D07_kei_truck_glass_20261014'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'art/library/vehicles/source/D07_textured_predecessor.glb'))
old = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
bpy.context.view_layer.objects.active = old
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# Exact plane cuts preserve the predecessor's UVs on the good cargo and bed.
bm = bmesh.new(); bm.from_mesh(old.data)
for point, normal in [((0, -.17, 0), (0, 1, 0)), ((0, 0, .59), (0, 0, 1))]:
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


def finish(o, name, mat, bevel=0, segments=2):
    o.name = name; o.data.materials.append(mat)
    if bevel:
        modifier = o.modifiers.new('Small_pressed_edge', 'BEVEL')
        modifier.width = bevel; modifier.segments = segments
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=modifier.name)
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


box('Chassis', (1.31, .14, 3.17), (0, .44, -.01), dark)
box('Cab_floor', (1.52, .11, 1.43), (0, .64, .91), trim)
box('Cab_back_lower', (1.60, .51, .07), (0, .93, .23))
box('Rear_window_sill', (1.58, .12, .07), (0, 1.205, .23))
box('Rear_window_header', (1.58, .10, .07), (0, 1.755, .23))
for side in [-1, 1]:
    box('Rear_window_side', (.22, .47, .065), (side*.69, 1.49, .23))
    panel = box('Door_lower', (.070, .62, 1.37), (side*.795, .89, .975))
    # True wheel arch removes the panel behind each front tyre.
    cutter = cylinder('Wheel_arch_cutter', (side*.795, .335, 1.075), .38, .3, dark)
    bpy.context.view_layer.objects.active = panel
    mod = panel.modifiers.new('Open_wheel_arch', 'BOOLEAN'); mod.operation='DIFFERENCE'; mod.object=cutter
    bpy.ops.object.modifier_apply(modifier=mod.name); bpy.data.objects.remove(cutter, do_unlink=True)
    box('Door_handle', (.035, .045, .15), (side*.843, 1.086, .435), dark, .012)
    box('Door_moulding', (.022, .026, 1.20), (side*.837, .86, .98), trim, .005)
    box('Cab_step', (.13, .08, .56), (side*.76, .515, .545), trim)
    window = [(side*.802, 1.225, .30), (side*.802, 1.225, 1.59),
              (side*.752, 1.752, 1.354), (side*.752, 1.752, .30)]
    quad('Glass_Left' if side < 0 else 'Glass_Right', window, glass)
    for i in range(4):
        beam('Side_window_seal', window[i], window[(i+1)%4], .045, dark)
    beam('Cab_A_pillar', (side*.798, 1.19, 1.63), (side*.752, 1.79, 1.37), .080)
    beam('Cab_B_pillar', (side*.795, 1.17, .255), (side*.75, 1.79, .255), .090)
    beam('Quarter_window_divider', (side*.801, 1.225, 1.39), (side*.766, 1.695, 1.376), .026, dark)
    beam('Mirror_arm', (side*.815, 1.195, 1.38), (side*.960, 1.23, 1.43), .028, dark)
    box('Side_mirror', (.08, .205, .12), (side*.967, 1.32, 1.44), dark)
    box('Mirror_face', (.006, .155, .085), (side*1.010, 1.325, 1.445), silver, .002)

wind = [(-.758, 1.215, 1.638), (.758, 1.215, 1.638), (.714, 1.763, 1.392), (-.714, 1.763, 1.392)]
quad('Glass_Windshield', wind, glass)
for i in range(4): beam('Windshield_seal', wind[i], wind[(i+1)%4], .036, dark)
quad('Glass_Rear', [(-.56, 1.265, .231), (.56, 1.265, .231), (.56, 1.70, .231), (-.56, 1.70, .231)], glass)
box('Cab_roof', (1.64, .085, 1.21), (0, 1.8125, .805), paint, .040)
box('Front_cowl', (1.61, .12, .16), (0, 1.17, 1.604), paint, .035)
box('Nose_panel', (1.62, .39, .13), (0, .93, 1.617), paint, .038)
box('Front_bumper', (1.67, .18, .17), (0, .62, 1.615), paint, .028)
box('Grille_recess', (.72, .12, .016), (0, .89, 1.691), dark, .01)
for row in [-1, 1]: box('Grille_slat', (.70, .018, .018), (0, .89+row*.035, 1.706), silver, .004)
for side in [-1, 1]:
    box('Headlamp_surround', (.36, .22, .055), (side*.575, .945, 1.678), trim, .035)
    box('Headlamp_lens', (.286, .157, .027), (side*.55, .959, 1.713), lamp, .024)
    box('Front_indicator', (.075, .11, .028), (side*.737, .925, 1.708), amber, .009)
    box('Bumper_insert', (.33, .066, .016), (side*.54, .604, 1.707), trim)
    beam('Wiper', (side*.51, 1.222, 1.669), (side*.20, 1.26, 1.650), .018, dark)
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

for side in [-1, 1]:
    for axle, z in [('Front', 1.075), ('Rear', -1.11)]:
        cylinder('Tyre_'+axle+('_Left' if side<0 else '_Right'), (side*.746, .325, z), .325, .235, rubber, vertices=40)
        cylinder('Rim', (side*.870, .325, z), .214, .020, silver, vertices=32)
        cylinder('Hub', (side*.887, .325, z), .092, .025, trim, vertices=24)
        for index in range(6):
            a=index*math.tau/6
            cylinder('Rim_vent', (side*.884, .325+math.cos(a)*.15, z+math.sin(a)*.15), .025, .006, dark, vertices=10)
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
protected=('TexturedBedAndCargo','Glass_', 'Seat_', 'Seatback_', 'Headrest_', 'Tyre_', 'SteeringWheel')
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
bpy.ops.wm.save_as_mainfile(filepath=str(authoring))
bpy.ops.export_scene.gltf(filepath=str(OUT/'ready.glb'),export_format='GLB',export_yup=True,export_apply=True,export_animations=False)
(OUT/'construction.json').write_text(json.dumps({'model':'D07_kei_truck','retained':'Original UV texture on produce crates and flatbed; no opaque original cab remains','rebuilt':'Hollow cab, 4 separate windows, seats, headrests, dashboard, right-hand steering, chassis, 4 tyres, wheel arches, lamps, mirrors','nose_axis':'+Z','wheel_radius_m':.325,'glass':'Thin separate quads; runtime angle-dependent soft anime sky tint','new_paid_generations':0},ensure_ascii=False,indent=2)+'\n')

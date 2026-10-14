"""Rebuild reviewed bakery appliances in place, from immutable predecessors.

Blender -b --factory-startup --python-exit-code 1 -P art/tools/refine_appliance_forms_20261014.py
Optional: -- --only=P_deck_oven (or P_coffee_station). Game export/config is owned by root.
All public dimensions below use Godot metres: +Y up, +Z towards the operator.
"""
from pathlib import Path
import bpy
import bmesh
import hashlib
import json
import math
import sys
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/library/appliance_forms_20261014/source'
OUT = ROOT / 'art/models/raw/appliance_forms_20261014'
MANIFEST = ROOT / 'art/manifests/appliance_forms_geometry_20261014.json'
TEXTURES = ROOT / 'game/assets/textures/furniture_forms_20261014'
ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
MATERIALS = {}
DETAILS = {}

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def p(value):
    return (value[0], -value[2], value[1])

def gp(value):
    return (value.x, value.z, -value.y)

def load_model(aid):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    MATERIALS.clear()
    path = SOURCE / (aid + '.glb')
    if not path.exists():
        raise FileNotFoundError('Immutable source must be copied before rebuilding: ' + str(path))
    bpy.ops.import_scene.gltf(filepath=str(path))
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            obj.data.transform(obj.matrix_world)
            obj.matrix_world = Matrix.Identity(4)
    for mat in bpy.data.materials:
        MATERIALS[mat.name] = mat

def material(name, colour, texture=None, alpha=1.0):
    if texture and not (TEXTURES / texture).exists():
        raise FileNotFoundError('Required approved surface painting: '+str(TEXTURES/texture))
    mat = MATERIALS.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*colour, alpha)
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*colour, 1.0)
    shader.inputs['Alpha'].default_value = alpha
    shader.inputs['Roughness'].default_value = .7
    shader.inputs['Metallic'].default_value = 0.0
    shader.inputs['Specular IOR Level'].default_value = 0.0
    if texture and (TEXTURES / texture).exists():
        for link in list(shader.inputs['Base Color'].links):
            mat.node_tree.links.remove(link)
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = bpy.data.images.load(str(TEXTURES / texture), check_existing=True)
        tex.image.pack()
        tex.extension = 'REPEAT'
        if name=='Oven_ControlPanel':
            # Blender 5.2's glTF exporter recognises the typed Mix node,
            # not legacy MixRGB, as an actual texture * baseColorFactor.
            tint=mat.node_tree.nodes.new('ShaderNodeMix')
            tint.data_type='RGBA';tint.blend_type='MULTIPLY'
            tint.inputs[0].default_value=1.0
            tint.inputs[7].default_value=(*colour,1.0)
            mat.node_tree.links.new(tex.outputs['Color'],tint.inputs[6])
            mat.node_tree.links.new(tint.outputs[2],shader.inputs['Base Color'])
        else:
            mat.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
        shader.inputs['Base Color'].default_value = (1,1,1,1)
    if alpha < 1:
        mat.surface_render_method = 'DITHERED'
    MATERIALS[name] = mat
    return mat

def uv(obj, scale=.5):
    layer = obj.data.uv_layers.active or obj.data.uv_layers.new(name='UVMap')
    for face in obj.data.polygons:
        normal = gp(face.normal)
        for loop_index in face.loop_indices:
            point = gp(obj.data.vertices[obj.data.loops[loop_index].vertex_index].co)
            coordinates = (point[0], point[2]) if abs(normal[1]) > .6 else ((point[0], point[1]) if abs(normal[2]) > .6 else (point[2], point[1]))
            layer.data[loop_index].uv = (coordinates[0] / scale, coordinates[1] / scale)

def bake_transform(obj):
    # A zero-bevel cylinder has not invoked a dependency-graph operator yet.
    # Flush its quaternion before baking, otherwise an X rack stays vertical.
    bpy.context.view_layer.update()
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)

def bevel(obj, width, segments=4):
    if width <= 0:
        return obj
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new('Real multi-segment edge radius', 'BEVEL')
    modifier.width = width
    modifier.segments = segments
    modifier.affect = 'EDGES'
    modifier.limit_method = 'ANGLE'
    modifier.angle_limit = math.radians(28)
    modifier.use_clamp_overlap = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
        weighted=obj.modifiers.new('Keep broad casing planes flat', 'WEIGHTED_NORMAL')
        weighted.keep_sharp=True
        weighted.weight=50
        bpy.ops.object.modifier_apply(modifier=weighted.name)
    except RuntimeError:
        pass
    return obj

def box(name, size, at, mat, radius=.006, segments=4):
    bpy.ops.mesh.primitive_cube_add(size=1, location=p(at))
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    bevel(obj, radius, segments)
    bake_transform(obj)
    uv(obj)
    return obj

def cylinder(name, radius, length, at, mat, axis='Y', vertices=32, edge=.0015):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=length, location=p(at))
    obj = bpy.context.object
    obj.name = name
    direction = Vector(p({'X': (1, 0, 0), 'Y': (0, 1, 0), 'Z': (0, 0, 1)}[axis]))
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction)
    obj.data.materials.append(mat)
    bevel(obj, edge, 3)
    bake_transform(obj)
    for face in obj.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    uv(obj, .25)
    return obj

def tube(name, points, radius, mat, sides=16):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 8
    curve.bevel_resolution = 3
    curve.bevel_depth = radius
    curve.use_fill_caps = True
    # Sample real corner fillets inside the control polyline's convex hull.
    # Automatic Bezier handles overshoot a U rail by >10cm and alter its footprint.
    rounded=[Vector(points[0])]
    for index in range(1,len(points)-1):
        previous=Vector(points[index-1]);corner=Vector(points[index]);following=Vector(points[index+1])
        distance=min(.020,(corner-previous).length*.25,(following-corner).length*.25)
        before=corner-(corner-previous).normalized()*distance
        after=corner+(following-corner).normalized()*distance
        rounded.append(before)
        for step in range(1,9):
            t=step/8
            rounded.append(before*(1-t)**2+corner*(2*t*(1-t))+after*t*t)
    rounded.append(Vector(points[-1]))
    spline=curve.splines.new('POLY');spline.points.add(len(rounded)-1)
    for knot,value in zip(spline.points,rounded):knot.co=(*p(value),1.0)
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    uv(obj, .25)
    return obj

def subtract(target, cutter):
    bpy.context.view_layer.objects.active = target
    modifier = target.modifiers.new('True appliance opening', 'BOOLEAN')
    modifier.operation = 'DIFFERENCE'
    modifier.solver = 'EXACT'
    modifier.object = cutter
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)

def contour(width, height, radius, steps=6):
    result = []
    for cx, cy, first in [(width/2-radius, height/2-radius, 0), (-width/2+radius, height/2-radius, 90), (-width/2+radius, -height/2+radius, 180), (width/2-radius, -height/2+radius, 270)]:
        for index in range(steps + 1):
            angle = math.radians(first + index * 90 / steps)
            result.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return result

def ring(name, at, outer, inner, depth, mat, radius=.018, inner_radius=.012, inner_offset=(0,0)):
    outside = contour(*outer, radius)
    inside = [(x+inner_offset[0],y+inner_offset[1]) for x,y in contour(*inner, inner_radius)]
    count = len(outside)
    vertices = [p((at[0]+x, at[1]+y, z)) for z in (at[2]-depth/2, at[2]+depth/2) for curve in (outside, inside) for x, y in curve]
    faces = []
    for index in range(count):
        nxt = (index+1) % count
        faces.extend([(index,nxt,nxt+count,index+count), (index+2*count,index+3*count,nxt+3*count,nxt+2*count), (index,index+2*count,nxt+2*count,nxt), (index+count,nxt+count,nxt+3*count,index+3*count)])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    bm = bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh); bm.free()
    bevel(obj, .0015, 3)
    uv(obj)
    return obj

def delete(obj):
    bpy.data.objects.remove(obj, do_unlink=True)

def retained_slice(original, name, height, upper):
    obj = original.copy(); obj.data = original.data.copy()
    bpy.context.collection.objects.link(obj); obj.name = name
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces), dist=.000001, plane_co=(0,0,height), plane_no=(0,0,1), clear_inner=upper, clear_outer=not upper)
    bm.to_mesh(obj.data); bm.free()
    return obj

def oven():
    load_model('P_deck_oven')
    enamel = material('Oven_MaintainedEnamel', (.74,.74,.71), 'oven_enamel_albedo.png')
    steel = material('Oven_ControlPanel', (.20,.23,.25), 'brushed_steel_albedo.png')
    bright = material('Oven_BrushedSteel', (.63,.67,.69), 'brushed_steel_albedo.png')
    rubber = MATERIALS['Oven_HeatSeal']
    grip = MATERIALS['Oven_HeatproofHandle']
    stone = MATERIALS['Oven_StoneDeck']
    cavity = MATERIALS['Oven_WarmCavity']
    old = bpy.data.objects['Oven_MaintainedEnamel_Geometry']
    retained_slice(old, 'Oven_PreservedBaseAndFeet', .5855, False)
    retained_slice(old, 'Oven_PreservedCompleteFlue', 1.8995, True)
    delete(old)
    for name in ['Oven_ControlPanel_Geometry','Oven_HeatSeal_Geometry','Oven_HeatproofHandle_Geometry','Oven_WarmCavity_Geometry']:
        delete(bpy.data.objects[name])
    cabinet = box('Oven_RoundedInsulatedCabinet', (1.458,1.314,.870), (0,1.2425,-.010), enamel, .012, 5)
    subtract(cabinet, box('Rear air plenum cutter', (1.40,1.27,.535), (0,1.255,-.1425), enamel, 0))
    for deck, level in enumerate([.905,1.465]):
        window_y = level-.037
        subtract(cabinet, box('True baking chamber cutter', (.783,.188,.350), (-.115,window_y+.004,.326), cavity, .004, 3))
        subtract(cabinet, box('Control bay cutter', (.17,.47,.34), (.585,level,.29), steel, 0))
        ring('Oven_Deck%d_RoundDoorFrame'%deck, (-.115,level,.429), (1.13,.49), (.80,.205), .034, enamel, .025, .014, (0,-.037))
        ring('Oven_Deck%d_RoundWindowSeal'%deck, (-.115,window_y,.441), (.829,.234), (.801,.207), .026, rubber, .020, .014)
        box('Oven_Deck%d_CavityBack'%deck, (.779,.183,.009), (-.115,window_y,.148), cavity, .002, 3)
        box('Oven_Deck%d_ControlPanel'%deck, (.18,.49,.020), (.585,level,.430), steel, .007, 5)
        cylinder('Oven_Deck%d_CylindricalGrip'%deck, .018, .80, (-.115,level+.170,.4918), grip, 'X', 40, .003)
        for side in [-1,1]:
            cylinder('Oven_Deck%d_HandleCap_%d'%(deck,side), .018, .026, (-.115+side*.405,level+.170,.4918), bright, 'X', 32, .003)
            tube('Oven_Deck%d_CurvedMount_%d'%(deck,side), [(-.115+side*.407,level+.170,.445),(-.115+side*.407,level+.170,.470),(-.115+side*.395,level+.170,.486)], .009, bright)
        for offset in [-.14,.14]:
            cylinder('Oven_Deck%d_Hinge_%d'%(deck,int(offset*100)), .012, .068, (-.691,level+offset,.448), steel, 'Y', 20, .001)
        for row in range(4):
            cylinder('Oven_Deck%d_Rack_%d'%(deck,row), .0018, .786, (-.115,window_y-.073,.389-row*.055), steel, 'X', 20, 0)
        for knob, offset in enumerate([.071,-.112]):
            cylinder('Oven_Deck%d_Knob%d'%(deck,knob), .037, .040, (.585,level+offset,.457), grip, 'Z', 40, .003)
            cylinder('Oven_Deck%d_KnobFace%d'%(deck,knob), .0315, .0022, (.585,level+offset,.4779), steel, 'Z', 40, .0005)
    for side in [-1,1]:
        for col, depth in enumerate([-.05,.22]):
            for row, height in enumerate([.82,.85,.88,1.38,1.41,1.44]):
                subtract(cabinet, box('Through side ventilation cutter', (.055,.012,.09), (side*.7085,height,-depth), steel, 0))
                box('Oven_VentLouver_%d_%d_%d'%(side,col,row), (.003,.016,.094), (side*.724,height,-depth), enamel, .001, 3)
    for index in range(11):
        subtract(cabinet, box('Through front ventilation cutter', (.066,.011,.34), (-.56+.112*index,1.875,.285), steel, 0))
    bpy.ops.object.select_all(action='DESELECT');cabinet.select_set(True)
    bpy.context.view_layer.objects.active=cabinet
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    weighted=cabinet.modifiers.new('Stable casing normals after ventilation booleans','WEIGHTED_NORMAL')
    weighted.keep_sharp=True;weighted.weight=50
    bpy.ops.object.modifier_apply(modifier=weighted.name)
    uv(cabinet)
    for deck,level in enumerate([.905,1.465]):
        box('Oven_Deck%d_BakingStone'%deck,(.740,.018,.250),(-.115,level-.118,.290),stone,.003,4)
    DETAILS['P_deck_oven'] = {'outer_radius_m':.012,'door_corner_radius_m':.025,'door_curve_segments':6,'bevel_segments':5,'preserved_base_below_y':.5855,'preserved_flue_above_y':1.8995,'glass_centres':[[-.115,.868,.431],[-.115,1.428,.431]],'operator_controls_x':.585,'physical_grip_radius_m':.018,'cavity_back_z':.1525,'actual_ventilation_openings':35}

def hollow_cup(name, at, radius, height, mat, thickness=.003, handle=True):
    # Lathed closed wall, open drinking mouth and actual interior floor.
    rings = [(radius*.91,0),(radius,height*.12),(radius,height-.003),(radius-thickness,height),(radius-thickness,height*.16),(radius-thickness*1.4,.006)]
    count=32; vertices=[]
    for rad, y in rings:
        for index in range(count):
            angle=index*math.tau/count
            vertices.append(p((at[0]+rad*math.cos(angle),at[1]+y,at[2]+rad*math.sin(angle))))
    faces=[]
    for row in range(len(rings)-1):
        for index in range(count):
            nxt=(index+1)%count;faces.append((row*count+index,row*count+nxt,(row+1)*count+nxt,(row+1)*count+index))
    faces.extend([tuple(reversed(range(count))),tuple(range((len(rings)-1)*count,len(rings)*count))])
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);mesh.materials.append(mat)
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    for face in mesh.polygons:face.use_smooth=len(face.vertices)==4
    uv(obj,.25)
    if handle:
        tube(name+'Handle',[(at[0]+radius*.93,at[1]+height*.75,at[2]),(at[0]+radius+.022,at[1]+height*.72,at[2]),(at[0]+radius+.022,at[1]+height*.24,at[2]),(at[0]+radius*.93,at[1]+height*.22,at[2])],.005,mat)
    return obj

def coffee():
    load_model('P_coffee_station')
    steel=material('BrushedSteel',(.63,.67,.69),'brushed_steel_albedo.png')
    sage=MATERIALS['Sage'];cedar=MATERIALS['Cedar'];dark=MATERIALS['CedarDark'];brass=MATERIALS['Brass'];black=MATERIALS['Charcoal'];cream=MATERIALS['Cream'];grounds=MATERIALS['Coffee']
    for obj in list(bpy.context.scene.objects):
        if obj.type=='MESH':delete(obj)
    box('Cabinet',(.96,.83,.62),(0,.415,0),sage,.012,4)
    box('Worktop',(1,.045,.66),(0,.8525,0),cedar,.012,5)
    for side in [-1,1]:
        box('Door_Left' if side<0 else 'Door_Right',(.44,.66,.025),(side*.24,.43,.322),sage,.008,4)
        box('DoorHandle_Left' if side<0 else 'DoorHandle_Right',(.12,.018,.020),(side*.24,.65,.345),brass,.007,5)
    # Same body envelope; its front is now a real recessed work bay.
    box('MachineBody',(.57,.37,.055),(-.14,1.06,-.2475),steel,.012,5)
    box('MachineSide_Left',(.025,.37,.36),(-.4125,1.06,-.055),steel,.009,4)
    box('MachineSide_Right',(.025,.37,.36),(.1325,1.06,-.055),steel,.009,4)
    box('MachineSide',(.045,.38,.41),(-.445,1.06,-.08),dark,.012,5)
    box('ControlFace',(.53,.095,.045),(-.14,1.195,.116),steel,.012,5)
    box('UpperBoilerBeam',(.53,.09,.35),(-.14,1.185,-.065),steel,.012,5)
    box('CupWarmerPlate',(.56,.005,.38),(-.14,1.2475,-.08),steel,.002,3)
    tube('CupWarmerRail',[(-.415,1.255,.10),(-.415,1.255,-.255),(.135,1.255,-.255),(.135,1.255,.10)],.004,steel)
    for x in [-.415,.135]:
        for z in [-.245,.09]:cylinder('CupWarmerRailFoot_%d_%d'%(int(x*1000),int(z*1000)),.004,.008,(x,1.251,z),steel,'Y',16,.001)
    # Real shallow basin and separate open grating, rather than a grey solid lid.
    box('DripTray',(.58,.012,.29),(-.14,.8825,.130),black,.005,4)
    for depth in [-.010,.270]:box('DripTrayRim_%d'%int(depth*1000),(.58,.025,.010),(-.14,.891,depth),steel,.003,3)
    for side in [-1,1]:box('DripTraySide_%d'%side,(.010,.025,.29),(-.14+side*.285,.891,.130),steel,.003,3)
    for row in range(10):box('DripGrid_%d'%row,(.552,.003,.006),(-.14,.902,.001+row*.028),steel,.001,3)
    for index,x in enumerate([-.29,-.05]):
        cylinder('GroupMount_%d'%index,.028,.040,(x,1.130,.135),steel,'Y',32,.003)
        cylinder('GroupHead_%d'%index,.042,.045,(x,1.09,.135),steel,'Y',40,.004)
        cylinder('GroupCollar_%d'%index,.034,.020,(x,1.060,.135),steel,'Y',32,.002)
        tube('Portafilter_%d'%index,[(x,1.075,.135),(x,1.075,.19),(x,1.075,.28)],.013,black)
        cylinder('Dial_%d'%index,.019,.008,(x,1.195,.15),cream,'Z',32,.002)
        cylinder('ControlButton_%d'%index,.009,.009,(x+.05,1.195,.15),black,'Z',24,.0015)
    tube('SteamWand',[(.08,1.145,.10),(.08,1.12,.12),(.08,1.075,.14),(.115,1.045,.16),(.13,.96,.23)],.008,steel)
    cylinder('SteamJoint',.013,.035,(.08,1.13,.12),black,'Y',24,.002)
    pitcher=hollow_cup('Pitcher',(.109,.9035,.216),.035,.075,steel,.002,False)
    for vertex in pitcher.data.vertices:
        point=gp(vertex.co)
        if point[1]>.973 and point[2]>.241:
            vertex.co.y-=.008*max(0.,1.-abs(point[0]-.109)/.02)
    box('GrinderBase',(.19,.025,.22),(.32,.89,0),black,.008,4)
    box('GrinderBody',(.14,.23,.17),(.32,1.015,-.03),sage,.014,5)
    box('GrinderSpout',(.050,.070,.026),(.32,1.015,.067),steel,.005,3)
    # Independent thin amber hopper, actual beans behind it, original outer bounds.
    amber=material('Coffee_HopperGlass',(.48,.29,.11),alpha=.25)
    hollow_cup('BeanHopper',(.32,1.13,-.03),.07,.16,amber,.0015,False)
    for index in range(18):
        angle=index*2.399963;rad=.016+.025*((index%4)/3);y=1.15+.012*(index//6)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10,ring_count=6,radius=1,location=p((.32+rad*math.cos(angle),y,-.03+rad*math.sin(angle))))
        bean=bpy.context.object;bean.name='CoffeeBean_%d'%index;bean.scale=(.010,.006,.007);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);bean.data.materials.append(grounds);bake_transform(bean);uv(bean,.1)
    cylinder('HopperCap',.075,.015,(.32,1.2975,-.03),black,'Y',40,.003)
    for index in range(3):
        x=-.32+index*.15
        hollow_cup('WarmCup%d'%index,(x,1.25,-.08),.037,.075,cream)
        cylinder('WarmCup%dCoffee'%index,.032,.002,(x,1.319,-.08),grounds,'Y',32,0)
    DETAILS['P_coffee_station']={'worktop_y':.875,'operator_hand':[-.29,1.075,.28],'body_corner_radius_m':.012,'worktop_radius_m':.012,'bevel_segments':5,'true_open_work_bay':True,'hollow_cups':4,'open_drip_grid_bars':10,'transparent_hopper_with_actual_beans':18,'pitcher_base_y':.9035,'pitcher_centre_xz':[.109,.216],'steam_tip_in_pitcher':[.13,.96,.23],'original_machine_body_envelope':[[-.425,.875,-.275],[.145,1.245,.115]]}

def bounds():
    points=[gp(obj.matrix_world@v.co) for obj in bpy.context.scene.objects if obj.type=='MESH' for v in obj.data.vertices]
    low=[min(point[a] for point in points) for a in range(3)];high=[max(point[a] for point in points) for a in range(3)]
    return {'min_godot':low,'max_godot':high,'godot_size_m_xyz':[high[a]-low[a] for a in range(3)]}

def save(aid):
    OUT.mkdir(parents=True,exist_ok=True)
    for obj in bpy.context.scene.objects:
        if obj.type=='MESH':uv(obj)
    report=bounds()
    expected={'P_deck_oven':[1.46,2.08,.9548],'P_coffee_station':[1.0,1.326,.685]}[aid]
    if max(abs(report['godot_size_m_xyz'][axis]-expected[axis]) for axis in range(3))>.008:
        raise RuntimeError('Refusing changed physical envelope: '+aid+' '+str(report))
    meshes=[obj for obj in bpy.context.scene.objects if obj.type=='MESH']
    report.update({'id':aid,'input':str((SOURCE/(aid+'.glb')).relative_to(ROOT)),'input_sha256':sha(SOURCE/(aid+'.glb')),'triangles':sum(len(face.vertices)-2 for obj in meshes for face in obj.data.polygons),'authoring_mesh_nodes':sorted(obj.name for obj in meshes),'materials':sorted({mat.name for obj in meshes for mat in obj.data.materials if mat}),'geometry':DETAILS[aid]})
    path=OUT/(aid+'.glb');blend=OUT/(aid+'.blend')
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    # Keep individual authoring hardware, but batch opaque game parts by material.
    # Panes/hopper remain independent for transparent sorting and clear sight lines.
    for obj in meshes:
        if len(obj.data.materials)<=1:continue
        bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.separate(type='MATERIAL');bpy.ops.object.mode_set(mode='OBJECT')
    meshes=[obj for obj in bpy.context.scene.objects if obj.type=='MESH']
    groups={}
    for obj in meshes:
        if len(obj.data.materials)!=1:continue
        mat=obj.data.materials[0]
        if mat.name in ['Oven_HeatGlass','Coffee_HopperGlass']:continue
        groups.setdefault(mat.name,[]).append(obj)
    for label,objects in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:obj.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        if len(objects)>1:bpy.ops.object.join()
        objects[0].name=label+'_Geometry'
    report['mesh_nodes']=sorted(obj.name for obj in bpy.context.scene.objects if obj.type=='MESH')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_yup=True,export_apply=True,export_animations=False,export_image_format='AUTO')
    report.update({'raw':str(path.relative_to(ROOT)),'raw_sha256':sha(path),'authoring':str(blend.relative_to(ROOT)),'authoring_sha256':sha(blend)})
    return report

reports={}
if MANIFEST.exists():reports=json.loads(MANIFEST.read_text()).get('assets',{})
for aid,build in [('P_deck_oven',oven),('P_coffee_station',coffee)]:
    if any(arg.startswith('--only=') for arg in ARGS) and '--only='+aid not in ARGS:continue
    build();reports[aid]=save(aid)
fragment={aid:{'src':'raw/appliance_forms_20261014/'+aid+'.glb','preserve_parts':True,'preserve_origin':True,'level':False,'tex':2048,'image_format':'AUTO','provider':'Blender in-place rounded appliance rebuild from approved imagegen reference, 2026-10-14','license':'项目自制；原模型及生成贴图授权沿用'} for aid in reports}
manifest={'date':'2026-10-14','script':str(Path(__file__).relative_to(ROOT)),'script_sha256':sha(__file__),'assets':reports,'config_fragment':fragment,'texture_files':{name:{'path':str((TEXTURES/name).relative_to(ROOT)),'present':(TEXTURES/name).exists(),'sha256':sha(TEXTURES/name) if (TEXTURES/name).exists() else None} for name in ['oven_enamel_albedo.png','brushed_steel_albedo.png']}}
MANIFEST.parent.mkdir(parents=True,exist_ok=True);MANIFEST.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(OUT/'game_assets.fragment.json').write_text(json.dumps({'assets':fragment},ensure_ascii=False,indent=2)+'\n')
print('APPLIANCE_FORMS',json.dumps(manifest,ensure_ascii=False))

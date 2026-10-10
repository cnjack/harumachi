"""Precise joinery from the accepted 2026-10-10 imagegen room layouts.

Coordinates here are Godot metres; convert to Blender Z-up at creation.
Blender -b --factory-startup -P art/tools/inhabited_fixtures.py
"""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/models/raw/inhabited_places_20261010'
OUT.mkdir(parents=True,exist_ok=True)
M={}
def mat(name,hexcode):
    if name in M:return M[name]
    rgb=[int(hexcode[i:i+2],16)/255 for i in (0,2,4)]
    rgb=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m=bpy.data.materials.new(name);m.use_nodes=True
    b=m.node_tree.nodes['Principled BSDF'];b.inputs['Base Color'].default_value=(*rgb,1)
    b.inputs['Roughness'].default_value=.9
    if name in ('Cedar','CedarDark'):
        tex=m.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image=bpy.data.images.load(str(ROOT/'game/assets/textures/three_places/quiet_pine_grain.png'),check_existing=True)
        mix=m.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=.32;mix.inputs[1].default_value=(*rgb,1)
        m.node_tree.links.new(tex.outputs['Color'],mix.inputs[2]);m.node_tree.links.new(mix.outputs[0],b.inputs['Base Color'])
    M[name]=m;return m
def p(v):return (v[0],-v[2],v[1])
def box(name,size,at,m,bevel=.008):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p(at));o=bpy.context.object;o.name=name
    o.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(m)
    if bevel:
        mod=o.modifiers.new('Joinery edges','BEVEL');mod.width=bevel;mod.segments=1
        bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
    return o
def cyl(name,r,h,at,m,segments=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments,radius=r,depth=h,location=p(at));o=bpy.context.object;o.name=name;o.data.materials.append(m);return o
def rod(name,a,b,r,m):
    o=cyl(name,r,(Vector(p(b))-Vector(p(a))).length,[(a[i]+b[i])/2 for i in range(3)],m,12)
    o.rotation_mode='QUATERNION';o.rotation_quaternion=Vector((0,0,1)).rotation_difference(Vector(p(b))-Vector(p(a)));return o
def marker(name,at,yaw=0):
    o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=p(at);o.rotation_euler.z=math.radians(yaw);return o
def table(name,at,w,d,h=.75):
    box(name+'Top',(w,.055,d),(at[0],h-.0275,at[2]),cedar)
    for x in (-w/2+.08,w/2-.08):
        for z in (-d/2+.08,d/2-.08):box(name+'Leg',(.055,h-.055,.055),(at[0]+x,(h-.055)/2,at[2]+z),dark)
def chair(name,x,z,yaw=0,arm=False):
    before=set(bpy.data.objects)
    box(name+'Seat',(.48,.065,.47),(0,.4475,0),sage if arm else cedar)
    box(name+'Back',(.48,.40,.055),(0,.69,-.22),sage if arm else cedar)
    for dx in (-.19,.19):
        for dz in (-.18,.18):box(name+'Leg',(.045,.415,.045),(dx,.2075,dz),dark)
    if arm:
        for dx in (-.275,.275):
            box(name+'Arm',(.055,.055,.51),(dx,.64,0),cedar)
            box(name+'Post',(.035,.17,.035),(dx,.53,.18),dark)
    for o in set(bpy.data.objects)-before:
        o.location=Vector(p((x,0,z)))+Vector((math.cos(math.radians(yaw))*o.location.x-math.sin(math.radians(yaw))*o.location.y, math.sin(math.radians(yaw))*o.location.x+math.cos(math.radians(yaw))*o.location.y,o.location.z))
        o.rotation_euler.z+=math.radians(yaw)
    marker(name+'SeatPoint',(x,.48,z),yaw)
def cup(name,x,y,z):
    cyl(name,.037,.075,(x,y+.0375,z),cream);cyl(name+'Coffee',.031,.002,(x,y+.075,z),coffee)
    bpy.ops.mesh.primitive_torus_add(major_radius=.021,minor_radius=.006,major_segments=12,minor_segments=6,location=p((x+.043,y+.04,z)),rotation=(math.pi/2,0,0));bpy.context.object.name=name+'Handle';bpy.context.object.data.materials.append(cream)
def shelf(name,width,heights,depth=.5,linen=False):
    h=max(heights)+.25
    for x in (-width/2+.025,width/2-.025):box('ShelfUpright',(.045,h,.045),(x,h/2,-depth/2+.025),dark)
    box('ShelfBack',(width,.20,.03),(0,h-.10,-depth/2+.015),sage)
    for i,y in enumerate(heights):
        box('TrayBoard_%d'%i,(width,.035,depth),(0,y-.0175,0),cedar)
        if linen:box('LinenLiner_%d'%i,(width-.06,.004,depth-.07),(0,y+.002,0),cream,0)
        box('TrayLip_%d'%i,(width,.07,.025),(0,y+.017,depth/2-.0125),cedar)
    box('ShelfFoot',(width,.06,depth),(0,.03,0),dark)
def build(aid):
    if aid=='P_community_table':
        table('Shared',(0,0,0),2.05,1.0)
        for x in (-.68,0,.68):
            chair('ChairBack',x,-.87);chair('ChairFront',x,.87,180)
    elif aid=='P_cafe_table':
        cyl('RoundTop',.36,.05,(0,.735,0),cedar,40);cyl('Pedestal',.045,.70,(0,.35,0),dark);cyl('Foot',.22,.035,(0,.0175,0),dark)
        chair('ChairLeft',-.70,0,90);chair('ChairRight',.70,0,-90)
    elif aid=='P_reading_chair':chair('ReadingChair',0,0,0,True)
    elif aid=='P_low_bookcase':
        shelf('Books',1.35,[.12,.48,.84],.34)
        colors=[mat('Book%d'%i,c) for i,c in enumerate(['b2b9a1','b57963','d8caa0','819dad','c6b598'])]
        for row,y in enumerate([.12,.48]):
            for i in range(16):box('Book_%d_%d'%(row,i),(.058,.21+(i%4)*.025,.19),(-.54+i*.072,y+.13+(i%4)*.0125,.02),colors[(i+row)%5],.002)
    elif aid=='P_coffee_station':
        box('Cabinet',(.96,.83,.62),(0,.415,0),sage);box('Worktop',(1.0,.045,.66),(0,.8525,0),cedar)
        for x in (-.24,.24):
            box('Door',(.44,.66,.025),(x,.43,.322),sage);box('DoorHandle',(.12,.018,.02),(x,.65,.345),brass)
        box('MachineBody',(.57,.37,.39),(-.14,1.06,-.08),steel)
        box('MachineSide',(.045,.38,.41),(-.445,1.06,-.08),dark)
        box('ControlFace',(.53,.095,.025),(-.14,1.195,.126),steel)
        box('DripTray',(.58,.027,.24),(-.14,.89,.105),black)
        for x in (-.29,-.05):
            cyl('GroupHead',.042,.045,(x,1.09,.135),steel);rod('Portafilter',(x,1.075,.135),(x,1.075,.28),.013,black)
            cyl('Dial',.019,.008,(x,1.195,.15),cream).rotation_euler.x=math.pi/2
        rod('SteamWand',(.08,1.12,.12),(.13,.96,.23),.008,steel)
        cyl('Pitcher',.035,.075,(.14,.92,.12),steel)
        box('GrinderBase',(.19,.025,.22),(.32,.89,0),black)
        box('GrinderBody',(.14,.23,.17),(.32,1.015,-.03),sage)
        cyl('BeanHopper',.07,.16,(.32,1.21,-.03),coffee)
        cyl('HopperCap',.075,.015,(.32,1.2975,-.03),black)
        for i in range(3):cup('WarmCup%d'%i,-.32+i*.15,1.25,-.08)
    elif aid in ('W24_sugar_pack','W25_salt_box','W26_miso_tub','W27_curry_box','W28_seed_packets'):
        if aid=='W26_miso_tub':
            cyl('MisoTub',.065,.115,(0,.0575,0),mat('MisoOchre','b88751'))
            cyl('Lid',.069,.012,(0,.121,0),cream)
            box('FrontLabel',(.075,.055,.006),(0,.067,.065),cream,.002)
        else:
            specs={'W24_sugar_pack':(.16,.23,.075,'c8a1a0'),'W25_salt_box':(.13,.18,.075,'b3cad1'),'W27_curry_box':(.16,.22,.08,'b99654'),'W28_seed_packets':(.085,.115,.008,'9db88b')}
            w,h,d,col=specs[aid]
            bodymat=mat('Package',col)
            box('Package',(w,h,d),(0,h/2,0),bodymat,.006)
            box('Label',(w*.78,h*.64,.002),(0,h*.53,d/2+.001),cream,.001)
            box('Band',(w,h*.13,.003),(0,h*.18,d/2+.002),bodymat,.001)
            cyl('LabelMark',w*.18,.002,(0,h*.64,d/2+.003),bodymat,16).rotation_euler.x=math.pi/2
    elif aid=='W17_display_shelf':shelf('DailyBread',1.09,[.35,.65,1.0],.5,True)
    elif aid=='I05_bread_shelf':shelf('WallBread',1.07,[.27,.61,.94,1.26],.62,True)
    elif aid=='I04_shop_counter':
        box('CounterBody',(2.05,.82,1.09),(0,.41,0),sage)
        box('CounterTop',(2.11,.05,1.15),(0,.845,0),cedar)
        for x in (-.68,0,.68):box('FrontPanel',(.61,.64,.025),(x,.42,.553),cream)
        box('FootRail',(2.04,.045,.045),(0,.12,.60),brass)
        box('RegisterBase',(.32,.07,.26),(.60,.905,-.20),black)
        box('Register',(.28,.28,.10),(.60,1.08,-.27),steel)
        box('Display',(.23,.12,.006),(.60,1.12,-.214),black)
        for i in range(4):box('RegisterKey',(.035,.009,.035),(.51+i*.052,.945,-.10),cream,.002)
    elif aid=='I03_drink_fridge':
        box('FridgeRear',(1.40,1.92,.07),(0,.96,-.35),sage)
        for x in (-.665,.665):box('FridgeSide',(.07,1.92,.77),(x,.96,0),cream)
        box('FridgeTop',(1.4,.14,.77),(0,1.85,0),cream);box('FridgeBase',(1.4,.14,.77),(0,.07,0),cream)
        for y in (.28,.66,1.04,1.42):box('ColdShelf',(1.25,.024,.62),(0,y-.012,0),steel)
        for x in (-.67,0,.67):box('DoorFrame',(.035,1.65,.03),(x,.96,.393),dark)
        for y in (.14,1.78):box('DoorRail',(1.36,.035,.035),(0,y,.393),dark)
        for x in (-.08,.08):box('DoorPull',(.018,.45,.04),(x,1.03,.425),brass)
        glass=mat('Glass','d9e8dd');b=glass.node_tree.nodes['Principled BSDF'];b.inputs['Alpha'].default_value=.12;glass.surface_render_method='BLENDED'
        for x in (-.335,.335):box('GlassDoor',(.63,1.60,.004),(x,.96,.395),glass,0)
    else:raise KeyError(aid)

ids=['P_community_table','P_cafe_table','P_reading_chair','P_low_bookcase','P_coffee_station','W17_display_shelf','I05_bread_shelf','I04_shop_counter','I03_drink_fridge','W24_sugar_pack','W25_salt_box','W26_miso_tub','W27_curry_box','W28_seed_packets']
only=set(sys.argv[sys.argv.index("--")+1:]) if "--" in sys.argv else set()
for aid in ids:
    if only and aid not in only:continue
    bpy.ops.wm.read_factory_settings(use_empty=True);M={}
    cedar=mat('Cedar','b48960');dark=mat('CedarDark','765440');sage=mat('Sage','899d89');cream=mat('Cream','eee8d8');steel=mat('BrushedSteel','a5aba5');black=mat('Charcoal','393d3b');brass=mat('Brass','b79a64');coffee=mat('Coffee','69462e')
    build(aid)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(aid+'.glb')),export_format='GLB',export_extras=True)
spec=json.loads((ROOT/'art/models/game_assets.json').read_text())
for aid in ids:
    spec['assets'][aid]={'src':'raw/inhabited_places_20261010/'+aid+'.glb','preserve_parts':True,'preserve_origin':True,'level':False,'tex':1024,'provider':'Blender precise joinery from imagegen inhabited room references','reference_images':['art/references/inhabited_places_20261010/'+ ('community_living_layout.png' if aid in ids[:1]+ids[2:4] else ('grocer_grouped_layout.png' if aid.startswith('W2') or aid=='I03_drink_fridge' else 'bakery_cafe_layout.png'))],'license':'项目自制；生成素材服务条款'}
(ROOT/'art/models/game_assets.json').write_text(json.dumps(spec,ensure_ascii=False,indent=2)+'\n')

"""Measured Japanese architectural components for close-up game views.

Blender -b --factory-startup -P art/tools/precise_houses.py -- [H01 H02 H03 S06]
Design/layout retains the Rodin references; structural geometry is authored here.
All authoring coordinates are Godot XYZ metres, converted once to Blender Z-up.
"""
import bpy
import bmesh
import json
import math
import sys
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/models/raw/precise_houses_20261002'
OUT.mkdir(parents=True,exist_ok=True)
TEXTURES=ROOT/'art/references/architecture_closeup_20261002'
BOUNDS=json.loads((ROOT/'art/models/model_quality_contracts.json').read_text())['bounds_godot']
ONLY=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
GROUPS={};MATS={};MEMBERS=[];TEXT=[];EXTRAS=[]

def bcoord(p):return (p[0],-p[2],p[1])

def linear(hexcode):
    a=[int(hexcode[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in a)

def mat(name,colour,texture=None):
    if name in MATS:return name
    m=bpy.data.materials.new(name);m.use_nodes=True
    bs=m.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(*linear(colour),1)
    bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0
    if texture:
        img=bpy.data.images.load(str(TEXTURES/(texture+'.png')),check_existing=True)
        tx=m.node_tree.nodes.new('ShaderNodeTexImage');tx.image=img
        m.node_tree.links.new(tx.outputs['Color'],bs.inputs['Base Color'])
    MATS[name]=(m,colour,texture);return name

def setup():
    mat('cedar','ffffff','cedar');mat('cedar_dark','876b4c','cedar');mat('cedar_light','dfcba7','cedar')
    mat('plaster','ffffff','plaster');mat('kawara','ffffff','kawara');mat('kawara_dark','9aadc2','kawara')
    mat('wood_end','9d7954','cedar');mat('stone','aaa997','plaster');mat('concrete','c5c6bf','plaster')
    mat('deep_reveal','39474c');mat('glass','ffffff','glass');mat('curtain','e6e1ce','plaster')
    mat('paper','ece6d5','plaster');mat('metal','526675');mat('olive_metal','5a715e')
    mat('ink','344655');mat('lamp','f8e8b2');mat('ceramic','cdd1c9','plaster')
    mat('cloth_cream','eee8d0','plaster');mat('cloth_mint','81ac8a','plaster');mat('cloth_blue','8fa9bf','plaster')
    mat('crate_green','4e7966');mat('red','b54b42');mat('produce','ffffff','produce')
    mat('bread_gold','d6a65f');mat('bread_score','efe2be')

def geometry(role,verts,faces,material,uvs=None,smooth=False):
    group=GROUPS.setdefault(material,{'verts':[],'faces':[],'uvs':[],'smooth':[]})
    base=len(group['verts']);group['verts']+=list(map(bcoord,verts))
    group['faces'] += [tuple(base+i for i in f) for f in faces]
    group['uvs'] += uvs or [[(0,0),(1,0),(1,1),(0,1)][:len(f)] for f in faces]
    group['smooth'] += [smooth]*len(faces)
    MEMBERS.append({'role':role,'min':[min(p[a] for p in verts) for a in range(3)],'max':[max(p[a] for p in verts) for a in range(3)]})

def box(role,size,centre,material='cedar'):
    dx,dy,dz=size;cx,cy,cz=centre
    vs=[(cx+x*dx/2,cy+y*dy/2,cz+z*dz/2) for x in [-1,1] for y in [-1,1] for z in [-1,1]]
    faces=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
    uvs=[];major=max(range(3),key=lambda a:size[a]);offset=(len(MEMBERS)*.173)%1
    for face in faces:
        a,b,c=[Vector(vs[i]) for i in face[:3]];normal=(b-a).cross(c-a);axis=max(range(3),key=lambda k:abs(normal[k]))
        if material.startswith(('cedar','wood')):
            vaxis=major if major!=axis else next(k for k in range(3) if k!=axis)
            uaxis=next(k for k in range(3) if k not in (axis,vaxis));scales=(.45,1.4)
        else:
            uaxis,vaxis=[k for k in range(3) if k!=axis];scales=(1.4,1.4)
        uvs.append([(vs[i][uaxis]/scales[0]+offset,vs[i][vaxis]/scales[1]+offset) for i in face])
    geometry(role,vs,faces,material,uvs)

def beam(role,a,b,width=.05,depth=.05,material='cedar_dark'):
    a,b=Vector(a),Vector(b);axis=(b-a).normalized();u=axis.cross(Vector((0,0,1)))
    if u.length<.1:u=axis.cross(Vector((1,0,0)))
    u.normalize();v=axis.cross(u).normalized();vs=[]
    for p in [a,b]:
        for su,sv in [(-1,-1),(1,-1),(1,1),(-1,1)]:vs.append(tuple(p+u*su*width/2+v*sv*depth/2))
    faces=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    geometry(role,vs,faces,material,[[(0,0),(1,0),(1,(b-a).length/1.4),(0,(b-a).length/1.4)] for f in faces])

def cylinder(role,centre,axis,radius,length,material='metal',segments=16):
    c=Vector(centre);d=Vector(axis).normalized();u=d.cross(Vector((0,1,0)))
    if u.length<.1:u=d.cross(Vector((1,0,0)))
    u.normalize();v=d.cross(u);vs=[]
    for side in [-1,1]:
        for i in range(segments):vs.append(tuple(c+d*side*length/2+radius*(u*math.cos(i*math.tau/segments)+v*math.sin(i*math.tau/segments))))
    faces=[tuple(reversed(range(segments))),tuple(range(segments,segments*2))]
    faces += [(i,(i+1)%segments,(i+1)%segments+segments,i+segments) for i in range(segments)]
    geometry(role,vs,faces,material,[[((i%segments)/segments,(i//segments)) for i in f] for f in faces],True)

def face_point(face,u,y,plane,out=0):
    if face=='front':return (u,y,plane+out)
    if face=='back':return (u,y,plane-out)
    if face=='right':return (plane+out,y,u)
    return (plane-out,y,u)

def face_box(role,face,u,y,plane,span,height,thick,material,out=0):
    size=(span,height,thick) if face in ['front','back'] else (thick,height,span)
    box(role,size,face_point(face,u,y,plane,out),material)

def wall(face,length,plane,floor,eave,holes,cladding=1.05,u_centre=0):
    wall_left=u_centre-length/2;wall_right=u_centre+length/2
    xs=sorted(set([wall_left,wall_right]+[v for h in holes for v in h[:2]]))
    ys=sorted(set([floor,eave]+[v for h in holes for v in h[2:4]]))
    for x0,x1 in zip(xs,xs[1:]):
        for y0,y1 in zip(ys,ys[1:]):
            x,y=(x0+x1)/2,(y0+y1)/2
            if any(h[0]<x<h[1] and h[2]<y<h[3] for h in holes):continue
            face_box('shikkui_wall',face,x,y,plane,x1-x0,y1-y0,.13,'plaster')
    top=min(eave,cladding)
    rows=math.ceil((top-floor)/.14)
    for i in range(max(rows,0)):
        y0=floor+i*.14;y1=min(top,y0+.14)
        cuts=sorted(set([wall_left,wall_right]+[v for h in holes if h[2]<y1 and h[3]>y0 for v in h[:2]]))
        for x0,x1 in zip(cuts,cuts[1:]):
            x=(x0+x1)/2
            if any(h[0]<x<h[1] and h[2]<y1 and h[3]>y0 for h in holes):continue
            face_box('shitami_ita',face,x,(y0+y1)/2,plane,x1-x0,y1-y0-.006,.022,'cedar',.087)
    for u in [wall_left,wall_right]:face_box('hashira',face,u,(floor+eave)/2,plane,.14,eave-floor,.16,'cedar_dark',.055)
    for y in [floor+.08,eave-.08]:face_box('nageshi',face,u_centre,y,plane,length+.12,.13,.16,'cedar_dark',.045)

def frame(face,u,y0,width,height,plane,kind='window',panels=2):
    face_box('window_reveal',face,u,y0+height/2,plane,width+.035,height+.035,.08,'deep_reveal',-.023)
    for x in [u-width/2,u+width/2]:face_box('straight_jamb',face,x,y0+height/2,plane,.075,height+.15,.18,'cedar_dark',.045)
    for y in [y0,y0+height]:face_box('straight_lintel',face,u,y,plane,width+.15,.075,.18,'cedar_dark',.045)
    for i in range(panels):
        x=u-width/2+(i+.5)*width/panels;pw=width/panels-.055
        face_box('shoji_paper' if kind=='shoji' else 'window_glass',face,x,y0+height/2,plane,pw,height-.055,.015,'paper' if kind=='shoji' else 'glass',.01)
        if kind=='shoji':
            for j in range(1,7):face_box('kumiko_horizontal',face,x,y0+j*height/7,plane,pw,.012,.014,'cedar_light',.028)
            for j in [-1,1]:face_box('kumiko_vertical',face,x+j*pw/6,y0+height/2,plane,.012,height-.07,.014,'cedar_light',.03)
        else:
            face_box('curtain',face,x-pw*.32,y0+height/2,plane,pw*.2,height-.07,.007,'curtain',.018)
            face_box('glass_transom',face,x,y0+height*.46,plane,pw,.025,.025,'cedar_dark',.039)
        if i<panels-1:face_box('sliding_mullion',face,u-width/2+(i+1)*width/panels,y0+height/2,plane,.045,height,.075,'cedar_dark',.05)
    for y in [y0-.055,y0-.03]:face_box('sliding_track',face,u,y,plane,width+.19,.015,.21,'cedar_dark',.06)
    face_box('window_sill',face,u,y0-.1,plane,width+.24,.045,.30,'cedar',.09)

def shutter(face,u,y0,width,height,plane):
    face_box('amado_shutter',face,u,y0+height/2,plane,width,height,.045,'cedar',.085)
    for y in [y0+.035,y0+height-.035]:face_box('amado_rail',face,u,y,plane,width,.045,.055,'cedar_dark',.095)
    for j in range(1,math.ceil(height/.115)):face_box('amado_board',face,u,y0+j*.115,plane,width-.055,.017,.052,'cedar_dark',.105)

def text(value,centre,size=.13,material='ink'):
    curve=bpy.data.curves.new('Lettering','FONT');curve.body=value;curve.align_x='CENTER';curve.size=size;curve.extrude=.0008;curve.resolution_u=3
    curve.font=bpy.data.fonts.load(str(ROOT/'game/assets/fonts/LXGWWenKai-Medium.ttf'))
    o=bpy.data.objects.new('Lettering_'+value,curve);bpy.context.collection.objects.link(o);o.location=bcoord(centre);o.rotation_euler.x=math.pi/2;o.data.materials.append(MATS[material][0]);TEXT.append(o)

def existing_prop(aid,centre,height):
    before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(ROOT/'game/assets/models'/f'{aid}.glb'))
    meshes=[o for o in bpy.context.scene.objects if o not in before and o.type=='MESH']
    points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    lo=Vector([min(p[a] for p in points) for a in range(3)]);hi=Vector([max(p[a] for p in points) for a in range(3)])
    scale=height/(hi.z-lo.z);base=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));target=Vector(bcoord(centre))
    for o in meshes:
        mw=o.matrix_world.copy()
        for v in o.data.vertices:v.co=(mw@v.co-base)*scale+target
        o.parent=None;o.matrix_world.identity();EXTRAS.append(o)

def bread_icon(centre):
    before=set(bpy.context.scene.objects);bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=10,radius=1,location=bcoord(centre))
    o=bpy.context.object;o.name='Bread_Sign';o.scale=(.57,.075,.17);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(MATS['bread_gold'][0]);EXTRAS.append(o)
    for dx in [-.25,0,.25]:beam('bread_score',(centre[0]+dx-.05,centre[1]-.09,centre[2]+.076),(centre[0]+dx+.05,centre[1]+.09,centre[2]+.076),.018,.012,'bread_score')

def door(u,y0,plane,number=None,sliding=False):
    w=1.0;h=2.08
    frame('front',u,y0,w,h,plane,'shoji' if sliding else 'window',2 if sliding else 1)
    if not sliding:
        face_box('door_lower_panel','front',u,y0+.46,plane,.84,.79,.035,'cedar',.04)
        for x in [u-.28,u+.28]:face_box('door_panel_stile','front',x,y0+.46,plane,.028,.65,.04,'cedar_dark',.055)
        cylinder('door_handle',face_point('front',u+.34,y0+1.03,plane,.12),(0,1,0),.018,.17,'metal',12)
    face_box('threshold','front',u,y0-.02,plane,1.22,.055,.36,'stone',.05)
    face_box('intercom','front',u+.64,y0+1.28,plane,.105,.2,.04,'ceramic',.09)
    for j in range(4):face_box('intercom_slot','front',u+.64,y0+1.3+j*.015,plane,.066,.004,.045,'metal',.112)
    if number:
        face_box('room_plate','front',u,y0+2.21,plane,.32,.14,.04,'ceramic',.10);text(number,face_point('front',u,y0+2.17,plane,.13),.10)
    face_box('genkan_light','front',u-.68,y0+1.82,plane,.15,.24,.11,'metal',.07)
    face_box('lamp_glass','front',u-.68,y0+1.82,plane,.10,.19,.014,'lamp',.135)

def roof(ridge_axis,width,depth,eave,ridge,centre_z=0,gable_inset=.4):
    # Eight-segment curved ceramic profiles, overlap, round noki tile ends.
    along=width if ridge_axis=='x' else depth;across=depth if ridge_axis=='x' else width
    half=across/2;top=ridge-.11;rise=top-eave;length=math.hypot(half,rise)
    cols=math.ceil(along/.29);rows=math.ceil(length/.32);cw=along/cols;step=length/rows
    for side in [-1,1]:
        down=Vector((0,-rise/length,side*half/length)) if ridge_axis=='x' else Vector((side*half/length,-rise/length,0))
        lateral=Vector((1,0,0)) if ridge_axis=='x' else Vector((0,0,1))
        normal=Vector((0,half/length,side*rise/length)) if ridge_axis=='x' else Vector((side*rise/length,half/length,0))
        for ci in range(cols):
            for ri in range(rows):
                middle=Vector((0,top,centre_z))+lateral*(-along/2+(ci+.5)*cw)+down*(ri*step)
                vs=[];segments=8
                for bottom in [False,True]:
                    for end in [0,1]:
                        for j in range(segments+1):
                            u=(j/segments-.5)*cw;relief=.058*(.5+.5*math.cos(j/segments*math.tau))+.032*end
                            q=middle+lateral*u+down*(end*(step+.025))+normal*(relief-(.025 if bottom else 0))
                            vs.append(tuple(q))
                n=segments+1;faces=[]
                for j in range(segments):faces.extend([(j,j+1,n+j+1,n+j),(2*n+j,3*n+j,3*n+j+1,2*n+j+1)])
                faces.extend([(0,n,3*n,2*n),(n-1,3*n-1,4*n-1,2*n-1)])
                for j in range(segments):faces.extend([(j,2*n+j,2*n+j+1,j+1),(n+j,n+j+1,3*n+j+1,3*n+j)])
                geometry('kawara_tile',vs,faces,'kawara',smooth=False)
            end=Vector((0,top,centre_z))+lateral*(-along/2+(ci+.5)*cw)+down*(length-.015)+normal*.053
            cylinder('noki_round_tile_end',tuple(end),tuple(down),.088,.024,'kawara',20)
            cylinder('tile_end_groove',tuple(end+down*.015),tuple(down),.045,.003,'kawara_dark',16)
        a=Vector((0,top,centre_z))+down*length-lateral*along/2;b=a+lateral*along
        beam('noki_fascia',tuple(a-normal*.07),tuple(b-normal*.07),.12,.15,'cedar_dark')
        for i in range(math.ceil(along/.42)):
            u=-along/2+.18+i*.42
            if abs(u)>along/2-.1:continue
            a=Vector((0,top,centre_z))+lateral*u+down*(length-.57)-normal*.085
            beam('exposed_rafter',tuple(a),tuple(a+down*.66),.065,.085,'cedar_dark')
    # Ridge cylinders stay below the specified maximum height.
    axis=(1,0,0) if ridge_axis=='x' else (0,0,1)
    ridge_c=Vector((0,ridge-.09,centre_z));cylinder('mune_ridge',tuple(ridge_c),axis,.09,along+.015,'kawara',20)
    for side in [-1,1]:
        p=ridge_c+Vector(axis)*side*(along/2-.02);cylinder('ridge_end',tuple(p),axis,.095,.06,'kawara_dark',20)
    # Real hafu boards trace the gable, with timber kingpost and triangular infill.
    for end in [-1,1]:
        def q(u,y):return (end*along/2,y,centre_z+u) if ridge_axis=='x' else (u,y,centre_z+end*along/2)
        def fill(u,y):
            p=list(q(u,y));p[0 if ridge_axis=='x' else 2]-=end*gable_inset;return tuple(p)
        geometry('gable_shikkui',[fill(-half+.32,eave-.03),fill(half-.32,eave-.03),fill(0,top-.06)],[(0,1,2),(2,1,0)],'plaster')
        for side in [-1,1]:beam('hafu_bargeboard',q(0,top-.045),q(side*half,eave-.045),.11,.10,'cedar_dark')
        beam('gable_tie_beam',q(-half+.23,eave+.015),q(half-.23,eave+.015),.10,.10,'cedar_dark')
        beam('gable_kingpost',q(0,eave+.06),q(0,top-.06),.10,.10,'cedar_dark')

def rainwater(body_w,front,eave):
    for x in [-body_w/2,body_w/2]:
        cylinder('downspout',(x,eave/2+.1,front+.105),(0,1,0),.035,eave-.25,'metal',12)
        for y in [.4,1.5,eave-.2]:face_box('pipe_clip','front',x,y,front,.105,.018,.10,'metal',.10)

def footprint(aid):
    b=BOUNDS[aid];w=b['max'][0]-b['min'][0];d=b['max'][2]-b['min'][2];h=b['max'][1]-b['min'][1]
    # The plot is paving flush with the road, not a raised box extending under
    # nearby street props. Structural plinths/steps are separate real solids.
    pts=[(-w/2,0,-d/2),(w/2,0,-d/2),(w/2,0,d/2),(-w/2,0,d/2)]
    geometry('paved_footprint',pts,[(0,3,2,1),(0,1,2,3)],'stone')
    return w,d,h

def apartment():
    w,d,h=footprint('H02');body_w=w-.72;front=1.48;back=-2.34;eave=5.47;ground=.18;upper=2.94
    units=[-3.60,-1.20,1.20,3.60];holes=[(u-.55,u+.55,floor,floor+2.16) for floor in [ground,upper+.08] for u in units]
    wall('front',body_w,front,ground,eave,holes,1.14)
    wall('back',body_w,back,ground,eave,[(u-.55,u+.55,y,y+.65) for y in [1.25,4.04] for u in units],eave)
    for u in units:
        for y in [1.25,4.04]:frame('back',u,y,1.1,.65,back)
    for face,plane in [('left',-body_w/2),('right',body_w/2)]:
        wall(face,3.82,plane,ground,eave,[(-.65,.55,y,y+.75) for y in [1.25,4.04]],eave,(front+back)/2)
        for y in [1.25,4.04]:frame(face,-.05,y,1.2,.75,plane)
    for floor,prefix in [(ground,'1'),(upper+.08,'2')]:
        for i,u in enumerate(units):door(u,floor,front,prefix+'0'+str(i+1))
    box('upper_corridor',(body_w+.06,.12,1.16),(0,upper-.06,2.02),'cedar_dark')
    for i in range(9):box('corridor_floorboard',(body_w,.021,.125),(0,upper+.01,1.49+i*.127),'cedar')
    # Full straight rail, with a clear landing at the right end.
    for x0,x1 in [(-4.70,3.43)]:
        for y in [upper+.14,upper+1.04]:box('balcony_horizontal_rail',(x1-x0,.055,.055),((x0+x1)/2,y,2.57),'cedar_dark')
        for i in range(math.ceil((x1-x0)/.24)):
            x=x0+.09+i*.24
            if x<x1:box('balcony_picket',(.035,.91,.045),(x,upper+.585,2.57),'cedar_dark')
        for x in [x0,-2.4,0,2.4,x1]:box('balcony_post',(.10,1.12,.10),(x,upper+.54,2.57),'cedar_dark')
    run=4.05;steps=16;rise=(upper-ground)/steps
    for i in range(steps):
        x=-.35+(i+.5)*run/steps;y=ground+(i+1)*rise
        box('stairs_tread',(run/steps+.018,.055,.75),(x,y-.028,2.21),'cedar')
        box('stairs_riser',(.035,rise,.75),(-.35+(i+1)*run/steps,ground+(i+.5)*rise,2.21),'cedar_dark')
    for z in [1.82,2.60]:
        beam('straight_stair_stringer',(-.35,ground-.03,z),(3.70,upper-.03,z),.10,.16,'metal')
        beam('straight_stair_handrail',(-.35,ground+.99,z),(3.70,upper+.99,z),.045,.055,'cedar_dark')
        for i in range(9):
            t=i/8;x=-.35+run*t;y=ground+(upper-ground)*t
            box('stairs_baluster',(.032,.96,.032),(x,y+.49,z),'metal')
    for x in [-4.60,-2.4,0,2.4,4.60]:box('corridor_support',(.13,upper-.10,.13),(x,upper/2,2.04),'cedar_dark')
    rainwater(body_w,front,eave);roof('x',w-.13,d-.18,eave,h)
    face_box('nameboard','front',-3.2,5.31,front,1.45,.30,.06,'cedar_dark',.15);text('晴町公寓',(-3.2,5.24,front+.19),.20,'paper')

def hall():
    w,d,h=footprint('S06');body_w=w-1.05;front=3.37;back=-4.63;eave=3.30;floor=.30
    wall('front',body_w,front,floor,eave,[(-1.8,1.8,floor,floor+2.29)],1.10)
    frame('front',0,floor,3.60,2.29,front,'window',4)
    for x in [-body_w/2+.20,body_w/2-.20]:
        for i in range(15):box('vertical_lattice_siding',(.035,2.77,.075),(x+i*.038*(-1 if x>0 else 1),1.72,front+.11),'cedar_dark')
    for face,plane in [('left',-body_w/2),('right',body_w/2)]:
        holes=[(u-.72,u+.72,1.00,2.33) for u in [-2.70,.0,2.70]]
        wall(face,8.0,plane,floor,eave,holes,eave,(front+back)/2)
        for u in [-2.70,0,2.70]:frame(face,u,1.0,1.44,1.33,plane)
    wall('back',body_w,back,floor,eave,[(-.55,.55,floor,2.38),(-3.1,-1.7,1.1,2.28),(1.7,3.1,1.1,2.28)],eave)
    for u in [-2.4,2.4]:frame('back',u,1.1,1.4,1.18,back)
    frame('back',0,floor,1.1,2.08,back,'shoji',2)
    box('porch_platform',(4.7,.3,1.63),(0,.15,4.10),'stone')
    for i in range(3):box('entrance_step',(3.55,.1,.31),(0,.05+i*.1,5.15-i*.3),'stone')
    # Sloped accessible ramp with cylindrical precise metal rails.
    for i in range(10):box('access_ramp',(.85,.03,.18),(-2.36,.015+i*.030,5.20-i*.16),'concrete')
    for x in [-2.78,-1.93]:
        beam('ramp_handrail',(x,.95,5.20),(x,1.23,3.7),.035,.035,'olive_metal')
        for z,y in [(5.16,.03),(4.5,.15),(3.76,.29)]:box('ramp_post',(.032,.9,.032),(x,y+.45,z),'olive_metal')
    for x in [-2.15,2.15]:box('porch_hashira',(.145,2.83,.145),(x,1.715,4.18),'cedar_dark')
    box('porch_lintel',(4.55,.17,.18),(0,3.08,4.18),'cedar_dark')
    roof('x',4.70,1.18,3.14,3.57,4.20,.02);roof('z',w-.17,9.06,eave,h,-.56,.61)
    face_box('kanban','front',0,3.00,4.90,2.17,.34,.07,'cedar_dark',0);text('晴町集会所',(0,2.91,4.947),.25,'paper')
    for i in range(8):box('gable_vent_slats',(.027,.35,.05),(-.30+i*.086,4.04,4.90),'cedar_dark')
    rainwater(body_w,front,eave)

def engawa():
    w,d,h=footprint('H03');body_w=w-1.02;front=1.19;back=-1.76;eave=2.86;floor=.46
    wall('front',body_w,front,floor,eave,[(-2.29,2.29,floor,2.50)],.75)
    frame('front',0,floor,4.58,2.04,front,'shoji',4)
    for x in [-2.84,2.84]:
        for i in range(8):box('koshi_side_screen',(.028,1.98,.07),(x+(i-3.5)*.062,1.48,front+.14),'cedar_dark')
    for face,plane in [('left',-body_w/2),('right',body_w/2)]:
        wall(face,2.95,plane,floor,eave,[(-.70,.70,1.05,2.23)],eave,(front+back)/2);frame(face,0,1.05,1.4,1.18,plane)
        shutter(face,1.05,1.05,.61,1.18,plane)
    wall('back',body_w,back,floor,eave,[(-2.45,-.85,1.03,2.18),(.85,2.45,1.03,2.18)],1.08)
    for u in [-1.65,1.65]:frame('back',u,1.03,1.6,1.15,back)
    for i in range(7):box('engawa_floorboard',(body_w+.24,.032,.13),(0,floor-.015,1.26+i*.133),'cedar')
    box('engawa_apron',(body_w+.22,.16,.08),(0,.35,2.17),'cedar_dark')
    for x in [-3,-2,-1,0,1,2,3]:box('engawa_post',(.11,.40,.12),(x,.20,2.06),'cedar_dark')
    for i in range(2):box('stone_genkan_step',(1.36,.20,.30),(0,.10+i*.18,2.25-i*.27),'stone')
    roof('x',w-.14,d-.25,eave,h,-.04);rainwater(body_w,front,eave)

def home():
    w,d,h=footprint('H01');body_w=w-1.13;front=2.57;back=-3.57;eave=5.64;floor=.22
    holes=[(-.16,.96,floor,2.39),(-.76,.76,3.83,5.04)]
    wall('front',body_w,front,floor,eave,holes,1.12);door(.40,floor,front,None,True)
    frame('front',0,3.83,1.52,1.21,front)
    shutter('front',-1.22,3.83,.62,1.21,front);shutter('front',1.22,3.83,.62,1.21,front)
    for face,plane in [('left',-body_w/2),('right',body_w/2)]:
        holes=[(u-.76,u+.76,y,y+1.23) for u in [-2.00,.70] for y in [1.06,3.79]]
        wall(face,6.14,plane,floor,eave,holes,1.02,(front+back)/2)
        for u in [-2.0,.7]:
            for y in [1.06,3.79]:frame(face,u,y,1.52,1.23,plane)
    wall('back',body_w,back,floor,eave,[(-2.0,-.55,y,y+1.15) for y in [1.06,3.80]]+[(.55,2.0,y,y+1.15) for y in [1.06,3.80]],1.1)
    for u in [-1.275,1.275]:
        for y in [1.06,3.80]:frame('back',u,y,1.45,1.15,back)
    for face,plane,length in [('front',front,body_w),('back',back,body_w),('left',-body_w/2,6.14),('right',body_w/2,6.14)]:face_box('storey_nageshi',face,0,2.92,plane,length+.08,.16,.18,'cedar_dark',.065)
    roof('z',w-.14,7.28,eave,h,-.46)
    roof('x',body_w+.64,1.31,2.72,3.17,front+.20)
    for x in [-1.4,1.43]:box('entry_hashira',(.12,2.42,.12),(x,1.45,front+.57),'cedar_dark')
    for i in range(2):box('genkan_step',(1.45,.11,.32),(.40,.055+i*.11,front+.91-i*.27),'stone')
    for a,b in [(-w/2+.13,-.36),(1.16,w/2-.13)]:box('garden_boundary', (b-a,.64,.17),((a+b)/2,.37,3.95),'plaster');box('garden_cap',(b-a+.06,.07,.22),((a+b)/2,.73,3.95),'stone')
    for x in [-.40,1.20]:box('gate_pier',(.26,.94,.27),(x,.50,3.94),'plaster');box('gate_cap',(.33,.08,.32),(x,1.0,3.94),'stone')
    for x in [-w/2+.14,w/2-.14]:box('side_garden_wall',(.17,.61,d-.25),(x,.36,0),'plaster')
    face_box('family_nameplate','front',1.20,.81,4.09,.14,.19,.027,'cedar_dark',.01);text('空',(1.2,.76,4.12),.13,'paper')
    rainwater(body_w,front,eave)

SHOP_PANES={
    'S01':[[-2.7,3.4,.25,2.05,2.42]],
    'S02':[[-2.55,.12,1.02,2.42,1.38],[1.65,2.45,.4,2.25,1.528]],
    'S03':[[-2.25,2.3,.3,2.45,1.994]],
    'S05':[[-2.,.3,.35,2.95,3.68]],
    'S08':[[-.95,1.3,.1,2.55,2.833]],
}

def awning(width,front,height,cloth):
    strips=math.ceil(width/.34);sw=width/strips
    for i in range(strips):
        x0=-width/2+i*sw;x1=x0+sw;back=front-.62;edge=front+.62
        vs=[(x0,height+.24,back),(x1,height+.24,back),(x1,height,edge),(x0,height,edge)]
        geometry('shop_canvas',vs,[(0,1,2,3),(3,2,1,0)],cloth if i%2==0 else 'cloth_cream')
        face_box('canvas_valance','front',(x0+x1)/2,height-.09,edge,sw-.005,.18,.012,cloth if i%2==0 else 'cloth_cream')
    beam('awning_front_rail',(-width/2,height,front+.60),(width/2,height,front+.60),.045,.045,'metal')
    for x in [-width/2+.12,width/2-.12]:beam('awning_support',(x,height-.60,front-.58),(x,height-.04,front+.59),.028,.028,'metal')

def produce_bin(x,width,quadrant):
    front=3.33;back=2.63;yfront=.78;yback=1.19
    for level in range(2):
        y=.13+level*.34
        box('produce_crate',(width,.30,.74),(x,y+.15,3.00),'crate_green')
        for i in range(7):face_box('crate_rib','front',x-width/2+(i+.5)*width/7,y+.15,3.375,.014,.24,.02,'metal')
        for yy in [y+.045,y+.255]:face_box('crate_stiffener','front',x,yy,3.375,width,.018,.024,'crate_green')
    vs=[(x-width/2,yfront,front),(x+width/2,yfront,front),(x+width/2,yback,back),(x-width/2,yback,back)]
    u0,u1,v0,v1=quadrant
    geometry('produce_display',vs,[(0,1,2,3),(3,2,1,0)],'produce',[[(u0,v0),(u1,v0),(u1,v1),(u0,v1)],[(u0,v1),(u1,v1),(u1,v0),(u0,v0)]])
    for side in [-1,1]:beam('produce_tray_rim',(x+side*width/2,yfront,front),(x+side*width/2,yback,back),.035,.035,'cedar_dark')
    beam('produce_tray_lip',(x-width/2,yfront,front),(x+width/2,yfront,front),.04,.055,'cedar_dark')
    face_box('produce_label','front',x,.61,3.395,.32,.17,.022,'ceramic');text('鲜蔬',(x,.565,3.411),.10)

def shop(aid):
    w,d,h=footprint(aid);body_w=w-.77;panes=SHOP_PANES[aid]
    front=max(p[4] for p in panes)-.10;back=-d/2+.52
    single=aid=='S05';eave=3.35 if single else 5.35;floor=.16
    holes=[(p[0],p[1],p[2],p[3]) for p in panes]
    if not single:holes.append((-1.6,1.6,3.67,4.98))
    door_u={'S01':.75,'S02':.9,'S03':3.05,'S05':1.55,'S08':-2.25}[aid]
    if aid not in ['S01','S02']:holes.append((door_u-.55,door_u+.55,floor,2.30))
    wall('front',body_w,front,floor,eave,holes,1.03)
    for p in panes:
        x0,x1,y0,y1,z=p
        # A glass front at z-.012 puts the existing room quad precisely in front.
        frame('front',(x0+x1)/2,y0,x1-x0,y1-y0,z-.0295,'window',max(1,round((x1-x0)/.93)))
    if aid not in ['S01','S02']:door(door_u,floor,front)
    if not single:
        # Separate upper room rather than a blank rear or side facade.
        frame('front',0,3.67,3.2,1.31,front,'window',4)
        for x in [-2.04,2.04]:shutter('front',x,3.67,.67,1.31,front)
        for x in [-1.55,-1.20,-.85,-.50,-.15,.20,.55,.90,1.25,1.55]:face_box('upper_koshi','front',x,4.32,front,.024,1.18,.032,'cedar_dark',.11)
        for y in [2.97,3.48]:face_box('machi_nageshi','front',0,y,front,body_w+.1,.12,.18,'cedar_dark',.08)
    depth=front-back
    for face,plane in [('left',-body_w/2),('right',body_w/2)]:
        window_us=[(front+back)/2]
        ys=[1.10] if single else [1.12,3.79]
        side_holes=[(u-.68,u+.68,y,y+1.13) for u in window_us for y in ys]
        wall(face,depth,plane,floor,eave,side_holes,eave,(front+back)/2)
        for u in window_us:
            for y in ys:frame(face,u,y,1.36,1.13,plane)
    rear_holes=[(u-.69,u+.69,y,y+1.15) for u in [-body_w*.23,body_w*.23] for y in ([1.08] if single else [1.08,3.80])]
    wall('back',body_w,back,floor,eave,rear_holes,1.1)
    for u in [-body_w*.23,body_w*.23]:
        for y in ([1.08] if single else [1.08,3.80]):frame('back',u,y,1.38,1.15,back)
    roof_centre=(front+back)/2
    roof('z' if single else 'x',w-.17,min(d-.19,depth+1.1),eave,h,roof_centre,.4)
    if not single:
        cloth={'S01':'cloth_mint','S02':'cloth_cream','S03':'cloth_blue','S08':'cloth_mint'}[aid]
        awning(body_w-.25,front+.60,2.58 if aid=='S02' else 2.48,cloth)
    else:
        roof('x',3.20,1.0,2.64,3.03,front+.34,.06)
    names={'S01':'晴町商店','S02':'莲的面包房','S03':'晴町花房','S05':'晴町邮局','S08':'晴町杂货店'}
    face_box('shop_kanban','front',0,3.14 if not single else 3.10,front,2.70,.42,.08,'cedar_dark',.15)
    text(names[aid],(0,3.03 if not single else 2.99,front+.197),.24,'paper')
    if aid=='S01':
        for x,width,uv in [(-2.45,1.22,(0,.5,.5,1)),(-.78,1.64,(0,.5,0,.5)),(2.55,1.65,(.5,1,.5,1))]:produce_bin(x,width,uv)
    elif aid=='S02':
        box('bread_sign',(1.14,.13,.28),(-1.7,2.98,front+.23),'cedar')
        text('パン',(-1.7,2.94,front+.39),.19,'ink')
        bread_icon((-2.55,3.14,front+.23))
    elif aid=='S05':
        box('postal_pillar',(.45,.97,.40),(-3.11,.54,front+.57),'red')
        face_box('postal_slot','front',-3.11,.91,front+.79,.30,.05,.012,'deep_reveal')
        text('〒',(-3.11,.62,front+.80),.20,'paper')
        face_box('postal_mark','front',3.13,2.57,front,.46,.48,.08,'red',.12);text('〒',(3.13,2.46,front+.165),.32,'paper')
    elif aid in ['S03','S08']:
        for x in [-2.8,2.7]:
            cylinder('ceramic_planter',(x,.22,front+.58),(0,1,0),.19,.32,'ceramic',16)
            for j in range(7):
                theta=j*math.tau/7
                beam('flower_stem',(x,.37,front+.58),(x+.13*math.cos(theta),.76,front+.58+.13*math.sin(theta)),.012,.012,'olive_metal')
                cx=x+.13*math.cos(theta);cz=front+.58+.13*math.sin(theta)
                cylinder('flower_centre',(cx,.76,cz),(0,.5,1),.02,.02,'lamp',12)
                for petal in range(5):
                    angle=petal*math.tau/5
                    cylinder('flower_petal',(cx+.039*math.cos(angle),.76+.039*math.sin(angle),cz+.012),(0,.5,1),.027,.012,'red' if j%2 else 'cloth_blue',12)
        if aid=='S03':
            for x in [-1.75,-.85,.85,1.65]:existing_prop('A14_hydrangea_pot',(x,.07,front+.78),.63)
        else:
            for x in [-body_w/2+.5,body_w/2-.5]:existing_prop('P_chochin_white',(x,1.86,front+.71),.49)
    rainwater(body_w,front,eave)

def narrow_house(aid):
    w,d,h=footprint(aid);body_w=w-.48;front=d/2-.25;back=-d/2+.25;floor=.16;eave=h-1.18
    door_w=min(1.0,body_w*.42);door_x=-body_w*.17
    holes=[(door_x-door_w/2,door_x+door_w/2,floor,2.26),(-body_w*.36,body_w*.36,3.58,4.87)]
    wall('front',body_w,front,floor,eave,holes,1.1)
    frame('front',door_x,floor,door_w,2.10,front,'shoji',2)
    frame('front',0,3.58,body_w*.72,1.29,front,'window',3)
    for i in range(12):face_box('machiya_koshi','front',-body_w*.32+i*body_w*.64/11,4.22,front,.021,1.18,.035,'cedar_dark',.11)
    for face,plane in [('left',-body_w/2),('right',body_w/2)]:
        wall(face,front-back,plane,floor,eave,[(-.40,.40,1.25,2.28),(-.40,.40,3.8,4.83)],eave)
        for y in [1.25,3.8]:frame(face,0,y,.8,1.03,plane)
    wall('back',body_w,back,floor,eave,[(-.5,.5,1.17,2.30),(-.5,.5,3.8,4.90)],eave)
    for y in [1.17,3.8]:frame('back',0,y,1.0,1.10,back)
    roof('z',w-.11,d-.14,eave,h,0,.19)
    roof('x',body_w+.23,.55,2.60,2.90,front+.03,.02)
    face_box('townhouse_name','front',body_w*.30,1.45,front,.20,.38,.04,'cedar_dark',.11)
    text('晴', (body_w*.30,1.37,front+.14),.18,'paper')

def modern_home():
    # The residential lane retains its contrasting white gabled two-storey home.
    w,d,h=footprint('M03_gable_house');body_w=w-.72;front=d/2-.75;back=-d/2+.65;floor=.20;eave=5.18
    holes=[(-.7,.7,floor,2.33),(-2.40,-.9,3.65,4.85),(.90,2.40,3.65,4.85)]
    wall('front',body_w,front,floor,eave,holes,.70);frame('front',0,floor,1.4,2.13,front,'shoji',2)
    for u in [-1.65,1.65]:frame('front',u,3.65,1.5,1.2,front);shutter('front',u+.94,3.65,.35,1.2,front)
    for face,plane in [('left',-body_w/2),('right',body_w/2)]:
        holes=[(-1.8,-.2,y,y+1.15) for y in [1.10,3.65]]
        wall(face,front-back,plane,floor,eave,holes,.72,(front+back)/2)
        for y in [1.10,3.65]:frame(face,-1.0,y,1.6,1.15,plane)
    wall('back',body_w,back,floor,eave,[(-1.9,-.5,y,y+1.15) for y in [1.1,3.65]]+[(.5,1.9,y,y+1.15) for y in [1.1,3.65]],.7)
    for u in [-1.2,1.2]:
        for y in [1.1,3.65]:frame('back',u,y,1.4,1.15,back)
    roof('z',w-.15,d-.20,eave,h,-.04,.6);roof('x',3.0,.98,2.65,3.04,front+.31,.04)
    for i in range(2):box('doorstep',(1.65,.10,.30),(0,.05+i*.10,front+.6-i*.25),'stone')
    rainwater(body_w,front,eave)

def save(aid,build):
    bpy.ops.wm.read_factory_settings(use_empty=True);GROUPS.clear();MATS.clear();MEMBERS.clear();TEXT.clear();EXTRAS.clear();setup();build()
    objects=[]
    for name,data in GROUPS.items():
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(data['verts'],[],data['faces']);mesh.update()
        uv=mesh.uv_layers.new(name='UVMap')
        for p,coords,smooth in zip(mesh.polygons,data['uvs'],data['smooth']):
            p.use_smooth=smooth
            for li,co in zip(p.loop_indices,coords):uv.data[li].uv=co
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces[:]);bm.to_mesh(mesh);bm.free()
        mesh.validate(clean_customdata=False)
        o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o);o.data.materials.append(MATS[name][0]);objects.append(o)
    for o in TEXT:
        bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH');objects.append(bpy.context.object)
    objects.extend(EXTRAS)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();ob=bpy.context.object;ob.name=aid
    # Exact collision footprint; roof caps can protrude by a few millimetres.
    bound=BOUNDS[aid];offset=((bound['min'][0]+bound['max'][0])/2,bound['min'][1],(bound['min'][2]+bound['max'][2])/2)
    lo=Vector([min(v.co[a] for v in ob.data.vertices) for a in range(3)])
    hi=Vector([max(v.co[a] for v in ob.data.vertices) for a in range(3)])
    target_lo=Vector((bound['min'][0],-bound['max'][2],bound['min'][1]));target_hi=Vector((bound['max'][0],-bound['min'][2],bound['max'][1]))
    fit_scale=[(target_hi[a]-target_lo[a])/(hi[a]-lo[a]) for a in range(3)]
    for v in ob.data.vertices:v.co=Vector([target_lo[a]+(v.co[a]-lo[a])*fit_scale[a] for a in range(3)])
    ob.data.validate(clean_customdata=False)
    for img in bpy.data.images:
        if img.size[0]>0:img.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{aid}.blend'))
    path=OUT/f'{aid}.glb';bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_animations=False,export_image_format='JPEG',export_jpeg_quality=95)
    # glTF baseColorFactor supplies tint on shared imagegen albedo textures.
    from edit_model_atlas import load
    import struct
    g,b=load(path)
    for m in g['materials']:
        if m['name'] in MATS:m.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=[*linear(MATS[m['name']][1]),1]
    enc=json.dumps(g,separators=(',',':')).encode();enc+=b' '*(-len(enc)%4);b+=b'\0'*(-len(b)%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(enc)+len(b))+struct.pack('<II',len(enc),0x4e4f534a)+enc+struct.pack('<II',len(b),0x004e4942)+b)
    (OUT/f'{aid}_members.json').write_text(json.dumps({'asset':aid,'geometry_source':'Blender measured components; Rodin layout reference','members':MEMBERS,'offset_godot':offset,'fit_scale_blender':fit_scale},ensure_ascii=False,indent=2))
    print('PRECISE_BUILD',aid,len(MEMBERS),sum(len(p.vertices)-2 for p in ob.data.polygons),path.stat().st_size)

sys.path.insert(0,str(Path(__file__).parent))
builds=[('H01',home),('H02',apartment),('H03',engawa),('S06',hall)]
builds += [(aid,lambda a=aid:shop(a)) for aid in ['S01','S02','S03','S05','S08']]
builds += [(aid,lambda a=aid:narrow_house(a)) for aid in ['M01_timber_machiya','M05_residential']]
builds += [('M03_gable_house',modern_home)]
if __name__ == '__main__':
    for aid,func in builds:
        if not ONLY or aid in ONLY:save(aid,func)

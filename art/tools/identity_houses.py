"""Individually designed, lived-in Japanese buildings from the approved concepts.

Blender -b --factory-startup -P art/tools/identity_houses.py -- H01 S01
Reuses precise joinery primitives, never a complete shared shop facade.
The original X/Z plot and ground origin are preserved without height stretching.
"""
import bpy, bmesh, json, math, sys, struct
from pathlib import Path
from contextlib import contextmanager
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).parent))
import precise_houses as p

ROOT=p.ROOT
OUT=ROOT/'art/models/raw/identity_houses_20261002'
OUT.mkdir(parents=True,exist_ok=True)
SHIFT=[0.,0.,0.];REMAP={};DISPLAY=False;CURRENT_AID=None
original_geometry=p.geometry

def geometry(role,verts,faces,material,uvs=None,smooth=False):
    material=REMAP.get(material,material)
    if DISPLAY:material+='__display'
    original_geometry(role,[tuple(v[a]+SHIFT[a] for a in range(3)) for v in verts],faces,material,uvs,smooth)
p.geometry=geometry
original_roof=p.roof
def bounded_roof(axis,width,depth,eave,ridge,centre_z=0,gable_inset=.4):
    if CURRENT_AID=='S05' and abs(width-3.20)<.01 and eave<3.0:width=4.80
    bound=p.BOUNDS[CURRENT_AID];w=bound['max'][0]-bound['min'][0];d=bound['max'][2]-bound['min'][2]
    width=min(width,w-2*(abs(SHIFT[0])+.13));depth=min(depth,d-2*(abs(centre_z+SHIFT[2])+.13))
    return original_roof(axis,width,depth,eave,ridge,centre_z,gable_inset)
p.roof=bounded_roof
original_beam=p.beam
def bounded_beam(role,a,b,width=.05,depth=.05,material='cedar_dark'):
    if role=='exposed_rafter':
        bound=p.BOUNDS[CURRENT_AID];sizes=[bound['max'][i]-bound['min'][i] for i in range(3)]
        aa=Vector(a);bb=Vector(b);delta=bb-aa;t0=0.;t1=1.;margin=max(width,depth)*.6
        for axis in [0,2]:
            lo=-sizes[axis]/2+margin-SHIFT[axis];hi=sizes[axis]/2-margin-SHIFT[axis]
            if abs(delta[axis])<1e-8:
                if not lo<=aa[axis]<=hi:return
            else:
                u,v=(lo-aa[axis])/delta[axis],(hi-aa[axis])/delta[axis]
                t0=max(t0,min(u,v));t1=min(t1,max(u,v))
        if t1<=t0:return
        a=tuple(aa+delta*t0);b=tuple(aa+delta*t1)
    return original_beam(role,a,b,width,depth,material)
p.beam=bounded_beam

@contextmanager
def display():
    global DISPLAY
    old=DISPLAY;DISPLAY=True
    try:yield
    finally:DISPLAY=old

@contextmanager
def move(x=0,y=0,z=0,materials=None):
    old=SHIFT[:];oldmap=REMAP.copy()
    for a,n in enumerate((x,y,z)):SHIFT[a]+=n
    REMAP.update(materials or {})
    try:yield
    finally:SHIFT[:]=old;REMAP.clear();REMAP.update(oldmap)

box=p.box;beam=p.beam;cylinder=p.cylinder;frame=p.frame;wall=p.wall
def text(value,centre,size=.13,material='ink'):
    p.text(value,centre,size,material)
    if DISPLAY:p.TEXT[-1].name+='__display'
HEIGHTS={'H01':7.0,'H02':6.80,'H03':4.60,'S06':5.80,'S01':5.25,'S02':6.60,'S03':5.45,'S05':5.60,'S08':6.15,'M01_timber_machiya':6.60,'M03_gable_house':6.60,'M05_residential':6.80}
PALETTES={
 'H01':('b6a587','514331','f0e5ca','607083'),
 'H02':('bbae8d','56504b','dfcea4','565e69'),
 'H03':('a58a63','55432e','eadbb9','586979'),
 'S06':('b09870','493d2d','efe3c8','5c6879'),
 'S01':('789074','485f50','e2dfc5','57645d'),
 'S02':('c3a27c','765036','fff0d3','9e7562'),
 'S03':('a3b498','61755b','e9e7cf','748788'),
 'S05':('ad9680','79574c','f4e6d2','5b7374'),
 'S08':('796750','382f28','ddcfad','515e70'),
 'M01_timber_machiya':('816d52','49372c','eadcc0','5b6370'),
 'M03_gable_house':('b8a58c','5d625e','eee9d9','546578'),
 'M05_residential':('a1a399','5a6269','d9dbc9','677b86')}

def materials(aid):
    p.setup()
    c,d,w,r=PALETTES[aid]
    for name,colour in [('cedar',c),('cedar_dark',d),('plaster',w),('kawara',r),('kawara_dark',r),('wood_end',c)]:
        m,old,texture=p.MATS[name];p.MATS[name]=(m,colour,texture)
    for name,col,tx in [
        ('paint_green','79967d','plaster'),('brick','a4674f','plaster'),('mortar','d9c7a6','plaster'),
        ('indigo','425d79','plaster'),('cloth_noren','395a78','plaster'),('cloth_laundry','d4deea','plaster'),
        ('cloth_towel','90b4c8','plaster'),('warm_window','e6cf96','glass'),
        ('leaf','5c8b52',None),('leaf_light','91b365',None),('flower_pink','e3a3b5',None),
        ('flower_purple','9a9ecc',None),('flower_yellow','edc776',None),
        ('terracotta','ba8868','plaster'),('porcelain_blue','66899c','plaster'),
        ('cabbage','8fa85a','plaster'),('cabbage_light','b5c87c','plaster'),
        ('tomato','cb6954','plaster'),('carrot','d5a258','plaster'),('cucumber','658b58','plaster'),
        ('steel','87999e','plaster'),('sign_cream','e6dfc5','plaster')]:p.mat(name,col,tx)
    p.mat('greenhouse_glass','d7e9e3','glass')
    skin='../architecture_identity_20261002/produce-skins' if (ROOT/'art/references/architecture_identity_20261002/produce-skins.png').exists() else 'plaster'
    for name in ['cabbage','cabbage_light','tomato','cucumber','carrot']:p.mat('produce_'+name,'ffffff',skin)

def ellipsoid(role,c,r,mat,segments=12,rings=7):
    verts=[]
    for j in range(rings+1):
        phi=math.pi*j/rings
        for i in range(segments):
            t=math.tau*i/segments
            verts.append((c[0]+r[0]*math.sin(phi)*math.cos(t),c[1]+r[1]*math.cos(phi),c[2]+r[2]*math.sin(phi)*math.sin(t)))
    faces=[];uv=[]
    for j in range(rings):
        for i in range(segments):
            faces.append((j*segments+i,j*segments+(i+1)%segments,(j+1)*segments+(i+1)%segments,(j+1)*segments+i))
            uv.append([(i/segments,j/rings),((i+1)/segments,j/rings),((i+1)/segments,(j+1)/rings),(i/segments,(j+1)/rings)])
    regions={'cabbage':(0,.5,.5,1),'cabbage_light':(0,.5,.5,1),'tomato':(.5,1,.5,1),'cucumber':(0,.5,0,.5),'carrot':(.5,1,0,.5)}
    if mat in regions:
        u0,u1,v0,v1=regions[mat]
        uv=[[(u0+.012+u*(u1-u0-.024),v0+.012+v*(v1-v0-.024)) for u,v in row] for row in uv]
        mat='produce_'+mat
    geometry(role,verts,faces,mat,uv,True)

def ring(role,c,r,tube,mat,axis='y',segments=16):
    verts=[]
    for i in range(segments):
        a=i*math.tau/segments
        for j in range(6):
            b=j*math.tau/6;rr=r+tube*math.cos(b)
            q=(rr*math.cos(a),tube*math.sin(b),rr*math.sin(a))
            if axis=='z':q=(q[0],q[2],q[1])
            verts.append(tuple(c[k]+q[k] for k in range(3)))
    faces=[(i*6+j,((i+1)%segments)*6+j,((i+1)%segments)*6+(j+1)%6,i*6+(j+1)%6) for i in range(segments) for j in range(6)]
    geometry(role,verts,faces,mat,smooth=True)

def vessel(c,r=.18,h=.34,mat='terracotta',role='ceramic_pot'):
    x,y,z=c;profile=[(0,.70),(h*.08,.75),(h*.72,1.0),(h*.95,.96),(h,1.06),(h*.90,.86),(h*.24,.61)]
    vs=[(x+r*rr*math.cos(i*math.tau/16),y+yy,z+r*rr*math.sin(i*math.tau/16)) for yy,rr in profile for i in range(16)]
    faces=[(j*16+i,j*16+(i+1)%16,(j+1)*16+(i+1)%16,(j+1)*16+i) for j in range(len(profile)-1) for i in range(16)]
    geometry(role,vs,faces,mat,smooth=True)
    cylinder('pot_soil',(x,y+h*.78,z),(0,1,0),r*.83,.018,'cedar_dark',16)

def plant(c,scale=.65,flower=None,pot='terracotta',seed=0):
    x,y,z=c;vessel(c,.16*scale,.28*scale,pot)
    for i in range(9):
        a=i*2.4+seed;stem=.28*scale+(i%4)*.10*scale
        end=(x+math.cos(a)*.21*scale,y+.24*scale+stem,z+math.sin(a)*.20*scale)
        beam('living_plant_stem',(x,y+.22*scale,z),end,.012*scale,.012*scale,'leaf')
        for side in [-1,1]:
            mid=Vector((x,y+.24*scale,z)).lerp(Vector(end),.60);tip=mid+Vector((math.cos(a+side*.7)*.15*scale,.03*scale,math.sin(a+side*.7)*.15*scale))
            cross=Vector((math.sin(a)*.055*scale,.015*scale,-math.cos(a)*.055*scale))
            geometry('plant_leaf',[tuple(mid),tuple((mid+tip)/2+cross),tuple(tip),tuple((mid+tip)/2-cross)],[(0,1,2,3),(3,2,1,0)],'leaf_light' if i%3==0 else 'leaf')
        if flower:
            ellipsoid('flower_heart',end,(.023*scale,.023*scale,.023*scale),'flower_yellow',8,5)
            for j in range(5):
                t=j*math.tau/5
                ellipsoid('flower_petals',(end[0]+.046*scale*math.cos(t),end[1]+.017*scale,end[2]+.046*scale*math.sin(t)),(.035*scale,.012*scale,.035*scale),flower,8,4)

def crate(c,size=(.58,.33,.46),contents=None):
    x,y,z=c;w,h,d=size
    box('crate_floor',(w,.035,d),(x,y+.018,z),'cedar')
    for yy in [y+h*.25,y+h*.72]:
        for zz in [-d/2,d/2]:box('crate_slat',(w,.09,.025),(x,yy,z+zz),'cedar')
        for xx in [-w/2,w/2]:box('crate_side',(.025,.09,d),(x+xx,yy,z),'cedar')
    for xx in [-w/2,w/2]:
        for zz in [-d/2,d/2]:box('crate_corner',(.04,h,.04),(x+xx,y+h/2,z+zz),'cedar_dark')
    if contents:
        for i in range(3):
            for j in range(2):produce((x+(i-1)*w*.25,y+h*.85,z+(j-.5)*d*.43),contents,.11)

def produce(c,kind,r=.12):
    x,y,z=c
    if kind=='cabbage':
        ellipsoid('individual_cabbage',c,(r,r*.8,r),'cabbage',12,7)
        for i in range(5):
            a=i*math.tau/5
            ellipsoid('cabbage_outer_leaf',(x+math.cos(a)*r*.42,y-.03,z+math.sin(a)*r*.42),(r*.60,r*.45,r*.55),'cabbage_light' if i%2 else 'cabbage',10,5)
    elif kind=='tomato':
        ellipsoid('individual_tomato',c,(r,r*.83,r),'tomato',12,7)
        for i in range(5):
            a=i*math.tau/5;geometry('tomato_calyx',[(x,y+r*.84,z),(x+math.cos(a)*r*.6,y+r*.80,z+math.sin(a)*r*.6),(x+math.cos(a+.5)*r*.22,y+r*.9,z+math.sin(a+.5)*r*.22)],[(0,1,2),(2,1,0)],'leaf')
    elif kind=='carrot':
        ellipsoid('individual_carrot',c,(r*.39,r*.4,r*1.65),'carrot',10,5)
        for i in range(3):beam('carrot_leaves',(x,y,z-r*1.4),(x+(i-1)*.035,y+.10,z-r*1.8),.016,.018,'leaf')
    else:ellipsoid('individual_cucumber',c,(r*1.55,r*.44,r*.44),'cucumber',12,6)

def bamboo_blind(face,u,y,width,height,plane):
    for j in range(math.ceil(height/.024)):
        p.face_box('sudare_reed',face,u,y+height-j*.024,plane,width,.012,.016,'cedar',.18)
    for dx in [-width*.32,width*.32]:p.face_box('sudare_cord',face,u+dx,y+height/2,plane,.012,height,.021,'cedar_dark',.20)
    p.face_box('sudare_roll',face,u,y+height+.04,plane,width+.03,.075,.075,'cedar',.18)

def cloth(c,width,height,mat='cloth_noren',strips=3,role='summer_cloth'):
    x,y,z=c
    for i in range(strips):
        x0=x-width/2+i*width/strips+.008;x1=x-width/2+(i+1)*width/strips-.008
        verts=[(x0,y,z),(x1,y,z),(x1,y-height,z+.016),(x0,y-height,z+.016)]
        geometry(role,verts,[(0,1,2,3),(3,2,1,0)],mat,[[(0,0),(1,0),(1,1),(0,1)],[(0,1),(1,1),(1,0),(0,0)]])
    cylinder('cloth_hanger',(x,y+.025,z),(1,0,0),.016,width+.12,'cedar_dark',12)

def ac(face,u,y,plane):
    p.face_box('ac_compressor',face,u,y,plane,.64,.48,.31,'ceramic',.18)
    pos=p.face_point(face,u-.11,y,plane,.35)
    axis=(0,0,1) if face in ['front','back'] else (1,0,0)
    cylinder('ac_fan',pos,axis,.18,.012,'steel',16)
    for j in range(7):p.face_box('ac_grille',face,u-.11,y-.15+j*.05,plane,.33,.013,.018,'metal',.363)
    for dx in [-.23,.23]:p.face_box('ac_bracket',face,u+dx,y-.27,plane,.045,.10,.37,'metal',.18)

def tap(c):
    x,y,z=c;cylinder('tap_pipe',(x,y-.12,z),(0,1,0),.021,.30,'steel',12)
    cylinder('tap_spout',(x,y,z+.06),(0,0,1),.023,.16,'steel',12)
    beam('tap_handle',(x-.06,y+.05,z),(x+.06,y+.05,z),.016,.016,'steel')
    for j in range(3):ring('coiled_hose',(x+.20,y-.20+j*.02,z+.035),.13,.012,'leaf',axis='z')

def stool(c):
    x,y,z=c;box('stool_seat',(.32,.045,.26),(x,y+.36,z),'cedar')
    for xx in [-.12,.12]:
        for zz in [-.09,.09]:box('stool_leg',(.045,.34,.045),(x+xx,y+.17,z+zz),'cedar_dark')

def bench(c,width=1.35):
    x,y,z=c
    for j in range(3):box('bench_seat',(width,.04,.09),(x,y+.42,z+(j-1)*.10),'cedar')
    for xx in [-width*.38,width*.38]:
        for zz in [-.11,.11]:box('bench_leg',(.075,.42,.075),(x+xx,y+.21,z+zz),'cedar_dark')

def enamel(c,width=.45,height=.62,label='牛奶',mat='indigo'):
    x,y,z=c;box('enamel_sign',(width,height,.026),c,mat)
    for yy in [-height/2+.023,height/2-.023]:box('enamel_sign_border',(width-.03,.012,.010),(x,y+yy,z+.018),'paper')
    for xx in [-width/2+.023,width/2-.023]:box('enamel_sign_border',(.012,height-.03,.010),(x+xx,y,z+.018),'paper')
    text(label,(x,y-.06,z+.022),min(.13,width*.28),'paper')

def utility(face,u,plane,height=2.1):
    p.face_box('electric_meter',face,u,1.80,plane,.19,.26,.065,'ceramic',.13)
    p.face_box('meter_glass',face,u,1.83,plane,.11,.095,.010,'deep_reveal',.17)
    for j in range(2):p.face_box('service_conduit',face,u-.07+j*.14,height/2,plane,.018,height,.035,'steel',.09)
    p.face_box('service_junction',face,u,2.23,plane,.30,.18,.08,'ceramic',.12)

def side_service(front,back,body_w,lower=0.22):
    utility('right',(front+back)*.5,body_w/2)
    ac('back',body_w*.27,.55,back)
    p.face_box('service_door','back',-body_w*.22,1.16,back,.84,1.9,.04,'cedar',.07)
    for dy in [.3,.95,1.65]:p.face_box('service_door_rail','back',-body_w*.22,dy,back,.80,.035,.055,'cedar_dark',.10)

def roof_at(x,z,axis,w,d,eave,ridge,mat=None):
    with move(x=x,materials={'kawara':mat,'kawara_dark':mat} if mat else None):p.roof(axis,w,d,eave,ridge,z,.22)

def shedroof(x,z,w,d,low,high,material='steel'):
    bound=p.BOUNDS[CURRENT_AID];plotw=bound['max'][0]-bound['min'][0];plotd=bound['max'][2]-bound['min'][2]
    w=min(w,plotw-2*(abs(x+SHIFT[0])+.07));d=min(d,plotd-2*(abs(z+SHIFT[2])+.08))
    vs=[(x-w/2,low,z+d/2),(x+w/2,low,z+d/2),(x+w/2,high,z-d/2),(x-w/2,high,z-d/2)]
    geometry('standing_seam_roof',vs,[(0,1,2,3),(3,2,1,0)],material)
    for i in range(math.ceil(w/.24)+1):
        xx=x-w/2+min(i*.24,w)
        beam('metal_roof_seam',(xx,low+.025,z+d/2),(xx,high+.025,z-d/2),.018,.025,material)
    beam('shedroof_fascia',(x-w/2,low-.045,z+d/2),(x+w/2,low-.045,z+d/2),.09,.12,'cedar_dark')

def hiproof(w,d,eave,ridge,z=0):
    halfx=w/2;halfd=d/2;r=max(.40,(w-d)*.5)
    corners=[(-halfx,eave,z+halfd),(halfx,eave,z+halfd),(halfx,eave,z-halfd),(-halfx,eave,z-halfd)]
    tops=[(-r,ridge-.09,z),(r,ridge-.09,z)]
    planes=[(corners[0],corners[1],tops[0],tops[1]),(corners[2],corners[3],tops[1],tops[0]),(corners[3],corners[0],tops[0],tops[0]),(corners[1],corners[2],tops[1],tops[1])]
    for a,b,c,dtop in planes:
        a,b,c,dtop=map(Vector,(a,b,c,dtop));cols=max(2,math.ceil((b-a).length/.30));rows=math.ceil((c-a).length/.34)
        base=[tuple(a),tuple(b),tuple(dtop),tuple(c)] if (c-dtop).length>.01 else [tuple(a),tuple(b),tuple(c)]
        face=tuple(range(len(base)));uv=[(v[0]/1.4,v[2]/1.4) for v in base]
        geometry('hipped_roof_sheathing',base,[face,tuple(reversed(face))],'kawara_dark',[uv,list(reversed(uv))])
        normal=(b-a).cross(c-a).normalized()
        if normal.y<0:normal=-normal
        for row in range(rows):
            for col in range(cols):
                vs=[]
                for v,u in [(row/rows,col/cols),(row/rows,(col+1)/cols),((row+1)/rows,(col+1)/cols),((row+1)/rows,col/cols)]:
                    lo=a.lerp(b,u);hi=c.lerp(dtop,u);vs.append(tuple(lo.lerp(hi,v)+normal*(.018+.025*(row%2))))
                geometry('hipped_kawara_tile',vs,[(0,1,2,3),(3,2,1,0)],'kawara')
        beam('hip_eave',tuple(a),tuple(b),.10,.13,'cedar_dark')
    cylinder('hip_roof_ridge',(0,ridge-.09,z),(1,0,0),.09,r*2+.08,'kawara',16)
    for q,t in [(corners[0],tops[0]),(corners[3],tops[0]),(corners[1],tops[1]),(corners[2],tops[1])]:beam('hip_tile_ridge',q,t,.11,.10,'kawara_dark')

def home():
    w,d,_=p.footprint('H01');mainw=3.68;front=.38;back=-3.54;floor=.23;eave=5.56
    # The tall rear house and low veranda wing are real separate masses.
    with move(x=-.55):
        wall('front',mainw,front,floor,eave,[(-1.12,.30,3.86,5.02),(.48,1.40,1.15,2.33)],1.0)
        frame('front',-.41,3.86,1.42,1.16,front);frame('front',.94,1.15,.92,1.18,front)
        bamboo_blind('front',-.39,4.37,1.47,.70,front)
        for face,plane in [('left',-mainw/2),('right',mainw/2)]:
            wall(face,front-back,plane,floor,eave,[(-2.15,-.95,3.84,4.94),(-2.8,-1.85,1.1,2.1)],1.04,(front+back)/2)
            frame(face,-1.55,3.84,1.20,1.10,plane);frame(face,-2.325,1.1,.95,1.0,plane)
        wall('back',mainw,back,floor,eave,[(-1.3,-.2,1.1,2.24),(.3,1.15,3.9,4.75)],1.10)
        frame('back',-.75,1.1,1.1,1.14,back);frame('back',.725,3.9,.85,.85,back)
    roof_at(-.55,-1.57,'z',4.35,4.20,eave,HEIGHTS['H01'])
    wingw=5.42;wingback=.29;wingfront=2.29
    wall('front',wingw,wingfront,.43,2.90,[(-2.12,-.43,.43,2.54),(-.16,.96,.43,2.54),(1.20,2.08,.65,2.30)],.90)
    frame('front',-1.275,.43,1.69,2.11,wingfront,'shoji',3)
    p.door(.40,.43,wingfront,None,True);frame('front',1.64,.65,.88,1.65,wingfront,'shoji',2)
    for face,plane in [('left',-wingw/2),('right',wingw/2)]:
        wall(face,2.0,plane,.23,2.90,[(.83,1.73,1.1,2.1)],.90,1.29);frame(face,1.28,1.1,.90,1.0,plane)
    roof_at(0,1.32,'x',w-.14,2.94,2.96,3.81)
    for i in range(6):box('engawa_board',(wingw,.032,.12),(0,.40,2.34+i*.126),'cedar')
    box('engawa_apron',(wingw,.20,.055),(0,.28,3.03),'cedar_dark')
    for x in [-2.5,-1.2,.3,1.5,2.5]:box('veranda_pier',(.16,.35,.16),(x,.175,2.75),'stone')
    for j in range(2):box('home_entry_step',(1.32,.10,.27),(.40,.06+j*.10,3.65-j*.27),'stone')
    for x in [-2.60,2.60]:box('engawa_hashira',(.12,2.47,.12),(x,1.66,2.81),'cedar_dark')
    # Small service annex breaks the right silhouette without moving the plot.
    box('kitchen_annex',(1.15,2.08,1.65),(2.42,1.26,-1.97),'plaster')
    roof_at(2.42,-1.97,'x',1.48,1.94,2.38,2.94)
    frame('right',-1.97,1.19,.84,.79,3.0)
    p.rainwater(mainw,.38,eave)
    for j in range(18):ring('rain_chain_link',(-2.46,2.88-j*.135,3.02),.054,.009,'steel',axis='z' if j%2 else 'y',segments=12)
    vessel((-2.46,.04,3.02),.33,.47,'porcelain_blue','rain_chain_basin')
    for x,z,sc in [(-1.80,3.64,.85),(1.98,3.43,.70),(2.50,.30,.90),(-2.79,-1.8,.75)]:plant((x,.04,z),sc,'flower_purple')
    crate((1.43,.04,3.57),(.57,.30,.48),'cucumber');stool((-1.64,.42,2.67))
    p.face_box('repaired_board','front',2.16,1.15,wingfront,.24,.58,.025,'cedar_light',.12)
    cloth((-1.15,2.59,2.76),.42,.63,'cloth_towel',1,'veranda_towel')
    for x in [-2.9,2.94]:box('garden_gate_pier',(.22,.84,.23),(x,.46,3.94),'stone')
    for x0,x1 in [(-w/2+.1,-.32),(1.12,w/2-.1)]:box('garden_boundary',(x1-x0,.62,.14),((x0+x1)/2,.34,3.94),'stone')
    p.face_box('family_nameplate','front',1.04,.88,3.95,.18,.20,.025,'cedar_dark',.05);text('空',(1.04,.81,4.02),.13,'paper')
    tap((2.82,.64,-.43));ac('back',.45,.69,-3.55)
    for centre,height in [((-2.59,.025,3.57),.69),((2.58,.025,2.92),.64),((2.73,.025,-.69),.73)]:p.existing_prop('A14_hydrangea_pot',centre,height)
    beam('veranda_broom_handle',(-2.10,.46,2.70),(-2.25,1.62,2.41),.028,.028,'cedar')
    for i in range(12):beam('broom_fibre',(-2.10,.48,2.70),(-2.25+i*.025,.43,2.82),.013,.013,'cedar_light')
    for j in range(4):box('garden_stepping_stone',(.39,.035,.27),(.40,.02,3.27+j*.19),'stone')
    box('garden_gate_hinge',(.085,.62,.085),(-.34,.36,3.90),'cedar_dark')
    for j in range(7):
        x=-.30+j*.047;z=3.89-j*.068
        box('open_garden_gate_slat',(.043,.59,.035),(x,.35,z),'cedar')
    beam('open_gate_top_rail',(-.30,.64,3.89),(-.018,.64,3.482),.035,.05,'cedar_dark')
    pig=ROOT/'art/models/raw/D_summer_pig_hyper3d_20261002/model.glb'
    if pig.exists():import_prop(pig,(-.63,.42,2.64),.21)

def import_prop(path,centre,height):
    before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(path))
    meshes=[o for o in bpy.context.scene.objects if o not in before and o.type=='MESH']
    points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    lo=Vector([min(v[a] for v in points) for a in range(3)]);hi=Vector([max(v[a] for v in points) for a in range(3)])
    base=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));target=Vector(p.bcoord(centre));s=height/(hi.z-lo.z)
    for o in meshes:
        mw=o.matrix_world.copy()
        for v in o.data.vertices:v.co=(mw@v.co-base)*s+target
        o.parent=None;o.matrix_world.identity();p.EXTRAS.append(o)

def grocery():
    w,d,_=p.footprint('S01');bw=w-.72;front=2.32;back=-d/2+.55;floor=.16;eave=4.28
    holes=[(-2.70,3.40,.25,2.05),(-2.48,-.87,3.12,3.91),(.11,1.03,3.18,3.82)]
    with move(materials={'cedar':'paint_green'}):
        wall('front',bw,front,floor,eave,holes,eave)
        for face,plane in [('left',-bw/2),('right',bw/2)]:wall(face,front-back,plane,floor,eave,[(-1.0,.1,1.2,2.21)],eave,(front+back)/2);frame(face,-.45,1.2,1.1,1.01,plane)
        wall('back',bw,back,floor,eave,[(-2.3,-.8,1.1,2.21),(.40,1.5,2.94,3.78)],eave)
    frame('front',.35,.25,6.10,1.80,2.42,'window',6)
    frame('front',-1.675,3.12,1.61,.79,front);frame('front',.57,3.18,.92,.64,front)
    bamboo_blind('front',-1.675,3.28,1.64,.66,front)
    frame('back',-1.55,1.1,1.5,1.11,back);frame('back',.95,2.94,1.1,.84,back)
    roof_at(0,(front+back)/2,'x',w-.13,front-back+.74,eave,HEIGHTS['S01'])
    with move(x=-.12):p.awning(bw-.42,front+.59,2.48,'cloth_mint')
    p.face_box('canvas_patch','front',-.57,2.41,3.535,.33,.15,.018,'cloth_cream',.01)
    p.face_box('grocer_sign','front',-.20,2.96,front,4.78,.40,.07,'sign_cream',.21);text('晴町商店',(-.2,2.84,front+.255),.34,'cedar_dark')
    enamel((-3.58,2.04,front+.19),.40,.65,'牛奶')
    with display():
        for x,width,kind in [(-2.45,1.22,'cabbage'),(-.78,1.64,'cucumber'),(2.55,1.65,'tomato')]:
            market_bin(x,width)
            for i in range(4):
                for j in range(2):produce((x+(i-1.5)*width*.20,1.02+j*.18,3.16-j*.31),kind,.13 if kind=='cabbage' else .11)
            text('当日鲜蔬',(x,.565,3.414),.09,'cedar_dark')
    for j in range(3):crate((-3.4,.04+j*.29,2.96),(.46,.27,.52),'carrot' if j==2 else None)
    with display():
        box('scale_table_top',(.30,.05,.32),(-1.73,1.085,2.79),'cedar')
        for dx in [-.09,.09]:
            for dz in [-.11,.11]:box('scale_table_leg',(.025,1.03,.025),(-1.73+dx,.545,2.79+dz),'cedar_dark')
        box('scale_body',(.27,.14,.28),(-1.73,1.18,2.79),'sign_cream');cylinder('scale_dial',(-1.73,1.45,2.81),(0,0,1),.14,.10,'paper',20)
        beam('scale_pointer',(-1.73,1.45,2.873),(-1.66,1.53,2.873),.01,.01,'ink')
        cylinder('scale_pan',(-1.73,1.61,2.79),(0,1,0),.18,.027,'steel',16)
    p.face_box('shutter_housing','front',.25,2.28,front,6.4,.18,.24,'steel',.10)
    side_service(front,back,bw)
    crate((2.63,.04,back+.37));crate((2.63,.37,back+.37));plant((-3.59,.02,-2.72),.75)
    p.rainwater(bw,front,eave)

def market_bin(x,width):
    for j in range(2):
        y=.13+j*.34;box('market_crate',(width,.30,.74),(x,y+.15,3.0),'crate_green')
        for i in range(7):p.face_box('market_crate_rib','front',x-width/2+(i+.5)*width/7,y+.15,3.375,.014,.24,.02,'cedar_dark')
    a=(x-width/2,.78,3.33);b=(x+width/2,.78,3.33);c=(x+width/2,1.19,2.63);d=(x-width/2,1.19,2.63)
    geometry('plain_produce_tray',[a,b,c,d],[(0,1,2,3),(3,2,1,0)],'cedar')
    for u,v in [(a,b),(b,c),(c,d),(d,a)]:beam('produce_tray_rim',u,v,.04,.055,'cedar_dark')
    p.face_box('produce_label','front',x,.61,3.395,.37,.17,.022,'paper')

def bakery():
    w,d,_=p.footprint('S02');bw=6.60;front=1.30;back=-d/2+.62;floor=.16;eave=5.20
    wall('front',bw,front,floor,eave,[(-2.55,.12,1.02,2.42),(.38,1.42,floor,2.35),(1.65,2.45,.4,2.25),(-1.82,-.20,3.78,5.04)],.61)
    frame('front',-1.215,1.02,2.67,1.4,1.825,'window',3);frame('front',2.05,.4,.8,1.85,1.528)
    p.door(.90,floor,front);frame('front',-1.01,3.78,1.62,1.26,front)
    for face,plane in [('left',-bw/2),('right',bw/2)]:
        wall(face,front-back,plane,floor,eave,[(-1.6,-.10,1.0,2.20),(-1.30,-.40,3.88,4.85)],.55,(front+back)/2)
        frame(face,-.85,1.0,1.5,1.2,plane);frame(face,-.85,3.88,.90,.97,plane)
    wall('back',bw,back,floor,eave,[(-2.1,-.7,1.1,2.3),(1.0,2.3,3.7,4.8)],.70)
    frame('back',-1.4,1.1,1.4,1.2,back);frame('back',1.65,3.7,1.3,1.1,back)
    roof_at(-.28,(front+back)/2,'z',bw+.46,front-back+.70,eave,HEIGHTS['S02'])
    # Projecting bay has actual side cheeks, sill and its own roof.
    for x in [-2.63,.20]:box('bakery_bay_side',(.12,1.67,.53),(x,1.73,1.62),'plaster')
    box('bay_window_sill',(3.0,.12,.61),(-1.215,.86,1.64),'brick')
    with move(x=-1.215):p.awning(3.25,1.93,2.59,'cloth_cream')
    for row in range(4):
        for i in range(14):
            x=-bw/2+(i+.5)*bw/14+(row%2)*.08
            if abs(x-.90)<.60:continue
            p.face_box('bakery_brick_base','front',x,.23+row*.115,front,bw/14-.012,.10,.026,'brick',.12)
    beam('bread_sign_bracket',(-3.20,3.36,front),(-3.20,3.36,front+.86),.045,.045,'metal')
    p.bread_icon((-3.20,3.03,front+.70))
    p.face_box('bakery_name','front',.0,3.02,front,2.38,.35,.08,'sign_cream',.11);text('莲的面包房',(0,2.93,front+.17),.23,'cedar_dark')
    cylinder('oven_flue',(-bw/2-.18,3.77,-1.67),(0,1,0),.13,4.98,'steel',16)
    cylinder('flue_cap',(-bw/2-.18,6.29,-1.67),(0,1,0),.19,.075,'metal',16)
    bench((2.74,.02,front+.74),1.18);plant((3.55,.02,front+.82),.80,'flower_pink')
    for j in range(2):crate((-3.40,.04+j*.31,front+.80),(.54,.29,.50))
    with display():
        box('bakery_menu_board',(.52,.73,.034),(2.57,.75,front+.80),'deep_reveal')
        for x in [2.29,2.85]:beam('bakery_menu_leg',(x,.04,front+.87),(x,.99,front+.77),.035,.035,'cedar_dark')
        text('今日烘焙',(2.57,.96,front+.825),.10,'paper');text('红豆包',(2.57,.72,front+.825),.09,'paper');text('咖喱面包',(2.57,.51,front+.825),.08,'paper')
    cloth((-1.215,1.62,1.866),2.43,.29,'cloth_towel',1,'bakery_half_curtain')
    box('bakery_upper_flower_box',(1.82,.19,.29),(-1.01,3.55,front+.20),'cedar')
    for x in [-1.62,-1.01,-.40]:plant((x,3.65,front+.24),.65,'flower_pink',seed=x)
    p.existing_prop('A14_hydrangea_pot',(3.42,.025,front+.67),.68)
    side_service(front,back,bw);p.rainwater(bw,front,eave)

def florist():
    w,d,_=p.footprint('S03');bw=5.42;front=1.89;back=-d/2+.57;floor=.16;eave=4.35
    with move(x=-.60):
        wall('front',bw,front,floor,eave,[(-2.25,2.30,.30,2.45),(-1.55,-.15,3.02,4.07)],1.10)
        frame('front',.025,.30,4.55,2.15,1.994,'window',5);frame('front',-.85,3.02,1.40,1.05,front)
        wall('left',front-back,-bw/2,floor,eave,[(-1.1,.15,1.1,2.30)],1.10,(front+back)/2);frame('left',-.475,1.1,1.25,1.20,-bw/2)
        wall('back',bw,back,floor,eave,[(-1.8,-.4,1.1,2.3),(.4,1.8,2.95,4.05)],1.10)
        frame('back',-1.1,1.1,1.4,1.2,back);frame('back',1.1,2.95,1.4,1.1,back)
    roof_at(-.60,(front+back)/2,'x',bw+.43,front-back+.66,eave,HEIGHTS['S03'])
    # Actual glass-and-timber side annex, with a separately visible entrance.
    ax=2.89;aw=1.81;z0=-1.70;z1=2.63
    for x in [ax-aw/2,ax+aw/2]:
        for z in [z0,z1]:box('greenhouse_post',(.075,2.68,.075),(x,1.49,z),'cedar_dark')
        for yy in [.30,1.55,2.80]:box('greenhouse_horizontal',(.065,.065,z1-z0),(x,yy,(z0+z1)/2),'cedar_dark')
        for z in [-1.1,-.2,.7,1.6]:box('greenhouse_mullion',(.05,2.46,.05),(x,1.56,z),'cedar_dark')
        p.face_box('greenhouse_side_glass','right' if x>ax else 'left',(z0+z1)/2,1.54,x,z1-z0-.05,2.42,.014,'greenhouse_glass')
    frame('front',ax,.24,aw-.10,2.46,z1,'window',2)
    shedroof(ax,(z0+z1)/2,aw+.10,z1-z0+.12,2.89,3.40,'greenhouse_glass')
    for z in [-1.20,-.30,.60,1.50,2.40]:beam('greenhouse_roof_bar',(ax-aw/2,3.40-(z-z0)/(z1-z0)*.51,z),(ax+aw/2,3.40-(z-z0)/(z1-z0)*.51,z),.045,.045,'cedar_dark')
    p.face_box('flower_sign','front',-.6,2.93,front,2.80,.36,.07,'sign_cream',.16);text('晴町花房',(-.6,2.83,front+.205),.25,'cedar_dark')
    for x in [-3.14,1.71]:box('pergola_post',(.085,2.66,.085),(x,1.44,3.43),'cedar_dark')
    for z in [2.60,3.43]:box('pergola_lintel',(4.99,.10,.095),(-.715,2.74,z),'cedar_dark')
    for x in [-3.1,-2.3,-1.5,-.7,.1,.9,1.7]:box('pergola_rafter',(.055,.07,1.08),(x,2.80,3.02),'cedar_dark')
    with display():
        for x,level in [(-2.91,0),(-2.05,1),(1.05,0),(.22,1)]:
            box('flower_stand',(.75,.045,.47),(x,.14+level*.31,3.27),'cedar_dark')
            for j in range(3):plant((x+(j-1)*.22,.17+level*.31,3.27),.62,'flower_pink' if level else 'flower_purple',seed=j)
    for x in [-2.66,.96]:
        beam('hanging_basket_wire',(x,2.70,3.06),(x,2.17,3.06),.009,.009,'metal');plant((x,1.87,3.06),.72,'flower_pink')
    for y in [.30,.74,1.18,1.62,2.06]:plant((1.73,y,3.44),.43,seed=y)
    tap((3.51,.67,-2.47));vessel((3.28,.04,-2.54),.20,.31,'steel','watering_can_body')
    for c,h in [((-3.04,.025,3.75),.88),((-2.12,.49,3.29),.67),((.92,.025,3.72),.80),((.26,.49,3.31),.57),((3.41,.025,1.76),.76)]:p.existing_prop('A14_hydrangea_pot',c,h)
    for y in [.47,.85,1.23,1.61,1.99,2.37]:
        a=y*4.2;mid=(1.72+math.cos(a)*.04,y,3.43+math.sin(a)*.04);tip=(mid[0]+math.cos(a)*.17,y+.025,mid[2]+math.sin(a)*.18)
        geometry('climbing_vine_leaf',[mid,(mid[0]-.06,y+.03,mid[2]+.10),tip,(mid[0]+.06,y-.03,mid[2]-.10)],[(0,1,2,3),(3,2,1,0)],'leaf_light')
    side_service(front,back,bw);p.rainwater(bw,front,eave)

def zakka():
    w,d,_=p.footprint('S08');bw=w-.92;front=2.66;back=-d/2+.52;floor=.16;eave=4.99
    holes=[(-.95,1.30,.16,2.55),(-2.80,-1.70,.16,2.33)]
    wall('front',bw,front,floor,eave,holes,2.90)
    frame('front',.175,.16,2.25,2.39,2.833,'window',3);p.door(-2.25,floor,front,sliding=True)
    for x0,x1 in [(-bw/2,-2.86),(1.48,bw/2)]:
        for i in range(max(2,int((x1-x0)/.11))):p.face_box('zakka_vertical_koshi','front',x0+.07+i*.11,1.43,front,.030,2.42,.060,'cedar_dark',.17)
    for u in [-2.35,-1.10,.15,1.40,2.65]:
        p.face_box('mushiko_recess','front',u,3.94,front,.61,.57,.04,'deep_reveal',.105)
        for j in range(3):p.face_box('mushiko_slats','front',u+(j-1)*.18,3.94,front,.06,.59,.08,'plaster',.14)
    for face,plane in [('left',-bw/2),('right',bw/2)]:
        wall(face,front-back,plane,floor,eave,[(-1.9,-.7,1.17,2.3),(-.1,.85,3.45,4.48)],2.9,(front+back)/2)
        frame(face,-1.3,1.17,1.2,1.13,plane);frame(face,.375,3.45,.95,1.03,plane)
    wall('back',bw,back,floor,eave,[(-2.3,-.9,1.1,2.23),(.8,2.2,3.3,4.44)],2.7)
    frame('back',-1.6,1.1,1.4,1.13,back);frame('back',1.5,3.3,1.4,1.14,back)
    roof_at(0,(front+back)/2,'x',w-.13,front-back+.64,eave,HEIGHTS['S08'])
    roof_at(0,front+.31,'x',bw+.27,1.42,2.92,3.34)
    cloth((-2.25,2.41,front+.25),1.20,.66,'cloth_noren',3)
    p.face_box('zakka_name','front',.35,2.66,3.70,2.80,.32,.06,'cedar',.03);text('晴町杂货店',(.35,2.57,3.772),.23,'paper')
    enamel((3.02,2.45,front+.39),.50,.96,'器物','cedar_dark')
    with display():
        for x in [1.89,2.59,3.27]:
            for y in [.15,.51,.88]:box('pottery_shelf',(.59,.035,.43),(x,y,3.43),'cedar_dark');vessel((x,y+.02,3.43),.13,.24,'porcelain_blue' if y>.7 else 'terracotta')
    box('umbrella_bin',(.35,.45,.32),(-3.13,.25,3.40),'cedar')
    for i in range(4):
        x=-3.22+i*.06;cylinder('umbrella_shaft',(x,.57,3.41),(0,1,0),.012,.76,'metal',10);ring('umbrella_handle',(x+.035,.95,3.41),.044,.012,'cedar_dark',axis='z',segments=12)
    for x in [-.78,1.72]:
        beam('windchime_string',(x,2.90,3.31),(x,2.45,3.31),.007,.007,'metal')
        ellipsoid('windchime_bell',(x,2.48,3.31),(.07,.09,.07),'porcelain_blue',12,6);cloth((x,2.35,3.31),.047,.22,'cloth_towel',1,'windchime_paper')
    side_service(front,back,bw);crate((2.6,.02,back+.36));p.rainwater(bw,front,eave)

def apartment():
    with move(materials={'cedar_dark':'metal','cedar':'steel'}):p.apartment()
    front=1.48;units=[-3.60,-1.20,1.20,3.60]
    for i,u in enumerate(units):
        utility('front',u+.68,front)
        ac('back',u,.66,-2.34)
        p.face_box('apartment_mailbox','front',u,.66,front,.36,.33,.10,'terracotta' if i%2 else 'steel',.17)
        p.face_box('mailbox_slot','front',u,.76,front,.27,.025,.014,'deep_reveal',.23)
        if i%2==0:plant((u-.70,.18,2.06),.73,seed=i);plant((u-.67,2.96,2.13),.61,seed=i)
        if i==0:cloth((u,3.99,2.45),.61,.58,'cloth_towel',1,'tenant_blue_towel')
        elif i==1:cloth((u,4.23,2.45),.98,.90,'cloth_laundry',1,'tenant_laundry_sheet')
        elif i==2:bamboo_blind('front',u,3.54,.83,1.09,front)
        else:crate((u-.66,3.02,2.00),(.32,.24,.31))
    for x in [-4.7,4.6]:
        box('shoe_rack',(.36,.49,.32),(x,.43,1.92),'cedar_dark')
        for j in range(3):box('shoe_shelf',(.39,.02,.32),(x,.23+j*.17,1.92),'cedar');ellipsoid('shoe_pair',(x-.08,.26+j*.17,1.94),(.055,.033,.095),'indigo',8,4)

def cottage():
    p.engawa()
    bamboo_blind('front',-1.38,1.82,1.62,.67,1.19);stool((1.75,.47,1.70))
    bench((-1.13,.47,1.69),1.15)
    for x in [-2.62,2.65]:plant((x,.06,2.10),.75,'flower_purple')
    tap((3.36,.64,-.86));vessel((3.25,.04,-1.23),.24,.40,'porcelain_blue')
    ac('back',2.54,.68,-1.76);utility('left',-.96,-3.26)
    cloth((1.00,2.47,1.64),.35,.46,'cloth_towel',1,'cottage_towel')
    p.face_box('tea_corner_tray','front',1.7,.86,1.75,.38,.035,.24,'cedar_dark')

def hall():
    p.hall();front=3.37
    p.face_box('hall_notice_frame','front',-3.14,1.79,front,.99,1.15,.12,'cedar_dark',.14)
    p.face_box('hall_notice_paper','front',-3.14,1.79,front,.83,.99,.02,'paper',.22)
    for j,line in enumerate(['夏祭筹备','周六集市','欢迎街坊']):text(line,(-3.14,2.03-j*.27,front+.246),.13,'ink')
    bench((3.26,.04,3.82),1.60)
    for x in [-3.42,3.85]:plant((x,.02,4.24),.88,'flower_yellow')
    shedroof(3.38,-3.46,1.45,2.02,2.30,2.69)
    for j in range(3):crate((3.38,.05+j*.30,-3.53),(.68,.28,.64))
    enamel((3.09,2.41,front+.15),.61,.50,'集会所','indigo')
    utility('right',-2.2,4.49);ac('back',-2.65,.71,-4.63)

def post():
    p.SHOP_PANES['S05']=[[-2.,.3,.35,2.43,3.68]]
    p.shop('S05');front=3.58
    for i in range(25):
        x=-4.04+i*.32
        for row in range(4):
            xx=x+(row%2)*.08;yy=.30+row*.11
            if (xx+.15>-2.0 and xx-.15<.30 and yy+.048>.35) or (xx+.15>1.0 and xx-.15<2.10):continue
            p.face_box('post_brick_course','front',xx,yy,front,.30,.095,.022,'brick',.13)
    enamel((3.45,2.16,front+.19),.48,.65,'〒','red')
    p.face_box('opening_hours','front',2.57,1.56,front,.50,.41,.025,'paper',.11)
    text('营业时间',(2.57,1.59,front+.134),.08,'ink');text('9:00—17:00',(2.57,1.46,front+.134),.068,'ink')
    for j in range(3):crate((3.68,.04+j*.27,-3.80),(.47,.25,.44))
    bench((-3.55,.04,3.97),1.17);plant((3.76,.04,3.96),.74,'flower_pink')
    utility('left',.07,-4.44);ac('back',1.9,.60,-4.31)

def machiya():
    p.narrow_house('M01_timber_machiya');w,d,_=p.footprint('M01_timber_machiya');front=d/2-.25
    cloth((-.36,2.30,front+.23),1.06,.52,'cloth_noren',3)
    for x in [-1.53,1.43]:plant((x,.04,front+.11),.55,'flower_purple')
    for i in range(10):p.face_box('machiya_ground_koshi','front',.55+i*.09,1.31,front,.025,1.56,.045,'cedar_dark',.15)
    enamel((1.55,2.05,front+.11),.27,.57,'晴','cedar_dark')
    utility('back',-.61,-d/2+.25);ac('back',.61,.71,-d/2+.44)

def modern():
    w,d,_=p.footprint('M03_gable_house');bw=w-.76;front=d/2-.81;back=-d/2+.68;floor=.20;eave=5.17
    wall('front',bw,front,floor,eave,[(-1.97,-.87,floor,2.36),(.0,1.81,1.02,2.35),(-1.70,-.28,3.64,4.88),(.47,1.90,3.64,4.88)],.60)
    p.door(-1.42,floor,front);frame('front',.905,1.02,1.81,1.33,front);frame('front',-.99,3.64,1.42,1.24,front);frame('front',1.185,3.64,1.43,1.24,front)
    for face,plane in [('left',-bw/2),('right',bw/2)]:
        wall(face,front-back,plane,floor,eave,[(-1.65,-.10,1.14,2.29),(.75,1.62,3.72,4.70)],.60,(front+back)/2)
        frame(face,-.875,1.14,1.55,1.15,plane);frame(face,1.185,3.72,.87,.98,plane)
    wall('back',bw,back,floor,eave,[(-1.65,-.30,1.2,2.31),(.46,1.74,3.63,4.88)],.60)
    frame('back',-.975,1.2,1.35,1.11,back);frame('back',1.10,3.63,1.28,1.25,back)
    hiproof(w-.14,d-.18,eave,HEIGHTS['M03_gable_house'])
    shedroof(-1.43,front+.34,1.82,1.22,2.62,2.78,'indigo')
    for j in range(2):box('modern_entry_step',(1.35,.10,.29),(-1.42,.05+j*.10,front+.65-j*.25),'stone')
    for x in [.02,1.94]:box('modern_balcony_rail_post',(.05,.78,.05),(x,3.35,front+.46),'metal')
    for yy in [3.06,3.71]:box('modern_balcony_rail',(1.96,.045,.045),(.98,yy,front+.46),'metal')
    box('modern_balcony_floor',(2.13,.10,.71),(.98,2.95,front+.22),'concrete')
    for x in [.34,1.44]:plant((x,3.01,front+.29),.60,'flower_pink')
    tap((2.60,.72,-1.14));side_service(front,back,bw);p.rainwater(bw,front,eave)

def narrow_modern():
    aid='M05_residential';w,d,_=p.footprint(aid);bw=w-.50;front=d/2-.32;back=-d/2+.32;floor=.16;eave=6.53
    wall('front',bw,front,floor,eave,[(-.97,-.13,floor,2.29),(.18,1.02,1.22,2.24),(-.79,.70,3.66,4.80),(-.54,.55,5.25,6.11)],.46)
    frame('front',-.55,floor,.84,2.13,front,'window',1);frame('front',.60,1.22,.84,1.02,front)
    frame('front',-.045,3.66,1.49,1.14,front);frame('front',.005,5.25,1.09,.86,front)
    for face,plane in [('left',-bw/2),('right',bw/2)]:
        wall(face,front-back,plane,floor,eave,[(-.25,.45,3.78,4.78)],.48,(front+back)/2);frame(face,.1,3.78,.7,1.0,plane)
    wall('back',bw,back,floor,eave,[(-.42,.42,1.20,2.24),(-.49,.49,4.0,5.12)],.46)
    frame('back',0,1.2,.84,1.04,back);frame('back',0,4.,.98,1.12,back)
    shedroof(0,0,w-.10,d-.10,6.54,HEIGHTS[aid]-.03,'indigo')
    shedroof(-.56,front+.06,1.25,.42,2.43,2.60,'steel')
    utility('right',-.12,bw/2-.06);ac('back',.45,.64,back+.08)
    plant((1.03,.03,front+.04),.49);cloth((-.03,4.48,front+.13),.42,.62,'cloth_towel',1)
    p.face_box('modern_nameplate','front',-.02,1.57,front,.17,.26,.025,'indigo',.10);text('晴',(-.02,1.49,front+.121),.11,'paper')

BUILDS={'H01':home,'H02':apartment,'H03':cottage,'S06':hall,'S01':grocery,'S02':bakery,'S03':florist,'S05':post,'S08':zakka,'M01_timber_machiya':machiya,'M03_gable_house':modern,'M05_residential':narrow_modern}

def save(aid):
    global CURRENT_AID
    CURRENT_AID=aid
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for group in [p.GROUPS,p.MATS]:group.clear()
    for group in [p.MEMBERS,p.TEXT,p.EXTRAS]:group.clear()
    SHIFT[:]=[0.,0.,0.];REMAP.clear();materials(aid);BUILDS[aid]()
    objects=[]
    for name,data in p.GROUPS.items():
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(data['verts'],[],data['faces']);mesh.update();uv=mesh.uv_layers.new(name='UVMap')
        for poly,coords,smooth in zip(mesh.polygons,data['uvs'],data['smooth']):
            poly.use_smooth=smooth
            for index,co in zip(poly.loop_indices,coords):uv.data[index].uv=co
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces[:]);bm.to_mesh(mesh);bm.free();mesh.validate(clean_customdata=False)
        ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);ob.data.materials.append(p.MATS[name.split('__')[0]][0]);objects.append(ob)
    for ob in p.TEXT:
        bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob;bpy.ops.object.convert(target='MESH');objects.append(bpy.context.object)
    objects.extend(p.EXTRAS)
    # Translate to the original plot centre, never squash architecture to a box.
    bound=p.BOUNDS[aid];cx=(bound['min'][0]+bound['max'][0])/2;cz=(bound['min'][2]+bound['max'][2])/2;ground=bound['min'][1]
    for ob in objects:
        for v in ob.data.vertices:v.co+=Vector((cx,-cz,ground))
    for img in bpy.data.images:
        if img.size[0]>0:img.pack()
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{aid}.blend'))
    path=OUT/f'{aid}.glb';bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_animations=False,export_image_format='JPEG',export_jpeg_quality=95)
    from edit_model_atlas import load
    g,b=load(path)
    for mat in g.get('materials',[]):
        if mat['name'] in p.MATS:mat.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=[*p.linear(p.MATS[mat['name']][1]),1]
        mat.get('pbrMetallicRoughness',{}).pop('metallicRoughnessTexture',None);mat.pop('normalTexture',None)
        mat.setdefault('pbrMetallicRoughness',{}).update(metallicFactor=0,roughnessFactor=1)
        if mat['name']=='greenhouse_glass':
            mat['alphaMode']='BLEND';mat['doubleSided']=True;mat['pbrMetallicRoughness']['baseColorFactor'][3]=.23
    encoded=json.dumps(g,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4);b+=b'\0'*(-len(b)%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(b))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(b),0x004e4942)+b)
    data={'asset':aid,'geometry_source':'Blender individual architecture; built-in imagegen concept and albedo; Hyper3D mosquito pig on H01','members':p.MEMBERS,'translation_godot':[cx,ground,cz],'fit_scale_blender':[1,1,1],'native_bounds':p.BOUNDS[aid],'concepts':['art/references/architecture_identity_20261002/street-concept.png','art/references/architecture_identity_20261002/homes-concept.png']}
    (OUT/f'{aid}_members.json').write_text(json.dumps(data,ensure_ascii=False,indent=2))
    print('IDENTITY_BUILD',aid,len(p.MEMBERS),sum(sum(len(f.vertices)-2 for f in ob.data.polygons) for ob in objects),path.stat().st_size,flush=True)

if __name__=='__main__':
    only=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(BUILDS)
    for aid in only:save(aid)

"""Retain Rodin bodies and add only local production repairs/independent props.

Prepared bodies remain immutable. Original atlases are preserved. Window locations
are recorded separately and verified in the actual Godot street.
"""
import bpy,bmesh,json,math,sys
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from assemble_rodin_houses import cut_box,flat_material,plane,xyz,surface_material,import_part
import project_lived_facade
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'art/models/raw/scene_rodin_20261002'
BACK=ROOT/'evidence/scene_hyper3d_replace_20261002/before/game/assets/models'

def lettering(value,at,size,colour=(.10,.08,.05)):
    curve=bpy.data.curves.new('Lettering','FONT');curve.body=value;curve.align_x='CENTER';curve.size=size;curve.extrude=.0008;curve.resolution_u=3
    curve.font=bpy.data.fonts.load(str(ROOT/'game/assets/fonts/LXGWWenKai-Medium.ttf'))
    ob=bpy.data.objects.new('Lettering_'+value,curve);bpy.context.collection.objects.link(ob);ob.location=xyz(at);ob.rotation_euler.x=math.pi/2;ob.data.materials.append(flat_material('Sign_ink',colour))

def front_depth(bodies,x,y):
    points=[];faces=[]
    for ob in bodies:
        base=len(points);points.extend(ob.matrix_world@v.co for v in ob.data.vertices)
        faces.extend([base+i for i in p.vertices] for p in ob.data.polygons)
    hit,_,_,_=BVHTree.FromPolygons(points,faces).ray_cast(xyz((x,y,20)),Vector((0,1,0)),40)
    if hit is None:raise RuntimeError('Sign has no support surface')
    return -hit.y

def display_parts(aid,shift):
    before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(BACK/f'{aid}.glb'))
    for ob in list(bpy.context.scene.objects):
        if ob in before:continue
        if '__display' not in ob.name:bpy.data.objects.remove(ob,do_unlink=True);continue
        mw=ob.matrix_world.copy()
        for v in ob.data.vertices:v.co=mw@v.co+xyz(shift)
        ob.parent=None;ob.matrix_world.identity()

def cloth_surface(ob,name,low,high,blue=False):
    """Separate only generated cloth faces inside a measured region; retain UVs."""
    mesh=ob.data;uv=mesh.uv_layers.active.data;mat=mesh.materials[0];bs=mat.node_tree.nodes.get('Principled BSDF')
    image=next(l.from_node.image for l in bs.inputs['Base Color'].links if l.from_node.type=='TEX_IMAGE')
    w,h=image.size;pixels=np.empty(w*h*4,dtype=np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape(h,w,4)
    indices=[]
    for poly in mesh.polygons:
        c=poly.center;p=(c.x,c.z,-c.y)
        if not all(low[i]<p[i]<high[i] for i in range(3)):continue
        q=sum((uv[i].uv for i in poly.loop_indices),start=Vector((0,0)))/len(poly.loop_indices)
        r,g,b=pixels[min(h-1,int(q.y%1*h)),min(w-1,int(q.x%1*w)),:3]
        if (b>r*1.15 and b>g*.9) if blue else (min(r,g,b)>.53):indices.append(poly.index)
    if not indices:raise RuntimeError('No cloth measured '+name)
    material=mat.copy();material.name=name;mesh.materials.append(material)
    for index in indices:mesh.polygons[index].material_index=len(mesh.materials)-1
    return len(indices)

def curtain_module(ob,centre,height,texture_id='H02_unit'):
    # A measured aperture avoids ragged material borders from RGB face masks.
    material=bpy.data.materials.get('Tenant_curtain_'+texture_id)
    if not material:
        material=project_lived_facade.material(texture_id).copy();material.name='Tenant_curtain_'+texture_id
    scale=height/2.65
    def point(v):return tuple(centre[i]+v[i]*scale for i in range(3))
    cut_box(ob,point((-1.302,1.116,-.15)),point((.207,2.12,.077)),'Clear_dark_generated_curtain')
    curtain=plane(ob.name+'_curtain',point((-1.302,1.116,.082)),point((.207,2.12,.082)),material)
    project_lived_facade.curtain_uv(curtain,centre,height)


def build(aid):
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(OUT/f'{aid}_body.glb'))
    bodies=[o for o in bpy.context.scene.objects if o.type=='MESH'];repairs=[]
    guides=json.loads((ROOT/'art/models/rodin_local_straightening_20261003.json').read_text())
    if aid in guides:
        guide=guides[aid];samples=np.array(guide['guide_yz']);moved=0
        for ob in bodies:
            for vertex in ob.data.vertices:
                v=vertex.co;x,y,z=v.x,v.z,-v.y
                if abs(x-guide['x'])>guide['half_width'] or not samples[0,0]-.08<y<samples[-1,0]+.08 or abs(z-guide['target_z'])>.08:continue
                end_weight=min(1.,max(0.,(y-samples[0,0]+.08)/.08),max(0.,(samples[-1,0]+.08-y)/.08))
                correction=guide['target_z']-float(np.interp(y,samples[:,0],samples[:,1]))
                vertex.co.y-=correction*end_weight;moved+=1
            ob.data.update()
        repairs.append(f'local jamb depth corrected using measured guide; {moved} vertices; UVs retained')
    if aid=='S01':
        for ob in bodies:project_lived_facade.apply(ob,'S01')
        display_parts(aid,(0,0,.36))
        lettering('晴町商店',(.10,2.91,front_depth(bodies,.1,3.07)+.016),.36)
        repairs.append('independent textured produce displays retained and moved 36 cm forward')
    if aid=='S02':
        # Clear the untextured bread/filled glass, preserve the raised wooden bars.
        for ob in bodies:cut_box(ob,(-1.45,.87,2.68),(.145,2.29,3.315),'Clear_gray_bread_inside_window')
        # Provider bread protruded past the former cavity depth at the sill.
        # Clear the two panes independently, retaining the central wooden stile.
        for ob in bodies:
            for low,high in [(-1.38,-.82),(-.62,.08)]:
                cut_box(ob,(low,.885,2.60),(high,1.35,3.425),'Clear_remaining_bread_at_sill')
        repairs.append('local display cavity cleared for interior mapping')
    if aid=='S05':
        for ob in bodies:cut_box(ob,(-1.83,1.04,3.05),(.39,2.58,3.734),'Clear_filled_post_window')
        for ob in bodies:cut_box(ob,(.20,3.28,3.90),(2.52,4.09,4.31),'Remove_garbled_sign')
        bpy.ops.mesh.primitive_cube_add(size=1,location=xyz((1.34,3.67,4.11)))
        sign=bpy.context.object;sign.name='Post_office_sign';sign.scale=(2.35,.07,.74)
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        sign.data.materials.append(surface_material('Sign_cedar','cedar'))
        bevel=sign.modifiers.new('Small_board_edge','BEVEL');bevel.width=.012;bevel.segments=2
        bpy.ops.object.modifier_apply(modifier=bevel.name)
        lettering('晴町邮局',(1.34,3.55,4.152),.33)
        repairs.append('garbled provider lettering replaced with a separately editable sign')
    if aid=='S06':
        lettering('晴町公民馆',(1.77,3.34,front_depth(bodies,1.77,3.52)+.014),.25,(.85,.81,.68))
    if aid=='H02':
        for ob in bodies:
            cloth_surface(ob,'cloth_towel',(-4.0,3.35,1.0),(-3.23,4.03,2.9),True)
            cloth_surface(ob,'cloth_laundry',(1.72,3.10,1.0),(2.96,4.03,2.9))
        repairs.append('provider laundry assigned independent animated materials')
        for floor_index,(bottom,height,centres) in enumerate([(.19,2.65,[-3.85,-.373,3.104]),(3.03,2.20,[-3.95,-.40,3.15])]):
            half=1.7384*height/2.65
            for unit_index,x in enumerate(centres):
                for ob in bodies:cut_box(ob,(x-half-.015,bottom+.015,-.08),(x+half+.015,bottom+height-.015,1.01),f'Clear_old_tenant_{floor_index}_{unit_index}')
                centre=(x,bottom,.37)
                units=import_part(OUT/'H02_unit_body.glb',f'Rodin_tenant_{floor_index}_{unit_index}',height,centre)
                texture_id=['H02_unit','H02_unit_blue','H02_unit_green'][(unit_index+floor_index)%3]
                for ob in units:
                    project_lived_facade.apply(ob,'H02_unit',centre,height/2.65,texture_id)
                    curtain_module(ob,centre,height,texture_id)
        repairs.append('six independently textured Hyper3D tenant facade modules; uniformly scaled per floor')
    if aid=='S08':
        for ob in bodies:cloth_surface(ob,'cloth_noren',(-2.05,1.19,3.16),(.4,2.20,3.35),True)
        repairs.append('provider indigo noren assigned animated material')
    if aid=='M01_timber_machiya':
        from level_util import squareness
        points=np.array([v.co[:] for ob in bodies for v in ob.data.vertices])
        angle,_=squareness(points)
        candidates=[Matrix.Rotation(math.radians(a),3,'Z') for a in [-angle,angle]]
        rotation=min(candidates,key=lambda m:abs(squareness(points@np.array(m).T)[0]))
        for ob in bodies:
            for v in ob.data.vertices:v.co=rotation@v.co
        new_front=max(-v.co.y for ob in bodies for v in ob.data.vertices)
        for ob in bodies:
            for v in ob.data.vertices:v.co.y-=1.15-new_front
        repairs.append('lower footprint squared with a rigid yaw correction; no axis scaling')
    for ob in [o for o in bpy.context.scene.objects if o.type=='MESH']:
        matrix=ob.matrix_world.copy()
        for v in ob.data.vertices:v.co=matrix@v.co
        ob.parent=None;ob.matrix_world.identity()
        for v in ob.data.vertices:
            if v.co.z<.015:v.co.z=0
    for image in bpy.data.images:
        if image.size[0]>0:image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{aid}.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'{aid}.glb'),export_format='GLB',export_yup=True,export_apply=True,export_image_format='JPEG',export_jpeg_quality=98)
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH'];points=[o.matrix_world@v.co for o in objects for v in o.data.vertices]
    lo=[min(v[a] for v in points) for a in range(3)];hi=[max(v[a] for v in points) for a in range(3)]
    report={'asset':aid,'source':f'{aid}_body.glb','provider':'Hyper3D Rodin image-to-3D; local Blender assembly','repairs':repairs,
     'parts':[o.name for o in objects],'bounds_godot':{'min':[lo[0],lo[2],-hi[1]],'max':[hi[0],hi[2],-lo[1]]}}
    (OUT/f'{aid}_assembly.json').write_text(json.dumps(report,indent=2)+'\n');print('ASSEMBLED',aid,report['bounds_godot'],flush=True)

if __name__=='__main__':
    for aid in sys.argv[sys.argv.index('--')+1:]:build(aid)

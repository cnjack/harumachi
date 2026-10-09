"""Compose provider-created house shells and high-detail door modules in metres.

Blender -b --factory-startup -P ... -- H01 H03
No procedural replacement of the architectural body. Local cuts only clear the
old facade for independent door frames; source GLBs are retained unchanged.
"""
import bpy,bmesh,json,sys,math
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[2]
RAW=ROOT/'art/models/raw/H01_hyper3d_modular_trial_20261002'
OUT=ROOT/'art/models/raw/scene_rodin_20261002';OUT.mkdir(parents=True,exist_ok=True)
PARTS=[];PROFILES=[]

def xyz(p):return Vector((p[0],-p[2],p[1]))

def import_part(path,name,height,at=(0,0,0)):
    before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(path))
    obs=[o for o in bpy.context.scene.objects if o not in before and o.type=='MESH']
    points=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
    lo=Vector([min(v[a] for v in points) for a in range(3)]);hi=Vector([max(v[a] for v in points) for a in range(3)])
    scale=height/(hi.z-lo.z);origin=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));target=xyz(at)
    for ob in obs:
        mw=ob.matrix_world.copy()
        for v in ob.data.vertices:v.co=(mw@v.co-origin)*scale+target
        ob.parent=None;ob.matrix_world.identity();ob.name=name
        bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.remove_doubles(bm,verts=bm.verts[:],dist=1e-7);bm.to_mesh(ob.data);bm.free()
        for material in ob.data.materials:
            if not material or not material.use_nodes:continue
            bs=material.node_tree.nodes.get('Principled BSDF')
            for slot,value in [('Normal',None),('Metallic',0),('Roughness',1),('Specular IOR Level',0)]:
                for link in list(bs.inputs[slot].links):material.node_tree.links.remove(link)
                if value is not None:bs.inputs[slot].default_value=value
        PARTS.append(ob)
    return obs

def cut_box(ob,low,high,name):
    a,b=xyz(low),xyz(high);centre=(a+b)/2;dims=Vector([abs(b[i]-a[i]) for i in range(3)])
    bpy.ops.mesh.primitive_cube_add(size=1,location=centre);cutter=bpy.context.object;cutter.scale=dims
    cutter.data.materials.append(flat_material('Hidden_timber_joint',(.28,.16,.075)))
    bpy.context.view_layer.objects.active=ob
    mod=ob.modifiers.new(name,'BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter;mod.solver='EXACT';mod.material_mode='TRANSFER'
    bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)

def plane(name,low,high,material):
    a,b=low,high;verts=[xyz((a[0],a[1],a[2])),xyz((b[0],a[1],a[2])),xyz((b[0],b[1],b[2])),xyz((a[0],b[1],b[2]))]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],[(0,1,2,3)]);mesh.update();mesh.validate();uv=mesh.uv_layers.new()
    for poly in mesh.polygons:
        for i,li in enumerate(poly.loop_indices):uv.data[li].uv=[(0,0),(1,0),(1,1),(0,1)][i]
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);ob.data.materials.append(material);PARTS.append(ob);return ob

def flat_material(name,colour):
    mat=bpy.data.materials.new(name);mat.use_nodes=True;bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*colour,1);bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0;return mat

def surface_material(name,texture):
    material=bpy.data.materials.get(name)
    if material:return material
    material=flat_material(name,(1,1,1));bs=material.node_tree.nodes.get('Principled BSDF')
    tex=material.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(ROOT/'art/references/architecture_closeup_20261002'/f'{texture}.png'),check_existing=True)
    material.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color']);return material

def refresh_large_surfaces(ob):
    """Keep AI roof/wood joinery; give the plain deck a repeat wood finish."""
    mesh=ob.data;uv=mesh.uv_layers.active.data;images={};original_count=len(mesh.materials)
    for index,material in enumerate(mesh.materials):
        if not material or not material.use_nodes:continue
        bs=material.node_tree.nodes.get('Principled BSDF')
        image=next((link.from_node.image for link in bs.inputs['Base Color'].links if link.from_node.type=='TEX_IMAGE'),None)
        if image is None:continue
        w,h=image.size;array=np.empty(w*h*4,dtype=np.float32);image.pixels.foreach_get(array);images[index]=(array.reshape(h,w,4),w,h)
    slots={}
    for name,texture in [('deck_detail','cedar')]:
        slots[name]=len(mesh.materials);mesh.materials.append(surface_material(name,texture))
    counts={key:0 for key in slots}
    for poly in mesh.polygons:
        if poly.material_index not in images:continue
        q=sum((uv[i].uv for i in poly.loop_indices),start=Vector((0,0)))/len(poly.loop_indices)
        array,w,h=images[poly.material_index];r,g,b=map(float,array[min(h-1,int((q.y%1)*h)),min(w-1,int((q.x%1)*w)),:3]);c=poly.center;n=poly.normal
        kind=None
        # The provider's painted tile joints and timber edges carry important
        # design detail. Preserve them; only the plain deck gets a repeat finish.
        if c.z<.60 and n.z>.65 and r>g*1.12 and g>b*1.03:kind='deck_detail'
        if kind is None:continue
        poly.material_index=slots[kind];counts[kind]+=1
        axis=max(range(3),key=lambda a:abs(n[a]));axes=[a for a in range(3) if a!=axis]
        for li in poly.loop_indices:
            v=mesh.vertices[mesh.loops[li].vertex_index].co
            if kind=='kawara_detail':uv[li].uv=(v.x/1.25,v.y/1.25)
            elif kind=='deck_detail':uv[li].uv=(v.y/.45,v.x/1.40)
            else:uv[li].uv=(v[axes[0]]/1.8,v[axes[1]]/1.8)
    print('SURFACE_DETAIL',ob.name,counts,flush=True)

def prepare_facade(shells,z_offset):
    # Clear the fused painted doors and curtain, keeping roof/deck/outer timber.
    for ob in shells:cut_box(ob,(-2.16,.455,z_offset+.62),(2.16,2.54,z_offset+1.92),'Clear_old_fused_front')
    front=z_offset+1.28;floor=.428
    for i,x in enumerate([-1.205,1.205]):
        doors=import_part(RAW/'door-game/door_game.glb',f'DoorFrame_{i}',2.10,(x,floor,front))
        # The pair joins at its outer frame, with a narrow hidden overlap.
        for ob in doors:
            for v in ob.data.vertices:v.co.x=x+(v.co.x-x)*.985
        PROFILES.append({'feature':'generated door outer stile','x':x-1.15*.985,'y0':floor+.25,'y1':floor+1.85,'z':front+.09})
    paper=flat_material('glass',(.69,.65,.53))
    plane('Shoji_backing',(-2.39,floor+.05,front-.105),(2.39,floor+2.03,front-.105),paper)
    # A lightweight fabric detail moves independently of the structural mesh.
    cloth=flat_material('cloth_towel',(.59,.70,.78))
    panel=plane('Summer_towel',(-2.62,2.20,z_offset+1.40),(-2.28,1.61,z_offset+1.40),cloth)
    for poly in panel.data.polygons:
        for index,loop in enumerate(poly.loop_indices):panel.data.uv_layers.active.data[loop].uv=[(0,0),(1,0),(1,1),(0,1)][index]

def build(aid):
    bpy.ops.wm.read_factory_settings(use_empty=True);PARTS.clear();PROFILES.clear()
    if aid=='H01':
        main=import_part(OUT/'H01_main_body.glb','Rodin_main_house',6.8,(0,0,-2.20))
        # Rodin left a rear ground-floor aperture. Close it behind the preserved
        # timber frame; it is not an accessible entrance into the separate interior.
        rear=plane('Rear_wood_infill',(-.22,.05,-4.23),(1.94,2.77,-4.23),surface_material('Rear_cedar','cedar'))
        for poly in rear.data.polygons:
            for li in poly.loop_indices:
                v=rear.data.vertices[rear.data.loops[li].vertex_index].co
                rear.data.uv_layers.active.data[li].uv=(v.x/1.4,v.z/2.0)
        centre=xyz((.73,.10,-4.18));rotation=Matrix.Rotation(math.pi,3,'Z')
        for ob in import_part(RAW/'door-game/door_game.glb','Rear_service_door',2.10,(.73,.10,-4.18)):
            for v in ob.data.vertices:v.co=centre+rotation@(v.co-centre)
        plane('Rear_shoji_backing',(-.45,.94,-4.20),(1.90,2.16,-4.20),flat_material('Rear_paper',(.69,.65,.53)))
        z=2.06
    else:z=.38
    porch=import_part(RAW/'engawa/model.glb','Rodin_engawa',3.5,(0,0,z))
    prepare_facade(porch,z)
    if aid=='H01':
        import_part(ROOT/'art/models/raw/D_summer_pig_hyper3d_20261002/model.glb','Rodin_summer_pig',.21,(-1.73,.432,z+1.52))
    for ob in PARTS:
        # Feet meet the ground; keep the tiny correction below visible joinery.
        for v in ob.data.vertices:
            if v.co.z<.025:v.co.z=0
        if ob.name.startswith(('Rodin_main_house','Rodin_engawa')):refresh_large_surfaces(ob)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in PARTS:ob.select_set(True)
    bpy.context.view_layer.objects.active=PARTS[0]
    for img in bpy.data.images:
        if img.size[0]>0:img.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{aid}.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'{aid}.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_image_format='JPEG',export_jpeg_quality=95)
    points=[o.matrix_world@v.co for o in PARTS for v in o.data.vertices];lo=Vector([min(v[a] for v in points) for a in range(3)]);hi=Vector([max(v[a] for v in points) for a in range(3)])
    data={'asset':aid,'sources':['H01_main_body' if aid=='H01' else 'engawa','engawa','door-game'],'provider':'Hyper3D Rodin; local Blender aperture cuts and assembly','parts':[o.name for o in PARTS],'door_profiles':PROFILES,'bounds_godot':{'min':[lo.x,lo.z,-hi.y],'max':[hi.x,hi.z,-lo.y]},'ground_m':0,'has_independent_lattice':True}
    (OUT/f'{aid}_assembly.json').write_text(json.dumps(data,indent=2)+'\n');print('ASSEMBLED',aid,json.dumps(data['bounds_godot']),flush=True)

if __name__=='__main__':
    for aid in sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['H01','H03']:build(aid)

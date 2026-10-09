"""Use a fitted, invisible MPFB anatomical weight field on the ORIGINAL exterior.

Exports no proxy mesh. The original positions, UVs, faces and textures are untouched.
"""
import bpy,sys,argparse,math,json,numpy as np
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion,geometry
from mathutils.bvhtree import BVHTree
ap=argparse.ArgumentParser();ap.add_argument('--character',required=True,choices=['sora','mio','ren','haru','tanaka','aoi','kazuko']);ap.add_argument('--source');ap.add_argument('--destination');ap.add_argument('--motion');ap.add_argument('--weights',choices=['proxy','heat'],default='proxy');ap.add_argument('--hand-frame',choices=['legacy','tpose-front'],default='legacy');args=ap.parse_args(sys.argv[sys.argv.index('--')+1:])
tool_dir=Path(__file__).resolve().parents[3]/'art/poc/character_pipeline_20261003/appearance_preserved';root=tool_dir.parent;here=Path(args.destination) if args.destination else tool_dir;downloads=root/'iteration3/downloads'
here.mkdir(parents=True,exist_ok=True);(here/'godot/assets').mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps=30
bpy.ops.import_scene.gltf(filepath=args.source or str(root/'godot/assets'/(args.character+'_original.glb')))
original_rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o.vertex_groups)
original_rest={b.name:(b.head_local.copy(),b.matrix_local.copy()) for b in original_rig.data.bones}
H=max(v.co.z for v in mesh.data.vertices);original_positions=np.array([v.co[:] for v in mesh.data.vertices])
for o in list(bpy.context.scene.objects):
    if o not in [original_rig,mesh]:bpy.data.objects.remove(o,do_unlink=True)
sandbox=here/('proxy_userdata_'+args.character);sandbox.mkdir(exist_ok=True)
old_extension=bpy.utils.extension_path_user
bpy.utils.extension_path_user=lambda package,**kw:str(sandbox) if 'mpfb' in package else old_extension(package,**kw)
sys.path.insert(0,str(downloads/'mpfb2/src'))
import mpfb
mpfb.get_preference=lambda name:{'mpfb_user_data':str(sandbox),'mpfb_second_root':'','mh_auto_user_data':False,'mh_user_data':''}.get(name,None)
mpfb.register()
from mpfb.services.humanservice import HumanService
from mpfb.services.targetservice import TargetService
settings=TargetService.get_default_macro_info_dict();settings.update(gender=1 if args.character in ['sora','ren','tanaka'] else 0,age=.22 if args.character=='aoi' else .85 if args.character in ['haru','tanaka'] else .65 if args.character=='kazuko' else .5,muscle=.3,weight=.60 if args.character=='kazuko' else .42,proportions=.65)
settings['race']={'african':0,'asian':1,'caucasian':0}
proxy=HumanService.create_human(macro_detail_dict=settings);rig=HumanService.add_builtin_rig(proxy,'mixamo',import_weights=True)
for mod in proxy.modifiers:
    if mod.type=='ARMATURE':mod.show_viewport=False
bpy.context.view_layer.update();evaluated=proxy.evaluated_get(bpy.context.evaluated_depsgraph_get());data=evaluated.to_mesh(preserve_all_data_layers=True,depsgraph=bpy.context.evaluated_depsgraph_get())
proxy.data=data.copy();evaluated.to_mesh_clear()
source_transform=rig.matrix_world.inverted()@proxy.matrix_world
old={b.name:b.matrix_local.copy() for b in rig.data.bones};old_length={b.name:b.length for b in rig.data.bones}
heads={'Hips':original_rest['hips'][0],'Spine':original_rest['spine'][0],
       'Spine1':original_rest['spine'][0].lerp(original_rest['chest'][0],.5),'Spine2':original_rest['chest'][0],
       'Neck':original_rest['neck'][0],'Head':original_rest['head'][0]}
tails={'Hips':heads['Spine'],'Spine':heads['Spine1'],'Spine1':heads['Spine2'],'Spine2':heads['Neck'],'Neck':heads['Head'],'Head':heads['Head']+Vector((0,0,.13*H))}
for side,short in [('Left','L'),('Right','R')]:
    for name,original in [('Shoulder','clav'),('Arm','upper'),('ForeArm','fore'),('Hand','hand'),('UpLeg','thigh'),('Leg','shin'),('Foot','foot')]:heads[side+name]=original_rest[original+'.'+short][0]
    for name,next_name in [('Shoulder','Arm'),('Arm','ForeArm'),('ForeArm','Hand'),('UpLeg','Leg'),('Leg','Foot')]:tails[side+name]=heads[side+next_name]
    direction=original_rest['hand.'+short][1].to_3x3().col[1].normalized()
    tails[side+'Hand']=heads[side+'Hand']+direction*.040*H
    heads[side+'ToeBase']=heads[side+'Foot']+Vector((0,-.075*H,-.042*H));tails[side+'Foot']=heads[side+'ToeBase']
    tails[side+'ToeBase']=heads[side+'ToeBase']+Vector((0,-.04*H,0))
sys.path.insert(0,str(tool_dir))
sys.path.insert(0,str(Path(__file__).resolve().parent))
from apose_hand_plane import surface_palm_normal
transforms={}
for name,head in heads.items():
    full='mixamorig:'+name;tail=tails[name];direction=old[full].to_3x3().col[1].normalized()
    aim=direction.rotation_difference((tail-head).normalized());q=aim@old[full].to_quaternion()
    if name.endswith('Hand') and args.hand_frame=='tpose-front':
        # A direction-only fit leaves MPFB fingers spread in XY while the
        # generated T-pose fingers lie in XZ. Match the anatomical palm plane.
        side='Left' if name.startswith('Left') else 'Right';sign=1 if side=='Left' else -1
        thumb=old['mixamorig:'+side+'HandThumb1'].translation-old[full].translation
        palm=sign*direction.cross(thumb).normalized()
        palm=aim@palm;axis=(tail-head).normalized()
        palm=(palm-axis*palm.dot(axis)).normalized()
        target,sample_count=surface_palm_normal(mesh,head,axis,side)
        rig['palm_normal_'+side]=list(target)
        rig['palm_plane_samples_'+side]=sample_count
        angle=math.atan2(axis.dot(palm.cross(target)),palm.dot(target))
        q=Quaternion(axis,angle)@q
        print('HAND_FRAME_ROLL',side,math.degrees(angle),flush=True)
    matrix=q.to_matrix().to_4x4();matrix.translation=head
    scale=Matrix.Diagonal((1,(tail-head).length/old_length[full],1,1))
    transforms[full]=matrix@scale@old[full].inverted()
bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
for bone in rig.data.edit_bones:bone.use_connect=False
for bone in rig.data.edit_bones:
    name=bone.name.split(':')[-1]
    if name in heads:
        bone.head=heads[name];bone.tail=tails[name]
        bone.align_roll(transforms[bone.name].to_3x3()@old[bone.name].to_3x3().col[2])
    else:
        side='Left' if name.startswith('Left') else 'Right';anchor='mixamorig:'+side+'Hand'
        transform=transforms[anchor]
        old_head=old[bone.name].translation
        old_tail=old_head+old[bone.name].to_3x3().col[1].normalized()*old_length[bone.name]
        bone.head=transform@old_head;bone.tail=transform@old_tail
        bone.align_roll(transform.to_3x3()@old[bone.name].to_3x3().col[2]);transforms[bone.name]=transform
bpy.ops.object.mode_set(mode='OBJECT');rig.matrix_world=Matrix.Identity(4)
proxy_weights=[];points=[]
for vertex in proxy.data.vertices:
    influences=[(proxy.vertex_groups[g.group].name,g.weight) for g in vertex.groups if proxy.vertex_groups[g.group].name in transforms]
    total=sum(w for n,w in influences);influences=[(n,w/total) for n,w in influences]
    points.append(sum((transforms[n]@(source_transform@vertex.co)*w for n,w in influences),Vector()))
    proxy_weights.append(dict(influences))
proxy.data.calc_loop_triangles();triangles=[tuple(t.vertices) for t in proxy.data.loop_triangles]
tree=BVHTree.FromPolygons(points,triangles,all_triangles=True)
mesh.vertex_groups.clear();groups={b.name:mesh.vertex_groups.new(name=b.name) for b in rig.data.bones}
# Hair ends can sit below the neck in a bob cut. They still belong to the head.
image=next((n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image),None)
hair=set()
if image and mesh.data.uv_layers.active:
    pixels=np.empty(len(image.pixels),dtype=np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4))
    uv=mesh.data.uv_layers.active.data
    for loop in mesh.data.loops:
        v=mesh.data.vertices[loop.vertex_index]
        if v.co.z<heads['Neck'].z-.07*H or abs(v.co.x)>.20*H:continue
        coordinate=uv[loop.index].uv
        r,g,b=pixels[int(coordinate.y*image.size[1])%image.size[1],int(coordinate.x*image.size[0])%image.size[0],:3]
        if r>g*1.18 and g>b*.9 and (r+g+b)/3<.40:hair.add(v.index)
for vertex in mesh.data.vertices:
    hit=tree.find_nearest(vertex.co);tri=triangles[hit[2]]
    bary=geometry.barycentric_transform(hit[0],points[tri[0]],points[tri[1]],points[tri[2]],Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1)))
    weights={}
    for index,amount in zip(tri,bary):
        for name,weight in proxy_weights[index].items():weights[name]=weights.get(name,0)+weight*max(0,amount)
    if (vertex.co.z>heads['Neck'].z+.012*H and abs(vertex.co.x)<.18*H) or vertex.index in hair or (vertex.co.z>heads['Neck'].z-.035*H and vertex.co.y>heads['Neck'].y+.035*H and abs(vertex.co.x)<.12*H):weights={'mixamorig:Head':1}
    influences=sorted(weights.items(),key=lambda p:p[1],reverse=True)[:4];total=sum(w for n,w in influences)
    for name,weight in influences:
        if weight>0:groups[name].add([vertex.index],weight/total,'REPLACE')
for modifier in list(mesh.modifiers):mesh.modifiers.remove(modifier)
mesh.parent=rig;mesh.matrix_parent_inverse=Matrix.Identity(4);mesh.matrix_basis=Matrix.Identity(4)
modifier=mesh.modifiers.new('Anatomical Skin','ARMATURE');modifier.object=rig
bpy.data.objects.remove(original_rig,do_unlink=True);bpy.data.objects.remove(proxy,do_unlink=True);rig.name='Rig'
if args.weights=='heat':
    mesh.vertex_groups.clear()
    for modifier in list(mesh.modifiers):mesh.modifiers.remove(modifier)
    bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    unweighted=sum(sum(g.weight for g in v.groups)<.00001 for v in mesh.data.vertices)
    if unweighted:raise RuntimeError('Heat binding left %d vertices unweighted; no silent fallback'%unweighted)
    for v in mesh.data.vertices:
        influences=sorted([(g.group,g.weight) for g in v.groups if g.weight>.00001],key=lambda p:p[1],reverse=True)[:4]
        total=sum(w for i,w in influences)
        for group in mesh.vertex_groups:group.remove([v.index])
        for index,weight in influences:mesh.vertex_groups[index].add([v.index],weight/total,'REPLACE')
print('PROXY_TRANSFER_COMPLETE',args.character,len(mesh.data.vertices),'visible proxy meshes = 0',flush=True)
sys.path.insert(0,str(tool_dir))
if args.motion:
    from twist_weights import add_forearm_twists
    add_forearm_twists(rig,mesh)
    from current_motion import animate_and_export
    animate_and_export(rig,mesh,root,here,args.character,H,Path(args.motion))
else:
    from standard_motion import animate_and_export
    animate_and_export(rig,mesh,root,here,args.character,H)
error=float(np.max(np.linalg.norm(np.array([v.co[:] for v in mesh.data.vertices])-original_positions,axis=1)))
out=here/'godot/assets'/(args.character+'_proxy.json')
out.write_text(json.dumps({'original_surface_position_error':error,'original_materials_and_uvs_preserved':True,'invisible_proxy_exported':False,'bones':len(rig.data.bones),'finger_bones':30,'accepted':False},indent=2))
print('PROXY_EXPORTED',args.character,'surface_error',error)

"""Keep binding13 appearance/motions; split sleeve surfaces and add hidden skin.

Exports a modular control/GPU asset and a spring-bone asset from the same faces.
"""
import bpy,sys,json,math,argparse,numpy as np
from pathlib import Path
from mathutils import Vector,Matrix

parser=argparse.ArgumentParser();parser.add_argument('--character',required=True);parser.add_argument('--source',required=True);parser.add_argument('--destination',required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
root=Path(__file__).resolve().parents[3];here=Path(args.destination);old=root/'art/poc/character_pipeline_20261003/tpose_20261004';here.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(old.parent/'appearance_preserved'))
from retime_glb import match_durations
bpy.ops.wm.open_mainfile(filepath=str(Path(args.source)))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
body=next(o for o in bpy.context.scene.objects if o.type=='MESH')
body.name='CharacterBody'
rig.animation_data.action=None
for t in rig.animation_data.nla_tracks:t.mute=True
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
key_actions={}
if body.data.shape_keys:
    key_actions={t.name:t.strips[0].action for t in body.data.shape_keys.animation_data.nla_tracks}
    body.data.shape_keys.animation_data.action=None
    for t in body.data.shape_keys.animation_data.nla_tracks:t.mute=True
    for key in body.data.shape_keys.key_blocks:key.value=0
bpy.context.view_layer.update()
H=max(v.co.z for v in body.data.vertices)
image=next(n.image for n in body.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image)
pixels=np.empty(len(image.pixels),dtype=np.float32);image.pixels.foreach_get(pixels)
pixels=pixels.reshape((image.size[1],image.size[0],4))
def rgb(mesh,face):
    uv=sum((mesh.data.uv_layers.active.data[i].uv for i in face.loop_indices),Vector((0,0)))/len(face.loop_indices)
    return pixels[int(uv.y*image.size[1])%image.size[1],int(uv.x*image.size[0])%image.size[0],:3],uv
def is_cloth(color):
    r,g,b=color
    if args.character=='sora':return g>r*1.025 and g>b*1.015
    if args.character=='mio':return g>r*.88 and b<r*1.015 and r>.25
    if args.character=='ren':return r>g*1.20 and g>b*1.12 and not (r>.6 and g/r>.64 and b/r>.46)
    if args.character=='haru':return b>g*1.03 and b>r*.95
    if args.character=='tanaka':return b>r*1.08 and b>g*1.01
    return min(r,g,b)>.40 and max(r,g,b)-min(r,g,b)<.20
def smooth(lo,hi,value):
    u=max(0,min(1,(value-lo)/(hi-lo)));return u*u*(3-2*u)
def arm_geometry(side):
    arm=rig.data.bones['mixamorig:'+side+'Arm'];fore=rig.data.bones['mixamorig:'+side+'ForeArm']
    return arm.head_local.copy(),fore.head_local.copy(),rig.data.bones['mixamorig:'+side+'Hand'].head_local.copy()
def project(p,side):
    a,e,w=arm_geometry(side);upper=e-a;fore=w-e
    t=(p-a).dot(upper)/upper.length_squared
    if t<=1:return t*upper.length,a+upper*t,(p-a-upper*t).length
    u=(p-e).dot(fore)/fore.length_squared
    return upper.length+u*fore.length,e+fore*u,(p-e-fore*u).length
def at_arc(s,side):
    a,e,w=arm_geometry(side)
    if s<=(e-a).length:return a+(e-a).normalized()*s,(e-a).normalized()
    return e+(w-e).normalized()*(s-(e-a).length),(w-e).normalized()
def sync_keys(mesh):
    keys=mesh.data.shape_keys
    if not keys:return
    keys.animation_data_create();keys.animation_data.action=None
    for t in list(keys.animation_data.nla_tracks):keys.animation_data.nla_tracks.remove(t)
    for clip,action in key_actions.items():
        track=keys.animation_data.nla_tracks.new();track.name=clip;track.strips.new(clip,1,action);track.mute=True
    for key in keys.key_blocks:key.value=0
parts=[];report={'character':args.character,'source':str(Path(args.source)),'sleeves':{},'original_style_and_textures_preserved':True}
for side,sign in [('Left',1),('Right',-1)]:
    shoulder,elbow,wrist=arm_geometry(side)
    groups={body.vertex_groups[n].index for n in ['mixamorig:'+side+'Arm','mixamorig:'+side+'ForeArm','TWIST_'+side]}
    selected=[]
    for face in body.data.polygons:
        p=sum((body.data.vertices[i].co for i in face.vertices),Vector())/len(face.vertices)
        arc,center,radius=project(p,side)
        share=sum(sum(g.weight for g in body.data.vertices[i].groups if g.group in groups) for i in face.vertices)/len(face.vertices)
        color,uv=rgb(body,face)
        if is_cloth(color) and sign*(p.x-shoulder.x)>-.01*H and arc>-.005*H and radius<.105*H and share>.30:selected.append(face.index)
    if len(selected)<100:raise RuntimeError('Sleeve extraction failed '+side)
    bpy.ops.object.select_all(action='DESELECT');body.select_set(True);bpy.context.view_layer.objects.active=body
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='DESELECT');bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.tool_settings.mesh_select_mode=(False,False,True)
    selected_set=set(selected)
    for f in body.data.polygons:f.select=f.index in selected_set
    before=set(bpy.context.scene.objects)
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_mode(type='FACE');bpy.ops.mesh.separate(type='SELECTED');bpy.ops.object.mode_set(mode='OBJECT')
    sleeve=next(o for o in set(bpy.context.scene.objects)-before if o.type=='MESH')
    print('SLEEVE_SPLIT',side,len(selected),'selected',len(sleeve.data.polygons),'split',len(body.data.polygons),'body remaining',flush=True)
    sleeve.name='Sleeve_'+side;sync_keys(sleeve);parts.append(sleeve)
    along=np.array([project(v.co,side)[0] for v in sleeve.data.vertices]);end=float(np.quantile(along,.99))
    color_layer=sleeve.data.color_attributes.new(name='ClothSimMask',type='FLOAT_COLOR',domain='POINT')
    for v in sleeve.data.vertices:
        mask=smooth(end-.035*H,end-.003*H,project(v.co,side)[0])
        color_layer.data[v.index].color=(mask,0,0,1)
    sleeve.data.color_attributes.active_color=color_layer
    # Infer the visible arm's own skin hue and radius; this tube only fills
    # what becomes visible when the sleeve lifts away from the arm.
    samples=[]
    for face in body.data.polygons:
        p=sum((body.data.vertices[i].co for i in face.vertices),Vector())/len(face.vertices)
        arc,center,radius=project(p,side);color,uv=rgb(body,face);r,g,b=color
        if end<arc<end+.10*H and radius<.08*H and r>g*1.07 and r>b*1.15 and (r+g+b)/3>.30:samples.append((radius,uv))
    if not samples:raise RuntimeError('No original skin samples '+side)
    samples.sort(key=lambda p:p[0]);skin_radius=min(.023*H,float(np.median([p[0] for p in samples]))*.45)
    skin_uv=samples[len(samples)//2][1]
    verts=[];faces=[];rings=15;cols=32
    for row in range(rings):
        start_arc=max(.025*H,end-.045*H)
        s=start_arc+(end+.008*H-start_arc)*row/(rings-1);center,axis=at_arc(s,side)
        nearby=[v.co for v in sleeve.data.vertices if abs(project(v.co,side)[0]-min(s,end-.002*H))<.012*H]
        if nearby:
            center.y=(min(p.y for p in nearby)+max(p.y for p in nearby))/2
            center.z=(min(p.z for p in nearby)+max(p.z for p in nearby))/2
        front=Vector((0,-1,0));front=(front-axis*front.dot(axis)).normalized();other=axis.cross(front).normalized()
        for col in range(cols):
            angle=col*math.tau/cols;verts.append(center+(front*math.cos(angle)+other*math.sin(angle))*skin_radius)
    for row in range(rings-1):
        for col in range(cols):
            nex=(col+1)%cols;faces.append((row*cols+col,row*cols+nex,(row+1)*cols+nex,(row+1)*cols+col))
    data=bpy.data.meshes.new('HiddenArm_'+side);data.from_pydata(verts,[],faces);data.materials.append(body.data.materials[0]);data.update()
    skin=bpy.data.objects.new('HiddenArm_'+side,data);bpy.context.collection.objects.link(skin)
    skin.parent=rig;skin.matrix_parent_inverse=Matrix.Identity(4);skin.matrix_basis=Matrix.Identity(4)
    modifier=skin.modifiers.new('Skin','ARMATURE');modifier.object=rig
    uv_data=data.uv_layers.new(name='UVMap')
    for loop in data.loops:uv_data.data[loop.index].uv=skin_uv
    ga=skin.vertex_groups.new(name='mixamorig:'+side+'Arm');gf=skin.vertex_groups.new(name='mixamorig:'+side+'ForeArm')
    upper_len=(elbow-shoulder).length
    for v in data.vertices:
        s,_,_=project(v.co,side);blend=smooth(upper_len*.80,upper_len*1.16,s)
        ga.add([v.index],1-blend,'REPLACE');gf.add([v.index],blend,'REPLACE')
    for face in data.polygons:face.use_smooth=True
    report['sleeves'][side]={'vertices':len(sleeve.data.vertices),'faces':len(sleeve.data.polygons),'length':end,'skin_radius':skin_radius,'helper_parent':'mixamorig:'+side+('Arm' if end<=(elbow-shoulder).length*1.02 else 'ForeArm')}
sync_keys(body)
author=here/'authoring';author.mkdir(exist_ok=True)
assets=here/'godot/assets';assets.mkdir(exist_ok=True,parents=True)
def export(label):
    rig.animation_data.action=None
    for t in rig.animation_data.nla_tracks:t.mute=True
    for o in bpy.context.scene.objects:
        if o.type=='MESH' and o.data.shape_keys:
            o.data.shape_keys.animation_data.action=None
            for t in o.data.shape_keys.animation_data.nla_tracks:t.mute=True
            for key in o.data.shape_keys.key_blocks:key.value=0
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(author/(args.character+'_'+label+'.blend')))
    for t in rig.animation_data.nla_tracks:t.mute=False
    for o in bpy.context.scene.objects:
        if o.type=='MESH' and o.data.shape_keys:
            for t in o.data.shape_keys.animation_data.nla_tracks:t.mute=False
    bpy.ops.object.select_all(action='DESELECT')
    for o in bpy.context.scene.objects:
        if o.type in ['MESH','ARMATURE']:o.select_set(True)
    bpy.context.view_layer.objects.active=rig
    path=assets/(args.character+'_'+label+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_merge_animation='NLA_TRACK',export_bake_animation=True,export_morph=True,export_morph_animation=True,export_extras=True,export_vertex_color='ACTIVE',export_active_vertex_color_when_no_material=True,export_influence_nb=8 if label=='spring' else 4)
    match_durations(root/'art/models/archive/characters_before_apose_20261004'/('CH_'+args.character+'.glb'),path)
export('modular')
for t in rig.animation_data.nla_tracks:t.mute=True
rig.animation_data.action=None
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
helper_info=[]
bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
for side in ['Left','Right']:
    record=report['sleeves'][side];end=record['length'];root_arc=end-.07*H
    parent=rig.data.edit_bones[record['helper_parent']]
    for sector,radial_sign in [('Front',-1),('Back',1)]:
        names=[]
        for index in range(3):
            start=root_arc+(end-root_arc)*index/2
            finish=root_arc+(end-root_arc)*(index+1)/2
            # Rig's object-mode bone geometry is immutable during edit setup.
            # Source segment anchors survive edit mode via original snapshots.
            source_arm=rig.data.edit_bones['mixamorig:'+side+'Arm'];source_fore=rig.data.edit_bones['mixamorig:'+side+'ForeArm'];source_hand=rig.data.edit_bones['mixamorig:'+side+'Hand']
            sh=source_arm.head.copy();el=source_fore.head.copy();wr=source_hand.head.copy();ul=(el-sh).length
            def edit_at(s):return sh+(el-sh).normalized()*s if s<=ul else el+(wr-el).normalized()*(s-ul)
            offset=Vector((0,radial_sign*record['skin_radius']*1.8,0))
            bone=rig.data.edit_bones.new('Cloth_'+side+'_'+sector+str(index))
            bone.head=edit_at(start)+offset;bone.tail=edit_at(finish)+offset
            bone.parent=parent if index==0 else rig.data.edit_bones[names[-1]];bone.use_connect=False;bone.use_deform=True
            names.append(bone.name)
        helper_info.append({'side':side,'sector':sector,'root':names[0],'end':names[-1]})
bpy.ops.object.mode_set(mode='OBJECT')
for sleeve in parts:
    side=sleeve.name.split('_')[-1];record=report['sleeves'][side];parent=sleeve.vertex_groups[record['helper_parent']]
    new={b.name:sleeve.vertex_groups.new(name=b.name) for b in rig.data.bones if b.name.startswith('Cloth_'+side)}
    for v in sleeve.data.vertices:
        mask=sleeve.data.color_attributes['ClothSimMask'].data[v.index].color[0]*.4
        weight=sum(g.weight for g in v.groups if g.group==parent.index)
        if weight*mask<1e-6:continue
        s,center,radius=project(v.co,side);front=smooth(-record['skin_radius'],record['skin_radius'],center.y-v.co.y)
        distal=smooth(record['length']-.04*H,record['length'],s)
        parent.add([v.index],weight*(1-mask),'REPLACE')
        for sector,amount in [('Front',front),('Back',1-front)]:
            for index,part in [(1,1-distal),(2,distal)]:
                new['Cloth_'+side+'_'+sector+str(index)].add([v.index],weight*mask*amount*part,'REPLACE')
    for v in sleeve.data.vertices:
        values=sorted([(g.group,g.weight) for g in v.groups if g.weight>1e-6],key=lambda p:p[1],reverse=True)[:8];total=sum(w for i,w in values)
        for g in sleeve.vertex_groups:g.remove([v.index])
        for i,w in values:sleeve.vertex_groups[i].add([v.index],w/total,'REPLACE')
report['spring_chains']=helper_info
export('spring')
(assets/(args.character+'_runtime.json')).write_text(json.dumps(report,indent=2))
print('CHARACTER_CLOTH_PREPARED',args.character,report,flush=True)

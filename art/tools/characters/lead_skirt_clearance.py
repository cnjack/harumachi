"""Pose-driven radial skirt clearance; no deletion of legs or garment faces."""
import bpy,sys,json,numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
root=Path(__file__).resolve().parents[3];base=root/'art/models/character_leads_apose_20261005';ev=root/'evidence/character_leads_apose_20261005';bpy.ops.wm.open_mainfile(filepath=str(base/'garments/authoring/mio_proxy.blend'))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=max((o for o in bpy.context.scene.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices));tracks={t.name:t for t in rig.animation_data.nla_tracks}
for track in tracks.values():track.mute=True
rig.animation_data.action=None
for bone in rig.pose.bones:bone.matrix_basis=Matrix.Identity(4)
positions=np.array([tuple(v.co) for v in mesh.data.vertices]);H=float(positions[:,2].max());count=len(positions);x,y,z=positions.T;yc=rig.data.bones['mixamorig:Hips'].head_local.y
image=next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image);pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4));colours=np.zeros_like(positions);counts=np.zeros(count)
for loop in mesh.data.loops:
 uv=mesh.data.uv_layers.active.data[loop.index].uv;colours[loop.vertex_index]+=pixels[int(uv.y*image.size[1])%image.size[1],int(uv.x*image.size[0])%image.size[0],:3];counts[loop.vertex_index]+=1
colours/=np.maximum(counts[:,None],1);r,g,b=colours.T
cloth=(b>r*1.08)&(b>g*1.04)&((r+g+b)<1.0)&(z>.29*H)&(z<.60*H)&(abs(x)<.23*H)
skin=(r>g*1.1)&(g>b*1.02)&(r>.30)&(z>.22*H)&(z<.53*H)&(abs(x)<.16*H)
faces=[tuple(f.vertices) for f in mesh.data.polygons if np.mean(cloth[list(f.vertices)])>.8];legs=np.flatnonzero(skin)[::2]
radial=np.column_stack((x,y-yc));radial/=np.maximum(np.linalg.norm(radial,axis=1,keepdims=True),1e-6);strength=np.clip((.57*H-z)/(.24*H),0,1)*cloth
delta=np.zeros_like(positions);delta[:,1]=radial[:,1]*.12*strength
edges=np.array([tuple(e.vertices) for e in mesh.data.edges],np.int32);degree=np.bincount(edges.ravel(),minlength=count);band=(z>.29*H)&(z<.60*H)&(abs(x)<.24*H)
for iteration in range(20):
 sums=np.zeros_like(delta);np.add.at(sums,edges[:,0],delta[edges[:,1]]);np.add.at(sums,edges[:,1],delta[edges[:,0]]);delta[band]=delta[band]*.35+sums[band]/np.maximum(degree[band,None],1)*.65
mesh.shape_key_add(name='Basis');key=mesh.shape_key_add(name='Skirt_Clearance');key.data.foreach_set('co',(positions+delta).astype(np.float32).ravel());keys=mesh.data.shape_keys;keys.animation_data_create();report=[]
directions=[Vector((0,1,0)),Vector((0,-1,0))]
def evaluated():
 bpy.context.view_layer.update();obj=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());data=obj.to_mesh();points=np.array([tuple(v.co) for v in data.vertices]);obj.to_mesh_clear();return points
for clip,track in tracks.items():
 rig.animation_data.action=track.strips[0].action;keys.animation_data.action=None;first,last=rig.animation_data.action.frame_range;values=[]
 for frame in range(int(first),int(last)+1):
  bpy.context.scene.frame_set(frame);key.value=0;pose=evaluated();key.value=1;full=evaluated();key.value=0;tree=BVHTree.FromPolygons([Vector(p) for p in pose],faces,all_triangles=True);amount=0.;before=0
  for index in legs:
   point=Vector(pose[index])
   for direction in directions:
    hit,normal,face,distance=tree.ray_cast(point-direction, direction,2.)
    if hit is None:continue
    needed=(hit-point).dot(direction)+.015
    if needed<=0:continue
    displacement=float(np.mean((pose[list(faces[face])]-full[list(faces[face])])@np.array(direction)))
    if displacement>.015:amount=max(amount,needed/displacement);before+=1
  amount=min(1.6,amount);values.append((frame,amount));report.append({'clip':clip,'frame':frame,'penetration_samples_before':before,'clearance_weight':round(amount,5)})
 action=bpy.data.actions.new('Skirt_'+clip);keys.animation_data.action=action
 for frame,amount in values:key.value=amount;key.keyframe_insert('value',frame=frame)
 for layer in action.layers:
  for strip in layer.strips:
   for bag in strip.channelbags:
    for curve in bag.fcurves:
     for point in curve.keyframe_points:point.interpolation='LINEAR'
 tr=keys.animation_data.nla_tracks.new();tr.name=clip;tr.strips.new(clip,1,action);tr.mute=True
rig.animation_data.action=None;keys.animation_data.action=None;key.value=0
out=base/'clearance';(out/'authoring').mkdir(parents=True,exist_ok=True);(out/'godot/assets').mkdir(parents=True,exist_ok=True);bpy.ops.wm.save_as_mainfile(filepath=str(out/'authoring/mio_proxy.blend'))
for track in tracks.values():track.mute=False
for track in keys.animation_data.nla_tracks:track.mute=False
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);mesh.select_set(True);bpy.context.view_layer.objects.active=rig;target=out/'godot/assets/mio_proxy.glb'
bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_merge_animation='NLA_TRACK',export_bake_animation=True,export_morph=True,export_morph_animation=True,export_extras=True)
sys.path.insert(0,str(root/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import match_durations;match_durations(root/'art/models/archive/characters_before_apose_20261004/CH_mio.glb',target)
(ev/'mio-skirt-clearance-samples.json').write_text(json.dumps({'skin_samples':len(legs),'skirt_faces':len(faces),'samples':report},indent=2));print('SKIRT_CLEARANCE',len(legs),len(report),max(row['clearance_weight'] for row in report))

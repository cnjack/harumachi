"""Bake a small leg clearance corrective into the existing apron and original motions.

The source surface, UVs and trousers remain intact. Rays against the posed apron
measure front-facing trouser penetration; one smooth morph opens enough room.
"""
import bpy,sys,json,numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
root=Path(__file__).resolve().parents[3];base=root/'art/models/character_roster_apose_20261004'
bpy.ops.wm.open_mainfile(filepath=str(base/'final-binding/authoring/kazuko_proxy.blend'))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
tracks={t.name:t for t in rig.animation_data.nla_tracks}
for track in tracks.values():track.mute=True
rig.animation_data.action=None
for bone in rig.pose.bones:bone.matrix_basis=Matrix.Identity(4)
positions=np.array([tuple(v.co) for v in mesh.data.vertices]);H=float(positions[:,2].max());hip_y=rig.data.bones['mixamorig:Hips'].head_local.y;count=len(positions)
image=next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image)
pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4));colours=np.zeros((count,3));counts=np.zeros(count)
for loop in mesh.data.loops:
 uv=mesh.data.uv_layers.active.data[loop.index].uv;colours[loop.vertex_index]+=pixels[int(uv.y*image.size[1])%image.size[1],int(uv.x*image.size[0])%image.size[0],:3];counts[loop.vertex_index]+=1
colours/=np.maximum(counts[:,None],1);x,y,z=positions.T;r,g,b=colours.T
yellow=(abs(x)<.20*H)&(z>.20*H)&(z<.55*H)&(r>g*.95)&(r<g*1.9)&(b<g*.65)&(g>.18)
# The generated atlas also projects yellow onto some hidden trouser faces.
# Keep only the visible front layer; texture colour alone is insufficient.
source_tree=BVHTree.FromPolygons([Vector(p) for p in positions],[tuple(f.vertices) for f in mesh.data.polygons],all_triangles=True)
for index in np.flatnonzero(yellow):
 point=Vector(positions[index]);hit,normal,face,distance=source_tree.ray_cast(Vector((point.x,-2,point.z)),Vector((0,1,0)),4.)
 if hit is None or point.y-hit.y>.012:yellow[index]=False
# Extend across pale hem texels by connected edges, with a gradual border.
import heapq
adj=[[] for _ in range(count)]
for edge in mesh.data.edges:
 a,c=edge.vertices;length=float(np.linalg.norm(positions[a]-positions[c]));adj[a].append((c,length));adj[c].append((a,length))
dist=np.full(count,np.inf);queue=[]
for index in np.flatnonzero(yellow):dist[index]=0;heapq.heappush(queue,(0,int(index)))
while queue:
 value,index=heapq.heappop(queue)
 if value!=dist[index]:continue
 for neighbour,length in adj[index]:
  candidate=value+length
  if candidate<dist[neighbour] and candidate<.015:
   dist[neighbour]=candidate;heapq.heappush(queue,(candidate,neighbour))
cloth=np.maximum(0,1-dist/.015);cloth=cloth*cloth*(3-2*cloth)
for vertex in mesh.data.vertices:
 amount=float(cloth[vertex.index])
 if amount<1e-6:continue
 old={mesh.vertex_groups[a.group].name:a.weight*(1-amount) for a in vertex.groups}
 old['mixamorig:Hips']=old.get('mixamorig:Hips',0)+amount
 row=sorted(old.items(),key=lambda pair:pair[1],reverse=True)[:4];total=sum(value for name,value in row)
 for group in mesh.vertex_groups:group.remove([vertex.index])
 for name,value in row:
  if value>1e-6:mesh.vertex_groups[name].add([vertex.index],value/total,'REPLACE')
height=np.clip((.55*H-z)/(.23*H),0,1);front=np.clip((hip_y-y)/(.12*H),0,1)
delta=np.zeros_like(positions);delta[:,1]=-.13*height*front*cloth
# Blend the welded waist/hem boundaries, including the hidden body underneath.
# This prevents individual short edges getting a different garment assignment.
edges=np.array([tuple(e.vertices) for e in mesh.data.edges],dtype=np.int32);degree=np.bincount(edges.ravel(),minlength=count).astype(np.float32)
band=(z>.29*H)&(z<.57*H)&(abs(x)<.23*H)
groups=list(mesh.vertex_groups);weights=np.zeros((count,len(groups)),dtype=np.float32)
for vertex in mesh.data.vertices:
 for assignment in vertex.groups:weights[vertex.index,assignment.group]=assignment.weight
for iteration in range(28):
 sums=np.zeros_like(weights);np.add.at(sums,edges[:,0],weights[edges[:,1]]);np.add.at(sums,edges[:,1],weights[edges[:,0]])
 weights[band]=weights[band]*.35+sums[band]/np.maximum(degree[band,None],1)*.65
for index in np.flatnonzero(band):
 row=weights[index];ids=np.argsort(row)[-4:];total=float(row[ids].sum())
 for group in groups:group.remove([int(index)])
 for group_id in ids:
  if row[group_id]>1e-6:groups[int(group_id)].add([int(index)],float(row[group_id]/total),'REPLACE')
for iteration in range(12):
 sums=np.zeros_like(delta);np.add.at(sums,edges[:,0],delta[edges[:,1]]);np.add.at(sums,edges[:,1],delta[edges[:,0]])
 delta[band]=delta[band]*.35+sums[band]/np.maximum(degree[band,None],1)*.65
mesh.shape_key_add(name='Basis');key=mesh.shape_key_add(name='Apron_Clearance');key.data.foreach_set('co',(positions+delta).astype(np.float32).ravel());keys=mesh.data.shape_keys;keys.animation_data_create()
faces=[tuple(f.vertices) for f in mesh.data.polygons if np.mean(cloth[list(f.vertices)])>.8 and np.mean(y[list(f.vertices)])<hip_y-.025 and np.mean(z[list(f.vertices)])<.55*H]
pants=np.flatnonzero((np.max(colours,axis=1)<.36)&(z>.24*H)&(z<.55*H)&(abs(x)<.14*H)&(y<hip_y))
# Source points are dense; a deterministic stride still samples every few mm.
pants=pants[::3];report=[]
def evaluated():
 bpy.context.view_layer.update();ev=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());data=ev.to_mesh();result=np.array([tuple(v.co) for v in data.vertices]);ev.to_mesh_clear();return result
for clip,track in tracks.items():
 rig_action=track.strips[0].action;rig.animation_data.action=rig_action;keys.animation_data.action=None;first,last=rig_action.frame_range;values=[]
 for frame in sorted(set(list(range(int(first),int(last)+1,2))+[int(last)])):
  bpy.context.scene.frame_set(frame);key.value=0;pose=evaluated();key.value=1;full=evaluated();key.value=0
  tree=BVHTree.FromPolygons([Vector(p) for p in pose],faces,all_triangles=True);amount=0.;penetrations=0
  for index in pants:
   point=Vector(pose[index]);location,normal,face,distance=tree.ray_cast(point-Vector((0,1,0)),Vector((0,1,0)),2.)
   if location is None:continue
   needed=float(location.y-point.y+.018)
   if needed<=0:continue
   displacement=float(np.mean(pose[list(faces[face]),1]-full[list(faces[face]),1]))
   if displacement>.01:amount=max(amount,needed/displacement);penetrations+=1
  amount=min(1.4,amount);values.append((frame,amount))
  report.append({'clip':clip,'frame':frame,'front_penetration_samples_before':penetrations,'clearance_weight':round(amount,5)})
 action=bpy.data.actions.new('Apron_'+clip);keys.animation_data.action=action
 for frame,amount in values:key.value=amount;key.keyframe_insert('value',frame=frame)
 for layer in action.layers:
  for strip in layer.strips:
   for bag in strip.channelbags:
    for curve in bag.fcurves:
     for point in curve.keyframe_points:point.interpolation='LINEAR'
 shape_track=keys.animation_data.nla_tracks.new();shape_track.name=clip;shape_track.strips.new(clip,1,action);shape_track.mute=True
rig.animation_data.action=None;keys.animation_data.action=None
for track in tracks.values():track.mute=False
for track in keys.animation_data.nla_tracks:track.mute=False
key.value=0
bpy.ops.wm.save_as_mainfile(filepath=str(base/'final-binding/authoring/kazuko_apron.blend'))
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig;export=base/'final-binding/godot/assets/kazuko_proxy.glb'
bpy.ops.export_scene.gltf(filepath=str(export),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_bake_animation=True,export_morph=True,export_morph_animation=True,export_merge_animation='NLA_TRACK',export_extras=True)
sys.path.insert(0,str(root/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import match_durations
match_durations(root/'art/models/archive/characters_before_apose_20261004/CH_kazuko.glb',export)
(root/'evidence/character_roster_apose_20261004/apron-clearance-samples.json').write_text(json.dumps({'morph':'Apron_Clearance','max_morph_displacement_m':float(np.max(abs(delta[:,1]))),'pants_samples':len(pants),'samples':report},indent=2));print('APRON_CLEARANCE_BAKED',len(report),len(pants),max(r['clearance_weight'] for r in report))

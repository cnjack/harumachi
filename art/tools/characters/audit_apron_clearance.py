"""Check trouser penetration against the actual posed apron, before/after corrective."""
import bpy,sys,json,numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
args=sys.argv[sys.argv.index('--')+1:];source=Path(args[0]);output=Path(args[1]);bpy.ops.wm.open_mainfile(filepath=str(source))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH');positions=np.array([tuple(v.co) for v in mesh.data.vertices]);H=float(positions[:,2].max());hip_y=rig.data.bones['mixamorig:Hips'].head_local.y
image=next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image);pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4));colours=np.zeros_like(positions);counts=np.zeros(len(positions))
for loop in mesh.data.loops:
 uv=mesh.data.uv_layers.active.data[loop.index].uv;colours[loop.vertex_index]+=pixels[int(uv.y*image.size[1])%image.size[1],int(uv.x*image.size[0])%image.size[0],:3];counts[loop.vertex_index]+=1
colours/=np.maximum(counts[:,None],1);x,y,z=positions.T;r,g,b=colours.T
yellow=(abs(x)<.20*H)&(z>.20*H)&(z<.55*H)&(r>g*.95)&(r<g*1.9)&(b<g*.65)&(g>.18)
faces=[tuple(f.vertices) for f in mesh.data.polygons if np.mean(yellow[list(f.vertices)])>.8 and np.mean(y[list(f.vertices)])<hip_y-.025]
pants=np.flatnonzero((np.max(colours,axis=1)<.36)&(z>.24*H)&(z<.55*H)&(abs(x)<.14*H)&(y<hip_y))[::3]
tracks={t.name:t for t in rig.animation_data.nla_tracks}
for track in tracks.values():track.mute=True
keys=mesh.data.shape_keys;shape_tracks={t.name:t for t in keys.animation_data.nla_tracks} if keys and keys.animation_data else {}
for track in shape_tracks.values():track.mute=True
samples=[]
for clip in ['idle','walk','run','wave','bow','dance','stretch','tend','cheer']:
 rig.animation_data.action=tracks[clip].strips[0].action;first,last=rig.animation_data.action.frame_range
 if shape_tracks:keys.animation_data.action=shape_tracks[clip].strips[0].action
 for frame in np.linspace(first,last,17):
  bpy.context.scene.frame_set(int(frame),subframe=float(frame%1));bpy.context.view_layer.update();ev=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());data=ev.to_mesh();pose=[v.co.copy() for v in data.vertices];tree=BVHTree.FromPolygons(pose,faces,all_triangles=True);count=0;deepest=0.
  for index in pants:
   point=pose[index];hit,normal,face,distance=tree.ray_cast(point-Vector((0,1,0)),Vector((0,1,0)),2.)
   if hit is not None and hit.y-point.y>.005:count+=1;deepest=max(deepest,float(hit.y-point.y))
  ev.to_mesh_clear();samples.append({'clip':clip,'frame':float(frame),'penetrations_over_5mm':count,'max_penetration_m':deepest,'morph_weight':float(keys.key_blocks['Apron_Clearance'].value) if shape_tracks else 0.})
report={'source':str(source),'passed':not any(s['penetrations_over_5mm'] for s in samples),'pants_samples_per_pose':len(pants),'poses':len(samples),'max_penetrations':max(s['penetrations_over_5mm'] for s in samples),'max_penetration_m':max(s['max_penetration_m'] for s in samples),'samples':samples};output.write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k!='samples'}))
if '--require-pass' in args:assert report['passed']

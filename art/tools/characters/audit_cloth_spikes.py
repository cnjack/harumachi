"""Measure short original edges which become centimetre-scale needles during motions."""
import bpy,sys,json,numpy as np
from pathlib import Path
args=sys.argv[sys.argv.index('--')+1:];source=Path(args[0]);out=Path(args[1])
bpy.ops.wm.open_mainfile(filepath=str(source));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
edges=np.array([tuple(e.vertices) for e in mesh.data.edges]);rest=np.array([tuple(v.co) for v in mesh.data.vertices]);length=np.linalg.norm(rest[edges[:,0]]-rest[edges[:,1]],axis=1);samples=[]
for track in rig.animation_data.nla_tracks:track.mute=True
keys=mesh.data.shape_keys;shape_tracks={t.name:t for t in keys.animation_data.nla_tracks} if keys and keys.animation_data else {}
for track in shape_tracks.values():track.mute=True
for clip in ['idle','walk','run','wave','dance','stretch','bow']:
 track=next(t for t in rig.animation_data.nla_tracks if t.name==clip);rig.animation_data.action=track.strips[0].action;start,end=track.strips[0].action.frame_range
 if shape_tracks:keys.animation_data.action=shape_tracks[clip].strips[0].action
 for frame in np.linspace(start,end,9):
  bpy.context.scene.frame_set(int(frame),subframe=float(frame%1));bpy.context.view_layer.update();ev=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());data=ev.to_mesh();posed=np.array([tuple(v.co) for v in data.vertices]);ev.to_mesh_clear();stretched=np.linalg.norm(posed[edges[:,0]]-posed[edges[:,1]],axis=1)
  needles=(length<.012)&(stretched>.07)&(stretched>length*8)
  worst=[]
  for edge_index in np.flatnonzero(needles)[np.argsort(stretched[needles])[-3:]]:
   worst.append({'length':float(stretched[edge_index]),'vertices':[{'rest':rest[index].tolist(),'weights':{mesh.vertex_groups[g.group].name:g.weight for g in mesh.data.vertices[index].groups}} for index in edges[edge_index]]})
  samples.append({'clip':clip,'frame':float(frame),'needle_edges':int(needles.sum()),'largest_short_edge_m':float(stretched[length<.012].max()),'worst':worst})
report={'source':str(source),'passed':not any(s['needle_edges'] for s in samples),'max_needle_edges':max(s['needle_edges'] for s in samples),'samples':samples};out.write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k!='samples'}))
if '--require-pass' in args:assert report['passed']

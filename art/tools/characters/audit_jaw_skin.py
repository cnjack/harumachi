"""Diagnose lower-face skinning independently of the top-skull regression.

Blender -b --factory-startup --python-exit-code 1 -P art/tools/characters/audit_jaw_skin.py -- CHARACTER SOURCE_GLB OUT_JSON [--limit=0.002]
The ROI may include actual neck skin or pale collars on other characters. Only
set a pass limit for a visually validated face ROI (currently Ren and Aoi).
"""
import bpy,sys,json,numpy as np
from pathlib import Path
from mathutils import Matrix
root=Path.cwd();args=sys.argv[sys.argv.index('--')+1:];who=args[0];source=Path(args[1]);out=Path(args[2])
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=max((o for o in bpy.context.scene.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices))
for obj in bpy.context.scene.objects:
 if obj.animation_data:
  obj.animation_data.action=None
  for t in obj.animation_data.nla_tracks:t.mute=True
 if obj.type=='MESH' and obj.data.shape_keys and obj.data.shape_keys.animation_data:
  obj.data.shape_keys.animation_data.action=None
  for t in obj.data.shape_keys.animation_data.nla_tracks:t.mute=True
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update();mw=np.array(mesh.matrix_world);local=np.array([tuple(v.co) for v in mesh.data.vertices]);rest=(np.c_[local,np.ones(len(local))]@mw.T)[:,:3];H=np.ptp(rest[:,2]);floor=rest[:,2].min()
image=next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image);pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4));col=np.zeros((len(rest),3));counts=np.zeros(len(rest))
for lp in mesh.data.loops:
 uv=mesh.data.uv_layers.active.data[lp.index].uv;col[lp.vertex_index]+=pixels[int(uv.y*image.size[1])%image.size[1],int(uv.x*image.size[0])%image.size[0],:3];counts[lp.vertex_index]+=1
col/=np.maximum(counts[:,None],1);r,g,b=col.T
head=rig.data.bones['mixamorig:Head'];hp=rig.matrix_world@head.head_local
skin=(r>.30)&(g>.16)&(b>.09)&(r>g*1.15)&(g>b*1.08)&(g/np.maximum(r,1e-8)>.55)&(b/np.maximum(r,1e-8)>.32)
lo={'ren':.848,'sora':.84,'mio':.80,'tanaka':.825,'aoi':.79,'kazuko':.825,'haru':.805}[who]
mask=skin&(rest[:,2]>floor+lo*H)&(rest[:,2]<floor+.90*H)&(abs(rest[:,0])<.11*H)&(rest[:,1]<hp.y+.035*H)
rows=[]
for track in rig.animation_data.nla_tracks:
 clip=track.name.split('|')[-1]
 if clip not in ['look','bow','stretch','walk','run','talk','wave']:continue
 rig.animation_data.action=track.strips[0].action;start,end=rig.animation_data.action.frame_range
 for frac in np.linspace(0,1,17):
  frame=start+(end-start)*frac;bpy.context.scene.frame_set(int(frame),subframe=float(frame%1));bpy.context.view_layer.update();ev=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());data=ev.to_mesh();posed=np.array([tuple(v.co) for v in data.vertices]);posed=(np.c_[posed,np.ones(len(posed))]@mw.T)[:,:3];ev.to_mesh_clear()
  transform=rig.matrix_world@rig.pose.bones[head.name].matrix@head.matrix_local.inverted()@rig.matrix_world.inverted();expected=(np.c_[rest,np.ones(len(rest))]@np.array(transform).T)[:,:3];delta=np.linalg.norm(posed[mask]-expected[mask],axis=1)
  wi=int(np.flatnonzero(mask)[int(np.argmax(delta))]);weights={mesh.vertex_groups[v.group].name:v.weight for v in mesh.data.vertices[wi].groups}
  rows.append({'clip':clip,'phase':float(frac),'max_deviation_m':float(delta.max()),'p95_deviation_m':float(np.quantile(delta,.95)),'worst_rest':rest[wi].tolist(),'worst_rgb':col[wi].tolist(),'worst_weights':weights})
report={'character':who,'sampled_vertices':int(mask.sum()),'source':str(source),'jaw_region_min_height_fraction':lo,'worst':max(rows,key=lambda x:x['max_deviation_m']),'samples':rows}
limit=next((float(a.split('=',1)[1]) for a in args[3:] if a.startswith('--limit=')),None)
if limit is not None:
 report.update(limit_m=limit,passed=report['worst']['max_deviation_m']<limit)
out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='samples'}))
if limit is not None:assert report['passed'], 'Lower-face skin deviates from head; see report'

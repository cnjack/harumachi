import bpy,sys,json,numpy as np
from pathlib import Path
from mathutils import Matrix
root=Path(__file__).resolve().parents[3];args=sys.argv[sys.argv.index('--')+1:];out=Path(args[0]);source_folder=Path(args[1]) if len(args)>1 else root/'game/assets/models';rows=[]
for who in ['sora','mio','ren','haru','tanaka','aoi','kazuko']:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=str(source_folder/('CH_'+who+'.glb')))
 rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
 for o in bpy.context.scene.objects:
  if o.animation_data:
   o.animation_data.action=None
   for t in o.animation_data.nla_tracks:t.mute=True
  if o.type=='MESH' and o.data.shape_keys and o.data.shape_keys.animation_data:
   o.data.shape_keys.animation_data.action=None
   for t in o.data.shape_keys.animation_data.nla_tracks:t.mute=True
   for k in o.data.shape_keys.key_blocks:k.value=0
 for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
 bpy.context.view_layer.update()
 mesh=max((o for o in bpy.context.scene.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices))
 mw=np.array(mesh.matrix_world);rest=np.array([tuple(v.co) for v in mesh.data.vertices]);rest=(np.c_[rest,np.ones(len(rest))]@mw.T)[:,:3]
 H=float(np.ptp(rest[:,2]));z0=float(rest[:,2].min())
 head=rig.data.bones['mixamorig:Head'];neck=rig.data.bones['mixamorig:Neck']
 hp=rig.matrix_world@head.head_local;npivot=rig.matrix_world@neck.head_local
 mask=(rest[:,2]>z0+.86*H)&(abs(rest[:,0]-hp.x)<.15*H)
 weights=[]
 for v in mesh.data.vertices:
  if mask[v.index]:weights.append(sum(g.weight for g in v.groups if mesh.vertex_groups[g.group].name=='mixamorig:Head'))
 sample=[]
 keys=mesh.data.shape_keys
 shape_tracks={t.name.split('|')[-1]:t for t in keys.animation_data.nla_tracks} if keys and keys.animation_data else {}
 for track in rig.animation_data.nla_tracks:
  clip=track.name.split('|')[-1]
  if clip not in ['idle','walk','run','look','bow','stretch','tend','talk','dance','wave','cheer']:continue
  action=track.strips[0].action;rig.animation_data.action=action;rig.animation_data.action_slot=track.strips[0].action_slot;a,b=action.frame_range
  if clip in shape_tracks:
   strip=shape_tracks[clip].strips[0];keys.animation_data.action=strip.action;keys.animation_data.action_slot=strip.action_slot
  for frame in np.linspace(a,b,7):
   bpy.context.scene.frame_set(int(frame),subframe=float(frame%1));bpy.context.view_layer.update()
   ev=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());data=ev.to_mesh()
   posed=np.array([tuple(v.co) for v in data.vertices]);posed=(np.c_[posed,np.ones(len(posed))]@mw.T)[:,:3];ev.to_mesh_clear()
   transform=rig.matrix_world@rig.pose.bones[head.name].matrix@head.matrix_local.inverted()@rig.matrix_world.inverted()
   expected=(np.c_[rest,np.ones(len(rest))]@np.array(transform).T)[:,:3]
   residual=np.linalg.norm(posed[mask]-expected[mask],axis=1)
   sample.append({'clip':clip,'frame':float(frame),'skull_deviation_max_m':float(residual.max()),'skull_deviation_p95_m':float(np.quantile(residual,.95))})
 rig.animation_data.action=None
 row={'character':who,'height':H,'head_pivot':list(hp),'neck_pivot':list(npivot),'skull_vertices':int(mask.sum()),'skull_y_quantiles':np.quantile(rest[mask,1],[.05,.5,.95]).tolist(),'skull_z_quantiles':np.quantile(rest[mask,2],[.05,.5,.95]).tolist(),'min_head_weight':min(weights),'head_weight_p05':float(np.quantile(weights,.05)), 'worst':max(sample,key=lambda s:s['skull_deviation_max_m']),'samples':sample,'passed':max(s['skull_deviation_max_m'] for s in sample)<.002}
 rows.append(row);print(json.dumps({k:v for k,v in row.items() if k!='samples'}),flush=True)
 out.write_text(json.dumps({'passed':all(r['passed'] for r in rows),'characters':rows},ensure_ascii=False,indent=2)+'\n')

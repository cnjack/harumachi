import bpy,sys,json,math,numpy as np
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[3];who=sys.argv[sys.argv.index('--')+1];bpy.ops.wm.open_mainfile(filepath=str(root/f'art/models/character_roster_apose_20261004/binding/authoring/{who}_proxy.blend'))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH');H=max(v.co.z for v in mesh.data.vertices)
for t in rig.animation_data.nla_tracks:t.mute=True
rig.animation_data.action=next(t.strips[0].action for t in rig.animation_data.nla_tracks if t.name=='idle');bpy.context.scene.frame_set(1);bpy.context.view_layer.update();ev=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());data=ev.to_mesh();rows=[]
def distance(p,a,e,w):
 result=[]
 for first,last in [(a,e),(e,w)]:
  delta=last-first;u=max(0,min(1,(p-first).dot(delta)/delta.length_squared));result.append((p-first-u*delta).length)
 return min(result)
for side,sign in [('Left',1),('Right',-1)]:
 names=['mixamorig:'+side+s for s in ['Arm','ForeArm','Hand']];a,e,w=[rig.data.bones[n].head_local for n in names];pa,pe,pw=[rig.pose.bones[n].head for n in names]
 for v in mesh.data.vertices:
  if sign*v.co.x<sign*a.x+.02*H or (v.co-w).length<.02*H:continue
  if distance(v.co,a,e,w)>.055*H:continue
  posed=data.vertices[v.index].co;d=distance(posed,pa,pe,pw)
  if d>.055*H:
   rows.append({'side':side,'vertex':v.index,'rest':list(v.co),'posed':list(posed),'distance':d,'weights':{mesh.vertex_groups[g.group].name:g.weight for g in v.groups}})
rows.sort(key=lambda r:r['distance'],reverse=True);print('SKIN_OUTLIERS',json.dumps(rows[:14],indent=2));ev.to_mesh_clear()
(root/f'evidence/character_roster_apose_20261004/{who}-skin-diagnostic.json').write_text(json.dumps(rows[:30],indent=2))

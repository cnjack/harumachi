"""Independent wave regression using the posed mesh's palm polygons in Blender."""
from pathlib import Path
import sys,json
import bpy,numpy as np
from mathutils import Matrix,Vector

args=sys.argv[sys.argv.index('--')+1:];out=Path(args[0]);paths=[Path(a) for a in args[1:] if a!='--require-pass'];rows=[]
for source in paths:
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=max((o for o in bpy.context.scene.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices))
    for obj in bpy.context.scene.objects:
        if obj.animation_data:
            obj.animation_data.action=None
            for t in obj.animation_data.nla_tracks:t.mute=True
        if obj.type=='MESH' and obj.data.shape_keys:
            for k in obj.data.shape_keys.key_blocks:k.value=0
            if obj.data.shape_keys.animation_data:
                obj.data.shape_keys.animation_data.action=None
                for t in obj.data.shape_keys.animation_data.nla_tracks:t.mute=True
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    bone=rig.data.bones['mixamorig:RightHand'];wrist=rig.matrix_world@bone.head_local;axis=(rig.matrix_world.to_3x3()@(bone.tail_local-bone.head_local)).normalized();normal=Vector(rig['palm_normal_Right']).normalized()
    share=np.array([sum(g.weight for g in v.groups if mesh.vertex_groups[g.group].name=='mixamorig:RightHand') for v in mesh.data.vertices])
    selected=[];areas=[]
    for poly in mesh.data.polygons:
        centre=mesh.matrix_world@poly.center;delta=centre-wrist;along=delta.dot(axis);radial=(delta-axis*along).length
        n=(mesh.matrix_world.to_3x3()@poly.normal).normalized()
        if .012<along<.075 and radial<.045 and np.mean(share[list(poly.vertices)])>.45 and n.dot(normal)>.60:
            selected.append(poly.index);areas.append(poly.area)
    assert len(selected)>15,(source,len(selected))
    action=next(t for t in rig.animation_data.nla_tracks if t.name.split('|')[-1]=='wave').strips[0].action;rig.animation_data.action=action;first,last=action.frame_range;samples=[]
    for phase in np.linspace(.22,.75,23):
        frame=first+(last-first)*phase;bpy.context.scene.frame_set(int(frame),subframe=float(frame%1));bpy.context.view_layer.update();evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());data=evaluated.to_mesh()
        normal=(mesh.matrix_world.to_3x3()@Vector(np.average([data.polygons[i].normal[:] for i in selected],axis=0,weights=areas))).normalized();evaluated.to_mesh_clear()
        samples.append({'phase':float(phase),'palm_forward_dot':-normal.y,'normal_blender':list(normal)})
    row={'source':str(source),'palm_polygons':len(selected),'min_forward_dot':min(s['palm_forward_dot'] for s in samples),'samples':samples};row['passed']=row['min_forward_dot']>.75;rows.append(row);print(json.dumps({k:v for k,v in row.items() if k!='samples'}),flush=True)
result={'passed':all(r['passed'] for r in rows),'criterion':'actual palm polygons face Blender -Y / glTF +Z, dot > 0.75','characters':rows};out.write_text(json.dumps(result,indent=2)+'\n')
if '--require-pass' in args:assert result['passed'], 'Actual waved palm surface is not facing the recipient'

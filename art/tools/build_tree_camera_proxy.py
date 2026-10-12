"""Reduce actual Godot-local bark faces for camera-only swept-sphere collision.
Run in Blender, with JSON exported from the imported visual mesh. No visual mesh edits.
"""
import argparse,json,sys,math
from pathlib import Path
import bpy,bmesh,numpy as np
from mathutils.bvhtree import BVHTree
from mathutils import Vector
args=argparse.ArgumentParser();args.add_argument('--input',required=True,type=Path);args.add_argument('--output',required=True,type=Path);args.add_argument('--targets',default='3000,6000,10000,16000')
opt=args.parse_args(sys.argv[sys.argv.index('--')+1:]);source=json.loads(opt.input.read_text());vertices=source['vertices'];faces=np.asarray(source['indices'],dtype=np.int64).reshape(-1,3).tolist();bpy.ops.wm.read_factory_settings(use_empty=True)
original_tree=BVHTree.FromPolygons([Vector(v)for v in vertices],faces,all_triangles=True)
points=np.asarray(vertices,dtype=float);tri=np.asarray(faces,dtype=np.int64);sample_indices=np.linspace(0,len(points)-1,min(16000,len(points)),dtype=int);centres=points[tri[np.linspace(0,len(tri)-1,min(16000,len(tri)),dtype=int)]].mean(axis=1);samples=np.concatenate([points[sample_indices],centres])
trials=[];chosen=None
for target in [int(v)for v in opt.targets.split(',')]:
 mesh=bpy.data.meshes.new('Bark camera measured source');mesh.from_pydata(vertices,[],faces);mesh.update();obj=bpy.data.objects.new('CameraBarkProxy',mesh);bpy.context.collection.objects.link(obj);bpy.context.view_layer.objects.active=obj;obj.select_set(True)
 bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001);bm.to_mesh(mesh);bm.free();mesh.calc_loop_triangles();start_count=len(mesh.loop_triangles)
 dec=obj.modifiers.new('Camera sweep geometry budget','DECIMATE');dec.ratio=min(1.,target/start_count);dec.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=dec.name);mesh.calc_loop_triangles();v=[list(x.co)for x in mesh.vertices];f=[list(x.vertices)for x in mesh.loop_triangles];proxy_tree=BVHTree.FromPolygons([Vector(x)for x in v],f,all_triangles=True)
 distances=np.asarray([proxy_tree.find_nearest(Vector(x))[3]for x in samples]);pv=np.asarray(v);pt=np.asarray(f,dtype=int);proxy_samples=np.concatenate([pv,pv[pt].mean(axis=1)]);reverse=np.asarray([original_tree.find_nearest(Vector(x))[3]for x in proxy_samples]);metrics={'target':target,'triangles':len(f),'visual_samples':len(samples),'visual_to_proxy_p99_m':float(np.quantile(distances,.99)),'visual_to_proxy_max_m':float(distances.max()),'proxy_to_visual_max_m':float(reverse.max())};trials.append(metrics);print('CAMERA_PROXY_TRIAL',json.dumps(metrics),flush=True)
 if metrics['visual_to_proxy_p99_m']<=.035 and metrics['visual_to_proxy_max_m']<=.12 and metrics['proxy_to_visual_max_m']<=.12:
  chosen={'vertices':v,'indices':[i for face in f for i in face],'source_sha256':source['source_sha256'],'coordinate_space':source['coordinate_space'],'metrics':metrics,'trials':trials};break
 bpy.data.objects.remove(obj,do_unlink=True);bpy.data.meshes.remove(mesh)
if chosen is None:raise RuntimeError('No proxy met measured two-way surface limits: '+json.dumps(trials))
opt.output.parent.mkdir(parents=True,exist_ok=True);opt.output.write_text(json.dumps(chosen,separators=(',',':'))+'\n');print('CAMERA_PROXY_READY',json.dumps(chosen['metrics']),flush=True)

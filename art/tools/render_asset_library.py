"""Deterministic thumbnails from actual meshes; four independent Blender shards are supported."""
import bpy,json,sys,math
from pathlib import Path
from mathutils import Vector
from mathutils import Matrix
ROOT=Path(__file__).resolve().parents[2]
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
shard=int(args[0]) if args else 0;shards=int(args[1]) if len(args)>1 else 1
selected_ids=set(next((a.removeprefix('--only=') for a in args if a.startswith('--only=')), '').split(','))-{''}
report_arg=next((a.removeprefix('--report=') for a in args if a.startswith('--report=')), '')
catalog=json.loads((ROOT/'art/library/catalog.json').read_text())
out=ROOT/'art/library/previews';out.mkdir(exist_ok=True)
fail=[];count=0
for index,asset in enumerate(catalog['assets']):
 if selected_ids and asset['id'] not in selected_ids:continue
 if '--characters' in args and asset['category']!='人物':continue
 if index%shards!=shard:continue
 target=ROOT/asset['preview'];source=ROOT/asset['path']
 if target.exists() and target.stat().st_mtime>=source.stat().st_mtime:continue
 try:
  bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source))
  for actor in bpy.context.scene.objects:
   if actor.type=='ARMATURE':
    actor.animation_data_clear()
    for bone in actor.pose.bones:bone.matrix_basis=Matrix.Identity(4)
  bpy.context.view_layer.update()
  meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
  lo=Vector([min(p[a] for p in points) for a in range(3)]);hi=Vector([max(p[a] for p in points) for a in range(3)]);centre=(lo+hi)*.5;size=hi-lo
  world=bpy.data.worlds.new('LibraryBackdrop');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.77,.81,.73,1);world.node_tree.nodes['Background'].inputs[1].default_value=.75;bpy.context.scene.world=world
  for material in bpy.data.materials:
   if material.use_nodes:
    bs=material.node_tree.nodes.get('Principled BSDF')
    if bs:bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0
  sun=bpy.data.objects.new('LibrarySun',bpy.data.lights.new('LibrarySun','SUN'));bpy.context.collection.objects.link(sun);sun.data.energy=2.2;sun.rotation_euler=(.7,-.2,-.5)
  fill=bpy.data.objects.new('LibraryFill',bpy.data.lights.new('LibraryFill','AREA'));bpy.context.collection.objects.link(fill);fill.location=centre+Vector((-2,-3,3))*max(size);fill.rotation_euler=(centre-fill.location).to_track_quat('-Z','Y').to_euler();fill.data.energy=60*max(size)**2;fill.data.shape='DISK';fill.data.size=max(size)*3
  camera=bpy.data.objects.new('LibraryCamera',bpy.data.cameras.new('LibraryCamera'));bpy.context.collection.objects.link(camera);camera.data.type='ORTHO';camera.data.ortho_scale=max(size)*1.45;camera.location=centre+Vector((1,-1,.65)).normalized()*size.length*2;camera.rotation_euler=(centre-camera.location).to_track_quat('-Z','Y').to_euler()
  scene=bpy.context.scene;scene.camera=camera;scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=320;scene.render.resolution_y=270;scene.render.resolution_percentage=100;scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.render.filepath=str(target);bpy.ops.render.render(write_still=True)
  count+=1
 except Exception as error:fail.append({'id':asset['id'],'error':str(error)});print('THUMB_FAILED',asset['id'],str(error),flush=True)
report={'shard':shard,'rendered':count,'failed':fail}
report_path=Path(report_arg) if report_arg else ROOT/'evidence/asset_library_20261004'/('thumbs-'+str(shard)+'.json')
report_path.parent.mkdir(parents=True,exist_ok=True);report_path.write_text(json.dumps(report,indent=2)+'\n');print('THUMB_REPORT',json.dumps(report),flush=True)

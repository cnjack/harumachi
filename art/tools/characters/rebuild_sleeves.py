"""Regular local sleeve tubes, original identity/body/texture, nearest original-cloth UV transfer."""
import bpy,bmesh,sys,json,math,numpy as np
from pathlib import Path
from mathutils import Vector,Matrix,geometry
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[3];who=sys.argv[sys.argv.index('--')+1];base=ROOT/'art/models/character_roster_apose_20261004/binding';path=base/'authoring'/f'{who}_proxy.blend'
bpy.ops.wm.open_mainfile(filepath=str(path));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');body=next(o for o in bpy.context.scene.objects if o.type=='MESH')
rig.animation_data.action=None
for t in rig.animation_data.nla_tracks:t.mute=True
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update();H=max(v.co.z for v in body.data.vertices)
source=body.data.copy();source.calc_loop_triangles();image=next(n.image for n in body.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image);pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4))
old=ROOT/f'evidence/character_roster_apose_20261004/weight-repair-before/CH_{who}.glb';sys.path.insert(0,str(ROOT/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import load,match_durations
d,_=load(old);profile=next(n for n in d['nodes'] if n.get('name')=='Rig')['extras']['character_clothing'];new_parts=[];remove=set();report=[]
def smooth(a,b,t):
 u=max(0,min(1,(t-a)/(b-a)));return u*u*(3-2*u)
def colour(face):
 uv=sum((source.uv_layers.active.data[i].uv for i in face.loop_indices),Vector((0,0)))/len(face.loop_indices);return pixels[int(uv.y*image.size[1])%image.size[1],int(uv.x*image.size[0])%image.size[0],:3]
def cloth(c):
 r,g,b=c
 if who=='ren':return r>g*1.18 and g>b*1.1 and not(r>.6 and g/r>.64 and b/r>.46)
 if who=='haru':return b>g*1.03 and b>r*.95
 if who=='tanaka':return b>r*1.08 and b>g*1.01
 return min(c)>.4 and max(c)-min(c)<.12
for side,sign in [('Left',1),('Right',-1)]:
 a=rig.data.bones['mixamorig:'+side+'Arm'].head_local;e=rig.data.bones['mixamorig:'+side+'ForeArm'].head_local;w=rig.data.bones['mixamorig:'+side+'Hand'].head_local;ul=(e-a).length;fl=(w-e).length
 def project(p):
  upper=e-a;t=(p-a).dot(upper)/upper.length_squared
  if t<=1:return t*ul,a+upper*t,(p-a-upper*t).length
  fore=w-e;u=(p-e).dot(fore)/fore.length_squared;return ul+u*fl,e+fore*u,(p-e-fore*u).length
 def arc(s):
  return (a+(e-a).normalized()*s,(e-a).normalized()) if s<=ul else (e+(w-e).normalized()*(s-ul),(w-e).normalized())
 end=float(profile['sleeves'][side]['length']);end=min(end,ul+fl-.025*H)
 selected=[]
 for face in source.polygons:
  centre=sum((source.vertices[i].co for i in face.vertices),Vector())/len(face.vertices);s,c,radius=project(centre)
  if sign*centre.x>sign*a.x-.03*H and -.03*H<s<end+.025*H and radius<.15*H and cloth(colour(face)):selected.append(face.index)
 selected_set=set(selected);remove.update(selected_set)
 tris=[tri for tri in source.loop_triangles if tri.polygon_index in selected_set];tree=BVHTree.FromPolygons([v.co for v in source.vertices],[tuple(t.vertices) for t in tris],all_triangles=True)
 ring_samples=[]
 for v in source.vertices:
  if any(p.index in selected_set and v.index in p.vertices for p in []):pass
 points=[source.vertices[i].co for fi in selected for i in source.polygons[fi].vertices]
 verts=[];faces=[];rows=22;cols=32;start=-.018*H
 for row in range(rows):
  s=start+(end-start)*row/(rows-1);centre,axis=arc(s);front=Vector((0,-1,0));front=(front-axis*front.dot(axis)).normalized();other=axis.cross(front).normalized()
  nearby=[p for p in points if abs(project(p)[0]-s)<.028*H]
  radii=[project(p)[2] for p in nearby]
  radius=float(np.median(radii)) if radii else .035*H
  radius=min(max(radius,.022*H),(.066 if who=='tanaka' else .048)*H)
  if row==0:radius*=1.04
  for col in range(cols):
   angle=col*math.tau/cols;verts.append(centre+front*math.cos(angle)*radius+other*math.sin(angle)*radius)
 for row in range(rows-1):
  for col in range(cols):nex=(col+1)%cols;faces.append((row*cols+col,row*cols+nex,(row+1)*cols+nex,(row+1)*cols+col))
 data=bpy.data.meshes.new('CleanSleeve_'+side);data.from_pydata(verts,[],faces);data.materials.append(body.data.materials[0]);data.update();obj=bpy.data.objects.new('CleanSleeve_'+side,data);bpy.context.collection.objects.link(obj);obj.parent=rig;mod=obj.modifiers.new('Skin','ARMATURE');mod.object=rig
 uv_layer=data.uv_layers.new(name='UVMap')
 for loop in data.loops:
  hit=tree.find_nearest(data.vertices[loop.vertex_index].co);tri=tris[hit[2]];indices=tri.vertices;bary=geometry.barycentric_transform(hit[0],*[source.vertices[i].co for i in indices],Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1)));uv_layer.data[loop.index].uv=sum((source.uv_layers.active.data[li].uv*amount for li,amount in zip(tri.loops,bary)),Vector((0,0)))
 groups={n:obj.vertex_groups.new(name=n) for n in ['mixamorig:Spine2','mixamorig:'+side+'Arm','mixamorig:'+side+'ForeArm','TWIST_'+side]}
 for v in data.vertices:
  s,c,r=project(v.co);attach=smooth(-.025*H,.025*H,s);elbow=smooth(ul-.035*H,ul+.035*H,s);twist=smooth(ul,ul+fl,s)
  weights=[1-attach,attach*(1-elbow),attach*elbow*(1-twist),attach*elbow*twist]
  for group,value in zip(groups.values(),weights):
   if value>1e-6:group.add([v.index],value,'REPLACE')
 for f in data.polygons:f.use_smooth=True
 new_parts.append(obj);report.append({'side':side,'removed_source_faces':len(selected),'new_tube_quads':len(data.polygons),'length':end})
bm=bmesh.new();bm.from_mesh(body.data);bm.faces.ensure_lookup_table();bmesh.ops.delete(bm,geom=[bm.faces[i] for i in sorted(remove)],context='FACES');bm.to_mesh(body.data);bm.free()
bpy.ops.object.select_all(action='DESELECT');body.select_set(True)
for obj in new_parts:obj.select_set(True)
bpy.context.view_layer.objects.active=body;bpy.ops.object.join();body.name='CharacterBody'
bpy.ops.wm.save_as_mainfile(filepath=str(path))
for t in rig.animation_data.nla_tracks:t.mute=False
bpy.ops.object.select_all(action='DESELECT');body.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig;out=base/'godot/assets'/f'{who}_proxy.glb';bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_bake_animation=True,export_extras=True);match_durations(ROOT/f'art/models/archive/characters_before_apose_20261004/CH_{who}.glb',out)
(ROOT/f'evidence/character_roster_apose_20261004/{who}-sleeve-rebuild.json').write_text(json.dumps(report,indent=2));print('CLEAN_SLEEVE_REBUILD',who,report,flush=True)

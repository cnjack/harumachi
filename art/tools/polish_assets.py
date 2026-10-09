"""Fit owned Hyper3D parts, retain UV detail, and build separate actual glass apertures."""
import bpy,bmesh,json,math,sys
from pathlib import Path
import numpy as np
from mathutils import Vector,Matrix
sys.path.insert(0,str(Path(__file__).parent))
from level_util import support_plane,level_matrix
ROOT=Path(__file__).resolve().parents[2]
RAW=ROOT/'art/models/raw/scene_polish_20261004'
OUT=RAW/'assembled';OUT.mkdir(exist_ok=True)
ids=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['bus','cat_sit','cat_sleep','conifer','broadleaf']

def import_join(path,name):
 bpy.ops.object.select_all(action='DESELECT');before=set(bpy.context.scene.objects)
 bpy.ops.import_scene.gltf(filepath=str(path));objs=[o for o in bpy.context.scene.objects if o not in before and o.type=='MESH']
 bpy.ops.object.select_all(action='DESELECT')
 for o in objs:o.select_set(True)
 bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join();ob=bpy.context.object;ob.name=name
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 return ob

def bounds(ob):
 co=np.array([v.co[:] for v in ob.data.vertices]);return co.min(0),co.max(0)

def normalize(ob,height=None,length=None,bus=False):
 co=np.array([v.co[:] for v in ob.data.vertices]);base=co[co[:,2]<co[:,2].min()+np.ptp(co[:,2])*.18]
 normal,tilt,_,_=support_plane(base if len(base)>10 else co);ob.data.transform(level_matrix(normal))
 if bus:
  ob.data.transform(Matrix.Rotation(math.pi/2,4,'Z'));ob.data.transform(Matrix.Diagonal((1,-1,1,1)))
  bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
 lo,hi=bounds(ob);factor=(height/(hi[2]-lo[2])) if height else (length/(hi[0]-lo[0]))
 ob.data.transform(Matrix.Translation(Vector((-(lo[0]+hi[0])/2,-(lo[1]+hi[1])/2,-lo[2]))));ob.data.transform(Matrix.Scale(factor,4))
 print('NORMALIZED',ob.name,'tilt',tilt,'bounds',bounds(ob),flush=True)

def reduce(ob,target):
 tris=sum(len(p.vertices)-2 for p in ob.data.polygons)
 if tris>target:
  mod=ob.modifiers.new('UV preserving game reduction','DECIMATE');mod.ratio=target/tris
  bpy.context.view_layer.objects.active=ob;bpy.ops.object.modifier_apply(modifier=mod.name)

def split(ob,name,predicate,origin=(0,0,0),keep=True):
 bm=bmesh.new();bm.from_mesh(ob.data)
 copy=bm.copy();remove=[f for f in copy.faces if not predicate(f.calc_center_median(),f.index)]
 bmesh.ops.delete(copy,geom=remove,context='FACES');me=bpy.data.meshes.new(name);copy.to_mesh(me);copy.free()
 for mat in ob.data.materials:me.materials.append(mat)
 piece=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(piece);piece.location=origin;me.transform(Matrix.Translation(-Vector(origin)))
 selected=[f for f in bm.faces if predicate(f.calc_center_median(),f.index)];bmesh.ops.delete(bm,geom=selected,context='FACES');bm.to_mesh(ob.data);bm.free()
 if not keep:bpy.data.objects.remove(piece,do_unlink=True)
 return piece

def green_faces(ob):
 me=ob.data;n=len(me.polygons);out=np.zeros(n,dtype=bool);uv=me.uv_layers.active
 if uv is None:return out
 coords=np.array([v.co[:] for v in me.vertices]);lo,hi=bounds(ob)
 for mi,mat in enumerate(me.materials):
  if not mat.use_nodes:continue
  tex=next((node.image for node in mat.node_tree.nodes if node.type=='TEX_IMAGE' and node.image),None)
  if tex is None:continue
  w,h=tex.size;rgba=np.empty(w*h*4,dtype=np.float32);tex.pixels.foreach_get(rgba);pixels=rgba.reshape(h,w,4)
  for poly in me.polygons:
   if poly.material_index!=mi:continue
   centre=poly.center
   if centre.z<lo[2]+(hi[2]-lo[2])*.20:continue
   v=sum((uv.data[index].uv for index in poly.loop_indices),Vector((0,0)))/len(poly.loop_indices)
   rgb=pixels[int((v.y%1)*h)%h,int((v.x%1)*w)%w,:3]
   out[poly.index]=rgb[1]>rgb[0]*1.07 and rgb[1]>rgb[2]*1.07
 return out

def matte():
 for mat in bpy.data.materials:
  if not mat.use_nodes:continue
  bs=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
  if not bs:continue
  for key in ['Normal','Metallic','Roughness']:
   for link in list(bs.inputs[key].links):mat.node_tree.links.remove(link)
  bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0

def assemble_leaf_clusters(source):
 """Reuse a connected owned Rodin leaf cluster; placements form a complete layered crown."""
 bm=bmesh.new();bm.from_mesh(source.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000005)
 unseen=set(bm.verts);groups=[]
 while unseen:
  first=unseen.pop();stack=[first];group=[first]
  while stack:
   vert=stack.pop()
   for edge in vert.link_edges:
    other=edge.other_vert(vert)
    if other in unseen:unseen.remove(other);stack.append(other);group.append(other)
  groups.append(group)
 largest=set(max(groups,key=len));bmesh.ops.delete(bm,geom=[v for v in bm.verts if v not in largest],context='VERTS')
 bm.to_mesh(source.data);bm.free();reduce(source,450)
 lo,hi=bounds(source);source.data.transform(Matrix.Translation(-Vector((lo+hi)/2)));source.data.transform(Matrix.Scale(.60/max(hi-lo),4))
 rng=np.random.default_rng(74);lobes=[(-1.7,-.25,4.15,1.25,.95,.80),(1.55,.1,4.2,1.28,1.0,.83),(-.75,-1.15,4.55,1.18,.95,.83),(.85,1.1,4.5,1.2,.95,.82),(-.8,.15,5.35,1.3,1.1,.87),(.70,-.15,5.3,1.3,1.12,.85),(0,0,5.85,1.15,1.0,.60),(0,0,4.0,1.30,1.13,.70)]
 instances=[]
 for index,lobe in enumerate(lobes):
  centre=np.array(lobe[:3]);radius=np.array(lobe[3:])
  for sample in range(100):
   direction=rng.normal(size=3);direction/=np.linalg.norm(direction);shell=.55 if sample%4==0 else .86
   piece=bpy.data.objects.new('RodinLeafCluster_%d_%d'%(index,sample),source.data);bpy.context.collection.objects.link(piece)
   piece.location=centre+direction*radius*shell;piece.rotation_euler=(rng.uniform(-.35,.35),rng.uniform(-.35,.35),rng.uniform(0,math.tau));piece.scale=(1.0,1.0,1.0);instances.append(piece)
 bpy.data.objects.remove(source,do_unlink=True);bpy.ops.object.select_all(action='DESELECT')
 for piece in instances:piece.select_set(True)
 bpy.context.view_layer.objects.active=instances[0];bpy.ops.object.join();crown=bpy.context.object;crown.name='FoliageCrown'
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);reduce(crown,170000)
 # Original imagegen pixels remain untouched; map a fully leafy central region to the crown.
 mat=bpy.data.materials.new('PaintedAnimeCrown');mat.use_nodes=True
 bs=mat.node_tree.nodes.get('Principled BSDF');tex=mat.node_tree.nodes.new('ShaderNodeTexImage')
 tex.image=bpy.data.images.load(str(ROOT/'art/references/scene_polish/broadleaf_crown.png'));mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
 crown.data.materials.clear();crown.data.materials.append(mat)
 lo,hi=bounds(crown);size=hi-lo;uv=crown.data.uv_layers.active or crown.data.uv_layers.new(name='PaintedCrownUV')
 for poly in crown.data.polygons:
  poly.material_index=0
  for loop_index in poly.loop_indices:
   co=crown.data.vertices[crown.data.loops[loop_index].vertex_index].co
   uv.data[loop_index].uv=(.30+.40*(co.x-lo[0])/size[0],.30+.40*(co.z-lo[2])/size[2])
 return crown

for kind in ids:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 ob=import_join(RAW/kind/'model.glb','GeneratedBody')
 if kind=='bus':
  normalize(ob,length=4.6,bus=True)
  lo,hi=bounds(ob);print('BUS_EXTENT',lo,hi,flush=True)
  # Remove only outer window faces; generated trim and interior geometry remain intact.
  apertures=[(-1.92,-1.22),(-1.12,-.42),(-.32,.44),(1.32,1.94)]
  split(ob,'RemovedGlazing',lambda c,i:(1.10<c.z<1.87 and abs(c.y)>.80 and any(a<c.x<b for a,b in apertures)) or (c.x>2.04 and 1.13<c.z<1.93 and abs(c.y)<.65),keep=False)
  for wheel_i,x in enumerate([-1.51,1.45]):
   for side_i,side in enumerate([-1,1]):split(ob,'Wheel_%d'%(wheel_i*2+side_i),lambda c,i,x=x,side=side:(c.x-x)**2+(c.z-.34)**2<.355**2 and c.y*side>.65,(x,side*.80,.34))
  for door_i in range(2):
   x=.70+door_i*.22;split(ob,'DoorLeaf_%d'%door_i,lambda c,i,x=x:x<c.x<x+.22 and c.y<-.72 and .36<c.z<1.89,(x,-.83,.37))
  for piece in list(bpy.context.scene.objects):
   if piece.type=='MESH':reduce(piece,130000 if piece==ob else 12000)
  matte();bpy.ops.export_scene.gltf(filepath=str(OUT/'B01_bus.glb'),export_format='GLB',export_yup=True)
 elif kind.startswith('cat'):
  # glTF duplicates vertices at UV seams. Weld coincident geometry before
  # collapse so adjacent triangles stay connected; loop UVs remain separate.
  bm=bmesh.new();bm.from_mesh(ob.data)
  bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000005)
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
  bm.to_mesh(ob.data);bm.free()
  normalize(ob,height=.35 if kind=='cat_sit' else None,length=None if kind=='cat_sit' else .45)
  ob.name='CatBody';reduce(ob,120000);matte()
  bpy.ops.export_scene.gltf(filepath=str(OUT/('A22_cat_sit.glb' if kind=='cat_sit' else 'A20_cat_sleep.glb')),export_format='GLB',export_yup=True)
 else:
  normalize(ob,height=10.0 if kind=='conifer' else 6.5)
  mask=green_faces(ob);foliage=split(ob,'FoliageOriginal',lambda c,i:bool(mask[i]))
  ob.name='TrunkGenerated';reduce(ob,25000);reduce(foliage,75000)
  if kind=='broadleaf':
   crown=import_join(RAW/'broadleaf_crown/model.glb','FoliageCrown')
   crown=assemble_leaf_clusters(crown)
  matte()
  if kind=='conifer':
   bpy.ops.export_scene.gltf(filepath=str(OUT/'T04_slender_cedar.glb'),export_format='GLB',export_yup=True)
  else:
   for aid,scale in [('T01_courtyard_tree',1.0),('T02_summer_tree',8.0/6.5),('T03_round_ginkgo',7.5/6.5)]:
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    for piece in meshes:piece.scale=(scale,scale,scale)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(aid+'.glb')),export_format='GLB',export_yup=True)
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(kind+'.blend')))

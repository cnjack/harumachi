"""Normalize the Pixal3D bus; keep its painted mesh and split actual wheel/door surfaces."""
import bpy, bmesh, math, json, sys
from pathlib import Path
import numpy as np
from mathutils import Vector, Matrix
sys.path.insert(0,str(Path(__file__).parent))
from level_util import support_plane, level_matrix
ROOT=Path(__file__).resolve().parents[2]
raw=ROOT/'art/models/raw/B01_bus_pixal_20261004'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(raw/'model.glb'))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:o.select_set(True)
bpy.context.view_layer.objects.active=meshes[0]
bpy.ops.object.join();body=bpy.context.object;body.name='GeneratedBusBody'
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
coords=np.array([v.co[:] for v in body.data.vertices]);normal,tilt,_,_=support_plane(coords)
body.data.transform(level_matrix(normal))
coords=np.array([v.co[:] for v in body.data.vertices]);p=coords[coords[:,2]<np.quantile(coords[:,2],.7),:2]
best=(1e9,0)
for degree in np.arange(0,180,.1):
 a=math.radians(degree);rot=np.array([[math.cos(a),-math.sin(a)],[math.sin(a),math.cos(a)]])
 q=p@rot.T;extent=np.ptp(q,axis=0);area=float(np.prod(extent))
 if extent[0]>extent[1] and area<best[0]:best=(area,a)
body.data.transform(Matrix.Rotation(best[1],4,'Z'))
coords=np.array([v.co[:] for v in body.data.vertices]);lo=coords.min(0);hi=coords.max(0)
scale=6.2/(hi[0]-lo[0]);body.data.transform(Matrix.Translation(Vector((-(lo[0]+hi[0])/2,-(lo[1]+hi[1])/2,-lo[2]))))
body.data.transform(Matrix.Scale(scale,4))
for mat in body.data.materials:
 bs=mat.node_tree.nodes.get('Principled BSDF') if mat.use_nodes else None
 if bs:bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0
coords=np.array([v.co[:] for v in body.data.vertices])
report={'source_job':'809f845a-87ea-4af5-a3c9-5f9470286a4b','support_tilt_before':tilt,'yaw_degrees':math.degrees(best[1]),'bounds_min':coords.min(0).tolist(),'bounds_max':coords.max(0).tolist()}
# First normalize and inspect before using measured component positions.
bpy.ops.export_scene.gltf(filepath=str(raw/'normalized.glb'),export_format='GLB',export_yup=True)
(raw/'normalization.json').write_text(json.dumps(report,indent=2)+'\n')
print(report)
body.data.transform(Matrix.Diagonal((-1,1,1,1)))
bm=bmesh.new();bm.from_mesh(body.data)
# Remove the reconstructed duplicate mirror in the middle of the far flank.
bad=[f for f in bm.faces if (lambda c:c.y>1.20 and abs(c.x)<1.1 and c.z<2.25)(f.calc_center_median())]
bmesh.ops.delete(bm,geom=bad,context='FACES')
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free()
def split(name,predicate,origin):
 bm=bmesh.new();bm.from_mesh(body.data)
 selected=[f for f in bm.faces if predicate(f.calc_center_median())]
 copy=bm.copy();remove=[f for f in copy.faces if not predicate(f.calc_center_median())]
 bmesh.ops.delete(copy,geom=remove,context='FACES')
 me=bpy.data.meshes.new(name);copy.to_mesh(me);copy.free()
 for m in body.data.materials:me.materials.append(m)
 ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
 ob.location=origin;me.transform(Matrix.Translation(-Vector(origin)))
 bmesh.ops.delete(bm,geom=selected,context='FACES');bm.to_mesh(body.data);bm.free()
 mod=ob.modifiers.new('Back thickness','SOLIDIFY');mod.thickness=.018
 bpy.context.view_layer.objects.active=ob;bpy.ops.object.modifier_apply(modifier=mod.name)
 return ob
for i,x in enumerate([-1.49,2.38]):
 for j,side in enumerate([-1,1]):
  split('Wheel_%d'%(i*2+j),lambda c,x=x,side=side:((c.x-x)**2+(c.z-.43)**2)<.52**2 and c.y*side>.78,(x,side*1.07,.43))
for i in range(2):
 x=1.52+i*.27
 split('DoorLeaf_%d'%i,lambda c,x=x:x<c.x<x+.27 and c.y<-.95 and .45<c.z<2.06,(x,-1.09,.46))
# Simplify the AI body without altering the reconstructed silhouette or its UV texture.
mod=body.modifiers.new('Game mesh','DECIMATE');mod.ratio=.10
bpy.context.view_layer.objects.active=body;bpy.ops.object.modifier_apply(modifier=mod.name)
for ob in bpy.context.scene.objects:
 if ob.type=='MESH' and ob!=body:
  mod=ob.modifiers.new('Component game mesh','DECIMATE');mod.ratio=.30
  bpy.context.view_layer.objects.active=ob;bpy.ops.object.modifier_apply(modifier=mod.name)
assembled=raw/'assembled.glb'
bpy.ops.export_scene.gltf(filepath=str(assembled),export_format='GLB',export_yup=True)
bpy.ops.wm.save_as_mainfile(filepath=str(raw/'assembled.blend'))

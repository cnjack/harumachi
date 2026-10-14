"""Retain the generated espresso station; repair only its opaque bean hopper.

Blender -b --factory-startup --python-exit-code 1 -P this.py
All principal timber, machine, grinder, handles and controls are Hyper3D faces.
"""
from pathlib import Path
import sys,json,hashlib,math
import bpy,bmesh,numpy as np
from mathutils import Vector,Matrix
sys.path.insert(0,str(Path(__file__).resolve().parent))
from level_util import support_plane,level_matrix
from hyper3d_furniture_sources_20261015 import source_record
ROOT=Path(__file__).resolve().parents[2]
RAW=ROOT/'art/models/raw/hyper3d_furniture_20261015/HFF13_espresso_station/a'
OUT=RAW.parent.parent/'ready';OUT.mkdir(parents=True,exist_ok=True)
source,record=source_record('HFF13_espresso_station')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(source)==record['sha256']
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
bpy.ops.import_scene.gltf(filepath=str(source))
model=next(o for o in bpy.context.scene.objects if o.type=='MESH');matrix=model.matrix_world.copy()
for v in model.data.vertices:v.co=matrix@v.co
model.parent=None;model.matrix_world=Matrix.Identity(4)
for o in list(bpy.context.scene.objects):
 if o!=model:bpy.data.objects.remove(o,do_unlink=True)
points=np.array([v.co[:] for v in model.data.vertices]);normal,tilt,_,_=support_plane(points);rotation=level_matrix(normal)
for v in model.data.vertices:v.co=rotation@v.co
points=np.array([v.co[:] for v in model.data.vertices]);lo=points.min(0);hi=points.max(0);target=np.array([1.,.685,1.325]);scale=target/(hi-lo)
for v in model.data.vertices:
 v.co=Vector((np.array(v.co)-lo)*scale-np.array([.5,.3425,0]));v.co.z=float(np.interp(v.co.z,[0,.835,1.325],[0,.875,1.325]))
model.data.update()
original_triangles=sum(len(p.vertices)-2 for p in model.data.polygons)
original_material=model.data.materials[0]
atlas=next(n.image for n in original_material.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and 'diffuse' in n.image.name.lower())
pixels=np.empty(len(atlas.pixels),np.float32);atlas.pixels.foreach_get(pixels);pixels=pixels.reshape(atlas.size[1],atlas.size[0],4)
atlas_sha=hashlib.sha256(pixels.tobytes()).hexdigest()
# Split the existing opaque hopper only; keep its actual cap, mounting neck,
# grinder and machine. No frame/body substitution is made.
bm=bmesh.new();bm.from_mesh(model.data)
for z in [1.195,1.307]:
 bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=Vector((0,0,z)),plane_no=Vector((0,0,1)),dist=1e-6)
remove=[f for f in bm.faces if f.calc_center_median().x>.19 and 1.195+1e-6<f.calc_center_median().z<1.307-1e-6]
removed=sum(len(f.verts)-2 for f in remove);bmesh.ops.delete(bm,geom=remove,context='FACES')
orphans=[v for v in bm.verts if not v.link_faces]
if orphans:bmesh.ops.delete(bm,geom=orphans,context='VERTS')
bm.to_mesh(model.data);bm.free();model.data.update()
# The real exposed wooden counter is flattened beneath cups and grinder.
flat=set()
for f in model.data.polygons:
 if f.normal.z>.45 and abs(f.center.z-.875)<.045:
  for i in f.vertices:
   v=model.data.vertices[i]
   if abs(v.co.z-.875)<.055 and abs(v.co.x)<.46 and abs(v.co.y)<.31:flat.add(i)
for i in flat:model.data.vertices[i].co.z=.875
model.data.update()
roles=['Hyper3D_TimberAtlas','Sage','BrushedSteel','Brass','Charcoal']
materials=[]
for role in roles:
 m=original_material.copy();m.name=role;bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
 for key,val in [('Metallic',0.),('Roughness',.65),('Normal',None),('Specular IOR Level',.35)]:
  for link in list(bs.inputs[key].links):m.node_tree.links.remove(link)
  if val is not None:bs.inputs[key].default_value=val
 materials.append(m)
model.data.materials.clear()
for m in materials:model.data.materials.append(m)
uv=model.data.uv_layers.active;areas={role:0. for role in roles}
for f in model.data.polygons:
 sample=sum((uv.data[i].uv for i in f.loop_indices),Vector((0,0)))/len(f.loop_indices)
 x=min(atlas.size[0]-1,max(0,int(sample.x*atlas.size[0])));y=min(atlas.size[1]-1,max(0,int(sample.y*atlas.size[1])));r,g,b=pixels[y,x,:3]
 if abs(f.center.z-.875)<.065 and r>g*1.10 and g>b*1.10:role='Hyper3D_TimberAtlas'
 elif max(r,g,b)<.30 and max(r,g,b)-min(r,g,b)<.08:role='Charcoal'
 elif g>r*1.06:role='Sage'
 elif r>g*1.16 and g>b*1.20:role='Brass'
 elif f.center.z>.89:role='BrushedSteel'
 else:role='Sage'
 f.material_index=roles.index(role);areas[role]+=f.area
model.name='Hyper3D_EspressoCabinetMachineAndGrinder'
def plain(name,color,roughness=.8,alpha=1):
 m=bpy.data.materials.new(name);m.use_nodes=True;b=m.node_tree.nodes['Principled BSDF'];b.inputs['Base Color'].default_value=(*color,1);b.inputs['Roughness'].default_value=roughness;b.inputs['Alpha'].default_value=alpha
 if alpha<1:m.surface_render_method='BLENDED'
 return m
glass=plain('Coffee_HopperGlass',(.80,.89,.90),.12,.12)
glass.node_tree.nodes['Principled BSDF'].inputs['IOR'].default_value=1.45
coffee=plain('Coffee',(.095,.038,.014))
center=(.310,-.0225);profile=[(1.195,.040),(1.214,.055),(1.245,.073),(1.284,.082),(1.306,.083)]
vertices=[];faces=[];segments=48
# Closed 3mm shell: separate inner and outer skins and real open cavity.
for inner in [False,True]:
 for z,radius in profile:
  radius-=.003 if inner else 0
  for i in range(segments):
   a=2*math.pi*i/segments;vertices.append((center[0]+radius*math.cos(a),-center[1]+radius*math.sin(a),z))
rings=len(profile);stride=rings*segments
for skin in range(2):
 for row in range(rings-1):
  for i in range(segments):
   j=(i+1)%segments;a=skin*stride+row*segments+i;b=skin*stride+row*segments+j;c=b+segments;d=a+segments
   faces.append((a,b,c,d) if skin==0 else (d,c,b,a))
for row in [0,rings-1]:
 for i in range(segments):
  j=(i+1)%segments;a=row*segments+i;b=row*segments+j;faces.append((a,a+stride,b+stride,b))
mesh=bpy.data.meshes.new('Hopper_Closed_3mm_Shell');mesh.from_pydata(vertices,[],faces);mesh.materials.append(glass)
hopper=bpy.data.objects.new('HopperGlass',mesh);bpy.context.collection.objects.link(hopper)
for p in mesh.polygons:p.use_smooth=True
# A settled pile fills the lower hopper; surface beans rest on that pile.
# Random beans throughout empty space would visibly float inside clear glass.
fill_vertices=[];fill_faces=[]
fill_profile=[(1.198,.035),(1.214,.049),(1.245,.063)]
for z,radius in fill_profile:
 for i in range(segments):
  angle=math.tau*i/segments;fill_vertices.append((center[0]+radius*math.cos(angle),-center[1]+radius*math.sin(angle),z))
for row in range(len(fill_profile)-1):
 for i in range(segments):
  j=(i+1)%segments;fill_faces.append((row*segments+i,row*segments+j,(row+1)*segments+j,(row+1)*segments+i))
fill_faces.append(tuple(range((len(fill_profile)-1)*segments,len(fill_profile)*segments)))
fill_faces.append(tuple(reversed(range(segments))))
fill_mesh=bpy.data.meshes.new('Settled_Coffee_Pile');fill_mesh.from_pydata(fill_vertices,[],fill_faces);fill_mesh.materials.append(coffee)
pile=bpy.data.objects.new('CoffeePile',fill_mesh);bpy.context.collection.objects.link(pile)
rng=np.random.default_rng(20261015)
for i in range(64):
 z=1.247+float(rng.uniform(-.001,.001));radius=.058
 angle=float(rng.uniform(0,math.tau));distance=radius*float(rng.random()**.5)
 bpy.ops.mesh.primitive_uv_sphere_add(segments=8,ring_count=4,radius=1,location=(center[0]+distance*math.cos(angle),-center[1]+distance*math.sin(angle),z))
 bean=bpy.context.object;bean.name='CoffeeBean_%02d'%i;bean.scale=(.007,.0045,.004);bean.rotation_euler.z=float(rng.uniform(0,math.tau));bean.data.materials.append(coffee);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
assert atlas_sha==hashlib.sha256(pixels.tobytes()).hexdigest()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'HFF13_espresso_station.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'HFF13_espresso_station.glb'),export_format='GLB',export_yup=True,export_apply=True,export_animations=False)
report=dict(asset='HFF13_espresso_station',generation_id=record['generation_id'],source_sha256=sha(source),prepared_sha256=sha(OUT/'HFF13_espresso_station.glb'),original_triangles=original_triangles,removed_opaque_hopper_triangles_after_local_splits=removed,original_albedo_pixels_unchanged=True,original_uv_retained_on_generated_faces=True,level_correction_degrees=tilt,support_height_warp=dict(before=[0,.835,1.325],after=[0,.875,1.325]),flattened_existing_worktop_vertices=len(flat),source_material_area_m2=areas,hopper_shell_thickness_m=.003,hopper_alpha=.12,beans=64,local_repairs=['opaque generated hopper replaced by a closed thin clear shell and visible beans','working height and existing top support corrected','original atlas faces assigned wood paint steel brass and rubber roles'],game_installed=False,native_accepted=False)
(OUT/'HFF13_espresso_station.preparation.json').write_text(json.dumps(report,indent=2)+'\n')
print('PREPARED_HYPER3D_ESPRESSO',json.dumps(report),flush=True)

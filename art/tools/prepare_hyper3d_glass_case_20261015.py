"""Keep the generated cabinet; repair only measured supports and real glazing.

Blender --python-exit-code 1 -P this.py. Never writes a game asset.
"""
from pathlib import Path
import sys,json,hashlib
import bpy,bmesh,numpy as np
from mathutils import Vector,Matrix
sys.path.insert(0,str(Path(__file__).resolve().parent))
from level_util import support_plane,level_matrix
from hyper3d_furniture_sources_20261015 import source_record
ROOT=Path(__file__).resolve().parents[2]
RAW=ROOT/'art/models/raw/hyper3d_furniture_20261015/HFF11_glass_case/a'
OUT=ROOT/'art/models/raw/hyper3d_furniture_20261015/ready';OUT.mkdir(parents=True,exist_ok=True)
source,record=source_record('HFF11_glass_case');digest=hashlib.sha256(source.read_bytes()).hexdigest()
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0;bpy.ops.import_scene.gltf(filepath=str(source))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];assert len(meshes)==1
model=meshes[0];matrix=model.matrix_world.copy()
for v in model.data.vertices:v.co=matrix@v.co
model.parent=None;model.matrix_world=Matrix.Identity(4)
for o in list(bpy.context.scene.objects):
 if o!=model:bpy.data.objects.remove(o,do_unlink=True)
points=np.array([v.co[:] for v in model.data.vertices]);normal,tilt,_,_=support_plane(points);rotation=level_matrix(normal)
for v in model.data.vertices:v.co=rotation@v.co
points=np.array([v.co[:] for v in model.data.vertices]);lo=points.min(0);hi=points.max(0);target=np.array([1.34,.75,1.149]);scale=target/(hi-lo)
for v in model.data.vertices:
 p=(np.array(v.co)-lo)*scale-np.array([.67,.375,0]);v.co=Vector(p)
model.data.update()
source_triangles=sum(len(p.vertices)-2 for p in model.data.polygons)
source_surface_area=sum(p.area for p in model.data.polygons)
atlas=next(n.image for m in model.data.materials if m and m.use_nodes for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and 'diffuse' in n.image.name.lower())
pixels=np.empty(len(atlas.pixels),np.float32);atlas.pixels.foreach_get(pixels);pixels=pixels.reshape(atlas.size[1],atlas.size[0],4)
albedo_bytes_before=hashlib.sha256(pixels.tobytes()).hexdigest()
for m in model.data.materials:
 m.name='Hyper3D_CaseAtlas'
 if not m.use_nodes:continue
 bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
 for name,value in [('Metallic',0.),('Roughness',.60),('Normal',None),('Specular IOR Level',.35)]:
  for link in list(bs.inputs[name].links):m.node_tree.links.remove(link)
  if value is not None:bs.inputs[name].default_value=value
bm=bmesh.new();bm.from_mesh(model.data)
# Split at exact aperture/support boundaries before deleting the opaque panes.
# Centroid-only deletion otherwise leaves saw-toothed triangle fringes.
for axis,positions in [(0,[-.61,.61]),(1,[-.33,.33]),(2,[.48,.503,.792,.818,1.11])]:
 for position in positions:
  point=Vector((0,0,0));point[axis]=position;normal_axis=Vector((0,0,0));normal_axis[axis]=1
  bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=point,plane_no=normal_axis,dist=1e-6)
bm.normal_update();uvs=bm.loops.layers.uv.active;assert uvs
remove=[];shelves=[]
for face in bm.faces:
 center=face.calc_center_median();uv=sum((loop[uvs].uv for loop in face.loops),Vector((0,0)))/len(face.loops)
 xx=min(atlas.size[0]-1,max(0,int(uv.x*atlas.size[0])));yy=min(atlas.size[1]-1,max(0,int(uv.y*atlas.size[1])));r,g,b=pixels[yy,xx,:3]
 timber=r>g*1.13 and g>b*1.08
 # The two actual generated horizontal boards remain. Only grey exterior
 # glazing planes between boards are removed; original timber is untouched.
 at_shelf=.48-1e-6<=center.z<=.503+1e-6 or .792-1e-6<=center.z<=.818+1e-6
 aperture=.503+1e-6<center.z<1.11-1e-6 and not at_shelf
 beyond_board=at_shelf and (abs(center.x)>.61+1e-6 or abs(center.y)>.33+1e-6)
 inner_window=aperture and (abs(center.x)<.61+1e-6 or abs(center.y)<.33+1e-6)
 top=center.z>1.11 and abs(center.x)<.61+1e-6 and abs(center.y)<.33+1e-6
 if inner_window or top or (not timber and (aperture or beyond_board)):remove.append(face)
 elif not timber and at_shelf:shelves.append(face)
removed_triangles=sum(len(f.verts)-2 for f in remove)
bmesh.ops.delete(bm,geom=remove,context='FACES')
orphan=[v for v in bm.verts if not v.link_faces]
if orphan:bmesh.ops.delete(bm,geom=orphan,context='VERTS')
retained_source_surface_area=sum(f.calc_area() for f in bm.faces)
bm.to_mesh(model.data);bm.free();model.data.update()
# Move existing support geometry continuously to the game's two display levels.
old=[0.,.50,.815,1.149];new=[0.,.60,.84,1.149]
for vertex in model.data.vertices:vertex.co.z=float(np.interp(vertex.co.z,old,new))
model.data.update();model.name='Hyper3D_CabinetFrameAndShelves'
ivory=bpy.data.materials.new('I02_DisplayIvory');ivory.use_nodes=True;bs=ivory.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(.86,.82,.70,1);bs.inputs['Roughness'].default_value=.82;bs.inputs['Specular IOR Level'].default_value=.2
model.data.materials.append(ivory);ivory_index=len(model.data.materials)-1
for face in model.data.polygons:
 center=face.center
 near_shelf=min(abs(center.z-.60),abs(center.z-.84))<.028
 vertical_span=max(model.data.vertices[i].co.z for i in face.vertices)-min(model.data.vertices[i].co.z for i in face.vertices)
 if near_shelf and vertical_span<.045 and abs(center.x)<.61 and abs(center.y)<.33:face.material_index=ivory_index
# Flatten only upward vertices on the usable source shelf boards, preserving
# the generated boards, edge profiles, frame, UV loops and original image.
model.data.update();flat=0
for v in model.data.vertices:
 for level in [.60,.84]:
  if abs(v.co.z-level)<.014 and v.normal.z>.55 and abs(v.co.x)<.61 and abs(v.co.y)<.33:
   v.co.z=level;flat+=1;break
model.data.update()
glass=bpy.data.materials.new('Glass_Thin_Clear');glass.use_nodes=True;bs=glass.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(.82,.90,.92,1);bs.inputs['Alpha'].default_value=.12;bs.inputs['Roughness'].default_value=.12;bs.inputs['IOR'].default_value=1.45;bs.inputs['Specular IOR Level'].default_value=.5;glass.surface_render_method='BLENDED'
bead=bpy.data.materials.new('Glass_CedarBeading');bead.use_nodes=True;bs=bead.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(.46,.24,.08,1);bs.inputs['Roughness'].default_value=.60
def pane(name,size,at,material=glass):
 bpy.ops.mesh.primitive_cube_add(size=1,location=(at[0],-at[2],at[1]));o=bpy.context.object;o.name=name;o.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(material)
bottom=.612;upper=1.111;mid=(bottom+upper)*.5;thickness=.006
pane('GlassFront',(1.235,upper-bottom,thickness),(0,mid,.353))
pane('GlassBack',(1.235,upper-bottom,thickness),(0,mid,-.353))
pane('GlassSideLeft',(thickness,upper-bottom,.700),(-.621,mid,0))
pane('GlassSideRight',(thickness,upper-bottom,.700),(.621,mid,0))
pane('GlassTop',(1.235,thickness,.700),(0,upper,0))
# Narrow real glazing beads cover the newly cut inner seams without replacing
# the generated outside frame; thin edge caps finish the original shelf cuts.
for xsign in [-1,1]:
 for zsign in [-1,1]:pane('GlazingBeadPost_%d_%d'%(xsign,zsign),(.035,upper-bottom,.035),(xsign*.6225,mid,zsign*.347),bead)
for y in [bottom,upper]:
 for sign in [-1,1]:
  pane('GlazingBeadLong_%d_%d'%(int(y*1000),sign),(1.280,.035,.035),(0,y,sign*.347),bead)
  pane('GlazingBeadSide_%d_%d'%(int(y*1000),sign),(.035,.035,.720),(sign*.6225,y,0),bead)
for level in [.60,.84]:
 for sign in [-1,1]:
  pane('ShelfCutEdgeLong_%d_%d'%(int(level*1000),sign),(1.220,.020,.004),(0,level-.010,sign*.328),ivory)
  pane('ShelfCutEdgeSide_%d_%d'%(int(level*1000),sign),(.004,.020,.660),(sign*.608,level-.010,0),ivory)
assert hashlib.sha256(pixels.tobytes()).hexdigest()==albedo_bytes_before
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'HFF11_glass_case.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'HFF11_glass_case.glb'),export_format='GLB',export_yup=True,export_apply=True,export_animations=False,export_image_format='AUTO')
retained=sum(len(p.vertices)-2 for p in model.data.polygons)
report=dict(asset='HFF11_glass_case',generation_id=record['generation_id'],source_sha256=digest,prepared_sha256=hashlib.sha256((OUT/'HFF11_glass_case.glb').read_bytes()).hexdigest(),original_triangles=source_triangles,removed_grey_glazing_triangles_after_local_splits=removed_triangles,retained_hyper3d_triangles_after_local_splits=retained,original_generated_surface_area_m2=source_surface_area,retained_generated_surface_area_before_support_warp_m2=retained_source_surface_area,retained_generated_surface_area_fraction=retained_source_surface_area/source_surface_area,provenance_note='Original generated cabinet, outside frame and shelf geometry retained with original UV/albedo. Triangle counts after bisect are not a source retention percentage; planar glazing and narrow seam/cut-edge finishes are local repairs.',level_correction_degrees=tilt,affine_scale_blender=scale.tolist(),support_height_warp=dict(before=old,after=new),flattened_existing_shelf_vertices=flat,glass_panels=5,glass_thickness_m=thickness,glass_alpha=.12,original_atlas_pixels_unchanged=True,game_installed=False,native_glass_accepted=False,required_next='Four-side prepared review, aperture ray/texture checks, original-frame contact measurements, real stock support and native multi-angle/day/night verification before replacing game asset.')
(OUT/'HFF11_glass_case.preparation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('PREPARED_GLASS_PROTOTYPE',json.dumps(report),flush=True)

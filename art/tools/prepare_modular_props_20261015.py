"""Fit reviewed Hyper3D geometry, retain its painted atlas, and compose reusable signs."""
from pathlib import Path
import sys,json,hashlib,math
import bpy,numpy as np
from mathutils import Vector,Matrix
sys.path.insert(0,str(Path(__file__).resolve().parent))
from level_util import support_plane,level_matrix
ROOT=Path(__file__).resolve().parents[2]
RAW=ROOT/'art/models/raw/modular_props_20261015';OUT=RAW/'ready';OUT.mkdir(parents=True,exist_ok=True)
SCOPE=json.loads((ROOT/'art/manifests/modular_props_20261015.json').read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def reset():
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
def export(aid):
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(aid+'.blend')))
 bpy.ops.export_scene.gltf(filepath=str(OUT/(aid+'.glb')),export_format='GLB',export_yup=True,export_apply=True,export_animations=False,export_image_format='AUTO',export_extras=True)
def prepare(row):
 aid=row['id'];src=RAW/aid/'a/model.glb'
 if not src.is_file():src=ROOT/'art/library/modular_props_20261015/source'/(aid+'.glb')
 reset();bpy.ops.import_scene.gltf(filepath=str(src))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
 for o in meshes:
  matrix=o.matrix_world.copy()
  for v in o.data.vertices:v.co=matrix@v.co
  o.parent=None;o.matrix_world=Matrix.Identity(4)
 for o in list(bpy.context.scene.objects):
  if o not in meshes:bpy.data.objects.remove(o,do_unlink=True)
 bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();o=bpy.context.object
 original_tris=sum(len(p.vertices)-2 for p in o.data.polygons)
 if aid not in ['MS07_timetable_case','MS13_picture_frame']:
  normal,tilt,_,_=support_plane(np.array([v.co[:] for v in o.data.vertices]))
  if tilt>.5:
   rotation=level_matrix(normal)
   for v in o.data.vertices:v.co=rotation@v.co
 low=Vector([min(v.co[k] for v in o.data.vertices) for k in range(3)])
 high=Vector([max(v.co[k] for v in o.data.vertices) for k in range(3)])
 xyz=row['nominal_size_m_xyz'];target=Vector((xyz[0],xyz[2],xyz[1]));factor=Vector([target[k]/(high[k]-low[k]) for k in range(3)])
 for v in o.data.vertices:
  v.co=Vector([(v.co[k]-low[k])*factor[k] for k in range(3)])-Vector((target.x/2,target.y/2,0))
  if v.co.z<.003:v.co.z=0
 o.name=aid+'_Hyper3D';o.data.update()
 # Keep source image/UVs; reduce excessive coplanar tessellation, not real board depth.
 budget=5000 if aid=='MS08_storage_bay' else (6500 if aid in ['MS01_signpost','MS02_arrow_board','MS04_wall_plaque','MS07_timetable_case','MS13_picture_frame'] else 12000)
 if original_tris>budget:
  dec=o.modifiers.new('Game_triangle_budget','DECIMATE');dec.ratio=budget/original_tris;dec.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=dec.name)
 for m in o.data.materials:
  m.name='Hyper3D_OriginalAtlas_'+aid
  if not m.use_nodes:continue
  bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
  for key,value in [('Metallic',0.),('Roughness',.72),('Normal',None),('Specular IOR Level',.32)]:
   for link in list(bs.inputs[key].links):m.node_tree.links.remove(link)
   if value is not None:bs.inputs[key].default_value=value
 o['source_generation']=json.loads((ROOT/'art/library/modular_props_20261015/provenance.json').read_text())['assets'][aid]['generation_id'];o['modular_source']=aid
 export(aid)
 report=dict(id=aid,source_sha256=sha(src),prepared_sha256=sha(OUT/(aid+'.glb')),source_generation=o['source_generation'],original_triangles=original_tris,prepared_triangles=sum(len(p.vertices)-2 for p in o.data.polygons),nominal_size_m_xyz=xyz,local_changes=['affine metre-scale fit and base centering','up to 3mm foot leveling','limited coplanar triangle reduction with original UV interpolation'],atlas_repainted=False,source_front='Godot +Z')
 (OUT/(aid+'.preparation.json')).write_text(json.dumps(report,indent=2)+'\n');print('PREPARED',aid,report['prepared_triangles'],flush=True)
def piece(aid,name,at,scale=(1,1,1),yaw=0):
 previous=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=str(OUT/(aid+'.glb')))
 objects=[o for o in bpy.context.scene.objects if o not in previous and o.type=='MESH']
 for o in objects:
  mat=Matrix.Translation(Vector((at[0],-at[2],at[1])))@Matrix.Rotation(math.radians(yaw),4,'Z')@Matrix.Diagonal(Vector((scale[0],scale[2],scale[1],1)))
  old=o.matrix_world.copy()
  o.parent=None;o.matrix_world=mat@old;o.name=name;o['modular_source']=aid
 for o in list(bpy.context.scene.objects):
  if o not in previous and o not in objects:bpy.data.objects.remove(o,do_unlink=True)
 return objects
def compose():
 for aid,turns in [('P_signpost',[0,180,25]),('R09',[180,0,180])]:
  reset();piece('MS01_signpost','Post',(0,0,0))
  for i,turn in enumerate(turns):piece('MS02_arrow_board','Arrow_%d'%i,(.22 if turn!=180 else -.22,1.85-i*.4,.10),yaw=turn)
  export(aid)
 reset()
 for x in [-.55,.55]:piece('MS01_signpost','Post_%d'%int(x*100),(x,0,-.02),(.5,1.4/2.2,.5))
 piece('MS04_wall_plaque','EventBoard',(0,.75,.045),(1.1/1.2,.6/.24,1.25));export('MS14_event_board')
if __name__=='__main__':
 ids=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
 for row in SCOPE['assets']:
  if not ids or row['id'] in ids:prepare(row)
 if not ids or 'compose' in ids:compose()

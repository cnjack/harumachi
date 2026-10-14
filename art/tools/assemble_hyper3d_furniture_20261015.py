"""Compose reusable Hyper3D furniture; partition actual faces for game contracts.

Outputs remain under art/models/raw until reviewed and exported by game_export.
No principal procedural replacement geometry or invisible support proxies.
"""
from pathlib import Path
import sys,json,hashlib,math
import bpy,bmesh
import numpy as np
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[2]
RAW=ROOT/'art/models/raw/hyper3d_furniture_20261015'
OUT=RAW/'assembled';OUT.mkdir(parents=True,exist_ok=True)
SCOPE={r['id']:r for r in json.loads((ROOT/'art/manifests/hyper3d_furniture_20261015.json').read_text())['assets']}
TEMPLATES={}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def tris(objects):return sum(len(p.vertices)-2 for o in objects if o.type=='MESH' for p in o.data.polygons)
def part_name(aid,face):
 p=face.center;x,y,z=p.x,-p.y,p.z
 if aid in ['HFF01_cafe_chair','HFF12_reading_armchair']:
  if .405<z<.555 and abs(x)<.265 and abs(y)<.225:return 'Seat'
  if aid=='HFF12_reading_armchair' and .58<z<.72 and abs(x)>.21:return 'Arm' if x<0 else 'Arm_001'
  if z>.57:return 'Back'
  return 'Frame'
 if aid=='HFF02_round_table':return 'Top' if z>.69 else ('Foot' if z<.065 else 'Pedestal')
 if aid in ['HFF03_rect_table','HFF04_low_table','HFF06_indoor_bench']:
  height={'HFF03_rect_table':.75,'HFF04_low_table':.43,'HFF06_indoor_bench':.43}[aid]
  return 'Top' if z>height-.07 else 'Frame'
 if aid=='HFF05_utility_stand':
  if z>.77:return 'Top'
  if .15<z<.255 and abs(x)<.43 and abs(y)<.24:return 'LowerBoard'
  return 'Frame'
 if aid=='HFF07_sage_counter':return 'CounterTop' if z>.78 else 'CounterBody'
 if aid in ['HFF08_bread_rack4','HFF09_bread_rack3','HFF10_wall_shelf']:
  levels={'HFF08_bread_rack4':[.28,.62,.95,1.27],'HFF09_bread_rack3':[.36,.66,1.01],'HFF10_wall_shelf':[.25,.70]}[aid]
  index=min(range(len(levels)),key=lambda i:abs(z-levels[i]))
  return 'TrayBoard_%d'%index if abs(z-levels[index])<.055 else 'RackFrame'
 if aid=='HFF14_outdoor_bench':return 'Seat' if .35<z<.50 else ('Back' if z>.55 else 'Frame')
 if aid=='HFF11_glass_case':return 'CabinetBase' if z<.57 else ('TopRail' if z>1.075 else 'CabinetFrameAndShelves')
 raise ValueError(aid)
def partition(ob,groups):
 before=tris([ob]);result=[]
 for name,indices in groups.items():
  if not indices:continue
  copy=ob.copy();copy.data=ob.data.copy();copy.name=name;bpy.context.collection.objects.link(copy)
  bm=bmesh.new();bm.from_mesh(copy.data);bm.faces.ensure_lookup_table()
  bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index not in indices],context='FACES')
  orphan=[v for v in bm.verts if not v.link_faces]
  if orphan:bmesh.ops.delete(bm,geom=orphan,context='VERTS')
  bm.to_mesh(copy.data);bm.free();copy.data.update();result.append(copy)
 assert tris(result)==before,'Face partition must retain exactly the real source triangles'
 bpy.data.objects.remove(ob,do_unlink=True);return result
def single(aid):
 if aid in TEMPLATES:
  result=[]
  for name,data,matrix in TEMPLATES[aid]:
   ob=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(ob);ob.matrix_world=matrix.copy();result.append(ob)
  return result
 before=set(bpy.data.objects);source=RAW/'ready'/(aid+'.glb');record=json.loads(source.with_suffix('.preparation.json').read_text());assert sha(source)==record['prepared_sha256']
 bpy.ops.import_scene.gltf(filepath=str(source));added=[o for o in bpy.data.objects if o not in before];objects=[]
 for ob in added:
  if ob.type!='MESH':continue
  transform=ob.matrix_world.copy()
  for v in ob.data.vertices:v.co=transform@v.co
  ob.parent=None;ob.matrix_world=Matrix.Identity(4);ob.data.update();objects.append(ob)
 for ob in added:
  if ob.type!='MESH':bpy.data.objects.remove(ob,do_unlink=True)
 result=[]
 for ob in objects:
  if aid=='HFF13_espresso_station':
   if ob.name.startswith('Hyper3D_'):
    groups={}
    for face in ob.data.polygons:
     role=ob.data.materials[face.material_index].name.split('.')[0]
     label={'Hyper3D_TimberAtlas':'Worktop','Sage':'CabinetPaint','BrushedSteel':'BrushedSteel_Geometry','Brass':'CabinetPulls','Charcoal':'RubberParts'}[role]
     groups.setdefault(label,set()).add(face.index)
    result.extend(partition(ob,groups))
   else:result.append(ob)
  elif aid=='HFF11_glass_case' and not ob.name.startswith('Hyper3D_'):result.append(ob)
  else:
   groups={}
   for face in ob.data.polygons:groups.setdefault(part_name(aid,face),set()).add(face.index)
   result.extend(partition(ob,groups))
 TEMPLATES[aid]=[(ob.name,ob.data,ob.matrix_world.copy()) for ob in result]
 return result
def place(objects,at=(0,0,0),yaw=0,scale=(1,1,1),prefix=''):
 rotation=Matrix.Rotation(math.radians(yaw),4,'Z');translation=Vector((at[0],-at[2],at[1]));scaling=Matrix.Diagonal((scale[0],scale[2],scale[1],1))
 for ob in objects:
  ob.name=prefix+ob.name;ob.matrix_world=Matrix.Translation(translation)@rotation@scaling@ob.matrix_world
 return objects
def aux(source_id,patterns):
 source=ROOT/'art/library/furniture_forms_20261014/source'/(source_id+'.glb')
 before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(source));result=[]
 for ob in list(bpy.data.objects):
  if ob in before:continue
  if ob.type=='MESH' and any(ob.name.startswith(s) for s in patterns):
   transform=ob.matrix_world.copy();ob.parent=None;ob.matrix_world=transform;result.append(ob)
  else:bpy.data.objects.remove(ob,do_unlink=True)
 return result
def reshape(objects,source_size,target_size,old_y=None,new_y=None):
 # Preserve the outer leg/post widths while changing the board span. Original
 # topology and UV loops stay unchanged; only source coordinates are fitted.
 def axis(value,old,new,band):
  inner=old*.5-band;target_inner=new*.5-band
  if new<=band*2.2:return value*new/old
  return math.copysign(target_inner+abs(value)-inner,value) if abs(value)>inner else value*target_inner/inner
 for ob in objects:
  ob.data=ob.data.copy()
  for v in ob.data.vertices:
   v.co.x=axis(v.co.x,source_size[0],target_size[0],min(.13,source_size[0]*.2))
   v.co.y=axis(v.co.y,source_size[2],target_size[2],min(.10,source_size[2]*.2))
   v.co.z=float(np.interp(v.co.z,old_y,new_y)) if old_y else v.co.z*target_size[1]/source_size[1]
  ob.data.update()
 return objects
def legacy(aid,predicate):
 source=ROOT/'art/library/hyper3d_furniture_20261015/legacy_auxiliary'/(aid+'.glb')
 before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(source));kept=[]
 for ob in list(bpy.data.objects):
  if ob in before:continue
  if ob.type!='MESH':bpy.data.objects.remove(ob,do_unlink=True);continue
  transform=ob.matrix_world.copy()
  for v in ob.data.vertices:v.co=transform@v.co
  ob.parent=None;ob.matrix_world=Matrix.Identity(4);ob.data.update()
  indices={f.index for f in ob.data.polygons if predicate(ob,f)}
  if indices:
   bm=bmesh.new();bm.from_mesh(ob.data);bm.faces.ensure_lookup_table();bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index not in indices],context='FACES');orphan=[v for v in bm.verts if not v.link_faces]
   if orphan:bmesh.ops.delete(bm,geom=orphan,context='VERTS')
   bm.to_mesh(ob.data);bm.free();ob.data.update();kept.append(ob)
  else:bpy.data.objects.remove(ob,do_unlink=True)
 return kept
def assemble(aid):
 TEMPLATES.clear();bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0;components=[];auxiliary=[]
 if aid in SCOPE:components=[aid];single(aid)
 elif aid=='P_cafe_table':
  components=['HFF02_round_table','HFF01_cafe_chair'];round_parts=single(components[0])
  for ob in round_parts:
   if ob.name=='Top':ob.name='RoundTop'
  place(single(components[1]),(-.70,0,0),90,prefix='ChairLeft');place(single(components[1]),(.70,0,0),-90,prefix='ChairRight')
 elif aid=='P_community_table':
  components=['HFF03_rect_table','HFF01_cafe_chair'];place(single(components[0]),prefix='Shared')
  for i,x in enumerate([-.68,0,.68]):
   place(single(components[1]),(x,0,-.87),0,prefix='ChairBack');place(single(components[1]),(x,0,.87),180,prefix='ChairFront')
 elif aid=='P_reading_chair':components=['HFF12_reading_armchair'];place(single(components[0]),prefix='ReadingChair')
 elif aid=='I04_shop_counter':
  components=['HFF07_sage_counter'];single(components[0]);aux('I04_shop_counter',['Register','Display']);auxiliary=['existing register, keys and display; counter geometry entirely Hyper3D']
 elif aid in ['I05_bread_shelf','W17_display_shelf','I02_cake_showcase','P_coffee_station','A12_bench']:
  components=[{'I05_bread_shelf':'HFF08_bread_rack4','W17_display_shelf':'HFF09_bread_rack3','I02_cake_showcase':'HFF11_glass_case','P_coffee_station':'HFF13_espresso_station','A12_bench':'HFF14_outdoor_bench'}[aid]];single(components[0])
 elif aid=='J03_dining_set':
  components=['HFF03_rect_table','HFF01_cafe_chair'];reshape(single(components[0]),[2.05,.75,1.],[.90,.75,1.001])
  place(single(components[1]),(-.515,0,0),90,prefix='DiningLeft');place(single(components[1]),(.515,0,0),-90,prefix='DiningRight')
 elif aid=='J07_kotatsu':
  components=['HFF04_low_table'];reshape(single(components[0]),[1.45,.43,.85],[1.45,.446,1.20])
  quilt=legacy(aid,lambda ob,f:f.center.z<.395 and (abs(f.center.x)>.42 or abs(f.center.y)>.43));auxiliary=['existing Hunyuan quilt faces retained; table and legs are Hyper3D']
  for ob in quilt:ob.name='KotatsuQuilt'
 elif aid=='P_low_bookcase':
  components=['HFF09_bread_rack3'];reshape(single(components[0]),[1.09,1.25,.5],[1.35,1.09,.34],[0,.36,.66,1.01,1.25],[0,.12,.48,.84,1.09])
  legacy(aid,lambda ob,f:ob.name.startswith('Book_'));auxiliary=['existing displayed books retained; all rack structure is Hyper3D']
 elif aid=='P_gondola':
  components=['HFF08_bread_rack4']
  for yaw,z,prefix in [(0,.155,'Front'),(180,-.155,'Rear')]:
   source=reshape(single(components[0]),[1.07,1.51,.62],[1.84,1.6,.31],[0,.28,.62,.95,1.27,1.51],[0,.14,.48,.82,1.16,1.6]);place(source,(0,0,z),yaw,prefix=prefix)
 else:raise ValueError(aid)
 bpy.context.view_layer.update();objects=[o for o in bpy.context.scene.objects if o.type=='MESH'];count=tris(objects)
 # Repeated chairs share their actual source meshes and atlas image. Exporting
 # repeated mesh buffers inflates the package; image bindings are also deduplicated.
 image_cache={};image_merges=0
 for material in bpy.data.materials:
  if not material.use_nodes:continue
  for node in material.node_tree.nodes:
   if node.type!='TEX_IMAGE' or not node.image:continue
   image=node.image;pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels)
   key=(tuple(image.size),image.colorspace_settings.name,hashlib.sha256(pixels.tobytes()).hexdigest())
   if key in image_cache:
    if node.image!=image_cache[key]:image_merges+=1
    node.image=image_cache[key]
   else:image_cache[key]=image
 bpy.ops.export_scene.gltf(filepath=str(OUT/(aid+'.glb')),export_format='GLB',export_yup=True,export_apply=True,export_animations=False)
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(aid+'.blend')))
 report=dict(asset=aid,components=[dict(asset=id,prepared_sha256=sha(RAW/'ready'/(id+'.glb')),generation_id=json.loads((RAW/'ready'/(id+'.preparation.json')).read_text())['generation_id']) for id in components],auxiliary=auxiliary,assembled_sha256=sha(OUT/(aid+'.glb')),triangles=count,real_mesh_parts=[o.name for o in objects],face_partition_preserves_real_source_triangles=True,invisible_support_geometry=False,game_installed=False,native_accepted=False)
 report['duplicate_atlas_image_bindings_merged']=image_merges
 (OUT/(aid+'.assembly.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('ASSEMBLED',aid,count,flush=True)
if __name__=='__main__':
 ids=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(SCOPE)+['P_cafe_table','P_community_table','P_reading_chair','I04_shop_counter','I05_bread_shelf','W17_display_shelf','I02_cake_showcase','P_coffee_station','A12_bench','J03_dining_set','J07_kotatsu','P_low_bookcase','P_gondola']
 for aid in ids:assemble(aid)

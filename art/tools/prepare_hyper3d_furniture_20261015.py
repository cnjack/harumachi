"""Fit actual generated timber geometry and supports without rebuilding furniture.

Blender --python-exit-code 1 -P this.py -- ID [ID...]
No game writes. Glass case and espresso require their dedicated local repairs.
"""
from pathlib import Path
import sys,json,hashlib
import bpy,numpy as np
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from level_util import support_plane,level_matrix,squareness
from hyper3d_furniture_sources_20261015 import source_record
ROOT=Path(__file__).resolve().parents[2];RAW=ROOT/'art/models/raw/hyper3d_furniture_20261015';OUT=RAW/'ready';OUT.mkdir(parents=True,exist_ok=True)
SCOPE={r['id']:r for r in json.loads((ROOT/'art/manifests/hyper3d_furniture_20261015.json').read_text())['assets']}
SUPPORTS={
 'HFF01_cafe_chair':dict(seat=.48), 'HFF02_round_table':dict(top=.76),
 'HFF03_rect_table':dict(top=.75), 'HFF04_low_table':dict(top=.43),
 'HFF05_utility_stand':dict(top=.84,levels=[.2225,.84],old_levels=[.275,.82]),
 'HFF06_indoor_bench':dict(top=.43), 'HFF07_sage_counter':dict(top=.87),
 'HFF08_bread_rack4':dict(levels=[.28,.62,.95,1.27],old_levels=[.222,.588,.95,1.287]),
 'HFF09_bread_rack3':dict(levels=[.36,.66,1.01],old_levels=[.218,.568,.920]),
 'HFF10_wall_shelf':dict(levels=[.25,.70],old_levels=[.265,.595],fit_height=.95),
 'HFF12_reading_armchair':dict(seat=.48), 'HFF14_outdoor_bench':dict(seat=.43)
}
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def tree(model):return BVHTree.FromPolygons([v.co for v in model.data.vertices],[list(p.vertices) for p in model.data.polygons],all_triangles=False)
def height(model,x,z,ceiling):
 hit,_,_,_=tree(model).ray_cast(Vector((x,-z,ceiling)),Vector((0,0,-1)),ceiling+1)
 return None if hit is None else hit.z
def main(aid):
 assert aid in SUPPORTS,'Dedicated glass/espresso preparation required'
 row=SCOPE[aid];source,generation=source_record(aid)
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0;bpy.ops.import_scene.gltf(filepath=str(source))
 meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];assert len(meshes)==1;model=meshes[0];matrix=model.matrix_world.copy()
 for v in model.data.vertices:v.co=matrix@v.co
 model.parent=None;model.matrix_world=Matrix.Identity(4)
 for o in list(bpy.context.scene.objects):
  if o!=model:bpy.data.objects.remove(o,do_unlink=True)
 original_triangles=sum(len(p.vertices)-2 for p in model.data.polygons)
 original_uv=np.array([tuple(loop.uv) for loop in model.data.uv_layers.active.data]);uv_sha=hashlib.sha256(original_uv.tobytes()).hexdigest()
 before=np.array([v.co[:] for v in model.data.vertices]);normal,tilt,_,_=support_plane(before)
 if aid!='HFF10_wall_shelf':
  rotation=level_matrix(normal)
  for v in model.data.vertices:v.co=rotation@v.co
 yaw_correction=0.
 if aid in ['HFF01_cafe_chair','HFF12_reading_armchair']:
  angle,fill=squareness(np.array([v.co[:] for v in model.data.vertices]))
  if fill>.90:
   yaw_correction=-angle;rotation=Matrix.Rotation(float(np.radians(yaw_correction)),3,'Z')
   for v in model.data.vertices:v.co=rotation@v.co
 xyz=np.array([v.co[:] for v in model.data.vertices]);lo=xyz.min(0);hi=xyz.max(0);size=row['nominal_size_m_xyz'];contract=SUPPORTS[aid];target=np.array([size[0],size[2],contract.get('fit_height',size[1])]);scale=target/(hi-lo)
 for v in model.data.vertices:v.co=Vector((np.array(v.co)-lo)*scale-np.array([target[0]/2,target[1]/2,0]))
 model.data.update();warps=[]
 if 'seat' in contract:
  found=height(model,0,0,contract['seat']+.13);assert found is not None
  old=[0.,found,target[2]];new=[0.,contract['seat'],target[2]];assert old[1]<old[2]
  for v in model.data.vertices:v.co.z=float(np.interp(v.co.z,old,new))
  warps.append(dict(kind='actual_center_seat_height',before=old,after=new))
 if aid in ['HFF01_cafe_chair','HFF12_reading_armchair']:
  model.data.update();probe=tree(model);skins=[]
  for origin,direction in [(-.4,1),(.4,-1)]:
   depths=[]
   for x in [-.15,0,.15]:
    hit,_,_,_=probe.ray_cast(Vector((x,origin,.69)),Vector((0,direction,0)),1.)
    assert hit is not None,'Both backrest skins must have real geometry at all three probes'
    depths.append(-hit.y)
   skins.append(dict(depths=depths,center=depths[1],slope=(depths[2]-depths[0])/.30,sag=(depths[0]+depths[2])*.5-depths[1]))
  for v in model.data.vertices:
   vertical=max(0.,min(1.,(v.co.z-.53)/.09));vertical=vertical*vertical*(3-2*vertical)
   back=max(0.,min(1.,(v.co.y-.03)/.07));back=back*back*(3-2*back)
   q2=(v.co.x/.15)**2
   front,rear=skins
   front_depth=front['center']+front['slope']*v.co.x+front['sag']*q2
   rear_depth=rear['center']+rear['slope']*v.co.x+rear['sag']*q2
   fraction=max(0.,min(1.,(-v.co.y-rear_depth)/max(front_depth-rear_depth,.001)))
   front_delta=(.014-front['sag'])*q2-front['slope']*v.co.x
   rear_delta=(.014-rear['sag'])*q2-rear['slope']*v.co.x
   correction=(rear_delta+(front_delta-rear_delta)*fraction)*vertical*back
   v.co.y-=correction
  warps.append(dict(kind='real_backrest_wrap_and_twist_correction_both_skins',probe_height=.69,source_skins=skins,target_signed_sag=.014))
 if 'old_levels' in contract:
  old=[0.,*contract['old_levels'],size[1]];new=[0.,*contract['levels'],target[2]]
  # Wall-shelf source diagnostic heights used the nominal .72m. Its existing
  # mounting span is .95m; map those measured heights in the new scale.
  if aid=='HFF10_wall_shelf':old=[v*target[2]/size[1] for v in old]
  assert all(old[i]<old[i+1] for i in range(len(old)-1))
  for v in model.data.vertices:v.co.z=float(np.interp(v.co.z,old,new))
  warps.append(dict(kind='actual_generated_shelf_level_fit',before=old,after=new))
 model.data.update();flattened=0;floor_vertices=0
 # Close centimetre-wide generated plank gaps to fine real joinery seams.
 # This is a monotone fit of the original board edges, not a replacement top.
 if aid in ['HFF03_rect_table','HFF05_utility_stand']:
  gaps={'HFF03_rect_table':[[-.318,-.298],[-.121,-.106],[.217,.238]],'HFF05_utility_stand':[[-.091,-.077],[.105,.123]]}[aid]
  old_knots=[-target[1]/2];new_knots=[-target[1]/2]
  for start,end in gaps:
   center=(start+end)/2;old_knots.extend([start,end]);new_knots.extend([center-.0001,center+.0001])
  old_knots.append(target[1]/2);new_knots.append(target[1]/2)
  top=contract['top']
  for v in model.data.vertices:
   weight=max(0.,min(1.,(v.co.z-(top-.12))/.025))
   depth=-v.co.y;fitted=float(np.interp(depth,old_knots,new_knots));v.co.y=-(depth+(fitted-depth)*weight)
  model.data.update();warps.append(dict(kind='original_plank_edges_fitted_to_fine_joinery',before_depth_knots=old_knots,after_depth_knots=new_knots,seam_width_m=.0002))
 support_before=np.array([v.co[:] for v in model.data.vertices])
 levels=contract.get('levels',[contract.get('top',contract.get('seat'))])
 # Generated shelf tops can undulate independently of their vertex normals.
 # Select real upward polygon corners, then flatten only the usable patch.
 # This preserves underfaces, rolled edges, UV seams and plank gaps.
 support_vertices={level:set() for level in levels}
 if 'seat' not in contract:
  for face in model.data.polygons:
   if face.normal.z<.45:continue
   level=min(levels,key=lambda y:abs(face.center.z-y))
   if abs(face.center.z-level)>.065:continue
   for index in face.vertices:
    vertex=model.data.vertices[index]
    if abs(vertex.co.z-level)<.075 and abs(vertex.co.x)<target[0]*.465 and abs(vertex.co.y)<target[1]*.465:
     support_vertices[level].add(index)
  for level,indices in support_vertices.items():
   for index in indices:model.data.vertices[index].co.z=level
   flattened+=len(indices)
  model.data.update()
 for vertex in model.data.vertices:
  if aid!='HFF10_wall_shelf' and vertex.co.z<.005:vertex.co.z=0;floor_vertices+=1
  if vertex.normal.z<.55:continue
  for level in levels:
   # Keep the rolled outer edges; only the actual central support vertices
   # are corrected. The generated faces/UV and structural gaps remain.
   inner_x=min(target[0]*.445,.115) if 'seat' in contract else target[0]*.445
   inner_z=min(target[1]*.445,.120) if 'seat' in contract else target[1]*.445
   if abs(vertex.co.z-level)<(.055 if 'top' in contract else .025) and abs(vertex.co.x)<inner_x and abs(vertex.co.y)<inner_z:
    vertex.co.z=level;flattened+=1;break
 if aid=='HFF10_wall_shelf':
  model.data.update();back_vertices=set()
  for face in model.data.polygons:
   if face.normal.y>.65 and face.center.y>.08:back_vertices.update(face.vertices)
  for index in back_vertices:
   if model.data.vertices[index].co.y>.08:model.data.vertices[index].co.y=target[1]/2
  warps.append(dict(kind='flatten_real_rear_mounting_faces',back_plane_blender_y=float(target[1]/2),vertices=len(back_vertices)))
 # glTF duplicates geometry vertices across UV seams. Moving only the upward
 # copy tears the physical board at that seam. Propagate each correction to
 # coincident copies without welding or changing any original UV loop.
 twins={}
 for index,point in enumerate(support_before):twins.setdefault(tuple(np.round(point,6)),[]).append(index)
 seam_corrections=0
 for indices in twins.values():
  for axis in range(3):
   changed=[i for i in indices if abs(model.data.vertices[i].co[axis]-support_before[i,axis])>1e-7]
   if not changed:continue
   destination=model.data.vertices[changed[0]].co[axis]
   for i in indices:
    if abs(model.data.vertices[i].co[axis]-destination)>1e-7:seam_corrections+=1
    model.data.vertices[i].co[axis]=destination
 model.data.update();model.name=aid+'_Hyper3D_SourceGeometry'
 for material in model.data.materials:
  material.name='Hyper3D_OriginalAtlas_'+aid
  if not material.use_nodes:continue
  bs=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
  for key,value in [('Metallic',0.),('Roughness',.65),('Normal',None),('Specular IOR Level',.35)]:
   for link in list(bs.inputs[key].links):material.node_tree.links.remove(link)
   if value is not None:bs.inputs[key].default_value=value
 after_uv=np.array([tuple(loop.uv) for loop in model.data.uv_layers.active.data]);assert hashlib.sha256(after_uv.tobytes()).hexdigest()==uv_sha
 triangles=sum(len(p.vertices)-2 for p in model.data.polygons);assert triangles==original_triangles
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(aid+'.blend')))
 bpy.ops.export_scene.gltf(filepath=str(OUT/(aid+'.glb')),export_format='GLB',export_yup=True,export_apply=True,export_animations=False,export_image_format='AUTO')
 probes=[]
 for level in levels:
  for x in [-target[0]*.30,0,target[0]*.30]:
   for z in [-target[1]*.25,0,target[1]*.25]:
    found=height(model,x,z,level+.012);probes.append(dict(target_y=level,x=float(x),z=float(z),actual_y=found))
 report=dict(asset=aid,generation_id=generation['generation_id'],source_sha256=sha(source),prepared_sha256=sha(OUT/(aid+'.glb')),provider='Hyper3D CLI Gen-2.5-High; original generated geometry fitted locally',original_triangles=original_triangles,prepared_triangles=triangles,topology_preserved=True,original_uv_coordinates_unchanged=True,uv_sha256=uv_sha,affine_scale_blender=scale.tolist(),level_correction_degrees=tilt if aid!='HFF10_wall_shelf' else 0,support_warps=warps,flattened_existing_support_vertices=flattened,coincident_uv_seam_vertices_corrected=seam_corrections,leveled_existing_foot_vertices=floor_vertices,support_probes=probes,nominal_size_godot=[float(target[0]),float(target[2]),float(target[1])],game_installed=False,native_accepted=False,required_next='Review prepared original geometry/support probes, decompose only real source components for legacy node/seat contracts, then integrate and perform actual gameplay/native package acceptance.')
 report['yaw_correction_degrees']=yaw_correction
 (OUT/(aid+'.preparation.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print('PREPARED_HYPER3D',aid,'triangles',triangles,'support vertices',flattened,flush=True)

if __name__=='__main__':
 ids=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(SUPPORTS)
 for aid in ids:main(aid)

"""Extract selected local Blender assets into self-contained, matte GLBs.
Run with Blender --disable-autoexec -P this.py -- --source /path/to/asset.
Original files are read-only. No course assets or Blender shader graphs are copied.
"""
import argparse, hashlib, json, pathlib, sys
import bpy
import numpy as np
from mathutils import Vector, Matrix

ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--source',type=pathlib.Path,required=True)
args=p.parse_args(sys.argv[sys.argv.index('--')+1:]);source=args.source.resolve()
out=ROOT/'art/models/raw/reviewed_library_20261012';out.mkdir(parents=True,exist_ok=True)
records=[];texture_cache={}
GRASS=[('V06_fine_grass','Basic_Grass_11',.38),('V07_grass_card','Basic_Grass_Card_03',.48),('V08_blade_rosette','Detailed_Blades_13',.40),('V09_fern_cluster','Detailed_Fern_01',.58),('V10_leaf_shrub','Detailed_Varied_06',.65),('V11_fallen_leaf','Basic_Leaf_Flat_01',.025),('V12_tulip','Basic_Tulip_01',.52),('V13_pampas','Detailed_Pampas_01',.9),('V14_broad_grass','Detailed_Tall_Grass_01',.42),('V15_wheat_stem','Detailed_Wheat_A_01',.75)]

def load(path):
 bpy.ops.wm.open_mainfile(filepath=str(path),load_ui=False,use_scripts=False)
 texture_cache.clear()

def matte(name,colour):
 m=bpy.data.materials.new(name);m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*colour,1);bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0
 return m

def plant_mat(original,aid,index):
 image_nodes=[n for n in original.node_tree.nodes if n.type=='TEX_IMAGE' and n.image]
 colour=(.29,.49,.10)
 if aid=='V11_fallen_leaf':colour=(.43,.30,.095)
 if aid=='V12_tulip':colour=(.65,.13,.23) if index==0 else (.20,.40,.07)
 if aid in ['V13_pampas','V15_wheat_stem']:colour=(.72,.65,.36) if index==0 else (.27,.42,.10)
 m=matte(aid+'_leaf_%d'%index,colour)
 if not image_nodes:return m
 original_image=image_nodes[0].image;key=original_image.name+'_'+aid+'_'+str(index)
 if key not in texture_cache:
  resized=original_image.copy();factor=min(1,1024/max(resized.size));resized.scale(round(resized.size[0]*factor),round(resized.size[1]*factor));w,h=resized.size
  pixels=np.empty(w*h*4,dtype=np.float32);resized.pixels.foreach_get(pixels);pixels=pixels.reshape(-1,4)
  mask=np.clip(pixels[:,:3].mean(axis=1),0,1)
  pixels[:,:3]=colour;pixels[:,3]=mask
  image=bpy.data.images.new(key,width=w,height=h,alpha=True);image.alpha_mode='STRAIGHT';image.pixels.foreach_set(pixels.reshape(-1));image.file_format='PNG';image.filepath_raw=str(out/(key+'.png'));image.save();image.pack();texture_cache[key]=image
 im=texture_cache[key];nt=m.node_tree;tn=nt.nodes.new('ShaderNodeTexImage');tn.image=im;bs=nt.nodes.get('Principled BSDF');nt.links.new(tn.outputs['Alpha'],bs.inputs['Alpha']);nt.links.new(tn.outputs['Color'],bs.inputs['Base Color']);m.surface_render_method='DITHERED';m.use_backface_culling=False

 return m

def export(aid,objects,height,path,plant=False):
 scene=bpy.data.scenes.new('Export_'+aid);bpy.context.window.scene=scene;copies=[]
 for original in objects:
  if original.type!='MESH':continue
  obj=bpy.data.objects.new(original.name,original.data.copy());scene.collection.objects.link(obj);obj.matrix_world=original.matrix_world.copy();obj.data.transform(obj.matrix_world);obj.matrix_world=Matrix.Identity(4);copies.append(obj)
  # Keep the original UVMap only. UVRandom/UVAniso refer to Blender-only shaders.
  for uv in list(obj.data.uv_layers):
   if uv.name!='UVMap' and plant:obj.data.uv_layers.remove(uv)
  mats=list(original.data.materials);obj.data.materials.clear()
  for i,m in enumerate(mats):
   if plant:new=plant_mat(m,aid,i)
   else:
    c=(.59,.45,.27) if 'stool' in aid or 'carton' in aid else ((.43,.53,.57) if 'bucket' in aid else (.43,.48,.45))
    if 'stool' in aid and any(w in m.name.lower() for w in ['metal','black']):c=(.19,.24,.26)
    new=matte(aid+'_'+str(i),c)
   obj.data.materials.append(new)
  if not mats:obj.data.materials.append(matte(aid,(.4,.48,.4)))
 points=[v.co for ob in copies for v in ob.data.vertices];mn=Vector([min(v[a] for v in points) for a in range(3)]);mx=Vector([max(v[a] for v in points) for a in range(3)]);scale=height/max(.001,mx.z-mn.z);offset=Vector(((mn.x+mx.x)/2,(mn.y+mx.y)/2,mn.z))
 for ob in copies:
  for v in ob.data.vertices:v.co=(v.co-offset)*scale
  for face in ob.data.polygons:face.use_smooth=plant
  ob.select_set(True)
 bpy.context.view_layer.objects.active=copies[0]
 dest=out/(aid+'.glb');bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',export_yup=True,export_apply=False,export_animations=False,export_image_format='AUTO',use_selection=True,use_active_scene=True)
 records.append({'id':aid,'source':str(path.relative_to(source)),'objects':[o.name for o in objects],'source_sha256':hashlib.file_digest(path.open('rb'),'sha256').hexdigest(),'height_m':height,'base_triangles':sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in copies),'file':str(dest.relative_to(ROOT)),'sha256':hashlib.file_digest(dest.open('rb'),'sha256').hexdigest(),'adaptation':'original mesh and UV; independent matte colours; alpha from supplied monochrome masks' if plant else 'original mesh, shared metre scale and new flat matte materials'})
 print('EXTRACTED',aid,flush=True)

path=source/'CGC_Painterly_Grass_1.0.blend';load(path)
for aid,name,height in GRASS:export(aid,[bpy.data.objects[name]],height,path,True)
path=source/'YNA. BU S2.blend';load(path)
for aid,name,height in [('P_library_carton','Cardboardbox',.36),('P_library_bucket','Painting Bucket',.32),('P_library_stool','Plywood Stool',.58)]:export(aid,list(bpy.data.collections[name].all_objects),height,path)
path=source/'CGC_Painterly_Grass_1.0Demo/DemoB_ScenesD_3.3/Adventure_Fields_Demo.blend';load(path)
for i,name in enumerate(['Pebble','Pebble.001','Pebble.002']):export('V%02d_path_pebble'%(16+i),[bpy.data.objects[name]],.16+i*.03,path)
path=source/'CGC_Painterly_Grass_1.0Demo/山谷场景演示/Cliff_Assets/Basic_Cliff_Asset_3.3.blend';load(path);export('V19_distant_cliff',[bpy.data.objects['Cliff_A_v02_Ultra_Low_Poly']],10,path)
manifest=ROOT/'art/manifests/models_reviewed_library.json';manifest.write_text(json.dumps({'date':'2026-10-12','source_license':'User confirmed game commercial use and public derivative source redistribution authorization on 2026-10-12','assets':records},ensure_ascii=False,indent=2)+'\n')
specpath=ROOT/'art/models/game_assets.json';spec=json.loads(specpath.read_text())
for row in records:spec['assets'][row['id']]={'src':'raw/reviewed_library_20261012/'+row['id']+'.glb','preserve_parts':True,'preserve_origin':True,'level':False,'tex':1024,'image_format':'AUTO','provider':'User-supplied CGC / YNA Blender mesh; see models_reviewed_library.json','note':row['adaptation']}
specpath.write_text(json.dumps(spec,ensure_ascii=False,indent=2)+'\n')

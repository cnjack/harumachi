"""Create a practical door module from the corrected provider-created joinery.

Blender -b --factory-startup -P ... -- CORRECTED_GLB OUT_DIR
Retains source UV/albedo; further reduction and neutral timber on cut reveals.
"""
import bpy,bmesh,json,sys
from pathlib import Path
import numpy as np
source,out=map(Path,sys.argv[sys.argv.index('--')+1:]);out.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
if len(objects)!=1:raise RuntimeError('Expected one corrected mesh')
ob=objects[0];bpy.context.view_layer.objects.active=ob;ob.select_set(True);mesh=ob.data
bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.remove_doubles(bm,verts=bm.verts[:],dist=1e-7);bm.to_mesh(mesh);bm.free()
source_faces=sum(len(p.vertices)-2 for p in mesh.polygons)
modifier=ob.modifiers.new('Practical_module_budget','DECIMATE');modifier.ratio=.25;bpy.ops.object.modifier_apply(modifier=modifier.name)
mesh=ob.data;uv=mesh.uv_layers.active.data
material=mesh.materials[0];bs=material.node_tree.nodes.get('Principled BSDF');image=next(link.from_node.image for link in bs.inputs['Base Color'].links if link.from_node.type=='TEX_IMAGE')
w,h=image.size;pixels=np.empty(w*h*4,dtype=np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape(h,w,4)
wood=bpy.data.materials.new('Cut_timber_reveal');wood.use_nodes=True;ws=wood.node_tree.nodes.get('Principled BSDF');ws.inputs['Base Color'].default_value=(.33,.17,.068,1);ws.inputs['Metallic'].default_value=0;ws.inputs['Roughness'].default_value=1;ws.inputs['Specular IOR Level'].default_value=0
mesh.materials.append(wood);changed=0
for poly in mesh.polygons:
    q=sum((uv[i].uv for i in poly.loop_indices),start=uv[poly.loop_indices[0]].uv*0)/len(poly.loop_indices)
    r,g,b=pixels[min(h-1,int((q.y%1)*h)),min(w-1,int((q.x%1)*w)),:3]
    if b>r*1.22 and g>r*1.10 and b>g*.98 and max(r,g,b)<.52:
        poly.material_index=len(mesh.materials)-1;changed+=1
for image in bpy.data.images:
    if image.size[0]>0:image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str((out/'door_game.blend').resolve()))
bpy.ops.export_scene.gltf(filepath=str((out/'door_game.glb').resolve()),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_image_format='JPEG',export_jpeg_quality=95)
report={'source':str(source),'triangles_before':source_faces,'triangles_after':sum(len(p.vertices)-2 for p in ob.data.polygons),'cut_reveal_faces_timber_material':changed,'changes':'provider joinery retained; geometry reduced; only blue residual reveal faces assigned neutral timber; no raster edits'}
(out/'optimization.json').write_text(json.dumps(report,indent=2)+'\n');print('DOOR_GAME',json.dumps(report),flush=True)

"""Local, UV-preserving cleanup of a reviewed Hyper3D candidate; original stays intact.

Blender -b --factory-startup -P art/tools/prepare_model_diversity.py -- ID CANDIDATE
Outputs raw/diversity_20261013/ready/ID.glb for the normal game_export pipeline.
"""
import hashlib
import json
from pathlib import Path
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
aid,candidate=sys.argv[sys.argv.index('--')+1:]
scope=json.loads((ROOT/'art/manifests/model_diversity_20261013.json').read_text())
row=next(r for r in scope['assets'] if r['id']==aid)
raw=ROOT/'art/models/raw/diversity_20261013'/aid/candidate/'model.glb'
out=ROOT/'art/models/raw/diversity_20261013/ready';out.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(raw))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
for ob in bpy.context.scene.objects:ob.select_set(ob.type=='MESH')
bpy.context.view_layer.objects.active=meshes[0]
if len(meshes)>1:bpy.ops.object.join()
model=bpy.context.view_layer.objects.active;model.parent=None
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
for ob in list(bpy.context.scene.objects):
    if ob!=model:bpy.data.objects.remove(ob,do_unlink=True)
notes=[]


def bounds():
    points=[v.co for v in model.data.vertices]
    return Vector([min(p[k] for p in points) for k in range(3)]),Vector([max(p[k] for p in points) for k in range(3)])


if aid=='D01_wheelbarrow':
    # The provider ignored handle shortening in B. Change only the rear handle
    # segment, retaining tray/wheel/support geometry and the original UVs.
    low,high=bounds();length=high.y-low.y;height=high.z-low.z
    pivot=low.y+length*.63
    desired_length=height*(1.4/.65)
    rear_length=high.y-pivot
    ratio=max(.2,min(1.,(desired_length-(pivot-low.y))/rear_length))
    changed=0
    for vertex in model.data.vertices:
        if vertex.co.y>pivot:
            vertex.co.y=pivot+(vertex.co.y-pivot)*ratio;changed+=1
    model.data.update()
    notes.append(dict(kind='local_rear_handle_shortening',pivot_y=pivot,ratio=ratio,vertices=changed,
                      target_whole_length_to_height=1.4/.65,retained='tray, wheel, support feet and UV mapping'))

if aid=='D03_veg_crates':
    # Keep the Hyper3D produce as actual textured geometry. Replace visibly
    # wavy outer frame strips with straight physical timber; no texture trick.
    low,high=bounds();dims=high-low;centre=(low+high)*.5
    height=dims.z/3
    wall=min(dims.x,dims.y)*.052
    bm=bmesh.new();bm.from_mesh(model.data)
    # Remove the old timber itself, including inward-warped strips that would
    # otherwise close the new slat openings. Source produce occupies green or
    # red/orange atlas regions; sample the original UVs without editing pixels.
    atlas=next(node.image for mat in model.data.materials if mat and mat.use_nodes
               for node in mat.node_tree.nodes if node.type=='TEX_IMAGE' and node.image
               and 'diffuse' in node.image.name.lower())
    pixels=np.empty(len(atlas.pixels),dtype=np.float32);atlas.pixels.foreach_get(pixels)
    pixels=pixels.reshape(atlas.size[1],atlas.size[0],4)
    uv_layer=bm.loops.layers.uv.active
    remove=[]
    for face in bm.faces:
        uv=sum((loop[uv_layer].uv for loop in face.loops),Vector((0,0)))/len(face.loops)
        xx=min(atlas.size[0]-1,max(0,int(uv.x*atlas.size[0])))
        yy=min(atlas.size[1]-1,max(0,int(uv.y*atlas.size[1])))
        red,green,blue=pixels[yy,xx,:3]
        if not (green>red*1.05 or red>green*1.8):remove.append(face)
    bmesh.ops.delete(bm,geom=remove,context='FACES')
    removed_timber_faces=len(remove)
    for axis in [0,1]:
        for sign in [-1,1]:
            point=centre.copy();point[axis]+=sign*(dims[axis]/2-wall*1.5)
            normal=Vector((0,0,0));normal[axis]=sign
            bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=point,
                                   plane_no=normal,clear_outer=True,dist=1e-6)
    bm.to_mesh(model.data);bm.free()
    wood=bpy.data.materials.new('Diversity_clean_cedar');wood.use_nodes=True
    bs=wood.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(.58,.37,.20,1)
    bs.inputs['Roughness'].default_value=1.;bs.inputs['Specular IOR Level'].default_value=0.
    parts=[model]
    def timber(name,size,at):
        bpy.ops.mesh.primitive_cube_add(size=1,location=at)
        ob=bpy.context.object;ob.name=name;ob.dimensions=size
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        bevel=ob.modifiers.new('Small_real_edge_bevel','BEVEL');bevel.width=wall*.10;bevel.segments=1
        bpy.ops.object.modifier_apply(modifier=bevel.name)
        ob.data.materials.append(wood);parts.append(ob)
    for layer in range(3):
        z0=low.z+layer*height
        # Real bottom, four straight corner posts and three long slats per side.
        timber(f'Crate_{layer}_bottom',(dims.x-wall,dims.y-wall,wall),(centre.x,centre.y,z0+wall/2))
        for xsign in [-1,1]:
            for ysign in [-1,1]:
                timber(f'Crate_{layer}_corner_{xsign}_{ysign}',(wall,wall,height*.98),
                       (centre.x+xsign*(dims.x-wall)/2,centre.y+ysign*(dims.y-wall)/2,z0+height*.49))
        gap=height*.14;slat=(height*.94-2*gap)/3
        for band in range(3):
            zz=z0+height*.03+slat/2+band*(slat+gap)
            for sign in [-1,1]:
                timber(f'Crate_{layer}_rail_{band}_{sign}',(dims.x-2*wall,wall,slat),
                       (centre.x,centre.y+sign*(dims.y-wall)/2,zz))
                if band==2:
                    # A real hand opening: two short cheeks and a top lip.
                    hole_width=dims.y*.30;side_span=(dims.y-2*wall-hole_width)/2
                    for side in [-1,1]:
                        timber(f'Crate_{layer}_handle_cheek_{sign}_{side}',(wall,side_span,slat),
                               (centre.x+sign*(dims.x-wall)/2,centre.y+side*(hole_width+side_span)/2,zz))
                    timber(f'Crate_{layer}_handle_lip_{sign}',(wall,hole_width,slat*.26),
                           (centre.x+sign*(dims.x-wall)/2,centre.y,zz+slat*.37))
                else:
                    timber(f'Crate_{layer}_end_{band}_{sign}',(wall,dims.y-2*wall,slat),
                           (centre.x+sign*(dims.x-wall)/2,centre.y,zz))
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts:ob.select_set(True)
    bpy.context.view_layer.objects.active=model;bpy.ops.object.join()
    notes.append(dict(kind='straight_container_joinery',retained='Hyper3D tomato/cucumber/carrot geometry and original UVs',
                      added='three precise cedar frames with actual hand holes, separate slats, bottoms and bevels',
                      removed_timber_faces=removed_timber_faces,
                      removed='outer strips whose slat edges visibly waved in both provider candidates'))

for mat in bpy.data.materials:
    if not mat.use_nodes:continue
    bs=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if not bs:continue
    for name,value in [('Normal',None),('Metallic',0.),('Roughness',1.),('Specular IOR Level',0.)]:
        for link in list(bs.inputs[name].links):mat.node_tree.links.remove(link)
        if value is not None:bs.inputs[name].default_value=value
model.name=aid
sys.path.insert(0,str(Path(__file__).resolve().parent))
from diversity_prop_repairs import repair
prop_note=repair(model,aid)
if prop_note:notes.append(prop_note)
from diversity_radial_plants import restore_depth,creeping_vine
radial_note=restore_depth(model,aid)
if radial_note:notes.append(radial_note)
vine_note=creeping_vine(model,aid)
if vine_note:notes.append(vine_note)
from diversity_tree_foliage import complete_crown
export_objects,canopy_note=complete_crown(model,aid,row,ROOT)
if canopy_note:notes.append(canopy_note)
bpy.ops.object.select_all(action='DESELECT')
for ob in export_objects:ob.select_set(True)
bpy.context.view_layer.objects.active=model
target=out/(aid+'.glb')
bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,use_active_scene=True,
                         export_apply=True,export_yup=True,export_animations=False,export_extras=False)
report=dict(asset=aid,candidate=candidate,provider='Hyper3D CLI Gen-2.5-High',source=str(raw.relative_to(ROOT)),
            source_sha256=hashlib.sha256(raw.read_bytes()).hexdigest(),prepared=str(target.relative_to(ROOT)),
            prepared_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),local_geometry_changes=notes,
            triangle_budget=row['triangle_budget'],preserve_parts=bool(canopy_note),final_game_export_pending=True)
(out/(aid+'.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('PREPARED',json.dumps(report),flush=True)

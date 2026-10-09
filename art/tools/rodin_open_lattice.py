"""Open the blue infill panes while retaining provider-created timber joinery.

Blender -b --factory-startup -P ... -- RAW_GLB OUT_DIR
UV/albedo sampling only identifies pane regions; no raster is edited. Hidden
pane bodies are cut with fitted straight apertures. Original raw stays intact.
"""
import bpy,bmesh,json,sys,math
from pathlib import Path
from collections import deque
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
source,out=map(Path,sys.argv[sys.argv.index('--')+1:]);out.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
if len(meshes)!=1:raise RuntimeError('Expected one provider mesh')
ob=meshes[0];bpy.context.view_layer.objects.active=ob;ob.select_set(True)
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
mesh=ob.data;mesh.calc_loop_triangles();verts=[v.co.copy() for v in mesh.vertices];triangles=list(mesh.loop_triangles)
indices=[tuple(t.vertices) for t in triangles];tree=BVHTree.FromPolygons(verts,indices,all_triangles=True)
uv=mesh.uv_layers.active.data
low=Vector([min(p[a] for p in verts) for a in range(3)]);high=Vector([max(p[a] for p in verts) for a in range(3)]);size=high-low
thin=0 if size.x<size.y else 1;across=1-thin;images={}
for index,material in enumerate(mesh.materials):
    if not material or not material.use_nodes:continue
    bs=material.node_tree.nodes.get('Principled BSDF')
    image=next((link.from_node.image for link in bs.inputs['Base Color'].links if link.from_node.type=='TEX_IMAGE'),None)
    if image is None:raise RuntimeError('Base colour must be an embedded image')
    w,h=image.size;pixels=np.empty(w*h*4,dtype=np.float32);image.pixels.foreach_get(pixels);images[index]=(pixels.reshape(h,w,4),w,h)

def blue_pane(hit,triangle_index):
    tri=triangles[triangle_index];a,b,c=[verts[i] for i in tri.vertices];v0=b-a;v1=c-a;v2=hit-a
    d00=v0.dot(v0);d01=v0.dot(v1);d11=v1.dot(v1);d20=v2.dot(v0);d21=v2.dot(v1);den=d00*d11-d01*d01
    if abs(den)<1e-16:return False
    u=(d11*d20-d01*d21)/den;v=(d00*d21-d01*d20)/den
    coords=[uv[i].uv for i in tri.loops];q=coords[0]+(coords[1]-coords[0])*u+(coords[2]-coords[0])*v
    pixels,w,h=images[tri.material_index];colour=pixels[min(h-1,int((q.y%1)*h)),min(w-1,int((q.x%1)*w)),:3]
    r,g,bv=map(float,colour)
    return bv>r*1.22 and g>r*1.10 and bv>g*.98 and max(r,g,bv)<.52

n=240;m=240;u0=low[across]+size[across]*.07;u1=high[across]-size[across]*.07;z0=low.z+size.z*.29;z1=low.z+size.z*.91
mask=np.zeros((m,n),dtype=bool)
direction=Vector((0,0,0));direction[thin]=1
for j in range(m):
    for i in range(n):
        q=Vector((0,0,0));q[across]=u0+(u1-u0)*(i+.5)/n;q.z=z0+(z1-z0)*(j+.5)/m;q[thin]=low[thin]-.2
        hit,normal,index,distance=tree.ray_cast(q,direction,size[thin]+.5)
        if hit is not None and blue_pane(hit,index):mask[j,i]=True
seen=np.zeros_like(mask);regions=[]
for j in range(m):
    for i in range(n):
        if not mask[j,i] or seen[j,i]:continue
        queue=deque([(j,i)]);seen[j,i]=True;cells=[]
        while queue:
            yy,xx=queue.popleft();cells.append((yy,xx))
            for y,x in [(yy-1,xx),(yy+1,xx),(yy,xx-1),(yy,xx+1)]:
                if 0<=y<m and 0<=x<n and mask[y,x] and not seen[y,x]:seen[y,x]=True;queue.append((y,x))
        if len(cells)<80:continue
        rows=[p[0] for p in cells];cols=[p[1] for p in cells]
        a=u0+(min(cols)+.5)/n*(u1-u0);b=u0+(max(cols)+.5)/n*(u1-u0);bottom=z0+(min(rows)+.5)/m*(z1-z0);top=z0+(max(rows)+.5)/m*(z1-z0)
        if b-a<.025 or top-bottom<.025:continue
        regions.append((a+.0015,b-.0015,bottom+.0015,top-.0015))
if not 25<=len(regions)<=48:raise RuntimeError('Unexpected cell count: '+str(len(regions)))
print('PANE_REGIONS',len(regions),flush=True)
# Weld glTF UV-seam duplicates, retaining loop UVs, before geometry reduction.
bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.remove_doubles(bm,verts=bm.verts[:],dist=1e-7);bm.to_mesh(mesh);bm.free()
modifier=ob.modifiers.new('Game_detail_budget','DECIMATE');modifier.ratio=.08;bpy.ops.object.modifier_apply(modifier=modifier.name)
cutters=bpy.data.collections.new('Pane_cutters');bpy.context.scene.collection.children.link(cutters)
for i,(a,b,bottom,top) in enumerate(regions):
    centre=Vector((0,0,0));centre[across]=(a+b)/2;centre[thin]=(low[thin]+high[thin])/2;centre.z=(bottom+top)/2
    dims=Vector((0,0,0));dims[across]=b-a;dims[thin]=size[thin]+.30;dims.z=top-bottom
    bpy.ops.mesh.primitive_cube_add(size=1,location=centre);cube=bpy.context.object;cube.name='Aperture_'+str(i);cube.scale=dims
    for collection in list(cube.users_collection):collection.objects.unlink(cube)
    cutters.objects.link(cube)
bpy.context.view_layer.objects.active=ob
boolean=ob.modifiers.new('Open_actual_lattice','BOOLEAN');boolean.operation='DIFFERENCE';boolean.operand_type='COLLECTION';boolean.collection=cutters;boolean.solver='EXACT'
bpy.ops.object.modifier_apply(modifier=boolean.name)
for cutter in list(cutters.objects):bpy.data.objects.remove(cutter,do_unlink=True)
bpy.data.collections.remove(cutters)
for material in ob.data.materials:
    if not material or not material.use_nodes:continue
    bs=material.node_tree.nodes.get('Principled BSDF')
    for name,value in [('Normal',None),('Metallic',0),('Roughness',1),('Specular IOR Level',0)]:
        for link in list(bs.inputs[name].links):material.node_tree.links.remove(link)
        if value is not None:bs.inputs[name].default_value=value
for image in bpy.data.images:
    if image.size[0]>0:image.pack()
bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
bpy.ops.wm.save_as_mainfile(filepath=str((out/'door_open.blend').resolve()))
bpy.ops.export_scene.gltf(filepath=str((out/'door_open.glb').resolve()),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_image_format='JPEG',export_jpeg_quality=95)
(out/'correction.json').write_text(json.dumps({'source':str(source),'correction':'only blue infill cells removed; original provider joinery, texture and UV retained','source_triangles':len(triangles),'output_triangles':sum(len(p.vertices)-2 for p in ob.data.polygons),'apertures':len(regions),'cell_bounds_native_blender':regions,'uniform_scale_to_2_1m':2.1/size.z,'no_raster_edits':True},indent=2)+'\n')
print('CORRECTED',out/'door_open.glb',flush=True)

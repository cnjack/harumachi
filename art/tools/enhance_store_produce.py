"""Give S01's embedded produce trays a dedicated imagegen atlas and planar UVs.

Blender -b --factory-startup -P art/tools/enhance_store_produce.py
Only material assignment/UV loops change; every world-space triangle is hashed.
"""
import bpy,json,hashlib,struct
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'evidence/architecture_closeup_20261002/before/game/assets/models/S01.glb'
OUT=ROOT/'art/models/raw/S01_produce_closeup_20261002';OUT.mkdir(parents=True,exist_ok=True)

def triangle_hash(objs):
    chunks=[]
    for ob in objs:
        mesh=ob.data;mesh.calc_loop_triangles();matrix=np.array(ob.matrix_world)
        verts=np.array([v.co[:] for v in mesh.vertices]);verts=verts@matrix[:3,:3].T+matrix[:3,3]
        triangles=np.array([t.vertices[:] for t in mesh.loop_triangles]);points=np.round(verts[triangles]*1e5).astype(np.int64)
        for tri in points:
            order=np.lexsort((tri[:,2],tri[:,1],tri[:,0]));chunks.append(tuple(tri[order].reshape(-1)))
    chunks.sort();return hashlib.sha256(np.asarray(chunks,dtype='<i8').tobytes()).hexdigest()

bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(SOURCE))
objs=[o for o in bpy.context.scene.objects if o.type=='MESH'];before=triangle_hash(objs)
atlas=bpy.data.images.load(str(ROOT/'art/references/architecture_closeup_20261002/produce.png'));atlas.pack();atlas_size=list(atlas.size)
material=bpy.data.materials.new('S01_Produce_Closeup');material.use_nodes=True
bs=material.node_tree.nodes['Principled BSDF'];bs.inputs['Roughness'].default_value=1;bs.inputs['Metallic'].default_value=0;bs.inputs['Specular IOR Level'].default_value=0
tx=material.node_tree.nodes.new('ShaderNodeTexImage');tx.image=atlas;material.node_tree.links.new(tx.outputs['Color'],bs.inputs['Base Color'])
counts=[0,0,0];groups=[(-3.13,-1.55,(0,.5,.5,1)),(-1.55,.10,(0,.5,0,.5)),(1.50,3.50,(.5,1,.5,1))]
for ob in objs:
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    ob.data.materials.append(material);mi=len(ob.data.materials)-1;uv=ob.data.uv_layers.active
    for poly in ob.data.polygons:
        c=poly.center;n=poly.normal
        # Blender front is -Y; tilted display surface normal points up/front.
        if not (.62<c.z<1.75 and -3.43<c.y<-2.52 and n.z>.35 and n.y<-.12):continue
        selected=next(((i,g) for i,g in enumerate(groups) if g[0]<c.x<g[1]),None)
        if selected is None:continue
        i,(x0,x1,(u0,u1,v0,v1))=selected;poly.material_index=mi;counts[i]+=1
        for li in poly.loop_indices:
            co=ob.data.vertices[ob.data.loops[li].vertex_index].co
            u=min(.985,max(.015,(co.x-x0)/(x1-x0)))
            v=min(.985,max(.015,(-co.y-2.52)/(3.43-2.52)))
            uv.data[li].uv=(u0+u*(u1-u0),v0+v*(v1-v0))
after=triangle_hash(objs)
if before!=after:raise RuntimeError('Material edit changed model geometry')
if min(counts)<5:raise RuntimeError('Incomplete produce tray coverage '+str(counts))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'model.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'model.glb'),export_format='GLB',export_yup=True,export_apply=True,export_animations=False,export_image_format='JPEG',export_jpeg_quality=95)
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(OUT/'model.glb'));exported=triangle_hash([o for o in bpy.context.scene.objects if o.type=='MESH'])
if exported!=before:raise RuntimeError('Export changed world triangles')
(OUT/'edit-report.json').write_text(json.dumps({'world_triangles_sha256':before,'geometry_unchanged':True,'tray_face_counts':counts,'atlas_size':atlas_size,'atlas':'art/references/architecture_closeup_20261002/produce.png','quarter_atlas_width':627,'tray_ranges':groups},indent=2))
print('STORE_PRODUCE',counts,'geometry unchanged',before)

"""Fit the owned Hyper3D bell and split only the paper-tag hinge, retaining UVs."""
import bpy
import bmesh
import json
import sys
from pathlib import Path
from mathutils import Matrix, Vector

ROOT=Path(__file__).resolve().parents[2]
folder=ROOT/'art/models/raw/E01_furin_hyper3d'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(folder/'model.glb'))
meshes=[ob for ob in bpy.context.scene.objects if ob.type=='MESH']
for ob in bpy.context.scene.objects:ob.select_set(ob.type=='MESH')
bpy.context.view_layer.objects.active=meshes[0]
if len(meshes)>1:bpy.ops.object.join()
bell=bpy.context.view_layer.objects.active
bell.parent=None;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
points=[vertex.co.copy() for vertex in bell.data.vertices]
minimum=Vector([min(p[i] for p in points) for i in range(3)])
maximum=Vector([max(p[i] for p in points) for i in range(3)])
height=.64
scale=height/(maximum.z-minimum.z)
center=Vector(((minimum.x+maximum.x)/2,(minimum.y+maximum.y)/2,maximum.z))
bell.data.transform(Matrix.Scale(scale,4)@Matrix.Translation(-center))
triangles=sum(len(face.vertices)-2 for face in bell.data.polygons)
modifier=bell.modifiers.new('UV_preserving_reduction','DECIMATE');modifier.ratio=min(1.,18000/triangles)
bpy.context.view_layer.objects.active=bell;bpy.ops.object.modifier_apply(modifier=modifier.name)
bell.name='BellBody'
paper=bell.copy();paper.data=bell.data.copy();bpy.context.collection.objects.link(paper);paper.name='PaperTagMesh'
hinge=-height*.53
for ob,keep_lower in [(bell,False),(paper,True)]:
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=(0,0,hinge),plane_no=(0,0,1),
                           clear_inner=not keep_lower,clear_outer=keep_lower,dist=.000001)
    bm.to_mesh(ob.data);bm.free()
root=bpy.data.objects.new('FurinMount',None);bpy.context.collection.objects.link(root)
pivot=bpy.data.objects.new('PaperPivot',None);bpy.context.collection.objects.link(pivot);pivot.parent=root;pivot.location.z=hinge
bell.parent=root
paper.data.transform(Matrix.Translation(Vector((0,0,-hinge))));paper.parent=pivot
for mat in bpy.data.materials:
    if not mat.use_nodes:continue
    shader=next((node for node in mat.node_tree.nodes if node.type=='BSDF_PRINCIPLED'),None)
    if shader:
        for name,value in [('Metallic',0.),('Roughness',1.),('Specular IOR Level',0.),('Normal',None)]:
            if name not in shader.inputs:continue
            for link in list(shader.inputs[name].links):mat.node_tree.links.remove(link)
            if value is not None:shader.inputs[name].default_value=value
bpy.ops.wm.save_as_mainfile(filepath=str(folder/'furin.blend'))
bpy.ops.export_scene.gltf(filepath=str(folder/'ready.glb'),export_format='GLB',export_yup=True,export_apply=True,export_animations=False)
report={'source':'model.glb','height_m':height,'mount_y_godot':0,'paper_pivot_y_godot':hinge,
        'parts':{'bell_triangles':sum(len(face.vertices)-2 for face in bell.data.polygons),
                 'paper_triangles':sum(len(face.vertices)-2 for face in paper.data.polygons)},
        'method':'uniform scale; UV-preserving reduction; paper hinge split; matte diffuse material'}
(folder/'preparation.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))

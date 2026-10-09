"""Probe actual empty lattice apertures in a provider door mesh.

Blender -b --factory-startup -P ... -- RAW_GLB REPORT
Uses world-space BVH rays through the thinner horizontal axis, without relying
on albedo or the reference alpha. Raw remains unmodified on disk.
"""
import bpy,json,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
source,output=map(Path,sys.argv[sys.argv.index('--')+1:])
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
vertices=[];faces=[]
for ob in bpy.context.scene.objects:
    if ob.type!='MESH':continue
    base=len(vertices);vertices.extend(ob.matrix_world@v.co for v in ob.data.vertices)
    faces.extend([base+i for i in poly.vertices] for poly in ob.data.polygons)
low=Vector([min(v[a] for v in vertices) for a in range(3)]);high=Vector([max(v[a] for v in vertices) for a in range(3)]);size=high-low
thin=0 if size.x<size.y else 1;across=1-thin;tree=BVHTree.FromPolygons(vertices,faces)
hits=0;samples=0;columns=71;rows=83;scale=2.1/size.z
for i in range(columns):
    for j in range(rows):
        q=low.copy();q[across]=low[across]+size[across]*(.075+.85*i/(columns-1));q.z=low.z+size.z*(.32+.55*j/(rows-1));q[thin]=low[thin]-size[thin]-.1
        direction=Vector((0,0,0));direction[thin]=1
        hit,normal,index,distance=tree.ray_cast(q,direction,size[thin]*3+.2)
        samples+=1
        if hit is not None:hits+=1
ratio=1-hits/samples
report={'source':str(source),'samples':samples,'mesh_hits':hits,'open_aperture_fraction':ratio,'thin_axis_blender':thin,'thickness_m_at_2_1m_height':size[thin]*scale,'passed_real_apertures':ratio>.40,'method':'BVH rays through the upper lattice region; no image, alpha or material used'}
output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n');print('APERTURE',json.dumps(report),flush=True)

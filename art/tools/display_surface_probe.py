"""Measure a generated tray's interior floor after metre-scale export."""
import bpy,json,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
aid=sys.argv[sys.argv.index('--')+1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT/f'game/assets/models/{aid}.glb'))
vertices=[];faces=[]
for ob in bpy.context.scene.objects:
    if ob.type!='MESH':continue
    start=len(vertices);vertices.extend(ob.matrix_world@v.co for v in ob.data.vertices)
    faces.extend([start+i for i in p.vertices] for p in ob.data.polygons)
tree=BVHTree.FromPolygons(vertices,faces)
width=max(p.x for p in vertices)-min(p.x for p in vertices)
depth=max(p.y for p in vertices)-min(p.y for p in vertices)
heights=[]
for x in [-.25,0,.25]:
    for y in [-.25,0,.25]:
        hit,_,_,_=tree.ray_cast(Vector((x*width,y*depth,1)),Vector((0,0,-1)),2)
        if hit is not None:heights.append(hit.z)
report={'id':aid,'sample_heights_m':heights,'floor_height_m':sorted(heights)[len(heights)//2] if heights else None}
(ROOT/f'evidence/windows3d_20261003/{aid}-surface.json').write_text(json.dumps(report,indent=2)+'\n')
print('SURFACE',report)

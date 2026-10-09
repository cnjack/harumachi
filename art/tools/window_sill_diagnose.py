"""Identify actual mesh/material hits through the lower bakery opening."""
import bpy,json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'game/assets/models/S02.glb'))
trees=[]
for ob in bpy.context.scene.objects:
    if ob.type!='MESH':continue
    vertices=[ob.matrix_world@v.co for v in ob.data.vertices]
    faces=[list(p.vertices) for p in ob.data.polygons]
    trees.append((ob,BVHTree.FromPolygons(vertices,faces)))
report=[]
for y in [.89,.94,.99,1.04,1.09,1.14]:
    for x in [-1.30,-1.05,-.80,-.55,-.30,-.05]:
        hits=[]
        for ob,tree in trees:
            camera=Vector((.5,-5.45,1.65))
            target=Vector((x,-3.327,y))
            hit,normal,index,distance=tree.ray_cast(camera,(target-camera).normalized(),7.0)
            if hit is not None:
                polygon=ob.data.polygons[index]
                mat=ob.data.materials[polygon.material_index]
                hits.append({'object':ob.name,'material':mat.name if mat else '', 'point':[hit.x,hit.z,-hit.y],'distance':distance})
        if hits:report.append({'ray':[x,y],'hit':min(hits,key=lambda h:h['distance'])})
(ROOT/'evidence/windows3d_20261003/sill-hits.json').write_text(json.dumps(report,indent=2)+'\n')
print(report)

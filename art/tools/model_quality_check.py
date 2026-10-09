"""Measure replacement landmark geometry and textures, including old-model failures.

Blender -b --factory-startup -P art/tools/model_quality_check.py -- MODEL_DIR REPORT
The gate roof must have geometric relief, the yagura a narrow roof ridge instead
of stacked boxes, and the oven a real albedo atlas. Also verifies physical bounds.
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Vector, geometry
from mathutils.bvhtree import BVHTree

root = Path(__file__).resolve().parents[2]
model_dir, output = sys.argv[sys.argv.index('--')+1:]
bounds = json.loads((root/'evidence/hyper3d_quality_20261001/original_bounds.json').read_text())
report = {'models':{}, 'checks':{}}
bad_bounds=[]
for aid in ['P_farm_gate','P_yagura','P_deck_oven']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source=Path(model_dir)/(aid+'.glb')
    bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
    meshes=[obj for obj in bpy.context.scene.objects if obj.type=='MESH']
    points=[obj.matrix_world @ vertex.co for obj in meshes for vertex in obj.data.vertices]
    low=Vector([min(p[k] for p in points) for k in range(3)])
    high=Vector([max(p[k] for p in points) for k in range(3)])
    original=bounds[aid]
    delta=max(abs(low[k]-original['blender_min'][k]) for k in range(3))
    delta=max(delta,max(abs(high[k]-original['blender_max'][k]) for k in range(3)))
    if delta>0.012:bad_bounds.append(aid)
    textures=[]
    for obj in meshes:
        for mat in obj.data.materials:
            if not mat or not mat.use_nodes:continue
            bsdf=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
            if not bsdf:continue
            for link in bsdf.inputs['Base Color'].links:
                if link.from_node.type=='TEX_IMAGE' and link.from_node.image:
                    textures.append(list(link.from_node.image.size))
    metrics={'bounds_max_error_m':delta, 'texture_sizes':textures,
             'source_mtime':source.stat().st_mtime,
             'triangles':sum(len(p.vertices)-2 for obj in meshes for p in obj.data.polygons)}
    if aid=='P_deck_oven':
        report['checks']['oven_textured']=any(min(size)>=1024 for size in textures)
    elif aid=='P_yagura':
        top=[Vector((p.x,p.y)) for p in points if p.z>=high.z-0.035]
        angle=geometry.box_fit_2d(top) if len(top)>2 else 0
        c,s=math.cos(angle),math.sin(angle)
        x=[p.x*c-p.y*s for p in top];y=[p.x*s+p.y*c for p in top]
        width=min(max(x)-min(x),max(y)-min(y)) if top else 0
        metrics['roof_ridge_width_m']=width
        report['checks']['yagura_pitched_roof']=width<0.4
    else:
        verts=[];faces=[]
        for obj in meshes:
            base=len(verts);verts += [obj.matrix_world @ v.co for v in obj.data.vertices]
            faces += [[base+i for i in poly.vertices] for poly in obj.data.polygons]
        tree=BVHTree.FromPolygons(verts,faces)
        relief=[]
        for side in [-1,1]:
            yy=(low.y+high.y)/2 + side*(high.y-low.y)*0.22
            heights=[]
            for i in range(49):
                xx=(low.x+high.x)/2 + (i/48-0.5)*(high.x-low.x)*0.7
                hit,normal,index,distance=tree.ray_cast(Vector((xx,yy,high.z+1)),Vector((0,0,-1)),2)
                if hit:heights.append(hit.z)
            mean=sum(heights)/len(heights) if heights else 0
            relief.append(math.sqrt(sum((h-mean)**2 for h in heights)/len(heights)) if heights else 0)
        metrics['roof_relief_std_m']=relief
        report['checks']['gate_roof_relief']=max(relief)>0.005 and metrics['triangles']>=8000
    report['models'][aid]=metrics
report['checks']['physical_bounds']=not bad_bounds
report['failed']=[name for name,ok in report['checks'].items() if not ok]
Path(output).parent.mkdir(parents=True,exist_ok=True)
Path(output).write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
if report['failed']:sys.exit(1)

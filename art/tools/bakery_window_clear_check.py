"""Measure residual provider geometry in the mapped bakery display panes."""
import bpy,json,sys,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
source,out=map(Path,sys.argv[sys.argv.index('--')+1:]);bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
vertices=[];faces=[]
for ob in bpy.context.scene.objects:
    if ob.type!='MESH':continue
    start=len(vertices);vertices.extend(ob.matrix_world@v.co for v in ob.data.vertices);faces.extend([start+i for i in p.vertices] for p in ob.data.polygons)
tree=BVHTree.FromPolygons(vertices,faces);hits=[]
for low,high in [(-1.35,-.84),(-.59,.04)]:
    for iy in range(4):
        y=.915+iy*.04
        for ix in range(17):
            x=low+(high-low)*(ix+.5)/17
            p,_,_,_=tree.ray_cast(Vector((x,-5,y)),Vector((0,1,0)),10)
            if p is not None and -p.y>3.333:hits.append([x,y,-p.y])
report={'source':str(source),'source_mtime':source.stat().st_mtime,'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'rays':136,'intrusions':hits,'passed':not hits,'pane_plane_z':3.327,'allowed_front_margin_m':.006}
out.write_text(json.dumps(report,indent=2)+'\n');print('BAKERY_CLEAR',len(hits),'/136')
sys.exit(0 if report['passed'] else 1)

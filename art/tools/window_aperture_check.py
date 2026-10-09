"""Measure clear depth through the actual exported window openings."""
import bpy,json,sys,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from open_shop_display_cavities import PANES
directory,out=map(Path,sys.argv[sys.argv.index('--')+1:]);report={'models':{},'windows':{},'passed':True}
for aid,panes in PANES.items():
    source=directory/f'{aid}.glb';bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
    vertices=[];faces=[]
    for ob in bpy.context.scene.objects:
        if ob.type!='MESH' or not ob.name.startswith('Rodin_'+aid):continue
        start=len(vertices);vertices.extend(ob.matrix_world@v.co for v in ob.data.vertices);faces.extend([start+i for i in p.vertices] for p in ob.data.polygons)
    tree=BVHTree.FromPolygons(vertices,faces)
    for wi,pane in enumerate(panes):
        x0,x1,y0,y1,front=pane;clear=0;depths=[]
        for iy in range(9):
            y=y0+(y1-y0)*(iy+.5)/9
            for ix in range(13):
                x=x0+(x1-x0)*(ix+.5)/13
                hit,_,_,_=tree.ray_cast(Vector((x,-front-.01,y)),Vector((0,1,0)),3.0)
                depth=front+hit.y if hit is not None else 3.0
                depths.append(depth)
                clear+=depth>=.75
        fraction=clear/117;passed=fraction>=.60
        report['windows'][aid+':'+str(wi)]={'clear_fraction':fraction,'min_clear_depth_m':.75,'rays':117,'passed':passed}
        report['passed'] &= passed
    report['models'][aid]={'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'source_mtime':source.stat().st_mtime}
out.write_text(json.dumps(report,indent=2)+'\n');print('APERTURES',report['passed'],report['windows']);sys.exit(0 if report['passed'] else 1)

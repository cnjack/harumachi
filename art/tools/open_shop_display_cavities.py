"""Clear opaque generated window fill behind retained facade frames.

Inputs are the reviewed game-ready material assets, not original downloads.
Only the body is cut; independent exterior displays, signs and trim survive.
Actual apertures and straight frame profiles must be measured after export.
"""
import bpy,bmesh,json,sys,hashlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from mesh_cavity_clip import clear_boxes
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/models/raw/window_cavities_20261003'
PANES={
 'S01':[[-2.10,2.22,.72,2.16,2.782]],
 'S02':[[-1.44,.145,.87,2.29,3.327],[.61,1.15,1.08,2.08,2.944]],
 'S03':[[-2.23,-1.49,1.10,1.94,3.041],[.03,2.52,.24,1.83,3.74]],
 'S05':[[-1.83,.39,1.04,2.58,3.746]],
 'S08':[[-2.01,.39,.22,2.18,3.065],[.57,2.69,.91,2.17,3.012]],
}

def build(aid):
    OUT.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src=ROOT/f'art/models/raw/material_detail_20261003/{aid}.glb'
    bpy.ops.import_scene.gltf(filepath=str(src))
    bodies=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith('Rodin_'+aid)]
    if not bodies:raise RuntimeError('No provider body found '+aid)
    source_points=[o.matrix_world@v.co for o in bodies for v in o.data.vertices]
    source_bounds=[min(p[i] for p in source_points) for i in range(3)]+[max(p[i] for p in source_points) for i in range(3)]
    source_tris=sum(len(p.vertices)-2 for ob in bodies for p in ob.data.polygons)
    boxes=[]
    for i,window in enumerate(PANES[aid]):
        x0,x1,y0,y1,front=window
        boxes.append(((x0+.015,-front-.018,y0+.015),(x1-.015,-front+2.25,y1-.015)))
        boxes.append(((x0+.015,-front+.36,.05),(x1-.015,-front+2.25,y0+.03)))
    for ob in bodies:clear_boxes(ob,boxes)
    # The clipping method creates no reveal caps. The exterior sill and plinth
    # must survive below the opening; a real timber reveal covers their edge.
    removed_caps=0
    output_points=[o.matrix_world@v.co for o in bodies for v in o.data.vertices]
    output_bounds=[min(p[i] for p in output_points) for i in range(3)]+[max(p[i] for p in output_points) for i in range(3)]
    output_tris=sum(len(p.vertices)-2 for ob in bodies for p in ob.data.polygons)
    if output_tris<source_tris*.70 or max(abs(a-b) for a,b in zip(source_bounds,output_bounds))>.03:
        raise RuntimeError('Cavity cut damaged unrelated exterior geometry: '+aid)
    for image in bpy.data.images:
        if image.size[0]>0:image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{aid}.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'{aid}.glb'),export_format='GLB',export_yup=True,export_apply=True,export_image_format='JPEG',export_jpeg_quality=96)
    assembly=json.loads((ROOT/f'art/models/raw/material_detail_20261003/{aid}_assembly.json').read_text())
    assembly.setdefault('repairs',[]).append('opaque body fill removed behind display panes; original facade trim retained')
    (OUT/f'{aid}_assembly.json').write_text(json.dumps(assembly,indent=2)+'\n')
    (OUT/f'{aid}_cavity.json').write_text(json.dumps({'asset':aid,'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'panes':PANES[aid],'method':'triangle clipping with original UV interpolation; no boolean caps','depth_m':2.25,'opening_front_overlap_m':.018,'frame_inset_m':.015,'interior_front_skin_m':.36,'removed_generated_cap_faces':removed_caps,'source_triangles':source_tris,'output_triangles':output_tris,'source_bounds_blender':source_bounds,'output_bounds_blender':output_bounds},indent=2)+'\n')
    print('OPENED_DISPLAY',aid,flush=True)

if __name__=='__main__':
    for aid in sys.argv[sys.argv.index('--')+1:]:build(aid)

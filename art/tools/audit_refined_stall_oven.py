"""Producer guard: real closed solids and fitted part contacts, independent of build.

Blender -b --factory-startup --python-exit-code 1 -P art/tools/audit_refined_stall_oven.py
Blender ... -- --before=evidence/material_refinement_delivery_20261011/topology-before --out=/tmp/old.json

Uses actual editable triangles, not the builder's nominal dimensions. The final
raw GLBs must also pass audit_stall_oven.py and model_audit's unchanged contract
before game-export promotion. No geometry or images are modified by this audit.
"""
import bpy,bmesh,json,hashlib,sys
from pathlib import Path
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
RAW=ROOT/'art/models/raw/material_refine_stall_oven_20261011'
ARGS=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
BEFORE=next((Path(a.split('=',1)[1]) for a in ARGS if a.startswith('--before=')),None)
OUTFILE=next((Path(a.split('=',1)[1]) for a in ARGS if a.startswith('--out=')),ROOT/'evidence/material_refinement_delivery_20261011/topology-diagnosis/closed-structure-actual-contacts.json')

def world_mesh(objects):
    points=[];faces=[]
    for obj in objects:
        base=len(points);points.extend(obj.matrix_world@v.co for v in obj.data.vertices)
        faces.extend([base+i for i in face.vertices] for face in obj.data.polygons)
    return points,faces

def tree(objects):
    points,faces=world_mesh(objects)
    return BVHTree.FromPolygons(points,faces),points

def closed(objects):
    points,faces=world_mesh(objects)
    mesh=bpy.data.meshes.new('independent topology probe');mesh.from_pydata(points,[],faces);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
    r={'boundary_edges':sum(e.is_boundary for e in bm.edges),'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),'faces':len(bm.faces),'signed_volume_m3':bm.calc_volume(signed=True)}
    bm.free();bpy.data.meshes.remove(mesh);return r

def contact(a,b):
    ta,pa=tree(a);tb,pb=tree(b);overlap=ta.overlap(tb)
    distances=[] if overlap else [tb.find_nearest(p)[3] for p in pa]+[ta.find_nearest(p)[3] for p in pb]
    minimum=0. if overlap else min(d for d in distances if d is not None)
    return {'passed':bool(overlap) or minimum<.00002,'surface_intersections':len(overlap),'minimum_sampled_gap_m':minimum}

report={'models':{}}
for aid in ['P09','P_deck_oven']:
    source=(BEFORE/('art__models__raw__material_refine_stall_oven_20261011__'+aid+'.blend')) if BEFORE else RAW/(aid+'.blend')
    bpy.ops.wm.open_mainfile(filepath=str(source))
    objs={o.name:o for o in bpy.context.scene.objects if o.type=='MESH'}
    if aid=='P09':
        subjects={'continuous_canvas':[o for n,o in objs.items() if n.startswith(('P09_Continuous','P09_CanvasValance'))],'timber_counter':[o for n,o in objs.items() if any(mat.name=='P09_Cedar_Maintained' for mat in o.data.materials)]}
        contacts={}
        # Both long roof rails touch the stretched cloth, retaining its load path.
        contacts['cloth_to_timber']=contact(subjects['continuous_canvas'],subjects['timber_counter'])
    else:
        core=[o for n,o in objs.items() if n in ['Oven_MaintainedEnamel_Geometry','Oven_WarmCavity_Geometry','Oven_StoneDeck_Geometry','Oven_HeatSeal_Geometry','Oven_ControlPanel_Geometry']]
        if BEFORE:
            core=[o for n,o in objs.items() if all(mat.name in ['Oven_MaintainedEnamel','Oven_WarmCavity','Oven_StoneDeck','Oven_HeatSeal'] for mat in o.data.materials) or '_Hinge' in n]
        subjects={'cabinet_base_flue_and_door_core':core}
        contacts={}
        for d in range(2):
            prefix='Oven_Deck'+str(d)
            for q in range(2):
                contacts[prefix+'_knob'+str(q)+'_to_panel']=contact([objs[prefix+'_Knob'+str(q)]],[objs[prefix+'_ControlPanel']])
            for suffix in ['_Glass','_ControlPanel','_WarmElement']+['_Rack_'+str(i) for i in range(4)]+['_HandleMount'+str(s) for s in [-1,1]]:
                contacts[prefix+suffix+'_to_cabinet']=contact([objs[prefix+suffix]],core)
            for s in [-1,1]:
                contacts[prefix+'_handle_to_mount'+str(s)]=contact([objs[prefix+'_LevelHandle']],[objs[prefix+'_HandleMount'+str(s)]])
        for name,obj in objs.items():
            if name.startswith('Oven_VentLouver_'):contacts[name+'_to_vent_lip']=contact([obj],core)
        subjects['closed_fitted_hardware']=[o for n,o in objs.items() if any(k in n for k in ['_Knob','_Glass','_ControlPanel','_LevelHandle','_HandleMount','_WarmElement','_Rack_','Oven_VentLouver_']) and o not in core]
    assert all(subjects.values()),'Nonempty physical structure required'
    measured={name:closed(group) for name,group in subjects.items()}
    # Hardware can intersect or meet at coincident capped faces; closedness is
    # tested per fitted solid, whereas the united cabinet must be manifold.
    if aid=='P_deck_oven':
        measured['closed_fitted_hardware']={o.name:closed([o]) for o in subjects['closed_fitted_hardware']}
    report['models'][aid]={'editable_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'topology':measured,'contacts':contacts,'passed':all(v['passed'] for v in contacts.values()) and all(v['boundary_edges']==0 and v['nonmanifold_edges']==0 for k,v in measured.items() if k!='closed_fitted_hardware') and all(v['boundary_edges']==0 and v['nonmanifold_edges']==0 for v in measured.get('closed_fitted_hardware',{}).values())}
report['passed']=all(m['passed'] for m in report['models'].values())
OUTFILE.parent.mkdir(parents=True,exist_ok=True)
OUTFILE.write_text(json.dumps(report,indent=2)+'\n')
print('STRUCTURE_CONTACTS',json.dumps(report))
if not report['passed']:raise RuntimeError('Actual closedness/contact failed')

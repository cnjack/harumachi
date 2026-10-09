"""Independent ray measurements of straight joinery; compare old/new exported GLBs.

Blender -b --factory-startup -P art/tools/architecture_quality_check.py -- MODEL_DIR REPORT
Uses the native design dimensions as a reference, then measures actual surfaces.
The old soft meshes must fail; labels/member counts are not acceptance evidence.
"""
import bpy,json,sys,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).parent))
directory,output=map(Path,sys.argv[sys.argv.index('--')+1:])
ids=['H01','H02','H03','S06','S01','S02','S03','S05','S08','M01_timber_machiya','M03_gable_house','M05_residential']
bounds=json.loads((ROOT/'art/models/model_quality_contracts.json').read_text())['bounds_godot']
report={'models':{},'profiles':{},'checks':{},'failed_profiles':[]}
spec=json.loads((ROOT/'art/models/game_assets.json').read_text())['assets']

def tree(path,only_prefix=None):
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(path.resolve()))
    verts=[];faces=[]
    for obj in bpy.context.scene.objects:
        if obj.type!='MESH' or (only_prefix and not obj.name.startswith(only_prefix)):continue
        base=len(verts)
        for v in obj.data.vertices:
            p=obj.matrix_world@v.co;verts.append(Vector((p.x,p.z,-p.y)))
        faces += [[base+i for i in p.vertices] for p in obj.data.polygons]
    return BVHTree.FromPolygons(verts,faces)

for aid in ids:
    source=directory/(aid+'.glb')
    if not source.exists():report['failed_profiles'].append(aid+': missing GLB');continue
    native=ROOT/'art/models'/spec[aid]['src']
    assembly=native.with_name(f'{aid}_assembly.json')
    if assembly.exists():
        data=json.loads(assembly.read_text())
        profiles_spec=json.loads((ROOT/'art/models/rodin_joinery_profiles_20261003.json').read_text())[aid]
        bt=tree(source,'DoorFrame' if aid in ['H01','H03'] else None);profiles=[]
        for ref in profiles_spec:
            active_tree=tree(source,ref['mesh_prefix']) if ref.get('mesh_prefix') else bt
            errors=[];hits=0;depths=[]
            for i in range(41):
                p=Vector(ref['a']).lerp(Vector(ref['b']),i/40)
                direction=Vector(ref.get('ray',[0,0,-1]))
                hit,normal,index,d=active_tree.ray_cast(p-direction*.15,direction,.30)
                if hit:
                    hits+=1;errors.append(abs((hit-p).dot(direction)));depths.append(list(hit))
            profiles.append({'feature':ref['feature'],'samples':41,'hits':hits,'max_deviation_m':max(errors,default=1.),'passed':hits>=39 and max(errors,default=1.)<.006,'hit_positions':depths})
        report['profiles'][aid]=profiles
        report['failed_profiles'].extend(aid+': '+p['feature'] for p in profiles if not p['passed'])
        report['models'][aid]={'source_mtime':source.stat().st_mtime,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
        continue
    data=json.loads(native.with_name(f'{aid}_members.json').read_text());members=data['members']
    native_lo=[min(m['min'][a] for m in members) for a in range(3)]
    scale=data['fit_scale_blender'];gs=[scale[0],scale[2],scale[1]];target=bounds[aid]['min']
    def map_point(p):
        if 'translation_godot' in data:return Vector([p[a]+data['translation_godot'][a] for a in range(3)])
        return Vector([target[a]+(p[a]-native_lo[a])*gs[a] for a in range(3)])
    bt=tree(source);profiles=[]
    jambs=[m for m in members if m['role']=='straight_jamb' and (m['min'][2]+m['max'][2])/2>.55 and m['max'][1]-m['min'][1]>1.7 and m['min'][1]<1.2]
    if not jambs:raise RuntimeError('Design lacks a front jamb '+aid)
    j=jambs[0];x=(j['min'][0]+j['max'][0])/2;z=j['max'][2];y0=max(j['min'][1]+.15,1.40);y1=j['max'][1]-.15
    expected=map_point((x,y0,z)).z;errors=[];hits=0
    for i in range(41):
        p=map_point((x,y0+(y1-y0)*i/40,z));origin=Vector((p.x,p.y,p.z+.35));hit,normal,index,d=bt.ray_cast(origin,Vector((0,0,-1)),.85)
        if hit:hits+=1;errors.append(abs(hit.z-expected))
    profiles.append({'feature':'vertical door/window jamb','samples':41,'hits':hits,'max_deviation_m':max(errors) if errors else 1.,'passed':hits>=39 and max(errors,default=1)<.006})
    if aid=='H02':
        rail=next(m for m in members if m['role']=='balcony_horizontal_rail' and m['max'][1]>3.7);z=(rail['min'][2]+rail['max'][2])/2;y=rail['max'][1];errors=[];hits=0;samples=0
        posts=[m for m in members if m['role']=='balcony_post']
        for i in range(41):
            x=rail['min'][0]+.15+(rail['max'][0]-rail['min'][0]-.30)*i/40
            # Raised post caps are separate designed parts, not bent rail.
            if any(m['min'][0]-.01<x<m['max'][0]+.01 for m in posts):continue
            samples+=1;p=map_point((x,y,z));hit,n,idx,d=bt.ray_cast(p+Vector((0,.35,0)),Vector((0,-1,0)),.85)
            if hit:hits+=1;errors.append(abs(hit.y-p.y))
        profiles.append({'feature':'horizontal balcony rail','samples':samples,'hits':hits,'max_deviation_m':max(errors) if errors else 1.,'passed':hits>=samples-1 and max(errors,default=1)<.006})
    report['profiles'][aid]=profiles
    for p in profiles:
        if not p['passed']:report['failed_profiles'].append(aid+': '+p['feature'])
    report['models'][aid]={'source_mtime':source.stat().st_mtime,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}

tree(directory/'S01.glb');densities=[]
for obj in bpy.context.scene.objects:
    if obj.type!='MESH' or not obj.data.uv_layers.active:continue
    mesh=obj.data;mesh.calc_loop_triangles();uv=mesh.uv_layers.active.data
    for tri in mesh.loop_triangles:
        mat=mesh.materials[tri.material_index]
        if not mat or 'produce' not in mat.name.lower() or not mat.use_nodes:continue
        img=next((n.image for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image),None)
        if img is None:continue
        p=[obj.matrix_world@mesh.vertices[i].co for i in tri.vertices];area=(p[1]-p[0]).cross(p[2]-p[0]).length*.5
        t=[Vector((uv[i].uv.x*img.size[0],uv[i].uv.y*img.size[1])) for i in tri.loops];a,b=t[1]-t[0],t[2]-t[0];pixels=abs(a.x*b.y-a.y*b.x)*.5
        if area>1e-10 and pixels>0:densities.append(((pixels/area)**.5,area))
densities.sort();total=sum(a for d,a in densities);acc=0;density=0
for d,a in densities:
    acc+=a
    if acc>=total*.5:density=d;break
report['produce_density_px_m']=density
report['checks']={'straight_joinery':not report['failed_profiles'],'produce_detail':report['produce_density_px_m']>=300}
Path(output).parent.mkdir(parents=True,exist_ok=True);Path(output).write_text(json.dumps(report,indent=2)+'\n')
print('ARCHITECTURE',report['checks'],'failed',report['failed_profiles'],'produce px/m',report['produce_density_px_m'])

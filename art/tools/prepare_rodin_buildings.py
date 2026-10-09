"""Normalize provider bodies uniformly and reduce geometry without rebaking UVs.

Original downloads remain immutable. Front plot anchors are explicit, so deep
houses extend into their plot instead of being flattened to an old bounding box.
Blender -b --factory-startup -P this_file -- ID ...
"""
import bpy,bmesh,json,sys,hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/models/raw/scene_rodin_20261002'
SPECS={
 'H01_main':(6.8,None,150000), 'H02':(6.8,2.895,200000), 'H02_unit':(2.65,None,45000),
 'S01':(5.25,3.80,150000), 'S02':(6.60,3.82,160000),
 'S03':(5.45,4.23,180000), 'S05':(5.60,4.84,160000),
 'S06':(5.80,5.46,180000), 'S08':(6.15,4.26,160000),
 'M01_timber_machiya':(6.60,1.15,140000),
 'M03_gable_house':(6.60,4.14,170000),
 'M05_residential':(6.80,1.31,140000),
}

def build(aid):
    source=ROOT/f'art/models/raw/{aid}_hyper_scene_20261003/model.glb'
    height,front,target=SPECS[aid]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    obs=[o for o in bpy.context.scene.objects if o.type=='MESH']
    pts=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
    lo=Vector([min(v[a] for v in pts) for a in range(3)])
    hi=Vector([max(v[a] for v in pts) for a in range(3)])
    scale=height/(hi.z-lo.z);origin=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    shift=0 if front is None else front-(hi.y-lo.y)*scale/2
    before=sum(len(p.vertices)-2 for o in obs for p in o.data.polygons)
    for ob in obs:
        mw=ob.matrix_world.copy()
        for v in ob.data.vertices:
            v.co=(mw@v.co-origin)*scale+Vector((0,-shift,0))
            if v.co.z<.02:v.co.z=0
        ob.parent=None;ob.matrix_world.identity();ob.name=f'Rodin_{aid}_body'
        bm=bmesh.new();bm.from_mesh(ob.data)
        bmesh.ops.remove_doubles(bm,verts=bm.verts[:],dist=1e-7)
        bm.to_mesh(ob.data);bm.free()
        bpy.context.view_layer.objects.active=ob
        mod=ob.modifiers.new('Preserve_UV_geometry_budget','DECIMATE')
        mod.ratio=min(1,target/before)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        for mat in ob.data.materials:
            if not mat or not mat.use_nodes:continue
            bs=mat.node_tree.nodes.get('Principled BSDF')
            for name,value in [('Normal',None),('Metallic',0),('Roughness',1),('Specular IOR Level',0)]:
                for link in list(bs.inputs[name].links):mat.node_tree.links.remove(link)
                if value is not None:bs.inputs[name].default_value=value
    for image in bpy.data.images:
        if image.size[0]>0:image.pack()
    OUT.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{aid}_body.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'{aid}_body.glb'),export_format='GLB',export_yup=True,export_apply=True,export_image_format='JPEG',export_jpeg_quality=98)
    pts=[v.co for o in obs for v in o.data.vertices]
    low=[min(v[a] for v in pts) for a in range(3)];high=[max(v[a] for v in pts) for a in range(3)]
    report={'asset':aid,'source':str(source.relative_to(ROOT)), 'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
      'uniform_scale':scale,'front_shift_m':shift,'triangles_before':before,'triangles_after':sum(len(p.vertices)-2 for o in obs for p in o.data.polygons),
      'bounds_godot':{'min':[low[0],low[2],-high[1]],'max':[high[0],high[2],-low[1]]},
      'method':'exact seam weld; UV-preserving decimation; uniform scale; front anchor; original albedo; matte materials'}
    (OUT/f'{aid}_body.json').write_text(json.dumps(report,indent=2)+'\n')
    print('PREPARED',json.dumps(report),flush=True)

if __name__=='__main__':
    for aid in sys.argv[sys.argv.index('--')+1:]:build(aid)

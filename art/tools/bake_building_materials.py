"""Bake genuinely new metre-scale painted detail into retained Rodin UVs.

No remeshing, enlarged islands, or interpolated-only texture upgrade. The input
albedo preserves fixtures; new AI painted cedar/plaster/glaze is sampled in world
metres, softly masked per texel and baked at the density required by each surface.
Blender handles texture composition and baking, never edits the source artwork.
"""
import bpy, json, math, sys, hashlib
from pathlib import Path
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT/'art/models/raw/scene_rodin_20261002'
OUT = ROOT/'art/models/raw/material_detail_20261003'
ART = ROOT/'art/references/building_materials_20261003'
AUDIT = json.loads((ROOT/'evidence/building_materials_20261003/before/audit.json').read_text())['models']

def math_node(nt, op, a, b=None, clamp=False):
    n=nt.nodes.new('ShaderNodeMath'); n.operation=op; n.use_clamp=clamp
    for i,v in enumerate([a,b]):
        if v is None:continue
        if isinstance(v,(int,float)):n.inputs[i].default_value=v
        else:nt.links.new(v,n.inputs[i])
    return n.outputs[0]

def ramp(nt,value,low,high):
    return math_node(nt,'MULTIPLY',math_node(nt,'SUBTRACT',value,low),1/(high-low),True)

def mix(nt,mode,factor,a,b):
    n=nt.nodes.new('ShaderNodeMixRGB');n.blend_type=mode
    for i,v in enumerate([factor,a,b]):
        if isinstance(v,(int,float)):n.inputs[i].default_value=v
        else:nt.links.new(v,n.inputs[i])
    return n.outputs[0]

def detail(nt,kind,position,scale):
    image=bpy.data.images.load(str(ART/f'{kind}.png'),check_existing=True)
    n=nt.nodes.new('ShaderNodeTexImage');n.image=image;n.projection='BOX';n.projection_blend=.18
    mapping=nt.nodes.new('ShaderNodeVectorMath');mapping.operation='SCALE';mapping.inputs[3].default_value=1/scale
    nt.links.new(position,mapping.inputs[0]);nt.links.new(mapping.outputs[0],n.inputs[0])
    bw=nt.nodes.new('ShaderNodeRGBToBW');nt.links.new(n.outputs['Color'],bw.inputs[0])
    # Normalize the authored material, retaining the colour of the provider.
    pixels=np.empty(image.size[0]*image.size[1]*4,dtype=np.float32);image.pixels.foreach_get(pixels)
    mean=float(np.mean(pixels.reshape(-1,4)[:,:3]@np.array([.2126,.7152,.0722])))
    value=math_node(nt,'DIVIDE',bw.outputs[0],max(mean,.01))
    value=math_node(nt,'MINIMUM',math_node(nt,'MAXIMUM',value,.70),1.16)
    return value

def setup(material, height, aid):
    nt=material.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
    if not bs.inputs['Base Color'].is_linked:return None
    base=bs.inputs['Base Color'].links[0].from_socket
    geo=nt.nodes.new('ShaderNodeNewGeometry');pos=geo.outputs['Position']
    ps=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(pos,ps.inputs[0])
    normal=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(geo.outputs['Normal'],normal.inputs[0])
    facade=ART/f'{aid}.png'
    # The edited facade stays a camera projection in actual metres. Original UVs
    # remain active, so joints, back faces and independent module atlases survive.
    if facade.exists() and (material.name=='model' or material.name.startswith('cloth_noren')) and aid.startswith(('S','M')):
        survey=json.loads((ROOT/f'evidence/scene_hyper3d_replace_20261002/front-survey/{aid}.json').read_text())
        size=survey['square_image_world_width'];cy=survey['image_center_xy'][1]
        projected_x=ps.outputs['X']
        correction_path=ROOT/'art/models/rodin_facade_projection_corrections_20261003.json'
        corrections=json.loads(correction_path.read_text()) if correction_path.exists() else {}
        if aid in corrections:
            affine=corrections[aid]['final_godot_to_original_godot_affine']
            projected_x=math_node(nt,'ADD',math_node(nt,'ADD',math_node(nt,'MULTIPLY',ps.outputs['X'],affine[0][0]),math_node(nt,'MULTIPLY',ps.outputs['Y'],-affine[2][0])),affine[3][0])
        comb=nt.nodes.new('ShaderNodeCombineXYZ')
        nt.links.new(math_node(nt,'ADD',math_node(nt,'DIVIDE',projected_x,size),.5),comb.inputs[0])
        nt.links.new(math_node(nt,'ADD',math_node(nt,'DIVIDE',math_node(nt,'SUBTRACT',ps.outputs['Z'],cy),size),.5),comb.inputs[1])
        painted=nt.nodes.new('ShaderNodeTexImage');painted.image=bpy.data.images.load(str(facade),check_existing=True);painted.extension='EXTEND'
        nt.links.new(comb.outputs[0],painted.inputs[0])
        front=math_node(nt,'SUBTRACT',0,normal.outputs['Y'])
        depth=math_node(nt,'SUBTRACT',0,ps.outputs['Y'])
        minimum={'S02':2.4,'S03':1.7,'S05':1.6,'S06':3.4,'S08':2.1,'M01_timber_machiya':-1.2,'M03_gable_house':2.5,'M05_residential':.5}.get(aid,2)
        weight=math_node(nt,'MULTIPLY',ramp(nt,front,.40,.75),ramp(nt,depth,minimum,minimum+.2))
        visible=nt.nodes.new('ShaderNodeVertexColor');visible.layer_name='Facade_visibility'
        weight=math_node(nt,'MULTIPLY',weight,visible.outputs['Color'])
        if aid=='S08':
            # The edited bell silhouette can shift a few pixels. Keep the
            # background within its full measured footprint on the provider UV;
            # the actual foreground bell still receives the edited blue pattern.
            zone_x=math_node(nt,'MULTIPLY',ramp(nt,ps.outputs['X'],0,.15),math_node(nt,'SUBTRACT',1,ramp(nt,ps.outputs['X'],1.40,1.55)))
            zone_y=math_node(nt,'MULTIPLY',ramp(nt,ps.outputs['Z'],1.55,1.70),math_node(nt,'SUBTRACT',1,ramp(nt,ps.outputs['Z'],3.05,3.20)))
            behind=math_node(nt,'SUBTRACT',1,ramp(nt,depth,3.42,3.60))
            exclude=math_node(nt,'MULTIPLY',math_node(nt,'MULTIPLY',zone_x,zone_y),behind)
            weight=math_node(nt,'MULTIPLY',weight,math_node(nt,'SUBTRACT',1,exclude))
        base=mix(nt,'MIX',weight,base,painted.outputs['Color'])
    sep=nt.nodes.new('ShaderNodeSeparateColor');nt.links.new(base,sep.inputs[0]);r,g,b=[sep.outputs[k] for k in ['Red','Green','Blue']]
    # Smooth masks live at image pixels, rather than assigning whole triangles.
    chroma=math_node(nt,'DIVIDE',math_node(nt,'SUBTRACT',r,b),math_node(nt,'MAXIMUM',r,.01))
    wood=math_node(nt,'MULTIPLY',ramp(nt,chroma,.24,.48),ramp(nt,math_node(nt,'SUBTRACT',r,g),.004,.04))
    # Strong red terracotta and brick keep their original joints; no wood grain.
    wood=math_node(nt,'MULTIPLY',wood,math_node(nt,'SUBTRACT',1,ramp(nt,math_node(nt,'SUBTRACT',r,g),.20,.36)))
    if aid in ['S02','S05']:
        wood=math_node(nt,'MULTIPLY',wood,ramp(nt,ps.outputs['Z'],1.15,1.35))
    white=math_node(nt,'MULTIPLY',ramp(nt,r,.52,.75),ramp(nt,b,.44,.66))
    roof=math_node(nt,'MULTIPLY',ramp(nt,math_node(nt,'SUBTRACT',b,r),-.025,.055),ramp(nt,normal.outputs['Z'],.18,.52))
    roof=math_node(nt,'MULTIPLY',roof,ramp(nt,ps.outputs['Z'],height*.27,height*.4))
    colour=mix(nt,'MULTIPLY',math_node(nt,'MULTIPLY',wood,.68),base,detail(nt,'cedar',pos,1.05))
    colour=mix(nt,'MULTIPLY',math_node(nt,'MULTIPLY',white,.30),colour,detail(nt,'plaster',pos,1.15))
    colour=mix(nt,'MULTIPLY',math_node(nt,'MULTIPLY',roof,.34),colour,detail(nt,'tile',pos,.75))
    if material.name.startswith('cloth_') and (ART/'cloth.png').exists():
        # Coarser sampling survives the final atlas density without moire.
        colour=mix(nt,'MULTIPLY',.35,base,detail(nt,'cloth',pos,2.40))
    output=next(n for n in nt.nodes if n.type=='OUTPUT_MATERIAL')
    emit=nt.nodes.new('ShaderNodeEmission');nt.links.new(colour,emit.inputs[0]);nt.links.new(emit.outputs[0],output.inputs['Surface'])
    return bs,output,emit

def build(aid):
    OUT.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src=INPUT/f'{aid}.glb';bpy.ops.import_scene.gltf(filepath=str(src))
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
    if (ART/f'{aid}.png').exists():
        # An orthographic picture contains foreground fixtures. Do not stamp
        # their silhouettes again onto the wooden wall hidden behind them.
        vertices=[];faces=[]
        for ob in objects:
            start=len(vertices);vertices.extend(ob.matrix_world@v.co for v in ob.data.vertices)
            faces.extend([start+i for i in p.vertices] for p in ob.data.polygons)
        tree=BVHTree.FromPolygons(vertices,faces)
        for ob in objects:
            attr=ob.data.color_attributes.new(name='Facade_visibility',type='FLOAT_COLOR',domain='POINT')
            colours=np.zeros((len(ob.data.vertices),4),dtype=np.float32);colours[:,3]=1
            for i,v in enumerate(ob.data.vertices):
                p=ob.matrix_world@v.co
                hit,_,_,_=tree.ray_cast(Vector((p.x,-40,p.z)),Vector((0,1,0)),80)
                visible=hit is not None and abs(hit.y-p.y)<.018
                colours[i,:3]=1 if visible else 0
            attr.data.foreach_set('color',colours.ravel())
    height=max((o.matrix_world@v.co).z for o in objects for v in o.data.vertices)
    sc=bpy.context.scene;sc.render.engine='CYCLES';sc.cycles.samples=1;sc.cycles.device='CPU'
    sc.render.bake.use_selected_to_active=False;sc.render.bake.margin=16;sc.render.bake.margin_type='EXTEND'
    report={'asset':aid,'input_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'method':'world metre AI detail, smooth pixel masks, emission bake into unchanged UVs','materials':[]}
    materials={m for o in objects for m in o.data.materials if m and m.use_nodes}
    targets={};originals={};details={}
    for mat in materials:
        den=AUDIT[aid]['material_density_px_m'].get(mat.name,{}).get('median')
        if den is None:continue
        tex=next((n.image for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image),None)
        if not tex:continue
        width=tex.size[0]
        # Tiny independent frontage parts already have genuine readable detail.
        if den>=280 and not mat.name.startswith('Lived_S01'):continue
        size=min(8192,max(width,2**math.ceil(math.log2(width*205/max(den,1)))))
        state=setup(mat,height,aid)
        if not state:continue
        image=bpy.data.images.new(f'{aid}_{mat.name}_painted_detail',size,size,alpha=False)
        image.generated_color=(.4,.4,.4,1)
        target=mat.node_tree.nodes.new('ShaderNodeTexImage');target.image=image;mat.node_tree.nodes.active=target
        targets[mat]=target;originals[mat]=state
        details[mat]={'name':mat.name,'old_size':list(tex.size),'new_size':[size,size],'old_density_px_m':den,'predicted_density_px_m':round(den*size/width,2)}
    # Bake each mesh; shared atlas targets accumulate without wiping prior parts.
    done=set()
    for ob in objects:
        selected=[m for m in ob.data.materials if m in targets]
        if not selected:continue
        # All surfaces need an active target for Blender, even surfaces retained.
        scratch=[]
        for mat in ob.data.materials:
            if mat in targets:mat.node_tree.nodes.active=targets[mat];continue
            if mat and mat.use_nodes:
                n=mat.node_tree.nodes.new('ShaderNodeTexImage');n.image=bpy.data.images.new('Unused_bake',8,8);mat.node_tree.nodes.active=n;scratch.append((mat,n))
        bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
        sc.render.bake.use_clear=not any(m in done for m in selected)
        print('BAKE_DETAIL',aid,ob.name,[(m.name,targets[m].image.size[:]) for m in selected],flush=True)
        bpy.ops.object.bake(type='EMIT');done.update(selected)
        for mat,n in scratch:mat.node_tree.nodes.remove(n)
    for mat,target in targets.items():
        bs,output,emit=originals[mat];nt=mat.node_tree
        nt.links.new(target.outputs['Color'],bs.inputs['Base Color']);nt.links.new(bs.outputs['BSDF'],output.inputs['Surface'])
        keep={bs,output,target}
        # Matte GLB exports only the baked new albedo; original art stays in src.
        for n in list(nt.nodes):
            if n not in keep:nt.nodes.remove(n)
        bs.inputs['Roughness'].default_value=1;bs.inputs['Metallic'].default_value=0;bs.inputs['Specular IOR Level'].default_value=0
        image=target.image;image.filepath_raw=str(OUT/f'{aid}_{len(report["materials"]):02d}.jpg');image.file_format='JPEG';image.save();image.pack()
        details[mat]['image_sha256']=hashlib.sha256(Path(image.filepath_raw).read_bytes()).hexdigest()
        report['materials'].append(details[mat])
    for ob in objects:
        attr=ob.data.color_attributes.get('Facade_visibility')
        if attr:ob.data.color_attributes.remove(attr)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{aid}.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'{aid}.glb'),export_format='GLB',export_yup=True,export_apply=True,export_image_format='JPEG',export_jpeg_quality=96)
    report['output_sha256']=hashlib.sha256((OUT/f'{aid}.glb').read_bytes()).hexdigest()
    (OUT/f'{aid}.json').write_text(json.dumps(report,indent=2)+'\n')
    print('DETAIL_DONE',aid,flush=True)

if __name__=='__main__':
    for aid in sys.argv[sys.argv.index('--')+1:]:build(aid)

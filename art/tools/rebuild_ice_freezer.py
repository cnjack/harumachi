"""Author the grocery chest freezer with a real cavity and two glass sliding lids.

Blender -b --factory-startup -P art/tools/rebuild_ice_freezer.py
Exports the editable source only. Use game_export.py with the recorded preserve_parts entry.
"""
import hashlib
import json
import math
import shutil
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / 'art/models/raw/I07_ice_freezer_20261024'
LIBRARY = ROOT / 'art/library/appliances'
EVIDENCE = ROOT / 'evidence/visual_rework_20261024/freezer'


def linear(hex_color):
    values = [int(hex_color[i:i+2], 16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in values)


def material(name, color, roughness=.6, alpha=1):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*linear(color), alpha)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*linear(color), 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Alpha'].default_value = alpha
    bsdf.inputs['Specular IOR Level'].default_value = .22
    if alpha < 1:
        mat.surface_render_method = 'BLENDED'
    return mat


def finish(obj, name, mat):
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def bevel_box(name, size, location, mat, radius=.008, segments=3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    finish(obj, name, mat)
    if radius:
        mod = obj.modifiers.new('Manufactured rounded edge', 'BEVEL')
        mod.width = radius
        mod.segments = segments
        bpy.ops.object.modifier_apply(modifier=mod.name)
        normal = obj.modifiers.new('Broad planar panels', 'WEIGHTED_NORMAL')
        normal.keep_sharp = True
        bpy.ops.object.modifier_apply(modifier=normal.name)
    return obj


def cylinder(name, radius, depth, location, mat, radius_bottom=None, rotation=(0,0,0)):
    bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=radius if radius_bottom is None else radius_bottom,
                                   radius2=radius, depth=depth, location=location, rotation=rotation)
    obj = finish(bpy.context.object, name, mat)
    for face in obj.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    return obj


def tube(name, points, mat, radius=.004):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    curve.resolution_u = 1
    line = curve.splines.new('POLY')
    line.points.add(len(points)-1)
    for point, coord in zip(line.points, points):
        point.co = (*coord, 1)
    obj = bpy.data.objects.new(name,curve)
    bpy.context.collection.objects.link(obj)
    curve.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj.select_set(False)
    return obj


def join(name, parts):
    bpy.ops.object.select_all(action='DESELECT')
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = parts[0]
    obj.name = name
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    return obj


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for folder in [RAW, LIBRARY/'authoring', LIBRARY/'source', EVIDENCE]:
        folder.mkdir(parents=True, exist_ok=True)
    paint = material('freezer_white','ecefe7',.55)
    blue = material('freezer_band','79a9b7',.55)
    trim = material('freezer_trim','b5c4c6',.4)
    liner = material('freezer_liner','dce9e3',.77)
    seal = material('freezer_seal','566e73',.85)
    dark = material('castor','3e4c50',.8)
    glass = material('freezer_glass','a9d5dc',.26,.08)
    cream = material('package_cream','fff4d6',.85)
    strawberry = material('package_strawberry','d78591',.85)
    matcha = material('package_matcha','a2bd84',.85)
    citrus = material('package_citrus','f0c871',.85)
    cocoa = material('package_cocoa','b28e77',.85)
    paper = material('package_paper','f6f0da',.9)
    colors = [strawberry,matcha,citrus,cocoa]

    # Five shell panels leave the top open. The cabinet is never a full solid cube.
    shell = [bevel_box('FrontPanel',(1.30,.045,.70),(0,-.3375,.425),paint,.017,4),
             bevel_box('RearPanel',(1.30,.045,.70),(0,.3375,.425),paint,.017,4),
             bevel_box('LeftPanel',(.05,.65,.70),(-.625,0,.425),paint,.014,4),
             bevel_box('RightPanel',(.05,.65,.70),(.625,0,.425),paint,.014,4),
             bevel_box('CompressorBase',(1.23,.65,.31),(0,0,.235),paint,.018,4)]
    join('CabinetShell',shell)
    join('CabinetBand',[
        bevel_box('BandFront',(1.26,.008,.070),(0,-.361,.397),blue,.003),
        bevel_box('BandLeft',(.008,.65,.070),(-.652,0,.397),blue,.003),
        bevel_box('BandRight',(.008,.65,.070),(.652,0,.397),blue,.003)])
    # The inner well is 38 cm below the glass; stock sits on basket floors.
    join('InnerWell',[
        bevel_box('WellFloor',(1.194,.605,.035),(0,0,.4225),liner,.012),
        bevel_box('WellFront',(1.194,.025,.34),(0,-.2975,.610),liner,.008),
        bevel_box('WellBack',(1.194,.025,.34),(0,.2975,.610),liner,.008),
        bevel_box('WellLeft',(.025,.57,.34),(-.585,0,.610),liner,.008),
        bevel_box('WellRight',(.025,.57,.34),(.585,0,.610),liner,.008)])
    join('InsulatedTopRim',[
        bevel_box('RimFront',(1.30,.06,.042),(0,-.33,.797),paint,.011,4),
        bevel_box('RimBack',(1.30,.06,.042),(0,.33,.797),paint,.011,4),
        bevel_box('RimLeft',(.06,.60,.042),(-.62,0,.797),paint,.011,4),
        bevel_box('RimRight',(.06,.60,.042),(.62,0,.797),paint,.011,4)])
    # The long tracks support two independently raised sliding frames.
    for y in [-.302,.302]:
        bevel_box('LidTrack',(1.24,.019,.025),(0,y,.822),seal,.004)
    for index,(x,z) in enumerate([(-.305,.833),(.305,.848)]):
        frame = []
        for y in [-.294,.294]:
            frame.append(bevel_box('LongLidRail',(.61,.025,.023),(x,y,z),trim,.005,4))
        for end in [-.293,.293]:
            frame.append(bevel_box('ShortLidRail',(.024,.564,.023),(x+end,0,z),trim,.005,4))
        join(f'SlidingFrame_{index}',frame)
        # A single two-sided pane avoids a second transparent layer tinting the products.
        mesh = bpy.data.meshes.new(f'SlidingGlass_{index}')
        mesh.from_pydata([(x-.281,-.281,z),(x+.281,-.281,z),(x+.281,.281,z),(x-.281,.281,z)],[],[(0,1,2,3)])
        pane = bpy.data.objects.new(f'SlidingGlass_{index}',mesh)
        bpy.context.collection.objects.link(pane)
        mesh.materials.append(glass)
        tube(f'LidHandle_{index}',[(x-.07,-.263,z+.012),(x-.07,-.263,z+.035),
                                  (x-.063,-.263,z+.041),(x+.063,-.263,z+.041),
                                  (x+.07,-.263,z+.035),(x+.07,-.263,z+.012)],trim,.007)

    # Four removable wire baskets, with a clear central aisle exposing the cavity depth.
    for basket_id,(cx,cy) in enumerate([(-.305,-.151),(-.305,.151),(.305,-.151),(.305,.151)]):
        basket=[]
        lx,rx=cx-.273,cx+.273
        fy,by=cy-.123,cy+.123
        for z in [.493,.686]:
            basket.append(tube('BasketRim',[(lx,fy,z),(rx,fy,z),(rx,by,z),(lx,by,z),(lx,fy,z)],trim,.003))
        for x in [lx+.045*i for i in range(13)]:
            if x>rx:continue
            basket.append(tube('BasketWire',[(x,fy,.686),(x,fy,.493),(x,by,.493),(x,by,.686)],trim,.0018))
        for y in [fy+.046*i for i in range(6)]:
            basket.append(tube('BasketWire',[(lx,y,.686),(lx,y,.493),(rx,y,.493),(rx,y,.686)],trim,.0018))
        join(f'StockBasket_{basket_id}',basket)

    # Individual sealed ice-cream cups and wrapped bars have depth, silhouette and gaps.
    product_index=0
    for row,cy in enumerate([-.151,.151]):
        for column,cx in enumerate([-.49,-.305,-.12]):
            color=colors[(column+row)%len(colors)]
            parts=[cylinder('PaperCup',.067,.107,(cx,cy,.5525),paper,radius_bottom=.050),
                   cylinder('LidLip',.072,.011,(cx,cy,.6115),paper),
                   cylinder('FlavorLid',.065,.004,(cx,cy,.619),color),
                   cylinder('LidMedallion',.023,.0015,(cx,cy,.622),cream)]
            # A recessed lower band distinguishes the cup wall from the solid-colored lid.
            parts.append(cylinder('CupFootBand',.054,.014,(cx,cy,.507),color,radius_bottom=.050))
            join(f'Stock_Cup_{product_index:02}',parts)
            product_index+=1
    for row,cy in enumerate([-.151,.151]):
        for column,cx in enumerate([.095,.232,.369,.506]):
            color=colors[(column+row+1)%len(colors)]
            parts=[bevel_box('WrappedBar',(.103,.182,.066),(cx,cy,.537),color,.013,4),
                   bevel_box('WrapperLabel',(.074,.055,.002),(cx,cy,.571),paper,.004),
                   cylinder('WrapperFlavorMark',.014,.001,(cx,cy,.5725),color)]
            for end in [-1,1]:
                parts.append(bevel_box('CrimpEnd',(.105,.012,.022),(cx,cy+end*.085,.531),paper,.003))
            join(f'Stock_Bar_{product_index:02}',parts)
            product_index+=1

    # Real cooling slots on the compressor side, a power lamp, and supported casters.
    vent=[bevel_box('VentInset',(.008,.284,.144),(.653,.105,.21),seal,.008)]
    for i in range(6):
        vent.append(bevel_box('VentLouvre',(.013,.26,.010),(.661,.105,.153+i*.022),trim,.003))
    join('CompressorVent',vent)
    bevel_box('PowerLamp',(.018,.003,.013),(.538,-.364,.283),matcha,.003)
    for index,(x,y) in enumerate([(-.535,-.245),(-.535,.245),(.535,-.245),(.535,.245)]):
        parts=[cylinder('CasterTyre',.034,.034,(x,y,.034),dark,rotation=(math.pi/2,0,0)),
               cylinder('CasterAxle',.014,.040,(x,y,.034),trim,rotation=(math.pi/2,0,0)),
               bevel_box('CasterFork',(.028,.047,.045),(x,y,.066),trim,.004)]
        join(f'Caster_{index}',parts)

    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    source=RAW/'ready.glb'
    bpy.ops.wm.save_as_mainfile(filepath=str(LIBRARY/'authoring/I07_ice_freezer.blend'))
    bpy.ops.export_scene.gltf(filepath=str(source),export_format='GLB',export_yup=True,export_apply=True,
                              export_animations=False,export_image_format='AUTO',export_extras=True)
    shutil.copy2(source,LIBRARY/'source/I07_ice_freezer.glb')
    entry={'src':'../library/appliances/source/I07_ice_freezer.glb','preserve_parts':True,'preserve_origin':True,
           'level':False,'tex':1024,'image_format':'AUTO',
           'provider':'Blender authored cavity, enamel shell, wire baskets, sealed stock and sliding glass lids',
           'note':'Replaces the opaque product photograph and solid cabinet. Source and geometry audit: art/manifests/models_freezer_20261024.json'}
    (EVIDENCE/'asset_entry.json').write_text(json.dumps({'I07_ice_freezer':entry},ensure_ascii=False,indent=2)+'\n')
    # A standalone export spec lets this asset be reviewed before the shared manifest is edited.
    temporary_entry=dict(entry,src=str(source))
    (EVIDENCE/'export_spec.json').write_text(json.dumps({'out':str(ROOT/'game/assets/models'),
                                                      'assets':{'I07_ice_freezer':temporary_entry}},indent=2)+'\n')
    provenance={'model':'I07_ice_freezer','date':'2026-10-24','authoring_script':'art/tools/rebuild_ice_freezer.py',
                'reference':'evidence/visual_rework_20261024/references/01.png',
                'source':'art/library/appliances/source/I07_ice_freezer.glb',
                'authoring':'art/library/appliances/authoring/I07_ice_freezer.blend',
                'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                'material':'Original procedural geometry and flat color materials; no product photograph or emissive atlas',
                'license':'Project-authored', 'export':entry,
                'verification':'evidence/visual_rework_20261024/freezer/'}
    (ROOT/'art/manifests/models_freezer_20261024.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n')
    print('FREEZER_SOURCE',source)


if __name__ == '__main__':
    build()

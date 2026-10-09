"""Render raw provider mesh and game mesh at the same physical size/camera.

Blender -b --factory-startup -P art/tools/architecture_source_compare.py -- OUT [IDs]
Outputs albedo and clay closeups. Geometry is never exported or modified in-game.
"""
import bpy,math,json,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
out=Path(sys.argv[sys.argv.index('--')+1]);out.mkdir(parents=True,exist_ok=True)
ids=sys.argv[sys.argv.index('--')+2:] or ['H02','S06','S01']
assets=json.loads((ROOT/'art/models/game_assets.json').read_text())['assets']

for aid in ids:
    raw=ROOT/'art/models/raw'/f'{aid}_h3d_audit_20261002/model.glb' if aid!='S01' else ROOT/'art/models/raw/S01/model.glb'
    reference=json.loads((ROOT/'evidence/architecture_closeup_20261002/before/game/assets/models/_stats/_audit.json').read_text())['models'][aid]['bounds_godot']
    target_min=Vector((reference['min'][0],-reference['max'][2],reference['min'][1]))
    target_max=Vector((reference['max'][0],-reference['min'][2],reference['max'][1]))
    for variant,path in [('raw',raw),('game',ROOT/'game/assets/models'/f'{aid}.glb')]:
        bpy.ops.wm.read_factory_settings(use_empty=True);sc=bpy.context.scene
        bpy.ops.import_scene.gltf(filepath=str(path))
        obs=[o for o in sc.objects if o.type=='MESH']
        pts=[o.matrix_world@v.co for o in obs for v in o.data.vertices]
        lo=Vector([min(p[a] for p in pts) for a in range(3)]);hi=Vector([max(p[a] for p in pts) for a in range(3)])
        if variant=='raw':
            for o in obs:
                mw=o.matrix_world.copy()
                for v in o.data.vertices:
                    q=mw@v.co;v.co=Vector([target_min[a]+(q[a]-lo[a])/(hi[a]-lo[a])*(target_max[a]-target_min[a]) for a in range(3)])
                o.matrix_world.identity()
        for mat in bpy.data.materials:
            if not mat.use_nodes:continue
            bs=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
            if not bs:continue
            for name in ['Normal','Metallic','Roughness','Specular IOR Level']:
                for link in list(bs.inputs[name].links):mat.node_tree.links.remove(link)
            bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0
        world=bpy.data.worlds.new('Neutral');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.65,.72,.82,1);world.node_tree.nodes['Background'].inputs[1].default_value=.7;sc.world=world
        sun=bpy.data.objects.new('Sun',bpy.data.lights.new('Sun','SUN'));sc.collection.objects.link(sun);sun.data.energy=2;sun.rotation_euler=(.55,0,-.45)
        cam=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera'));sc.collection.objects.link(cam);sc.camera=cam
        cam.data.type='ORTHO';sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x=1280;sc.render.resolution_y=900;sc.render.resolution_percentage=100;sc.view_settings.view_transform='Standard'
        details={'H02':(Vector((1.6,-2.2,2.7)),4.8),'S06':(Vector((0,-3.7,1.6)),4.8),'S01':(Vector((-1.5,-3.1,.85)),3.8)}
        focus,size=details[aid];cam.data.ortho_scale=size;cam.location=focus+Vector((3,-6,1.6));cam.rotation_euler=(focus-cam.location).to_track_quat('-Z','Y').to_euler()
        for clay in [False,True]:
            if clay:
                mat=bpy.data.materials.new('Clay');mat.diffuse_color=(.62,.64,.68,1);mat.use_nodes=True;bs=mat.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(.62,.64,.68,1);bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0
                for o in obs:o.data.materials.clear();o.data.materials.append(mat)
            sc.render.filepath=str(out/f'{aid}_{variant}_{"clay" if clay else "albedo"}.png');bpy.ops.render.render(write_still=True)
        print('SOURCE_COMPARE',aid,variant)

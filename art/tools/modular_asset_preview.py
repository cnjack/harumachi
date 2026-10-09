"""Four fixed views of game exports, with a clay view to expose geometry.

Blender -b --factory-startup -P ... -- OUTPUT_DIRECTORY ID ...
Uses each exported metre-scale model unchanged; no reshaping or asset writes.
"""
import bpy, math, sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
args = sys.argv[sys.argv.index('--') + 1:]
out = Path(args[0]).resolve()
for aid in args[1:]:
    dest = out / aid
    dest.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / f'game/assets/models/{aid}.glb'))
    sc = bpy.context.scene
    meshes = [ob for ob in sc.objects if ob.type == 'MESH']
    pts = [ob.matrix_world @ v.co for ob in meshes for v in ob.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    centre = (lo + hi) * .5
    size = hi - lo
    world = bpy.data.worlds.new('Neutral')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (.68, .75, .85, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = .8
    sc.world = world
    sun = bpy.data.objects.new('Sun', bpy.data.lights.new('Sun', 'SUN'))
    sc.collection.objects.link(sun)
    sun.data.energy = 1.6
    sun.rotation_euler = (.65, -.25, -.6)
    cam = bpy.data.objects.new('Camera', bpy.data.cameras.new('Camera'))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = max(size) * 1.55
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x = 960
    sc.render.resolution_y = 800
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        bs = mat.node_tree.nodes.get('Principled BSDF')
        if bs:
            bs.inputs['Roughness'].default_value = 1
            bs.inputs['Specular IOR Level'].default_value = 0
    clay = bpy.data.materials.new('Clay')
    clay.diffuse_color = (.57, .61, .69, 1)
    backups = {ob.name: list(ob.data.materials) for ob in meshes}
    for name, direction in [('front', (0, -1, .42)), ('back', (0, 1, .42)), ('oblique', (1, -1, .6)), ('clay', (1, -1, .6))]:
        if name == 'clay':
            for ob in meshes:
                ob.data.materials.clear()
                ob.data.materials.append(clay)
        cam.location = centre + Vector(direction).normalized() * size.length * 2
        cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = str(dest / f'{name}.png')
        bpy.ops.render.render(write_still=True)
    print('PREVIEWED', aid, tuple(size), flush=True)

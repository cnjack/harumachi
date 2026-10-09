import bpy, sys, math, os
from mathutils import Vector, geometry
argv = sys.argv[sys.argv.index("--")+1:]
outdir = argv[0]; names = argv[1:]
MD = None
for name in names:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=name); name = os.path.basename(os.path.dirname(name)) if os.path.basename(name)=='model.glb' else os.path.splitext(os.path.basename(name))[0]
    objs = [o for o in sc.objects if o.type == 'MESH']
    mn = Vector((1e9,)*3); mx = Vector((-1e9,)*3)
    npoly = 0; pts = []
    for o in objs:
        npoly += len(o.data.polygons)
        mw = o.matrix_world
        vs = o.data.vertices
        step = max(1, len(vs) // 20000)
        for i in range(0, len(vs), step):
            w = mw @ vs[i].co; pts.append((w.x, w.y))
        for c in o.bound_box:
            w = mw @ Vector(c)
            mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
    ang = math.degrees(geometry.box_fit_2d(pts))
    mats = [(m.name, [n.type for n in m.node_tree.nodes]) for o in objs for m in o.data.materials]
    ctr = (mn + mx) / 2; r = (mx - mn).length / 2
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.8, 0.85, 0.9, 1)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')); sc.collection.objects.link(sun)
    sun.data.energy = 3; sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    sc.render.engine = 'BLENDER_EEVEE'; sc.render.resolution_x = 360; sc.render.resolution_y = 360
    sc.eevee.taa_render_samples = 8; sc.view_settings.view_transform = 'Standard'
    dirs = [Vector((0,-1,0.35)), Vector((1,0,0.35)), Vector((0,1,0.35)), Vector((-1,0,0.35)), Vector((0.01,-0.2,1))]
    for i, d in enumerate(dirs):
        d = d.normalized()
        cam.location = ctr + d * r * 2.9
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = f"{outdir}/{name}_{i}.png"
        bpy.ops.render.render(write_still=True)
    print("BBOX", name, npoly, "boxfit_deg", round(ang, 1), tuple(round(x,3) for x in mn), tuple(round(x,3) for x in mx))
    print("MATS", name, mats)

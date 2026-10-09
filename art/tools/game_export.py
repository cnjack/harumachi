"""Headless Blender: turn generated GLBs into game-ready GLBs for Godot.

Blender -b --factory-startup -P game_export.py -- <specs.json> [ID ...]

Per asset: import -> join -> level (stand it on its base) -> yaw fix (facade to -Y, i.e. +Z
in Godot) -> scale to real size -> trim baked ground skirt -> origin at base centre ->
decimate -> smooth by angle -> resize texture -> matte material -> export GLB (JPEG
textures) + stats in <out>/_stats/<ID>.json
"""
import bpy, bmesh, sys, os, json, math, subprocess, tempfile
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from level_util import support_plane, level_matrix, mesh_coords  # noqa: E402

# "level": "auto" (default) stands the model on its biggest downward hull face when that face
# covers at least this share of the footprint; thin-stemmed crops, hanging lanterns and
# characters have no real base and stay as built. true/false force it either way.
LEVEL_MIN_BASE = 0.15
LEVEL_MIN_DEG = 1.0

# Python with pymeshlab, for "rebake" assets (Pixal3D): decimate freely, then bake the texture onto new UVs
MESHLAB_PY = os.environ.get("MESHLAB_PY", "/Users/jack/.copilot/session-state/ca10e179-b441-4d77-b938-250cea2ee4c6/files/venv/bin/python")
HERE = os.path.dirname(os.path.abspath(__file__))


def fill_holes(img):
    """v0.6: every texel the bake did not reach (between UV islands, or where a ray missed the
    original surface) is filled from its surroundings with a push-pull pyramid, so no black seams
    show up through mipmaps and no dark holes stay on the model."""
    import numpy as np
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb, m = px[..., :3].copy(), (px[..., 3] > 0.5).astype(np.float32)
    levels = []
    c, a = rgb * m[..., None], m
    while min(c.shape[0], c.shape[1]) > 1:
        levels.append((c, a))
        hh, ww = c.shape[0] // 2, c.shape[1] // 2
        c = c[:hh * 2, :ww * 2].reshape(hh, 2, ww, 2, 3).sum(axis=(1, 3))
        a = a[:hh * 2, :ww * 2].reshape(hh, 2, ww, 2).sum(axis=(1, 3))
    fill = c / np.maximum(a, 1e-6)[..., None]
    for c, a in reversed(levels):
        up = np.repeat(np.repeat(fill, 2, axis=0), 2, axis=1)[:c.shape[0], :c.shape[1]]
        own = c / np.maximum(a, 1e-6)[..., None]
        fill = np.where((a > 0)[..., None], own, up)
    out = np.where(m[..., None] > 0, rgb, fill)
    px[..., :3] = out
    px[..., 3] = 1.0
    img.pixels[:] = px.reshape(-1)
    img.alpha_mode = "NONE"
    print("FILL holes %.1f%%" % (100.0 * (1.0 - m.mean())))


def rebake(ob, target, tex, uv_margin=0.004, pixel_margin=8):
    """Dense scan-like meshes stall Blender's decimator: hand the geometry to meshlab, then bake the
    original texture onto the low mesh with fresh UVs (Cycles, colour only, no lighting)."""
    tmp = tempfile.mkdtemp()
    hi_obj, lo_obj = os.path.join(tmp, "hi.obj"), os.path.join(tmp, "lo.obj")
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.wm.obj_export(filepath=hi_obj, export_selected_objects=True, export_uv=False, export_normals=False,
                          export_materials=False, export_triangulated_mesh=True, forward_axis="Y", up_axis="Z")
    r = subprocess.run([MESHLAB_PY, os.path.join(HERE, "meshlab_decimate.py"), hi_obj, lo_obj, str(target)], capture_output=True, text=True)
    print(r.stdout.strip(), r.stderr.strip()[-300:])
    bpy.ops.wm.obj_import(filepath=lo_obj, forward_axis="Y", up_axis="Z")
    lo = [o for o in bpy.context.selected_objects if o.type == "MESH"][0]
    bpy.ops.object.select_all(action="DESELECT")
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=uv_margin)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new(ob.name + "_baked", tex, tex, alpha=True)
    img.generated_color = (0.0, 0.0, 0.0, 0.0)
    m = bpy.data.materials.new(ob.name + "_baked")
    m.use_nodes = True
    nt = m.node_tree
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = img
    bsdf = nt.nodes["Principled BSDF"]
    nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    nt.nodes.active = tn
    lo.data.materials.clear()
    lo.data.materials.append(m)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 1
    sc.cycles.device = "CPU"
    bk = sc.render.bake
    bk.use_selected_to_active = True
    dims = max(ob.dimensions)
    bk.cage_extrusion = 0.02 * dims
    bk.max_ray_distance = 0.08 * dims
    bk.margin = pixel_margin
    ob.select_set(True)
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    fill_holes(img)
    img.pack()
    bpy.data.objects.remove(ob)
    lo.name = "model"
    return lo

argv = sys.argv[sys.argv.index("--") + 1:]
SPEC_PATH = argv[0]
ONLY = set(argv[1:])
spec_all = json.load(open(SPEC_PATH))
BASE = os.path.dirname(os.path.abspath(SPEC_PATH))
OUT = os.path.join(BASE, spec_all["out"])
os.makedirs(os.path.join(OUT, "_stats"), exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def bbox(objs):
    mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
    return mn, mx


def process(aid, s):
    if s.get("preserve_rigged_character"):
        export_rigged_character(aid, s)
        return
    if s.get("preserve_parts"):
        export_preserved(aid, s)
        return
    reset()
    src = os.path.join(BASE, s["src"])
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in bpy.context.scene.objects:
        o.select_set(o.type == 'MESH')
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    for o in list(bpy.context.scene.objects):
        if o != ob:
            bpy.data.objects.remove(o)
    ob.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = ob.data
    # Pixal3D rebuilds in the reference picture's camera frame; pictures shot from above come
    # out leaning back by the camera elevation (10-30 deg). Level on the standing face.
    lv = s.get("level", "auto")
    lean0, frac0, leveled = 0.0, 0.0, False
    if lv:
        support_points = mesh_coords(me)
        # Organic crowns can dominate the convex hull. For an isolated pot/vase
        # reference, measure its explicitly configured basal region instead.
        basal_fraction = s.get("level_base_fraction", 1.0)
        if basal_fraction < 1.0:
            floor_z = support_points[:, 2].min()
            height_z = support_points[:, 2].max() - floor_z
            support_points = support_points[support_points[:, 2] < floor_z + height_z * basal_fraction]
        n, lean0, area, foot = support_plane(support_points)
        frac0 = area / foot if foot else 0.0
        if lean0 >= LEVEL_MIN_DEG and (lv is True or frac0 >= LEVEL_MIN_BASE):
            me.transform(level_matrix(n))
            leveled = True
        print("LEVEL %s lean %.2f deg base %.2f -> %s" % (aid, lean0, frac0, "levelled" if leveled else "kept"))
    # optional extra axis-angle correction [ax, ay, az, deg], applied after levelling
    tilt = s.get("tilt")
    if tilt:
        axis = Vector(tilt[:3]).normalized()
        me.transform(Matrix.Rotation(math.radians(tilt[3]), 4, axis))
    yaw = math.radians(s.get("yaw", 0))
    if yaw:
        me.transform(Matrix.Rotation(yaw, 4, 'Z'))
    mn, mx = bbox([ob])
    dims = mx - mn
    fit = s.get("fit", "h")
    ref = {"h": dims.z, "w": dims.x, "d": dims.y, "max": max(dims)}[fit]
    k = s["size"] / ref
    me.transform(Matrix.Scale(k, 4))
    mn, mx = bbox([ob])
    # move base centre to origin
    me.transform(Matrix.Translation(Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))))
    H_full = (mx - mn).z
    bm = bmesh.new(); bm.from_mesh(me)
    trim = s.get("trim", 0.0)
    if trim > 0:
        h = (mx - mn).z
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, trim * h), plane_no=(0, 0, 1), clear_inner=True)
    cut = s.get("cut_above")
    if cut:
        h = (mx - mn).z
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, cut * h), plane_no=(0, 0, 1), clear_outer=True)
    # weld UV-seam splits first so islands are real geometric pieces, not texture charts
    # (weld 0 = skip: welding Rodin foliage creates non-manifold fans that stall the decimator)
    if s.get("weld", 0.0005) > 0:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=s.get("weld", 0.0005) * s["size"])
    ci = s.get("clear_inside")  # [fx, fy, zfrac]: delete faces inside the inner rect above zfrac*H
    if ci:
        hx = (mx.x - mn.x) / 2 * ci[0]; hy = (mx.y - mn.y) / 2 * ci[1]; zc = H_full * ci[2]
        dead = [f for f in bm.faces if (lambda c: abs(c.x) < hx and abs(c.y) < hy and c.z > zc)(f.calc_center_median())]
        bmesh.ops.delete(bm, geom=dead, context='FACES')
    mi = s.get("min_island", 0.0)
    if mi > 0:
        bm.faces.ensure_lookup_table()
        islands = []
        seen = set()
        for f in bm.faces:
            if f.index in seen:
                continue
            stack = [f]; isl = []
            seen.add(f.index)
            while stack:
                c = stack.pop(); isl.append(c)
                for e in c.edges:
                    for g in e.link_faces:
                        if g.index not in seen:
                            seen.add(g.index); stack.append(g)
            islands.append(isl)
        if islands:
            big = max(len(i) for i in islands)
            kill = [f for i in islands if len(i) < big * mi for f in i]
            if kill:
                bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.to_mesh(me); bm.free()
    if not s.get("keep_origin"):
        mn, mx = bbox([ob])
        me.transform(Matrix.Translation(Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))))
    tris0 = sum(len(p.vertices) - 2 for p in me.polygons)
    target = s.get("tris", 10000)
    if s.get("rebake") and tris0 > target * 1.1:
        ob = rebake(ob, target, s.get("tex", 1024), s.get("rebake_uv_margin", 0.004), s.get("rebake_pixel_margin", 8))
        me = ob.data
    # foliage meshes (thousands of open leaf patches) stall after one collapse pass, so repeat
    for _ in range(5):
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        if tris <= target * 1.1:
            break
        mod = ob.modifiers.new("dec", 'DECIMATE')
        mod.ratio = target / tris
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(s.get("smooth", 35)))
    except Exception:
        bpy.ops.object.shade_smooth()
    tex = s.get("tex", 1024)
    for mat in me.materials:
        if not mat or not mat.use_nodes:
            continue
        for n in mat.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image:
                img = n.image
                if max(img.size) > tex:
                    img.scale(tex, tex)
                img.pack()
            if n.type == 'BSDF_PRINCIPLED':
                # Linked ORM/normal maps override default_value. Remove their
                # links before setting the anime material; scalar assignment
                # alone exported metallic reflections on 39 older models.
                for socket_name in ('Metallic', 'Roughness', 'Normal', 'Specular IOR Level', 'Specular'):
                    if socket_name in n.inputs:
                        for link in list(n.inputs[socket_name].links):
                            mat.node_tree.links.remove(link)
                n.inputs['Metallic'].default_value = 0.0
                n.inputs['Roughness'].default_value = 0.92
                for nm in ("Specular IOR Level", "Specular"):
                    if nm in n.inputs:
                        n.inputs[nm].default_value = 0.25
                        break
        mat.name = f"M_{aid}"
    # optional soil plane (empty planter variant)
    if s.get("soil"):
        sx, sy, sz = s["soil"]  # fractions of bbox width/depth; z as fraction of the uncut height
        mn, mx = bbox([ob])
        d = mx - mn
        bpy.ops.mesh.primitive_plane_add(size=1)
        pl = bpy.context.active_object
        pl.scale = (d.x * sx, d.y * sy, 1)
        pl.location = ((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, H_full * sz)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        sm = bpy.data.materials.new("M_soil")
        sm.use_nodes = True
        b = sm.node_tree.nodes.get("Principled BSDF")
        b.inputs['Base Color'].default_value = (0.20, 0.12, 0.07, 1)
        b.inputs['Roughness'].default_value = 1.0
        pl.data.materials.append(sm)
        pl.select_set(True); ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.join()
        me = ob.data
    ob.name = aid
    me.name = aid
    # Replacement landmarks retain their established collision footprint and origin.
    # Apply this after decimation, which can slightly alter the extreme vertices.
    physical = s.get("fit_bounds_blender")
    if physical:
        # A decimator can leave loose extreme vertices. glTF discards them, so
        # fitting against them would make the actual exported mesh undersized.
        physical_mesh = bmesh.new()
        physical_mesh.from_mesh(me)
        loose_vertices = [vertex for vertex in physical_mesh.verts if not vertex.link_faces]
        if loose_vertices:
            bmesh.ops.delete(physical_mesh, geom=loose_vertices, context='VERTS')
            physical_mesh.to_mesh(me)
        physical_mesh.free()
        source_min, source_max = bbox([ob])
        source_size = source_max - source_min
        target_min = Vector(physical["min"])
        target_max = Vector(physical["max"])
        target_size = target_max - target_min
        for vertex in me.vertices:
            vertex.co = Vector([target_min[axis] + (vertex.co[axis] - source_min[axis])
                                / source_size[axis] * target_size[axis] for axis in range(3)])
        me.update()
    mn, mx = bbox([ob])
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    _, lean1, area1, foot1 = support_plane(mesh_coords(me))
    out = os.path.join(OUT, f"{aid}.glb")
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_image_format='JPEG', export_jpeg_quality=88,
                              export_animations=False, export_extras=False)
    st = {"id": aid, "src": s["src"], "provider": s.get("provider", "hunyuan hy-3d-3.1"),
          "tris_src": tris0, "tris": tris, "size_m": [round(v, 3) for v in (mx - mn)],
          "godot_size_m_xyz": [round((mx - mn).x, 3), round((mx - mn).z, 3), round((mx - mn).y, 3)],
          "tex": tex, "bytes": os.path.getsize(out), "yaw_fix": s.get("yaw", 0),
          "level": lv, "lean_src_deg": round(lean0, 2), "levelled": leveled,
          "lean_deg": round(lean1, 2), "base_frac": round(area1 / foot1, 3) if foot1 else 0.0}
    if physical:
        st["fit_bounds_blender"] = physical
    json.dump(st, open(os.path.join(OUT, "_stats", f"{aid}.json"), "w"), indent=1)
    print("EXPORTED", json.dumps(st, ensure_ascii=False))


def export_rigged_character(aid, s):
    """A character pipeline output is already fitted and animated; keep its skin and morphs."""
    import shutil, struct, hashlib
    src = os.path.join(BASE, s["src"])
    raw = open(src, "rb").read()
    length = struct.unpack_from("<I", raw, 12)[0]
    data = json.loads(raw[20:20 + length])
    clips = [animation.get("name", "") for animation in data.get("animations", [])]
    required = {"idle", "walk", "run", "wave", "bow", "look", "stretch", "tend", "talk", "cheer", "dance"}
    if not required.issubset(clips) or not data.get("skins"):
        raise RuntimeError("Character source must contain its rig and all original actions: " + aid)
    out = os.path.join(OUT, aid + ".glb")
    if os.path.abspath(src) != os.path.abspath(out):
        shutil.copy2(src, out)
    tris = sum(data["accessors"][primitive["indices"]]["count"] // 3 for mesh in data.get("meshes", []) for primitive in mesh["primitives"])
    stats = {"id": aid, "src": s["src"], "provider": s.get("provider"),
             "preserve_rigged_character": True, "tris": tris, "bytes": len(raw),
             "bones": len(data["skins"][0]["joints"]), "animations": clips,
             "sha256": hashlib.sha256(raw).hexdigest(), "character_pipeline": s.get("character_pipeline")}
    json.dump(stats, open(os.path.join(OUT, "_stats", aid + ".json"), "w"), ensure_ascii=False, indent=1)
    print("EXPORTED_RIGGED_CHARACTER", json.dumps(stats, ensure_ascii=False))


def export_preserved(aid, s):
    """Material-only upgrades keep node names, physical origin and collision deck geometry."""
    reset()
    bpy.ops.import_scene.gltf(filepath=os.path.join(BASE, s["src"]))
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    mn, mx = bbox(meshes)
    tris = sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type == 'BSDF_PRINCIPLED':
                node.inputs['Metallic'].default_value = 0
                node.inputs['Roughness'].default_value = 1
                if 'Specular IOR Level' in node.inputs:
                    node.inputs['Specular IOR Level'].default_value = 0
            elif node.type == 'TEX_IMAGE' and node.image:
                image = node.image
                limit = s.get('tex', 2048)
                if max(image.size) > limit:
                    ratio = limit / max(image.size)
                    image.scale(max(1,round(image.size[0]*ratio)),max(1,round(image.size[1]*ratio)))
                image.pack()
    out = os.path.join(OUT, aid + '.glb')
    bpy.ops.export_scene.gltf(filepath=out,export_format='GLB',export_yup=True,export_apply=True,
                              export_animations=False,export_image_format=s.get('image_format','JPEG'),export_jpeg_quality=92)
    size = mx-mn
    stats = {'id':aid,'src':s['src'],'provider':s.get('provider'),'preserve_parts':True,
             'origin_preserved':True,'tris':tris,'tex':s.get('tex',2048),'bytes':os.path.getsize(out),
             'godot_size_m_xyz':[round(size.x,4),round(size.z,4),round(size.y,4)],
             'mesh_nodes':sorted(o.name for o in meshes)}
    json.dump(stats,open(os.path.join(OUT,'_stats',aid+'.json'),'w'),indent=1)
    print('EXPORTED_PRESERVED',json.dumps(stats,ensure_ascii=False))


for aid, s in spec_all["assets"].items():
    if ONLY and aid not in ONLY:
        continue
    try:
        process(aid, s)
    except Exception as e:
        import traceback; traceback.print_exc()
        print("FAILED", aid, e)

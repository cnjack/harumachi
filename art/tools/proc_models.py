"""Headless Blender: procedural props that are easier to build than to generate.

Blender -b --factory-startup -P proc_models.py -- <out_dir> [name ...]

Stylised low-poly models with flat base-colour materials (the game's toon lighting does the rest):
  P_bridge        arched wooden footbridge, 10 m bank to bank, railings and stone abutments; the walkable
                  deck is a separate mesh named "deck" so Godot can build a trimesh collider from it
  P_signpost      wooden post with three arrow boards (Godot writes the text with Label3D)
  P_farm_gate     entrance arch for the allotment: two posts, a crossbeam, a little roof, lanterns
  P_yagura        bon-odori tower: platform on four posts, red-and-white skirt, railing, roof, ladder
  P_toro          floating paper lantern on a wooden base (glowing paper)
  P_long_table    festival table with a white cloth
  P_chest         wooden storage chest with iron bands (v0.6: superseded by a Pixal3D trunk, see game_assets.json;
                  build it explicitly with `-- <out> P_chest` if the fallback is wanted)
  P_offer_stand   tsukimi offering stand (sanbō) with a plate
v0.6 lanterns (washi textures from art/tools/lantern_textures.py):
  P_chochin_red / P_chochin_white / P_chochin_bon   ribbed paper lanterns: a lathe body that dips
                  between 22 bamboo rings, black lacquer rims with a gold line, a wire bail; the paper
                  is textured and emissive, the ink stays dark
  P_toro          (v2) framed tōrō: wooden base with feet, corner posts, top frame, four painted panels,
                  a candle and flame inside
  P_farm_gate     (v2) now hangs two white 晴 chochin instead of red spheres
v0.6 model review (Pixal3D turns glass and steel into grey blobs, so these are built here):
  I03_drink_fridge  glass-door drinks fridge, 0.76 x 0.7 x 1.92 m: white cabinet, lit header, the door is a
                    textured pane (art/references/v06/tex/fridge_front.png, codex) that glows a little
  I07_ice_freezer   ice-cream chest freezer, 1.3 x 0.72 x 0.86 m: white body with a blue band, the glass top
                    shows art/references/v06/tex/freezer_top.png, two sliding-lid frames and castors
"""
import bpy, bmesh, sys, os, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
ONLY = set(argv[1:])
os.makedirs(OUT, exist_ok=True)

MATS = {}


def mat(name, rgb, rough=0.85, emit=0.0):
    key = (name, rgb, emit)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    MATS[key] = m
    return m


def srgb(h):
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


WOOD = lambda: mat("wood", srgb("8a5f3e"))
WOOD_D = lambda: mat("wood_dark", srgb("5e3f2a"))
WOOD_L = lambda: mat("wood_light", srgb("b98a5c"))
STONE = lambda: mat("stone", srgb("9a958a"), 0.95)
RED = lambda: mat("red", srgb("c23b2e"))
WHITE = lambda: mat("cloth", srgb("f2eee4"))
IRON = lambda: mat("iron", srgb("3a3a3e"), 0.6)
PAPER = lambda: mat("paper_glow", srgb("ffe2a8"), 0.9, 2.5)
ROOF = lambda: mat("roof", srgb("4a5561"), 0.7)


TEX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "references", "v06", "lanterns")


def tex_mat(name, img, emit=1.6, rough=0.9):
    """Paper: the image drives base colour and emission, so ink lines stay dark when it glows."""
    key = ("tex", name, img, emit)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(os.path.abspath(os.path.join(TEX, img)))
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(t.outputs["Color"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = emit
    b.inputs["Roughness"].default_value = rough
    MATS[key] = m
    return m


def lathe(name, profile, rows, segs, m, u_offset=0.0):
    """Surface of revolution around Z. profile(t) -> (radius, z) for t in 0..1; UV u = angle, v = t."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    grid = []
    for j in range(rows + 1):
        t = j / rows
        r, z = profile(t)
        ring = []
        for i in range(segs + 1):
            a = 2 * math.pi * i / segs
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        grid.append(ring)
    for j in range(rows):
        for i in range(segs):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for lp, (ii, jj) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                lp[uv].uv = (ii / segs + u_offset, jj / rows)   # the texture repeats past 1.0
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    me.materials.append(m)
    for poly in me.polygons:
        poly.use_smooth = True
    return o


LACQUER = lambda: mat("lacquer", srgb("1d1916"), 0.35)
GOLD = lambda: mat("gold_line", srgb("c8a24a"), 0.4)


def chochin_parts(img, H=0.42, R=0.15, z0=0.0, prefix="c"):
    """A hanging chochin whose bail top sits at z0 + H + ~0.07; the body spans z0..z0+H."""
    ribs = 22
    def prof(t):
        body = 0.64 + 0.36 * math.sin(math.pi * t) ** 0.75
        sag = 1.0 - 0.035 * math.sin(math.pi * ((t * ribs) % 1.0)) ** 2
        return R * body * sag, z0 + H * t
    p = [lathe(prefix + "paper", prof, ribs * 2, 20, tex_mat("paper_" + img, img))]
    rr = R * 0.66
    for k, z in ((0, z0 - 0.012), (1, z0 + H + 0.012)):
        p.append(cyl(f"{prefix}rim{k}", rr, 0.045, (0, 0, z), LACQUER(), 24))
        p.append(cyl(f"{prefix}gold{k}", rr * 1.02, 0.008, (0, 0, z + (0.018 if k else -0.018)), GOLD(), 24))
    p.append(cyl(prefix + "cap", rr * 0.55, 0.03, (0, 0, z0 + H + 0.05), LACQUER(), 16))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.035, minor_radius=0.006, location=(0, 0, z0 + H + 0.095),
                                     rotation=(math.pi / 2, 0, 0), major_segments=16, minor_segments=6)
    t = bpy.context.active_object
    t.name = prefix + "bail"
    t.data.materials.append(IRON())
    p.append(t)
    p.append(cyl(prefix + "tassel", 0.012, 0.05, (0, 0, z0 - 0.06), LACQUER(), 8))
    return p


def chochin(name, img, H=0.42, R=0.15):
    # origin at the hook, so Godot can hang it from a cord point
    p = chochin_parts(img, H, R, z0=-(H + 0.1))
    join(p, name)
    export(name)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


def box(name, size, loc, m, rot=(0, 0, 0), parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(m)
    return o


def cyl(name, r, h, loc, m, verts=10, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(m)
    return o


def sphere(name, r, loc, m, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=r, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(m)
    return o


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def export(name):
    bpy.ops.object.select_all(action="SELECT")
    for o in bpy.context.selected_objects:
        if o.type == "MESH":
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.shade_flat()
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False, export_yup=True,
                              export_apply=True, export_materials="EXPORT")
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH")
    print("PROC", name, "tris", tris, os.path.getsize(path))


# ------------------------------------------------------------------ bridge
def bridge():
    L, W, RISE = 10.0, 1.9, 0.85       # along Blender Y (-> Godot Z), rise at the middle
    N = 26
    def hgt(y):
        t = y / (L / 2)
        return RISE * (1 - t * t)
    planks = []
    for i in range(N):
        y0 = -L / 2 + L * i / N
        y1 = y0 + L / N * 0.92
        yc = (y0 + y1) / 2
        slope = -2 * RISE * yc / (L / 2) ** 2
        a = math.atan(slope)
        planks.append(box(f"plank{i}", (W, (y1 - y0) / math.cos(a), 0.07), (0, yc, hgt(yc) + 0.035), WOOD_L() if i % 3 else WOOD(), rot=(a, 0, 0)))
    join(planks, "planks")
    # walkable deck (hidden in Godot, used for collision): a smooth strip
    bm = bmesh.new()
    S = 40
    for i in range(S + 1):
        y = -L / 2 - 0.2 + (L + 0.4) * i / S
        z = hgt(max(-L / 2, min(L / 2, y))) + 0.07
        bm.verts.new((-W / 2, y, z))
        bm.verts.new((W / 2, y, z))
    bm.verts.ensure_lookup_table()
    for i in range(S):
        a, b, c, d = bm.verts[2 * i], bm.verts[2 * i + 1], bm.verts[2 * i + 3], bm.verts[2 * i + 2]
        bm.faces.new((a, b, c, d))
    me = bpy.data.meshes.new("deck")
    bm.to_mesh(me)
    deck = bpy.data.objects.new("deck", me)
    bpy.context.scene.collection.objects.link(deck)
    deck.data.materials.append(WOOD())
    # beams under the deck
    beams = []
    for x in (-W / 2 + 0.15, W / 2 - 0.15):
        for i in range(12):
            y0 = -L / 2 + L * i / 12
            y1 = y0 + L / 12
            yc = (y0 + y1) / 2
            a = math.atan(-2 * RISE * yc / (L / 2) ** 2)
            beams.append(box(f"beam{x}{i}", (0.14, L / 12 / math.cos(a) + 0.02, 0.2), (x, yc, hgt(yc) - 0.1), WOOD_D(), rot=(a, 0, 0)))
    join(beams, "beams")
    # railings: posts and a curved handrail on both sides
    rail = []
    for side in (-1, 1):
        x = side * (W / 2 - 0.05)
        for i in range(11):
            y = -L / 2 + 0.3 + (L - 0.6) * i / 10
            rail.append(box(f"post{side}{i}", (0.1, 0.1, 0.95), (x, y, hgt(y) + 0.5), WOOD_D()))
        for i in range(20):
            y0 = -L / 2 + 0.3 + (L - 0.6) * i / 20
            y1 = y0 + (L - 0.6) / 20
            yc = (y0 + y1) / 2
            a = math.atan(-2 * RISE * yc / (L / 2) ** 2)
            rail.append(box(f"rail{side}{i}", (0.09, (y1 - y0) / math.cos(a) + 0.02, 0.07), (x, yc, hgt(yc) + 0.98), WOOD(), rot=(a, 0, 0)))
            rail.append(box(f"mid{side}{i}", (0.05, (y1 - y0) / math.cos(a) + 0.02, 0.05), (x, yc, hgt(yc) + 0.55), WOOD(), rot=(a, 0, 0)))
    join(rail, "railings")
    # stone abutments and legs in the water
    st = []
    for y in (-L / 2 + 0.3, L / 2 - 0.3):
        st.append(box(f"abut{y}", (W + 0.6, 0.9, 1.3), (0, y, -0.55), STONE()))
    for y in (-2.2, 2.2):
        for x in (-W / 2 + 0.15, W / 2 - 0.15):
            st.append(cyl(f"leg{x}{y}", 0.1, 2.2, (x, y, hgt(y) - 1.2), WOOD_D()))
    join(st, "abutments")
    export("P_bridge")


def signpost():
    parts = [cyl("post", 0.07, 2.4, (0, 0, 1.2), WOOD_D(), 8), box("cap", (0.2, 0.2, 0.06), (0, 0, 2.43), WOOD_D())]
    for i, (z, yaw) in enumerate(((2.0, 0), (1.6, 180), (1.2, 25))):
        a = math.radians(yaw)
        c, s = math.cos(a), math.sin(a)
        # board with a pointed end, pointing along +X rotated by yaw around Z
        bm = bmesh.new()
        pts = [(0.05, -0.16), (0.95, -0.16), (1.15, 0.0), (0.95, 0.16), (0.05, 0.16)]
        top = [bm.verts.new((x * c, x * s, z + y)) for x, y in pts]
        bm.faces.new(top)
        me = bpy.data.meshes.new(f"board{i}")
        bm.to_mesh(me)
        o = bpy.data.objects.new(f"board{i}", me)
        bpy.context.scene.collection.objects.link(o)
        o.data.materials.append(WOOD_L())
        mod = o.modifiers.new("s", "SOLIDIFY")
        mod.thickness = 0.05
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        parts.append(o)
    join(parts, "signpost")
    export("P_signpost")


def farm_gate():
    p = []
    for x in (-1.9, 1.9):
        p.append(box(f"post{x}", (0.24, 0.24, 3.1), (x, 0, 1.55), WOOD_D()))
        p.append(box(f"foot{x}", (0.4, 0.4, 0.2), (x, 0, 0.1), STONE()))
    p.append(box("beam", (4.6, 0.26, 0.26), (0, 0, 3.0), WOOD()))
    p.append(box("beam2", (4.1, 0.18, 0.18), (0, 0, 2.55), WOOD()))
    p.append(box("board", (1.6, 0.08, 0.5), (0, 0.0, 2.78), WOOD_L()))
    # little gable roof
    for s in (-1, 1):
        p.append(box(f"roof{s}", (4.9, 0.62, 0.06), (0, s * 0.22, 3.28), ROOF(), rot=(s * math.radians(28), 0, 0)))
    for x in (-1.5, 1.5):
        p.append(cyl(f"cord{x}", 0.01, 0.12, (x, 0, 2.42), IRON(), 4))
        parts = chochin_parts("chochin_white.png", 0.44, 0.16, z0=1.86, prefix=f"g{x}")
        for o in parts:
            o.location.x += x
        p += parts
    join(p, "gate")
    export("P_farm_gate")


def yagura():
    p = []
    S, H = 3.0, 2.1
    for x in (-S / 2, S / 2):
        for y in (-S / 2, S / 2):
            p.append(box(f"leg{x}{y}", (0.16, 0.16, H + 1.6), (x, y, (H + 1.6) / 2), WOOD_D()))
    p.append(box("floor", (S + 0.3, S + 0.3, 0.14), (0, 0, H), WOOD()))
    # red and white skirt below the floor (vertical stripes)
    for side in range(4):
        for i in range(10):
            t = -S / 2 + S * (i + 0.5) / 10
            m = RED() if i % 2 == 0 else WHITE()
            if side == 0:
                p.append(box(f"sk{side}{i}", (S / 10, 0.03, H - 0.3), (t, -S / 2 - 0.16, (H - 0.3) / 2 + 0.3), m))
            elif side == 1:
                p.append(box(f"sk{side}{i}", (S / 10, 0.03, H - 0.3), (t, S / 2 + 0.16, (H - 0.3) / 2 + 0.3), m))
            elif side == 2:
                p.append(box(f"sk{side}{i}", (0.03, S / 10, H - 0.3), (-S / 2 - 0.16, t, (H - 0.3) / 2 + 0.3), m))
            else:
                p.append(box(f"sk{side}{i}", (0.03, S / 10, H - 0.3), (S / 2 + 0.16, t, (H - 0.3) / 2 + 0.3), m))
    for side in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        if side[0] == 0:
            p.append(box(f"rail{side}", (S, 0.08, 0.08), (0, side[1] * S / 2, H + 0.75), WOOD()))
        else:
            p.append(box(f"rail{side}", (0.08, S, 0.08), (side[0] * S / 2, 0, H + 0.75), WOOD()))
    p.append(box("roof", (S + 0.8, S + 0.8, 0.12), (0, 0, H + 1.65), ROOF()))
    p.append(box("roof2", (S * 0.6, S * 0.6, 0.35), (0, 0, H + 1.85), ROOF()))
    # ladder on the south (-Y) side
    for x in (-0.3, 0.3):
        p.append(box(f"lrail{x}", (0.06, 0.06, 2.4), (x, -S / 2 - 0.55, 1.05), WOOD_L(), rot=(math.radians(-18), 0, 0)))
    for i in range(6):
        z = 0.25 + i * 0.35
        p.append(box(f"rung{i}", (0.6, 0.05, 0.05), (0, -S / 2 - 0.9 + i * 0.11, z), WOOD_L()))
    join(p, "yagura")
    export("P_yagura")


def toro():
    p = [box("base", (0.36, 0.36, 0.045), (0, 0, 0.045), WOOD_L())]
    for x in (-0.15, 0.15):
        for y in (-0.15, 0.15):
            p.append(box(f"foot{x}{y}", (0.05, 0.05, 0.025), (x, y, 0.012), WOOD_D()))
            p.append(box(f"post{x}{y}", (0.02, 0.02, 0.3), (x * 0.88, y * 0.88, 0.22), WOOD_D()))
    for k, (sx, sy, x, y) in enumerate(((0.3, 0.02, 0, -0.132), (0.3, 0.02, 0, 0.132), (0.02, 0.3, -0.132, 0), (0.02, 0.3, 0.132, 0))):
        p.append(box(f"topbar{k}", (sx, sy, 0.02), (x, y, 0.37), WOOD_D()))
        p.append(box(f"midbar{k}", (sx, sy, 0.012), (x, y, 0.08), WOOD_D()))
    # four painted panels, each quad mapped to one quarter of the panel strip
    paper = tex_mat("toro_paper", "toro_panels.png", 1.8)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    h0, h1, e = 0.085, 0.365, 0.128
    corners = [(-e, -e), (e, -e), (e, e), (-e, e)]
    for k in range(4):
        (x0, y0), (x1, y1) = corners[k], corners[(k + 1) % 4]
        vs = [bm.verts.new((x0, y0, h0)), bm.verts.new((x1, y1, h0)), bm.verts.new((x1, y1, h1)), bm.verts.new((x0, y0, h1))]
        f = bm.faces.new(vs)
        for lp, uv in zip(f.loops, ((k / 4, 0), ((k + 1) / 4, 0), ((k + 1) / 4, 1), (k / 4, 1))):
            lp[uvl].uv = uv
    me = bpy.data.meshes.new("panels")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("panels", me)
    bpy.context.collection.objects.link(o)
    me.materials.append(paper)
    p.append(o)
    p.append(cyl("candle", 0.018, 0.07, (0, 0, 0.1), WHITE(), 10))
    p.append(sphere("flame", 0.016, (0, 0, 0.155), mat("flame", srgb("ffd27a"), 0.5, 6.0), (1, 1, 1.8)))
    join(p, "toro")
    export("P_toro")


def gondola():
    """Double-sided shop shelf, long axis along X, four shelf levels whose tops sit at 0.14/0.48/0.82/1.16 m
    (InteriorBuilder._stock_gondolas places the goods at exactly these heights)."""
    metal = mat("shelf_cream", srgb("efe8d8"), 0.5)
    rail = mat("price_rail", srgb("9fc3d8"), 0.5)
    p = [box("plinth", (1.8, 0.6, 0.1), (0, 0, 0.05), metal), box("back", (1.76, 0.03, 1.42), (0, 0, 0.79), metal)]
    for lv in (0.14, 0.48, 0.82, 1.16):
        for sd in (-1, 1):
            p.append(box(f"shelf{lv}{sd}", (1.74, 0.28, 0.025), (0, sd * 0.16, lv - 0.0125), metal))
            p.append(box(f"rail{lv}{sd}", (1.74, 0.012, 0.035), (0, sd * 0.3, lv - 0.02), rail))
    for x in (-0.9, 0.9):
        p.append(box(f"end{x}", (0.04, 0.62, 1.52), (x, 0, 0.76), WOOD_L()))
    p.append(box("header", (1.84, 0.12, 0.1), (0, 0, 1.55), WOOD_L()))
    join(p, "gondola")
    export("P_gondola")


def deck_oven():
    """Two-deck bakery oven, 1.4 x 0.85 x 1.75 m, front faces -Y (Godot +Z)."""
    steel = mat("steel", srgb("c9ccd1"), 0.35)
    dark = mat("steel_dark", srgb("5b6068"), 0.4)
    glow = mat("oven_glow", srgb("ff9a3c"), 0.6, 3.0)
    black = mat("knob", srgb("1e1e22"), 0.5)
    red = mat("display", srgb("ff4a3a"), 0.5, 2.0)
    p = []
    for x in (-0.64, 0.64):
        for y in (-0.36, 0.36):
            p.append(box(f"leg{x}{y}", (0.05, 0.05, 0.55), (x, y, 0.275), dark))
    p.append(box("lowshelf", (1.34, 0.76, 0.03), (0, 0, 0.14), dark))
    for k, z0 in enumerate((0.55, 1.05)):
        p.append(box(f"deck{k}", (1.4, 0.85, 0.48), (0, 0, z0 + 0.24), steel))
        p.append(box(f"door{k}", (1.0, 0.03, 0.36), (-0.12, -0.44, z0 + 0.24), steel))
        p.append(box(f"win{k}", (0.78, 0.02, 0.2), (-0.12, -0.46, z0 + 0.25), glow))
        for r in range(3):
            p.append(box(f"rack{k}{r}", (0.76, 0.005, 0.008), (-0.12, -0.472, z0 + 0.18 + r * 0.06), dark))
        p.append(box(f"handle{k}", (0.8, 0.04, 0.03), (-0.12, -0.49, z0 + 0.42), dark))
        p.append(box(f"panel{k}", (0.24, 0.02, 0.36), (0.55, -0.44, z0 + 0.24), dark))
        for q in range(2):
            p.append(cyl(f"knob{k}{q}", 0.03, 0.03, (0.55, -0.465, z0 + 0.16 + q * 0.1), black, 12, rot=(math.pi / 2, 0, 0)))
        p.append(box(f"disp{k}", (0.12, 0.01, 0.05), (0.55, -0.46, z0 + 0.36), red))
    p.append(box("hood", (1.46, 0.95, 0.12), (0, -0.03, 1.62), steel))
    p.append(box("hood2", (1.1, 0.7, 0.1), (0, 0.0, 1.73), steel))
    p.append(cyl("pipe", 0.07, 0.3, (0.4, 0.2, 1.93), dark, 12))
    join(p, "oven")
    export("P_deck_oven")


def long_table():
    p = [box("top", (3.2, 0.9, 0.06), (0, 0, 0.75), WOOD()), box("cloth", (3.3, 1.0, 0.02), (0, 0, 0.79), WHITE())]
    for s in (-1, 1):
        p.append(box(f"skirt{s}", (3.3, 0.02, 0.5), (0, s * 0.5, 0.55), WHITE()))
    for x in (-1.4, 1.4):
        for y in (-0.35, 0.35):
            p.append(box(f"leg{x}{y}", (0.07, 0.07, 0.75), (x, y, 0.375), WOOD_D()))
    join(p, "table")
    export("P_long_table")


def chest():
    p = [box("body", (0.9, 0.55, 0.45), (0, 0, 0.26), WOOD()), box("lid", (0.94, 0.59, 0.12), (0, 0, 0.54), WOOD_L())]
    for x in (-0.3, 0.3):
        p.append(box(f"band{x}", (0.06, 0.6, 0.6), (x, 0, 0.3), IRON()))
    p.append(box("lock", (0.1, 0.04, 0.12), (0, -0.3, 0.42), mat("brass", srgb("c9a243"), 0.5)))
    join(p, "chest")
    export("P_chest")


TEXDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "references", "v06", "tex")


def pane_mat(name, img, emit, size):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    im = bpy.data.images.load(os.path.abspath(os.path.join(TEXDIR, img)))
    im.scale(*size)
    t.image = im
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(t.outputs["Color"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = emit
    b.inputs["Roughness"].default_value = 0.25
    return m


def pane(name, w, h, loc, m, facing):
    """Textured plane with UVs 0..1. facing '-Y' (a front, Godot +Z) or '+Z' (a top)."""
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc, rotation=((math.pi / 2, 0, 0) if facing == "-Y" else (0, 0, 0)))
    o = bpy.context.active_object
    o.name = name
    o.scale = (w, h, 1)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(m)
    return o


def drink_fridge():
    W, D, H = 0.76, 0.7, 1.92
    white = mat("fridge_white", srgb("f1f3f4"), 0.4)
    trim = mat("fridge_trim", srgb("c9d3da"), 0.35)
    grille = mat("grille", srgb("3b4046"), 0.6)
    header = mat("header_glow", srgb("9fd8f2"), 0.5, 1.4)
    p = [box("side_l", (0.05, D, H), (-W / 2 + 0.025, 0, H / 2), white), box("side_r", (0.05, D, H), (W / 2 - 0.025, 0, H / 2), white),
         box("top", (W, D, 0.08), (0, 0, H - 0.04), white), box("base", (W, D, 0.16), (0, 0, 0.08), white),
         box("back", (W - 0.1, 0.04, H - 0.24), (0, D / 2 - 0.02, H / 2), white),
         box("header", (W - 0.1, 0.02, 0.12), (0, -D / 2 - 0.005, H - 0.14), header),
         box("grille", (W - 0.14, 0.02, 0.08), (0, -D / 2 - 0.005, 0.08), grille)]
    # the door: a frame round the lit pane, handle on the right
    fz0, fz1 = 0.18, H - 0.22
    p += [box("fr_l", (0.04, 0.03, fz1 - fz0), (-W / 2 + 0.07, -D / 2 - 0.01, (fz0 + fz1) / 2), trim),
          box("fr_r", (0.04, 0.03, fz1 - fz0), (W / 2 - 0.07, -D / 2 - 0.01, (fz0 + fz1) / 2), trim),
          box("fr_t", (W - 0.1, 0.03, 0.04), (0, -D / 2 - 0.01, fz1), trim), box("fr_b", (W - 0.1, 0.03, 0.04), (0, -D / 2 - 0.01, fz0), trim),
          box("handle", (0.025, 0.05, 0.7), (W / 2 - 0.1, -D / 2 - 0.045, H * 0.55), trim)]
    p.append(pane("glass", W - 0.18, fz1 - fz0 - 0.04, (0, -D / 2 + 0.005, (fz0 + fz1) / 2), pane_mat("drinks", "fridge_front.png", 0.55, (384, 768)), "-Y"))
    join(p, "fridge")
    export("I03_drink_fridge")


def ice_freezer():
    W, D, H = 1.3, 0.72, 0.86
    white = mat("freezer_white", srgb("f3f4f2"), 0.4)
    band = mat("freezer_band", srgb("6fa3d6"), 0.5)
    trim = mat("freezer_trim", srgb("c5cfd6"), 0.35)
    dark = mat("castor", srgb("33363b"), 0.6)
    p = [box("body", (W, D, H - 0.1), (0, 0, 0.06 + (H - 0.1) / 2), white),
         box("band_f", (W + 0.004, 0.01, 0.1), (0, -D / 2 - 0.002, 0.44), band),
         box("band_s1", (0.01, D + 0.004, 0.1), (-W / 2 - 0.002, 0, 0.44), band),
         box("band_s2", (0.01, D + 0.004, 0.1), (W / 2 + 0.002, 0, 0.44), band),
         box("grille", (0.02, 0.3, 0.16), (W / 2 + 0.006, 0.12, 0.2), dark)]
    top = H - 0.04
    p += [box("rim_f", (W, 0.06, 0.05), (0, -D / 2 + 0.03, top), trim), box("rim_b", (W, 0.06, 0.05), (0, D / 2 - 0.03, top), trim),
          box("rim_l", (0.06, D, 0.05), (-W / 2 + 0.03, 0, top), trim), box("rim_r", (0.06, D, 0.05), (W / 2 - 0.03, 0, top), trim),
          box("lid_bar", (0.03, D - 0.1, 0.03), (0.02, 0, top + 0.035), trim),
          box("lid_h1", (0.16, 0.03, 0.025), (-0.3, -D / 2 + 0.09, top + 0.03), trim),
          box("lid_h2", (0.16, 0.03, 0.025), (0.34, -D / 2 + 0.09, top + 0.03), trim)]
    p.append(pane("glass", W - 0.12, D - 0.12, (0, 0, top + 0.012), pane_mat("icecream", "freezer_top.png", 0.45, (768, 384)), "+Z"))
    for x in (-W / 2 + 0.1, W / 2 - 0.1):
        for y in (-D / 2 + 0.1, D / 2 - 0.1):
            p.append(cyl(f"castor{x}{y}", 0.04, 0.05, (x, y, 0.035), dark, 10, rot=(0, math.pi / 2, 0)))
    join(p, "freezer")
    export("I07_ice_freezer")


def offer_stand():
    p = [box("stand", (0.5, 0.5, 0.35), (0, 0, 0.18), WOOD_L()), box("tray", (0.6, 0.6, 0.05), (0, 0, 0.38), WOOD())]
    for i, (x, y, z) in enumerate(((0, 0, 0.5), (-0.07, -0.07, 0.44), (0.07, -0.07, 0.44), (-0.07, 0.07, 0.44), (0.07, 0.07, 0.44))):
        p.append(sphere(f"dango{i}", 0.07, (x, y, z), WHITE()))
    join(p, "offer")
    export("P_offer_stand")


BUILD = {"P_bridge": bridge, "P_signpost": signpost, "P_farm_gate": farm_gate, "P_yagura": yagura,
         "P_toro": toro, "P_long_table": long_table, "P_gondola": gondola, "P_deck_oven": deck_oven, "P_offer_stand": offer_stand,
         "I03_drink_fridge": drink_fridge, "I07_ice_freezer": ice_freezer,
         "P_chochin_red": lambda: chochin("P_chochin_red", "chochin_red.png"),
         "P_chochin_white": lambda: chochin("P_chochin_white", "chochin_white.png"),
         "P_chochin_bon": lambda: chochin("P_chochin_bon", "chochin_bon.png", 0.5, 0.17)}
if "P_chest" in ONLY:
    BUILD["P_chest"] = chest
for n, fn in BUILD.items():
    if ONLY and n not in ONLY:
        continue
    reset()
    fn()

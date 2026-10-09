"""Headless Blender: add a simple humanoid rig + walk/idle loops to a static A-pose character.

Blender -b --factory-startup -P rig_char.py -- <in.glb> <out.glb> [preview_dir]

The mesh comes from Hunyuan (single mesh, +Z up, faces -Y, feet at z=0, A-pose).
Joints are placed from body proportions and the measured hand position, weights come from
Blender's heat (automatic) weighting, and all animation rotations are authored around
armature-space axes, then converted into each bone's local frame.
"""
import bpy, sys, os, math
from mathutils import Vector, Quaternion, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = argv[0], argv[1]
PREV = argv[2] if len(argv) > 2 else None

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
mesh = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
for o in list(bpy.context.scene.objects):
    if o is not mesh and o.type != 'MESH':
        bpy.data.objects.remove(o)
mesh.parent = None
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

vs = [v.co.copy() for v in mesh.data.vertices]
H = max(v.z for v in vs)


def side_pts(sign, zlo, zhi):
    return [v for v in vs if zlo <= v.z <= zhi and v.x * sign > 0]


# hands: outermost vertices on each side (A-pose)
hands = {}
for s in (1, -1):
    cand = [v for v in vs if v.x * s > 0 and 0.3 * H < v.z < 0.75 * H]
    tip = max(cand, key=lambda v: v.x * s)
    near = [v for v in cand if (v - tip).length < 0.06 * H]
    c = sum(near, Vector()) / len(near)
    hands[s] = c
# legs: centre of each leg at knee height
legs = {}
for s in (1, -1):
    pts = side_pts(s, 0.26 * H, 0.30 * H)
    pts = [v for v in pts if abs(v.x) < 0.14 * H]
    legs[s] = sum((Vector((v.x, v.y, 0)) for v in pts), Vector()) / max(1, len(pts))

hip_z, knee_z, ankle_z = 0.50 * H, 0.27 * H, 0.055 * H
sh_z = 0.815 * H
yc = sum(v.y for v in vs) / len(vs)

J = {
    "hips": Vector((0, yc, hip_z)), "spine": Vector((0, yc, 0.60 * H)), "chest": Vector((0, yc, 0.70 * H)),
    "neck": Vector((0, yc, 0.82 * H)), "head": Vector((0, yc, 0.86 * H)), "head_end": Vector((0, yc, H)),
}
for s, n in ((1, "L"), (-1, "R")):
    lx = legs[s].x
    J["thigh." + n] = Vector((lx * 0.9, yc, hip_z))
    J["shin." + n] = Vector((lx, legs[s].y, knee_z))
    J["foot." + n] = Vector((lx, legs[s].y, ankle_z))
    J["toe." + n] = Vector((lx, legs[s].y - 0.09 * H, 0.01 * H))
    shoulder = Vector((s * 0.105 * H, yc, sh_z))
    hand = hands[s]
    wrist = shoulder.lerp(hand, 0.86)
    J["clav." + n] = Vector((s * 0.03 * H, yc, 0.8 * H))
    J["upper." + n] = shoulder
    J["fore." + n] = shoulder.lerp(wrist, 0.5) + Vector((0, 0.012 * H, 0))
    J["hand." + n] = wrist
    J["hand_end." + n] = hand + (hand - wrist).normalized() * 0.03 * H

arm_data = bpy.data.armatures.new("Rig")
arm = bpy.data.objects.new("Rig", arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
eb = arm_data.edit_bones


def bone(name, head, tail, parent=None, connect=False):
    b = eb.new(name)
    b.head, b.tail = head, tail
    b.roll = 0.0
    if parent:
        b.parent = eb[parent]
        b.use_connect = connect
    return b


bone("hips", J["hips"], J["spine"])
bone("spine", J["spine"], J["chest"], "hips", True)
bone("chest", J["chest"], J["neck"], "spine", True)
bone("neck", J["neck"], J["head"], "chest", True)
bone("head", J["head"], J["head_end"], "neck", True)
for n in ("L", "R"):
    bone("thigh." + n, J["thigh." + n], J["shin." + n], "hips")
    bone("shin." + n, J["shin." + n], J["foot." + n], "thigh." + n, True)
    bone("foot." + n, J["foot." + n], J["toe." + n], "shin." + n, True)
    bone("clav." + n, J["clav." + n], J["upper." + n], "chest")
    bone("upper." + n, J["upper." + n], J["fore." + n], "clav." + n, True)
    bone("fore." + n, J["fore." + n], J["hand." + n], "upper." + n, True)
    bone("hand." + n, J["hand." + n], J["hand_end." + n], "fore." + n, True)
bpy.ops.object.mode_set(mode='OBJECT')

# ------------------------------------------------------------------ weights
# Heat weighting fails on these single-shell generated meshes, so weights are computed here:
# legs are split left/right with a soft band in the middle (skirts and wide trousers do not tear),
# loose cloth far from the leg axis follows the pelvis more than the thigh, and the thigh tops
# blend into the hips so the crotch does not pinch.
bpy.ops.object.select_all(action='DESELECT')
mesh.select_set(True)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type='ARMATURE_NAME')

SEG = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in arm_data.bones}
LEG = {n: ["thigh." + n, "shin." + n, "foot." + n] for n in ("L", "R")}
ARM = [p + "." + n for n in ("L", "R") for p in ("upper", "fore", "hand")]
UPPER = [n for n in SEG if n not in LEG["L"] + LEG["R"]]


def seg_d(p, name):
    a, b = SEG[name]
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (a + ab * t - p).length


def nearest(p, names, k=2, pw=4.0):
    ds = sorted((seg_d(p, n), n) for n in names)[:k]
    ws = [(1.0 / max(d, 1e-4) ** pw, n) for d, n in ds]
    tot = sum(w for w, _ in ws)
    return {n: w / tot for w, n in ws}


def sstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


lx_ref = max(0.02 * H, (abs(legs[1].x) + abs(legs[-1].x)) / 2)
groups = {n: (mesh.vertex_groups.get(n) or mesh.vertex_groups.new(name=n)) for n in SEG}
for v in mesh.data.vertices:
    p = v.co
    w = {}
    if p.z < hip_z + 0.03 * H:
        d_arm = min(seg_d(p, n) for n in ARM)
        d_leg = min(seg_d(p, n) for n in LEG["L"] + LEG["R"])
        if d_arm < 0.8 * d_leg:
            w = nearest(p, ARM + ["chest", "spine"])
        else:
            u = p.x / lx_ref
            side = {"L": sstep(-0.45, 0.45, u)}
            side["R"] = 1.0 - side["L"]
            hip_w = sstep(hip_z - 0.10 * H, hip_z + 0.03 * H, p.z)
            d_own = min(seg_d(p, n) for n in LEG["L" if u >= 0 else "R"][:2])
            loose = 0.55 * sstep(0.075 * H, 0.14 * H, d_own) * sstep(knee_z - 0.02 * H, knee_z + 0.08 * H, p.z)
            hip_w = 1.0 - (1.0 - hip_w) * (1.0 - loose)
            w["hips"] = hip_w
            for n in ("L", "R"):
                if side[n] < 1e-3:
                    continue
                for bn, bw in nearest(p, LEG[n]).items():
                    w[bn] = w.get(bn, 0.0) + (1.0 - hip_w) * side[n] * bw
    else:
        w = nearest(p, UPPER)
    for bn, bw in w.items():
        if bw > 1e-3:
            groups[bn].add([v.index], bw, 'REPLACE')
print("RIG weights done", len(mesh.data.vertices), "verts")


# ------------------------------------------------------------------ v0.7.3: cut the arms free
# The generated meshes are one closed shell, and in their narrow A-pose the inner side of each arm is
# welded to the side of the body (shirt, apron, cardigan) from the armpit down. Weights cannot help:
# raising an arm stretches the welded faces into a sheet of cloth. So below the armpit, rip the seam
# between arm faces and body faces, give each side pure weights, and close both openings with a cap
# (hidden against each other at rest, seen only when the arm is lifted).
ARMPIT_Z = sh_z - 0.06 * H
SPECK = 40      # arm/body islands smaller than this many faces are merged into their surroundings


def _loops_of(edges):
    """Order boundary edges into chains. Returns lists of verts (closed chains repeat nothing)."""
    nb = {}
    for e in edges:
        a, b = e.verts
        nb.setdefault(a, []).append(b)
        nb.setdefault(b, []).append(a)
    seen = set()
    chains = []
    starts = [v for v in nb if len(nb[v]) == 1] + list(nb)
    for s in starts:
        if s in seen:
            continue
        chain = [s]
        seen.add(s)
        cur = s
        while True:
            nxt = [u for u in nb[cur] if u not in seen]
            if not nxt:
                break
            cur = nxt[0]
            seen.add(cur)
            chain.append(cur)
        if len(chain) >= 3:
            chains.append(chain)
    return chains


def _cap(bm, chain, outward, uvl, src_faces):
    """Triangulate the polygon closed by `chain` (projected on its best-fit plane)."""
    import numpy as np
    from mathutils import geometry
    P = np.array([v.co[:] for v in chain])
    c = P.mean(0)
    _, _, vt = np.linalg.svd(P - c)
    u_ax, v_ax = vt[0], vt[1]
    pts = [Vector(((p - c) @ u_ax, (p - c) @ v_ax)) for p in P]
    out = geometry.delaunay_2d_cdt(pts, [], [list(range(len(pts)))], 1, 1e-6, True)
    verts_out, _, faces_out, orig_verts = out[0], out[1], out[2], out[3]
    made = 0
    for f in faces_out:
        ids = []
        for k in f:
            o = orig_verts[k]
            if not o:
                break
            ids.append(o[0])
        if len(ids) != 3 or len(set(ids)) != 3:
            continue
        vs = [chain[i] for i in ids]
        n = (vs[1].co - vs[0].co).cross(vs[2].co - vs[0].co)
        if n.length < 1e-12:
            continue
        if n.dot(outward) < 0:
            vs = [vs[0], vs[2], vs[1]]
        try:
            nf = bm.faces.new(vs)
        except ValueError:
            continue
        ref = src_faces.get(vs[0])
        if ref is not None:
            nf.material_index = ref.material_index
        for lp in nf.loops:
            rf = src_faces.get(lp.vert)
            if rf is not None and uvl is not None:
                for rl in rf.loops:
                    if rl.vert == lp.vert:
                        lp[uvl].uv = rl[uvl].uv
                        break
        made += 1
    return made


def separate_arms():
    import bmesh
    me = mesh.data
    bm = bmesh.new()
    bm.from_mesh(me)
    dl = bm.verts.layers.deform.verify()
    uvl = bm.loops.layers.uv.active
    gi = {n: mesh.vertex_groups[n].index for n in SEG}
    torso_ids = [gi[n] for n in ("chest", "spine", "hips")]
    for side in ("L", "R"):
        s = 1 if side == "L" else -1
        ids = [gi[p + "." + side] for p in ("upper", "fore", "hand")]
        share = {v: sum(v[dl].get(i, 0.0) for i in ids) for v in bm.verts}
        # the arm is a tube: measure each bone's radius (the lower quartile of its arm vertices'
        # distance from the bone axis; cloth beside the arm inflates anything higher). On the side
        # facing the body only 1.5x that radius counts as arm (an apron or cardigan pressed against the
        # arm stays on the body); outwards cuffs and fingers may reach further.
        bones = [p + "." + side for p in ("upper", "fore", "hand")]
        FLOOR = {"upper": (0.035, 0.06), "fore": (0.032, 0.07), "hand": (0.045, 0.065)}
        CEIL = (0.05, 0.085)     # a sleeve is never thicker than this; beyond it is draped cloth
        rad = {}
        for bn in bones:
            a0, b0 = SEG[bn]
            ab = b0 - a0
            ds = [seg_d(v.co, bn) for v in bm.verts if share[v] >= 0.5
                  and 0.15 < (v.co - a0).dot(ab) / ab.length_squared < 0.85]
            ds.sort()
            q = ds[len(ds) // 4] if ds else 0.03 * H
            lo, hi = FLOOR[bn.split(".")[0]]
            rad[bn] = (min(max(q * 1.5, lo * H), CEIL[0] * H), min(max(q * 2.4, hi * H), CEIL[1] * H))

        def near_arm(f):
            c = f.calc_center_median()
            for bn in bones:
                a0, b0 = SEG[bn]
                ab = b0 - a0
                if bn.startswith("hand"):
                    ab = ab * 1.8      # the hand bone stops at the knuckles; fingers hang below
                t = max(0.0, min(1.0, (c - a0).dot(ab) / ab.length_squared))
                o = c - (a0 + ab * t)
                inward = -s * o.x > 0.5 * o.length
                if o.length <= rad[bn][0 if inward else 1]:
                    return True
            return False
        cls = {f: sum(share[v] for v in f.verts) / len(f.verts) >= 0.5 and near_arm(f) for f in bm.faces}
        # merge specks so the seam is two clean lines instead of a ragged patchwork
        for _ in range(2):
            seen = set()
            for f0 in bm.faces:
                if f0 in seen:
                    continue
                comp, stack = [f0], [f0]
                seen.add(f0)
                while stack:
                    f = stack.pop()
                    for e in f.edges:
                        for g in e.link_faces:
                            if g not in seen and cls[g] == cls[f0]:
                                seen.add(g)
                                stack.append(g)
                                comp.append(g)
                if len(comp) < SPECK:
                    for f in comp:
                        cls[f] = not cls[f]
        old_boundary = {e for e in bm.edges if e.is_boundary}
        # rip: every vertex below the armpit that touches both arm and body faces gets a twin for
        # the arm faces (edge splitting alone leaves vertices joined where the seam meets one of
        # the mesh's own holes)
        mixed = [v for v in bm.verts if v.co.z < ARMPIT_Z and len({cls[f] for f in v.link_faces}) == 2]
        if not mixed:
            continue
        twin = {v: bm.verts.new(v.co, v) for v in mixed}
        for f in {f for v in mixed for f in v.link_faces if cls[f]}:
            uvs = [lp[uvl].uv.copy() for lp in f.loops] if uvl else []
            try:
                nf = bm.faces.new([twin.get(v, v) for v in f.verts], f)
            except ValueError:
                continue
            for lp, uv in zip(nf.loops, uvs):
                lp[uvl].uv = uv
            cls[nf] = True
            bm.faces.remove(f)
        seam = mixed
        # pure weights on each side of the cut
        for v in bm.verts:
            if v.co.z >= ARMPIT_Z or not v.link_faces:
                continue
            sides = {cls.get(f, False) for f in v.link_faces}
            if len(sides) != 1:
                continue
            on_arm = sides.pop()
            d = v[dl]
            keep = {k: w for k, w in d.items() if (k in ids) == on_arm}
            if not keep:
                pool = ids if on_arm else torso_ids
                keep = {min(pool, key=lambda k: seg_d(v.co, mesh.vertex_groups[k].name)): 1.0}
            tot = sum(keep.values())
            if tot <= 0:
                continue
            for k in list(d.keys()):
                del d[k]
            for k, w in keep.items():
                d[k] = w / tot
        new_b = [e for e in bm.edges if e.is_boundary and e not in old_boundary]
        src = {}
        for e in new_b:
            for v in e.verts:
                src.setdefault(v, e.link_faces[0])
        caps = 0
        for on_arm in (False, True):
            edges = [e for e in new_b if cls.get(e.link_faces[0], False) == on_arm]
            out = Vector((-s if on_arm else s, 0, 0))
            for chain in _loops_of(edges):
                caps += _cap(bm, chain, out, uvl, src)
        print("RIG arm %s: ripped %d seam verts below z=%.2f, capped with %d faces; radius %s" % (side, len(seam), ARMPIT_Z, caps, {k: (round(r[0] / H, 3), round(r[1] / H, 3)) for k, r in rad.items()}))
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.update()


if os.environ.get("RIG_SEPARATE_ARMS", "1") != "0":
    separate_arms()

# ------------------------------------------------------------------ animation
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
pb = arm.pose.bones
for p in pb:
    p.rotation_mode = 'QUATERNION'
X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def local_q(name, axis, deg):
    rest = arm_data.bones[name].matrix_local.to_quaternion()
    ax = rest.inverted() @ axis
    return Quaternion(ax, math.radians(deg))


def key(name, frame, *rots, loc=None):
    q = Quaternion()
    for axis, deg in rots:
        q = local_q(name, axis, deg) @ q
    pb[name].rotation_quaternion = q
    pb[name].keyframe_insert("rotation_quaternion", frame=frame)
    if loc is not None:
        pb[name].location = loc
        pb[name].keyframe_insert("location", frame=frame)


# Bring the A-pose arms down, but only until the hand hangs just outside the clothes: generated
# characters stand anywhere from 8 to 22 degrees open, and a fixed angle pushed some hands into
# their trousers. The clothes to clear are measured in the band just below the hanging hand.
RELAX_ARM = {}
for s_, n_ in ((1, "L"), (-1, "R")):
    shp = J["upper." + n_]
    hp = hands[s_]
    L_arm = math.hypot(hp.x - shp.x, hp.z - shp.z)
    a0 = math.degrees(math.atan2(abs(hp.x - shp.x), shp.z - hp.z))
    band = [abs(v.x) for v in vs if hp.z - 0.13 * H <= v.z <= hp.z - 0.07 * H and v.x * s_ > 0]
    edge = max(band) if band else abs(hp.x)
    x_goal = max(edge + 0.025 * H, abs(shp.x) + 0.02 * H)
    a_goal = math.degrees(math.asin(max(-1.0, min(1.0, (x_goal - abs(shp.x)) / L_arm))))
    RELAX_ARM[n_] = max(0.0, min(22.0, a0 - a_goal))
    print("ARM %s rest %.1f deg, clothes edge %.3f, relax %.1f deg" % (n_, a0, edge, RELAX_ARM[n_]))


def new_action(name):
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for p in pb:
        p.rotation_quaternion = Quaternion()
        p.location = Vector()
    return act


def finish(act):
    try:
        fcs = act.fcurves
    except AttributeError:
        fcs = [fc for layer in act.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
    for fc in fcs:
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
        try:
            fc.modifiers.new('CYCLES')
        except Exception:
            pass
    tr = arm.animation_data.nla_tracks.new()
    tr.name = act.name
    tr.strips.new(act.name, int(act.frame_range[0]), act)
    arm.animation_data.action = None


# ------------------------------------------------------------------ gait
# Sagittal angles per phase (0..1, left leg; right leg is +0.5). Positive = forward flexion for the
# hip, flexion for the knee, dorsiflexion (toes up) for the ankle. Values follow a normal gait curve.
L1, L2 = hip_z - knee_z, knee_z - ankle_z
PH = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]
# Frontal plane (what a camera behind or in front sees): "foot_w" is the half step width as a
# fraction of the rest leg offset, so the feet land near the midline instead of on two far-apart
# rails; "sway" shifts the pelvis over the stance foot (fraction of height); "list" drops the
# pelvis on the swing side once per step. The legs are re-aimed every key so the planted foot
# stays on its line while the pelvis moves above it.
WALK = {
    "hip":   [32, 25, 11, -4, -17, -10, 14, 30],
    "knee":  [4, 15, 7, 4, 14, 42, 60, 26],
    "ankle": [0, -6, 2, 8, 6, -16, -4, 2],
    "arm_fwd": 11, "arm_back": 20, "elbow": (-24, -6), "lean": 3, "yaw": 5, "chest_yaw": 7,
    "arm_out": 0.0, "clav": 0.0, "arm_in": 0.0,
    "foot_w": 0.48, "sway": 0.019, "list": 5.0,
}
RUN = {
    "hip":   [34, 20, 2, -16, -22, -6, 20, 36],
    "knee":  [16, 34, 22, 16, 55, 95, 80, 34],
    "ankle": [2, 10, 12, -22, -18, -6, 0, 5],
    # running arms swing from the shoulder as one bent unit: the elbow drives well behind the
    # back and the hand comes forward to chest height; the elbow stays near 85 degrees, so the
    # upper arm carries the motion instead of the forearm flapping up and down. The arms are held
    # a few degrees wider than at rest so the swinging upper arm stays clear of the torso, and the
    # upper arm turns inward on the forward swing ("arm_in") so the hand comes across in front of
    # the chest rather than rising beside the shoulder.
    "arm_fwd": 26, "arm_back": 44, "elbow": (-88, -82), "lean": 7, "yaw": 6, "chest_yaw": 12,
    "arm_out": 6.0, "clav": 4.0, "arm_in": 26.0,
    "foot_w": 0.30, "sway": 0.011, "list": 3.5,
}
HIP_X = {"L": abs(J["thigh.L"].x), "R": abs(J["thigh.R"].x)}
# long axis of each upper arm at rest: twisting about it turns the bent forearm in or out
ARM_AXIS = {n: (J["fore." + n] - J["upper." + n]).normalized() for n in ("L", "R")}
FOOT_X = {"L": abs(J["foot.L"].x), "R": abs(J["foot.R"].x)}


def leg_drop(hip, knee):
    f, k = math.radians(hip), math.radians(knee)
    return L1 * math.cos(f) + L2 * math.cos(f - k)


def leg_y(hip, knee):
    f, k = math.radians(hip), math.radians(knee)
    return -(L1 * math.sin(f) + L2 * math.sin(f - k))   # forward is -Y


def arm_loc(name, v):
    """Armature-space offset -> pose-bone location (bone local axes)."""
    return arm_data.bones[name].matrix_local.to_quaternion().inverted() @ v


def gait_action(name, G, frames):
    act = new_action(name)
    n = len(PH)
    step = frames / n
    for i in range(n + 1):
        j = i % n
        f = 1 + i * step
        jr = (j + n // 2) % n
        hl, kl, al = G["hip"][j], G["knee"][j], G["ankle"][j]
        hr, kr, ar = G["hip"][jr], G["knee"][jr], G["ankle"][jr]
        ph = PH[j] * 2 * math.pi
        s = math.sin(ph + math.pi / 2)   # +1 when the left leg is forward
        # phases 0..0.5 are left stance: pelvis over the left foot, right (swing) side drops
        lat = G["sway"] * H * math.sin(ph)
        roll = -G["list"] * math.sin(ph + 0.6)          # + = left side down (rotation about +Y)
        rr = math.radians(roll)
        tilt, drop_need = {}, []
        for side, hh, kk, sg in (("L", hl, kl, 1), ("R", hr, kr, -1)):
            D = leg_drop(hh, kk)
            target = sg * G["foot_w"] * FOOT_X[side]
            sin_t = (lat + sg * FOOT_X[side] - target) / D
            t = math.asin(max(-0.5, min(0.5, sin_t)))
            tilt[side] = t
            dz_roll = -sg * HIP_X[side] * math.sin(rr)
            drop_need.append(D * math.cos(t) - dz_roll)
        # keep the lower foot on the ground: drop the pelvis by how much the longer leg is shortened
        drop = max(drop_need) - (L1 + L2)
        tl, tr = math.degrees(tilt["L"]), math.degrees(tilt["R"])
        key("hips", f, (Z, -G["yaw"] * s), (Y, roll), loc=arm_loc("hips", Vector((lat, 0, drop))))
        key("spine", f, (X, G["lean"] * 0.5), (Y, -0.5 * roll))
        key("chest", f, (Z, G["chest_yaw"] * s), (X, G["lean"] * 0.5), (Y, -0.9 * roll))
        key("head", f, (Z, -G["chest_yaw"] * 0.5 * s), (X, -G["lean"] * 0.6), (Y, 0.4 * roll))
        key("thigh.L", f, (X, -hl), (Y, tl - roll))
        key("thigh.R", f, (X, -hr), (Y, tr - roll))
        key("shin.L", f, (X, kl))
        key("shin.R", f, (X, kr))
        key("foot.L", f, (X, -al), (Y, -tl))
        key("foot.R", f, (X, -ar), (Y, -tr))
        # arms swing against the legs: a smaller forward swing with the elbow bending, a longer
        # backward swing with the arm almost straight (positive flex = forward)
        e_fwd, e_back = G["elbow"]
        for side, fwd, sg in (("L", -s, 1), ("R", s, -1)):
            flex = (G["arm_fwd"] if fwd > 0 else G["arm_back"]) * fwd
            front = (0.5 + 0.5 * fwd) ** 1.5
            key("clav." + side, f, (Z, -sg * G["clav"] * fwd))
            key("upper." + side, f, (ARM_AXIS[side], sg * G["arm_in"] * front),
                (Y, sg * (RELAX_ARM[side] - G["arm_out"])), (X, -flex))
            key("fore." + side, f, (X, e_back + (e_fwd - e_back) * front))
    finish(act)
    # stance foot travel -> the ground speed at which this clip plays without sliding
    y0 = leg_y(G["hip"][0], G["knee"][0])
    y1 = leg_y(G["hip"][4], G["knee"][4])
    speed = abs(y1 - y0) / (0.5 * frames / 24.0)
    print("GAIT", name, "stride_speed_mps=%.3f" % speed)
    return speed


walk_speed = gait_action("walk", WALK, 22)
run_speed = gait_action("run", RUN, 16)
arm["walk_speed"] = walk_speed
arm["run_speed"] = run_speed

# idle: 48 frames, gentle breathing
act = new_action("idle")
for i, f in enumerate([1, 25, 49]):
    b = math.sin(i / 2.0 * 2 * math.pi)
    key("hips", f, (X, 0), loc=Vector((0, 0, 0)))
    key("chest", f, (X, -1.5 * (1 - abs(b))))
    key("head", f, (X, 1.0 * (1 - abs(b))), (Z, 2 * b))
    key("upper.L", f, (Y, RELAX_ARM["L"] + 1.5 * (1 - abs(b))))
    key("upper.R", f, (Y, -RELAX_ARM["R"] - 1.5 * (1 - abs(b))))
    key("fore.L", f, (X, -8))
    key("fore.R", f, (X, -8))
finish(act)

# ------------------------------------------------------------------ gestures (v0.4)
# Short clips for idle variety and reactions. Each starts and ends on the idle rest pose so it can
# blend in and out at any time. Arms raise by opening the A-pose about +/-Y (for the right arm +Y is
# up); the elbow then bends about the same Y axis, which a lateral raise leaves unchanged.
REST = {"upper.L": [(Y, RELAX_ARM["L"])], "upper.R": [(Y, -RELAX_ARM["R"])],
        "fore.L": [(X, -8)], "fore.R": [(X, -8)]}
GEST_BONES = ["hips", "spine", "chest", "neck", "head", "clav.L", "clav.R", "upper.L", "upper.R",
              "fore.L", "fore.R", "hand.L", "hand.R",
              "thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R"]


def pose_key(f, pose, hips_loc=None):
    for b in GEST_BONES:
        rots = pose.get(b, REST.get(b, []))
        if b == "hips":
            key(b, f, *rots, loc=hips_loc if hips_loc is not None else Vector())
        else:
            key(b, f, *rots)


def gesture(name, keys):
    act = new_action(name)
    for f, pose in keys:
        pose_key(f, pose)
    finish(act)


def up_r(deg, fwd=0.0):
    return [(Y, -RELAX_ARM["R"] + deg), (X, -fwd)]


def up_l(deg, fwd=0.0):
    return [(Y, RELAX_ARM["L"] - deg), (X, -fwd)]


R0 = {}
gesture("wave", [
    (1, R0),
    (8, {"upper.R": up_r(118, 10), "fore.R": [(Y, 55)], "head": [(Y, -4)], "chest": [(Y, 2)]}),
    (13, {"upper.R": up_r(122, 10), "fore.R": [(Y, 25)], "head": [(Y, -4)], "chest": [(Y, 2)]}),
    (18, {"upper.R": up_r(118, 10), "fore.R": [(Y, 60)], "head": [(Y, -4)], "chest": [(Y, 2)]}),
    (23, {"upper.R": up_r(122, 10), "fore.R": [(Y, 25)], "head": [(Y, -4)], "chest": [(Y, 2)]}),
    (28, {"upper.R": up_r(118, 10), "fore.R": [(Y, 55)], "head": [(Y, -4)], "chest": [(Y, 2)]}),
    (37, R0),
])
gesture("bow", [
    (1, R0),
    (10, {"spine": [(X, 18)], "chest": [(X, 14)], "head": [(X, 10)],
          "upper.L": [(Y, RELAX_ARM["L"] + 3), (X, -8)], "upper.R": [(Y, -RELAX_ARM["R"] - 3), (X, -8)]}),
    (20, {"spine": [(X, 20)], "chest": [(X, 15)], "head": [(X, 10)],
          "upper.L": [(Y, RELAX_ARM["L"] + 3), (X, -8)], "upper.R": [(Y, -RELAX_ARM["R"] - 3), (X, -8)]}),
    (33, R0),
])
gesture("look", [
    (1, R0),
    (14, {"head": [(Z, 38)], "neck": [(Z, 8)], "chest": [(Z, 8)]}),
    (34, {"head": [(Z, 40), (X, -4)], "neck": [(Z, 8)], "chest": [(Z, 9)]}),
    (48, {"head": [(Z, -36)], "neck": [(Z, -8)], "chest": [(Z, -8)]}),
    (66, {"head": [(Z, -38), (X, -4)], "neck": [(Z, -8)], "chest": [(Z, -9)]}),
    (80, R0),
])
gesture("stretch", [
    (1, R0),
    (16, {"upper.L": up_l(40, 95), "upper.R": up_r(40, 95), "fore.L": [(X, -20)], "fore.R": [(X, -20)],
          "chest": [(X, -6)], "head": [(X, -10)], "spine": [(X, -3)]}),
    (34, {"upper.L": up_l(46, 118), "upper.R": up_r(46, 118), "fore.L": [(X, -12)], "fore.R": [(X, -12)],
          "chest": [(X, -9)], "head": [(X, -14)], "spine": [(X, -4)]}),
    (46, {"upper.L": up_l(30, 60), "upper.R": up_r(30, 60), "fore.L": [(X, -30)], "fore.R": [(X, -30)]}),
    (60, R0),
])
TEND = {"spine": [(X, 24)], "chest": [(X, 18)], "head": [(X, 12)],
        "upper.L": [(Y, RELAX_ARM["L"] - 6), (X, -38)], "upper.R": [(Y, -RELAX_ARM["R"] + 6), (X, -38)],
        "fore.L": [(X, -35)], "fore.R": [(X, -35)]}
TEND2 = dict(TEND)
TEND2["fore.R"] = [(X, -52)]
TEND2["upper.R"] = [(Y, -RELAX_ARM["R"] + 8), (X, -44)]
TEND2["head"] = [(X, 12), (Z, 6)]
gesture("tend", [(1, TEND), (13, TEND2), (25, TEND), (37, TEND2), (49, TEND)])
TALK_A = {"fore.R": [(X, -48)], "upper.R": up_r(4, 14), "head": [(X, 3)], "chest": [(Z, -3)]}
TALK_B = {"fore.R": [(X, -60)], "upper.R": up_r(8, 20), "hand.R": [(Z, 12)], "head": [(X, -2), (Z, 3)], "chest": [(Z, -1)]}
TALK_C = {"fore.L": [(X, -42)], "upper.L": up_l(4, 12), "fore.R": [(X, -30)], "head": [(X, 2), (Z, -3)], "chest": [(Z, 3)]}
gesture("talk", [(1, TALK_A), (13, TALK_B), (25, TALK_A), (37, TALK_C), (49, TALK_A)])
gesture("cheer", [
    (1, R0),
    (7, {"upper.L": up_l(55, 120), "upper.R": up_r(55, 120), "fore.L": [(X, -25)], "fore.R": [(X, -25)], "head": [(X, -8)]}),
    (12, {"upper.L": up_l(35, 70), "upper.R": up_r(35, 70), "fore.L": [(X, -60)], "fore.R": [(X, -60)]}, ),
    (17, {"upper.L": up_l(55, 125), "upper.R": up_r(55, 125), "fore.L": [(X, -25)], "fore.R": [(X, -25)], "head": [(X, -8)]}),
    (30, R0),
])

# bon-odori: clap in front, then raise the arms to one side while stepping, mirrored (loops)
DANCE_A = {"upper.R": up_r(95, 40), "fore.R": [(Y, 30)], "upper.L": up_l(20, 30), "fore.L": [(X, -50)],
           "hips": [(Z, 8)], "chest": [(Z, 6), (Y, -3)], "head": [(Z, 8)], "thigh.R": [(X, -12)], "shin.R": [(X, 22)]}
DANCE_B = {"upper.L": up_l(95, 40), "fore.L": [(Y, -30)], "upper.R": up_r(20, 30), "fore.R": [(X, -50)],
           "hips": [(Z, -8)], "chest": [(Z, -6), (Y, 3)], "head": [(Z, -8)], "thigh.L": [(X, -12)], "shin.L": [(X, 22)]}
CLAP = {"upper.L": up_l(10, 62), "upper.R": up_r(10, 62), "fore.L": [(X, -62)], "fore.R": [(X, -62)], "spine": [(X, 6)], "head": [(X, 4)]}
gesture("dance", [(1, CLAP), (13, DANCE_A), (25, CLAP), (37, DANCE_B), (49, CLAP)])

bpy.ops.object.mode_set(mode='OBJECT')
bpy.context.scene.render.fps = 24

# ------------------------------------------------------------------ previews
if PREV:
    os.makedirs(PREV, exist_ok=True)
    sc = bpy.context.scene
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.8, 0.85, 0.9, 1)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')); sc.collection.objects.link(sun)
    sun.data.energy = 3; sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    sc.render.engine = 'BLENDER_EEVEE'; sc.render.resolution_x = int(os.environ.get("RIG_PREV_W", 300)); sc.render.resolution_y = int(os.environ.get("RIG_PREV_H", 400))
    sc.eevee.taa_render_samples = 4; sc.view_settings.view_transform = 'Standard'
    tag = os.path.splitext(os.path.basename(DST))[0]
    for act_name, frames in (("walk", [1, 4, 7, 9, 12, 15, 18, 20]), ("run", [1, 3, 5, 7, 9, 11, 13, 15]), ("idle", [1])):
        if os.environ.get("RIG_PREV_GAIT", "1") == "0":
            break
        arm.animation_data.action = bpy.data.actions[act_name]
        views = (("front", Vector((0.25, -1, 0.15))), ("side", Vector((1, 0, 0.1))),
                 ("back35", Vector((0, 1, 0.70))), ("front35", Vector((0, -1, 0.70))))
        if act_name == "idle":
            views = views[:2]
        for view, d in views:
            d = d.normalized()
            cam.location = Vector((0, 0, 0.5 * H)) + d * H * 2.2
            cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
            for f in frames:
                sc.frame_set(f)
                sc.render.filepath = f"{PREV}/{tag}_{act_name}_{view}_{f:02d}.png"
                bpy.ops.render.render(write_still=True)
    for act_name, frames in (("wave", [8, 13]), ("bow", [15]), ("look", [24, 60]), ("stretch", [34]),
                             ("tend", [1, 13]), ("talk", [13, 37]), ("cheer", [7]), ("dance", [13, 37])):
        for t in arm.animation_data.nla_tracks:
            t.mute = True
        arm.animation_data.action = bpy.data.actions[act_name]
        for view, d in (("front", Vector((0.25, -1, 0.15))), ("side", Vector((1, 0, 0.1)))):
            d = d.normalized()
            cam.location = Vector((0, 0, 0.5 * H)) + d * H * 2.2
            cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
            for f in frames:
                sc.frame_set(f)
                sc.render.filepath = f"{PREV}/{tag}_g_{act_name}_{view}_{f:02d}.png"
                bpy.ops.render.render(write_still=True)
    arm.animation_data.action = None
    for t in arm.animation_data.nla_tracks:
        t.mute = False

bpy.ops.object.select_all(action='DESELECT')
mesh.select_set(True)
arm.select_set(True)
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=True, export_yup=True,
                          export_image_format='JPEG', export_jpeg_quality=88, export_animations=True,
                          export_animation_mode='NLA_TRACKS', export_skins=True, export_extras=True)
print("RIGGED", DST, "H=%.2f" % H)

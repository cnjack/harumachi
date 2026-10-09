"""Find the plane an object stands on, so leaning reconstructions can be set upright.

Pixal3D builds each model in the frame of its 3/4-view reference picture, so anything shot
from slightly above comes out leaning back by roughly the camera's elevation. The yaw fix
cannot undo that. What does work is the physical definition of "standing": the object rests
on one face of its convex hull (four leg tips, a flat base, two wheels and a foot). Take the
biggest nearly-downward hull face and rotate it flat.

Runs inside Blender (uses bmesh for the hull, numpy for the maths).
"""
import math

import bmesh
import numpy as np
from mathutils import Matrix, Vector

MAX_TILT = 40.0  # only hull faces within this angle of straight down count as a base
SAME_PLANE_DEG = 2.5


def support_plane(coords):
    """coords: (N, 3) numpy array, Z up. Returns (normal, tilt_deg, base_area, footprint_area).

    normal points down (out of the base). tilt_deg is the angle between it and -Z.
    """
    pts = np.asarray(coords, dtype=np.float64)
    lo = pts.min(0); hi = pts.max(0)
    size = float(np.linalg.norm(hi - lo)) or 1.0
    # the hull only needs a sparse sample; keep every extreme point by rounding to a grid
    q = np.unique(np.round((pts - lo) / (size * 0.002)).astype(np.int64), axis=0)
    pts = q * (size * 0.002) + lo
    bm = bmesh.new()
    for p in pts:
        bm.verts.new(p)
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:], use_existing_faces=False)
    # drop interior points the hull op leaves behind
    bmesh.ops.delete(bm, geom=[v for v in res["geom_interior"] if isinstance(v, bmesh.types.BMVert)], context='VERTS')
    bm.faces.ensure_lookup_table()
    hull_pts = np.array([v.co[:] for v in bm.verts])
    centre = Vector(pts.mean(0))
    faces = []
    for f in bm.faces:
        n = f.normal.copy()
        c = f.calc_center_median()
        if n.dot(c - centre) < 0:
            n = -n
        a = f.calc_area()
        if a <= 0:
            continue
        faces.append((np.array(n), np.array(c), a))
    bm.free()
    down = np.array([0.0, 0.0, -1.0])
    cos_max = math.cos(math.radians(MAX_TILT))
    cand = [f for f in faces if f[0] @ down > cos_max]
    cand.sort(key=lambda f: -f[2])
    cos_same = math.cos(math.radians(SAME_PLANE_DEG))
    best = None
    used = [False] * len(cand)
    for i, (n0, c0, _) in enumerate(cand):
        if used[i]:
            continue
        acc_n = np.zeros(3); acc_a = 0.0
        for j, (n, c, a) in enumerate(cand):
            if used[j]:
                continue
            if n @ n0 > cos_same and abs((c - c0) @ n0) < size * 0.01:
                used[j] = True
                acc_n += n * a; acc_a += a
        if best is None or acc_a > best[1]:
            best = (acc_n / np.linalg.norm(acc_n), acc_a)
    if best is None:
        return down, 0.0, 0.0, _shadow_area(hull_pts, down)
    n = best[0]
    tilt = math.degrees(math.acos(max(-1.0, min(1.0, float(n @ down)))))
    # footprint = the object's shadow on its own base plane, so the ratio doesn't depend on yaw
    return n, tilt, best[1], _shadow_area(hull_pts, n)


def _shadow_area(pts, n):
    n = np.asarray(n, dtype=np.float64)
    u = np.cross(n, [1.0, 0.0, 0.0])
    if np.linalg.norm(u) < 1e-6:
        u = np.cross(n, [0.0, 1.0, 0.0])
    u /= np.linalg.norm(u); w = np.cross(n, u)
    p = np.unique(np.round(np.c_[pts @ u, pts @ w], 6), axis=0)
    if len(p) < 3:
        return 0.0
    p = p[np.lexsort((p[:, 1], p[:, 0]))]

    def half(seq):
        h = []
        for q in seq:
            while len(h) >= 2 and (h[-1][0] - h[-2][0]) * (q[1] - h[-2][1]) - (h[-1][1] - h[-2][1]) * (q[0] - h[-2][0]) <= 0:
                h.pop()
            h.append(q)
        return h
    lo = half(p); hi = half(p[::-1])
    ring = np.array(lo[:-1] + hi[:-1])
    x, y = ring[:, 0], ring[:, 1]
    return float(0.5 * abs(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))))


def level_matrix(normal):
    """Rotation that turns the base normal to straight down."""
    n = Vector(normal).normalized()
    return n.rotation_difference(Vector((0, 0, -1))).to_matrix().to_4x4()


def mesh_coords(me):
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    return co.reshape(-1, 3)


def squareness(coords):
    """How far a model's footprint is turned off the X/Z axes (Blender X/Y), in degrees.

    Uses the minimum-area rectangle around the lower 60% of the model (canopies and roofs
    overhang). Returns (angle in -45..45, hull area / rectangle area); the angle only means
    something when the second number is high (a boxy footprint).
    """
    pts = np.asarray(coords, dtype=np.float64)
    z0, z1 = pts[:, 2].min(), pts[:, 2].max()
    p = pts[pts[:, 2] <= z0 + 0.6 * (z1 - z0)][:, :2]
    p = np.unique(np.round(p, 4), axis=0)
    if len(p) < 3:
        return 0.0, 0.0
    p = p[np.lexsort((p[:, 1], p[:, 0]))]

    def half(seq):
        h = []
        for q in seq:
            while len(h) >= 2 and (h[-1][0] - h[-2][0]) * (q[1] - h[-2][1]) - (h[-1][1] - h[-2][1]) * (q[0] - h[-2][0]) <= 0:
                h.pop()
            h.append(q)
        return h
    ring = np.array(half(p)[:-1] + half(p[::-1])[:-1])
    x, y = ring[:, 0], ring[:, 1]
    hull_area = 0.5 * abs(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))
    best = (float("inf"), 0.0)
    for i in range(len(ring)):
        e = ring[(i + 1) % len(ring)] - ring[i]
        L = np.hypot(*e)
        if L < 1e-9:
            continue
        a = math.atan2(e[1], e[0])
        c, s = math.cos(-a), math.sin(-a)
        r = ring @ np.array([[c, s], [-s, c]])
        area = np.ptp(r[:, 0]) * np.ptp(r[:, 1])
        if area < best[0]:
            best = (area, a)
    ang = math.degrees(best[1]) % 90.0
    if ang > 45.0:
        ang -= 90.0
    return ang, (hull_area / best[0] if best[0] > 0 else 0.0)

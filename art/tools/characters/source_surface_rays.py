"""Vectorized exact ±Z source-surface envelopes for offline clothing audits.

This batches queries sharing a spatial cell. It retains every valid source
triangle, chooses the exterior before any optional normal gate, and uses no
engine-sized absolute determinant epsilon or LOD approximation.
"""
import numpy as np


def envelope(points, faces, queries, sign=1, cell=.035):
    points = np.asarray(points, float)
    faces = np.asarray(faces, np.int64)
    queries = np.asarray(queries, float)
    tri = points[faces]
    first = tri[:, 1] - tri[:, 0]
    second = tri[:, 2] - tri[:, 0]
    determinant = first[:, 0] * second[:, 1] - first[:, 1] * second[:, 0]
    lo = np.floor(tri[:, :, :2].min(1) / cell).astype(np.int64)
    hi = np.floor(tri[:, :, :2].max(1) / cell).astype(np.int64)
    bins = {}
    for face in np.flatnonzero(abs(determinant) > 1e-12):
        for x in range(lo[face, 0], hi[face, 0] + 1):
            for y in range(lo[face, 1], hi[face, 1] + 1):
                bins.setdefault((x, y), []).append(face)
    query_cells = np.floor(queries[:, :2] / cell).astype(np.int64)
    keys, inverse = np.unique(query_cells, axis=0, return_inverse=True)
    order = np.argsort(inverse, kind='stable')
    boundaries = np.searchsorted(inverse[order], np.arange(len(keys) + 1))
    depth = np.full(len(queries), np.nan)
    face_ids = np.full(len(queries), -1, np.int64)
    barycentrics = np.full((len(queries), 3), np.nan)
    cross = np.cross(first, second)
    length = np.linalg.norm(cross, axis=1)
    normal = np.divide(abs(cross[:, 2]), length, out=np.zeros(len(faces)), where=length > 0)
    for index, key in enumerate(keys):
        candidates = bins.get(tuple(key))
        if not candidates:
            continue
        ids = np.asarray(candidates, np.int64)
        starts = tri[ids, 0]
        a, b, det = first[ids], second[ids], determinant[ids]
        selected_queries = order[boundaries[index]:boundaries[index + 1]]
        # Bound temporary arrays even for unusually dense UV seams.
        chunk = max(1, min(512, 1000000 // max(1, len(ids))))
        for begin in range(0, len(selected_queries), chunk):
            qs = selected_queries[begin:begin + chunk]
            at = queries[qs, None, :2] - starts[None, :, :2]
            u = (at[:, :, 0] * b[None, :, 1] - at[:, :, 1] * b[None, :, 0]) / det
            v = (a[None, :, 0] * at[:, :, 1] - a[None, :, 1] * at[:, :, 0]) / det
            valid = (u >= -1e-7) & (v >= -1e-7) & (u + v <= 1 + 1e-7)
            z = starts[None, :, 2] + u * a[None, :, 2] + v * b[None, :, 2]
            score = np.where(valid, z * sign, -np.inf)
            best = np.argmax(score, axis=1)
            hit = np.any(valid, axis=1)
            rows = np.flatnonzero(hit)
            target, face = qs[rows], best[rows]
            depth[target] = sign * (queries[target, 2] - z[rows, face])
            face_ids[target] = ids[face]
            barycentrics[target] = np.c_[1 - u[rows, face] - v[rows, face], u[rows, face], v[rows, face]]
    return {'signed_depth_m': depth, 'face_ids': face_ids,
            'barycentrics': barycentrics,
            'normal_abs_dot_ray': np.where(face_ids >= 0, normal[np.maximum(face_ids, 0)], np.nan)}

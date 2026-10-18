"""Audit posed body-triangle interiors against the complete source cloth envelope.

Witnesses are barycentric combinations of FINAL POSED triangle corners. They
never interpolate rest-space weights, which would describe another surface.
This is an extra surface check; it does not remove any existing vertex anchor.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from audit_local_garments import mesh_state, pose
from prepare_local_garments import read


def envelope(points, faces, queries, direction=(0., 0., 1.), cell=.035):
    """Exact, double-sided outermost source hit, without an absolute-area gate.

    Unlike the old ray metric, a steep outer pleat is retained when it hides an
    inner wall. Face normal is reported after choosing the exterior intersection.
    """
    direction = np.asarray(direction, float)
    direction /= np.linalg.norm(direction)
    helper = np.eye(3)[np.argmin(abs(direction))]
    axis_u = np.cross(helper, direction)
    axis_u /= np.linalg.norm(axis_u)
    axis_v = np.cross(direction, axis_u)
    frame = np.stack([axis_u, axis_v, direction], axis=1)
    projected = points @ frame
    query = queries @ frame
    tri = projected[faces]
    first, second = tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]
    determinant = first[:, 0] * second[:, 1] - first[:, 1] * second[:, 0]
    cross = np.cross(first, second)
    normal_dot = np.divide(abs(cross[:, 2]), np.linalg.norm(cross, axis=1),
                           out=np.zeros(len(faces)), where=np.linalg.norm(cross, axis=1) > 0)
    bins = {}
    for face in np.flatnonzero(abs(determinant) > 1e-12):
        lo = np.floor(tri[face, :, :2].min(0) / cell).astype(int)
        hi = np.floor(tri[face, :, :2].max(0) / cell).astype(int)
        for x in range(lo[0], hi[0] + 1):
            for y in range(lo[1], hi[1] + 1):
                bins.setdefault((x, y), []).append(face)
    results = []
    for q in query:
        candidates = bins.get(tuple(np.floor(q[:2] / cell).astype(int)), [])
        if not candidates:
            results.append(None)
            continue
        ids = np.asarray(candidates)
        at = q - tri[ids, 0]
        u = (at[:, 0] * second[ids, 1] - at[:, 1] * second[ids, 0]) / determinant[ids]
        v = (first[ids, 0] * at[:, 1] - first[ids, 1] * at[:, 0]) / determinant[ids]
        valid = (u >= -1e-7) & (v >= -1e-7) & (u + v <= 1 + 1e-7)
        if not valid.any():
            results.append(None)
            continue
        z = tri[ids, 0, 2] + u * first[ids, 2] + v * second[ids, 2]
        selected = np.flatnonzero(valid)[np.argmax(z[valid])]
        face = ids[selected]
        bary = np.array([1 - u[selected] - v[selected], u[selected], v[selected]])
        results.append({'source_vertices': faces[face].tolist(),
                        'cloth_barycentric': bary.tolist(),
                        'signed_depth_m': float(q[2] - z[selected]),
                        'normal_abs_dot_ray': float(normal_dot[face])})
    return results


def native_row(args):
    sha = hashlib.sha256(args.input.read_bytes()).hexdigest()
    provenance = json.loads((args.native.parent / 'model-hashes.json').read_text()) if args.native.name == 'engine.log' else json.loads((args.native.parent.parent / 'model-hashes.json').read_text())
    if provenance.get(f'CH_{args.character}.glb') != sha:
        raise ValueError('Source SHA does not match the native companion model-hashes.json')
    if args.native.name == 'engine.log':
        rows = [json.loads(line.split(' ', 1)[1]) for line in args.native.read_text().splitlines()
                if line.startswith('GARMENT_FULL_SOURCE ')]
        row = next(r for r in rows if r['id'] == args.character and r['clip'] == args.clip and abs(r['phase'] - args.phase) < 1e-8)
        return {**row['measurement'], 'phase': row['phase']}
    rows = json.loads(args.native.read_text())['shots']
    return next(r for r in rows if r['id'] == args.character and r['clip'] == args.clip and abs(r['phase'] - args.phase) < 1e-8)


def main(args):
    state = mesh_state(args.input, args.character)
    row = native_row(args)
    actual, _ = pose(state, row['clip'], row['clip_time'], row, actual_shapes=True)
    primitive = state['d']['meshes'][state['node']['mesh']]['primitives'][0]
    all_faces = read(state['d'], state['b'], primitive['indices']).reshape(-1, 3)
    source_faces = state['body_faces']
    source_face_ids = np.flatnonzero(np.all(np.isin(all_faces, state['body']), axis=1))
    # Full original vertex anchors remain a separately identifiable witness set.
    barycentrics = np.asarray([[1, 0, 0], [0, 1, 0], [0, 0, 1],
                              [.5, .5, 0], [.5, 0, .5], [0, .5, .5],
                              [1/3, 1/3, 1/3]], float)
    points = np.einsum('wc,fcj->fwj', barycentrics, actual[source_faces]).reshape(-1, 3)
    rest_points = np.einsum('wc,fcj->fwj', barycentrics, state['positions'][source_faces]).reshape(-1, 3)
    witness_faces = np.repeat(source_face_ids, len(barycentrics))
    witness_barys = np.tile(barycentrics, (len(source_faces), 1))
    kinds = np.tile(np.asarray(['vertex'] * 3 + ['edge_midpoint'] * 3 + ['centroid']), len(source_faces))
    pixel_witnesses = []
    if args.pixel_witnesses:
        for pixel in json.loads(args.pixel_witnesses.read_text())['pixels']:
            if pixel['source_face'] not in source_face_ids:
                continue
            pixel_witnesses.append(pixel)
        if pixel_witnesses:
            pixel_points = np.asarray([np.asarray(p['barycentric']) @ actual[all_faces[p['source_face']]] for p in pixel_witnesses])
            points = np.r_[points, pixel_points]
            rest_points = np.r_[rest_points, [np.asarray(p['barycentric']) @ state['positions'][all_faces[p['source_face']]] for p in pixel_witnesses]]
            witness_faces = np.r_[witness_faces, [p['source_face'] for p in pixel_witnesses]]
            witness_barys = np.r_[witness_barys, [p['barycentric'] for p in pixel_witnesses]]
            kinds = np.r_[kinds, ['confirmed_native_skin_pixel'] * len(pixel_witnesses)]
    # Source cloth pigment selection is independent of runtime targets/LOD.
    full_cloth = state['cloth_faces']
    axes = {'front': (0., 0., 1.), 'back': (0., 0., -1.)}
    if args.camera_manifest:
        camera_rows = json.loads(args.camera_manifest.read_text())['shots']
        camera_row = next(r for r in camera_rows if r['id'] == args.character and r['clip'] == args.clip and abs(r['phase'] - args.phase) < 1e-8 and r['view'] == 'front')
        bones = np.asarray([bone['position'] + [1] for bone in camera_row['bones']])
        screens = np.asarray([bone['screen'] for bone in camera_row['bones']])
        projection = np.linalg.lstsq(bones, screens, rcond=None)[0]
        direction = np.cross(projection[:3, 0], projection[:3, 1])
        if direction @ (np.asarray(camera_row['camera']) - camera_row['position']) < 0:
            direction = -direction
        axes['confirmed_front_camera'] = direction
    result = {'input': str(args.input), 'input_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
              'native': str(args.native), 'clip': args.clip, 'phase': args.phase,
              'scope': 'Exact native bones/morphs; barycentric interpolation of final posed source body triangle corners against complete independently labelled source cloth; no normal rejection before exterior hit',
              'body_source_triangles': len(source_faces), 'source_cloth_triangles': len(full_cloth),
              'witness_counts': {kind: int(np.count_nonzero(kinds == kind)) for kind in np.unique(kinds)},
              'axes': {}}
    for name, direction in axes.items():
        hits = envelope(actual, full_cloth, points, direction)
        rest_hits = envelope(state['positions'], full_cloth, rest_points, direction)
        measured = []
        for index, hit in enumerate(hits):
            if hit is not None:
                measured.append({**hit, 'body_source_face': int(witness_faces[index]),
                                 'covered_by_source_cloth_at_rest': rest_hits[index] is not None and rest_hits[index]['signed_depth_m'] <= 0,
                                 'body_source_vertices': all_faces[witness_faces[index]].tolist(),
                                 'body_barycentric': witness_barys[index].tolist(),
                                 'witness_kind': str(kinds[index]), 'body_posed_position': points[index].tolist()})
        measured.sort(key=lambda item: item['signed_depth_m'], reverse=True)
        result['axes'][name] = {'covered_witnesses': len(measured),
                               'positive_over_5mm': sum(m['signed_depth_m'] > .005 for m in measured),
                               'maximum_signed_depth_m': max((m['signed_depth_m'] for m in measured), default=None),
                               'rest_covered_positive_over_5mm': sum(m['signed_depth_m'] > .005 and m['covered_by_source_cloth_at_rest'] for m in measured),
                               'rest_covered_worst_20': [m for m in measured if m['covered_by_source_cloth_at_rest']][:20],
                               'worst_20': measured[:20],
                               'confirmed_pixel_witnesses': [m for m in measured if m['witness_kind'] == 'confirmed_native_skin_pixel']}
        print(name, result['axes'][name]['maximum_signed_depth_m'], result['axes'][name]['positive_over_5mm'], flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--character', required=True)
    parser.add_argument('--native', type=Path, required=True)
    parser.add_argument('--clip', required=True)
    parser.add_argument('--phase', type=float, required=True)
    parser.add_argument('--pixel-witnesses', type=Path)
    parser.add_argument('--camera-manifest', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    main(parser.parse_args())

"""Replay actual final bones through the imported production collision proxy.

Unlike fixed-old-weight counterfactuals this resets local coefficients, then
re-solves the same coarse proxy. It exposes corrective/proxy compensation before
a native recapture. This is approximate CPU preflight, never a native substitute.
"""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree

from audit_local_garments import layer_hits, mesh_state, measure, pose
from prepare_local_garments import read
from prepare_sleeve_correctives import patch_weights
from audit_native_garment_surfaces import paired_clearance, witnesses
from source_surface_rays import envelope


def imported_proxy(state, path, target=1400):
    export = json.loads(path.read_text())
    point = np.asarray(export['positions'])
    uv = np.asarray(export['uv'])
    primitive = state['d']['meshes'][state['node']['mesh']]['primitives'][0]
    source_uv = read(state['d'], state['b'], primitive['attributes']['TEXCOORD_0'])
    near = cKDTree(state['positions']).query_ball_point(point, 1e-5)
    mapping = np.asarray([min(ids, key=lambda j: np.linalg.norm(source_uv[j] - uv[i])) for i, ids in enumerate(near)])
    if np.linalg.norm(state['positions'][mapping] - point, axis=1).max() > 1e-5 or np.linalg.norm(source_uv[mapping] - uv, axis=1).max() > 1e-5:
        raise ValueError('Imported proxy does not map exactly to candidate rest geometry/UV')
    candidates = export['candidates']
    level = min(range(len(candidates)), key=lambda i: abs(candidates[i]['total_triangles'] - target) if candidates[i]['total_triangles'] >= 800 and candidates[i]['front'] >= 200 and candidates[i]['back'] >= 200 else np.inf)
    faces = {side: mapping[np.asarray(export['levels'][level][side]).reshape(-1, 3)] for side in ['front', 'back']}
    # Preserve imported ascending body-anchor order and physical seam dedup.
    body_set = set(state['body'].tolist())
    body, seen = [], set()
    for original in mapping:
        if original not in body_set:
            continue
        key = state['positions'][original].tobytes() + state['joints'][original].tobytes() + state['weights'][original].tobytes()
        if key not in seen:
            seen.add(key)
            body.append(original)
    return faces, np.asarray(body), {'level': level, **candidates[level]}


def solve_proxy(state, base, directions, faces, body, exact_plane=False):
    coeff = np.stack([state['shapes'][i][:, 2] for i in state['local']], axis=1)
    amount = np.zeros(len(state['local']), np.float32)
    profile = next(n['extras']['garment_local_clearance'] for n in state['d']['nodes'] if n.get('name') == 'Rig')
    margin = profile['clearance_margin_m']
    for iteration in range(4):
        start = amount.copy()
        posed = base + directions * (coeff @ amount.astype(float))[:, None]
        # TriangleMesh in100x space snaps at0.1mm there: 1micrometre physically.
        query_geometry = np.round(posed * 1e6) / 1e6
        increased = False
        for sign, side in [(1, 'front'), (-1, 'back')]:
            for _, triangle, bary, depth in layer_hits(query_geometry, faces[side], body, sign):
                if depth < -margin + .00025:
                    continue
                bary = bary.astype(np.float32)
                slopes = np.zeros(len(amount), np.float32)
                triangle_points = query_geometry[triangle]
                normal = np.cross(triangle_points[1] - triangle_points[0], triangle_points[2] - triangle_points[0])
                for corner in range(3):
                    vertex = triangle[corner]
                    slope_direction = float(normal @ directions[vertex] / normal[2]) if exact_plane else directions[vertex, 2]
                    for patch in np.flatnonzero(abs(coeff[vertex]) >= 1e-7):
                        slopes[patch] = float(slopes[patch]) + float(bary[corner]) * sign * slope_direction * float(coeff[vertex, patch])
                required = depth + margin
                for patch in range(len(amount)):
                    required -= float(slopes[patch]) * (float(amount[patch]) - float(start[patch]))
                if required <= .0001:
                    continue
                divisor = sum(float(slopes[i]) ** 2 for i in range(len(amount)) if slopes[i] > 0 and amount[i] < 1)
                if divisor < 1e-8:
                    continue
                for patch in range(len(amount)):
                    if slopes[patch] <= 0:
                        continue
                    new = min(1., float(amount[patch]) + required * float(slopes[patch]) / divisor)
                    increased |= new > amount[patch] + .000001
                    amount[patch] = new
        if not increased:
            break
    return base + directions * (coeff @ amount.astype(float))[:, None], amount


def main(args):
    source = mesh_state(args.native_source, args.character)
    state = mesh_state(args.candidate, args.character)
    sha = hashlib.sha256(args.native_source.read_bytes()).hexdigest()
    if json.loads((args.native.parent / 'model-hashes.json').read_text()).get(f'CH_{args.character}.glb') != sha:
        raise ValueError('Native source hash mismatch')
    faces, body, proxy = imported_proxy(state, args.proxy)
    rows = [json.loads(line.split(' ', 1)[1]) for line in args.native.read_text().splitlines() if line.startswith('GARMENT_FULL_SOURCE ')]
    rows = [row for row in rows if row['id'] == args.character and (not args.clip or row['clip'] == args.clip)]
    if args.phase:
        rows = [row for row in rows if any(abs(row['phase'] - phase) < 1e-8 for phase in args.phase)]
    if not rows:
        raise ValueError('No matching native samples')
    if args.captured_local and args.candidate.read_bytes() != args.native_source.read_bytes():
        raise ValueError('Captured local weights are valid only for the exact native source')
    samples = []
    witness_triangles, witness_bary, witness_coverage = witnesses(state, args.character) if args.surface else (None, None, None)
    pixels = json.loads(args.pixel_witnesses.read_text())['pixels'] if args.pixel_witnesses else []
    thigh_triangles = None
    thigh_rest_covered = None
    if args.surface and args.character == 'mio':
        centres = state['positions'][state['body_faces']].mean(1)
        selected = (abs(centres[:, 0]) > .075) & (abs(centres[:, 0]) < .20) & (centres[:, 1] > .60) & (centres[:, 1] < .80)
        thigh_triangles = np.repeat(state['body_faces'][selected], 7, axis=0)
        thigh_bary = np.tile(np.asarray([[1,0,0],[0,1,0],[0,0,1],[.5,.5,0],[.5,0,.5],[0,.5,.5],[1/3,1/3,1/3]]), (int(selected.sum()), 1))
        rest_points = np.einsum('wc,wcj->wj', thigh_bary, state['positions'][thigh_triangles])
        rest_depth = envelope(state['positions'], state['cloth_faces'], rest_points)['signed_depth_m']
        thigh_rest_covered = np.isfinite(rest_depth) & (rest_depth <= 0)
    for row in rows:
        reference = deepcopy(row['measurement'])
        animation = next(a for a in state['d']['animations'] if a['name'] == row['clip'])
        table = reference['blend_shape_values'][state['node']['name']]
        values = patch_weights(state['d'], state['b'], animation, state['ni'], len(state['names']), np.asarray([reference['clip_time']]))[0]
        for index, name in enumerate(state['names']):
            if name not in table or any(name.startswith(prefix) for prefix in args.authored_shape_prefix):
                table[name] = float(values[index])
        base, directions = pose(state, row['clip'], reference['clip_time'], reference, actual_shapes=True, disable_local=True)
        if args.captured_local:
            posed, _ = pose(state, row['clip'], reference['clip_time'], reference, actual_shapes=True)
            amount = np.asarray([table[state['names'][i]] for i in state['local']])
        else:
            posed, amount = solve_proxy(state, base, directions, faces, body, args.ray_plane_derivative)
        after = measure(state, posed)
        actual_local = [table.get(state['names'][index], 0) for index in state['local']]
        sample = {'clip': row['clip'], 'phase': row['phase'], 'after': after,
                        'replayed_local_weights': amount.tolist(), 'captured_old_local_weights': actual_local,
                        'max_replay_vs_actual_local_weight_difference': float(np.max(abs(amount - actual_local)))}
        if args.gap:
            sample['predicted_clearance'] = paired_clearance(state, posed, base, True)
        if args.surface:
            points = np.einsum('wc,wcj->wj', witness_bary, posed[witness_triangles])
            surface = {}
            for side, sign in [('front', 1), ('back', -1)]:
                hits = envelope(posed, state['layers'][side], points, sign)
                depth = hits['signed_depth_m']
                valid = np.isfinite(depth)
                gated = valid & (hits['normal_abs_dot_ray'] >= .35)
                surface[side] = {'witnesses': len(points), 'coverage': witness_coverage,
                    'max_raw_depth_m': float(np.nanmax(depth)) if valid.any() else None,
                    'max_normal_gated_depth_m': float(np.max(depth[gated])) if gated.any() else None,
                    'raw_over5mm': int(np.count_nonzero(depth > .005)),
                    'original_normal_gate_over5mm': int(np.count_nonzero(gated & (depth > .005)))}
            sample['body_surface_witnesses'] = surface
        if thigh_triangles is not None and row['clip'] == 'run':
            thigh_points = np.einsum('wc,wcj->wj', thigh_bary, posed[thigh_triangles])
            body_depth = envelope(posed, state['body_faces'], thigh_points)['signed_depth_m']
            cloth_depth = envelope(posed, state['cloth_faces'], thigh_points)['signed_depth_m']
            visible = thigh_rest_covered & np.isfinite(body_depth) & (body_depth >= -1e-7)
            sample['original_upper_thigh_surface_regression'] = {'witnesses': len(thigh_points),
                'source_covered_actual_outer_witnesses': int(visible.sum()),
                'over5mm': int(np.count_nonzero(visible & (cloth_depth > .005))),
                'missing_cloth_hits': int(np.count_nonzero(visible & ~np.isfinite(cloth_depth))),
                'maximum_signed_depth_m': float(np.nanmax(cloth_depth[visible])) if visible.any() else None}
        if pixels:
            pixel_points = np.asarray([np.asarray(p['barycentric']) @ posed[p['vertices']] for p in pixels])
            pixel_hits = envelope(posed, state['layers']['front'], pixel_points)
            sample['confirmed_skin_pixel_source_witnesses'] = [{'source_face': p['source_face'], 'body_vertices': p['vertices'],
                'body_barycentric': p['barycentric'], 'front_signed_depth_m': float(pixel_hits['signed_depth_m'][i])} for i, p in enumerate(pixels)]
        samples.append(sample)
        print(row['clip'], row['phase'], round(after['max_penetration_m'] * 1000, 3), flush=True)
    result = {'native_source': str(args.native_source), 'native_source_sha256': sha,
              'candidate': str(args.candidate), 'candidate_sha256': hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
              'proxy': proxy, 'imported_order_physical_body_anchors': len(body),
              'uses_full_ray_plane_derivative': args.ray_plane_derivative,
              'uses_actual_captured_native_local_coefficients': args.captured_local,
              'scope': 'Approximate imported-proxy re-solve under actual source-native final bones; original captured shape values/new authored tracks; local weights reset0. No old-coefficient warmstart and no production-native claim.',
              'samples': samples, 'passes_5mm': all(s['after']['max_penetration_m'] <= .005 for s in samples)}
    args.output.write_text(json.dumps(result, indent=2))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--native-source', required=True, type=Path)
    p.add_argument('--candidate', required=True, type=Path)
    p.add_argument('--native', required=True, type=Path)
    p.add_argument('--proxy', required=True, type=Path)
    p.add_argument('--character', default='mio')
    p.add_argument('--clip')
    p.add_argument('--phase', action='append', type=float)
    p.add_argument('--authored-shape-prefix', action='append', default=[])
    p.add_argument('--gap', action='store_true')
    p.add_argument('--surface', action='store_true')
    p.add_argument('--ray-plane-derivative', action='store_true')
    p.add_argument('--pixel-witnesses', type=Path)
    p.add_argument('--captured-local', action='store_true')
    p.add_argument('--output', required=True, type=Path)
    main(p.parse_args())

"""Audit complete final-pose cloth and body surfaces in native traces.

Uses actual final bones and native morph scalars, including root yaw reversal.
No animation-time recomputation substitutes for a captured scalar. This is an
offline independent surface check, not a substitute for native acceptance.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image

from audit_local_garments import mesh_state, pose
from motion_math import world_matrices
from prepare_local_garments import colours, read
from source_surface_rays import envelope


BARY = np.asarray([[1, 0, 0], [0, 1, 0], [0, 0, 1],
                   [.5, .5, 0], [.5, 0, .5], [0, .5, .5], [1/3, 1/3, 1/3]])


def local_support_amplitudes(state):
    """Per-side source clothing support, independent of captured coefficients."""
    amplitude = np.zeros((len(state['positions']), 2), dtype=float)
    for index, name in enumerate(state['names']):
        for side, label in enumerate(['Front', 'Back']):
            if name.startswith('Garment_Local_' + label + '_'):
                amplitude[:, side] += abs(state['shapes'][index][:, 2])
    return amplitude


def isolated_pigment_clothing_anchors(state, threshold=1e-6):
    """Identify isolated warm texels enclosed by independently painted cloth.

    A complete pure-body triangle is never removed. Coincident UV copies with
    identical skin slots are considered together so a real trouser or skin
    boundary is not classified from an incomplete single UV fan. Every other
    vertex in the complete fan must independently belong to the same painted
    white panel and carry that panel's Local support. This is intentionally
    stricter than either a color-only or an affected-by-morph-only rule.
    """
    from scipy.spatial import cKDTree
    primitive = state['d']['meshes'][state['node']['mesh']]['primitives'][0]
    faces = read(state['d'], state['b'], primitive['indices']).reshape(-1, 3)
    pure = np.unique(state['body_faces'])
    candidates = np.setdiff1d(state['body'], pure)
    colour = colours(state['d'], state['b'], primitive)
    r, g, blue = colour.T
    white = (colour.min(1) > .50) & (np.ptp(colour, axis=1) < .10)
    white &= ~((r > g * 1.04) & (g > blue * 1.08))
    amplitude = local_support_amplitudes(state)
    # These must be pigment-only layers, never the support/pigment union.
    paint = state.get('independent_pigment_layers', state['layers'])
    painted = [np.unique(paint[side]) for side in ['front', 'back']]
    tree = cKDTree(state['positions'])
    classified = []
    for vertex in candidates:
        copies = np.asarray(tree.query_ball_point(state['positions'][vertex], 1e-6), dtype=int)
        same = np.all(state['joints'][copies] == state['joints'][vertex], axis=1)
        same &= np.max(abs(state['weights'][copies] - state['weights'][vertex]), axis=1) < 1e-7
        copies = copies[same]
        if np.any(np.isin(copies, pure)):
            continue
        incident = np.flatnonzero(np.any(np.isin(faces, copies), axis=1))
        neighbours = np.setdiff1d(np.unique(faces[incident]), copies)
        if not len(neighbours) or not np.all(white[neighbours]):
            continue
        for side, label in enumerate(['front', 'back']):
            if np.all(np.isin(neighbours, painted[side])) and np.all(amplitude[neighbours, side] > threshold):
                classified.append({'vertex': int(vertex), 'side': label,
                                   'physical_uv_copies': copies.tolist(),
                                   'incident_source_faces': incident.tolist(),
                                   'neighbour_vertices': neighbours.tolist(),
                                   'minimum_neighbour_local_support_m': float(amplitude[neighbours, side].min())})
                break
    return classified


def witnesses(state, who, *, classify_clothing=True):
    """Return body queries; the unclassified form is a regression negative control."""
    triangles = np.repeat(state['body_faces'], len(BARY), axis=0)
    bary = np.tile(BARY, (len(state['body_faces']), 1))
    # Preserve pigment-border anchors except an isolated texel whose complete
    # physical fan independently proves that it is white clothing.
    isolated = isolated_pigment_clothing_anchors(state) if who == 'ren' and classify_clothing else []
    anchors = state['body'][~np.isin(state['body'], [r['vertex'] for r in isolated])]
    triangles = np.r_[triangles, np.repeat(anchors[:, None], 3, axis=1)]
    bary = np.r_[bary, np.tile([1, 0, 0], (len(anchors), 1))]
    counts = {'fully_labelled_body_triangles': len(state['body_faces']),
              'original_body_vertex_anchors': len(state['body']),
              'retained_body_vertex_anchors': len(anchors),
              'isolated_pigment_clothing_anchors': isolated,
              'additional_mixed_uv_witnesses': 0, 'additional_mixed_uv_faces': 0}
    if who != 'ren':
        return triangles, bary, counts
    d, blob = state['d'], state['b']
    primitive = d['meshes'][state['node']['mesh']]['primitives'][0]
    all_faces = read(d, blob, primitive['indices']).reshape(-1, 3)
    faces = all_faces[~np.all(np.isin(all_faces, state['body']), axis=1)]
    sample_triangles = np.repeat(faces, 4, axis=0)
    sample_bary = np.tile(BARY[3:], (len(faces), 1))
    rest = np.einsum('wc,wcj->wj', sample_bary, state['positions'][sample_triangles])
    height = state['positions'][:, 1].max()
    region = (abs(rest[:, 0]) < .16 * height) & (rest[:, 1] > .20 * height) & (rest[:, 1] < .55 * height)
    uv = read(d, blob, primitive['attributes']['TEXCOORD_0'])
    sample_uv = np.einsum('wc,wcj->wj', sample_bary, uv[sample_triangles])
    material = d['materials'][primitive['material']]['pbrMetallicRoughness']
    image = d['images'][d['textures'][material['baseColorTexture']['index']]['source']]
    view = d['bufferViews'][image['bufferView']]
    start = view.get('byteOffset', 0)
    texture = np.asarray(Image.open(io.BytesIO(blob[start:start + view['byteLength']])).convert('RGB')) / 255.
    color = texture[(sample_uv[:, 1] * len(texture)).astype(int) % len(texture),
                    (sample_uv[:, 0] * texture.shape[1]).astype(int) % texture.shape[1]]
    selected = region & (color[:, 0] > color[:, 1] * 1.04) & (color[:, 1] > color[:, 2] * 1.08)
    candidate_count = int(selected.sum())
    # A warm shadow on a white ribbon is not an interior point of trousers.
    # This applies only to newly added mixed-UV witnesses; pure body triangles
    # and all retained original anchors keep their original coverage.
    amplitude = local_support_amplitudes(state)
    interpolated = np.einsum('wc,wcs->ws', sample_bary, amplitude[sample_triangles])
    clothing = np.any(interpolated > 1e-6, axis=1)
    counts['mixed_uv_pigment_candidates'] = candidate_count
    counts['mixed_uv_clothing_support_exclusions'] = int(np.count_nonzero(selected & clothing))
    counts['maximum_pure_body_local_support_m'] = float(amplitude[np.unique(state['body_faces'])].max())
    if classify_clothing:
        selected &= ~clothing
    counts['additional_mixed_uv_witnesses'] = int(selected.sum())
    counts['additional_mixed_uv_faces'] = int(np.unique(np.flatnonzero(selected) // 4).size)
    return np.r_[triangles, sample_triangles[selected]], np.r_[bary, sample_bary[selected]], counts


def transition_rows(path, who):
    data = json.loads(path.read_text())
    case = next(c for c in data['cases'] if c['character'] == who)
    frames = {f['frame']: f for f in case['frames']}
    for sample in case['full_bone_samples']:
        frame = frames[sample['applied_frame']]
        if sample['maximum_transform_difference_from_continuous'] > .00001:
            raise ValueError('Final callback and continuous frame differ')
        model_basis = np.asarray(frame['model_basis']).T
        inverse = np.linalg.inv(model_basis)
        origin = np.asarray(frame['model_position'])
        bones = []
        for layout, transform in zip(case['bone_layout'], sample['bone_transforms']):
            transform = np.asarray(transform)
            bones.append({'name': layout['name'],
                          'position': (inverse @ (transform[:3] - origin)).tolist(),
                          'basis': (inverse @ transform[3:].reshape(3, 3).T).T.tolist()})
        yield {'clip': sample['clip'] or 'idle', 'captured_clip': sample['clip'],
               'clip_time': sample['clip_time'], 'position': [0, 0, 0],
               'bones': bones, 'blend_shape_values': sample['blend_shape_values'],
               'frame': sample['applied_frame'], 'phase': frame['phase'],
               'natural_pose_trace': frame['natural_pose_trace']}


def continuous_rows(path, who):
    data = json.loads(path.read_text())
    if data.get('failures'):
        raise ValueError('Native continuous capture contains failures')
    cases = [case for case in data['cases'] if case['character'] == who]
    if not cases or any(not case.get('frames') for case in cases):
        raise ValueError('Native continuous capture has no complete character frames')
    for case in cases:
        layout = case['bone_layout']
        names = [bone['name'] for bone in layout]
        if not names or len(set(names)) != len(names):
            raise ValueError('Native continuous bone layout is empty or ambiguous')
        previous_frame = -1
        for frame in case['frames']:
            if frame['frame'] <= previous_frame or frame['clip'] != case['requested_clip']:
                raise ValueError('Native continuous frame order or clip mismatch')
            if not np.isfinite([frame['clip_time'], frame['phase']]).all():
                raise ValueError('Non-finite native continuous clip timing')
            previous_frame = frame['frame']
            for name in ['natural_pose_trace', 'foot_support_trace']:
                trace = frame.get(name, {})
                trace_time = float(trace.get('clip_time', float('inf')))
                if trace.get('frame') != frame['frame'] or trace.get('clip') != frame['clip'] or not np.isfinite(trace_time) or abs(trace_time - frame['clip_time']) > .0001:
                    raise ValueError('Stale native continuous ' + name)
            packed = np.asarray(frame['bone_transforms'], dtype=float)
            basis = np.asarray(frame['model_basis'], dtype=float).T
            origin = np.asarray(frame['model_position'], dtype=float)
            if packed.shape != (len(layout), 12) or basis.shape != (3, 3) or origin.shape != (3,):
                raise ValueError('Incomplete native continuous bone or model transform')
            if not all(np.isfinite(value).all() for value in [packed, basis, origin]):
                raise ValueError('Non-finite native continuous transform')
            inverse = np.linalg.inv(basis)
            bones = [{'name': bone['name'],
                      'position': (inverse @ (transform[:3] - origin)).tolist(),
                      'basis': (inverse @ transform[3:].reshape(3, 3).T).T.tolist()}
                     for bone, transform in zip(layout, packed)]
            yield {'clip': frame['clip'], 'captured_clip': frame['clip'],
                   'clip_time': frame['clip_time'], 'position': [0, 0, 0],
                   'bones': bones, 'blend_shape_values': frame['blend_shape_values'],
                   'frame': frame['frame'], 'phase': frame['phase'],
                   'view': case.get('view', 'right'),
                   'source_case': who + '-' + case['requested_clip'] + '-' + case.get('view', 'right'),
                   'natural_pose_trace': frame['natural_pose_trace']}


def static_rows(path, who):
    data = json.loads(path.read_text())
    if data.get('failures'):
        raise ValueError('Native static capture contains failures')
    shots = [shot for shot in data.get('shots', []) if shot.get('id') == who]
    if not shots:
        raise ValueError('Native static input has no complete character samples')
    for shot in shots:
        packet = shot.get('pose_sample', {})
        if not np.isfinite([float(packet.get('clip_time', float('inf'))), float(shot.get('clip_time', float('inf'))), float(shot.get('phase', float('inf')))]).all():
            raise ValueError('Non-finite native static timing')
        if (packet.get('request_id', -1) != packet.get('acknowledged_request', -2)
                or packet.get('applied_frame', -1) != packet.get('captured_frame', -2)
                or packet.get('clip') != shot.get('clip')
                or abs(float(packet.get('clip_time', float('inf'))) - float(shot['clip_time'])) > .0001):
            raise ValueError('Stale native static final-pose packet')
        basis = np.asarray(shot.get('model_basis'), dtype=float)
        origin = np.asarray(shot.get('model_position'), dtype=float)
        if basis.shape != (3, 3) or origin.shape != (3,):
            raise ValueError('Native static packet lacks explicit model transform; older images cannot inherit this geometry proof')
        if not np.isfinite(basis).all() or not np.isfinite(origin).all():
            raise ValueError('Non-finite native static model transform')
        inverse = np.linalg.inv(basis.T)
        bones = []
        for bone in shot.get('bones', []):
            position = np.asarray(bone['position'], dtype=float)
            rotation = np.asarray(bone['basis'], dtype=float)
            if position.shape != (3,) or rotation.shape != (3, 3) or not np.isfinite(position).all() or not np.isfinite(rotation).all():
                raise ValueError('Incomplete or non-finite native static bone packet')
            bones.append(dict(name=bone['name'], position=(inverse @ (position-origin)).tolist(),
                              basis=(inverse @ rotation.T).T.tolist()))
        if not bones or len({b['name'] for b in bones}) != len(bones):
            raise ValueError('Native static bone layout is empty or ambiguous')
        yield dict(clip=shot['clip'], captured_clip=shot['clip'], clip_time=shot['clip_time'],
                   phase=shot['phase'], position=[0,0,0], bones=bones,
                   blend_shape_values=shot['blend_shape_values'], frame=packet['applied_frame'],
                   view=shot['view'], source_case=shot['file'])


def rows(args):
    actual_hash = hashlib.sha256(args.input.read_bytes()).hexdigest()
    provenance = args.native.parent if args.native.name == 'engine.log' else args.native.parent.parent
    hashes = json.loads((provenance / 'model-hashes.json').read_text())
    if hashes[f'CH_{args.character}.glb'] != actual_hash:
        raise ValueError('Native source hash does not match input model')
    if args.native.name == 'transition-gait.json':
        return list(transition_rows(args.native, args.character))
    if args.native.name == 'continuous-gait.json':
        return list(continuous_rows(args.native, args.character))
    if args.native.name == 'manifest.json':
        return list(static_rows(args.native, args.character))
    data = [json.loads(line.split(' ', 1)[1]) for line in args.native.read_text().splitlines()
            if line.startswith('GARMENT_FULL_SOURCE ')]
    captured = [{**r['measurement'], 'clip': r['clip'], 'phase': r['phase']} for r in data if r['id'] == args.character]
    if not captured:
        raise ValueError('Native input has no complete character samples; expected continuous/transition-gait.json or GARMENT_FULL_SOURCE engine log')
    return captured


def clearance(state, posed):
    out = {}
    for side, sign in [('front', 1), ('back', -1)]:
        triangles = posed[state['layers'][side]]
        centres = triangles.mean(1)
        areas = np.linalg.norm(np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0]), axis=1) * .5
        hit = envelope(posed, state['body_faces'], centres, sign)
        depth = hit['signed_depth_m']
        covered = np.isfinite(depth)
        values, weights = depth[covered], areas[covered]
        order = np.argsort(values)
        def quantile(q):
            return float(np.interp(q * weights.sum(), np.cumsum(weights[order]), values[order])) if len(values) else None
        out[side] = {'body_covered_cloth_area_fraction': float(weights.sum() / max(areas.sum(), 1e-12)),
                     'body_covered_cloth_centres': int(covered.sum()),
                     'signed_axis_gap_p05_m': quantile(.05), 'signed_axis_gap_median_m': quantile(.5),
                     'signed_axis_gap_p95_m': quantile(.95),
                     'maximum_axis_gap_m': float(values.max()) if len(values) else None,
                     'cloth_area_inside_body_over5mm_fraction': float(weights[values < -.005].sum() / max(areas.sum(), 1e-12))}
    return out


def paired_clearance(state, actual, base, euclidean):
    from triangle_distance import closest_points
    rest_worlds, _ = world_matrices(state['d'], state['b'])
    hip_index = next(i for i, n in enumerate(state['d']['nodes']) if n.get('name') == 'mixamorig:Hips')
    hip_y = float(rest_worlds[hip_index][1, 3])
    result = {}
    for side, sign in [('front', 1), ('back', -1)]:
        faces = state['layers'][side]
        current_tri, previous_tri = actual[faces], base[faces]
        centres, old_centres = current_tri.mean(1), previous_tri.mean(1)
        areas = np.linalg.norm(np.cross(current_tri[:, 1] - current_tri[:, 0], current_tri[:, 2] - current_tri[:, 0]), axis=1) * .5
        rest_centres = state['positions'][faces].mean(1)
        moved = np.linalg.norm(centres - old_centres, axis=1)
        a = envelope(actual, state['body_faces'], centres, sign)['signed_depth_m']
        b = envelope(base, state['body_faces'], old_centres, sign)['signed_depth_m']
        matched = np.isfinite(a) & np.isfinite(b)
        distances = {}
        if euclidean:
            da, fa, qa = closest_points(actual, state['body_faces'], centres)
            db, fb, qb = closest_points(base, state['body_faces'], old_centres)
            distances = {'actual': da, 'zero_local': db, 'added': da - db}
        regions = {}
        for region, selected in [('all_source_panel', np.ones(len(faces), bool)),
                                 ('at_or_below_rest_hip', rest_centres[:, 1] <= hip_y + .02)]:
            weight = areas[selected]
            def stats(values, mask=selected):
                mask = mask & np.isfinite(values)
                vals, ws = values[mask], areas[mask]
                order = np.argsort(vals)
                def quantile(q):
                    return float(np.interp(q * ws.sum(), np.cumsum(ws[order]), vals[order])) if len(vals) else None
                return {'covered_area_fraction_of_region': float(ws.sum() / max(weight.sum(), 1e-12)),
                        'area_weighted_p05_m': quantile(.05), 'area_weighted_median_m': quantile(.5),
                        'area_weighted_p95_m': quantile(.95), 'maximum_m': float(vals.max()) if len(vals) else None}
            summary = {'source_triangle_count': int(selected.sum()),
                       'source_panel_area_fraction': float(weight.sum() / max(areas.sum(), 1e-12)),
                       'moved_area_over1mm_fraction': float(areas[selected & (moved > .001)].sum() / max(weight.sum(), 1e-12)),
                       'signed_axis_actual': stats(a), 'signed_axis_zero_local': stats(b),
                       'signed_axis_added_matched': stats(np.where(matched, a - b, np.nan))}
            if euclidean:
                summary['euclidean_cloth_to_real_body'] = {name: stats(values) for name, values in distances.items()}
                summary['euclidean_added_area_over10mm_fraction'] = float(areas[selected & (da - db > .01)].sum() / max(weight.sum(), 1e-12))
                summary['euclidean_added_area_over30mm_fraction'] = float(areas[selected & (da - db > .03)].sum() / max(weight.sum(), 1e-12))
                ids = np.flatnonzero(selected)
                largest = ids[np.argsort(da[ids] - db[ids])[-5:][::-1]]
                summary['largest_added_distance_examples'] = [{'source_cloth_vertices': faces[i].tolist(),
                    'rest_cloth_centre': rest_centres[i].tolist(), 'actual_cloth_centre': centres[i].tolist(),
                    'zero_local_cloth_centre': old_centres[i].tolist(),
                    'actual_nearest_body_vertices': state['body_faces'][fa[i]].tolist(),
                    'actual_nearest_body_point': qa[i].tolist(),
                    'actual_distance_m': float(da[i]), 'zero_local_distance_m': float(db[i]),
                    'added_distance_m': float(da[i] - db[i])} for i in largest]
            regions[region] = summary
        result[side] = {'rest_hip_y_m': hip_y, 'regions': regions}
    return result


def support_cloth_union(state):
    """Retain independent pigment faces and add every affected source face."""
    primitive = state['d']['meshes'][state['node']['mesh']]['primitives'][0]
    source_faces = read(state['d'], state['b'], primitive['indices']).reshape(-1, 3)
    layers, domains = {}, {}
    for side, label in [('front', 'Front'), ('back', 'Back')]:
        selected = [index for index in state['local'] if state['names'][index].startswith('Garment_Local_' + label + '_')]
        amplitude = np.zeros(len(state['positions']), dtype=float)
        for index in selected:
            amplitude += abs(state['shapes'][index][:, 2])
        support = source_faces[np.all((amplitude >= .000001)[source_faces], axis=1)]
        painted = {tuple(face) for face in state['layers'][side].tolist()}
        supported = {tuple(face) for face in support.tolist()}
        union = painted | supported
        layers[side] = np.asarray([face for face in source_faces.tolist() if tuple(face) in union], dtype=np.int64).reshape(-1, 3)
        domains[side] = {'independent_pigment_faces': len(state['layers'][side]),
                         'local_support_faces': len(support), 'union_faces': len(layers[side]),
                         'support_only_additional_face_keys': len(supported - painted)}
    return layers, domains


def complete_painted_cloth_union(state, who):
    """Add real hip-depth cloth without changing the historical sided domains.

    Independent source texels label compatible physical UV copies. Only faces
    with three painted corners in the original garment region are added; their
    centroid supplies a side when neither old pigment nor Local did so.
    """
    domain_state = dict(state, layers=state.get('independent_pigment_layers', state['layers']))
    layers, domains = support_cloth_union(domain_state)
    if who not in ['mio', 'kazuko']:
        return layers, domains
    from scipy.spatial import cKDTree
    primitive = state['d']['meshes'][state['node']['mesh']]['primitives'][0]
    faces = read(state['d'], state['b'], primitive['indices']).reshape(-1, 3)
    rgb = colours(state['d'], state['b'], primitive)
    r, g, b = rgb.T
    paint = ((b > r * 1.08) & (b > g * 1.04) & (r + g + b < 1.0) if who == 'mio'
             else (r > g * .95) & (r < g * 1.9) & (b < g * .65) & (g > .18))
    pairs = cKDTree(state['positions']).query_pairs(1e-6, output_type='ndarray')
    if len(pairs):
        compatible = np.all(state['joints'][pairs[:, 0]] == state['joints'][pairs[:, 1]], axis=1)
        compatible &= np.max(abs(state['weights'][pairs[:, 0]] - state['weights'][pairs[:, 1]]), axis=1) < 1e-7
        pairs = pairs[compatible]
        while True:
            before = int(paint.sum())
            chosen = pairs[paint[pairs[:, 0]] | paint[pairs[:, 1]]]
            paint[chosen.ravel()] = True
            if int(paint.sum()) == before:
                break
    x, y, z = state['positions'].T
    height = float(y.max())
    paint &= (abs(x) < .24 * height) & (y > .20 * height) & (y < .59 * height)
    painted = faces[np.all(paint[faces], axis=1)]
    if len(np.intersect1d(np.unique(painted), state['body'])):
        raise ValueError('Complete painted source faces intersect original body anchors')
    worlds, _ = world_matrices(state['d'], state['b'])
    hips = [i for i, node in enumerate(state['d']['nodes']) if node.get('name', '').split(':')[-1] in ['Hips', 'hips']]
    if len(hips) != 1:
        raise ValueError('Ambiguous original hips for source face side')
    hip_z = float(worlds[hips[0]][2, 3])
    old = {tuple(face) for values in layers.values() for face in values.tolist()}
    selected = {side: {tuple(face) for face in values.tolist()} for side, values in layers.items()}
    for face in painted:
        key = tuple(face)
        if key not in old:
            side = 'front' if float(z[face].mean()) > hip_z else 'back'
            selected[side].add(key)
    for side in layers:
        original_count = len(layers[side])
        layers[side] = np.asarray([face for face in faces.tolist() if tuple(face) in selected[side]], dtype=np.int64).reshape(-1, 3)
        domains[side].update(original_sided_union_faces=original_count,
                             additional_complete_pigment_faces=len(layers[side]) - original_count,
                             union_faces=len(layers[side]))
    return layers, domains


def measure_surface(state, points, witness_triangles, witness_bary, rest_covered):
    """Measure the supplied final geometry; never silently clear its Local values."""
    measurements = {}
    queries = np.einsum('wc,wcj->wj', witness_bary, points[witness_triangles])
    for side, sign in [('front', 1), ('back', -1)]:
        h = envelope(points, state['layers'][side], queries, sign)
        values = h['signed_depth_m']
        valid = np.isfinite(values)
        selected = valid & rest_covered[side]
        worst = int(np.nanargmax(np.where(selected, values, np.nan))) if selected.any() else None
        all_worst = int(np.nanargmax(values)) if valid.any() else None
        measurements[side] = {'covered_witnesses': int(valid.sum()),
                              'all_hit_over5mm': int((valid & (values > .005)).sum()),
                              'all_hit_max_depth_m': float(np.nanmax(values)) if valid.any() else None,
                              'all_hit_worst_normal_abs_dot_ray': float(h['normal_abs_dot_ray'][all_worst]) if all_worst is not None else None,
                              'all_hit_worst_body_vertices': witness_triangles[all_worst].tolist() if all_worst is not None else None,
                              'all_hit_worst_body_barycentric': witness_bary[all_worst].tolist() if all_worst is not None else None,
                              'original_normal_gate_all_hit_over5mm': int((valid & (values > .005) & (h['normal_abs_dot_ray'] >= .35)).sum()),
                              'rest_covered_witnesses': int(selected.sum()),
                              'lost_rest_covered_witnesses': int((~valid & rest_covered[side]).sum()),
                              'rest_covered_over5mm': int((selected & (values > .005)).sum()),
                              'rest_covered_max_depth_m': float(values[worst]) if worst is not None else None,
                              'original_normal_gate_rest_covered_over5mm': int((selected & (values > .005) & (h['normal_abs_dot_ray'] >= .35)).sum()),
                              'worst_hit_normal_abs_dot_ray': float(h['normal_abs_dot_ray'][worst]) if worst is not None else None,
                              'worst_body_vertices': witness_triangles[worst].tolist() if worst is not None else None,
                              'worst_body_barycentric': witness_bary[worst].tolist() if worst is not None else None}
    return measurements


def run(args):
    state = mesh_state(args.input, args.character)
    # Witness semantics must use independent paint before support expands the
    # cloth ray domain; otherwise that expansion could certify its own labels.
    state['independent_pigment_layers'] = state['layers']
    witness_triangles, witness_bary, witness_counts = witnesses(state, args.character)
    domains = None
    if args.support_cloth or getattr(args, 'complete_painted_cloth', False):
        state['layers'], domains = (complete_painted_cloth_union(state, args.character)
                                   if getattr(args, 'complete_painted_cloth', False)
                                   else support_cloth_union(state))
        state['cloth_faces'] = np.concatenate(list(state['layers'].values()))
        state['cloth_vertices'] = np.unique(state['cloth_faces'])
    captured = rows(args)
    if not len(witness_triangles) or any(not len(faces) for faces in state['layers'].values()):
        raise ValueError('Native surface audit requires nonempty original body and both cloth domains')
    body_tri = state['body_faces']
    rest_queries = np.einsum('wc,wcj->wj', witness_bary, state['positions'][witness_triangles])
    rest_covered = {}
    if args.surface:
        for side, sign in [('front', 1), ('back', -1)]:
            h = envelope(state['positions'], state['layers'][side], rest_queries, sign)
            rest_covered[side] = np.isfinite(h['signed_depth_m']) & (h['signed_depth_m'] <= 0)
    report = {'source': str(args.input), 'source_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
              'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'ray_helper_sha256': hashlib.sha256(Path(__file__).with_name('source_surface_rays.py').read_bytes()).hexdigest(),
              'native': str(args.native), 'character': args.character,
              'native_sha256': hashlib.sha256(args.native.read_bytes()).hexdigest(),
              'cloth_domains': domains,
              'complete_painted_cloth': bool(getattr(args, 'complete_painted_cloth', False)),
              'also_measures_actual_local_surface': bool(getattr(args, 'actual_surface', False)),
              'scope': 'Exact same-source native final world bones and named morph scalars; final posed body triangle corners interpolated barycentrically. Root yaw reversed. Complete independently labelled front/back source panels, retaining original side/back openings, no normal gate before exterior hit.',
              'witnesses_per_pose': len(rest_queries), 'body_triangles': len(body_tri), 'cloth_triangles': len(state['cloth_faces']),
              'witness_counts': witness_counts,
              'source_rest_covered_witnesses': {side:int(mask.sum()) for side,mask in rest_covered.items()},
              'gap_scope': 'Area weighted cloth triangle centre to outermost real body surface along model ±Z. Cloth without an underlying real body ray is excluded and coverage reported; this is directional clearance, not Euclidean closest distance.',
              'samples': []}
    for index, row in enumerate(captured):
        if args.clip and row['clip'] not in args.clip:
            continue
        actual, _ = pose(state, row['clip'], row['clip_time'], row, actual_shapes=True)
        base, _ = pose(state, row['clip'], row['clip_time'], row, actual_shapes=True, disable_local=True)
        measurements = {}
        if args.surface:
            measurements = measure_surface(state, base, witness_triangles, witness_bary, rest_covered)
        result = {'clip': row['clip'], 'phase': row['phase'], 'clip_time': row['clip_time'],
                  'frame': row.get('frame'), 'surface_with_local_zero': measurements,
                  'maximum_actual_local_weight': max((abs(v) for table in row['blend_shape_values'].values() for name, v in table.items() if name.startswith('Garment_Local_')), default=0)}
        if 'view' in row: result['view'] = row['view']
        if 'source_case' in row: result['source_case'] = row['source_case']
        if getattr(args, 'actual_surface', False):
            result['surface_with_actual_local'] = measure_surface(state, actual, witness_triangles, witness_bary, rest_covered)
        if args.gap:
            result['paired_source_face_clearance'] = paired_clearance(state, actual, base, args.euclidean)
        report['samples'].append(result)
        print(args.character, index, row['clip'], row['phase'], flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', required=True, type=Path)
    p.add_argument('--native', required=True, type=Path)
    p.add_argument('--character', required=True)
    p.add_argument('--clip', action='append')
    p.add_argument('--surface', action='store_true')
    p.add_argument('--actual-surface', action='store_true', help='With --surface, independently measure the actual native Local values as well as the source-only counterfactual')
    p.add_argument('--support-cloth', action='store_true', help='Retain independent pigment cloth and add all source Local support faces before exterior ray selection')
    p.add_argument('--complete-painted-cloth', action='store_true', help='Also cover all independently painted hip-depth cloth faces and compatible physical UV copies; retains the original sided union')
    p.add_argument('--gap', action='store_true')
    p.add_argument('--euclidean', action='store_true')
    p.add_argument('--output', required=True, type=Path)
    args = p.parse_args()
    if args.actual_surface and not args.surface:
        p.error('--actual-surface requires --surface')
    run(args)

"""Move a small source white-apron patch away from Ren's back waistband.

The native v23 walk witness is at rest (-.0463,.9436,-.1283): its
khaki trousers protrude through the back white cloth by 5.317 mm. This tool
changes only nearby white-cloth base POSITION/NORMAL and the corresponding
existing corrective NORMAL deltas. Skeleton, all animation tracks, UVs,
skin weights, indices, images and every target POSITION remain exact.
No runtime solver, new morph or permissive contact threshold is introduced.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree

from audit_local_garments import mesh_state
from corrective_normals import geometry_normals, rotate_between, unit
from prepare_local_garments import colours, read, smooth
from repair_head_neck import append, save


def repair(args):
    if args.output.exists():
        raise ValueError('Use a new immutable output path')
    if not 0 < args.offset <= .001 or np.hypot(args.offset, args.tangent_x) > .001:
        raise ValueError('Back-waist displacement must be positive and <=1 mm')
    if not 0 < args.inner_radius < args.outer_radius <= .06:
        raise ValueError('Require a small smooth patch with 0<inner<outer<=6cm')
    state = mesh_state(args.input, 'ren')
    d, original = state['d'], state['b']
    profile = next(n.get('extras', {}).get('garment_local_clearance', {}) for n in d['nodes'] if n.get('name') == 'Rig')
    if profile.get('character') != 'ren':
        raise ValueError('Input must be the existing Ren garment candidate')
    source_document = copy.deepcopy(d)
    b = bytearray(original)
    primitive = d['meshes'][state['node']['mesh']]['primitives'][0]
    attrs = primitive['attributes']
    positions = state['positions']
    faces = read(d, b, primitive['indices']).reshape(-1, 3)
    normals = read(d, b, attrs['NORMAL'])
    rgb = colours(d, b, primitive)
    r, g, blue = rgb.T
    white = (rgb.min(1) > .50) & (np.ptp(rgb, axis=1) < .10)
    khaki = (r > g * 1.04) & (g > blue * 1.08)
    centre = np.asarray(args.centre, float)
    distance = np.linalg.norm(positions - centre, axis=1)
    eligible = white & ~khaki & (positions[:, 2] < -.105)
    amount = args.offset * (1 - smooth(args.inner_radius, args.outer_radius, distance))
    amount[~eligible] = 0

    # Physical seam copies retain exactly the same delta. A group containing
    # trousers, skin or another non-white boundary is pinned as a whole.
    pairs = cKDTree(positions).query_pairs(1e-6, output_type='ndarray')
    parent = np.arange(len(positions))
    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for a, c in pairs:
        if np.array_equal(state['joints'][a], state['joints'][c]) and np.max(abs(state['weights'][a] - state['weights'][c])) < 1e-7:
            parent[root(int(c))] = root(int(a))
    groups = {}
    for index in np.unique(pairs):
        groups.setdefault(root(int(index)), []).append(int(index))
    for group in groups.values():
        amount[group] = float(amount[group].max()) if np.all(eligible[group]) else 0
    changed = amount > 0
    if not changed.any() or np.any(changed[state['body']]):
        raise ValueError('Empty patch or protected body overlap')
    result = positions.copy()
    result[:, 2] -= amount
    # Pure -Z follows the skin's yaw and moves the patch sideways by ~41um at
    # native run .9765625, uncovering an existing boundary witness. Retain the
    # cloth overlap with a 60um tangential extension, not a ray-miss exemption.
    result[:, 0] += (amount / args.offset) * args.tangent_x
    delta = result - positions
    changed_faces = np.any(changed[faces], axis=1)
    neighbours = np.zeros(len(positions), bool)
    neighbours[np.unique(faces[changed_faces])] = True
    normal_eligible = neighbours & eligible
    old_geo = geometry_normals(positions, faces)
    new_geo = geometry_normals(result, faces)
    new_normals = normals.copy()
    rotated = unit(rotate_between(old_geo, new_geo, unit(normals)))
    new_normals[normal_eligible] = rotated[normal_eligible]
    attrs['POSITION'] = append(d, b, attrs['POSITION'], result)
    attrs['NORMAL'] = append(d, b, attrs['NORMAL'], new_normals)

    updated_targets = []
    for name, target, shape in zip(state['names'], primitive.get('targets', []), state['shapes']):
        if 'NORMAL' not in target:
            continue
        old_delta = read(d, b, target['NORMAL'])
        if not np.any(shape[neighbours]) and not np.any(old_delta[normal_eligible]):
            continue
        old_render = unit(normals + old_delta)
        # A target's imported normal is unit(base+delta), not delta alone.
        old_target_geo = geometry_normals(positions + shape, faces)
        new_target_geo = geometry_normals(result + shape, faces)
        desired = unit(rotate_between(old_target_geo, new_target_geo, old_render))
        new_delta = old_delta.copy()
        new_delta[normal_eligible] = desired[normal_eligible] - new_normals[normal_eligible]
        if not np.array_equal(new_delta, old_delta):
            target['NORMAL'] = append(d, b, target['NORMAL'], new_delta)
            updated_targets.append(name)
    save(d, b, args.output)

    report = {
        'scope': __doc__, 'input': str(args.input),
        'input_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
        'output': str(args.output), 'output_sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
        'centre_m': centre.tolist(), 'inner_radius_m': args.inner_radius,
        'outer_radius_m': args.outer_radius, 'maximum_requested_offset_m': args.offset,
        'tangential_x_offset_m': args.tangent_x,
        'changed_vertices': np.flatnonzero(changed).tolist(),
        'changed_vertex_count': int(changed.sum()), 'changed_face_count': int(changed_faces.sum()),
        'maximum_actual_displacement_m': float(np.linalg.norm(delta, axis=1).max()),
        'changed_rest_bounds': {'min': positions[changed].min(0).tolist(), 'max': positions[changed].max(0).tolist()},
        'protected_body_position_delta_m': float(np.linalg.norm(delta[state['body']], axis=1).max()),
        'base_normal_vertices_changed': int(np.count_nonzero(np.any(normals != new_normals, axis=1))),
        'target_normals_updated': updated_targets,
        'physical_seam_delta_max_m': max((float(np.linalg.norm(delta[a] - delta[c])) for a, c in pairs
                                          if parent[root(int(a))] == parent[root(int(c))]), default=0.),
        'animations_document_exact': d['animations'] == source_document['animations'],
        'nodes_document_exact': d['nodes'] == source_document['nodes'],
        'skins_document_exact': d['skins'] == source_document['skins'],
        'original_binary_prefix_exact': bytes(b[:len(original)]) == original,
        'preserved': ['all animation tracks and times', 'node hierarchy/rest', 'skin and inverse binds',
                      'joint weights', 'all morph POSITION deltas', 'UVs', 'indices', 'images',
                      'body/face/hands/fingers/shoes geometry', 'all geometry outside the back-waist patch'],
        'native_acceptance': 'pending; source-native poses may be reused only as an explicitly labelled counterfactual',
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2))
    print(json.dumps({k: v for k, v in report.items() if k not in ['scope', 'changed_vertices']}, indent=2))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--report', type=Path, required=True)
    p.add_argument('--offset', type=float, default=.0008)
    p.add_argument('--tangent-x', type=float, default=-.000060)
    p.add_argument('--centre', type=float, nargs=3, default=[-.045, .946, -.123])
    p.add_argument('--inner-radius', type=float, default=.015)
    p.add_argument('--outer-radius', type=float, default=.050)
    repair(p.parse_args())

"""Author a small, continuous rest-space cloth seam field from explicit contacts.

Only independently painted or Local-supported cloth can move. Body, UVs, weights and
bones stay exact. Full independent source surfaces must be audited afterwards;
the authoring target is not an acceptance waiver or a universal cloth solver.
"""
from pathlib import Path
import argparse, copy, hashlib, json
import numpy as np
from glb_io import durations
from audit_local_garments import mesh_state, pose
from audit_native_garment_surfaces import witnesses, complete_painted_cloth_union
from corrective_normals import geometry_normals, rotate_between, unit
from source_surface_rays import envelope
from repair_head_neck import read, append, save
from garment_bake_support import complete_source_domain


def author(source, output, actor, samples, report_path):
    state = mesh_state(source, actor)
    document, raw = state['d'], state['b']
    doc = copy.deepcopy(document)
    blob = bytearray(raw)
    positions = state['positions']
    # Include independently painted cloth corners missed by the old Local
    # templates. Template support must never define its own audit coverage.
    _, support, _ = complete_source_domain(state, 'blue' if actor == 'mio' else 'yellow')
    panels, coverage = complete_painted_cloth_union(state, actor)
    triangles, barycentrics, _ = witnesses(state, actor)
    lengths = durations(source)
    fixtures = []
    for clip, phase in samples:
        points, directions = pose(state, clip, lengths[clip] * phase)
        queries = np.r_[points[state['body']], np.einsum('wc,wcj->wj', barycentrics, points[triangles])]
        fixtures.append((clip, phase, points, directions, queries))
    field = np.zeros(len(positions))
    history = []
    for iteration in range(24):
        maximum = 0.
        for clip, phase, base, directions, queries in fixtures:
            for side, sign in [('front', 1), ('back', -1)]:
                current = base + directions * field[:, None]
                hit = envelope(current, panels[side], queries, sign)
                accepted = np.isfinite(hit['signed_depth_m']) & (hit['normal_abs_dot_ray'] >= .35)
                scores = np.where(accepted, hit['signed_depth_m'], -np.inf)
                query = int(np.argmax(scores))
                depth = float(scores[query])
                maximum = max(maximum, depth)
                if depth <= .0035:
                    continue
                face = panels[side][hit['face_ids'][query]]
                weights = hit['barycentrics'][query]
                center = weights @ positions[face]
                kernel = np.exp(-np.sum((positions-center)**2, axis=1) / (2*.015**2))
                kernel[~support] = 0.
                slope = float(weights @ (directions[face, 2] * kernel[face]))
                if slope <= .05:
                    raise ValueError(f'Contact cannot use source-Z seam field: {clip} {phase} {side}; slope={slope}; support={support[face]}; basis_z={directions[face, 2]}; rest={positions[face]}')
                field += sign * kernel * (depth-.003+.00005) / slope
                if np.max(abs(field)) > .006:
                    raise ValueError('Seam field exceeds its explicit 6mm rest-space cap')
        history.append({'iteration': iteration, 'maximum_fixture_depth_m': maximum})
        if maximum <= .0035:
            break
    else:
        raise ValueError('Requested source seam contacts did not converge')
    node = doc['nodes'][state['ni']]
    mesh = doc['meshes'][node['mesh']]
    primitive = mesh['primitives'][0]
    old_count = len(state['names'])
    delta = np.zeros_like(positions)
    delta[:, 2] = field
    if np.any(delta[state['body']]):
        raise ValueError('Source seam field overlaps body')
    faces = read(document, raw, primitive['indices']).reshape(-1, 3)
    normals = unit(read(document, raw, primitive['attributes']['NORMAL']))
    changed = np.linalg.norm(delta, axis=1) > 1e-8
    affected = np.zeros(len(positions), bool)
    affected[np.unique(faces[np.any(changed[faces], axis=1)])] = True
    dn = unit(rotate_between(geometry_normals(positions, faces), geometry_normals(positions+delta, faces), normals)) - normals
    dn[~affected] = 0
    primitive['targets'].append({'POSITION': append(doc, blob, primitive['attributes']['POSITION'], delta.astype(np.float32)),
                                 'NORMAL': append(doc, blob, primitive['attributes']['NORMAL'], dn.astype(np.float32))})
    name = 'GarmentSourceHemSeam'
    mesh['extras']['targetNames'].append(name)
    mesh['weights'] = list(mesh.get('weights', [0.]*old_count)) + [1.]
    if 'weights' in node:
        node['weights'].append(1.)
    for animation in doc['animations']:
        channel = next(c for c in animation['channels'] if c['target'] == {'node': state['ni'], 'path': 'weights'})
        sampler = animation['samplers'][channel['sampler']]
        old = read(document, raw, sampler['output']).reshape(-1, old_count)
        sampler['output'] = append(doc, blob, sampler['output'], np.c_[old, np.ones(len(old))].astype(np.float32).reshape(-1, 1))
    rig = next(n for n in doc['nodes'] if n.get('name') == 'Rig')
    rig['extras']['source_garment_animation']['rest_seam_field'] = {
        'name': name, 'maximum_rest_shift_m': float(np.max(abs(field))),
        'support_radius_m': .015, 'body_unchanged': True,
        'authoring_samples': [[clip, phase] for clip, phase in samples]}
    save(doc, blob, Path(output))
    report = {'character': actor, 'input_sha256': hashlib.sha256(Path(source).read_bytes()).hexdigest(),
              'output_sha256': hashlib.sha256(Path(output).read_bytes()).hexdigest(),
              'maximum_rest_shift_m': float(np.max(abs(field))), 'changed_vertices': int(changed.sum()),
              'body_position_delta_m': 0., 'coverage': coverage, 'history': history,
              'scope': 'Static source cloth seam only; complete source/game contact and visual acceptance required'}
    Path(report_path).write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ['source', 'output', 'report']:
        parser.add_argument('--'+key, type=Path, required=True)
    parser.add_argument('--character', choices=['mio', 'kazuko'], required=True)
    parser.add_argument('--sample', action='append', required=True, help='clip:phase')
    args = parser.parse_args()
    samples = [(value.split(':')[0], float(value.split(':')[1])) for value in args.sample]
    print(author(args.source, args.output, args.character, samples, args.report))

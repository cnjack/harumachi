"""Audit every source face/edge incident to changed sleeve P/N curve support.

Uses actual candidate final bones and scalars. The old SleeveFit curve is sampled
from the source animation, with its blend envelope recovered from the actual
candidate controls. Normal turns are diagnostic, not asserted topology flips.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from scipy.spatial import cKDTree
from glb_io import load
from prepare_local_garments import read
from sew_arm_seams import dense_part
from corrective_normals import unit

PARTS = ['CharacterBody', 'Sleeve_Left', 'Sleeve_Right']


def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def control(n): return n.startswith(('SleeveFit_stretch_', 'SleeveGuide_stretch_'))


def curve(d, b, part, clip):
    a = next(a for a in d['animations'] if a['name'] == clip)
    ni = d['nodes'].index(part['node'])
    c = next(c for c in a['channels'] if c['target'] == {'node': ni, 'path': 'weights'})
    s = a['samplers'][c['sampler']]
    assert s.get('interpolation', 'LINEAR') == 'LINEAR'
    return read(d, b, s['input']).ravel(), read(d, b, s['output']).reshape(-1, len(part['names']))


def normalized_row(bones, basis, origin, **fields):
    inv = np.linalg.inv(np.asarray(basis).T)
    return {**fields, 'bones': [{'name': x['name'],
            'position': (inv @ (np.asarray(x['position']) - origin)).tolist(),
            'basis': (inv @ np.asarray(x['basis']).T).T.tolist()} for x in bones]}


def native_rows(root):
    m = json.loads((root / 'joint-poses/manifest.json').read_text())
    for s in m['shots']:
        q = s['pose_sample']
        assert q['captured_frame'] == q['applied_frame'] and q['request_id'] == q['acknowledged_request']
        yield normalized_row(s['bones'], s['model_basis'], s['model_position'], kind='static',
            view=s['view'], frame=q['applied_frame'], phase=s['phase'], clip=s['clip'],
            clip_time=s['clip_time'], values=s['blend_shape_values'])
    c = json.loads((root / 'transitions/transition-gait.json').read_text())
    for case in c['cases']:
        assert case['sampling_failures'] == 0
        ack = {s['applied_frame']: s for s in case['full_bone_samples']}
        for f in case['frames']:
            s = ack.get(f['frame'])
            if s is None: continue
            assert s['maximum_transform_difference_from_continuous'] == 0
            assert s['bone_transforms'] == f['bone_transforms'] and s['blend_shape_values'] == f['blend_shape_values']
            bones = [{'name': meta['name'], 'position': t[:3], 'basis': np.asarray(t[3:]).reshape(3, 3).tolist()}
                     for meta, t in zip(case['bone_layout'], s['bone_transforms'])]
            yield normalized_row(bones, f['model_basis'], f['model_position'], kind='continuous',
                view=case['view'], frame=f['frame'], phase=f['phase'], clip=f['clip'],
                clip_time=f['clip_time'], values=s['blend_shape_values'])


def adjacency(part, faces, used):
    parent = np.arange(len(part['pos']))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i
    for a, b in cKDTree(part['pos']).query_pairs(1e-6, output_type='ndarray'):
        if np.max(abs(part['dense'][a] - part['dense'][b])) <= 1e-3: parent[find(b)] = find(a)
    labels = np.array([find(i) for i in range(len(parent))])
    edge_faces = {}
    for fi, face in enumerate(faces):
        for a, b in zip(face, np.roll(face, -1)):
            if labels[a] > labels[b]: a, b = b, a
            edge_faces.setdefault((labels[a], labels[b]), []).append((a, b, fi))
    pairs = []
    for neighbours in edge_faces.values():
        if len(neighbours) == 2:
            a, b, f = neighbours[0]; c, e, g = neighbours[1]
            pairs.append((used[a], used[b], used[c], used[e], f, g))
    return np.asarray(pairs, dtype=int).reshape(-1, 6)


def run(args):
    d, b = load(args.candidate); sd, sb = load(args.source)
    model_hashes = json.loads((args.native / 'model-hashes.json').read_text())
    assert model_hashes[f'CH_{args.character}.glb'] == sha(args.candidate)
    parts = {n['name']: dense_part(d, b, n) for n in d['nodes'] if n.get('name') in PARTS}
    olds = {n['name']: dense_part(sd, sb, n) for n in sd['nodes'] if n.get('name') in PARTS}
    ids = {n.get('name'): i for i, n in enumerate(d['nodes'])}
    sk = d['skins'][0]
    ib = read(d, b, sk['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    prepared = {}; scope = {}
    for name, p in parts.items():
        old = olds[name]; ot, ov = curve(sd, sb, old, 'stretch'); nt, nv = curve(d, b, p, 'stretch')
        control_old = [n for n in old['names'] if control(n)]; control_new = [n for n in p['names'] if control(n)]
        normal_cache = {}
        for key, doc, binary, part in [('old', sd, sb, old), ('new', d, b, p)]:
            base_n = unit(read(doc, binary, part['a']['NORMAL'])); normal_cache[key] = {'base': base_n}
            for n in (control_old if key == 'old' else control_new):
                target = part['p']['targets'][part['names'].index(n)]
                normal_cache[key][n] = unit(base_n + read(doc, binary, target['NORMAL'])) - base_n
        dp = np.zeros(len(p['pos'])); dn = dp.copy()
        for t in np.union1d(ot, nt):
            delta_p = np.zeros_like(p['pos']); delta_n = delta_p.copy()
            for names, part, ts, vs, key, sign in [(control_new, p, nt, nv, 'new', 1), (control_old, old, ot, ov, 'old', -1)]:
                for n in names:
                    value = float(np.interp(t, ts, vs[:, part['names'].index(n)]))
                    if value:
                        delta_p += sign * value * part['shapes'][n]
                        delta_n += sign * value * normal_cache[key][n]
            dp = np.maximum(dp, np.linalg.norm(delta_p, axis=1)); dn = np.maximum(dn, np.linalg.norm(delta_n, axis=1))
        faces = read(d, b, p['p']['indices']).reshape(-1, 3)
        position_faces = (dp[faces] > 1e-12).any(1); normal_faces = (dn[faces] > 1e-12).any(1)
        selected = np.flatnonzero(position_faces | normal_faces)
        used, local = np.unique(faces[selected], return_inverse=True); local = local.reshape(-1, 3)
        lookup = np.full(len(p['pos']), -1, dtype=int); lookup[used] = np.arange(len(used))
        edges = np.unique(np.sort(np.r_[local[:, [0, 1]], local[:, [1, 2]], local[:, [2, 0]]], axis=1), axis=0)
        rest = p['pos'][used]; tri = rest[local]; rest_cross = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]); rest_area = np.linalg.norm(rest_cross, axis=1)
        lengths = np.linalg.norm(rest[edges[:, 0]] - rest[edges[:, 1]], axis=1)
        valid_edges = lengths > 1e-6; valid_faces = rest_area > 1e-12
        # Adjacency uses selected source faces and physical UV copies within the
        # same visible mesh. Cross-mesh cut continuity is measured separately.
        physical_pairs = adjacency(p, local, np.arange(len(used))) if False else None
        label_part = dict(p); label_part['pos'] = p['pos'][used]; label_part['dense'] = p['dense'][used]
        pairs = adjacency(label_part, local, np.arange(len(used)))
        prepared[name] = dict(old=old, p=p, ot=ot, ov=ov, nt=nt, nv=nv, used=used, local=local, selected=selected,
            edges=edges[valid_edges], rest_lengths=lengths[valid_edges], rest_cross=rest_cross,
            rest_area=rest_area, valid_faces=valid_faces, normals=normal_cache, pairs=pairs)
        scope[name] = {'source_position_changed_vertices_gt_1e12': int((dp > 1e-12).sum()),
            'position_changed_vertices_gt_1um': int((dp > 1e-6).sum()),
            'source_normal_changed_vertices_gt_1e12': int((dn > 1e-12).sum()),
            'all_incident_position_faces': int(position_faces.sum()), 'all_incident_normal_faces': int(normal_faces.sum()),
            'union_source_faces': len(selected), 'source_face_ids': selected.tolist(),
            'all_incident_edges': len(edges), 'nondegenerate_edges_measured': int(valid_edges.sum()),
            'physical_uv_adjacency_pairs': len(pairs)}
    summaries = {n: {'new_collapsed_faces': set(), 'old_collapsed_faces': set(), 'introduced_collapsed_faces': set(),
        'old_orientation_disagreement_faces': set(), 'new_orientation_disagreement_faces': set(),
        'introduced_orientation_disagreement_faces': set(), 'introduced_normal_disagreement_faces': set(),
        'introduced_edge_strain_source_vertex_pairs': set(), 'introduced_sharp_pairs': set()} for n in PARTS}
    samples = []
    rows = list(native_rows(args.native))
    for ri, row in enumerate(rows):
        world = {i: np.eye(4) for i in sk['joints']}
        for bone in row['bones']:
            i = ids[bone['name'].replace('mixamorig_', 'mixamorig:')]
            world[i] = np.eye(4); world[i][:3, :3] = np.asarray(bone['basis']).T; world[i][:3, 3] = bone['position']
        matrices = np.array([world[j] @ bind for j, bind in zip(sk['joints'], ib)])
        sample = {k: row[k] for k in ['kind', 'view', 'frame', 'clip', 'phase']}; sample['parts'] = []
        for name, q in prepared.items():
            p, old, used, faces = q['p'], q['old'], q['used'], q['local']
            values_new = row['values'][name]
            values_old = {n: values_new.get(n, 0.) for n in old['names']}
            if row['clip'] == 'stretch':
                pure_new = sum(float(np.interp(row['clip_time'], q['nt'], q['nv'][:, p['names'].index(n)])) for n in p['names'] if control(n))
                actual_new = sum(v for n, v in values_new.items() if control(n))
                blend = actual_new / pure_new if pure_new > 1e-9 else 0.
                for n in old['names']:
                    if control(n): values_old[n] = float(np.interp(row['clip_time'], q['ot'], q['ov'][:, old['names'].index(n)])) * blend
            else:
                assert sum(v for n, v in values_new.items() if control(n)) < 1e-8
                for n in old['names']:
                    if control(n): values_old[n] = 0.
            transform = np.zeros((len(used), 3, 4))
            for slot in range(p['j'].shape[1]): transform += matrices[p['j'][used, slot], :3] * p['w'][used, slot, None, None]
            B = transform[:, :, :3]; posed = {}; renders = {}
            for key, doc, binary, part, values in [('old', sd, sb, old, values_old), ('new', d, b, p, values_new)]:
                points = part['pos'][used].copy(); normals = q['normals'][key]['base'][used].copy()
                for n, value in values.items():
                    if not value: continue
                    points += value * part['shapes'][n][used]
                    if n not in q['normals'][key]:
                        dn = read(doc, binary, part['p']['targets'][part['names'].index(n)]['NORMAL'])
                        q['normals'][key][n] = unit(q['normals'][key]['base'] + dn) - q['normals'][key]['base']
                    normals += value * q['normals'][key][n][used]
                posed[key] = np.einsum('vab,vb->va', B, points) + transform[:, :, 3]
                renders[key] = unit(np.einsum('vab,vb->va', B, unit(normals)))
            metric = {}; crosses = {}; normals = {}; normals_dot = {}; orientation = {}; collapsed = {}; edge_ratio = {}
            ref = unit(np.einsum('fab,fb->fa', B[faces].mean(1), q['rest_cross']))
            for key in ['old', 'new']:
                tri = posed[key][faces]; cross = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]); crosses[key] = cross
                normals[key] = unit(cross); orientation[key] = (normals[key] * ref).sum(1)
                normals_dot[key] = (normals[key] * unit(renders[key][faces].mean(1))).sum(1)
                ratio = np.linalg.norm(cross, axis=1) / np.maximum(q['rest_area'], 1e-20); collapsed[key] = q['valid_faces'] & (ratio < .15)
                edge_ratio[key] = np.linalg.norm(posed[key][q['edges'][:, 0]] - posed[key][q['edges'][:, 1]], axis=1) / q['rest_lengths']
                metric[key] = {'collapsed_vs_rest_below_15pct': int(collapsed[key].sum()),
                    'rest_transport_orientation_nonpositive': int((q['valid_faces'] & (orientation[key] <= 0)).sum()),
                    'geometry_rendered_normal_nonpositive': int((q['valid_faces'] & (normals_dot[key] <= 0)).sum()),
                    'edge_strain_p95_p99_max': np.percentile(edge_ratio[key], [95, 99, 100]).tolist()}
            summary = summaries[name]; face_ids = q['selected']
            for key in ['old', 'new']:
                summary[f'{key}_collapsed_faces'].update(map(int, face_ids[collapsed[key]]))
                summary[f'{key}_orientation_disagreement_faces'].update(map(int, face_ids[q['valid_faces'] & (orientation[key] <= 0)]))
            introduced = q['valid_faces'] & collapsed['new'] & ~collapsed['old']
            turns = q['valid_faces'] & (orientation['new'] <= 0) & (orientation['old'] > 0)
            shade = q['valid_faces'] & (normals_dot['new'] <= 0) & (normals_dot['old'] > 0)
            summary['introduced_collapsed_faces'].update(map(int, face_ids[introduced]))
            summary['introduced_orientation_disagreement_faces'].update(map(int, face_ids[turns]))
            summary['introduced_normal_disagreement_faces'].update(map(int, face_ids[shade]))
            strain = (edge_ratio['new'] > 2) & (edge_ratio['old'] <= 2)
            summary['introduced_edge_strain_source_vertex_pairs'].update(map(tuple, used[q['edges'][strain]].tolist()))
            pairs = q['pairs']; sharp_count = 0
            if len(pairs):
                old_angle = np.degrees(np.arccos(np.clip((normals['old'][pairs[:, 4]] * normals['old'][pairs[:, 5]]).sum(1), -1, 1)))
                new_angle = np.degrees(np.arccos(np.clip((normals['new'][pairs[:, 4]] * normals['new'][pairs[:, 5]]).sum(1), -1, 1)))
                old_gap = np.maximum(np.linalg.norm(posed['old'][pairs[:, 0]] - posed['old'][pairs[:, 2]], axis=1), np.linalg.norm(posed['old'][pairs[:, 1]] - posed['old'][pairs[:, 3]], axis=1))
                sharp = (new_angle > 120) & (old_angle < 60) & (old_gap < .0001)
                sharp_count = int(sharp.sum()); summary['introduced_sharp_pairs'].update(map(tuple, face_ids[pairs[sharp, 4:6]].tolist()))
            sample['parts'].append({'mesh': name, **metric, 'introduced_collapse_face_ids': face_ids[introduced].tolist(),
                'introduced_rest_orientation_disagreement_face_ids': face_ids[turns].tolist(),
                'introduced_geometry_rendered_disagreement_face_ids': face_ids[shade].tolist(),
                'introduced_edge_strain_over_2_count': int(strain.sum()), 'introduced_closed_edge_dihedral_over_120_from_below_60': sharp_count})
        samples.append(sample)
        if ri % 100 == 0: print(ri, 'of', len(rows), flush=True)
    for name, s in summaries.items():
        summaries[name] = {k: {'unique_count': len(v), 'source_ids': sorted(v)} for k, v in s.items()}
    report = {'source': str(args.source), 'source_sha256': sha(args.source), 'candidate': str(args.candidate),
        'candidate_sha256': sha(args.candidate), 'native': str(args.native), 'tool_sha256': sha(Path(__file__)),
        'static_rows': sum(r['kind'] == 'static' for r in rows), 'continuous_rows': sum(r['kind'] == 'continuous' for r in rows),
        'scope': scope, 'summary': summaries, 'samples': samples,
        'limitations': ['Raw source GLB skin/normal decoding replayed with actual candidate bones and scalar values; Godot UNORM/octahedral quantization not re-exported',
        'Old control values use the source AP function with actual shared blend envelope; actual old runtime is not recaptured',
        'Rest-normal transport sign is a diagnostic, not a topological inversion certificate; no no-fit folded reference is used',
        'Dihedrals include physical UV copies within each mesh; cross-mesh cut edges are covered by the separate seam audit',
        'No full triangle-triangle self-intersection certificate or human naturalness verdict']}
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'source': report['source_sha256'], 'scope': {n: {k: v for k, v in q.items() if k != 'source_face_ids'} for n, q in scope.items()},
                      'summary': {n: {k: v['unique_count'] for k, v in q.items()} for n, q in summaries.items()}}, indent=2))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for n in ['source', 'candidate', 'native', 'output']: p.add_argument('--' + n, required=True, type=Path)
    p.add_argument('--character', default='mio')
    run(p.parse_args())

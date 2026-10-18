"""Review an offline weight-guided sleeve candidate against actual bone packets.

The selected face IDs are diagnostic witnesses from image ray attribution, never
production selection rules. A transported local guide normal is a deformation
reference, not a claim that every normal turn is a topological mesh inversion.
Native rendering and garment fit remain separate acceptance requirements.
"""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from scipy.spatial import cKDTree
from glb_io import load
from prepare_local_garments import read
from sew_arm_seams import dense_part
from synchronize_sleeve_corrective_seams import posed_part
from motion_math import world_matrices
from corrective_normals import unit


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def adjacent_faces(part):
    """Join only source same-position/same-skin UV copies before edge lookup."""
    parent = np.arange(len(part['pos']))
    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for a, b in cKDTree(part['pos']).query_pairs(1e-6, output_type='ndarray'):
        if np.max(abs(part['dense'][a] - part['dense'][b])) <= 1e-3:
            parent[root(b)] = root(a)
    labels = np.array([root(i) for i in range(len(parent))])
    faces = part['faces']
    edge_faces = {}
    for fi, face in enumerate(labels[faces]):
        for a, b in zip(face, np.roll(face, -1)):
            edge_faces.setdefault(tuple(sorted((a, b))), set()).add(fi)
    result = []
    for fi, face in enumerate(labels[faces]):
        neighbours = set()
        for a, b in zip(face, np.roll(face, -1)):
            neighbours.update(edge_faces[tuple(sorted((a, b)))])
        neighbours.discard(fi)
        result.append(sorted(neighbours))
    return result


def run(args):
    sd, sb = load(args.source)
    d, b = load(args.candidate)
    part_names = ['CharacterBody', 'Sleeve_Left', 'Sleeve_Right']
    old = {n['name']: dense_part(sd, sb, n) for n in sd['nodes'] if n.get('name') in part_names}
    parts = {n['name']: dense_part(d, b, n) for n in d['nodes'] if n.get('name') in part_names}
    for p in parts.values():
        p['faces'] = read(d, b, p['p']['indices']).reshape(-1, 3)
    p = parts[args.mesh]
    adj = adjacent_faces(p)
    guide_npz = np.load(args.trace_dir / f'{args.mesh}-SleeveFit_stretch_625.npz')
    guide = guide_npz['guide']
    gamma = guide_npz['gamma']
    ids = {n.get('name'): i for i, n in enumerate(d['nodes'])}
    sk = d['skins'][0]
    ib = read(d, b, sk['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    witness_ids = [int(i) for i in args.faces.split(',')]
    rows = [r for r in json.loads(args.manifest.read_text())['shots']
            if r['id'] == args.character and r['clip'] == 'stretch']
    samples = []
    for row in rows:
        world, _ = world_matrices(d, b)
        for bone in row['bones']:
            i = ids[bone['name'].replace('mixamorig_', 'mixamorig:')]
            world[i] = np.eye(4)
            world[i][:3, :3] = np.asarray(bone['basis']).T
            world[i][:3, 3] = np.asarray(bone['position']) - row['position']
        matrices = np.array([world[j] @ bind for j, bind in zip(sk['joints'], ib)])
        before, source_B, oldn = posed_part(sd, sb, old[args.mesh], row)
        replay = dict(row)
        replay['blend_shape_values'] = {name: dict(value) for name, value in row['blend_shape_values'].items()}
        extra_names = set(p['names']) - set(replay['blend_shape_values'][args.mesh])
        if extra_names:
            animation = next(a for a in d['animations'] if a['name'] == row['clip'])
            ni = d['nodes'].index(p['node'])
            channel = next(c for c in animation['channels'] if c['target'] == {'node': ni, 'path': 'weights'})
            sampler = animation['samplers'][channel['sampler']]
            times = read(d, b, sampler['input']).ravel()
            values = read(d, b, sampler['output']).reshape(-1, len(p['names']))
            replay_names = extra_names | {n for n in p['names'] if n.startswith('SleeveFit_stretch_')}
            for name in replay_names:
                replay['blend_shape_values'][args.mesh][name] = float(np.interp(row['clip_time'], times, values[:, p['names'].index(name)]))
        after, B, newn = posed_part(d, b, p, replay)
        guide_amount = sum(v for n, v in replay['blend_shape_values'][args.mesh].items()
                           if n.startswith(('SleeveFit_stretch_', 'SleeveGuide_stretch_')))
        guide_B = np.einsum('vj,jab->vab', guide, matrices[:, :3, :3])
        envelope = guide_amount * gamma
        effective_B = source_B * (1 - envelope[:, None, None]) + guide_B * envelope[:, None, None]
        triangles = after[p['faces']]
        normals = unit(np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0]))
        original_tri = before[p['faces']]
        old_normals = unit(np.cross(original_tri[:, 1] - original_tri[:, 0], original_tri[:, 2] - original_tri[:, 0]))
        reference = p['pos'][p['faces']]
        rest_cross = np.cross(reference[:, 1] - reference[:, 0], reference[:, 2] - reference[:, 0])
        packet = {'phase': row['phase'], 'view': row['view'], 'faces': []}
        rendered = unit(np.einsum('vij,vj->vi', B, unit(newn)))
        for fi in witness_ids:
            v = p['faces'][fi]
            G = effective_B[v].mean(0)
            if np.linalg.det(G) <= 0:
                raise ValueError('The diagnostic guide itself reverses local winding')
            ref = unit((G @ rest_cross[fi])[None])[0]
            neighbours = np.array(adj[fi], dtype=int)
            angles = np.degrees(np.arccos(np.clip(normals[neighbours] @ normals[fi], -1, 1)))
            old_angles = np.degrees(np.arccos(np.clip(old_normals[neighbours] @ old_normals[fi], -1, 1)))
            bone_weights = [{d['nodes'][j].get('name', ''): float(w)
                             for j, w in zip(sk['joints'], guide[vi]) if w > 1e-5} for vi in v]
            packet['faces'].append({
                'source_face': fi, 'vertices': v.tolist(), 'adjacent_source_faces': neighbours.tolist(),
                'source_guide_orientation_cosine': float(old_normals[fi] @ ref),
                'candidate_guide_orientation_cosine': float(normals[fi] @ ref),
                'reference_linear_determinant': float(np.linalg.det(G)),
                'source_adjacent_dihedral_degrees': old_angles.tolist(),
                'candidate_adjacent_dihedral_degrees': angles.tolist(),
                'candidate_geometry_rendered_normal_cosine': float(normals[fi] @ unit(rendered[v].mean(0)[None])[0]),
                'source_triangle': before[v].tolist(), 'candidate_triangle': after[v].tolist(),
                'world_displacement_m': np.linalg.norm(after[v] - before[v], axis=1).tolist(),
                'guide_bone_weights': bone_weights,
            })
        samples.append(packet)
    old_fail = sum(f['source_guide_orientation_cosine'] <= 0 for s in samples for f in s['faces'])
    new_fail = sum(f['candidate_guide_orientation_cosine'] <= 0 for s in samples for f in s['faces'])
    report = {
        'source': str(args.source), 'source_sha256': sha(args.source),
        'candidate': str(args.candidate), 'candidate_sha256': sha(args.candidate),
        'manifest': str(args.manifest), 'manifest_sha256': sha(args.manifest),
        'tool_sha256': sha(Path(__file__)), 'candidate_native': False,
        'scope': 'Image-attributed sleeve faces replayed with actual final bone/scalar packets; local guide orientation gate only',
        'reference': 'Topologically smoothed original skin weights transported by actual bones, blended from original skin by the anatomical ROI and the active stretch field envelope. At zero corrective amount the original skin reference is retained. Positive determinant checked separately; not no-fit folded geometry.',
        'witness_count': len(rows) * len(witness_ids),
        'source_nonpositive_orientation_witnesses': old_fail,
        'candidate_nonpositive_orientation_witnesses': new_fail,
        'regression_pass': old_fail > 0 and new_fail == 0,
        'limitations': ['Not a native image or naturalness pass', 'Not a full sleeve self-intersection or cloth-body distance certificate', 'Adjacent dihedral values disclosed; positive orientation alone does not prove a smooth surface'],
        'samples': samples,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(args.output, 'source_fail', old_fail, 'candidate_fail', new_fail)
    if args.expect_fixed and not report['regression_pass']:
        raise SystemExit(1)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['source', 'candidate', 'manifest', 'trace-dir', 'output']:
        p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--mesh', default='Sleeve_Right')
    p.add_argument('--character', default='mio')
    p.add_argument('--faces', default='1325,1369,199')
    p.add_argument('--expect-fixed', action='store_true')
    run(p.parse_args())

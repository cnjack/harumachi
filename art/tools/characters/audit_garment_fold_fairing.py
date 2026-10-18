"""Preservation and posed-surface preflight for a run-only fold candidate."""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

import numpy as np

from audit_garment_surface_witnesses import envelope
from audit_local_garments import mesh_state, pose
from prepare_local_garments import read


def run(args):
    source = mesh_state(args.source, 'mio')
    candidate = mesh_state(args.candidate, 'mio')
    source_sha = hashlib.sha256(args.source.read_bytes()).hexdigest()
    if json.loads((args.native.parent / 'model-hashes.json').read_text()).get('CH_mio.glb') != source_sha:
        raise ValueError('Native SHA mismatch')
    prefix = 'GarmentFoldFair_'
    added = [i for i, n in enumerate(candidate['names']) if n.startswith(prefix)]
    original_count = len(source['names'])
    assert candidate['names'][:original_count] == source['names']
    attrs_equal = {}
    sp = source['d']['meshes'][source['node']['mesh']]['primitives'][0]
    cp = candidate['d']['meshes'][candidate['node']['mesh']]['primitives'][0]
    for name, accessor in sp['attributes'].items():
        attrs_equal[name] = np.array_equal(read(source['d'], source['b'], accessor), read(candidate['d'], candidate['b'], cp['attributes'][name]))
    old_targets_equal = all(all(np.array_equal(read(source['d'], source['b'], accessor), read(candidate['d'], candidate['b'], cp['targets'][i][key]))
                                 for key, accessor in target.items()) for i, target in enumerate(sp['targets']))
    faces = read(source['d'], source['b'], sp['indices']).reshape(-1, 3)
    assert np.array_equal(faces, read(candidate['d'], candidate['b'], cp['indices']).reshape(-1, 3))
    original_anim_equal = True
    non_run_exact = True
    for animation in source['d']['animations']:
        other = next(a for a in candidate['d']['animations'] if a['name'] == animation['name'])
        for channel in animation['channels']:
            if channel['target']['path'] == 'weights' and channel['target']['node'] == source['ni']:
                continue
            match = next(c for c in other['channels'] if c['target'] == channel['target'])
            a, b = animation['samplers'][channel['sampler']], other['samplers'][match['sampler']]
            original_anim_equal &= all(np.array_equal(read(source['d'], source['b'], a[key]), read(candidate['d'], candidate['b'], b[key])) for key in ['input', 'output'])
        duration = max(float(read(source['d'], source['b'], item['input']).max()) for item in animation['samplers'])
        if animation['name'] != 'run':
            for phase in [0, .125, .375, .625, .875, 1]:
                before, _ = pose(source, animation['name'], phase * duration)
                after, _ = pose(candidate, animation['name'], phase * duration)
                non_run_exact &= np.array_equal(before, after)
    # Source rest coverage and actual outer-body visibility define surface
    # witnesses. Raw counts are retained; hidden/rear body points are not
    # mislabelled as visible front-facing skin. No original vertex is removed.
    body_faces = source['body_faces']
    rest_centres = source['positions'][body_faces].mean(1)
    local_region = (abs(rest_centres[:, 0]) > .075) & (abs(rest_centres[:, 0]) < .20)
    local_region &= (rest_centres[:, 1] > .60) & (rest_centres[:, 1] < .80)
    body_faces = body_faces[local_region]
    bary = np.asarray([[1, 0, 0], [0, 1, 0], [0, 0, 1], [.5, .5, 0], [.5, 0, .5], [0, .5, .5], [1/3, 1/3, 1/3]])
    rest_queries = np.einsum('wc,fcj->fwj', bary, source['positions'][body_faces]).reshape(-1, 3)
    rest_hits = envelope(source['positions'], source['cloth_faces'], rest_queries)
    rest_covered = np.asarray([h is not None and h['signed_depth_m'] <= 0 for h in rest_hits])
    captured = [json.loads(line.split(' ', 1)[1]) for line in args.native.read_text().splitlines() if line.startswith('GARMENT_FULL_SOURCE ')]
    captured = [row for row in captured if row['id'] == 'mio' and row['clip'] == 'run' and row['phase'] < 1]
    samples = []
    for row in captured:
        reference = row['measurement']
        phase = row['phase']
        before, _ = pose(source, 'run', reference['clip_time'], reference, actual_shapes=True)
        counterfactual = deepcopy(reference)
        values = counterfactual['blend_shape_values'][source['node']['name']]
        phase_keys = np.unique(np.r_[np.arange(16) / 16, .2, .8])
        for k, index in enumerate(added):
            curve = np.zeros(len(phase_keys) + 1)
            curve[k] = 1
            if k == 0:
                curve[-1] = 1
            values[candidate['names'][index]] = float(np.interp(phase % 1, np.r_[phase_keys, 1], curve))
        after, _ = pose(candidate, 'run', reference['clip_time'], counterfactual, actual_shapes=True)
        queries = np.einsum('wc,fcj->fwj', bary, before[body_faces]).reshape(-1, 3)
        body_hits = envelope(before, source['body_faces'], queries)
        actual_outer = np.asarray([h is not None and h['signed_depth_m'] >= -1e-7 for h in body_hits])
        valid = actual_outer & rest_covered
        before_hits = envelope(before, source['cloth_faces'], queries)
        after_hits = envelope(after, source['cloth_faces'], queries)
        before_depth = np.asarray([h['signed_depth_m'] if h else np.inf for h in before_hits])
        after_depth = np.asarray([h['signed_depth_m'] if h else np.inf for h in after_hits])
        shift = np.linalg.norm(after - before, axis=1)
        cross0 = np.cross(before[faces[:, 1]] - before[faces[:, 0]], before[faces[:, 2]] - before[faces[:, 0]])
        cross1 = np.cross(after[faces[:, 1]] - after[faces[:, 0]], after[faces[:, 2]] - after[faces[:, 0]])
        inverted = (np.einsum('ij,ij->i', cross0, cross1) <= 0) & (np.linalg.norm(cross0, axis=1) > 1e-12)
        samples.append({'phase': phase, 'surface_queries': len(queries), 'rest_covered_queries': int(rest_covered.sum()),
                        'actual_outer_body_source_covered_queries': int(valid.sum()),
                        'before_visible_depth_over_5mm': int(np.count_nonzero((before_depth > .005) & valid)),
                        'after_visible_depth_over_5mm': int(np.count_nonzero((after_depth > .005) & valid)),
                        'new_visible_depth_over_5mm': int(np.count_nonzero((before_depth <= .005) & (after_depth > .005) & valid)),
                        'maximum_added_posed_shift_m': float(shift.max()),
                        'newly_inverted_faces': int(inverted.sum()),
                        'maximum_body_shift_m': float(shift[source['body']].max())})
        print(phase, samples[-1]['before_visible_depth_over_5mm'], '->', samples[-1]['after_visible_depth_over_5mm'], flush=True)
    result = {'source': str(args.source), 'source_sha256': source_sha,
              'candidate': str(args.candidate), 'candidate_sha256': hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
              'scope': 'Source-native counterfactual preflight, not a candidate-native acceptance; unchanged native bones and old morphs plus new authored run curves. Extra surface witness region is fixed source upper thighs |x| .075-.20m / y .60-.80m; all original vertex anchors remain in production and strict tests.',
              'attributes_exact': attrs_equal, 'original_targets_exact': old_targets_equal,
              'all_original_non_weight_animation_tracks_exact': bool(original_anim_equal),
              'all_11_non_run_actions_at_6_phases_exact': bool(non_run_exact),
              'new_body_position_delta_max_m': max(float(np.linalg.norm(candidate['shapes'][i][source['body']], axis=1).max()) for i in added),
              'new_body_normal_delta_max': max(float(np.linalg.norm(read(candidate['d'], candidate['b'], cp['targets'][i]['NORMAL'])[source['body']], axis=1).max()) for i in added),
              'samples': samples}
    args.output.write_text(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--native', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    run(parser.parse_args())

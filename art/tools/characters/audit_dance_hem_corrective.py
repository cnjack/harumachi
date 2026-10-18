"""Full-source preflight of dance hem contact under known final native poses."""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

import numpy as np

from audit_local_garments import mesh_state, pose, measure
from prepare_sleeve_correctives import patch_weights


def run(args):
    source = mesh_state(args.native_source, 'mio')
    candidate = mesh_state(args.candidate, 'mio')
    sha = hashlib.sha256(args.native_source.read_bytes()).hexdigest()
    if json.loads((args.native.parent / 'model-hashes.json').read_text()).get('CH_mio.glb') != sha:
        raise ValueError('Native source hash mismatch')
    rows = [json.loads(line.split(' ', 1)[1]) for line in args.native.read_text().splitlines() if line.startswith('GARMENT_FULL_SOURCE ')]
    rows = [r for r in rows if r['id'] == 'mio' and r['clip'] == 'dance']
    animation = next(a for a in candidate['d']['animations'] if a['name'] == 'dance')
    samples = []
    for row in rows:
        reference = row['measurement']
        before, _ = pose(source, 'dance', reference['clip_time'], reference, actual_shapes=True)
        augmented = deepcopy(reference)
        values = augmented['blend_shape_values'][source['node']['name']]
        curve = patch_weights(candidate['d'], candidate['b'], animation, candidate['ni'], len(candidate['names']), np.asarray([reference['clip_time']]))[0]
        for index, name in enumerate(candidate['names']):
            if name not in values:
                if not name.startswith(('GarmentFoldFair_run_', 'GarmentHem_dance')):
                    raise ValueError('Unexpected target missing from actual source table')
                values[name] = float(curve[index])
        after, _ = pose(candidate, 'dance', reference['clip_time'], augmented, actual_shapes=True)
        b = measure(source, before)
        a = measure(candidate, after)
        samples.append({'phase': row['phase'], 'before': b, 'after': a,
                        'new_target_value': values.get('GarmentHem_dance', 0.),
                        'maximum_added_displacement_m': float(np.linalg.norm(after - before, axis=1).max()),
                        'maximum_body_displacement_m': float(np.linalg.norm(after[source['body']] - before[source['body']], axis=1).max())})
        print(row['phase'], b['max_penetration_m'] * 1000, '->', a['max_penetration_m'] * 1000, flush=True)
    result = {'native_source': str(args.native_source), 'native_source_sha256': sha,
              'candidate': str(args.candidate), 'candidate_sha256': hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
              'scope': 'Source-native counterfactual preflight; actual original bone matrices and original morph coefficients, plus only the new authored action fields. Full independently labelled source panels, exterior selected before original0.35 normal gate; unchanged5mm gate. Production post-IK re-solve and actual candidate native acceptance still required.',
              'samples': samples,
              'passes_original_5mm_gate': all(s['after']['max_penetration_m'] <= .005 for s in samples),
              'body_unchanged': all(s['maximum_body_displacement_m'] == 0 for s in samples),
              'bounded_9mm': all(s['maximum_added_displacement_m'] <= .00901 for s in samples)}
    args.output.write_text(json.dumps(result, indent=2))
    if not result['passes_original_5mm_gate'] or not result['body_unchanged'] or not result['bounded_9mm']:
        raise SystemExit(1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-source', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--native', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    run(parser.parse_args())

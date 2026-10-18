"""Check dense versus cached-support contact arithmetic on real cloth templates."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from audit_local_garments import mesh_state


def run(args):
    rng = np.random.default_rng(20261017)
    reports = []
    for who in ['mio', 'ren', 'kazuko']:
        path = args.models / f'CH_{who}.glb'
        state = mesh_state(path, who)
        coefficients = np.stack([state['shapes'][i][:, 2] for i in state['local']], axis=1)
        faces = state['cloth_faces']
        chosen = rng.integers(0, len(faces), args.samples)
        mismatches = 0
        factor_mismatches = 0
        support_sizes = []
        for face in faces[chosen]:
            active = np.flatnonzero(np.any(coefficients[face] != 0, axis=0))
            support_sizes.append(len(active))
            bary = rng.dirichlet(np.ones(3)).astype(np.float32)
            directions = rng.uniform(-1, 1, 3)
            slopes = np.zeros(len(state['local']), np.float32)
            lifted_slopes = np.zeros(len(state['local']), np.float32)
            # PackedFloat32 writes after each original corner accumulation.
            for corner in range(3):
                factor = float(bary[corner]) * directions[corner]
                for patch in np.flatnonzero(coefficients[face[corner]] != 0):
                    slopes[patch] = float(slopes[patch]) + float(bary[corner]) * directions[corner] * float(coefficients[face[corner], patch])
                    lifted_slopes[patch] = float(lifted_slopes[patch]) + factor * float(coefficients[face[corner], patch])
            factor_mismatches += not np.array_equal(slopes, lifted_slopes)
            amounts = rng.uniform(0, 1, len(slopes)).astype(np.float32)
            previous = rng.uniform(0, 1, len(slopes)).astype(np.float32)
            depth = float(rng.uniform(-.03, .12))

            def evaluate(ids):
                required = depth + .006
                for patch in ids:
                    required -= float(slopes[patch]) * (float(amounts[patch]) - float(previous[patch]))
                divisor = 0.
                for patch in ids:
                    if slopes[patch] > 0 and amounts[patch] < 1:
                        divisor += float(slopes[patch]) * float(slopes[patch])
                new = amounts.copy()
                if required > .0001 and divisor >= 1e-8:
                    for patch in ids:
                        if slopes[patch] > 0:
                            new[patch] = min(1., float(amounts[patch]) + required * float(slopes[patch]) / divisor)
                return required, divisor, new

            dense = evaluate(range(len(slopes)))
            sparse = evaluate(active)
            mismatches += dense[0].hex() != sparse[0].hex() or dense[1].hex() != sparse[1].hex() or not np.array_equal(dense[2], sparse[2])
        reports.append({'character': who, 'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                        'constraints': len(chosen), 'bitwise_mismatches': int(mismatches),
                        'lifted_corner_prefix_bitwise_mismatches': int(factor_mismatches),
                        'dense_patch_visits': len(state['local']),
                        'cached_support_mean': float(np.mean(support_sizes)),
                        'cached_support_max': int(max(support_sizes))})
        print(who, 'mismatches', mismatches, 'mean support', round(float(np.mean(support_sizes)), 3), flush=True)
    result = {'scope': 'Real source template supports; random signed skin directions/barycentrics/current and previous coefficients; original per-corner PackedFloat32 accumulation, increasing-patch double arithmetic and PackedFloat32 output preserved. Native CPU timing remains separate.',
              'cases': reports, 'passed': all(row['bitwise_mismatches'] == 0 and row['lifted_corner_prefix_bitwise_mismatches'] == 0 for row in reports)}
    args.output.write_text(json.dumps(result, indent=2))
    if not result['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models', required=True, type=Path)
    parser.add_argument('--samples', default=10000, type=int)
    parser.add_argument('--output', required=True, type=Path)
    run(parser.parse_args())

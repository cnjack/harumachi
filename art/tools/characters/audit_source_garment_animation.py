"""Check authored cloth on complete source surfaces with no game modifiers.

Original body vertices and seven witnesses on every labelled body triangle use
the unchanged 5mm depth / .35 normal gates. An optional same-pose source reference
also reports cloth displacement; it is not a measurement of cloth-to-skin gap.
"""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np
from glb_io import durations
from audit_local_garments import mesh_state, pose
from audit_native_garment_surfaces import witnesses, complete_painted_cloth_union
from source_surface_rays import envelope


def audit(model, actor, phases, reference=None):
    state = mesh_state(model, actor)
    panels, domain = complete_painted_cloth_union(state, actor)
    triangles, barycentrics, coverage = witnesses(state, actor)
    lengths = durations(model)
    baseline = mesh_state(reference, actor) if reference else None
    cloth_faces = np.unique(np.concatenate(list(panels.values())), axis=0)
    rest = state['positions'][cloth_faces]
    areas = np.linalg.norm(np.cross(rest[:, 1]-rest[:, 0], rest[:, 2]-rest[:, 0]), axis=1)*.5
    rows = []
    for clip in ['idle', 'walk', 'run']:
        for index in range(phases):
            time = lengths[clip]*index/phases
            points, _ = pose(state, clip, time)
            queries = np.r_[points[state['body']], np.einsum('wc,wcj->wj', barycentrics, points[triangles])]
            layers = {}
            for side, sign in [('front', 1), ('back', -1)]:
                hit = envelope(points, panels[side], queries, sign)
                accepted = np.isfinite(hit['signed_depth_m']) & (hit['normal_abs_dot_ray'] >= .35)
                values = hit['signed_depth_m'][accepted]
                layers[side] = {'covered_queries': int(accepted.sum()),
                                'maximum_penetration_m': max(0., float(values.max(initial=0.))),
                                'over_original_5mm_gate': int((values > .005).sum())}
            row = {'clip': clip, 'phase': index/phases, 'layers': layers}
            if baseline:
                prior, _ = pose(baseline, clip, time)
                displacement = np.linalg.norm(points-prior, axis=1)
                face_mean = displacement[cloth_faces].mean(axis=1)
                row['fit_displacement'] = {
                    'maximum_m': float(displacement.max()),
                    'body_maximum_m': float(displacement[state['body']].max(initial=0.)),
                    'cloth_area_weighted_mean_m': float(face_mean @ areas / areas.sum()),
                    'cloth_area_fraction_mean_over_1mm': float(areas[face_mean > .001].sum()/areas.sum())}
            rows.append(row)
        print(actor, clip, 'samples', phases,
              'max_m', max(layer['maximum_penetration_m'] for row in rows if row['clip'] == clip for layer in row['layers'].values()), flush=True)
    result = {'actor': actor, 'source_sha256': hashlib.sha256(model.read_bytes()).hexdigest(),
              'reference_sha256': hashlib.sha256(reference.read_bytes()).hexdigest() if reference else None,
              'phases_per_clip': phases, 'game_modifiers': 0, 'gate_m': .005, 'normal_gate': .35,
              'domains': domain, 'body_witnesses': coverage, 'rows': rows,
              'passed': all(layer['over_original_5mm_gate'] == 0 and layer['covered_queries'] > 0
                            for row in rows for layer in row['layers'].values()),
              'scope': 'Discrete full-source collision and optional displacement; native fit, self-intersection and naturalness need separate visual review.'}
    if baseline:
        result['passed'] &= all(row['fit_displacement']['body_maximum_m'] < .000001 and row['fit_displacement']['maximum_m'] <= .1205 for row in rows)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--character', choices=['mio', 'kazuko'], required=True)
    parser.add_argument('--reference', type=Path)
    parser.add_argument('--phases', type=int, default=256)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.phases < 2:
        parser.error('--phases must be at least 2')
    report = audit(args.model, args.character, args.phases, args.reference)
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    raise SystemExit(0 if report['passed'] else 1)

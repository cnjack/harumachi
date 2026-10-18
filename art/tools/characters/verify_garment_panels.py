"""Independent source-cloth coverage and contact preflight for candidate GLBs.

Coverage uses source pigments and anatomical hip depth, never the candidate's
patch support. Counterfactual native rows reuse only final bones and original
shape values; all local amounts are solved anew. Native candidate QA is required.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from audit_local_garments import mesh_state, pose, measure, solve, template_seam_gap
from prepare_local_garments import read


def verify(args):
    state = mesh_state(args.input, args.character)
    p = state['positions']
    h = float(p[:, 1].max())
    faces = state['cloth_faces']
    support = np.maximum.reduce([np.linalg.norm(state['shapes'][i], axis=1) for i in state['local']])
    contact_region = np.all(p[faces, 1] < .55*h, axis=1)
    missing = contact_region & np.any(support[faces] < 1e-7, axis=1)
    tri = p[faces]
    areas = np.linalg.norm(np.cross(tri[:, 1]-tri[:, 0], tri[:, 2]-tri[:, 0]), axis=1)*.5
    body_delta = max(float(np.linalg.norm(state['shapes'][i][state['body']], axis=1).max()) for i in state['local'])
    coverage = {
        'source_pigment_cloth_triangles': len(faces),
        'leg_contact_region_source_triangles': int(contact_region.sum()),
        'unsupported_contact_region_triangles': int(missing.sum()),
        'unsupported_contact_region_area_fraction': float(areas[missing].sum()/areas[contact_region].sum()),
        'body_vertices': len(state['body']),
        'body_cloth_overlap': len(np.intersect1d(state['body'], state['cloth_vertices'])),
        'body_local_delta_max_m': body_delta,
        'uv_template_gap_m': template_seam_gap(state),
        'waist_pin_scope': 'Source waist is feathered to zero above .55 height; lower leg-contact cloth is fully supported.'
    }
    coverage['pass'] = (coverage['unsupported_contact_region_triangles'] == 0 and
                        coverage['body_cloth_overlap'] == 0 and body_delta < 1e-7 and
                        coverage['uv_template_gap_m'] < .0001)
    samples = []
    if not args.coverage_only:
        rows = []
        for clip in ['walk', 'run', 'dance', 'idle', 'wave', 'bow', 'look', 'stretch', 'tend', 'talk', 'cheer']:
            a = next(a for a in state['d']['animations'] if a['name'] == clip)
            length = max(float(read(state['d'], state['b'], s['input']).max()) for s in a['samplers'])
            phases = sorted(list(np.linspace(0, 1, 17))+[.2, .8]) if clip in ['walk', 'run', 'dance'] else [.5]
            for phase in phases:
                rows.append({'kind': 'authored65', 'clip': clip, 'phase': float(phase), 'clip_time': float(length*(phase % 1))})
        assert len(rows) == 65
        native = {}
        for manifest in args.native_manifest:
            for row in json.loads(manifest.read_text())['shots']:
                if row['id'] != args.character: continue
                key = (row['clip'], round(row['clip_time'], 7))
                native.setdefault(key, {**row, 'kind': 'source_native_counterfactual', 'reference_manifest': str(manifest)})
        rows.extend(native.values())
        for row in rows:
            actual_native = row['kind'] == 'source_native_counterfactual'
            base, direction = pose(state, row['clip'], row['clip_time'], row if actual_native else None,
                                   disable_global=True, actual_shapes=actual_native, disable_local=True,
                                   counterfactual_new_shapes=actual_native)
            original = measure(state, base)
            posed, amounts, saturated = solve(state, base, direction)
            measured = measure(state, posed)
            shift = np.linalg.norm(posed-base, axis=1)
            moved = shift[state['cloth_vertices']]
            result = {'kind': row['kind'], 'clip': row['clip'], 'phase': row['phase'],
                      'before_max_penetration_m': original['max_penetration_m'],
                      'after_max_penetration_m': measured['max_penetration_m'],
                      'before_covered_vertices': original['covered_body_vertices'],
                      'after_covered_vertices': measured['covered_body_vertices'],
                      'max_shift_m': float(shift.max()), 'shift_p95_m': float(np.percentile(moved[moved > 1e-7], 95)) if np.any(moved > 1e-7) else 0,
                      'saturated_constraints': int(saturated), 'maximum_local_amount': float(max(amounts))}
            if actual_native: result['reference_file'] = row['file']
            samples.append(result)
            print(args.character, row['kind'], row['clip'], row['phase'],
                  round(original['max_penetration_m']*1000, 3), '->',
                  round(measured['max_penetration_m']*1000, 3), 'mm', flush=True)
    checks = {'coverage': coverage['pass'],
              'all_recomputed_source_panels_under_5mm': all(s['after_max_penetration_m'] <= .005 for s in samples),
              'all_recomputed_source_panels_under_12cm_shift': all(s['max_shift_m'] <= .1205 for s in samples),
              'all_samples_keep_real_body_coverage': all(s['after_covered_vertices'] > 100 for s in samples)}
    report = {'input': str(args.input), 'input_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
              'character': args.character, 'scope': 'independent full source pigment/hip-axis coverage; full-source recomputation is preflight, not native production-proxy proof',
              'coverage': coverage, 'samples': samples, 'checks': checks, 'pass': all(checks.values())}
    args.output.write_text(json.dumps(report, indent=2))
    print(args.output, report['pass'], coverage, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--character', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--native-manifest', action='append', default=[], type=Path)
    parser.add_argument('--coverage-only', action='store_true')
    verify(parser.parse_args())

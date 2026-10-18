#!/usr/bin/env python3
"""Regress two measured rig transition defects in a native transition-gait.json.

This does not grade natural gait or fast swing. Exit 0 means eligible samples
passed, 1 means a measured regression, and 2 means missing/ineligible evidence.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

GESTURE_LIMIT = .003
STARTUP_LIMIT = .020
STARTUP_MAX_DT = .020
ROOT_STABLE_LIMIT = .001
BASIS_STABLE_LIMIT = 1e-5


def root(row):
    return tuple(float(v) for v in row['actor_position'])


def envelope(row, side):
    points = row['feet'][side]['cached_points_world']
    if len(points) < 8:
        raise ValueError('Fewer than eight real cached shoe points')
    height = min(float(p[1]) for p in points)
    if not math.isfinite(height):
        raise ValueError('Non-finite cached shoe geometry')
    reported = row['feet'][side].get('min_y')
    if reported is not None and abs(float(reported) - height) > 1e-6:
        raise ValueError('Reported min_y disagrees with the actual cached points')
    return height


def gesture_windows(frames):
    windows = []
    index = 1
    while index < len(frames) - 1:
        if frames[index]['clip'] != '' or frames[index - 1]['clip'] not in ('wave', 'bow'):
            index += 1
            continue
        end = index
        while end + 1 < len(frames) and frames[end + 1]['clip'] == '':
            end += 1
        if end + 1 >= len(frames) or frames[end + 1]['clip'] != 'idle':
            index = end + 1
            continue
        before, after = frames[index - 1], frames[end + 1]
        interval = frames[index - 1:end + 2]
        root_shift = max(math.dist(root(before), root(r)) for r in interval)
        record = {'gesture': before['clip'], 'before_frame': before['frame'], 'empty_frames': [r['frame'] for r in frames[index:end + 1]], 'after_frame': after['frame'], 'root_shift_m': root_shift, 'assessed': False}
        if root_shift > ROOT_STABLE_LIMIT:
            record['skip_reason'] = 'root moved; outside fixed-ground stationary gesture fixture'
        else:
            sides = {}
            for side in ('L', 'R'):
                low_before, low_after = envelope(before, side), envelope(after, side)
                empty = [envelope(r, side) for r in frames[index:end + 1]]
                deviation = max(abs(v - reference) for v in empty for reference in (low_before, low_after))
                sides[side] = {'before_min_y_m': low_before, 'after_min_y_m': low_after, 'empty_min_y_m': empty, 'reference_difference_m': abs(low_before - low_after), 'maximum_empty_deviation_m': deviation}
            record['sides'] = sides
            if max(s['reference_difference_m'] for s in sides.values()) > GESTURE_LIMIT:
                record['skip_reason'] = 'before/after support is not the same stable height'
            else:
                record.update({'assessed': True, 'ok': all(s['maximum_empty_deviation_m'] <= GESTURE_LIMIT for s in sides.values())})
        windows.append(record)
        index = end + 1
    return windows


def relative_joint(row, joint):
    return tuple(float(v) - p for v, p in zip(row['joints'][joint], root(row)))


def startup_windows(frames, domain='strict-static-root'):
    windows = []
    for index in range(2, len(frames)):
        before, after = frames[index - 1], frames[index]
        if before['clip'] != 'idle' or after['clip'] != 'walk':
            continue
        history = frames[max(0, index - 3):index]
        dt = float(after['elapsed_s']) - float(before['elapsed_s'])
        record = {'before_frame': before['frame'], 'after_frame': after['frame'], 'dt_s': dt, 'assessed': False}
        stable = len(history) >= 2 and all(r['clip'] == 'idle' for r in history)
        if domain == 'stable-relative-pose':
            stable = stable and len(history) == 3
            stable = stable and max(math.dist(relative_joint(before, joint), relative_joint(r, joint)) for r in history for joint in ('hips', 'foot.L', 'foot.R')) <= ROOT_STABLE_LIMIT
            basis_step = max(math.dist(a, b) for r in history + [after] for a, b in zip(before['model_basis'], r['model_basis']))
            stable = stable and basis_step <= BASIS_STABLE_LIMIT
            record['maximum_model_basis_column_change'] = basis_step
        else:
            stable = stable and max(math.dist(root(before), root(r)) for r in history) <= ROOT_STABLE_LIMIT
        if not stable:
            record['skip_reason'] = 'idle relative hips/feet or model orientation was not stable' if domain == 'stable-relative-pose' else 'idle root was not stationary immediately before startup'
        elif dt <= 0 or dt > STARTUP_MAX_DT + 1e-9:
            record['skip_reason'] = 'frame interval outside the <=20ms startup observation'
        elif math.dist(root(before), root(after)) > .05:
            record['skip_reason'] = 'root discontinuity; not an ordinary walk startup'
        else:
            steps = {}
            for joint in ('hips', 'foot.L', 'foot.R'):
                steps[joint] = math.dist(relative_joint(before, joint), relative_joint(after, joint))
            record.update({'assessed': True, 'actor_relative_steps_m': steps, 'ok': max(steps.values()) <= STARTUP_LIMIT})
        windows.append(record)
    return windows


def audit(document, checks=('gesture', 'startup'), startup_domain='strict-static-root'):
    if document.get('failures'):
        raise ValueError('Native capture reports failures; it cannot establish transition coverage')
    cases, coverage, violations = [], [], []
    for case in document['cases']:
        if int(case.get('sampling_failures', 0)):
            raise ValueError('Native final-pose pairing failed for ' + case['character'])
        rows = case['frames']
        result = {'character': case['character']}
        for kind, reader in [('gesture', gesture_windows), ('startup', lambda frames: startup_windows(frames, startup_domain))]:
            if kind not in checks:
                continue
            windows = reader(rows)
            result[kind] = windows
            eligible = [r for r in windows if r['assessed']]
            if kind == 'gesture':
                for clip in ('wave', 'bow'):
                    if not any(r['gesture'] == clip for r in eligible):
                        coverage.append(case['character'] + ': missing eligible ' + clip + ' -> empty -> idle')
            for row in eligible:
                if not row['ok']:
                    violations.append({'character': case['character'], 'kind': kind, **row})
        cases.append(result)
    if not cases:
        coverage.append('No character cases')
    if 'startup' in checks and not any(r['assessed'] for c in cases for r in c.get('startup', [])):
        coverage.append('No eligible stationary idle -> walk frame within20ms')
    counts = {kind: {'assessed': sum(r['assessed'] for c in cases for r in c.get(kind, [])), 'skipped': sum(not r['assessed'] for c in cases for r in c.get(kind, []))} for kind in checks}
    code = 2 if coverage else 1 if violations else 0
    return {'scope': 'Only stationary gesture empty-frame support and first-frame stable idle/walk correction jumps; no claim of overall gait naturalness or swing-speed acceptance', 'startup_domain': startup_domain, 'thresholds': {'gesture_empty_height_m': GESTURE_LIMIT, 'startup_actor_relative_step_m': STARTUP_LIMIT, 'startup_max_frame_interval_s': STARTUP_MAX_DT, 'stationary_root_or_relative_pose_m': ROOT_STABLE_LIMIT, 'model_basis_column_change': BASIS_STABLE_LIMIT}, 'checks': list(checks), 'exit_code': code, 'passed': code == 0, 'assessment_counts': counts, 'coverage_errors': coverage, 'violations': violations, 'cases': cases}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--checks', nargs='+', choices=['gesture', 'startup'], default=['gesture', 'startup'])
    parser.add_argument('--startup-domain', choices=['strict-static-root', 'stable-relative-pose'], default='strict-static-root')
    args = parser.parse_args()
    try:
        report = audit(json.loads(args.input.read_text()), args.checks, args.startup_domain)
    except (ValueError, KeyError, TypeError) as error:
        report = {'exit_code': 2, 'passed': False, 'error': str(error)}
    report.update({'source': str(args.input), 'source_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(), 'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()})
    for name in ('source-hashes.json', 'model-hashes.json'):
        provenance = args.input.parent.parent / name
        if provenance.exists():
            report[name] = json.loads(provenance.read_text())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'exit_code': report['exit_code'], 'assessment_counts': report.get('assessment_counts', {}), 'violations': len(report.get('violations', [])), 'coverage_errors': report.get('coverage_errors', []), 'output': str(args.output)}))
    return report['exit_code']


if __name__ == '__main__':
    raise SystemExit(main())

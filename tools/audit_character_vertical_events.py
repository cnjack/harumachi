#!/usr/bin/env python3
"""Locate native foot vertical events and decompose optional atomic modifier traces.

This is a diagnostic, not a swing-speed acceptance gate. Root-relative final
joint increments are ranked separately for each character. Missing causal traces
are marked unavailable; final ground gaps do not imply safety IK was enabled.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path


def y(point):
    return float(point[1])


def causal(row, side):
    support = row.get('foot_support_trace', {})
    natural = row.get('natural_pose_trace', {})
    result = {'support_trace_fresh': support.get('frame') == row['frame'], 'natural_trace_fresh': natural.get('frame') == row['frame']}
    if result['support_trace_fresh']:
        result.update({'support_enabled': support.get('enabled'), 'support_applied': support.get('applied'), 'process_delta_s': support.get('process_delta_s')})
        trace = support.get('sides', {}).get(side)
        if trace:
            result.update({'support_before': trace['before'], 'support_after': trace['after'], 'support_requested_correction_m': trace['correction'], 'support_actual_ankle_dy_m': y(trace['after']['ankle_world']) - y(trace['before']['ankle_world'])})
    if result['natural_trace_fresh']:
        key = 'foot.' + side
        if key in natural.get('before', {}) and key in natural.get('after', {}):
            result.update({'natural_before_ankle_world': natural['before'][key], 'natural_after_ankle_world': natural['after'][key], 'natural_actual_ankle_dy_m': y(natural['after'][key]) - y(natural['before'][key]), 'natural_transition_elapsed_s': natural.get('transition_elapsed'), 'natural_transition_duration_s': natural.get('transition_duration')})
            if key in natural.get('desired', {}):
                result['natural_desired_ankle_world'] = natural['desired'][key]
    return result


def events(case, count):
    rows = case['frames']
    changes = [(r['elapsed_s'], previous['clip'], r['clip']) for previous, r in zip(rows, rows[1:]) if previous['clip'] != r['clip']]
    last_change = float(rows[0]['elapsed_s'])
    found = []
    for index, (before, after) in enumerate(zip(rows, rows[1:]), 1):
        if after['clip'] != before['clip']:
            last_change = float(after['elapsed_s'])
        dt = float(after['elapsed_s']) - float(before['elapsed_s'])
        if dt <= 0:
            continue
        for side in ('L', 'R'):
            key = 'foot.' + side
            foot_before, foot_after = before['joints'][key], after['joints'][key]
            root_dy = y(after['actor_position']) - y(before['actor_position'])
            dy = y(foot_after) - y(foot_before) - root_dy
            shoe_before, shoe_after = before['feet'][side], after['feet'][side]
            ca, cb = causal(before, side), causal(after, side)
            event = {'index': index, 'side': side, 'frame_pair': [before['frame'], after['frame']], 'time_pair_s': [before['elapsed_s'], after['elapsed_s']], 'wall_dt_ms': dt * 1000, 'clip_pair': [before['clip'], after['clip']], 'phase_pair': [before['phase'], after['phase']], 'playback_pair': [before['playback_scale'], after['playback_scale']], 'dy_root_relative_mm': dy * 1000, 'dy_world_mm': (dy + root_dy) * 1000, 'vertical_velocity_wall_mps': dy / dt, 'shoe_ground_gap_mm': [shoe_before['ground_gap'] * 1000, shoe_after['ground_gap'] * 1000], 'shoe_min_y_delta_mm': (shoe_after['min_y'] - shoe_before['min_y']) * 1000, 'root_step_mm': math.dist(before['actor_position'], after['actor_position']) * 1000, 'since_clip_change_s': float(after['elapsed_s']) - last_change, 'causal_pair': [ca, cb]}
            process_dt = cb.get('process_delta_s')
            if process_dt:
                event['process_delta_s'] = process_dt
                event['vertical_velocity_process_mps'] = dy / process_dt
            if changes:
                nearest = min(changes, key=lambda c: abs(float(after['elapsed_s']) - c[0]))
                event['nearest_clip_change'] = {'elapsed_s': nearest[0], 'clips': nearest[1:], 'offset_ms': (float(after['elapsed_s']) - nearest[0]) * 1000}
            if 'support_actual_ankle_dy_m' in ca and 'support_actual_ankle_dy_m' in cb:
                support_delta = cb['support_actual_ankle_dy_m'] - ca['support_actual_ankle_dy_m']
                pre_dy = y(cb['support_before']['ankle_world']) - y(ca['support_before']['ankle_world']) - root_dy
                event['decomposition_mm'] = {'before_support_dy': pre_dy * 1000, 'support_change': support_delta * 1000, 'final_dy': dy * 1000, 'residual': (dy - pre_dy - support_delta) * 1000}
                if 'natural_actual_ankle_dy_m' in ca and 'natural_actual_ankle_dy_m' in cb:
                    raw = y(cb['natural_before_ankle_world']) - y(ca['natural_before_ankle_world']) - root_dy
                    correction = cb['natural_actual_ankle_dy_m'] - ca['natural_actual_ankle_dy_m']
                    event['decomposition_mm'].update({'before_natural_dy': raw * 1000, 'natural_change': correction * 1000, 'all_modifiers_residual': (dy - raw - correction - support_delta) * 1000})
            found.append(event)
    found.sort(key=lambda e: abs(e['dy_root_relative_mm']), reverse=True)
    return {'character': case['character'], 'requested_clip': case.get('requested_clip'), 'frame_count': len(rows), 'top_events': found[:count]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--count', type=int, default=3)
    args = parser.parse_args()
    doc = json.loads(args.input.read_text())
    report = {'scope': __doc__.strip(), 'source': str(args.input), 'source_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(), 'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'capture_failures': doc.get('failures', []), 'cases': [events(case, args.count) for case in doc['cases']]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'output': str(args.output), 'cases': [{'character': c['character'], 'requested_clip': c.get('requested_clip'), 'largest_root_relative_vertical_mm': c['top_events'][0]['dy_root_relative_mm'] if c['top_events'] else None} for c in report['cases']]}))


if __name__ == '__main__':
    main()

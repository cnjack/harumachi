#!/usr/bin/env python3
"""Keep game rendering, inference throughput and actually presented fresh frames distinct."""
import argparse
import json
import math
from pathlib import Path
import statistics
from collections import Counter

parser = argparse.ArgumentParser()
parser.add_argument('evidence', type=Path)
parser.add_argument('--prefix', default='live')
args = parser.parse_args()


def stats(values):
    ordered = sorted(values)
    if not ordered:
        return None
    return {'mean': statistics.mean(ordered), 'p50': statistics.median(ordered),
            'p95': ordered[math.ceil(len(ordered) * .95) - 1], 'max': ordered[-1], 'n': len(ordered)}


reports = []
for path in sorted(args.evidence.glob(args.prefix + '-*-overlay.json')):
    overlay = json.loads(path.read_text())
    phase = overlay['command']
    game = json.loads(path.with_name(path.name.replace('-overlay.json', '-game.json')).read_text())
    start, end = phase['start'], phase['end']
    duration = end - start
    game_all = game['frames']
    frames = [row for row in game_all if start <= row['unix'] < end]
    by_stamp = {row['stamp']: row for row in game_all}
    offset = overlay['unix_minus_host']
    processed = [row for row in overlay['frames'] if start <= row.get('processed_host', -offset) + offset < end]
    presented = [row for row in overlay['frames'] if start <= row.get('presented_unix', 0) < end]
    paired = [row for row in presented if row['source_stamp'] in by_stamp]
    target_file = args.evidence / 'presentation-targets.json'
    targets = overlay.get('presentation_targets') or (json.loads(target_file.read_text()) if target_file.exists() else {})
    presented_ids = set(int(row.get('presented_window', -1)) for row in presented)
    presentation_scope = ('preview' if presented_ids == {targets.get('preview')} else
                          'overlay' if presented_ids == {targets.get('overlay')} else
                          'none' if not presented_ids else 'first-enhanced-window')
    intervals = [(b['tick_usec'] - a['tick_usec']) / 1000 for a, b in zip(frames, frames[1:])]
    presentation_intervals = [(b['presented_host'] - a['presented_host']) * 1000 for a, b in zip(presented, presented[1:])]
    source_delays = [(row['presented_unix'] - by_stamp[row['source_stamp']]['unix']) * 1000 for row in paired]
    observed = []
    previous_stamp = -1
    for observation in overlay.get('display_observations', []):
        if observation['stamp'] < 0:
            continue
        if observation['stamp'] != previous_stamp and start <= observation['unix'] < end:
            observed.append(observation)
        previous_stamp = observation['stamp']
    processed_by_stamp = {}
    for row in overlay['frames']:
        if row.get('source_stamp', -1) >= 0 and 'processed_host' in row:
            processed_by_stamp.setdefault(row['source_stamp'], row)
    output_observed = [(row, processed_by_stamp[row['stamp']]) for row in observed
                       if row['stamp'] in processed_by_stamp and row['host'] >= processed_by_stamp[row['stamp']]['processed_host']]
    source_observed = [row for row in observed if row['stamp'] in by_stamp]
    report = {
        'id': phase['id'], 'scene': phase['scene'], 'mode': phase['mode'], 'seconds': duration,
        'game_fps': len(set(row['drawn'] for row in frames)) / duration,
        'game_frame_ms': stats(intervals), 'game_gpu_ms': stats([row['gpu_ms'] for row in frames]),
        'game_fps_cap': game['fps_cap'], 'viewport': game['viewport'],
        'overlay_processed_fps': len(processed) / duration,
        'overlay_presented_fps': len(presented) / duration,
        'overlay_fresh_source_fps': len(set(row['source_stamp'] for row in presented if row['source_stamp'] >= 0)) / duration,
        'overlay_present_interval_ms': stats(presentation_intervals),
        'processing_ms': stats([row['processing_ms'] for row in processed]),
        'capture_to_present_ms': stats([(row['presented_host'] - row['capture_host']) * 1000 for row in presented]),
        'capture_to_processed_ms': stats([(row['processed_host'] - row['capture_host']) * 1000 for row in processed]),
        'submit_to_present_ms': stats([(row['presented_host'] - row['submitted_host']) * 1000 for row in presented]),
        'source_render_callback_to_present_ms': stats(source_delays),
        'paired_source_frames': len(paired), 'presented_frames': len(presented),
        'presentation_windows': dict(Counter(str(int(row.get('presented_window', -1))) for row in presented)),
        'presentation_scope': presentation_scope, 'presentation_targets': targets,
        'valid_marker_frames': sum(row.get('source_stamp', -1) >= 0 for row in overlay['frames']),
        'queue_dropped_in_sample': max(0, processed[-1]['dropped_cumulative'] - processed[0]['dropped_cumulative']) if processed else 0,
        'negative_latency_samples': sum(value < 0 for value in source_delays),
        'compositor_observed_fps': len(observed) / duration,
        'compositor_verified_output_fps': len(output_observed) / duration,
        'compositor_marker_valid_fraction': sum(row['stamp'] >= 0 for row in overlay.get('display_observations', [])) / max(1, len(overlay.get('display_observations', []))),
        'source_callback_to_compositor_ms': stats([(row['unix'] - by_stamp[row['stamp']]['unix']) * 1000 for row in source_observed]),
        'capture_to_compositor_ms': stats([(row['host'] - processed_row['capture_host']) * 1000 for row, processed_row in output_observed]),
        'processed_to_compositor_ms': stats([(row['host'] - processed_row['processed_host']) * 1000 for row, processed_row in output_observed]),
        'app_error': overlay.get('app_error'), 'probe_error': overlay.get('probe_error')}
    reports.append(report)
    latency = report['capture_to_present_ms']
    delay = f"{latency['p50']:.1f} ms" if latency else 'unmeasured'
    print(f"{phase['scene']:20} {phase['mode']:18} game={report['game_fps']:5.1f} shown={report['overlay_presented_fps']:5.1f} "
          f"capture→shown={delay} paired={len(paired)}/{len(presented)}")
(args.evidence / (args.prefix + '-summary.json')).write_text(json.dumps(reports, ensure_ascii=False, indent=2) + '\n')

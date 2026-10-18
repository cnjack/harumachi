#!/usr/bin/env python3
"""Low-CPU boundary regression against the real GDScript gait expressions.

These contracts cover a decelerating NPC entering a compact walk too fast,
hysteresis, and the actual AnimationPlayer blend clock. They do not assess
character appearance or replace native last-callback transition recordings.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--char-source', type=Path, default=ROOT / 'game/scripts/player/char_anim.gd')
parser.add_argument('--natural-source', type=Path, default=ROOT / 'game/scripts/characters/natural_locomotion_pose.gd')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
CHAR = args.char_source.read_text()
NATURAL = args.natural_source.read_text()


def constant(name, source):
    match = re.search(r'^const ' + name + r'(?:\s*:[^=]+)?\s*:?=\s*(.+)$', source, re.M)
    return json.loads(match.group(1).strip()) if match else None


def threshold(state, walk_speed, rebuilt):
    if 'func _run_threshold()' not in CHAR:
        expression = re.search(r'elif speed > (.+?) and ap.has_animation\("run"\)', CHAR).group(1)
        return eval(expression, {'__builtins__': {}}, {'run_above': 2.85})
    # Execute the real small threshold method, after removing its GDScript
    # declaration/type syntax. No separate copy of its policy lives here.
    body = CHAR.split('func _run_threshold()', 1)[1].split('\n\nfunc ', 1)[0].split('\n', 1)[1]
    body = re.sub(r'var (\w+)\s*:\s*float\s*=', r'\1 =', body)
    namespace = {'__builtins__': {}, '_state': state, 'walk_speed': walk_speed,
                 'rebuilt_clips': rebuilt, 'run_above': 2.85, 'minf': min,
                 'REBUILT_WALK_RUN_ENTER': constant('REBUILT_WALK_RUN_ENTER', CHAR),
                 'REBUILT_WALK_RUN_EXIT': constant('REBUILT_WALK_RUN_EXIT', CHAR)}
    exec('def actual():\n' + body.expandtabs(4), namespace)
    return namespace['actual']()


def clock_increment(delta, speed):
    expression = re.search(r'^\s*_transition_elapsed\s*\+=\s*(.+)$', NATURAL, re.M).group(1)
    return eval(expression, {'__builtins__': {}},
                {'get_process_delta_time': lambda: delta, 'absf': abs,
                 'animation': SimpleNamespace(speed_scale=speed)})


class LocomotionPolicyContracts(unittest.TestCase):
    def test_normal_compact_walks_remain_walks(self):
        for speed in [1.15, 1.5]:
            self.assertGreater(threshold('walk', speed, ['walk', 'run']), speed)
            self.assertGreater(threshold('run', speed, ['walk', 'run']), speed)
        self.assertEqual(threshold('walk', 1.8, ['run']), 2.85)
        self.assertEqual(threshold('run', 1.8, ['run']), 2.85)

    def test_actual_threshold_has_two_distinct_boundaries(self):
        self.assertIn('elif speed > _run_threshold() and ap.has_animation("run"):', CHAR)
        for speed in [1.15, 1.5]:
            self.assertAlmostEqual(threshold('walk', speed, ['walk', 'run']), 1.35 * speed)
            self.assertAlmostEqual(threshold('run', speed, ['walk', 'run']), 1.20 * speed)

    def test_deceleration_never_enters_turbo_walk(self):
        for speed in [1.15, 1.5]:
            state = 'run'
            first_walk_speed = None
            for hundredths in range(310, int(speed * 100) - 1, -1):
                actual_speed = hundredths / 100
                state = 'run' if actual_speed > threshold(state, speed, ['walk', 'run']) else 'walk'
                if state == 'walk':
                    first_walk_speed = actual_speed
                    break
            self.assertIsNotNone(first_walk_speed)
            self.assertLessEqual(first_walk_speed / speed, 1.20 + 1e-9)

    def test_hysteresis_retains_each_side_in_its_band(self):
        for speed in [1.15, 1.5]:
            for state in ['walk', 'run']:
                current = state
                for ratio in [1.27, 1.24, 1.29, 1.26, 1.30, 1.25]:
                    current = 'run' if ratio * speed > threshold(current, speed, ['walk', 'run']) else 'walk'
                    self.assertEqual(current, state)

    def test_correction_clock_matches_real_ap_global_clock(self):
        for delta, scale in [(1/60, 2.432), (.02, .926), (0., 1.), (.01, 0.), (.015, -1.2)]:
            self.assertAlmostEqual(clock_increment(delta, scale), delta * abs(scale))
        # The empty-SceneTree native control establishes AP scale2.432 consumes
        # .22 blend units by .10s; the correction must not still be half done.
        self.assertGreaterEqual(sum(clock_increment(1/60, 2.432) for _ in range(6)), .22)

    def test_native_rejected_phase_directions_are_explicit(self):
        policy = constant('NORMALIZED_GAIT_DIRECTIONS', NATURAL) or {}
        self.assertEqual(policy, {'haru': ['walk', 'run'], 'mio': ['walk'], 'aoi': ['walk']})
        method = NATURAL.split('func match_gait_phase(', 1)[1].split('\nfunc ', 1)[0]
        self.assertIn('if next_clip in NORMALIZED_GAIT_DIRECTIONS.get(profile,[]):', method)
        self.assertLess(method.index('NORMALIZED_GAIT_DIRECTIONS'), method.index('_gait_phase_cache.has'))


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.loadTestsFromTestCase(LocomotionPolicyContracts))
    report = {'scope': __doc__.strip(), 'char_source': str(args.char_source),
              'char_source_sha256': hashlib.sha256(args.char_source.read_bytes()).hexdigest(),
              'natural_source': str(args.natural_source),
              'natural_source_sha256': hashlib.sha256(args.natural_source.read_bytes()).hexdigest(),
              'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'tests': result.testsRun, 'failures': len(result.failures),
              'errors': len(result.errors), 'passed': result.wasSuccessful()}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    raise SystemExit(0 if result.wasSuccessful() else 1)

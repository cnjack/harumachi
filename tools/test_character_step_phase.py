#!/usr/bin/env python3
"""Exercise the real CharAnim footstep expressions against phase-path contracts.

No Godot process is started. The phase predicate and seek-reset expression are
read from GDScript, rather than copied into a second implementation. The oracle
counts half-cycle contacts only along real forward playback, never along seeks.
"""
import argparse
import ast
import hashlib
import json
import math
from pathlib import Path
import re
from types import SimpleNamespace
import unittest

PARSER = argparse.ArgumentParser(description=__doc__)
PARSER.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1] / 'game/scripts/player/char_anim.gd')
PARSER.add_argument('--output', type=Path)
ARGS = PARSER.parse_args()
SOURCE = ARGS.source.read_text()
DETECTOR = SOURCE.split('func _check_step()', 1)[1].split('\n\nfunc ', 1)[0]
PREDICATE_TEXT = re.search(r'^\s*if (_prev_ph\s*>=.+):\s*$', DETECTOR, re.M).group(1)
PREDICATE_AST = ast.parse(PREDICATE_TEXT, mode='eval')
ALLOWED = (ast.Expression, ast.BoolOp, ast.And, ast.Or, ast.Compare, ast.GtE, ast.Gt, ast.LtE, ast.Lt, ast.Name, ast.Load, ast.Constant)
if any(not isinstance(node, ALLOWED) for node in ast.walk(PREDICATE_AST)):
    raise ValueError('Unexpected non-mathematical step predicate')
PREDICATE = compile(PREDICATE_AST, '<actual CharAnim step predicate>', 'eval')
GO = SOURCE.split('func _go(', 1)[1]
RESET_MATCH = re.search(r'^\s*_prev_ph\s*=\s*(.+)$', GO, re.M)
RESET = compile(RESET_MATCH.group(1), '<actual CharAnim matched-seek reset>', 'eval') if RESET_MATCH else None


def emitted(previous, phase):
    return int(eval(PREDICATE, {'__builtins__': {}}, {'_prev_ph': previous, 'ph': phase}))


def actual_seek_phase(wanted, duration):
    player = SimpleNamespace(current_animation_position=wanted * duration, current_animation_length=duration)
    phase = math.fmod(player.current_animation_position / duration, 1.0)
    return player, phase


def previous_after_seek(previous, player):
    if RESET is None:
        return previous
    return float(eval(RESET, {'__builtins__': {}, 'fmod': math.fmod, 'maxf': max}, {'ap': player}))


class StepPhaseContracts(unittest.TestCase):
    def test_matched_seek_is_not_a_contact(self):
        for previous, wanted in [(.40, .75), (.90, .20), (.10, .50), (.75, .125), (.25, .875)]:
            with self.subTest(previous=previous, wanted=wanted):
                player, phase = actual_seek_phase(wanted, .9583333134651184)
                self.assertEqual(emitted(previous_after_seek(previous, player), phase), 0)

    def test_same_phase_reset_uses_the_actual_player_clock(self):
        # These are the actual64 cached entry fractions at representative
        # imported clip lengths. Multiplication/division must not fake a wrap.
        for duration in [.57, .64, .65, .67, .68, .7083333134651184, .77, .78, .9583333134651184]:
            for sample in range(64):
                player, phase = actual_seek_phase(sample / 64, duration)
                self.assertEqual(emitted(previous_after_seek(.4, player), phase), 0)

    def test_real_heel_strikes_are_preserved(self):
        # An independent unwrapped path oracle counts half-cycle boundaries.
        # Every normal frame here traverses less than half a cycle.
        for start in [.001, .10, .25, .40, .499, .501, .75, .90, .999]:
            for delta in [.0015, .016, .025, .04, .08]:
                end = start + delta
                expected = math.floor(end * 2) - math.floor(start * 2)
                self.assertEqual(emitted(start, math.fmod(end, 1.0)), expected)

    def test_first_sample_does_not_invent_a_step(self):
        for phase in [0., .25, .50, .75, .999]:
            self.assertEqual(emitted(-1., phase), 0)

    def test_next_contact_after_a_seek_still_emits(self):
        for wanted, advance in [(.49, .02), (.99, .02), (.74, .27), (.24, .27)]:
            player, phase = actual_seek_phase(wanted, .78)
            settled = previous_after_seek(.1, player)
            self.assertEqual(emitted(settled, phase), 0)
            end = phase + advance
            self.assertEqual(emitted(phase, math.fmod(end, 1.0)), math.floor(end * 2) - math.floor(phase * 2))


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.loadTestsFromTestCase(StepPhaseContracts))
    if ARGS.output:
        ARGS.output.parent.mkdir(parents=True, exist_ok=True)
        ARGS.output.write_text(json.dumps({'scope': __doc__.strip(), 'source': str(ARGS.source), 'source_sha256': hashlib.sha256(ARGS.source.read_bytes()).hexdigest(), 'tool_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'tests': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors), 'passed': result.wasSuccessful(), 'has_seek_reset': RESET is not None}, indent=2) + '\n')
    raise SystemExit(0 if result.wasSuccessful() else 1)

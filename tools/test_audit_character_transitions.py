import unittest
from audit_character_transitions import gesture_windows, startup_windows, audit


def frame(index, clip, height=.008, position=(0, 0, 0), foot_shift=0, dt=.016):
    x, y, z = position
    feet = {side: {'cached_points_world': [[x + n*.001, height, z] for n in range(8)], 'min_y': height} for side in ('L', 'R')}
    return {'frame': index, 'clip': clip, 'elapsed_s': index*dt, 'actor_position': list(position), 'model_basis': [[1, 0, 0], [0, 1, 0], [0, 0, 1]], 'feet': feet, 'joints': {'hips': [x, y+.8, z], 'foot.L': [x+.08+foot_shift, y+.1, z], 'foot.R': [x-.08, y+.1, z]}}


class TransitionCounterexamples(unittest.TestCase):
    def test_empty_drop_within_old_floor_tolerance_still_fails_support_continuity(self):
        rows = [frame(0, 'wave'), frame(1, '', -.0027), frame(2, 'idle')]
        self.assertGreater(rows[1]['feet']['L']['min_y'], -.005)
        result = gesture_windows(rows)[0]
        self.assertTrue(result['assessed'])
        self.assertFalse(result['ok'])
        self.assertAlmostEqual(result['sides']['L']['maximum_empty_deviation_m'], .0107)

    def test_stable_multiple_empty_frames_keep_support(self):
        rows = [frame(0, 'bow'), frame(1, ''), frame(2, ''), frame(3, 'idle')]
        self.assertTrue(gesture_windows(rows)[0]['ok'])

    def test_moving_root_is_not_a_fixed_pose_support_example(self):
        rows = [frame(0, 'wave'), frame(1, '', position=(.02, 0, 0)), frame(2, 'idle')]
        self.assertFalse(gesture_windows(rows)[0]['assessed'])

    def test_startup_subtracts_rigid_root_translation(self):
        rows = [frame(0, 'idle'), frame(1, 'idle'), frame(2, 'walk', position=(.025, 0, 0))]
        self.assertTrue(startup_windows(rows)[0]['ok'])

    def test_original_stationary_startup_correction_pop_fails(self):
        rows = [frame(0, 'idle'), frame(1, 'idle'), frame(2, 'walk', foot_shift=.085)]
        self.assertFalse(startup_windows(rows)[0]['ok'])

    def test_fast_running_swing_is_outside_startup_rule(self):
        rows = [frame(0, 'run'), frame(1, 'run'), frame(2, 'walk', foot_shift=.145)]
        self.assertEqual(startup_windows(rows), [])

    def test_slow_capture_interval_is_not_treated_as_a_pop(self):
        rows = [frame(0, 'idle', dt=.03), frame(1, 'idle', dt=.03), frame(2, 'walk', foot_shift=.04, dt=.03)]
        self.assertFalse(startup_windows(rows)[0]['assessed'])

    def test_no_eligible_samples_is_incomplete_not_pass(self):
        document = {'cases': [{'character': 'fixture', 'frames': [frame(0, 'idle'), frame(1, 'run')]}]}
        self.assertEqual(audit(document, ('startup',))['exit_code'], 2)

    def test_reported_minimum_cannot_hide_actual_geometry_drop(self):
        rows = [frame(0, 'wave'), frame(1, '', -.0027), frame(2, 'idle')]
        rows[1]['feet']['L']['min_y'] = .008
        with self.assertRaises(ValueError):
            gesture_windows(rows)

    def test_relative_domain_covers_accelerating_root_with_stable_idle_pose(self):
        rows = [frame(0, 'idle'), frame(1, 'idle', position=(.002, 0, 0)), frame(2, 'idle', position=(.005, 0, 0)), frame(3, 'walk', position=(.010, 0, 0))]
        self.assertFalse(startup_windows(rows)[0]['assessed'])
        self.assertTrue(startup_windows(rows, 'stable-relative-pose')[0]['ok'])

    def test_relative_domain_excludes_turning_model(self):
        rows = [frame(0, 'idle'), frame(1, 'idle'), frame(2, 'idle'), frame(3, 'walk')]
        rows[-1]['model_basis'][0] = [0, 0, 1]
        self.assertFalse(startup_windows(rows, 'stable-relative-pose')[0]['assessed'])

    def test_relative_domain_excludes_idle_leg_motion(self):
        rows = [frame(0, 'idle'), frame(1, 'idle', foot_shift=.002), frame(2, 'idle'), frame(3, 'walk')]
        self.assertFalse(startup_windows(rows, 'stable-relative-pose')[0]['assessed'])


if __name__ == '__main__':
    unittest.main()

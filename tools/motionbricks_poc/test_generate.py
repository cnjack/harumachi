"""Small CPU-only format/control tests; no checkpoints, neural model or engine."""
import argparse
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate import action_list, command_sequence, npz_qualification, load_schedules


class ExportContract(unittest.TestCase):
    def test_actions_are_real_modes_and_never_a_sped_up_walk_run(self):
        self.assertEqual(action_list("left,crouch,boxing,hand_crawling"),
                         ["walk_left", "walk_stealth", "walk_boxing", "hand_crawling"])
        with self.assertRaises(argparse.ArgumentTypeError):
            action_list("run")
        with self.assertRaises(argparse.ArgumentTypeError):
            action_list("left,walk_left")

    def test_sequence_has_real_duration_and_fixed_side_direction(self):
        segments = command_sequence("walk_left", .5, 7, .5)
        self.assertEqual(segments[-1]["end_frame_exclusive"], 240)
        self.assertEqual(segments[1]["end_frame_exclusive"] - segments[1]["start_frame"], 210)
        self.assertEqual(segments[1]["movement_direction_mujoco"], [0., 1., 0.])
        self.assertEqual(segments[1]["facing_direction_mujoco"], [1., 0., 0.])
        with self.assertRaises(ValueError):
            command_sequence("walk", .01, 7, .5)

    def test_continuous_challenges_use_real_controls_without_speed_scaling(self):
        schedules = load_schedules(Path(__file__).with_name('challenges.json'))
        self.assertEqual(len(schedules),6)
        for commands in schedules.values():
            self.assertEqual(commands[-1]['end_frame_exclusive'],360)
            self.assertEqual(commands[0]['start_frame'],0)
            self.assertEqual([a['end_frame_exclusive'] for a in commands[:-1]],
                             [b['start_frame'] for b in commands[1:]])
        self.assertIn('elbow_crawling',[c['mode'] for c in schedules['crawl_style_transition']])
        self.assertGreater(len({tuple(c['facing_direction_mujoco']) for c in schedules['dance_full_turn']}),3)

    def fixture(self):
        import numpy as np
        quaternions = np.zeros((2, 34, 4));quaternions[..., 3] = 1
        return {"fps": np.asarray(30), "joint_names": np.asarray([f"j{i}" for i in range(34)]),
                "joint_parents": np.asarray([-1] + [0] * 33), "qpos": np.zeros((2,36)),
                "global_positions": np.zeros((2,34,3)), "global_quaternions_xyzw": quaternions,
                "global_scales": np.ones((2,34,3)), "reference_qpos": np.zeros(36),
                "reference_global_positions": np.zeros((34,3)),
                "reference_global_quaternions_xyzw": quaternions[0]}

    def test_incomplete_and_nonfinite_final_motion_is_rejected(self):
        import numpy as np
        data = self.fixture()
        self.assertEqual(npz_qualification(data)["joints"], 34)
        data["global_positions"][1,2,0] = np.nan
        with self.assertRaises(ValueError):
            npz_qualification(data)
        data = self.fixture();data["qpos"] = np.zeros((2,35))
        with self.assertRaises(ValueError):
            npz_qualification(data)

    def test_bad_quaternion_or_scale_is_not_a_qualified_export(self):
        data = self.fixture();data["global_quaternions_xyzw"][0,0,3] = 2
        with self.assertRaises(ValueError):
            npz_qualification(data)
        data = self.fixture();data["global_scales"][0,0,0] = 2
        with self.assertRaises(ValueError):
            npz_qualification(data)


if __name__ == "__main__":
    unittest.main()

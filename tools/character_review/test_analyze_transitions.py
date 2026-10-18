"""Kinematic negative controls for transition report interpretation; no Godot required."""
import unittest
import json
from pathlib import Path
import tempfile

from analyze_transitions import analyze_case, frame_metrics, read_transition_report


def trajectory(times, body, root_speed=0):
    frames = []
    for index, time in enumerate(times):
        root = [root_speed * time, 0, 0]
        relative = body(time)
        frames.append({"frame": index + 1, "physics_frame": index + 1, "elapsed_s": time,
                       "clip": "walk" if index < len(times) // 2 else "idle",
                       "actor_position": root,
                       "joints": {name: [root[0] + relative[0], relative[1], relative[2]]
                                  for name in ("hips", "foot.L", "foot.R")}})
    return frames


class TransitionAnalysisTests(unittest.TestCase):
    def test_fast_uniform_swing_is_not_a_discontinuity(self):
        frames = trajectory([0, .01, .02, .03, .04, .05], lambda time: [0, 0, 7 * time])
        rows, warnings = frame_metrics(frames)
        self.assertFalse(warnings)
        for row in rows:
            self.assertAlmostEqual(row["joints"]["foot.L"]["velocity_mps"], 7)
            residual = row["joints"]["foot.L"]["continuity_residual_m"]
            if residual is not None:
                self.assertLess(residual, 1e-12)

    def test_root_translation_is_removed_before_joint_speed(self):
        rows, _ = frame_metrics(trajectory([0, .01, .02, .03, .04], lambda time: [0, 1, .2], root_speed=5))
        for row in rows:
            self.assertAlmostEqual(row["root_speed_mps"], 5)
            self.assertLess(row["joints"]["hips"]["velocity_mps"], 1e-12)

    def test_isolated_position_jump_keeps_its_displacement(self):
        frames = trajectory([0, .01, .02, .03, .04, .05, .06],
                            lambda time: [0, 1 + (.04 if time >= .03 else 0), 0])
        rows, _ = frame_metrics(frames)
        jump = next(row for row in rows if row["elapsed_s"] == .03)
        self.assertAlmostEqual(jump["joints"]["hips"]["step_m"], .04)
        self.assertAlmostEqual(jump["joints"]["hips"]["continuity_residual_m"], .04)
        self.assertAlmostEqual(jump["joints"]["hips"]["residual_velocity_mps"], 4)

    def test_nonuniform_times_normalize_velocity_and_linear_acceleration(self):
        times = [0, .008, .022, .033, .052, .073]
        rows, _ = frame_metrics(trajectory(times, lambda time: [0, 1, 2 * time * time]))
        for row in rows:
            value = row["joints"]["foot.L"]
            self.assertAlmostEqual(value["velocity_mps"], 2 * (row["elapsed_s"] + row["before_s"]))
            if value["continuity_residual_m"] is not None:
                self.assertLess(value["continuity_residual_m"], 1e-12)

    def test_missing_neighbors_do_not_claim_zero_residual(self):
        rows, _ = frame_metrics(trajectory([0, .02], lambda time: [0, time, 0]))
        self.assertIsNone(rows[0]["joints"]["hips"]["continuity_residual_m"])

    def test_zero_time_interval_is_reported_instead_of_dividing(self):
        frames = trajectory([0, .01, .01, .03], lambda time: [0, time, 0])
        rows, warnings = frame_metrics(frames)
        self.assertEqual(len(rows), 2)
        self.assertEqual(len(warnings), 1)

    def test_no_full_bone_coverage_is_preserved_as_a_limitation(self):
        frames = trajectory([0, .01, .02, .03], lambda time: [0, time, 0])
        case = analyze_case({"character": "synthetic", "frames": frames, "commands": []})
        self.assertEqual(case["full_bone_unique_paired_frames"], 0)
        self.assertTrue(case["warnings"])
        self.assertEqual(len(case["events"]), 1)

    def test_stream_reader_preserves_metadata_and_discards_both_bone_encodings(self):
        source = {"engine": "synthetic", "cases": [{"character": "test", "frames": [],
                  "full_bone_samples": [{"applied_frame": 2, "clip": "walk", "bones": [{"name": "escaped \\\" brace }"}],
                                         "joints": {"hips": [0, 1, 0]}},
                                        {"applied_frame": 3, "clip": "idle", "bone_transforms": [[0] * 12]}]}]}
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "report.json"
            path.write_text(json.dumps(source))
            actual = read_transition_report(path)
        samples = actual["cases"][0]["full_bone_samples"]
        self.assertEqual(actual["engine"], "synthetic")
        self.assertEqual(samples[0]["joints"], {"hips": [0, 1, 0]})
        self.assertNotIn("bones", samples[0])
        self.assertNotIn("bone_transforms", samples[1])

    def test_expected_first_unrequested_frame_is_not_a_failed_request(self):
        frames = trajectory([0, .01, .02, .03], lambda time: [0, time, 0])
        samples = [{"applied_frame": row["frame"], "request_frame": row["frame"] - 1,
                    "clip": row["clip"], "joints": row["joints"]} for row in frames[1:]]
        case = analyze_case({"character": "synthetic", "frames": frames, "commands": [],
                             "sampling_failures": 0, "full_bone_samples": samples})
        self.assertEqual(case["initial_unrequested_continuous_frame"]["frame"], 1)
        self.assertEqual(case["full_bone_pairing_errors"], 0)
        self.assertFalse(case["warnings"])


if __name__ == "__main__":
    unittest.main()

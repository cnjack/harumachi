"""Capture clip filters fail before creating a project; no Godot is started."""
import argparse
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from capture import continuous_clips, continuous_clip_override


class ContinuousClipOptions(unittest.TestCase):
    def test_supported_selections(self):
        for value in ["walk", "run", "walk,run", "run,walk"]:
            self.assertEqual(continuous_clips(value), value)

    def test_invalid_or_duplicate_selections(self):
        for value in ["", "idle", "walk,walk", "walk,", "walk, run"]:
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                continuous_clips(value)

    def test_default_does_not_change_the_engine_command(self):
        self.assertEqual(continuous_clip_override("continuous", None), [])

    def test_only_the_continuous_job_receives_the_selection(self):
        self.assertEqual(continuous_clip_override("continuous", "walk"), ["--continuous-clips=walk"])
        for job in ["locomotion-poses", "joint-poses", "hands", "transitions", "multi-performance"]:
            self.assertEqual(continuous_clip_override(job, "walk"), [])

    def test_invalid_cli_does_not_create_output_or_launch_the_engine(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "must-not-exist"
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("capture.py")),
                                     "--out", str(destination), "--continuous-clips", "walk,walk"],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 2)
            self.assertIn("--continuous-clips requires distinct", result.stderr)
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()

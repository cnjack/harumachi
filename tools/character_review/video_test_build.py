"""Offline protocol fixtures; artificial MP4 bytes are never media/decode qualification."""
from collections import Counter
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("video_builder", HERE / "video_build.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))


def fixture(folder):
    models = {"CH_" + actor + ".glb": (str(i + 1) * 64) for i, actor in enumerate(m.ACTORS)}
    runtime = "a" * 64
    native = {"addons/contact/native.gdextension": "b" * 64}
    freeze = {"ready_for_recording": True, "models": models, "runtime_files": {m.RUNTIME: runtime}, "native_addon_files": native}
    write(folder / "final-freeze.snapshot.json", freeze)
    freeze_hash = m.digest(folder / "final-freeze.snapshot.json")
    context = {"models": models, "final_freeze_sha256": freeze_hash, "runtime_addon_proof_sha256": {m.RUNTIME: runtime}}
    write(folder / "recording-context.json", context)
    verification = {"all_completed": True, "failed_checks": 0, "completed": 9, "expected": 9, "pending": [], "results": [{"take": take, "failed": 0} for take in m.TAKES]}
    write(folder / "final-take-verification.json", verification)
    delivery = {"fps": 30, "takes": {}, "checks": {"failed": 0, "report": "final-take-verification.json", "sha256": m.digest(folder / "final-take-verification.json")}, "final_freeze": {"sha256": freeze_hash, "models": models, "runtime_sha256": runtime, "native_files": native}}
    for take in m.TAKES:
        solo = take.startswith("solo-")
        actors = [take.removeprefix("solo-")] if solo else ["ren", "mio", "kazuko"] if take == "group-walk-run" else list(m.ACTORS)
        plan = list(zip(list(m.ACTIONS)[:-1], [30, 210, 210, 90, 90, 90])) if solo else [("walk", 240), ("run", 240), ("wave", 120), ("bow", 120)] if take == "group-walk-run" else [("idle", 90), ("wave", 180), ("stretch", 180), ("bow", 150), ("dance", 120)]
        sections, rows = [], []
        for action, count in plan:
            observed = Counter()
            for index in range(count):
                view = list(m.VIEWS)[:5][min(4, index * 5 // count)] if solo and action in ["walk", "run"] else "oblique" if solo and action in ["wave", "stretch", "bow"] else "front"
                values = {actor: {"clip": action, "position": [i * 1.3, .01, -13]} for i, actor in enumerate(actors)}
                observed.update(actor + "/" + action for actor in actors)
                rows.append({"drawn_frame": len(rows) + 500, "action": action, "view": view, "actors": values})
            sections.append({"action": action, "count": count, "start_frame": len(rows) - count + 499, "end_frame": len(rows) + 499, "observed_clips": dict(observed)})
        write(folder / take / "movie-journal.json", {"take": take, "fps": 30, "failures": [], "frames": rows, "sections": sections})
        media = folder / take / "video.mp4"
        media.write_bytes(b"artificial protocol bytes, not decoded video:" + take.encode())
        stream = {"codec_type": "video", "nb_frames": "720", "nb_read_frames": "720", "avg_frame_rate": "30/1", "r_frame_rate": "30/1", "duration": "24.000000"}
        write(folder / take / "media-verification.json", {"sha256": m.digest(media), "bytes": media.stat().st_size, "full_decode_passed": True, "strict_full_decode_passed": True, "probe": {"streams": [stream], "format": {"duration": "24.000000"}}})
        write(folder / take / "input-hashes.json", {"models": models, "garment_runtime_sha256": runtime, "final_freeze_sha256": freeze_hash, "recording_context_sha256": m.digest(folder / "recording-context.json")})
        delivery["takes"][take] = {"file": take + "/video.mp4", "sha256": m.digest(media), "frames": 720, "duration_s": 24, "strict_full_decode_passed": True}
    write(folder / "delivery.json", delivery)
    return delivery


class VideoBuildTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.folder = Path(self.tmp.name)
        self.delivery = fixture(self.folder)

    def tearDown(self):
        self.tmp.cleanup()

    def test_49_cases_9_takes_use_relative_row_time_and_actual_views(self):
        data = m.dataset(self.folder)
        self.assertEqual((len(data["cases"]), len(data["takes"])), (49, 9))
        walk = next(c for c in data["cases"] if c["id"] == "ren/walk")
        self.assertEqual((walk["frame_start"], walk["frame_end"], walk["start_s"], walk["end_s"]), (30, 240, 1, 8))
        self.assertEqual([v["view"] for v in walk["view_segments"]], ["front", "right", "back", "left", "top"])
        self.assertEqual(walk["view_segments"][4]["start_s"], (30 + 168) / 30)
        for i, actor in enumerate(m.ACTORS):
            case = next(c for c in data["cases"] if c["id"] == actor + "/dance")
            self.assertEqual((case["take"], case["start_s"], case["end_s"], case["group_position"]), ("group-all-actions", 20, 24, i + 1))
            self.assertIn("七人同场", case["context"])

    def test_build_only_creates_new_ui_snapshots_and_preserves_sources(self):
        before = {p.relative_to(self.folder).as_posix(): m.digest(p) for p in self.folder.rglob("*") if p.is_file()}
        data = m.build(self.folder)
        self.assertTrue(all(m.digest(self.folder / name) == value for name, value in before.items()))
        html = (self.folder / "index.html").read_text()
        self.assertIn(data["id"], html)
        self.assertIn('id="reviewVideo" controls', html)
        self.assertNotIn("autoplay", html)
        self.assertEqual(data["id"], m.build(self.folder)["id"])

    def test_arbitrary_media_path_rejected_before_any_ui_write(self):
        self.delivery["takes"]["solo-ren"]["file"] = "../solo-ren/video.mp4"
        write(self.folder / "delivery.json", self.delivery)
        with self.assertRaises(ValueError): m.build(self.folder)
        self.assertFalse((self.folder / "index.html").exists())

    def test_changed_video_bytes_rejected(self):
        (self.folder / "solo-ren/video.mp4").write_bytes(b"changed")
        with self.assertRaises(ValueError): m.dataset(self.folder)

    def test_journal_short_or_wrong_action_rejected(self):
        path = self.folder / "solo-ren/movie-journal.json"
        value = json.loads(path.read_text()); original = copy.deepcopy(value)
        value["frames"].pop(); write(path, value)
        with self.assertRaises(ValueError): m.dataset(self.folder)
        original["frames"][31]["action"] = "idle"; write(path, original)
        with self.assertRaises(ValueError): m.dataset(self.folder)

    def test_probe_and_decode_receipts_are_checked(self):
        path = self.folder / "solo-ren/media-verification.json"
        value = json.loads(path.read_text()); original = copy.deepcopy(value)
        value["probe"]["streams"][0]["nb_read_frames"] = "719"; write(path, value)
        with self.assertRaises(ValueError): m.dataset(self.folder)
        original["strict_full_decode_passed"] = False; write(path, original)
        with self.assertRaises(ValueError): m.dataset(self.folder)

    def test_final_verification_hash_and_full_completion_checked(self):
        path = self.folder / "final-take-verification.json"
        value = json.loads(path.read_text()); value["all_completed"] = False; write(path, value)
        self.delivery["checks"]["sha256"] = m.digest(path); write(self.folder / "delivery.json", self.delivery)
        with self.assertRaises(ValueError): m.dataset(self.folder)

    def test_case_identity_changes_with_journal_and_source_identity(self):
        first = m.dataset(self.folder)
        path = self.folder / "solo-ren/movie-journal.json"
        value = json.loads(path.read_text()); value["frames"][0]["drawn_frame"] += 1000; write(path, value)
        changed = m.dataset(self.folder)
        self.assertNotEqual(first["id"], changed["id"])
        self.assertEqual(first["cases"][0]["start_s"], changed["cases"][0]["start_s"])

    def test_existing_old_ui_is_protected(self):
        path = self.folder / "index.html"; path.write_text("old original review")
        with self.assertRaises(ValueError): m.build(self.folder)
        self.assertEqual(path.read_text(), "old original review")


if __name__ == "__main__":
    unittest.main()

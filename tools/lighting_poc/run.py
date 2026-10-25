#!/usr/bin/env python3
"""Isolated, opt-in lighting POC; existing screen, muted, serial real rendering.

prepare -> preview -> bench -> record -> finish. Movie capture is presentation
evidence only. The benchmark runs without Movie Maker at the shipping 60 FPS cap.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from visual_qa import save_hashes

spec = importlib.util.spec_from_file_location("power_compare", ROOT / "tools/performance/power_compare.py")
power = importlib.util.module_from_spec(spec)
spec.loader.exec_module(power)
VIEWS = "farm,street,plaza_festival_night,store_interior"


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def sync(stage):
    for source, name in [("look.gd", "lighting_poc_look.gd"), ("capture.gd", "lighting_poc_capture.gd")]:
        shutil.copyfile(ROOT / "tools/lighting_poc" / source, stage / "game/scripts/tools" / name)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("mode", choices=["prepare", "preview", "bench", "record", "finish"])
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--look", choices=["before", "poc", "both"], default="both")
    ap.add_argument("--views", default=VIEWS)
    ap.add_argument("--suffix", default="")
    ap.add_argument("--seconds", type=int, default=30)
    args = ap.parse_args()
    out = args.out.resolve(); out.mkdir(parents=True, exist_ok=True)
    state_path = out / "stage.json"
    if args.mode == "prepare":
        if state_path.exists(): raise SystemExit("Existing stage: finish it before creating another")
        stage = Path(tempfile.mkdtemp(prefix="harumachi-lighting-poc-"))
        subprocess.run(["cp", "-cR", str(ROOT / "game"), str(stage / "game")], check=True)
        write(state_path, {"stage": str(stage), "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                           "default_saves_before": save_hashes(), "screen": 0, "virtual_display": False,
                           "production_runtime_unchanged": True, "date": "2026-10-25"})
        sync(stage)
        folder = out / "import"; folder.mkdir(exist_ok=True)
        with (folder / "engine.log").open("w") as log:
            result = subprocess.run([str(ROOT / "tools/godot"), "--headless", "--path", str(stage / "game"), "--audio-driver", "Dummy", "--import"],
                                    env=dict(os.environ, HARUMACHI_SAVE_DIR=str(folder / "save")), stdout=log, stderr=subprocess.STDOUT, timeout=300)
        body = (folder / "engine.log").read_text(errors="replace")
        assert result.returncode == 0 and "SCRIPT ERROR" not in body and "SHADER ERROR" not in body, body[-3000:]
        print(stage, flush=True); return
    state = json.loads(state_path.read_text()); stage = Path(state["stage"])
    assert stage.name.startswith("harumachi-lighting-poc-") and stage.parent == Path(tempfile.gettempdir())
    if args.mode == "finish":
        assert save_hashes() == state["default_saves_before"], "Default save changed"
        shutil.rmtree(stage)
        write(out / "cleanup.json", {"temporary_project_and_avi_removed": True, "default_saves_unchanged": True,
                                     "default_save_files": len(state["default_saves_before"])})
        return
    sync(stage)
    movie = args.mode == "record"
    width, height = (1920, 1080) if movie else (2560, 1440)
    (stage / "game/override.cfg").write_text('[display]\nwindow/size/no_focus=true\nwindow/vsync/vsync_mode=1\n'
        f'window/size/viewport_width={width}\nwindow/size/viewport_height={height}\nwindow/size/window_width_override={width}\nwindow/size/window_height_override={height}\n')
    for look in (["before", "poc"] if args.look == "both" else [args.look]):
        power.quiet(120)
        folder = out / (args.mode + args.suffix) / look
        folder.mkdir(parents=True, exist_ok=False)
        cmd = [str(ROOT / "tools/godot"), "--path", str(stage / "game"), "--screen", "0", "-t", "--position", "60,80",
               "--resolution", f"{width}x{height}", "--audio-driver", "Dummy", "--script", "res://scripts/tools/lighting_poc_capture.gd"]
        if movie: cmd += ["--write-movie", str(stage / (look + ".avi")), "--fixed-fps", "30"]
        cmd += ["--", "--out=" + str(folder), "--views=" + args.views, "--graphics-profile=balanced", "--graphics-benchmark",
                "--frame-policy=play", "--tag=" + look, "--look=" + look, "--capture=" + ("movie" if movie else "preview"),
                "--settle=" + ("180" if args.mode == "bench" else "90"), "--frames=" + ("600" if args.mode == "bench" else "30"),
                "--sample-seconds=" + str(args.seconds if args.mode == "bench" else 0)]
        started = time.monotonic(); telemetry = []; conflicts = set(); phase = ""; offset = 0; process = None
        write(folder / "environment.json", power.power_environment())
        print("START", args.mode, look, flush=True)
        try:
            with (folder / "engine.log").open("w") as log:
                process = subprocess.Popen(cmd, env=dict(os.environ, HARUMACHI_SAVE_DIR=str(folder / "save")), stdout=log, stderr=subprocess.STDOUT)
                while process.poll() is None:
                    time.sleep(1)
                    with (folder / "engine.log").open() as reader:
                        reader.seek(offset); new = reader.read(); offset = reader.tell()
                    for line in new.splitlines():
                        if line.startswith("BENCH_SAMPLE_BEGIN "): phase = line.split(" ", 1)[1]
                        if line.startswith("BENCH_SAMPLE_END "): phase = ""
                        if line.startswith(("BENCH_VIEW", "POC_CLIP")): print(line, flush=True)
                    if any(x in new for x in ["SCRIPT ERROR", "SHADER ERROR", "BENCH_FAIL", "Assertion failed"]):
                        raise RuntimeError(new[-4000:])
                    conflicts.update(power.foreign_games(process.pid))
                    if conflicts: raise RuntimeError("Concurrent renderer/media worker: " + str(conflicts))
                    telemetry.append({"wall_seconds": time.monotonic()-started, "phase": phase, "thermal_state": power.thermal_state(), **(power.process_usage(process.pid) or {})})
                    if time.monotonic()-started > 900: raise TimeoutError("POC capture exceeded 15 minutes")
            body = (folder / "engine.log").read_text(errors="replace")
            assert process.returncode == 0 and not any(x in body for x in ["SCRIPT ERROR", "SHADER ERROR", "Assertion failed"]), body[-3000:]
            assert save_hashes() == state["default_saves_before"], "Default save changed"
            write(folder / "process.json", {"command": cmd, "exit": process.returncode, "wall_seconds": time.monotonic()-started,
                "movie_is_not_performance_measurement": movie, "default_saves_unchanged": True, "conflicts": sorted(conflicts)})
            write(folder / "telemetry.json", telemetry)
            if not movie:
                result = json.loads((folder / "result.json").read_text()); assert result["status"] == "complete"
                for row in result["samples"]:
                    assert row["rendered_frames"] >= row["frames"] - 2 and row["render_gpu_ms"]["valid"]
                    points = [p for p in telemetry if p["phase"] == row["view"] and "cpu_seconds" in p]
                    if len(points) >= 2:
                        first,last=points[0],points[-1]
                        row["process_cpu_percent"] = 100*(last["cpu_seconds"]-first["cpu_seconds"])/(last["wall_seconds"]-first["wall_seconds"])
                write(folder / "result.json", result)
            print("DONE", args.mode, look, flush=True)
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=5)


if __name__ == "__main__": main()

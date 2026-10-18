#!/usr/bin/env python3
"""Capture a frozen character candidate with muted audio and an isolated save."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("visual_qa", ROOT / "tools/visual_qa.py")
visual = importlib.util.module_from_spec(spec)
spec.loader.exec_module(visual)


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def continuous_clips(value):
    clips = value.split(",")
    if len(set(clips)) != len(clips) or any(clip not in {"walk", "run"} for clip in clips):
        raise argparse.ArgumentTypeError("--continuous-clips requires distinct walk,run names")
    return value


def continuous_clip_override(job, clips):
    return ["--continuous-clips=" + clips] if job == "continuous" and clips is not None else []


def run(command, folder, env, limit):
    folder.mkdir(parents=True, exist_ok=True)
    log_path = folder / "engine.log"
    started = time.monotonic()
    process = None
    try:
        with log_path.open("w") as log:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
            write(folder / "process.json", {"command": command, "pid": process.pid, "status": "running"})
            while process.poll() is None:
                if time.monotonic() - started > limit:
                    raise RuntimeError("Native capture exceeded its time limit")
                if "SCRIPT ERROR" in log_path.read_text(errors="replace"):
                    raise RuntimeError("Godot script error; see " + str(log_path))
                time.sleep(.5)
        contents = log_path.read_text(errors="replace")
        errors = [s for s in ["SCRIPT ERROR", "SHADER ERROR", "Shader compilation failed", "!p_transform.is_finite()"] if s in contents]
        record = {"command": command, "exit": process.returncode, "elapsed_seconds": time.monotonic() - started, "errors": errors}
        write(folder / "process.json", record)
        if process.returncode or errors:
            raise RuntimeError("Capture failed: " + str(folder))
        print(json.dumps({"job": folder.name, **record}), flush=True)
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--candidate-models", type=Path)
    parser.add_argument("--actors", default="sora,ren,haru,mio,aoi,tanaka,kazuko")
    parser.add_argument("--display", choices=["virtual", "existing"], default="virtual", help="Use existing when the user asks not to create a virtual display")
    parser.add_argument("--screen", type=int, default=0, help="Godot screen index for --display existing")
    parser.add_argument("--jobs", default="locomotion-poses,joint-poses,continuous")
    parser.add_argument("--clips", help="Override clips for a focused pose capture")
    parser.add_argument("--phases", help="Override phases for a focused pose capture")
    parser.add_argument("--pose-views", default="front,right,back,left,top", help="Capture the listed pose camera views")
    parser.add_argument("--hand-clips", help="Override authored clips for hand detail cameras")
    parser.add_argument("--continuous-views", help="Capture native movement from the listed relative camera views")
    parser.add_argument("--continuous-clips", type=continuous_clips, help="Filter native movement to walk,run; omitted captures both")
    parser.add_argument("--hide-arm-fill", action="store_true", help="Diagnostic only: hide internal arm fill meshes")
    parser.add_argument("--disable-lod", action="store_true", help="Diagnostic only: disable viewport mesh LOD")
    parser.add_argument("--export-garment-proxy", action="store_true", help="Export actual imported proxy source indices for diagnosis")
    parser.add_argument("--garment-fine-contact", action="store_true", help="Diagnostic only: evaluate complete source garment contact")
    parser.add_argument("--garment-safe-face-cache", action="store_true", help="Diagnostic only: measure same-frame safe-ray certificates")
    parser.add_argument("--garment-fixed-layer-reuse", action="store_true", help="Diagnostic only: reuse proven unchanged layers within a callback")
    parser.add_argument("--garment-skin-direction-skip", action="store_true", help="Diagnostic only: omit unused pure-body displacement directions")
    parser.add_argument("--garment-layer-geometry-cache", action="store_true", help="Diagnostic only: reuse identical callback-local layer bounds/tree/face geometry")
    parser.add_argument("--garment-unique-panel-scaling", action="store_true", help="Diagnostic only: scale each panel vertex once before filling identical tree corners")
    parser.add_argument("--garment-risk-contact", action="store_true", help="Diagnostic only: verify mapped source contact patches")
    parser.add_argument("--garment-risk-actors", help="Diagnostic only: enable mapped source contact for comma-separated mio,ren,kazuko")
    parser.add_argument("--garment-proxy-mio", type=int, choices=[3300, 7100], help="Diagnostic only: override Mio proxy detail")
    parser.add_argument("--diagnostic-idle-start-phase", type=float, help="COW diagnostic only: replace the random initial idle seek with this phase; never edits production CharAnim")
    parser.add_argument("--limit", type=int, default=1200)
    args = parser.parse_args()
    if args.diagnostic_idle_start_phase is not None and not 0 <= args.diagnostic_idle_start_phase < 1:
        parser.error("--diagnostic-idle-start-phase must be in [0,1)")
    pose_views = args.pose_views.split(",")
    if len(set(pose_views)) != len(pose_views) or any(view not in {"front", "right", "back", "left", "top"} for view in pose_views):
        parser.error("--pose-views requires distinct front,right,back,left,top names")
    jobs = {
        "locomotion-poses": ["--mode=poses", "--clips=idle,walk,run", "--phases=0,0.125,0.25,0.375,0.5,0.625,0.75,0.875"],
        "joint-poses": ["--mode=poses", "--clips=wave,stretch,bow,dance", "--phases=0.125,0.375,0.625,0.875"],
        "continuous": ["--mode=continuous"],
        "transitions": ["--mode=transitions"],
        "multi-performance": ["--mode=multi-performance"],
        "hands": ["--mode=hands"],
    }
    requested = args.jobs.split(",")
    risk_actors = args.garment_risk_actors.split(",") if args.garment_risk_actors else []
    if len(set(risk_actors)) != len(risk_actors) or any(actor not in {"mio", "ren", "kazuko"} for actor in risk_actors):
        parser.error("--garment-risk-actors requires distinct mio,ren,kazuko names")
    if any(j not in jobs for j in requested):
        parser.error("Unknown job")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    before = visual.save_hashes()
    write(out / "default-save-before.json", before)
    with tempfile.TemporaryDirectory(prefix="harumachi-character-capture-") as temporary:
        stage = Path(temporary)
        project = stage / "game"
        subprocess.run(["cp", "-cR", str(ROOT / "game"), str(project)], check=True)
        if args.candidate_models:
            for model in args.candidate_models.resolve().glob("CH_*.glb"):
                shutil.copyfile(model, project / "assets/models" / model.name)
        if args.diagnostic_idle_start_phase is not None:
            animation_source = project / "scripts/player/char_anim.gd"
            text = animation_source.read_text()
            marker = 'ap.seek(randf() * ap.get_animation("idle").length, true)'
            if text.count(marker) != 1:
                raise ValueError("Inspect the exact initial idle seek before a reference diagnostic")
            animation_source.write_text(text.replace(marker, 'ap.seek(' + repr(args.diagnostic_idle_start_phase) + ' * ap.get_animation("idle").length, true)'))
            write(out / "diagnostic-idle-start.json", {"scope": "COW-only initial idle phase; not a production behavior change or ordinary acceptance run", "phase": args.diagnostic_idle_start_phase,
                  "production_char_anim_sha256": visual.digest(ROOT / "game/scripts/player/char_anim.gd"), "cow_char_anim_sha256": visual.digest(animation_source)})
        proof = project / "data/character_garment_proofs.json"
        if proof.is_file():
            frozen_data = out / "frozen-production-data"
            frozen_data.mkdir(exist_ok=True)
            shutil.copyfile(proof, frozen_data / proof.name)
            write(out / "production-data-hashes.json", {"data/" + proof.name: visual.digest(proof)})
        write(out / "source-hashes.json", {str(p.relative_to(project)): visual.digest(p) for p in sorted(project.rglob("*.gd"))})
        write(out / "model-hashes.json", {p.name: visual.digest(p) for p in sorted((project / "assets/models").glob("CH_*.glb"))})
        (project / "override.cfg").write_text("[display]\nwindow/size/no_focus=true\nwindow/vsync/vsync_mode=0\n")
        env = dict(os.environ, HARUMACHI_SAVE_DIR=str(stage / "save"))
        run([str(ROOT / "tools/godot"), "--headless", "--path", str(project), "--editor", "--import", "--audio-driver", "Dummy"], out / "import", env, 300)
        display = None
        try:
            if args.display == "virtual":
                binary = stage / "virtual-display"
                subprocess.run(["clang", str(ROOT / "tools/macos_virtual_display.m"), "-fobjc-arc", "-framework", "AppKit", "-framework", "CoreGraphics", "-framework", "Foundation", "-o", str(binary)], check=True)
                display = subprocess.Popen([str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
                line = display.stdout.readline()
                if not line:
                    raise RuntimeError("Isolated virtual display unavailable")
                info = json.loads(line)
                write(out / "virtual-display.json", info)
            else:
                info = {"screen": args.screen, "temporary": False, "created_virtual_display": False}
                write(out / "existing-display.json", info)
            (project / "display_probe.gd").write_text('extends SceneTree\nfunc _initialize() -> void:\n for i: int in DisplayServer.get_screen_count():\n  print("PROBE_SCREEN ",i," ",DisplayServer.screen_get_position(i)," ",DisplayServer.screen_get_size(i))\n quit()\n')
            probe = subprocess.run([str(ROOT / "tools/godot"), "--path", str(project), "--audio-driver", "Dummy", "--script", "res://display_probe.gd"], env=env, capture_output=True, text=True, timeout=30)
            (out / "display-probe.log").write_text(probe.stdout + probe.stderr)
            screens = re.findall(r"PROBE_SCREEN (\d+) \((-?\d+), (-?\d+)\) \((\d+), (\d+)\)", probe.stdout)
            screen = next(s for s in screens if int(s[0]) == info["screen"])
            position = f"{int(screen[1])+40},{int(screen[2])+50}"
            for job in requested:
                folder = out / job
                overrides = []
                if args.hide_arm_fill: overrides.append("--hide-arm-fill")
                if args.disable_lod: overrides.append("--disable-lod")
                if job == "hands" and args.hand_clips: overrides.append("--hand-clips=" + args.hand_clips)
                if job == "continuous" and args.continuous_views: overrides.append("--continuous-views=" + args.continuous_views)
                overrides.extend(continuous_clip_override(job, args.continuous_clips))
                if args.export_garment_proxy: overrides.append("--garment-proxy-export-dir=" + str(folder / "garment-proxy"))
                if args.garment_fine_contact: overrides.append("--garment-fine-contact")
                if args.garment_safe_face_cache: overrides.append("--garment-safe-face-cache")
                if args.garment_fixed_layer_reuse: overrides.append("--garment-fixed-layer-reuse")
                if args.garment_skin_direction_skip: overrides.append("--garment-skin-direction-skip")
                if args.garment_layer_geometry_cache: overrides.append("--garment-layer-geometry-cache")
                if args.garment_unique_panel_scaling: overrides.append("--garment-unique-panel-scaling")
                if args.garment_risk_contact: overrides.append("--garment-risk-contact")
                overrides.extend("--garment-risk-contact-" + actor for actor in risk_actors)
                if args.garment_proxy_mio: overrides.append("--garment-proxy-mio=" + str(args.garment_proxy_mio))
                if job in {"locomotion-poses", "joint-poses"}:
                    if args.clips: overrides.append("--clips=" + args.clips)
                    if args.phases: overrides.append("--phases=" + args.phases)
                frame_limit = ["--max-fps", "60"] if job in {"continuous", "transitions"} else []
                command = [str(ROOT / "tools/godot"), "--path", str(project), "--screen", str(info["screen"]), "-t", "--position", position, "--resolution", "1280x720", "--audio-driver", "Dummy", *frame_limit, "res://scenes/main.tscn", "--", "--qa-characters", "--out=" + str(folder), "--actors=" + args.actors, "--pose-views=" + args.pose_views, "--final-bones", "--measure-motion-soles", *jobs[job], *overrides]
                run(command, folder, env, args.limit)
                report = json.loads((folder / "manifest.json").read_text())
                if report["failures"] or report["images"] != report["expected_images"]:
                    raise RuntimeError("Incomplete capture: " + str(folder))
        finally:
            if display is not None:
                display.stdin.close()
                display.wait(timeout=10)
            after = visual.save_hashes()
            changed = [k for k in sorted(before.keys() | after.keys()) if before.get(k) != after.get(k)]
            integrity = {"default_save_files": len(before), "changed": changed, "display_mode": args.display, "virtual_display_created": display is not None, "virtual_display_released": display.returncode == 0 if display is not None else None, "temporary_project_removed": False}
            write(out / "integrity-and-cleanup.json", integrity)
            if changed:
                raise RuntimeError("Default save changed")
    integrity["temporary_project_removed"] = not project.exists()
    write(out / "integrity-and-cleanup.json", integrity)


if __name__ == "__main__":
    main()

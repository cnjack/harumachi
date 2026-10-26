#!/usr/bin/env python3
"""Run two scene comparisons through the local overlay's unchanged RenderEngine."""
import argparse
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--app", type=Path, required=True)
parser.add_argument("--model", type=Path, required=True)
parser.add_argument("--evidence", type=Path, required=True)
args = parser.parse_args()
out = args.evidence.resolve()
scenes = ["bakery_scene_front", "lake_pier"]
results = []


def process(scene, variant, source, width, profile):
    target = out / "results" / scene / variant
    target.mkdir(parents=True, exist_ok=True)
    command = [str(args.app.resolve()), "--scene-trial", str(source), "--model", str(args.model.resolve()),
               "--output", str(target), "--width", str(width), "--profile", profile]
    print("PROCESS", scene, variant, flush=True)
    with (target / "run.log").open("w") as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=600, check=True)
    record = json.loads((target / "metrics.json").read_text())
    record.update(scene=scene, variant=variant)
    results.append(record)
    (out / "measurements.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    print(f"DONE {scene} {variant}: {record['processingFPS']:.2f} processing FPS", flush=True)


for scene in scenes:
    for width, profile in [(512, "natural"), (768, "natural"), (768, "cinematic")]:
        process(scene, f"{profile}-{width}", out / "source" / f"{scene}.png", width, profile)
    process(scene, "motion-natural-768", out / "motion_source" / scene, 768, "natural")
    video = out / "videos"
    video.mkdir(exist_ok=True)
    originals = out / "motion_source" / scene / "%05d.png"
    processed = out / "results" / scene / "motion-natural-768" / "%05d.png"
    # Every source frame has a paired result. Video playback is 30 FPS even when
    # inference was slower; the UI labels this as offline processing explicitly.
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", "30",
                    "-i", str(originals), "-framerate", "30", "-i", str(processed), "-filter_complex",
                    "[0:v]scale=960:540[a];[1:v]scale=960:540[b];[a][b]hstack=inputs=2[v]",
                    "-map", "[v]", "-an", "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p",
                    "-movflags", "+faststart", str(video / f"{scene}-comparison.mp4")], check=True)

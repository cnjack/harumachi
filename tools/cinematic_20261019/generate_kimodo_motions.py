#!/usr/bin/env python3
"""Generate the film's character motion with the pinned NVIDIA Kimodo G1 model.

One process keeps the 8B local text encoder resident; every clip is independent
text-conditioned diffusion, not a scripted or procedural animation. Raw Kimodo
NPZ output is kept, then converted to the MotionBricks schema by
convert_kimodo.py and retargeted by the existing G1 retargeter.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import time

import numpy as np

from kimodo import load_model
from kimodo.exports.motion_io import save_kimodo_npz
from kimodo.tools import seed_everything


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    plan = json.loads(args.plan.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    device = "cuda:0" if __import__("torch").cuda.is_available() else "cpu"
    started = time.time()
    model, resolved = load_model(plan["model"], device=device, default_family="Kimodo",
                                 return_resolved_name=True)
    load_seconds = time.time() - started
    print(f"KIMODO_LOADED {resolved} device={device} seconds={load_seconds:.1f}", flush=True)
    report = {"kind": "NVIDIA Kimodo text-conditioned G1 motion for the Harumachi short",
              "model": resolved, "device": device, "load_seconds": load_seconds,
              "fps": model.fps, "diffusion_steps": plan["diffusion_steps"],
              "prompts_file": str(args.plan), "prompts_sha256": sha(args.plan),
              "clips": []}
    for clip in plan["clips"]:
        frames = round(float(clip["seconds"]) * model.fps)
        if frames < 2:
            raise ValueError(f"Clip too short: {clip['id']}")
        seed_everything(int(clip["seed"]))
        started = time.time()
        output = model([clip["prompt"]], [frames], num_denoising_steps=plan["diffusion_steps"],
                       multi_prompt=False, num_samples=1, return_numpy=True,
                       progress_bar=lambda iterable: iterable)
        seconds = time.time() - started
        single = {key: (value[0] if hasattr(value, "shape") and value.shape[0] == 1 else value)
                  for key, value in output.items()}
        path = args.output / f"{clip['id']}.npz"
        save_kimodo_npz(str(path), single)
        entry = {"id": clip["id"], "prompt": clip["prompt"], "seed": clip["seed"],
                 "frames": frames, "seconds": frames / model.fps,
                 "generation_seconds": seconds, "npz": str(path), "npz_sha256": sha(path),
                 "shape": list(np.asarray(single["posed_joints"]).shape)}
        report["clips"].append(entry)
        print("KIMODO_CLIP " + json.dumps(entry, ensure_ascii=False), flush=True)
    report["total_seconds"] = time.time() - started
    (args.output / "generation.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()

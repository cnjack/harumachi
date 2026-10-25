#!/usr/bin/env python3
"""Summarize paired, non-recording 60 FPS samples without claiming watts/temperature."""
import argparse
import json
from pathlib import Path


def main():
    ap = argparse.ArgumentParser(description=__doc__); ap.add_argument("out", type=Path); args = ap.parse_args()
    out = args.out
    data = {side: json.loads((out / "bench" / side / "result.json").read_text()) for side in ["before", "poc"]}
    before = {r["view"]: r for r in data["before"]["samples"]}; rows = []
    for new in data["poc"]["samples"]:
        old = before[new["view"]]
        assert old["minute"] == new["minute"] and old["weather"] == new["weather"]
        assert old["graphics"] == new["graphics"]
        assert old["rendered_image_size"] == new["rendered_image_size"] == [2560, 1440]
        assert old["elapsed_seconds"] >= 29.9 and new["elapsed_seconds"] >= 29.9
        delta = 100 * (new["render_gpu_ms"]["median"] / old["render_gpu_ms"]["median"] - 1)
        rows.append({"view": new["view"], "label": new["label"], "gpu_ms_before": old["render_gpu_ms"]["median"],
                     "gpu_ms_poc": new["render_gpu_ms"]["median"], "gpu_change_percent": delta,
                     "fps_before": old["fps_mean"], "fps_poc": new["fps_mean"], "p95_before_ms": old["p95_ms"], "p95_poc_ms": new["p95_ms"],
                     "cpu_before_percent": old.get("process_cpu_percent"), "cpu_poc_percent": new.get("process_cpu_percent")})
    result = {"rows": rows, "gpu_increase_within_ten_percent": all(r["gpu_change_percent"] <= 10 for r in rows),
              "resolution": [2560,1440], "seconds_per_scene": 30, "profile": "balanced", "recording_enabled": False,
              "watts": None, "temperature_celsius": None, "limits": "Four static camera scenes, one paired run; not long-session/thermal validation. Movie playback has a separate fixed 30 FPS timeline."}
    (out / "performance-comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__": main()

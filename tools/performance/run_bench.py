#!/usr/bin/env python3
"""Native runtime performance benchmark on the existing display.

Serial only: one Godot GPU process at a time, one process per variant, a COW copy
of the project, an isolated save directory, muted audio and vsync/no-focus
overrides. No virtual screen is created (2026-10-18 session rule): the window is
placed on the requested existing screen with -t so macOS keeps drawing it.
Every variant writes result.json, engine.log and display.json.

Baselines cover the requested resolutions; feature ablations run the slowest
views and are compared against a separate control with the same camera order,
resolution and warm-up. Each process receives a fresh save directory.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("visual_qa", ROOT / "tools/visual_qa.py")
visual = importlib.util.module_from_spec(spec)
spec.loader.exec_module(visual)

VIEWS = "street,plaza_day,farm,lake,store_interior,bedroom,plaza_festival_night"
ABLATIONS = ["no-volumetric-fog+no-ssil", "no-ssao+no-glow", "msaa0", "no-directional-shadow", "hide-props", "hide-characters"]
ERROR_MARKERS = ["SCRIPT ERROR", "SHADER ERROR", "Shader compilation failed", "!p_transform.is_finite()", "BENCH_FAIL"]
GODOT_PROCESS_MARKER = "Contents/MacOS/Godot"


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def slug(name):
    return name.replace("+", "-")


def foreign_godot_processes(exclude=()):
    """Any Godot GPU process that is not ours would pollute the timings."""
    listing = subprocess.run(["ps", "-Ao", "pid=,command="], capture_output=True, text=True, check=True).stdout
    found = []
    for line in listing.splitlines():
        if GODOT_PROCESS_MARKER not in line or "run_bench.py" in line:
            continue
        pid = int(line.split(None, 1)[0])
        if pid in exclude:
            continue
        found.append(line.strip())
    return found


def wait_for_quiet(limit=60):
    """Single-GPU-process policy: wait for any other Godot to exit, then start."""
    started = time.monotonic()
    while True:
        running = foreign_godot_processes()
        if not running:
            return
        if time.monotonic() - started > limit:
            raise RuntimeError("another Godot process stayed alive; refusing a contaminated benchmark: " + "; ".join(running))
        print("waiting for another Godot process to exit: " + "; ".join(running), flush=True)
        time.sleep(5)


def run(command, folder, env, limit, require_result=True):
    wait_for_quiet()
    folder.mkdir(parents=True, exist_ok=True)
    log_path = folder / "engine.log"
    started = time.monotonic()
    process = None
    concurrent = set()
    polls = 0
    try:
        with log_path.open("w") as log:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
            write(folder / "process.json", {"command": command, "pid": process.pid, "status": "running"})
            while process.poll() is None:
                if time.monotonic() - started > limit:
                    raise RuntimeError("Benchmark variant exceeded its time limit: " + str(folder))
                contents = log_path.read_text(errors="replace")
                found = [marker for marker in ERROR_MARKERS if marker in contents]
                if found:
                    raise RuntimeError("Godot reported %s; see %s" % (",".join(found), log_path))
                polls += 1
                if polls % 4 == 0:
                    for line in foreign_godot_processes(exclude={process.pid}):
                        concurrent.add(line.split()[0])
                time.sleep(.5)
        contents = log_path.read_text(errors="replace")
        errors = [marker for marker in ERROR_MARKERS if marker in contents]
        record = {"command": command, "exit": process.returncode, "elapsed_seconds": round(time.monotonic() - started, 1),
                  "errors": errors, "other_godot_pids_seen": sorted(concurrent)}
        write(folder / "process.json", record)
        if concurrent:
            print("warning: another Godot process overlapped this variant: " + ",".join(sorted(concurrent)), flush=True)
        if process.returncode or errors:
            raise RuntimeError("Benchmark variant failed: " + str(folder))
        if require_result and not (folder / "result.json").is_file():
            raise RuntimeError("Benchmark variant wrote no result.json: " + str(folder))
        print(json.dumps({"variant": folder.name, **record}, ensure_ascii=False), flush=True)
        return record
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def parse_resolution(text):
    match = re.fullmatch(r"(\d+)x(\d+)", text.strip())
    if not match:
        raise argparse.ArgumentTypeError("resolution must look like 1600x900")
    return int(match.group(1)), int(match.group(2))


def read_result(folder):
    return json.loads((folder / "result.json").read_text())


def renderer_banner(log_path):
    """Engine.log line 2 is the renderer banner: Metal 4.0 - Forward+ - Using Device #0 ..."""
    for line in log_path.read_text(errors="replace").splitlines()[:6]:
        if " - " in line and "Godot Engine" not in line:
            return line.strip()
    return ""


def run_variant(out, folder, command, env, limit, attempts=1):
    """A foreign Godot GPU process ruins frame timings, so retry that variant."""
    if not str(folder.resolve()).startswith(str(out.resolve()) + os.sep):
        raise RuntimeError("refusing to delete a folder outside the evidence directory")
    record = None
    for attempt in range(1, attempts + 1):
        if folder.exists():
            shutil.rmtree(folder)
        variant_env = dict(env, HARUMACHI_SAVE_DIR=str(Path(env["HARUMACHI_SAVE_DIR"]) / (folder.name + "-" + str(attempt))))
        record = run(command, folder, variant_env, limit)
        banner = renderer_banner(folder / "engine.log")
        record["renderer"] = banner
        record["attempt"] = attempt
        write(folder / "process.json", record)
        if not record["other_godot_pids_seen"]:
            return record
        print("retrying %s: another Godot process overlapped attempt %d" % (folder.name, attempt), flush=True)
    raise RuntimeError("%s stayed contaminated by another Godot process" % folder.name)


def view_rows(result, resolution):
    rows = {}
    for sample in result["samples"]:
        rows[sample["view"]] = {
            "resolution": resolution,
            "median_ms": sample["median_ms"],
            "p95_ms": sample["p95_ms"],
            "max_ms": sample["max_ms"],
            "fps": sample["fps_median"],
            "draw_calls": sample["monitors"].get("RENDER_TOTAL_DRAW_CALLS_IN_FRAME", {}).get("median"),
            "primitives": sample["monitors"].get("RENDER_TOTAL_PRIMITIVES_IN_FRAME", {}).get("median"),
            "objects": sample["monitors"].get("RENDER_TOTAL_OBJECTS_IN_FRAME", {}).get("median"),
            "video_mem_mb": (sample["monitors"].get("RENDER_VIDEO_MEM_USED", {}).get("median") or 0) / 1048576.0 if sample["monitors"].get("RENDER_VIDEO_MEM_USED") else None,
            "process_ms": (sample["monitors"].get("TIME_PROCESS", {}).get("median") or 0) * 1000.0 if sample["monitors"].get("TIME_PROCESS") else None,
            "physics_ms": (sample["monitors"].get("TIME_PHYSICS_PROCESS", {}).get("median") or 0) * 1000.0 if sample["monitors"].get("TIME_PHYSICS_PROCESS") else None,
            "node_count": sample["monitors"].get("OBJECT_COUNT", {}).get("median"),
            "memory_static_mb": (sample["monitors"].get("MEMORY_STATIC", {}).get("median") or 0) / 1048576.0 if sample["monitors"].get("MEMORY_STATIC") else None,
        }
    return rows


def summary_payload(baselines, controls, ablations, views, frames, settle):
    base = {name: view_rows(result, res) for (name, res, result) in baselines}
    payload = {
        "views": views,
        "frames": frames,
        "settle": settle,
        "baselines": {name: base[name] for name in base},
        "ablations": {},
        "ablation_views": [],
    }
    if ablations:
        control_name, control_result, control_views = controls
        control_rows = view_rows(control_result, control_views["resolution"])
        payload["control"] = control_rows
        payload["ablation_views"] = control_views["views"]
        for name, result in ablations:
            rows = view_rows(result, control_views["resolution"])
            deltas = {}
            for view_id in rows:
                control_median = control_rows.get(view_id, {}).get("median_ms")
                if control_median:
                    deltas[view_id] = {
                        "control_ms": control_median,
                        "variant_ms": rows[view_id]["median_ms"],
                        "delta_ms": rows[view_id]["median_ms"] - control_median,
                        "delta_percent": 100.0 * (rows[view_id]["median_ms"] - control_median) / control_median,
                        "control_draw_calls": control_rows[view_id]["draw_calls"],
                        "variant_draw_calls": rows[view_id]["draw_calls"],
                    }
            payload["ablations"][name] = {"rows": rows, "deltas": deltas}
    return payload


def baseline_markdown(summary, resolutions):
    lines = ["## 基线（每场景 300+ 帧，vsync 关闭，静音，独立存档）", ""]
    for name in summary["baselines"]:
        rows = summary["baselines"][name]
        resolution = rows[next(iter(rows))]["resolution"] if rows else name
        lines.append("### %s" % resolution)
        lines.append("")
        lines.append("| 场景 | 中位帧耗时 ms | p95 ms | 最长 ms | 中位 FPS | 绘制调用 | 图元 | 可见对象 | 进程 ms | 物理 ms | 显存 MB | 节点数 | 60fps(p95≤16.7) |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
        for view_id in summary["views"]:
            if view_id not in rows:
                continue
            row = rows[view_id]
            lines.append("| %s | %.2f | %.2f | %.2f | %.1f | %s | %s | %s | %s | %s | %s | %s | %s |" % (
                view_id, row["median_ms"], row["p95_ms"], row["max_ms"], row["fps"],
                fmt(row["draw_calls"], 0), fmt(row["primitives"], 0), fmt(row["objects"], 0),
                fmt(row["process_ms"], 2), fmt(row["physics_ms"], 2), fmt(row["video_mem_mb"], 1),
                fmt(row["node_count"], 0), "是" if row["p95_ms"] <= 16.67 else "否"))
        lines.append("")
    return lines


def ablation_markdown(summary):
    lines = ["## 特性消融（同一控制组、同一机位、每变体独立进程）", ""]
    views = summary["ablation_views"]
    lines.append("控制组：" + ", ".join(views) + "（消融分辨率 %s）" % (
        summary["control"][views[0]]["resolution"] if views and summary.get("control") else "?"))
    lines.append("")
    header = "| 变体 | 场景 | 控制 ms | 变体 ms | 差值 ms | 差值 % | 绘制调用（控制→变体） |"
    lines.append(header)
    lines.append("| --- | --- | --- | --- | --- | --- | --- |")
    for name in summary["ablations"]:
        for view_id, delta in summary["ablations"][name]["deltas"].items():
            lines.append("| %s | %s | %.2f | %.2f | %+.2f | %+.1f | %s→%s |" % (
                name, view_id, delta["control_ms"], delta["variant_ms"], delta["delta_ms"], delta["delta_percent"],
                fmt(delta["control_draw_calls"], 0), fmt(delta["variant_draw_calls"], 0)))
    lines.append("")
    return lines


def motion_markdown(rows):
    lines = ["## 移动场景（真实跟随镜头，玩家按自身 auto_move 走/跑，NPC 漫游保持游戏默认）", ""]
    lines.append("| 场景 | 帧数 | 中位 ms | p95 ms | 最长 ms | 中位 FPS | 绘制调用 | 图元 | TIME_PROCESS ms | TIME_PHYSICS ms |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for row in rows:
        monitors = row["monitors"]
        lines.append("| %s | %d | %.2f | %.2f | %.2f | %.1f | %s | %s | %s | %s |" % (
            row["view"], row["frames"], row["median_ms"], row["p95_ms"], row["max_ms"], row["fps_median"],
            fmt(monitors.get("RENDER_TOTAL_DRAW_CALLS_IN_FRAME", {}).get("median"), 0),
            fmt(monitors.get("RENDER_TOTAL_PRIMITIVES_IN_FRAME", {}).get("median"), 0),
            fmt((monitors.get("TIME_PROCESS", {}).get("median") or 0) * 1000.0, 2),
            fmt((monitors.get("TIME_PHYSICS_PROCESS", {}).get("median") or 0) * 1000.0, 2)))
    lines.append("")
    return lines


def fmt(value, digits):
    if value is None:
        return "—"
    return ("%." + str(digits) + "f") % value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--resolutions", default="1600x900,1920x1080")
    parser.add_argument("--views", default=VIEWS)
    parser.add_argument("--frames", type=int, default=300)
    parser.add_argument("--settle", type=int, default=240)
    parser.add_argument("--ablations", default=",".join(ABLATIONS), help="comma list; empty skips the ablation stage")
    parser.add_argument("--ablation-views", default="", help="comma list; empty uses the two slowest baseline views")
    parser.add_argument("--motion-views", default="", help="moving rows (walk/run) run as one extra variant at the first resolution")
    parser.add_argument("--screen", type=int, default=0, help="existing display index; this session forbids creating a virtual screen")
    parser.add_argument("--allow-hidpi", choices=["true", "false"], default="true", help="false forces 1x rendering on a Retina screen for the scaling comparison")
    parser.add_argument("--only", default="baseline,ablations", help="baseline,ablations")
    parser.add_argument("--limit", type=int, default=1200)
    parser.add_argument("--retries", type=int, default=1, help="re-run a variant when another Godot process overlapped it")
    parser.add_argument("--import-limit", type=int, default=900)
    parser.add_argument("--project", type=Path, default=None, help="project directory to benchmark; default ROOT/game")
    args = parser.parse_args()
    source_project = args.project.resolve() if args.project else ROOT / "game"

    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    views = [view.strip() for view in args.views.split(",") if view.strip()]
    resolutions = [parse_resolution(item) for item in args.resolutions.split(",") if item.strip()]
    ablation_names = [item.strip() for item in args.ablations.split(",") if item.strip()]
    stages = {item.strip() for item in args.only.split(",") if item.strip()}
    if args.frames < 300:
        print("warning: --frames < 300 is only meant for pipeline smoke tests", flush=True)
    wait_for_quiet()

    before = visual.save_hashes()
    write(out / "default-save-before.json", before)
    project = None
    display_info = None
    variants = []
    baselines = []
    ablations = []
    controls = None
    try:
        with tempfile.TemporaryDirectory(prefix="harumachi-perf-bench-") as temporary:
            stage = Path(temporary)
            project = stage / "game"
            subprocess.run(["cp", "-cR", str(source_project), str(project)], check=True)
            (project / "override.cfg").write_text(
                "[display]\nwindow/size/no_focus=true\nwindow/vsync/vsync_mode=0\nwindow/dpi/allow_hidpi=%s\n" % args.allow_hidpi)
            env = dict(os.environ, HARUMACHI_SAVE_DIR=str(stage / "save"))
            run([str(ROOT / "tools/godot"), "--headless", "--path", str(project), "--editor", "--import", "--audio-driver", "Dummy"],
                out / "import", env, args.import_limit, require_result=False)

            (project / "display_probe.gd").write_text(
                'extends SceneTree\nfunc _initialize() -> void:\n for i: int in DisplayServer.get_screen_count():\n'
                '  print("PROBE_SCREEN ",i," ",DisplayServer.screen_get_position(i)," ",DisplayServer.screen_get_size(i),'
                '" scale=",DisplayServer.screen_get_scale(i)," refresh=",DisplayServer.screen_get_refresh_rate(i))\n quit()\n')
            probe = subprocess.run([str(ROOT / "tools/godot"), "--path", str(project), "--audio-driver", "Dummy",
                                    "--script", "res://display_probe.gd"], env=env, capture_output=True, text=True, timeout=120)
            (out / "display-probe.log").write_text(probe.stdout + probe.stderr)
            screens = re.findall(r"PROBE_SCREEN (\d+) \((-?\d+), (-?\d+)\) \((\d+), (\d+)\) scale=(\S+) refresh=(\S+)", probe.stdout)
            match = next((item for item in screens if int(item[0]) == args.screen), None)
            if match is None:
                raise RuntimeError("Requested existing screen is not visible to the engine")
            offset = (60, 60)
            position = "%d,%d" % (int(match[1]) + offset[0], int(match[2]) + offset[1])
            display_info = {
                "display_mode": "existing",
                "screen": args.screen,
                "screen_position": [int(match[1]), int(match[2])],
                "screen_size": [int(match[3]), int(match[4])],
                "screen_scale": float(match[5]),
                "screen_refresh": float(match[6]),
                "window_offset": list(offset),
                "allow_hidpi": args.allow_hidpi,
                "virtual_display_created": False,
                "note": "2026-10-18 session rule: no virtual screen is created; measurement uses the existing display.",
            }
            write(out / "existing-display.json", display_info)

            def bench_command(folder, resolution, view_ids, ablation, tag):
                return [str(ROOT / "tools/godot"), "--path", str(project), "--screen", str(display_info["screen"]),
                        "-t", "--position", position, "--resolution", "%dx%d" % resolution, "--audio-driver", "Dummy",
                        "--script", "res://scripts/tools/performance_bench.gd", "--",
                        "--out=" + str(folder), "--views=" + ",".join(view_ids), "--frames=" + str(args.frames),
                        "--settle=" + str(args.settle), "--tag=" + tag] + (["--ablation=" + ablation] if ablation else [])

            def finish_variant(folder, expected_views):
                write(folder / "display.json", display_info)
                result = read_result(folder)
                if result.get("status") != "complete":
                    raise RuntimeError("Incomplete benchmark variant: " + str(folder))
                if len(result["samples"]) != len(expected_views):
                    raise RuntimeError("Variant sampled %d of %d views: %s" % (len(result["samples"]), len(expected_views), folder))
                return result

            if "baseline" in stages:
                for resolution in resolutions:
                    name = "baseline-%dx%d" % resolution
                    folder = out / name
                    run_variant(out, folder, bench_command(folder, resolution, views, "", name), env, args.limit, args.retries)
                    result = finish_variant(folder, views)
                    variants.append(folder)
                    viewport = result.get("viewport_size", "")
                    scale = result.get("screen_scale", "")
                    label = "%dx%d（渲染 %s，屏幕 scale %s）" % (resolution + (str(viewport), str(scale)))
                    baselines.append((name, label, result))

            motion_rows = []
            if "motion" in stages and args.motion_views:
                motion_views = [item.strip() for item in args.motion_views.split(",") if item.strip()]
                folder = out / ("motion-%dx%d" % resolutions[0])
                run_variant(out, folder, bench_command(folder, resolutions[0], motion_views, "", "motion"), env, args.limit, args.retries)
                motion_result = finish_variant(folder, motion_views)
                variants.append(folder)
                motion_rows = motion_result["samples"]

            if "ablations" in stages and ablation_names:
                if args.ablation_views:
                    ablation_views = [item.strip() for item in args.ablation_views.split(",") if item.strip()]
                else:
                    reference = baselines[0][2] if baselines else None
                    if reference is None:
                        raise RuntimeError("Ablation stage needs a baseline to rank the views")
                    ranked = sorted(reference["samples"], key=lambda sample: sample["median_ms"], reverse=True)
                    ablation_views = [sample["view"] for sample in ranked[:2]]
                control_resolution = resolutions[0]
                control_folder = out / "ablation-control"
                run_variant(out, control_folder, bench_command(control_folder, control_resolution, ablation_views, "", "ablation-control"), env, args.limit, args.retries)
                control_result = finish_variant(control_folder, ablation_views)
                variants.append(control_folder)
                controls = ("ablation-control", control_result, {"resolution": "%dx%d" % control_resolution, "views": ablation_views})
                for name in ablation_names:
                    folder = out / ("ablation-" + slug(name))
                    run_variant(out, folder, bench_command(folder, control_resolution, ablation_views, name, "ablation-" + name), env, args.limit, args.retries)
                    ablations.append((name, finish_variant(folder, ablation_views)))
                    variants.append(folder)

            summary = summary_payload(baselines, controls, ablations, views, args.frames, args.settle)
            summary["motion"] = motion_rows
            write(out / "summary.json", summary)
            lines = ["# 运行时性能基准（原生 Forward+，现有显示器，静音，独立存档）", ""]
            banner = renderer_banner(out / baselines[0][0] / "engine.log") if baselines else ""
            lines.append("引擎 `%s`；渲染 `%s`；每场景先丢弃 %d 帧暖机，再采样 %d 帧；vsync 关闭。" % (
                baselines[0][2]["engine"] if baselines else "?", banner, args.settle, args.frames))
            lines.append("")
            lines.extend(baseline_markdown(summary, resolutions))
            if motion_rows:
                lines.extend(motion_markdown(motion_rows))
            if ablations:
                lines.extend(ablation_markdown(summary))
            (out / "summary.md").write_text("\n".join(lines) + "\n")
            print("summary written to " + str(out / "summary.md"), flush=True)
    finally:
        after = visual.save_hashes()
        write(out / "default-save-after.json", after)
        changed = [key for key in sorted(before.keys() | after.keys()) if before.get(key) != after.get(key)]
        integrity = {
            "default_save_files": len(before),
            "changed": changed,
            "display_mode": "existing",
            "virtual_display_created": False,
            "temporary_project_removed": project is not None and not project.exists(),
            "fresh_save_per_variant": True,
            "variants": [variant.name for variant in variants],
        }
        write(out / "integrity-and-cleanup.json", integrity)
        print(json.dumps(integrity, ensure_ascii=False), flush=True)
        if changed:
            raise SystemExit("Default save changed during the benchmark: " + ", ".join(changed))


if __name__ == "__main__":
    main()

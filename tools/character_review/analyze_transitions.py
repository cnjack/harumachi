#!/usr/bin/env python3
"""Summarize native transition JSON without changing its frames or source images.

High foot velocity alone is not a pose jump. Alongside dt-normalized velocity,
this report measures the position-step residual against velocities immediately
before and after that step. Constant fast movement therefore has zero residual;
an isolated position discontinuity retains its displacement. Neither measure is
an automatic judgement of natural movement. Native images remain authoritative.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
from pathlib import Path

JOINTS = ("hips", "foot.L", "foot.R")
COLORS = {"hips": "#a34b12", "foot.L": "#126b9c", "foot.R": "#8b4298"}


class JSONStream:
    """Bounded input buffer; whole native reports may exceed 800 MB."""
    def __init__(self, stream):
        self.stream = stream
        self.buffer = ""
        self.position = 0
        self.ended = False
        self.decoder = json.JSONDecoder()

    def fill(self):
        self.buffer = self.buffer[self.position:]
        self.position = 0
        chunk = self.stream.read(1024 * 1024)
        self.buffer += chunk
        self.ended = not chunk

    def peek(self):
        while True:
            if self.position >= len(self.buffer):
                if self.ended:
                    raise ValueError("Unexpected end of transition JSON")
                self.fill()
                continue
            if self.buffer[self.position].isspace():
                self.position += 1
                continue
            return self.buffer[self.position]

    def take(self, expected):
        actual = self.peek()
        if actual != expected:
            raise ValueError(f"Expected {expected!r}, got {actual!r}")
        self.position += 1

    def value(self):
        self.peek()
        while True:
            try:
                value, end = self.decoder.raw_decode(self.buffer, self.position)
                if not self.ended and (end == len(self.buffer) or self.buffer[end] not in " \t\r\n,]}:"):
                    self.fill()
                    continue
                self.position = end
                return value
            except json.JSONDecodeError:
                if self.ended:
                    raise
                self.fill()


def read_transition_report(path):
    """Discard only unused per-frame full-bone payload, never rewrite the input.

    Every full bone sample is decoded separately, so neither the old verbose
    report nor the compact encoding needs to be resident in memory at once.
    Request/frame/clip/root/joint metadata are retained for independent pairing.
    """
    def samples(reader):
        result = []
        reader.take("[")
        while reader.peek() != "]":
            sample = reader.value()
            result.append({key: value for key, value in sample.items()
                           if key not in {"bones", "bone_transforms", "soles"}})
            if reader.peek() != ",":
                break
            reader.take(",")
        reader.take("]")
        return result

    def native_case(reader):
        result = {}
        reader.take("{")
        while reader.peek() != "}":
            key = reader.value()
            reader.take(":")
            result[key] = samples(reader) if key == "full_bone_samples" else reader.value()
            if reader.peek() != ",":
                break
            reader.take(",")
        reader.take("}")
        return result

    with path.open() as stream:
        reader = JSONStream(stream)
        result = {}
        reader.take("{")
        while reader.peek() != "}":
            key = reader.value()
            reader.take(":")
            if key == "cases":
                cases = []
                reader.take("[")
                while reader.peek() != "]":
                    cases.append(native_case(reader))
                    if reader.peek() != ",":
                        break
                    reader.take(",")
                reader.take("]")
                result[key] = cases
            else:
                result[key] = reader.value()
            if reader.peek() != ",":
                break
            reader.take(",")
        reader.take("}")
        return result


def subtract(left, right):
    return [float(a) - float(b) for a, b in zip(left, right)]


def scale(value, amount):
    return [float(component) * amount for component in value]


def length(value):
    return math.sqrt(sum(component * component for component in value))


def relative(frame, joint):
    return subtract(frame["joints"][joint], frame["actor_position"])


def percentile(values, fraction):
    ordered = sorted(values)
    if not ordered:
        return None
    index = (len(ordered) - 1) * fraction
    low = math.floor(index)
    high = math.ceil(index)
    return ordered[low] + (ordered[high] - ordered[low]) * (index - low)


def statistics(values):
    return {"samples": len(values), "median": percentile(values, .5),
            "p95": percentile(values, .95), "maximum": max(values) if values else None}


def frame_metrics(frames):
    """Preserve native chronology and derive one interval record per valid step."""
    intervals = []
    warnings = []
    for index in range(1, len(frames)):
        before, current = frames[index - 1:index + 1]
        dt = float(current["elapsed_s"]) - float(before["elapsed_s"])
        if not math.isfinite(dt) or dt <= 0:
            warnings.append(f"nonpositive/nonfinite interval ending at frame {current.get('frame')}")
            continue
        root_step = subtract(current["actor_position"], before["actor_position"])
        interval = {"before_frame": before["frame"], "after_frame": current["frame"],
                    "frame_index": index, "before_s": float(before["elapsed_s"]),
                    "elapsed_s": float(current["elapsed_s"]), "dt_s": dt,
                    "from_clip": before["clip"], "to_clip": current["clip"],
                    "clip_changed": current["clip"] != before["clip"],
                    "physics_tick_changed": current.get("physics_frame") != before.get("physics_frame"),
                    "root_step_m": length(root_step), "root_speed_mps": length(root_step) / dt,
                    "joints": {}}
        for joint in JOINTS:
            if joint not in before["joints"] or joint not in current["joints"]:
                warnings.append(f"{joint} absent at interval ending frame {current.get('frame')}")
                continue
            delta = subtract(relative(current, joint), relative(before, joint))
            world_delta = subtract(current["joints"][joint], before["joints"][joint])
            values = {"step_m": length(delta), "vertical_step_m": delta[1],
                      "velocity_mps": length(delta) / dt,
                      "vertical_velocity_mps": delta[1] / dt,
                      "world_step_m": length(world_delta), "delta_m": delta,
                      "continuity_residual_m": None, "residual_velocity_mps": None,
                      "continuity_residual_vector_m": None}
            if 1 < index < len(frames) - 1:
                preceding, following = frames[index - 2], frames[index + 1]
                if joint in preceding["joints"] and joint in following["joints"]:
                    previous_dt = float(before["elapsed_s"]) - float(preceding["elapsed_s"])
                    next_dt = float(following["elapsed_s"]) - float(current["elapsed_s"])
                    if previous_dt > 0 and next_dt > 0:
                        previous_velocity = scale(subtract(relative(before, joint), relative(preceding, joint)), 1 / previous_dt)
                        next_velocity = scale(subtract(relative(following, joint), relative(current, joint)), 1 / next_dt)
                        previous_centre = (float(preceding["elapsed_s"]) + float(before["elapsed_s"])) / 2
                        next_centre = (float(current["elapsed_s"]) + float(following["elapsed_s"])) / 2
                        current_centre = (float(before["elapsed_s"]) + float(current["elapsed_s"])) / 2
                        weight = (current_centre - previous_centre) / (next_centre - previous_centre)
                        expected_velocity = [a * (1 - weight) + b * weight
                                             for a, b in zip(previous_velocity, next_velocity)]
                        residual = subtract(delta, scale(expected_velocity, dt))
                        values.update(continuity_residual_m=length(residual),
                                      residual_velocity_mps=length(residual) / dt,
                                      continuity_residual_vector_m=residual)
            interval["joints"][joint] = values
        intervals.append(interval)
    return intervals, warnings


def extrema(intervals, joint, metric):
    valid = [row for row in intervals if row["joints"].get(joint, {}).get(metric) is not None]
    if not valid:
        return None
    row = max(valid, key=lambda item: abs(item["joints"][joint][metric]))
    return {"before_frame": row["before_frame"], "after_frame": row["after_frame"],
            "elapsed_s": row["elapsed_s"], "dt_s": row["dt_s"],
            "from_clip": row["from_clip"], "to_clip": row["to_clip"],
            "root_speed_mps": row["root_speed_mps"], "physics_tick_changed": row["physics_tick_changed"],
            **row["joints"][joint]}


def joint_summary(intervals, joint):
    valid = [row["joints"][joint] for row in intervals if joint in row["joints"]]
    return {"steps_m": statistics([row["step_m"] for row in valid]),
            "velocity_mps": statistics([row["velocity_mps"] for row in valid]),
            "continuity_residual_m": statistics([row["continuity_residual_m"] for row in valid
                                                 if row["continuity_residual_m"] is not None]),
            "maximum_step": extrema(intervals, joint, "step_m"),
            "maximum_velocity": extrema(intervals, joint, "velocity_mps"),
            "maximum_residual": extrema(intervals, joint, "continuity_residual_m")}


def analyze_case(case, window=.25):
    frames = case.get("frames", [])
    intervals, warnings = frame_metrics(frames)
    boundaries = [row for row in intervals if row["clip_changed"]]
    steady = [row for row in intervals
              if all(abs(row["elapsed_s"] - boundary["elapsed_s"]) > window for boundary in boundaries)]
    events = []
    for boundary in boundaries:
        near = [row for row in intervals if abs(row["elapsed_s"] - boundary["elapsed_s"]) <= window]
        eligible_commands = [command for command in case.get("commands", [])
                             if float(command["elapsed_s"]) <= boundary["elapsed_s"]]
        command = max(eligible_commands, key=lambda item: float(item["elapsed_s"])) if eligible_commands else None
        events.append({"from": boundary["from_clip"], "to": boundary["to_clip"],
                       "elapsed_s": boundary["elapsed_s"], "command_at_or_before": command,
                       "immediate_step": boundary, "window_seconds": window,
                       "window_root_speed_mps": statistics([row["root_speed_mps"] for row in near]),
                       "joints": {joint: joint_summary(near, joint) for joint in JOINTS}})
    available_frames = {frame["frame"] for frame in frames}
    by_frame = {frame["frame"]: frame for frame in frames}
    bone_samples = case.get("full_bone_samples", [])
    paired_frames = [sample.get("applied_frame") for sample in bone_samples
                     if sample.get("applied_frame") in available_frames]
    missing = sorted(available_frames - set(paired_frames))
    requests = [int(sample["request_frame"]) for sample in bone_samples if "request_frame" in sample]
    initial_unrequested = None
    if (len(missing) == 1 and frames and missing[0] == frames[0]["frame"] and requests
            and missing[0] <= min(requests) and case.get("sampling_failures") == 0):
        initial_unrequested = {"frame": missing[0], "first_request_frame": min(requests),
                               "reason": "Continuous recording began before the first later-frame full-bone request could acknowledge. This first root/joint sample is retained, not counted as a failed request."}
    elif len(set(paired_frames)) != len(frames):
        warnings.append(f"full-bone coverage {len(set(paired_frames))}/{len(frames)}; preserve missing-frame evidence")
    pairing_errors = 0
    for sample in bone_samples:
        frame = by_frame.get(sample.get("applied_frame"))
        if frame is None:
            pairing_errors += 1
            continue
        invalid_request = ("request_frame" in sample and sample["applied_frame"] <= sample["request_frame"])
        wrong_clip = sample.get("clip") != frame.get("clip")
        wrong_position = any(length(subtract(sample.get("joints", {}).get(joint, frame["joints"][joint]),
                                                    frame["joints"][joint])) > .000001
                             for joint in JOINTS if joint in frame["joints"])
        if invalid_request or wrong_clip or wrong_position:
            pairing_errors += 1
    if pairing_errors:
        warnings.append(f"{pairing_errors} full-bone samples have unmatched request/clip/final joint data")
    return {"character": case["character"], "frame_count": len(frames),
            "full_bone_unique_paired_frames": len(set(paired_frames)),
            "initial_unrequested_continuous_frame": initial_unrequested,
            "full_bone_pairing_errors": pairing_errors,
            "capture_sampling_failures": case.get("sampling_failures"),
            "intervals": intervals, "render_interval_s": statistics([row["dt_s"] for row in intervals]),
            "steady_reference_excludes_seconds_around_clip_changes": window,
            "steady_reference": {joint: joint_summary(steady, joint) for joint in JOINTS},
            "all_frames": {joint: joint_summary(intervals, joint) for joint in JOINTS},
            "events": events, "warnings": warnings}


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def write_svg(case, analysis, path):
    width, panel_height, left, right = 1100, 190, 74, 25
    frames = case.get("frames", [])
    if len(frames) < 2:
        return
    duration = max(float(row["elapsed_s"]) for row in frames)
    panels = [
        ("Actor-relative vertical position (m)",
         {joint: [(float(row["elapsed_s"]), relative(row, joint)[1]) for row in frames
                  if joint in row["joints"]] for joint in JOINTS}),
        ("Actor-relative step velocity (m/s): fast swing alone is not a jump",
         {joint: [(row["elapsed_s"], row["joints"][joint]["velocity_mps"]) for row in analysis["intervals"]
                  if joint in row["joints"]] for joint in JOINTS}),
        ("Continuity residual (mm): compare the same step's dt and native images",
         {joint: [(row["elapsed_s"], row["joints"][joint]["continuity_residual_m"] * 1000)
                  for row in analysis["intervals"]
                  if row["joints"].get(joint, {}).get("continuity_residual_m") is not None] for joint in JOINTS}),
    ]
    result = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{panel_height * len(panels) + 65}" viewBox="0 0 {width} {panel_height * len(panels) + 65}">',
              '<rect width="100%" height="100%" fill="#fff"/>',
              f'<text x="20" y="25" font-family="sans-serif" font-size="18">{html.escape(case["character"])} · native transitions · no automatic naturalness PASS</text>']
    for panel_index, (title, series) in enumerate(panels):
        top = 60 + panel_index * panel_height
        values = [value for pairs in series.values() for _, value in pairs]
        low, high = min(values, default=0), max(values, default=1)
        padding = max((high - low) * .08, .001)
        low, high = low - padding, high + padding
        plot_height = panel_height - 55
        transform_x = lambda time: left + time / max(duration, .001) * (width - left - right)
        transform_y = lambda value: top + 20 + (high - value) / (high - low) * plot_height
        result.append(f'<text x="20" y="{top + 3}" font-family="sans-serif" font-size="13">{html.escape(title)}</text>')
        for grid in range(4):
            value = low + (high - low) * grid / 3
            y = transform_y(value)
            result.append(f'<line x1="{left}" x2="{width-right}" y1="{y:.1f}" y2="{y:.1f}" stroke="#e3e7eb"/>')
            result.append(f'<text x="{left-8}" y="{y+4:.1f}" text-anchor="end" font-family="monospace" font-size="10">{value:.3g}</text>')
        for event in analysis["events"]:
            x = transform_x(event["elapsed_s"])
            result.append(f'<line x1="{x:.1f}" x2="{x:.1f}" y1="{top+18}" y2="{top+20+plot_height}" stroke="#9ba5ae" stroke-dasharray="3 3"><title>{html.escape(event["from"]+" → "+event["to"])}</title></line>')
        for joint, pairs in series.items():
            points = " ".join(f"{transform_x(time):.1f},{transform_y(value):.1f}" for time, value in pairs)
            result.append(f'<polyline points="{points}" fill="none" stroke="{COLORS[joint]}" stroke-width="1.5"/>')
        for tick in range(math.ceil(duration) + 1):
            if tick <= duration:
                result.append(f'<text x="{transform_x(tick):.1f}" y="{top+plot_height+36}" text-anchor="middle" font-family="monospace" font-size="10">{tick}s</text>')
    for index, joint in enumerate(JOINTS):
        result.append(f'<text x="{width-320+index*105}" y="25" fill="{COLORS[joint]}" font-family="sans-serif" font-size="13">{joint}</text>')
    result.append("</svg>")
    path.write_text("\n".join(result), encoding="utf-8")


def contact_sheet(case, analysis, report_folder, output):
    """Copy actual nearest frames onto a separate sheet; source PNGs stay untouched."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        return {"created": False, "reason": "Pillow unavailable; JSON/SVG/Markdown remain available"}
    images = case.get("images", [])
    if not images or not analysis["events"]:
        return {"created": False, "reason": "no source frames or actual clip changes"}
    offsets = (-.18, -.06, 0, .06, .18)
    columns, tile_width, tile_height, header = 5, 320, 211, 29
    canvas = Image.new("RGB", (columns * tile_width, header + len(analysis["events"]) * tile_height), "#eef1f4")
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("Arial.ttf", 12)
    except OSError:
        font = ImageFont.load_default()
    draw.text((8, 7), f'{case["character"]}: actual nearest native images; columns -180/-60/0/+60/+180ms around clip change', fill="black", font=font)
    selected = []
    for event_index, event in enumerate(analysis["events"]):
        for column, offset in enumerate(offsets):
            chosen = min(images, key=lambda row: abs(float(row["elapsed_s"]) - event["elapsed_s"] - offset))
            source = report_folder / case["image_folder"] / chosen["file"]
            x, y = column * tile_width, header + event_index * tile_height
            label = f'{event["from"] or "(empty)"}>{event["to"] or "(empty)"} {float(chosen["elapsed_s"])-event["elapsed_s"]:+.3f}s {chosen.get("clip") or "(empty)"}'
            draw.text((x + 5, y + 4), label, fill="black", font=font)
            if source.is_file():
                with Image.open(source) as original:
                    preview = original.convert("RGB")
                    preview.thumbnail((tile_width, 180))
                    canvas.paste(preview, (x + (tile_width - preview.width) // 2, y + 26))
                selected.append({"event_index": event_index, "requested_offset_s": offset,
                                 "actual_offset_s": float(chosen["elapsed_s"]) - event["elapsed_s"],
                                 "source": str(source.resolve()), "sha256": digest(source),
                                 "final_process_frame": chosen.get("final_process_frame")})
            else:
                draw.text((x + 5, y + 70), "SOURCE PNG MISSING", fill="#b00020", font=font)
                selected.append({"event_index": event_index, "missing_source": str(source)})
    target = output / f'{case["character"]}-contact.png'
    canvas.save(target)
    return {"created": True, "file": target.name, "selected_native_frames": selected}


def text_number(value, multiplier=1):
    return "—" if value is None else f"{value * multiplier:.2f}"


def markdown_report(result):
    lines = ["# 原生动作切换测量", "", "这是运动数据与原生图片的审查辅助，不自动判定动作自然或通过。",
             "逐帧位移先减去同帧人物根位移，再除以真实 dt 得到速度。脚摆动较快本身不等于姿势跳变。",
             "连续性残差使用该步前、后相邻区间的速度，按时间中心插值估算本步应有的位移；实际位移与估算位移的差另以毫米报告。匀速快速摆动的残差为零；加减速、物理更新节奏和测量噪声仍可能产生残差，需要结合原生帧判断。",
             "相邻 dt 很不均匀时，速度预测可能把前一步的突变放大到下一步残差；残差甚至可大于真实步长，不能把残差毫米数直接称为画面跳动幅度。实际逐帧位移与 dt 必须一起看，另与同动画的稳态参考比较。",
             "实际停止输入/取消路线造成的根速度变化与骨盆、脚相对人物根的突变分别记录。PNG 读取会影响这些帧的 dt，因此本报告不是性能基准。", "",
             f'输入 SHA-256：`{result["input_sha256"]}`', ""]
    for case in result["cases"]:
        lines += [f'## {case["character"]}', "",
                  f'最终帧 {case["frame_count"]}；完整骨架配对 {case["full_bone_unique_paired_frames"]}；采样失败 {case["capture_sampling_failures"]}。', "",
                  f'[位置、速度与连续性图]({case["character"]}.svg)', ""]
        if case["contact_sheet"]["created"]:
            lines += [f'![实际切换帧]({case["contact_sheet"]["file"]})', ""]
        lines += ["| 实际动画切换 | 秒 | 根速度范围 m/s | 骨盆最大步长 mm | 骨盆最大速度 m/s | 骨盆最大残差 mm | 左/右脚最大残差 mm |",
                  "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
        for event in case["events"]:
            hips = event["joints"]["hips"]
            left = event["joints"]["foot.L"]["continuity_residual_m"]["maximum"]
            right = event["joints"]["foot.R"]["continuity_residual_m"]["maximum"]
            root = event["window_root_speed_mps"]
            lines.append(f'| {event["from"] or "空 clip"} → {event["to"] or "空 clip"} | {event["elapsed_s"]:.3f} | {text_number(root["median"])} / p95 {text_number(root["p95"])} | {text_number(hips["steps_m"]["maximum"],1000)} | {text_number(hips["velocity_mps"]["maximum"])} | {text_number(hips["continuity_residual_m"]["maximum"],1000)} | {text_number(left,1000)} / {text_number(right,1000)} |')
        if case["initial_unrequested_continuous_frame"]:
            lines += ["", "首个连续根/关节帧先于首个完整骨架请求确认，已保留并单列；后续请求配对另行核查。"]
        if case["warnings"]:
            lines += ["", "记录限制：" + "; ".join(case["warnings"])]
        lines.append("")
    return "\n".join(lines) + "\n"


def write_index(result, output):
    sections = []
    for case in result["cases"]:
        name = html.escape(case["character"])
        image = f'<a href="{name}-contact.png"><img loading="lazy" src="{name}-contact.png" alt="{name} native transition contact sheet"></a>' if case["contact_sheet"]["created"] else ""
        sections.append(f'<section id="{name}"><h2>{name}</h2><p>{case["frame_count"]} final frames · {case["full_bone_unique_paired_frames"]} full-bone pairs</p><img src="{name}.svg" alt="{name} measured position velocity and residual">{image}</section>')
    document = '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>人物动作切换测量</title><style>body{font:15px/1.65 system-ui,sans-serif;max-width:1120px;margin:30px auto;padding:0 18px;background:#f5f6f7;color:#24313c}section{background:white;padding:18px;margin:22px 0}img{display:block;width:100%;height:auto}h1,h2{line-height:1.2}a{color:#126b9c}code{overflow-wrap:anywhere}</style><h1>人物动作切换测量</h1><p>位移、速度、连续性残差分别查看。较快的摆腿不直接判作跳变，停止输入的根速度变化与身体相对根的突变分开记录。本页不自动判定自然度通过。</p><p>连续性残差按相邻速度插值估算本步位移，再比较实际位移。加减速、物理帧节奏、截图开销均须结合原生帧核对。</p><p><a href="analysis.md">逐次切换数据表</a> · <a href="analysis.json">完整统计与源图摘要</a></p>'
    document += "".join(sections) + "</html>"
    (output / "index.html").write_text(document, encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path, help="transition-gait.json from the native QA driver")
    parser.add_argument("--out", type=Path, help="Derived artifacts only; defaults to a sibling transition-analysis folder")
    parser.add_argument("--window", type=float, default=.25, help="Seconds around each actual clip change")
    args = parser.parse_args(argv)
    if not math.isfinite(args.window) or args.window <= 0:
        parser.error("--window must be a positive finite number")
    report_path = args.report.resolve()
    source_sha256 = digest(report_path)
    source = read_transition_report(report_path)
    output = (args.out or report_path.parent / "transition-analysis").resolve()
    output.mkdir(parents=True, exist_ok=True)
    result = {"input": str(report_path), "input_sha256": source_sha256,
              "analysis_script_sha256": digest(Path(__file__)), "source_failures": source.get("failures", []),
              "automatic_naturalness_pass": False,
              "method": "Root translation removed per sample. Step velocities use actual adjacent elapsed times. Continuity residual predicts a step from the interval velocities immediately before and after it, interpolated at the step's time centre. This distinguishes fast smooth movement from a local position outlier but does not independently prove a perceptual jump or naturalness.",
              "cases": []}
    for case in source.get("cases", []):
        analysis = analyze_case(case, args.window)
        write_svg(case, analysis, output / f'{case["character"]}.svg')
        analysis["contact_sheet"] = contact_sheet(case, analysis, report_path.parent, output)
        result["cases"].append(analysis)
    (output / "analysis.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    (output / "analysis.md").write_text(markdown_report(result), encoding="utf-8")
    write_index(result, output)
    if digest(report_path) != source_sha256:
        raise RuntimeError("Source report changed during analysis; this output is not a frozen input analysis")
    summary = [{"character": case["character"], "frames": case["frame_count"],
                "hips_max_step_mm": (case["all_frames"]["hips"]["steps_m"]["maximum"] or 0) * 1000,
                "hips_max_residual_mm": (case["all_frames"]["hips"]["continuity_residual_m"]["maximum"] or 0) * 1000,
                "warnings": case["warnings"]} for case in result["cases"]]
    print(json.dumps({"output": str(output), "input_sha256": source_sha256, "source_failures": result["source_failures"], "automatic_naturalness_pass": False, "cases": summary}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

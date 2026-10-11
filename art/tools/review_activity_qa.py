#!/usr/bin/env python3
"""Assemble each real activity screenshot with its optional diagnostic cameras.

Images are never marked reviewed by this tool. Manual assessments survive only
when every native PNG in a group still has the same SHA-256 digest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ANGLE = re.compile(r"^(.*?)_(?:diagnostic_)?angle_(-?\d+)$")


def make_sheets(directory: Path, output: Path, width: int = 640) -> dict:
    directory = directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    manifest = directory / "diagnostic-manifest.json"
    diagnostic = json.loads(manifest.read_text()) if manifest.exists() else {}
    entries = {Path(shot["file"]).name: shot for shot in diagnostic.get("shots", [])}
    previous_path = output / "index.json"
    previous = json.loads(previous_path.read_text()) if previous_path.exists() else {}
    old_groups = {row["activity_frame"]: row for row in previous.get("sheets", [])}
    grouped = defaultdict(list)
    for path in sorted(directory.glob("*.png")):
        match = ANGLE.match(path.stem)
        label = match.group(1) if match else path.stem
        grouped[label].append((int(match.group(2)) if match else None, path))
    rows = []
    height = round(width * 9 / 16)
    font = ImageFont.load_default(size=16)
    for label, files in sorted(grouped.items()):
        files.sort(key=lambda item: (item[0] is not None, item[0] or 0))
        canvas = Image.new("RGB", (width * 2, ((len(files) + 1) // 2) * (height + 30)), "#ebe8de")
        draw = ImageDraw.Draw(canvas)
        frames = []
        old = old_groups.get(label, {})
        old_frames = {item["file"]: item for item in old.get("frames", [])}
        for index, (angle, path) in enumerate(files):
            fingerprint = hashlib.sha256(path.read_bytes()).hexdigest()
            metadata = entries.get(path.name, {})
            if metadata.get("sha256", fingerprint) != fingerprint:
                raise ValueError(f"diagnostic manifest digest differs: {path}")
            with Image.open(path) as image:
                native_size = image.size
                thumb = ImageOps.contain(image.convert("RGB"), (width, height), Image.Resampling.LANCZOS)
            x, y = (index % 2) * width, (index // 2) * (height + 30)
            canvas.paste(thumb, (x + (width - thumb.width) // 2, y + (height - thumb.height) // 2))
            role = metadata.get("kind", "original_camera" if angle is None else "supplemental_camera")
            caption = "original camera" if angle is None else f"angle {angle} / {role}"
            draw.text((x + 8, y + height + 5), caption, fill="#172e36", font=font)
            previous_frame = old_frames.get(str(path), {})
            frames.append({"file": str(path), "sha256": fingerprint, "width": native_size[0], "height": native_size[1],
                           "angle": angle, "kind": role, "reviewed": previous_frame.get("sha256") == fingerprint and
                           bool(previous_frame.get("reviewed", old.get("reviewed", False)))})
        destination = output / f"{label}.jpg"
        canvas.save(destination, quality=94, subsampling=0)
        unchanged = [item["sha256"] for item in old.get("frames", [])] == [item["sha256"] for item in frames]
        rows.append({"activity_frame": label, "sheet": str(destination.resolve()), "frames": frames,
                     "reviewed": all(frame["reviewed"] for frame in frames),
                     "findings": old.get("findings", []) if unchanged else [],
                     "prior_review": [] if unchanged else old.get("findings", [])})
    report = {"source_directory": str(directory), "diagnostic_manifest": str(manifest) if manifest.exists() else None,
              "sheet_count": len(rows), "frame_count": sum(len(row["frames"]) for row in rows), "sheets": rows}
    previous_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--cell-width", type=int, default=640)
    args = parser.parse_args()
    report = make_sheets(args.directory, args.output, args.cell_width)
    print(json.dumps({"sheets": report["sheet_count"], "frames": report["frame_count"], "index": str((args.output / "index.json").resolve())}))


if __name__ == "__main__":
    main()

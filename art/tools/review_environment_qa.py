#!/usr/bin/env python3
"""Group native QA screenshots by camera; retain every original in the review index.

Usage: python review_environment_qa.py --manifest <shots>/manifest.json --output <sheets>
The script assembles contact sheets and a review checklist. It never marks a sheet
reviewed automatically: an image existing on disk is not visual verification.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


CONDITIONS = ("morning", "noon", "sunset", "night", "rain", "cloudy")


def image_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_sheets(manifest_path: Path, output: Path, cell_width: int = 640) -> dict:
    manifest = json.loads(manifest_path.read_text())
    output.mkdir(parents=True, exist_ok=True)
    groups: dict[str, list[dict]] = defaultdict(list)
    for shot in manifest["shots"]:
        configuration = shot.get("configuration", {})
        if configuration.get("group") not in ("environments", "activities"):
            continue
        groups[shot["name"].split("__", 1)[0]].append(shot)
    # Keep manual assessments when new screenshots are assembled after a repair.
    old_index_path = output / "index.json"
    old_index = json.loads(old_index_path.read_text()) if old_index_path.exists() else {}
    previous = {row["camera"]: row for row in old_index.get("sheets", [])}
    rows = []
    font = ImageFont.load_default(size=18)
    small_font = ImageFont.load_default(size=14)
    for camera, shots in sorted(groups.items()):
        # Assessments follow the exact image hash, including partial weather recaptures.
        old = previous.get(camera, {})
        previous_frames = {frame["name"]: frame for frame in old.get("frames", [])}
        shots.sort(key=lambda shot: (CONDITIONS.index(shot["name"].split("__")[-1])
                   if shot["name"].split("__")[-1] in CONDITIONS else 99, shot["name"]))
        cols = 2
        cell_height = round(cell_width * 9 / 16)
        label_height = 30
        sheet_height = ((len(shots) + cols - 1) // cols) * (cell_height + label_height)
        sheet = Image.new("RGB", (cols * cell_width, sheet_height), "#ebe8de")
        draw = ImageDraw.Draw(sheet)
        frames = []
        for index, shot in enumerate(shots):
            image_path = manifest_path.parent / shot["file"]
            if not image_path.is_file():
                raise FileNotFoundError(image_path)
            with Image.open(image_path) as original:
                width, height = original.size
                thumb = ImageOps.contain(original.convert("RGB"), (cell_width, cell_height), Image.Resampling.LANCZOS)
                x = (index % cols) * cell_width
                y = (index // cols) * (cell_height + label_height)
                sheet.paste(thumb, (x + (cell_width - thumb.width) // 2, y + (cell_height - thumb.height) // 2))
                label = shot["name"].split("__")[-1]
                draw.text((x + 8, y + cell_height + 5), label, fill="#172e36", font=font)
                draw.text((x + cell_width - 110, y + cell_height + 7), f"{width} x {height}", fill="#4f5e61", font=small_font)
            fingerprint = image_sha(image_path)
            previous_frame = previous_frames.get(shot["name"], {})
            reviewed = (previous_frame.get("sha256") == fingerprint and
                        bool(previous_frame.get("reviewed", old.get("reviewed", False))))
            frames.append({"name": shot["name"], "condition": shot["name"].split("__")[-1],
                           "file": str(image_path.resolve()), "sha256": fingerprint,
                           "width": width, "height": height, "reviewed": reviewed})
        destination = output / f"{camera}.jpg"
        sheet.save(destination, quality=94, subsampling=0)
        configuration = shots[0].get("configuration", {})
        old_fingerprints = [item["sha256"] for item in old.get("frames", [])]
        new_fingerprints = [item["sha256"] for item in frames]
        unchanged = old_fingerprints == new_fingerprints
        rows.append({"camera": camera, "scene": configuration.get("scene", ""),
                     "label": configuration.get("label", ""),
                     "camera_role": configuration.get("camera_role", ""),
                     "sheet": str(destination.resolve()), "frames": frames,
                     "reviewed": all(frame["reviewed"] for frame in frames),
                     "findings": old.get("findings", []) if unchanged else [],
                     "prior_review": old.get("findings", []) if not unchanged else []})
    result = {"source_manifest": str(manifest_path.resolve()), "engine": manifest.get("engine", ""),
              "sheet_count": len(rows), "frame_count": sum(len(row["frames"]) for row in rows),
              "sheets": rows}
    old_index_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--cell-width", type=int, default=640)
    args = parser.parse_args()
    result = make_sheets(args.manifest, args.output, args.cell_width)
    print(json.dumps({"sheets": result["sheet_count"], "frames": result["frame_count"],
                      "index": str((args.output / "index.json").resolve())}))


if __name__ == "__main__":
    main()

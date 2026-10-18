#!/usr/bin/env python3
"""Annotate final applied bones and make contact sheets beside native evidence.

Original PNGs are never rewritten. Screen points are scaled from the recorded
projection viewport; these overlays are analytical x-ray annotations.
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

VIEWS = ["front", "right", "back", "left", "top"]


def annotate(folder):
    font = ImageFont.load_default(size=16)
    index = []
    total = 0
    for batch in ("locomotion-poses", "joint-poses"):
        manifest = folder / batch / "manifest.json"
        if not manifest.exists():
            continue
        groups = {}
        overlay_dir = folder / "skeleton-overlay" / batch
        overlay_dir.mkdir(parents=True, exist_ok=True)
        for row in json.loads(manifest.read_text())["shots"]:
            bones = row.get("bones", [])
            viewport = row.get("projection_viewport")
            if not bones or not viewport or min(viewport) <= 0:
                raise ValueError("Missing final bones or projection viewport: " + row["file"])
            sample = row.get("pose_sample", {})
            if sample and not (sample["request_id"] == sample["acknowledged_request"]
                               and sample["applied_frame"] == sample["captured_frame"]):
                raise ValueError("Stale pose metadata: " + row["file"])
            source = folder / batch / row["file"]
            with Image.open(source) as original:
                overlay = original.convert("RGB")
                draw = ImageDraw.Draw(overlay)
                scale = (overlay.width / viewport[0], overlay.height / viewport[1])
                points = [(b["screen"][0] * scale[0], b["screen"][1] * scale[1]) for b in bones]
                for i, bone in enumerate(bones):
                    parent = bone["parent"]
                    if parent < 0:
                        continue
                    colour = "#00ffff" if "Left" in bone["name"] else "#ff8a45" if "Right" in bone["name"] else "#ffef41"
                    draw.line((*points[i], *points[parent]), fill="#182333", width=6)
                    draw.line((*points[i], *points[parent]), fill=colour, width=3)
                for x, y in points:
                    draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill="white")
                draw.text((12, 12), "FINAL APPLIED BONES / cyan=L orange=R yellow=spine / x-ray annotation",
                          font=font, fill="black", stroke_width=2, stroke_fill="white")
                overlay.save(overlay_dir / row["file"])
            total += 1
            groups.setdefault((row["id"], row["action"]), {})[(float(row["phase"]), row["view"])] = source
        for (actor, action), frames in groups.items():
            phases = sorted({p for p, _ in frames})
            if any((p, v) not in frames for p in phases for v in VIEWS):
                raise ValueError(f"Incomplete five-direction sheet: {actor}/{action}")
            cellw, cellh = 250, 360
            sheet = Image.new("RGB", (len(phases) * cellw, len(VIEWS) * cellh + 45), "#17232f")
            draw = ImageDraw.Draw(sheet)
            draw.text((12, 12), f"{actor} / {action} / native Forward+ / phase by column", font=font, fill="white")
            for y, view in enumerate(VIEWS):
                for x, phase in enumerate(phases):
                    with Image.open(frames[(phase, view)]) as image:
                        image = image.crop((int(image.width * .336), int(image.height * .16), int(image.width * .664), image.height))
                        image.thumbnail((cellw, cellh - 26))
                        sheet.paste(image, (x * cellw + (cellw - image.width) // 2, 45 + y * cellh + 26))
                    draw.text((x * cellw + 5, 45 + y * cellh + 4), f"{view} p{phase:g}", font=font, fill="white")
            target = folder / "sheets" / batch / f"{actor}-{action}.jpg"
            target.parent.mkdir(parents=True, exist_ok=True)
            sheet.save(target, quality=94)
            index.append({"batch": batch, "actor": actor, "action": action, "phases": phases,
                          "sheet": str(target.relative_to(folder))})
    (folder / "sheets").mkdir(exist_ok=True)
    (folder / "sheets/index.json").write_text(json.dumps(index, indent=2))
    print(json.dumps({"overlays": total, "sheets": len(index)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    annotate(parser.parse_args().evidence.resolve())

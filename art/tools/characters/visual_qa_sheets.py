#!/usr/bin/env python3
"""Make labelled review sheets from character_visual_qa.gd's native PNGs."""
import argparse
import json
import re
import time
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("capture", type=Path)
    parser.add_argument("--partial", action="store_true", help="Review finished PNG groups before the capture manifest is written")
    args = parser.parse_args()
    source = args.capture
    if args.partial:
        shots = []
        pattern = re.compile(r"^(?P<scene>.+?)-(?P<id>sora|ren|haru|mio|aoi|tanaka|kazuko)-(?P<action>.+?)-p(?P<phase>\d+)-(?P<view>front|right|back|left|oblique_front|oblique_back|high|low)(?:-t(?P<time>\d+))?(?:-s(?P<sample>\d+))?\.png$")
        for file in sorted(source.glob("*.png")):
            if time.time() - file.stat().st_mtime < .5:
                continue
            match = pattern.match(file.name)
            if not match:
                continue
            shot = match.groupdict()
            shot["phase"] = int(shot["phase"]) / 100
            shot["file"] = file.name
            shot["kind"] = "partial native capture"
            if shot["time"] is None:
                del shot["time"]
            else:
                shot["time"] = int(shot["time"])
            shots.append(shot)
        manifest = {"shots": shots}
    else:
        manifest = json.loads((source / "manifest.json").read_text())
    target = source / "sheets"
    target.mkdir(exist_ok=True)
    groups = defaultdict(list)
    for shot in manifest["shots"]:
        key = (shot["id"], shot["scene"], shot["action"], "" if shot["scene"] == "lighting" else shot.get("time", ""))
        groups[key].append(shot)
    font = ImageFont.load_default(size=18)
    index = []
    for key, shots in groups.items():
        order = {"front": 0, "right": 1, "back": 2, "left": 3, "oblique_front": 0, "oblique_back": 1, "high": 2, "low": 3}
        shots.sort(key=lambda shot: (shot.get("time", 0), shot.get("phase", 0), int(shot.get("sample") or 0), order[shot["view"]]))
        width, height = 480, 270
        columns = min(4, len(shots))
        rows = (len(shots) + columns - 1) // columns
        sheet = Image.new("RGB", (columns * width, 42 + rows * (height + 32)), "#17232f")
        draw = ImageDraw.Draw(sheet)
        title = " / ".join(str(part) for part in key if str(part))
        draw.text((12, 10), title, font=font, fill="white")
        for index_shot, shot in enumerate(shots):
            x = index_shot % columns * width
            y = 42 + index_shot // columns * (height + 32)
            with Image.open(source / shot["file"]) as image:
                image.thumbnail((width, height))
                sheet.paste(image, (x + (width - image.width) // 2, y))
            label = "%s p%.2f %s%s" % (shot["view"], shot.get("phase", 0), shot["kind"], " t%04d" % shot["time"] if "time" in shot else "")
            draw.text((x + 8, y + height + 5), label, font=font, fill="#e3e9ef")
        name = "-".join(str(part) for part in key if str(part)) + ".jpg"
        sheet.save(target / name, quality=91)
        index.append({"sheet": name, "shots": [shot["file"] for shot in shots], "id": key[0], "scene": key[1], "action": key[2]})
    (target / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2))
    print(json.dumps({"sheets": len(index), "screenshots": len(manifest["shots"]), "path": str(target)}))


if __name__ == "__main__":
    main()

"""Contact sheets and measurements from --review-motion's real Metal PNGs.

This is a review tool, not a naturalness pass/fail test. In particular, opaque
joint centres do not establish that outlines or painted seams are correct.
Requires Pillow; does not repaint or modify source artwork.
"""
import argparse
import json
import math
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    root = args.directory
    data = json.loads((root / "review-frames.json").read_text())
    groups = defaultdict(list)
    for entry in data["records"]:
        groups[entry["group"]].append(entry)
    fonts = ["/System/Library/Fonts/STHeiti Light.ttc", "DejaVuSans.ttf"]
    for path in fonts:
        try:
            font = ImageFont.truetype(path, 16)
            break
        except OSError:
            continue
    else:
        font = ImageFont.load_default()
    names = dict(idle="放下", wave="招手", think="思考", talk="说话")

    def picture(entry, box=None, size=None, background="#faf9f4"):
        with Image.open(root / entry["frame"]) as source:
            crop = source.convert("RGBA")
        if box:
            crop = crop.crop(box)
        result = Image.new("RGBA", crop.size, background)
        result.alpha_composite(crop)
        if size:
            result = result.resize(size, Image.Resampling.LANCZOS)
        return result.convert("RGB")

    regions = [("shoulder_left", "左肩"), ("shoulder_right", "右肩"),
               ("elbow_left", "左肘"), ("elbow_right", "右肘"),
               ("cuff_left", "左袖口"), ("cuff_right", "右袖口"),
               ("wrist_left", "左手腕"), ("wrist_right", "右手腕"),
               ("neck", "颈部"), ("waist", "腰部")]
    for gesture in names:
        phases = [0, 8, 15, 25, 45, 75, 129, 147]
        sheet = Image.new("RGB", (1360, 40 + len(regions) * 176), "#eeede8")
        draw = ImageDraw.Draw(sheet)
        for col, frame in enumerate(phases):
            entry = groups["gesture-" + gesture][frame]
            draw.text((85 + col * 160, 10), f'{names[gesture]} {frame / 30:.2f}s', font=font, fill="#25333b")
            for row, (region, label) in enumerate(regions):
                cx, cy = entry["centers"][region]
                w, h = (160, 90) if region == "waist" else (88, 80)
                box = (round(cx - w / 2), round(cy - h / 2), round(cx + w / 2), round(cy + h / 2))
                sheet.paste(picture(entry, box, (160, 146)), (80 + col * 160, 40 + row * 176))
                if col == 0:
                    draw.text((4, 100 + row * 176), label, font=font, fill="#25333b")
        sheet.save(root / f"joints-{gesture}.png")

    def gallery(filename, rows, phases, title):
        sheet = Image.new("RGB", (len(phases) * 275, len(rows) * 290), "#eeede8")
        draw = ImageDraw.Draw(sheet)
        for row, entries in enumerate(rows):
            for col, frame in enumerate(phases):
                entry = entries[frame]
                sheet.paste(picture(entry, (55, 70, 705, 650), (275, 245)), (col * 275, row * 290 + 40))
                draw.text((col * 275 + 7, row * 290 + 10), title(entry), font=font, fill="#25333b")
        sheet.save(root / filename)

    for to in names:
        gallery(f"switch-to-{to}.png", [groups[f"switch-{start}-{to}"] for start in names],
                [0, 3, 9, 18, 30, 45, 75, 120] if len(groups[f"switch-idle-{to}"]) > 120 else [0, 3, 6, 9, 12, 18, 27, 36],
                lambda e: f'{names[e["group"].split("-")[1]]} → {names[to]} {int(Path(e["frame"]).stem)/30:.2f}s')
    gallery("automatic-speech.png", [groups[f"automatic-speech-{time}"] for time in [2, 18, 36]],
            [8, 9, 10, 11, 24, 25, 26, 36], lambda e: f'自动/说话 {e["time"]:.2f}s')
    late = [entries for group, entries in groups.items() if group.startswith("late-")]
    if late:
        gallery("late-clock.png", late, [0, 3, 9, 18, 30, 45, 75, 120],
                lambda e: f'{e["group"]} {int(Path(e["frame"]).stem)/30:.2f}s')
    gallery("look-extremes.png", [groups["look-extremes"][i:i + 5] for i in range(0, len(names)*5, 5)],
            list(range(5)), lambda e: f'{names[e["gesture"]]} 视线 {e["look"]}')
    auto_phases = [0, 8, 15, 30, 75, 137, 149, 150, 479, 488, 495, 510, 540, 617, 629, 630,
                   1019, 1028, 1035, 1050, 1080, 1217, 1229, 1230, 1559, 1560, 1563, 1566]
    gallery("automatic-cycle.png", [groups["automatic"][i:i + 1] for i in auto_phases], [0],
            lambda e: f'自动 {e["time"]:.2f}s')
    # Arrange this long timeline into four columns without changing source pixels.
    with Image.open(root / "automatic-cycle.png") as long_sheet:
        timeline = Image.new("RGB", (1100, 7 * 290), "#eeede8")
        for i in range(len(auto_phases)):
            timeline.paste(long_sheet.crop((0, i * 290, 275, (i + 1) * 290)), ((i % 4) * 275, (i // 4) * 290))
        timeline.save(root / "automatic-cycle.png")

    statistics = {}
    minimum_alpha = 255
    low_centers = []
    clipped = []
    for group, entries in groups.items():
        displacements = []
        for before, after in zip(entries, entries[1:]):
            a, b = before["centers"]["wrist_right"], after["centers"]["wrist_right"]
            displacements.append((math.dist(a, b), before["frame"], after["frame"]))
        statistics[group] = {"frames": len(entries), "largest_right_wrist_step_px":
                             dict(zip(["distance", "before", "after"], max(displacements)))
                             if displacements and group != "look-extremes" else None}
        for entry in entries:
            with Image.open(root / entry["frame"]) as source:
                alpha = source.getchannel("A")
                box = alpha.point(lambda x: 255 if x > 32 else 0).getbbox()
                if box and (box[0] < 5 or box[1] < 5 or box[2] > source.width - 5 or box[3] > source.height - 5):
                    clipped.append({"frame": entry["frame"], "bounds": box})
                for joint, (cx, cy) in entry["centers"].items():
                    x, y = round(cx), round(cy)
                    value = min(alpha.crop((x - 1, y - 1, x + 2, y + 2)).tobytes())
                    minimum_alpha = min(minimum_alpha, value)
                    if value < 192:
                        low_centers.append({"frame": entry["frame"], "joint": joint, "alpha": value})
    report = {"frames": data["frames"], "joint_center_samples": data["frames"] * 10,
              "minimum_center_alpha": minimum_alpha, "low_center_samples": low_centers, "clipped_frames": clipped,
              "groups": statistics, "visual_acceptance": "requires_review",
              "measurement_limit": "Centre samples cannot establish seam, outline or animation naturalness."}
    (root / "measurements.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "groups"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

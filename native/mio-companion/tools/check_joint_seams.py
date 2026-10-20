"""Read real Metal frames and detect the dark cut line inside flat skin bands.

The band straddles the measured sleeve/common-forearm source cut at -54 px
from the wrist. Alpha at the joint centre alone missed this defect.
"""
import json
import statistics
import sys
from pathlib import Path

from PIL import Image

root = Path(sys.argv[1])
records = json.loads((root / "review-frames.json").read_text())["records"]
failures = []
tested = 0
maximum = 0.0
worst = None
for entry in records:
    with Image.open(root / entry["frame"]).convert("RGBA") as image:
        for side in ["left", "right"]:
            wrist = entry["centers"]["wrist_" + side]
            cuff = entry["centers"]["cuff_" + side]
            direction = [(wrist[i] - cuff[i]) / 40 for i in range(2)]
            normal = [-direction[1], direction[0]]
            rows = []
            valid = True
            for along in range(-61, -46):
                pixels = []
                for across in [-5, -3, 0, 3, 5]:
                    x = round(wrist[0] + direction[0] * along + normal[0] * across)
                    y = round(wrist[1] + direction[1] * along + normal[1] * across)
                    if not (0 <= x < image.width and 0 <= y < image.height):
                        valid = False
                        break
                    pixels.append(image.getpixel((x, y)))
                if not valid:
                    break
                rows.append([statistics.mean(p[c] for p in pixels) for c in range(4)])
            if not valid:
                continue
            # Only analyse bands with skin at both ends. Clothing/occlusion
            # boundaries have an intentional colour edge and require review.
            if not all(r[0] > 235 and 170 < r[1] < 235 and 140 < r[2] < 210 and r[3] > 250
                       for r in rows[:2] + rows[-2:]):
                continue
            first = statistics.mean(sum(r[:3]) / 3 for r in rows[:2])
            last = statistics.mean(sum(r[:3]) / 3 for r in rows[-2:])
            if abs(last - first) > 4:
                continue
            deficits = [first + (last - first) * i / 14 - sum(row[:3]) / 3
                        for i, row in enumerate(rows)]
            deficit = max(deficits[2:-2])
            tested += 1
            evidence = {"frame": entry["frame"], "side": side, "dark_line_deficit": deficit}
            if deficit > maximum:
                maximum = deficit
                worst = evidence
            if deficit > 4:
                failures.append(evidence)
report = {"tested_flat_skin_bands": tested, "threshold": 4, "maximum_dark_line_deficit": maximum,
          "worst": worst, "failures": failures,
          "scope": "Flat opaque skin bands around the measured source cut; other outlines require visual review."}
(root / "seam-audit.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({**report, "failures": failures[:10]}, indent=2))
sys.exit(bool(failures) or tested < 1000)

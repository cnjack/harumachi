"""Check real Metal output; this reads pixels and never repaints source artwork."""
import json
import sys
from pathlib import Path

from PIL import Image

root = Path(sys.argv[1])
probes = json.loads((root / "attachment-probes.json").read_text())
failures = []
minimum_alpha = 255
bounds = [10000, 10000, 0, 0]
for entry in probes:
    with Image.open(root / "frames" / entry["frame"]) as image:
        alpha = image.getchannel("A")
        box = alpha.point(lambda x: 255 if x > 32 else 0).getbbox()
        if box:
            bounds = [min(bounds[0], box[0]), min(bounds[1], box[1]),
                      max(bounds[2], box[2]), max(bounds[3], box[3])]
            if box[0] < 5 or box[1] < 5 or box[2] > image.width-5 or box[3] > image.height-5:
                failures.append({"frame": entry["frame"], "clipped": box})
        for i, (px, py) in enumerate(entry["attachments"]):
            x, y = round(px), round(py)
            value = min(alpha.crop((x-1, y-1, x+2, y+2)).tobytes())
            minimum_alpha = min(minimum_alpha, value)
            if value < 192:
                failures.append({"frame": entry["frame"], "attachment": i, "alpha": value})
report = {"frames": len(probes), "attachment_samples": sum(len(p["attachments"]) for p in probes),
          "minimum_attachment_alpha": minimum_alpha, "opaque_bounds": bounds, "failures": failures}
(root / "pixel-audit.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({**report, "failures": failures[:10]}, indent=2))
sys.exit(bool(failures) or len(probes) != 1050)

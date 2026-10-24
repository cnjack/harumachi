"""Print short activity titles using the game's font for physical timber engraving."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "game/assets/fonts/LXGWWenKai-Medium.ttf"
OUTPUT = ROOT / "game/assets/textures/engraving"
TITLES = ["夏祭准备", "灯笼试挂", "夏祭入口", "树下集合", "树下晚会", "围坐聊天"]


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for title in TITLES:
        mask = Image.new("L", (1024, 256), 0)
        draw = ImageDraw.Draw(mask)
        size = 210
        while True:
            font = ImageFont.truetype(str(FONT), size)
            bounds = draw.textbbox((0, 0), title, font=font)
            if bounds[2] - bounds[0] <= 960 and bounds[3] - bounds[1] <= 210:
                break
            size -= 1
        draw.text(((1024 - bounds[2] + bounds[0]) / 2 - bounds[0],
                   (256 - bounds[3] + bounds[1]) / 2 - bounds[1]),
                  title, font=font, fill=255)
        target = OUTPUT / (hashlib.md5(title.encode()).hexdigest() + ".png")
        mask.convert("RGB").save(target)
        rows.append({"title": title, "mask": str(target.relative_to(ROOT)),
                     "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
    manifest = {"font": str(FONT.relative_to(ROOT)),
                "font_sha256": hashlib.sha256(FONT.read_bytes()).hexdigest(),
                "use": "Short titles engraved into both faces of MS14 activity boards; stored between activities.",
                "assets": rows}
    (ROOT / "art/manifests/plaza_signage_20261024.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Built {len(rows)} physical-sign text masks")


if __name__ == "__main__":
    main()

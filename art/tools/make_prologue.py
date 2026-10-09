"""v0.6 prologue (序章): anime panels drawn by codex, shown in the game as a slideshow (scripts/ui/prologue.gd).

    python3 art/tools/make_prologue.py

Inputs:  art/references/v06/prologue_anime/<img>.png (codex, prompts in art/manifests/prompts/v06/prologue_anime/;
         generated with the in-game portraits of 空 and 澪 attached as character references)
         game/data/prologue.json (panel order, 空's line for each panel, zoom / pan of the slow camera drift)
Output:  game/assets/ui/prologue/<img>.jpg, 1920x1080, cover-cropped.
空's lines are voiced like every other line: art/tools/voice/gen_voice_lines.py reads prologue.json too.

(Until v0.6's feedback round the prologue was a movie made with LTX-2.5 image-to-video; the user wanted it
anime-styled, so the movie and its tools were removed.)
"""
import json, os
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art", "references", "v06", "prologue_anime")
DST = os.path.join(ROOT, "game", "assets", "ui", "prologue")
W, H = 1920, 1080


def main():
    d = json.load(open(os.path.join(ROOT, "game", "data", "prologue.json")))
    os.makedirs(DST, exist_ok=True)
    keep = set()
    for p in d["panels"]:
        im = Image.open(os.path.join(SRC, p["img"] + ".png")).convert("RGB")
        s = max(W / im.width, H / im.height)
        im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
        x, y = (im.width - W) // 2, (im.height - H) // 2
        out = os.path.join(DST, p["img"] + ".jpg")
        im.crop((x, y, x + W, y + H)).save(out, quality=90)
        keep.add(p["img"] + ".jpg")
        print("panel", p["img"], "->", os.path.relpath(out, ROOT))
    for f in os.listdir(DST):
        base = f[:-7] if f.endswith(".import") else f
        if base not in keep:
            os.remove(os.path.join(DST, f))
            print("removed", f)


if __name__ == "__main__":
    main()

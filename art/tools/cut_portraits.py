"""Frame every dialogue portrait as a 512x512 transparent PNG.

    python3 art/tools/cut_portraits.py [--preview /tmp/p.jpg] [--sheets]

v0.7.3: the portraits are now drawn by codex one per image with a real transparent background
(art/references/v07/portraits/gen/<who>_<mood>.png, prompts in art/manifests/prompts/v07/portraits/).
They are used as generated; fit_alpha only trims the empty margin and scales to 512. Keying the cream sheet background out, below, punched
holes wherever clothing was close to the sheet colour (Kazuko's blouse, Aoi's overalls), so it is only
used with --sheets or for a character that has no transparent source yet.

Sheets (codex, cream background ~ RGB 244 239 229):
  art/references/characters/portraits_sheet.png   4x2: sora, mio, ren, haru; row 0 neutral, row 1 happy
  art/references/characters/portraits_farm.png    2x2: tanaka, aoi; row 0 neutral, row 1 happy
  art/references/v06/ui/pt_kazuko.png             2x1: kazuko neutral, happy
Output: game/assets/ui/portraits/<who>_<mood>.png, 512x512 RGBA, bust anchored to the bottom edge.

Earlier versions flood-filled from the border only, so cream pockets that the hair, arms or collar close off
(between an arm and the body, under a ponytail) stayed opaque and showed as white patches in the dialogue box.
Here the background is every pixel close to the sheet colour that is either connected to the border or a
large enough pocket; the edge band is un-premultiplied against the cream so no light fringe is left.
"""
import os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "game", "assets", "ui", "portraits")
SHEETS = [
    ("art/references/characters/portraits_sheet.png", 4, 2, ["sora", "mio", "ren", "haru"]),
    ("art/references/characters/portraits_farm.png", 2, 2, ["tanaka", "aoi"]),
    ("art/references/v06/ui/pt_kazuko.png", 2, 1, ["kazuko"]),
]


def cut(cell):
    a = np.asarray(cell.convert("RGB")).astype(np.float32)
    h, w, _ = a.shape
    edge = np.concatenate([a[:3].reshape(-1, 3), a[-3:].reshape(-1, 3), a[:, :3].reshape(-1, 3), a[:, -3:].reshape(-1, 3)])
    # the sheet colour: the most common light colour on the cell border (some cells have a tinted blob behind)
    light = edge[edge.min(1) > 200]
    bg = np.median(light if len(light) > 50 else edge, axis=0)
    d = np.linalg.norm(a - bg, axis=2)
    near = d < 24.0
    lab, n = ndimage.label(near)
    border_ids = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    sizes = ndimage.sum(near, lab, range(1, n + 1))
    # pockets: enclosed cream regions bigger than ~0.08 % of the cell (eye whites and highlights are much smaller)
    pocket = {i + 1 for i, s in enumerate(sizes) if s > 0.0008 * h * w}
    bgm = np.isin(lab, list(border_ids | pocket))
    fg = ~bgm
    # keep the character (largest piece) and anything attached to it; drop stray specks
    lab2, n2 = ndimage.label(fg)
    if n2 > 1:
        s2 = ndimage.sum(fg, lab2, range(1, n2 + 1))
        big = s2.max()
        fg = np.isin(lab2, [i + 1 for i, s in enumerate(s2) if s > 0.02 * big])
    fg = ndimage.binary_opening(fg, iterations=1)
    # soft alpha: 1 inside, ramps over ~1.5 px across the boundary, guided by the colour distance
    inside = ndimage.binary_erosion(fg, iterations=1)
    band = fg & ~inside
    alpha = fg.astype(np.float32)
    alpha[band] = np.clip(d[band] / 60.0, 0.35, 1.0)
    alpha = ndimage.gaussian_filter(alpha, 0.6) * ndimage.binary_dilation(fg, iterations=1)
    alpha[inside] = 1.0
    # un-premultiply the cream out of semi-transparent edge pixels
    al = np.clip(alpha, 1e-3, 1.0)[..., None]
    rgb = np.where(alpha[..., None] < 0.999, (a - bg * (1 - al)) / al, a)
    rgba = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha * 255, 0, 255)]).astype(np.uint8)
    im = Image.fromarray(rgba, "RGBA")
    ys, xs = np.where(alpha > 0.05)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    S = int(max(x1 - x0, y1 - y0) * 1.06)
    sq = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sq.paste(im.crop((x0, y0, x1, y1)), ((S - (x1 - x0)) // 2, S - (y1 - y0)))
    return sq.resize((512, 512), Image.LANCZOS)


GEN = "art/references/v07/portraits/gen"
WHO = ["sora", "mio", "ren", "haru", "tanaka", "aoi", "kazuko"]


def frame(im, alpha):
    ys, xs = np.where(alpha > 0.05)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    S = int(max(x1 - x0, y1 - y0) * 1.06)
    sq = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sq.paste(im.crop((x0, y0, x1, y1)), ((S - (x1 - x0)) // 2, S - (y1 - y0)))
    return sq.resize((512, 512), Image.LANCZOS)


def fit_alpha(im):
    """codex draws the portrait on a real transparent background: only trim and scale, alpha untouched."""
    im = im.convert("RGBA")
    return frame(im, np.asarray(im)[..., 3].astype(np.float32) / 255.0)


def main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    done = set()
    if "--sheets" not in sys.argv:
        for who in WHO:
            for mood in ("neutral", "happy"):
                src = os.path.join(ROOT, GEN, f"{who}_{mood}.png")
                if not os.path.exists(src):
                    continue
                out = os.path.join(OUT, f"{who}_{mood}.png")
                fit_alpha(Image.open(src)).save(out)
                made.append(out)
                done.add((who, mood))
    for path, cols, rows, who in SHEETS:
        sheet = Image.open(os.path.join(ROOT, path)).convert("RGB")
        cw, ch = sheet.width / cols, sheet.height / rows
        for r in range(rows):
            for c in range(cols):
                name = who[c] if len(who) == cols else who[0]
                mood = ["neutral", "happy"][r if rows == 2 else c]
                if (name, mood) in done:
                    continue
                cell = sheet.crop((int(c * cw), int(r * ch), int((c + 1) * cw), int((r + 1) * ch)))
                out = os.path.join(OUT, f"{name}_{mood}.png")
                cut(cell).save(out)
                made.append(out)
    print("portraits", len(made))
    if "--preview" in sys.argv:
        p = sys.argv[sys.argv.index("--preview") + 1]
        C = 220
        S = Image.new("RGB", (7 * C, 4 * C))
        for i, f in enumerate(sorted(made)):
            im = Image.open(f)
            for k, col in enumerate([(34, 52, 92), (250, 246, 236)]):
                bgi = Image.new("RGBA", im.size, col + (255,))
                S.paste(Image.alpha_composite(bgi, im).convert("RGB").resize((C, C)), ((i % 7) * C, (i // 7) * 2 * C + k * C))
        S.save(p, quality=88)


if __name__ == "__main__":
    main()

"""Cut the v0.6 codex sheets into game assets.

    <venv>/python art/tools/process_v06_2d.py

  badges_a/b.png (4x4)      -> game/assets/ui/badges/<achievement id>.png  (160 px, background removed)
  col_sheet_a/b.png (3x2)   -> game/assets/ui/collection/<keepsake id>.jpg (480 px cards)
  products.png (6x4)        -> game/assets/textures/products_atlas.png      (6x4 atlas on white, for shelf goods)
  pt_kazuko.png (2x1)       -> game/assets/ui/portraits/kazuko_{neutral,happy}.png (512 px, background removed)
  icons_v06.png (4x2)       -> game/assets/ui/icons/{washi,bamboo_strip,wood,book,keepsake_box,teruteru,chochin,photo}.png
  prologue/K*.png           -> game/assets/ui/prologue/K*.jpg (1600x900, the fallback stills for the opening)
"""
import json, os
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
REF = os.path.join(ROOT, "art", "references", "v06")
GAME = os.path.join(ROOT, "game")


def cut_grid(im, cols, rows):
    w, h = im.size
    for r in range(rows):
        for c in range(cols):
            yield r * cols + c, im.crop((round(c * w / cols), round(r * h / rows), round((c + 1) * w / cols), round((r + 1) * h / rows)))


def remove_bg(cell, tol=38, min_island=400):
    """Background = pixels close to the border colour and connected to the border."""
    a = np.asarray(cell.convert("RGB")).astype(float)
    h, w, _ = a.shape
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    ref = np.median(border, axis=0)
    close = np.linalg.norm(a - ref, axis=2) < tol
    lab, n = ndimage.label(close)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(edge))
    fg = ~bg
    # drop specks (stars on a dark sheet) and fill small holes
    lab2, n2 = ndimage.label(fg)
    if n2:
        sizes = ndimage.sum(fg, lab2, range(1, n2 + 1))
        keep = np.isin(lab2, [i + 1 for i, s in enumerate(sizes) if s >= min_island])
        fg = ndimage.binary_fill_holes(keep)
    alpha = ndimage.gaussian_filter(fg.astype(float), 0.8)
    rgba = np.dstack([a, np.clip(alpha * 255, 0, 255)]).astype(np.uint8)
    out = Image.fromarray(rgba, "RGBA")
    return out.crop(out.getbbox()) if out.getbbox() else out


def square(im, size):
    w, h = im.size
    s = max(w, h)
    c = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    c.paste(im, ((s - w) // 2, (s - h) // 2))
    return c.resize((size, size), Image.LANCZOS)


def main():
    ach = json.load(open(os.path.join(GAME, "data", "achievements.json")))["items"]
    col = json.load(open(os.path.join(GAME, "data", "collection.json")))["items"]
    bd = os.path.join(GAME, "assets", "ui", "badges"); os.makedirs(bd, exist_ok=True)
    for k, sheet in enumerate(("a", "b")):
        im = Image.open(os.path.join(REF, "ui", f"badges_{sheet}.png"))
        for i, cell in cut_grid(im, 4, 4):
            a = ach[k * 16 + i]
            square(remove_bg(cell, tol=60 if sheet == "a" else 30), 160).save(os.path.join(bd, a["id"] + ".png"))
    cd = os.path.join(GAME, "assets", "ui", "collection"); os.makedirs(cd, exist_ok=True)
    cells = {}
    for sheet in ("a", "b"):
        im = Image.open(os.path.join(REF, "ui", f"col_sheet_{sheet}.png")).convert("RGB")
        for i, cell in cut_grid(im, 3, 2):
            w, h = cell.size
            m = int(min(w, h) * 0.03)
            cells[(sheet, i)] = cell.crop((m, m, w - m, h - m))
    for c in col:
        if c["sheet"] == "":
            # the new group photo is taken in game; until then the card shows the festival memory keyframe
            k = Image.open(os.path.join(REF, "prologue", "K2_memory_festival.png")).convert("RGB")
            w, h = k.size
            img = k.crop(((w - h) // 2, 0, (w + h) // 2, h))
        else:
            img = cells[(c["sheet"], c["cell"])]
        img.resize((480, 480), Image.LANCZOS).save(os.path.join(cd, c["id"] + ".jpg"), quality=90)
    # shelf goods atlas: keep the 6x4 layout, square it, 1024 px
    pr = Image.open(os.path.join(REF, "ui", "products.png")).convert("RGB").resize((1536, 1024), Image.LANCZOS)
    pr.save(os.path.join(GAME, "assets", "textures", "products_atlas.png"))
    # Kazuko's portraits in the same 512 px transparent format as the others
    pt = Image.open(os.path.join(REF, "ui", "pt_kazuko.png"))
    for i, cell in cut_grid(pt, 2, 1):
        fg = remove_bg(cell, tol=26, min_island=2000)
        w, h = fg.size
        s = max(w, h)
        c = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        c.paste(fg, ((s - w) // 2, s - h))
        c.resize((512, 512), Image.LANCZOS).save(os.path.join(GAME, "assets", "ui", "portraits", ("kazuko_neutral", "kazuko_happy")[i] + ".png"))
    # item icons (4x2 on white) in the same 128 px transparent format as the v0.5 icons
    names = ["washi", "bamboo_strip", "wood", "book", "keepsake_box", "teruteru", "chochin", "photo"]
    icons = Image.open(os.path.join(REF, "ui", "icons_v06.png"))
    for i, cell in cut_grid(icons, 4, 2):
        square(remove_bg(cell, tol=24, min_island=300), 192).save(os.path.join(GAME, "assets", "ui", "icons", names[i] + ".png"))
    pd = os.path.join(GAME, "assets", "ui", "prologue"); os.makedirs(pd, exist_ok=True)
    for f in sorted(os.listdir(os.path.join(REF, "prologue"))):
        if f.endswith(".png"):
            Image.open(os.path.join(REF, "prologue", f)).convert("RGB").resize((1600, 900), Image.LANCZOS).save(
                os.path.join(pd, f.replace(".png", ".jpg")), quality=90)
    print("badges", len(ach), "keepsakes", len(col))


if __name__ == "__main__":
    main()

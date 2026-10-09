"""v0.4 2D assets: sky panoramas (seamless wrap), river backdrop card, farm icons, Tanaka/Aoi portraits.
python process_farm_2d.py   (run from the anime/ folder with PIL + numpy + scipy)"""
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

REF = "art/references"
OUT = "game/assets"


def seamless(im, band_frac=0.04):
    a = np.asarray(im).astype(np.float32)
    W = a.shape[1]; b = int(W * band_frac)
    out = a[:, :W - b].copy()
    t = (np.arange(b) / b)[None, :, None]
    out[:, :b] = a[:, :b] * t + a[:, W - b:] * (1 - t)
    return Image.fromarray(out.clip(0, 255).astype(np.uint8))


for name in ("sky_dusk", "sky_night"):
    im = Image.open(f"{REF}/world/{name}.png").convert("RGB")
    im = seamless(im).resize((4096, 2048), Image.LANCZOS)
    im.save(f"{OUT}/textures/{name}.jpg", quality=90)
    a = np.asarray(im.convert("L")).astype(np.float32)
    band = a[int(0.3 * 2048):int(0.5 * 2048)]
    print(name, "brightest column u=%.3f" % (band.mean(0).argmax() / 4096.0))

# river backdrop: keep the painted strip, cut to its alpha bounds
im = Image.open(f"{REF}/world/bg_river.png").convert("RGBA")
a = np.asarray(im)
alpha = a[:, :, 3]
if alpha.min() > 200:   # no alpha: key out the white sky
    rgb = a[:, :, :3].astype(int)
    alpha = np.where((rgb > 240).all(2), 0, 255).astype(np.uint8)
ys = np.where(alpha.max(1) > 128)[0]
card = Image.fromarray(np.dstack([a[:, :, :3], alpha]).astype(np.uint8)).crop((0, ys.min(), im.width, ys.max() + 1))
card.save(f"{OUT}/textures/bg/bg_river.png")
print("bg_river", card.size)


def clean_rgba(cell, size):
    a = np.asarray(cell.convert("RGBA")).astype(np.float32)
    al = a[:, :, 3]
    if al.min() > 200:   # white background -> flood from the border
        rgb = a[:, :, :3]
        white = (rgb > 238).all(2)
        lab, _ = ndimage.label(white)
        border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
        al = np.where(np.isin(lab, list(border)), 0, 255).astype(np.float32)
    hard = al > 120
    hard = ndimage.binary_opening(hard, iterations=1)
    lab, n = ndimage.label(hard)
    if n > 1:   # drop specks from neighbouring cells
        sizes = ndimage.sum(hard, lab, range(1, n + 1))
        keep = [i + 1 for i, s in enumerate(sizes) if s >= sizes.max() * 0.04]
        hard = np.isin(lab, keep)
    # pull colour from the interior into the soft edge so no fringe survives the resize
    rgb = a[:, :, :3]
    inner = ndimage.binary_erosion(hard, iterations=2)
    idx = ndimage.distance_transform_edt(~inner, return_distances=False, return_indices=True)
    rgb = rgb[idx[0], idx[1]]
    soft = ndimage.gaussian_filter(hard.astype(np.float32), 0.8) * 255
    img = Image.fromarray(np.dstack([rgb, soft]).clip(0, 255).astype(np.uint8))
    ys, xs = np.where(hard)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    img = img.crop(box)
    w, h = img.size
    S = int(max(w, h) * 1.12)
    sq = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sq.paste(img, ((S - w) // 2, (S - h) // 2))
    return sq.resize((size, size), Image.LANCZOS)


names = [["seed_radish", "seed_komatsuna", "seed_tomato", "seed_cucumber", "seed_sunflower"],
         ["crop_radish", "crop_komatsuna", "crop_tomato", "crop_cucumber", "crop_edamame"],
         ["crop_sunflower", "crop_strawberry", "hoe", "farm_can", "fertilizer"],
         ["weeds", "seed_edamame", "seed_strawberry", "letter", "hairclip"]]
sheet = Image.open(f"{REF}/ui/icons_farm.png")
cw, ch = sheet.width / 5, sheet.height / 4
for r, row in enumerate(names):
    for c, n in enumerate(row):
        cell = sheet.crop((int(c * cw), int(r * ch), int((c + 1) * cw), int((r + 1) * ch)))
        clean_rgba(cell, 192).save(f"{OUT}/ui/icons/{n}.png")
print("icons", sum(len(r) for r in names))

ps = Image.open(f"{REF}/characters/portraits_farm.png").convert("RGB")
pw, ph = ps.width / 2, ps.height / 2
for c, who in enumerate(["tanaka", "aoi"]):
    for r, mood in enumerate(["neutral", "happy"]):
        cell = ps.crop((int(c * pw), int(r * ph), int((c + 1) * pw), int((r + 1) * ph)))
        a = np.asarray(cell).astype(int)
        bg = np.median(np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]]), axis=0)
        near = (np.abs(a - bg).sum(2) < (14 if who == "aoi" else 30))
        lab, _ = ndimage.label(near)
        border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
        fg = ~np.isin(lab, list(border))
        fg = ndimage.binary_fill_holes(ndimage.binary_opening(fg, iterations=2))
        ys, xs = np.where(fg)
        soft = ndimage.gaussian_filter(fg.astype(np.float32), 1.0) * 255
        img = Image.fromarray(np.dstack([a, soft]).clip(0, 255).astype(np.uint8))
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        S = int(max(x1 - x0, y1 - y0) * 1.06)
        sq = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        sq.paste(img.crop((x0, y0, x1, y1)), ((S - (x1 - x0)) // 2, S - (y1 - y0)))
        sq.resize((512, 512), Image.LANCZOS).save(f"{OUT}/ui/portraits/{who}_{mood}.png")
print("portraits ok")

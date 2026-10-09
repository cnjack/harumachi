"""v0.5 2D assets: icon sheets -> 192 px icons, banners, the grass-tuft atlas and seamless ground textures.
python process_v05_2d.py  (from the anime/ folder; needs PIL, numpy, scipy)"""
import os, sys
import numpy as np
from PIL import Image
from scipy import ndimage
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
REF = "art/references/v05"
OUT = "game/assets"


def clean_rgba(cell, size, all_white=False):
    a = np.asarray(cell.convert("RGBA")).astype(np.float32)
    al = a[:, :, 3]
    rgb = a[:, :, :3]
    if al.min() > 200:
        white = (rgb > 236).all(2)
        lab, _ = ndimage.label(white)
        border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
        al = np.where(np.isin(lab, list(border)), 0, 255).astype(np.float32)
        if all_white:
            # plants: the white showing between blades is background too
            gaps = (rgb > 228).all(2) & ((rgb.max(2) - rgb.min(2)) < 16)
            al = np.where(gaps, 0, al)
    hard = (al > 120) if all_white else ndimage.binary_opening(al > 120, iterations=1)
    lab, n = ndimage.label(hard)
    if n > 1:
        sizes = ndimage.sum(hard, lab, range(1, n + 1))
        keep = [i + 1 for i, s in enumerate(sizes) if s >= sizes.max() * 0.04]
        hard = np.isin(lab, keep)
    inner = ndimage.binary_erosion(hard, iterations=2)
    if inner.sum() < 20:
        inner = hard
    idx = ndimage.distance_transform_edt(~inner, return_distances=False, return_indices=True)
    rgb = rgb[idx[0], idx[1]]
    soft = ndimage.gaussian_filter(hard.astype(np.float32), 0.8) * 255
    img = Image.fromarray(np.dstack([rgb, soft]).clip(0, 255).astype(np.uint8))
    ys, xs = np.where(hard)
    img = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    w, h = img.size
    S = int(max(w, h) * 1.12)
    sq = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sq.paste(img, ((S - w) // 2, (S - h) // 2))
    return sq.resize((size, size), Image.LANCZOS)


SHEETS = {
    "icons_crops2": [["seed_carrot", "seed_potato", "seed_eggplant", "seed_corn", "seed_pumpkin"],
                     ["seed_watermelon", "seed_wheat", "seed_onion", "crop_carrot", "crop_potato"],
                     ["crop_eggplant", "crop_corn", "crop_pumpkin", "crop_watermelon", "crop_wheat"],
                     ["crop_onion", "ing_flour", "ing_sugar", "ing_salt", "ing_soy_sauce"]],
    "icons_food": [["ing_miso", "ing_rice", "ing_milk", "ing_butter", "ing_egg"],
                   ["ing_curry_roux", "dish_salad", "dish_pickles", "dish_radish_nimono", "dish_miso_soup"],
                   ["dish_edamame_onigiri", "dish_strawberry_jam", "dish_pumpkin_nimono", "dish_korokke", "dish_corn_soup"],
                   ["dish_curry", "dish_nasu_dengaku", "dish_watermelon_slice", "dish_kinpira", "dish_tempura"]],
    "icons_bakery_b": [["bread_focaccia", "bread_corn", "bread_pumpkin", "cake_shortcake", "cake_carrot"],
                       ["bread_sunflower", "bread_sandwich", "bread_curry_pan", "cookie_box", "recipe_card"],
                       ["can_copper", "bag_upgrade", "storage_box", "fest_tanzaku", "fest_uchiwa"],
                       ["fest_toro", "fest_dango", "fest_ribbon", "fest_candy_apple", "fest_sparklers"]],
    "icons_ui2": [["w_sunny", "w_cloudy", "w_rain", "w_night", "w_festival"],
                  ["tab_all", "tab_seed", "tab_crop", "tab_dish", "tab_material"],
                  ["tab_key", "xp_star", "level_badge", "calendar", "recipe_book"],
                  ["st_pot", "st_oven", "coin_stack", "clock", "signpost"]],
}


def icons():
    n = 0
    for sheet, rows in SHEETS.items():
        path = f"{REF}/ui/{sheet}.png"
        if not os.path.exists(path):
            print("missing", path)
            continue
        im = Image.open(path)
        cw, ch = im.width / 5, im.height / 4
        for r, row in enumerate(rows):
            for c, name in enumerate(row):
                cell = im.crop((int(c * cw), int(r * ch), int((c + 1) * cw), int((r + 1) * ch)))
                clean_rgba(cell, 192).save(f"{OUT}/ui/icons/{name}.png")
                n += 1
    # the gold can is the copper one re-tinted
    cu = f"{OUT}/ui/icons/can_copper.png"
    if os.path.exists(cu):
        a = np.asarray(Image.open(cu).convert("RGBA")).astype(np.float32)
        lum = a[:, :, :3].mean(2, keepdims=True)
        gold = np.concatenate([lum * 1.25 + 40, lum * 1.05 + 20, lum * 0.45], 2)
        Image.fromarray(np.dstack([gold, a[:, :, 3]]).clip(0, 255).astype(np.uint8)).save(f"{OUT}/ui/icons/can_gold.png")
    print("icons", n)


def banners():
    for f in sorted(os.listdir(f"{REF}/ui")):
        if not (f.startswith("ban_") and f.endswith(".png")):
            continue
        im = Image.open(f"{REF}/ui/{f}").convert("RGB")
        w, h = im.size
        band = h / 3.0
        im = im.crop((0, int(h / 2 - band / 2 - band * 0.05), w, int(h / 2 + band / 2 - band * 0.05)))
        im.resize((1200, 400), Image.LANCZOS).save(f"{OUT}/ui/banners/{f[:-4]}.jpg", quality=88)
    print("banners ok")


def tufts():
    im = Image.open(f"{REF}/tex/tufts.png").convert("RGB")
    cw, ch = im.width / 4, im.height / 2
    C = 256
    atlas = Image.new("RGBA", (C * 4, C * 2), (0, 0, 0, 0))
    for r in range(2):
        for c in range(4):
            cell = im.crop((int(c * cw), int(r * ch), int((c + 1) * cw), int((r + 1) * ch)))
            t = clean_rgba(cell, 512, all_white=True)
            a = np.asarray(t)
            ys, xs = np.where(a[:, :, 3] > 40)
            t = t.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
            w, h = t.size
            k = min((C - 8) / w, (C - 4) / h)
            t = t.resize((max(1, int(w * k)), max(1, int(h * k))), Image.LANCZOS)
            atlas.alpha_composite(t, (c * C + (C - t.width) // 2, r * C + C - t.height))
    atlas.save(f"{OUT}/textures/tufts_atlas.png")
    print("tufts atlas", atlas.size)


def seamless(im):
    a = np.asarray(im.convert("RGB")).astype(np.float32)
    H, W = a.shape[:2]
    sh = np.roll(np.roll(a, H // 2, 0), W // 2, 1)
    y = np.minimum(np.arange(H), H - 1 - np.arange(H)) / (H / 2)
    x = np.minimum(np.arange(W), W - 1 - np.arange(W)) / (W / 2)
    w = np.clip(np.minimum.outer(y, x) * 2.2, 0, 1)
    w = (w * w * (3 - 2 * w))[:, :, None]
    return Image.fromarray((a * w + sh * (1 - w)).clip(0, 255).astype(np.uint8))


def textures():
    for src, dst in (("tex_meadow", "meadow"), ("tex_grass_dark", "grass_dark"), ("tex_dirt", "dirt")):
        im = seamless(Image.open(f"{REF}/tex/{src}.png"))
        im.resize((1024, 1024), Image.LANCZOS).save(f"{OUT}/textures/{dst}.jpg", quality=90)
    print("textures ok")


if __name__ == "__main__":
    icons()
    banners()
    tufts()
    textures()

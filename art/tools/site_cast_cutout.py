"""Clean cutout of the website cast lineup (art/references/site/cast.png -> site/assets/cast.{webp,png}).

The codex original already has an alpha channel, but its "opaque" level is ~252, it carries
thousands of alpha 1-6 specks, the sky blob has a 1-2 px light rim, and the lower edge of the
blob (where the sky fades to white near the ground) is ragged. This script:

1. drops specks and small detached islands, and rescales alpha so the body is fully opaque;
2. smooths the alpha only along sky edges (pixels far from any dark line art), so hair,
   fingers and outlines keep their original edges;
3. replaces the colour of semi-transparent edge pixels with the colour a few pixels inside
   (edge extension), which removes the light rim / white halo;
4. writes a lossy WebP with alpha and a palette PNG fallback.

usage: python art/tools/site_cast_cutout.py [--preview DIR]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "art/references/site/cast.png"
OUT_WEBP = ROOT / "site/assets/cast.webp"
OUT_PNG = ROOT / "site/assets/cast.png"


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def main():
    preview = None
    if "--preview" in sys.argv:
        preview = Path(sys.argv[sys.argv.index("--preview") + 1])
        preview.mkdir(parents=True, exist_ok=True)

    rgba = np.asarray(Image.open(SRC).convert("RGBA")).astype(np.float32)
    rgb = rgba[..., :3]
    a = rgba[..., 3]

    # 1. alpha levels + specks
    a = np.clip((a - 10.0) / (246.0 - 10.0), 0.0, 1.0)
    solid = a > 0.5
    labels, n = ndi.label(solid)
    sizes = ndi.sum(solid, labels, range(1, n + 1))
    keep = np.zeros(n + 1, bool)
    keep[1:] = sizes > 400
    island = keep[labels]
    near = ndi.binary_dilation(island, iterations=3)
    a = np.where(near, a, 0.0)

    # 2. sky edges vs line-art edges
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    dark = (lum < 150) & (a > 0.3)
    dist_dark = ndi.distance_transform_edt(~dark)
    sky_w = smoothstep(5.0, 10.0, dist_dark)  # 0 near line art, 1 in open sky
    blurred = ndi.gaussian_filter(a, 2.2)
    a_sky = smoothstep(0.38, 0.62, blurred)
    a = a * (1 - sky_w) + a_sky * sky_w

    # 3. edge extension: colour of edge pixels comes from the solid interior
    core = ndi.binary_erosion(a > 0.97, iterations=3)
    _, (iy, ix) = ndi.distance_transform_edt(~core, return_indices=True)
    inner = rgb[iy, ix]
    edge = (a > 0) & ~core
    inner_lum = lum[iy, ix]
    # only replace pixels that are lighter than the interior (light rim / halo); keep dark outlines
    lighter = lum > inner_lum + 4
    w = np.where(edge & (lighter | (sky_w > 0.5)), 1.0, 0.0)[..., None]
    rgb = rgb * (1 - w) + inner * w
    # fully transparent pixels get the nearest colour too (better WebP edges, no black bleed)
    solid2 = a > 0.02
    _, (jy, jx) = ndi.distance_transform_edt(~solid2, return_indices=True)
    rgb = np.where(solid2[..., None], rgb, rgb[jy, jx])

    out = np.dstack([np.clip(rgb, 0, 255), np.clip(a * 255.0, 0, 255)]).round().astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    img.save(OUT_WEBP, "WEBP", quality=86, alpha_quality=100, method=6)
    pal = img.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
    pal.save(OUT_PNG, optimize=True)
    print(OUT_WEBP, OUT_WEBP.stat().st_size, OUT_PNG, OUT_PNG.stat().st_size)

    if preview:
        for name, bg in {"cream": (246, 239, 224), "purple": (110, 40, 150), "black": (0, 0, 0)}.items():
            base = Image.new("RGBA", img.size, bg + (255,))
            comp = Image.alpha_composite(base, Image.open(OUT_WEBP).convert("RGBA")).convert("RGB")
            comp.save(preview / f"cast_new_{name}.png")
            for i, (x, y, w_, h_) in enumerate([(940, 560, 360, 200), (440, 540, 360, 200), (1380, 280, 260, 360),
                                                (150, 200, 260, 260), (400, 0, 300, 160), (820, 0, 300, 160),
                                                (250, 740, 700, 140), (950, 740, 650, 140)]):
                comp.crop((x, y, x + w_, y + h_)).resize((w_ * 3, h_ * 3), Image.LANCZOS).save(
                    preview / f"cast_new_{name}_crop{i}.png")


if __name__ == "__main__":
    main()

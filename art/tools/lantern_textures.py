"""Paint the washi textures for the procedural lanterns (P_chochin_*, P_toro).

    <venv>/python art/tools/lantern_textures.py

Writes art/references/v06/lanterns/*.png (cylindrical unwraps for the chochin: u = around, v = height;
square panels for the tōrō). Brush lettering uses the OFL-licensed LXGW WenKai the game already ships.
"""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "art", "references", "v06", "lanterns")
FONT = os.path.join(ROOT, "game", "assets", "fonts", "LXGWWenKai-Medium.ttf")
os.makedirs(OUT, exist_ok=True)
RIBS = 22
rng = np.random.default_rng(7)


def washi(w, h, base, fiber=0.06, mottling=0.05):
    """Paper: base colour, soft mottling and short fibres."""
    a = np.ones((h, w, 3)) * np.array(base, float)[None, None, :] / 255.0
    low = Image.fromarray((rng.random((h // 32, w // 32)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    a *= 1.0 + (np.asarray(low) / 255.0 - 0.5)[..., None] * mottling * 2
    im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im, "RGBA")
    for _ in range(int(w * h / 900)):
        x, y = rng.random() * w, rng.random() * h
        ang = rng.random() * math.pi
        L = rng.random() * 14 + 4
        c = 255 if rng.random() < 0.5 else 0
        d.line([(x, y), (x + math.cos(ang) * L, y + math.sin(ang) * L)], fill=(c, c, c, int(255 * fiber)), width=1)
    return im


def ribs(im, dark=(0, 0, 0, 70), top=0.06, bottom=0.06):
    """Horizontal rib shadows (the bamboo rings under the paper) and darker ends."""
    w, h = im.size
    d = ImageDraw.Draw(im, "RGBA")
    for k in range(RIBS + 1):
        y = int(h * (top + (1 - top - bottom) * k / RIBS))
        d.line([(0, y), (w, y)], fill=dark, width=3)
        d.line([(0, y + 3), (w, y + 3)], fill=(255, 255, 255, 25), width=2)
    # the paper darkens towards the rims
    g = np.linspace(0, 1, h)
    shade = 1.0 - 0.28 * (np.clip(1 - g / 0.16, 0, 1) ** 1.5 + np.clip((g - 0.84) / 0.16, 0, 1) ** 1.5)
    a = np.asarray(im).astype(float) * shade[:, None, None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def brush(im, text, cx, cy, size, fill, vertical=True, stroke=3, blur=0.6):
    """Brush lettering: thick strokes with a slightly bled edge, like ink on washi."""
    w, h = im.size
    layer = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(layer)
    f = ImageFont.truetype(FONT, size)
    chars = list(text) if vertical else [text]
    step = size * 1.02
    y0 = cy - step * (len(chars) - 1) / 2
    for i, ch in enumerate(chars):
        d.text((cx, y0 + i * step), ch, font=f, fill=255, anchor="mm", stroke_width=stroke, stroke_fill=255)
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    ink = Image.new("RGB", (w, h), fill)
    im.paste(ink, (0, 0), layer)
    return im


def crest(im, cx, cy, r, col, ch, ch_col):
    d = ImageDraw.Draw(im)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    return brush(im, ch, cx, cy, int(r * 1.3), ch_col, stroke=1, blur=0.4)


def bands(im, col, top=0.0, h1=0.055):
    d = ImageDraw.Draw(im)
    w, h = im.size
    d.rectangle([0, 0, w, int(h * h1)], fill=col)
    d.rectangle([0, int(h * (1 - h1)), w, h], fill=col)
    return im


def kikyo(d, cx, cy, r, col, centre):
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = r if k % 2 == 0 else r * 0.48
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=col)
    d.ellipse([cx - r * 0.16, cy - r * 0.16, cx + r * 0.16, cy + r * 0.16], fill=centre)


W, H = 1024, 512
# red festival chochin: 祭 on the front and back, 晴町 small at the sides
im = washi(W, H, (214, 58, 43))
im = ribs(im, dark=(60, 0, 0, 80))
for u in (0.25, 0.75):
    im = brush(im, "祭", int(W * u), H // 2, 250, (22, 16, 14), stroke=4)
for u in (0.0, 0.5, 1.0):
    im = brush(im, "晴町", int(W * u), H // 2, 64, (22, 16, 14), stroke=1)
im.save(f"{OUT}/chochin_red.png")
# white chochin with a red sun crest bearing 晴, red bands top and bottom
im = washi(W, H, (246, 238, 220))
im = ribs(im, dark=(120, 90, 60, 55))
for u in (0.25, 0.75):
    im = crest(im, int(W * u), int(H * 0.47), 118, (205, 52, 40), "晴", (250, 244, 232))
im = bands(im, (190, 45, 36))
im.save(f"{OUT}/chochin_white.png")
# obon lantern: pale paper, blue kikyō bellflowers and grass strokes
im = washi(W, H, (240, 242, 238), fiber=0.04)
d = ImageDraw.Draw(im, "RGBA")
for _ in range(38):
    x, y = rng.random() * W, H * (0.25 + rng.random() * 0.62)
    for s in range(3):
        a = -math.pi / 2 + (rng.random() - 0.5) * 0.9
        L = 40 + rng.random() * 70
        d.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], fill=(70, 120, 90, 150), width=3)
for _ in range(26):
    x, y = rng.random() * W, H * (0.2 + rng.random() * 0.55)
    kikyo(d, x, y, 22 + rng.random() * 12, (72, 88, 180, 235), (235, 225, 150, 255))
im = ribs(im, dark=(60, 70, 110, 45))
im = bands(im, (40, 44, 70), h1=0.04)
im.save(f"{OUT}/chochin_bon.png")
# tōrō panels (256 px squares in a 1024x256 strip): 祈, a lotus, 想, and a sun crest
P = 256
strip = Image.new("RGB", (P * 4, P))
for k in range(4):
    pan = washi(P, P, (248, 240, 222), fiber=0.05)
    dd = ImageDraw.Draw(pan, "RGBA")
    if k == 0:
        pan = brush(pan, "祈", P // 2, P // 2, 170, (40, 30, 26), stroke=3)
    elif k == 1:
        for j in range(7):
            a = math.pi + j * math.pi / 6
            cx, cy = P / 2 + math.cos(a) * 34, P * 0.62 + math.sin(a) * 34
            dd.ellipse([cx - 22, cy - 46, cx + 22, cy + 10], fill=(232, 130, 150, 200), outline=(170, 70, 90, 220), width=2)
        dd.ellipse([P / 2 - 24, P * 0.55 - 24, P / 2 + 24, P * 0.55 + 12], fill=(245, 170, 180, 230))
        dd.arc([P * 0.2, P * 0.7, P * 0.8, P * 0.95], 190, 350, fill=(70, 120, 80, 230), width=5)
    elif k == 2:
        pan = brush(pan, "想", P // 2, P // 2, 170, (40, 30, 26), stroke=3)
    else:
        pan = crest(pan, P // 2, P // 2, 62, (205, 52, 40), "晴", (250, 244, 232))
    # the thin frame shadow at the panel edges
    dd = ImageDraw.Draw(pan, "RGBA")
    dd.rectangle([0, 0, P - 1, P - 1], outline=(90, 60, 40, 90), width=6)
    strip.paste(pan, (k * P, 0))
strip.save(f"{OUT}/toro_panels.png")
print("lantern textures in", OUT)

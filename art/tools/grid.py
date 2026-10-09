import sys
from PIL import Image, ImageDraw
out = sys.argv[1]; files = sys.argv[2:]
ims = [Image.open(f) for f in files]
w, h = ims[0].size
g = Image.new("RGB", (w*len(ims), h+18), (30,30,30)); d = ImageDraw.Draw(g)
labs = ["-Y", "+X", "+Y", "-X", "top"]
for i, im in enumerate(ims):
    g.paste(im.convert("RGB"), (i*w, 18)); d.text((i*w+4, 3), labs[i], fill=(255,255,0))
g.save(out)

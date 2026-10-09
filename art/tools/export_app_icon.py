"""Format a selected imagegen app icon for Godot and macOS; no creative image edits.
Python export_app_icon.py <selected-square-PNG>
"""
from pathlib import Path
import json
import subprocess
import sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
SOURCE=Path(sys.argv[1]).resolve()
OUT=ROOT/'art/references/app_icon/harumachi.iconset'
OUT.mkdir(parents=True,exist_ok=True)
image=Image.open(SOURCE).convert('RGBA')
assert image.width==image.height,'Icon must be square; do not distort or crop the selected design.'
for size in [16,32,128,256,512]:
    for scale in [1,2]:
        pixels=size*scale
        name=f'icon_{size}x{size}'+('@2x' if scale==2 else '')+'.png'
        image.resize((pixels,pixels),Image.Resampling.LANCZOS).save(OUT/name)
image.resize((1024,1024),Image.Resampling.LANCZOS).save(ROOT/'game/icon.png')
subprocess.run(['iconutil','-c','icns','-o',str(ROOT/'game/harumachi.icns'),str(OUT)],check=True)
report={'source':str(SOURCE),'png':'game/icon.png','icns':'game/harumachi.icns','source_size':[image.width,image.height],
        'alpha_extrema':image.getchannel('A').getextrema(),'sizes':[16,32,64,128,256,512,1024]}
(ROOT/'evidence/app_icon_20261001/icon-formats.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))

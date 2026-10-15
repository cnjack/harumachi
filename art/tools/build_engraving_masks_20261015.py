"""Render the game's handwritten font as portable, unlettered-model engraving masks."""
from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'game/assets/textures/engraving';OUT.mkdir(parents=True,exist_ok=True)
FONT=ROOT/'game/assets/fonts/LXGWWenKai-Medium.ttf'
TEXTS=['晴町','商店街','住宅支巷','河边农园','公交站','菜地 · 温室','回晴町','河边 · 木桥','镜波湖','沿河步道','钓鱼 · 木桥','晴町 市民农园','晴町 小集市','小份试作','焼菓子','焼きたて','米粮','茶と調味料']
rows=[]
for text in TEXTS:
 key=hashlib.md5(text.encode()).hexdigest();im=Image.new('L',(1024,256),0);draw=ImageDraw.Draw(im)
 size=180
 while True:
  font=ImageFont.truetype(str(FONT),size);b=draw.textbbox((0,0),text,font=font)
  if b[2]-b[0]<=960 and b[3]-b[1]<=210:break
  size-=1
 draw.text(((1024-(b[2]-b[0]))/2-b[0],(256-(b[3]-b[1]))/2-b[1]),text,font=font,fill=255)
 im.convert('RGB').save(OUT/(key+'.png'))
 rows.append(dict(text=text,mask=str((OUT/(key+'.png')).relative_to(ROOT)),sha256=hashlib.sha256((OUT/(key+'.png')).read_bytes()).hexdigest()))
(ROOT/'art/manifests/engraving_masks_20261015.json').write_text(json.dumps(dict(font='game/assets/fonts/LXGWWenKai-Medium.ttf',font_sha256=hashlib.sha256(FONT.read_bytes()).hexdigest(),style='WenKai hand lettering projected into actual timber; dark recessed fibres, bevel edge and local normal response',assets=rows),ensure_ascii=False,indent=2)+'\n')
print('ENGRAVING_MASKS',len(rows))

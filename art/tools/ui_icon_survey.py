"""Measure alpha bounds for AtlasTexture regions without editing generated PNGs."""
import json,hashlib
from pathlib import Path
from PIL import Image
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
folder=ROOT/'game/assets/ui/refresh_20261003'
sheets=[('navigation_atlas.png',4,4,['home','store','bakery','florist','post','hall','farm','fish','tree','exit','quest','book','backpack','calendar','map','coin'],[0,346,638,922,1280]),('weather_atlas.png',4,2,['w_sunny','w_night','w_cloudy','w_rain','w_festival','level_badge','support_token','compass'],None)]
regions={};reports=[]
for name,cols,rows,ids,guides in sheets:
    with Image.open(folder/name) as image:
        alpha=np.asarray(image.getchannel('A'));w,h=image.size
    ys=[round(v*h/guides[-1]) for v in guides] if guides else [round(i*h/rows) for i in range(rows+1)]
    for i,key in enumerate(ids):
        row,col=divmod(i,cols);left,right=round(col*w/cols),round((col+1)*w/cols);top,bottom=ys[row:row+2]
        y,x=np.where(alpha[top:bottom,left:right]>12)
        assert len(x)>100,key
        box=[int(left+x.min()),int(top+y.min()),int(x.max()-x.min()+1),int(y.max()-y.min()+1)]
        regions[key]={'sheet':name,'rect':box}
    reports.append({'file':name,'size':[w,h],'transparent_fraction':float(np.mean(alpha==0)),'sha256':hashlib.sha256((folder/name).read_bytes()).hexdigest()})
(folder/'regions.json').write_text(json.dumps(regions,indent=2)+'\n')
lines=['class_name UIIcons','extends RefCounted','## Original imagegen alpha is retained; regions only select each illustrated icon.','const REGIONS := {']
for key,value in regions.items():lines.append('\t"%s": ["%s", Rect2(%s)],'%(key,value['sheet'],','.join(map(str,value['rect']))))
lines.extend(['}','const ALIASES := {"tab_all":"backpack","tab_seed":"level_badge","tab_crop":"farm","tab_dish":"bakery","tab_material":"store","tab_key":"post"}','static var _cache: Dictionary = {}','','static func texture(id: String) -> Texture2D:', '\tvar key: String=ALIASES.get(id,id)','\tif not REGIONS.has(key):return null','\tif _cache.has(key):return _cache[key]','\tvar spec: Array=REGIONS[key]','\tvar icon:=AtlasTexture.new()','\ticon.atlas=load("res://assets/ui/refresh_20261003/"+str(spec[0]))','\ticon.region=spec[1]','\ticon.filter_clip=true','\t_cache[key]=icon','\treturn icon',''])
(ROOT/'game/scripts/ui/ui_icons.gd').write_text('\n'.join(lines))
(ROOT/'evidence/ui_map_20261003/icon-survey.json').write_text(json.dumps({'sheets':reports,'regions':regions},indent=2)+'\n')
print('ICONS',len(regions),reports)

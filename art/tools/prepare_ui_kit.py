"""Prepare the canonical source catalog; PNG pixels are never edited here."""
import json,hashlib
from pathlib import Path
from PIL import Image
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
KIT=ROOT/'game/ui_kit';ASSETS=KIT/'assets'
regions=json.loads((ROOT/'game/assets/ui/refresh_20261003/regions.json').read_text())
catalog={key:{**value,'category':'icon'} for key,value in regions.items()}
sheets=[('buttons_atlas.png',4,2,['primary_normal','primary_hover','primary_pressed','primary_disabled','secondary_normal','secondary_hover','secondary_pressed','secondary_disabled'],'control'),('controls_atlas.png',4,2,['slot_normal','slot_selected','slot_disabled','slot_empty','progress_track','progress_fill','notice_info','notice_warning'],'control'),('utility_atlas.png',4,2,['settings','close','back','check','gift','fishing_rod','heart','filter'],'icon')]
for filename,cols,rows,ids,category in sheets:
    with Image.open(ASSETS/filename) as image:alpha=np.asarray(image.getchannel('A'));w,h=image.size
    for index,key in enumerate(ids):
        row,col=divmod(index,cols);x0,x1=round(col*w/cols),round((col+1)*w/cols);y0,y1=round(row*h/rows),round((row+1)*h/rows)
        ys,xs=np.where(alpha[y0:y1,x0:x1]>32);assert len(xs)>100,key
        left=max(x0,x0+int(xs.min())-3);top=max(y0,y0+int(ys.min())-3);right=min(x1,x0+int(xs.max())+4);bottom=min(y1,y0+int(ys.max())+4)
        catalog[key]={'sheet':filename,'rect':[left,top,right-left,bottom-top],'category':category}
catalog.update(modal_paper={'sheet':'modal_paper.png','rect':[74,90,1106,1072],'category':'surface'},hud_paper={'sheet':'hud_paper.png','rect':[21,106,2129,505],'category':'surface'},minimap_ring={'sheet':'minimap_ring.png','rect':None,'category':'overlay'})
catalog['camera']={'sheet':'controls/camera.svg','rect':[0,0,64,64],'category':'icon'}
report={'version':'1.0.0','name':'晴町和纸 UI','assets':catalog,'source_images':[]}
for file in sorted(ASSETS.glob('*.png')):
    with Image.open(file) as image:alpha=np.asarray(image.getchannel('A'));size=list(image.size)
    report['source_images'].append({'file':file.name,'size':size,'transparent_fraction':float((alpha==0).mean()),'sha256':hashlib.sha256(file.read_bytes()).hexdigest()})
(KIT/'catalog.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
lines=['class_name UIKitCatalog','extends RefCounted','## Generated metadata from source PNG alpha; regenerate with prepare_ui_kit.py.','const VERSION := "1.0.0"','const ENTRIES := {']
for key,value in catalog.items():
    rect='Rect2i(%s)'%','.join(map(str,value['rect'])) if value['rect'] else 'Rect2i()'
    lines.append('\t"%s": ["%s", %s, "%s"],'%(key,value['sheet'],rect,value['category']))
lines+=['}','']
(KIT/'catalog.gd').write_text('\n'.join(lines))
out=ROOT/'evidence/ui_kit_20261003';out.mkdir(exist_ok=True)
(out/'asset-survey.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('UI_KIT',len(catalog),'entries;',len(report['source_images']),'source PNGs')

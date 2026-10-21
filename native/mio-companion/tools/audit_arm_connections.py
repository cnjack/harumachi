"""Measure actual Core attachments and rendered opaque bands for every frame.

This does not establish aesthetic quality of exterior outlines/folds. Inspect
review_motion.py's full shoulder/elbow/wrist contact sheets as well.
"""
import argparse
import json
import math
from pathlib import Path
from PIL import Image

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory',type=Path)
args=parser.parse_args();root=args.directory
data=json.loads((root/'review-frames.json').read_text())
failures=[];gap_max=0.;gap_worst=None;alpha_min=255;alpha_worst=None;tested=0;groups={}
for record in data['records']:
    group=groups.setdefault(record['group'],{'frames':0,'min_alpha':255,'max_attachment_gap':0.})
    group['frames']+=1
    for joint,gap in record.get('attachmentGaps',{}).items():
        group['max_attachment_gap']=max(group['max_attachment_gap'],gap)
        if gap>gap_max:gap_max=gap;gap_worst={'frame':record['frame'],'joint':joint,'gap':gap}
        if gap>0.15:failures.append({'frame':record['frame'],'joint':joint,'gap':gap})
    with Image.open(root/record['frame']) as picture:
        alpha=picture.getchannel('A')
        for side in ['left','right']:
            centres=record['centers'];s=centres['shoulder_'+side];e=centres['elbow_'+side];w=centres['wrist_'+side]
            for joint in ['shoulder','elbow','sleeve_cuff','wrist']:
                centre=centres[joint+'_'+side]
                dx,dy=(e[0]-s[0],e[1]-s[1]) if joint=='shoulder' else (w[0]-e[0],w[1]-e[1])
                length=math.hypot(dx,dy);dx/=length;dy/=length
                width=6 if joint in ['shoulder','elbow'] else (4 if joint=='sleeve_cuff' else 3)
                for along in [-2,0,2]:
                    for across in [-width,-width/2,0,width/2,width]:
                        x=round(centre[0]+dx*along-dy*across);y=round(centre[1]+dy*along+dx*across)
                        value=alpha.getpixel((x,y)) if 0<=x<alpha.width and 0<=y<alpha.height else 0
                        tested+=1;group['min_alpha']=min(group['min_alpha'],value)
                        if value<alpha_min:alpha_min=value;alpha_worst={'frame':record['frame'],'joint':joint+'_'+side,'pixel':[x,y],'alpha':value}
                        if value<250:failures.append({'frame':record['frame'],'joint':joint+'_'+side,'pixel':[x,y],'alpha':value})
report={'frames':len(data['records']),'band_pixels':tested,'minimum_band_alpha':alpha_min,'alpha_threshold':250,'worst_alpha':alpha_worst,'maximum_attachment_gap_px':gap_max,'gap_threshold_px':0.15,'worst_gap':gap_worst,'groups':groups,'failures':failures,'scope':'Actual MOC vertex anchors and 15 pixels across each inner joint band. Exterior folds/outlines require contact-sheet review.'}
(root/'arm-connections.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({**report,'failures':failures[:12]},indent=2))
raise SystemExit(bool(failures) or len(data['records'])<6000)

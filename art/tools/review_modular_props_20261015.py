"""Inspect actual Hyper3D source meshes; never generates or edits game assets."""
from pathlib import Path
import argparse,json,subprocess,hashlib
from concurrent.futures import ThreadPoolExecutor
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'evidence/modular_props_20261015'
VIEWS=['front','back','left','right','oblique','clay_front','clay_oblique']
def main():
 p=argparse.ArgumentParser();p.add_argument('--ids',required=True);p.add_argument('--candidate',default='a',choices=['a','b']);p.add_argument('--stage',default='source',choices=['source','ready','assembled']);p.add_argument('--blender',default='/Applications/Blender.app/Contents/MacOS/Blender');a=p.parse_args()
 scope={r['id']:r for r in json.loads((ROOT/'art/manifests/modular_props_20261015.json').read_text())['assets']}
 for aid,h in {'P_cafe_table':.89,'P_community_table':.89,'P_reading_chair':.89,'I04_shop_counter':1.22,'I05_bread_shelf':1.51,'W17_display_shelf':1.25,'I02_cake_showcase':1.149,'P_coffee_station':1.325,'A12_bench':.83,'J03_dining_set':.89,'J07_kotatsu':.446,'P_low_bookcase':1.09,'P_gondola':1.6}.items():scope[aid]={'nominal_size_m_xyz':[0,h,0]}
 ids=a.ids.split(',');assert len(ids)==len(set(ids)) and all(i in scope for i in ids)
 def render(aid):
  raw_root=ROOT/'art/models/raw/modular_props_20261015'
  source=raw_root/aid/a.candidate/'model.glb' if a.stage=='source' else raw_root/a.stage/(aid+'.glb')
  if a.stage=='source' and not source.exists():source=ROOT/scope[aid]['source_glb']
  folder=OUT/(a.stage+'-review')/aid/a.candidate;folder.mkdir(parents=True,exist_ok=True);sha=hashlib.sha256(source.read_bytes()).hexdigest()
  report=folder/'review.json'
  if not (report.exists() and json.loads(report.read_text())['sha256']==sha and all((folder/(v+'.png')).exists() for v in VIEWS)):
   with (folder/'render.log').open('w') as log:
    done=subprocess.run([a.blender,'-b','--factory-startup','--disable-autoexec','--python-exit-code','1','-P',str(ROOT/'art/tools/render_diversity_review.py'),'--',str(source),str(folder),str(scope[aid]['nominal_size_m_xyz'][1])],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=240)
   assert done.returncode==0,(aid,done.returncode)
  sheet=Image.new('RGB',(2100,325),'white');draw=ImageDraw.Draw(sheet)
  for index,view in enumerate(VIEWS):
   im=Image.open(folder/(view+'.png')).convert('RGB');im.thumbnail((300,300));sheet.paste(im,(index*300,0));draw.text((index*300+4,304),aid+' '+view,fill='black')
  sheet.save(folder/'contact.jpg',quality=94);print('RENDERED',aid,flush=True)
 with ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(render,ids))
if __name__=='__main__':main()

"""Record provenance from saved private Pixal jobs; never queries or stores auth."""
import json,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=json.loads((ROOT/'art/models/game_assets.json').read_text())['assets']
jobs=[]
for folder in sorted((ROOT/'art/models/raw').glob('*_pixal_*_20261003')):
    submitted=folder/'submission.json';raw=folder/'model.glb'
    if not submitted.exists() or not raw.exists():continue
    aid=folder.name.split('_pixal_')[0]
    retry='retry' in folder.name
    ref=ROOT/('art/references/windows3d_20261003' if 'windows' in folder.name else 'art/references/window_modules_20261003')/(aid+('_retry' if retry else '')+'.png')
    selected=spec.get(aid,{}).get('src')==str(raw.relative_to(ROOT/'art/models'))
    entry={'id':aid,'job_id':json.loads(submitted.read_text())['job_id'],'status':'completed and downloaded','reference':str(ref.relative_to(ROOT)),'reference_sha256':hashlib.sha256(ref.read_bytes()).hexdigest(),'raw_file':str(raw.relative_to(ROOT)),'raw_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),'raw_bytes':raw.stat().st_size,'resolution':1024,'seed':77 if retry else 42,'selected':selected}
    if selected:
        exported=ROOT/f'game/assets/models/{aid}.glb'
        entry.update(export_file=str(exported.relative_to(ROOT)),export_sha256=hashlib.sha256(exported.read_bytes()).hexdigest(),configuration=spec[aid],export_stats=json.loads((exported.parent/'_stats'/f'{aid}.json').read_text()))
    jobs.append(entry)
out=ROOT/'art/manifests/models_pixal_windows_20261003.json'
out.write_text(json.dumps({'date':'2026-10-03','provider':'private Pixal3D RTX 4080','mode':'image-to-3D; independent components assembled in metres','hyper3d_new_credits':0,'jobs':jobs},ensure_ascii=False,indent=2)+'\n')
print('PROVENANCE',len(jobs),'attempts;',sum(j['selected'] for j in jobs),'selected kinds')

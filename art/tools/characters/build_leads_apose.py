"""Build isolated Sora/Mio A-pose proxy and welded heat candidates from completed jobs."""
import argparse,json,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[3];base=root/'art/models/character_leads_apose_20261005';ev=root/'evidence/character_leads_apose_20261005';blender='/Applications/Blender.app/Contents/MacOS/Blender'
parser=argparse.ArgumentParser();parser.add_argument('--character',required=True,choices=['sora','mio']);args=parser.parse_args();who=args.character
record=next(r for r in json.loads((root/'art/manifests/character_leads_apose_20261005.json').read_text())['characters'] if r['character']==who)
def run(label,script,arguments):
 with (ev/(who+'-'+label+'.log')).open('w') as f:
  subprocess.run([blender,'-b','--factory-startup','--python-exit-code','1','-P',str(root/script),'--',*[str(v) for v in arguments]],stdout=f,stderr=subprocess.STDOUT,timeout=300,check=True)
 print(who,label,'completed',flush=True)
raw=root/record['raw_directory']/'model.glb';assert raw.is_file()
run('normalize','art/poc/character_pipeline_20261003/prepare_model.py',[raw,base/(who+'_static.glb'),record['height_m']])
run('reference-views','art/tools/characters/render_static.py',[base/(who+'_static.glb'),ev/(who+'-source-views')])
run('seed','art/tools/characters/seed_apose.py',[base/(who+'_static.glb'),base/(who+'_seed.glb'),who])
run('proxy','art/tools/characters/proxy_bind.py',['--character',who,'--source',base/(who+'_seed.glb'),'--destination',base/'proxy','--motion',root/record['original_motion_source'],'--hand-frame','tpose-front'])
try:
 run('heat','art/tools/characters/heat_trial.py',[who,'--source',base/f'proxy/authoring/{who}_proxy.blend','--destination',base/'heat'])
except subprocess.CalledProcessError:
 print(who,'heat candidate rejected; inspect retained diagnostic',flush=True)
for variant in ['proxy','heat']:
 author=base/f'{variant}/authoring/{who}_proxy.blend'
 if not author.exists():continue
 run(variant+'-spikes','art/tools/characters/audit_cloth_spikes.py',[author,ev/(who+'-'+variant+'-spikes.json')])

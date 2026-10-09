"""Normalize, measure and rebind completed NPC sources; preserve original action timings."""
from pathlib import Path
import subprocess,json,argparse
ROOT=Path(__file__).resolve().parents[3];BLENDER='/Applications/Blender.app/Contents/MacOS/Blender'
parser=argparse.ArgumentParser();parser.add_argument('--character',required=True);args=parser.parse_args();who=args.character
record=next(r for r in json.loads((ROOT/'art/manifests/characters_apose_20261004.json').read_text())['characters'] if r['character']==who)
folder=ROOT/'art/models/character_roster_apose_20261004';evidence=ROOT/'evidence/character_roster_apose_20261004'
steps=[('normalize',ROOT/'art/poc/character_pipeline_20261003/prepare_model.py',[ROOT/record['raw_directory']/'model.glb',folder/(who+'_static.glb'),str(record['height_m'])]),('seed',ROOT/'art/tools/characters/seed_apose.py',[folder/(who+'_static.glb'),folder/(who+'_seed.glb'),who]),('render',ROOT/'art/tools/characters/render_static.py',[folder/(who+'_static.glb'),evidence/(who+'-source-views')]),('bind',ROOT/'art/tools/characters/proxy_bind.py',['--character',who,'--source',folder/(who+'_seed.glb'),'--destination',folder/'binding','--motion',ROOT/f'art/models/archive/characters_before_apose_20261004/CH_{who}.glb','--hand-frame','tpose-front'])]
for name,script,arguments in steps:
 cmd=[BLENDER,'-b','--factory-startup','--python-exit-code','1','-P',str(script),'--',*[str(v) for v in arguments]]
 with (evidence/f'{who}-{name}.log').open('w') as f:r=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,timeout=300)
 if r.returncode:raise RuntimeError(who+' '+name+' failed; inspect log')
 print(who,name,'passed',flush=True)

# The current selected NPC variants use welded heat weights and a torso garment pass.
# Aoi uses the corrected cross-section anchors plus the local skin-rim patch.

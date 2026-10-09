"""Package the new leads without touching other people; adopt only after native QA."""
from pathlib import Path
import sys,json,struct,hashlib,argparse,shutil,math
root=Path(__file__).resolve().parents[3];base=root/'art/models/character_leads_apose_20261005';ev=root/'evidence/character_leads_apose_20261005';sys.path.insert(0,str(root/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import load,durations
parser=argparse.ArgumentParser();parser.add_argument('--adopt',action='store_true');args=parser.parse_args();out=base/'exports';out.mkdir(exist_ok=True);preview=base/'previews';preview.mkdir(exist_ok=True)
def save(doc,blob,path):
 data=json.dumps(doc,separators=(',',':')).encode();data+=b' '*((-len(data))%4);blob+=b'\0'*((-len(blob))%4);path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(data)+len(blob))+struct.pack('<II',len(data),0x4E4F534A)+data+struct.pack('<II',len(blob),0x004E4942)+blob)
def clean(doc):
 for mesh in doc['meshes']:
  for p in mesh['primitives']:p['attributes'].pop('COLOR_0',None)
rows=[]
for who,name in [('sora','空'),('mio','澪')]:
 source=base/'clothing/godot/assets';doc,blob=load(source/f'{who}_spring.glb');clean(doc);profile=json.loads((source/f'{who}_runtime.json').read_text());rig=next(n for n in doc['nodes'] if n.get('name')=='Rig');rig.setdefault('extras',{}).update(character_id=who,character_name=name,character_pipeline='leads-apose-20261005',reference_pose='A 45 degrees below horizontal',character_clothing={'spring_chains':profile['spring_chains'],'sleeves':profile['sleeves'],'limit_degrees':12})
 target=out/f'CH_{who}.glb';save(doc,blob,target);pd,pb=load(source/f'{who}_modular.glb');clean(pd);save(pd,pb,preview/f'CH_{who}.glb')
 before=durations(root/f'art/models/archive/characters_before_apose_20261004/CH_{who}.glb');after=durations(target);assert all(abs(after.get(k,-1)-v)<1e-6 for k,v in before.items())
 joints=doc['skins'][0]['joints'];assert len(joints)==66;fingers=sum(any(part in doc['nodes'][j].get('name','') for part in ['Thumb','Index','Middle','Ring','Pinky']) for j in joints);assert fingers==30
 generation=json.loads((root/f'art/models/raw/CH_{who}_rodin_apose_20261005/generation.json').read_text());fit=json.loads((base/f'{who}_seed.json').read_text())['arm_fits'];rows.append({'id':'CH_'+who,'character':who,'name':name,'file':str(target.relative_to(root)),'preview_path':f'art/library/characters/CH_{who}.glb','reference_pose':'A 45 degrees below horizontal','base_joints':54,'clothing_joints':12,'finger_joints':fingers,'animations':list(before),'clip_duration_error':0,'triangles':sum(doc['accessors'][p['indices']]['count']//3 for m in doc['meshes'] for p in m['primitives']),'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'clothing':profile,'surface_source':str((base/f'{who}_static.glb').relative_to(root)),'status':'candidate','generation_id':generation['generation_id'],'source_url':generation['display_url'],'references':[f'art/library/characters/references/{who}_{view}.png' for view in ['front','back']],'raw_path':f'art/models/raw/CH_{who}_rodin_apose_20261005/model.glb','authoring_path':str((base/f'clothing/authoring/{who}_spring.blend').relative_to(root)),'corrective_shapes':['Shoulder_Left','Cuff_Left','Shoulder_Right','Cuff_Right']+(['Skirt_Clearance'] if who=='mio' else []),'measured_arm_angles_degrees':{side:round(math.degrees(math.atan(abs(co[0]))),2) for side,co in fit.items()}})
(ev/'lead-candidates.json').write_text(json.dumps({'characters':rows},ensure_ascii=False,indent=2))
if args.adopt:
 proof=json.loads((ev/'asset-contract.json').read_text());assert proof['passed']
 canonical=root/'art/manifests/character_roster_20261004.json';data=json.loads(canonical.read_text());updates={p['character']:p for p in rows}
 for row in rows:
  for view in ['front','back']:shutil.copy2(root/f'art/references/character_leads_apose_20261005/{row["character"]}_{view}.png',root/f'art/library/characters/references/{row["character"]}_{view}.png')
  shutil.copy2(preview/(row['id']+'.glb'),root/row['preview_path']);row['status']='installed';row['game_path']='game/assets/models/'+row['id']+'.glb'
 data['characters']=[updates.get(p['character'],p) for p in data['characters']];data['status']='leads replaced; final game verification pending';canonical.write_text(json.dumps(data,ensure_ascii=False,indent=2))
 config=root/'art/models/game_assets.json';data=json.loads(config.read_text())
 for row in rows:data['assets'][row['id']].update(src=str((root/row['file']).relative_to(root/'art/models')),preserve_rigged_character=True,source_page=row['source_url'])
 config.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
print('Packaged regenerated Sora/Mio', 'and adopted' if args.adopt else 'as candidates')

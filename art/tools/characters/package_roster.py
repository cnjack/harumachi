"""Prepare validated game candidates and four-influence browser motion previews."""
from pathlib import Path
import json,struct,sys,hashlib,shutil
ROOT=Path(__file__).resolve().parents[3];BASE=ROOT/'art/models/character_roster_apose_20261004';SOURCE=BASE/'clothing/godot/assets'
sys.path.insert(0,str(ROOT/'art/poc/character_pipeline_20261003/appearance_preserved'))
from retime_glb import load,durations
NAMES={'sora':'空','mio':'澪','ren':'莲','haru':'春','tanaka':'田中爷爷','aoi':'小葵','kazuko':'和子阿姨'}
OUT=BASE/'exports';OUT.mkdir(exist_ok=True);PREVIEW=ROOT/'art/library/characters';PREVIEW.mkdir(exist_ok=True)
REFS=PREVIEW/'references';REFS.mkdir(exist_ok=True)
POSE_PLAN={r['character']:r for r in json.loads((ROOT/'art/manifests/characters_apose_20261004.json').read_text())['characters']}
def save(doc,blob,path):
 encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);blob+=b'\0'*((-len(blob))%4)
 path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(blob))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+struct.pack('<II',len(blob),0x004E4942)+blob)
def strip_colors(doc):
 for mesh in doc['meshes']:
  for p in mesh['primitives']:p['attributes'].pop('COLOR_0',None)
manifest=[]
current_manifest=ROOT/'art/manifests/character_roster_20261004.json'
current_rows={p['character']:p for p in json.loads(current_manifest.read_text())['characters']} if current_manifest.exists() else {}
for who,name in NAMES.items():
 if who in current_rows and current_rows[who].get('file')!=str((OUT/f'CH_{who}.glb').relative_to(ROOT)):
  manifest.append(current_rows[who]);continue
 profile=json.loads((SOURCE/f'{who}_runtime.json').read_text()) if who in ['sora','mio'] else {'spring_chains':[],'sleeves':{}}
 selected=(SOURCE/f'{who}_spring.glb') if who in ['sora','mio'] else BASE/f'final-binding/godot/assets/{who}_proxy.glb'
 doc,blob=load(selected);strip_colors(doc)
 rig=next(n for n in doc['nodes'] if n.get('name')=='Rig');extras=rig.setdefault('extras',{});extras.update(character_id=who,character_name=name,character_pipeline='apose-roster-20261004',character_clothing={'spring_chains':profile['spring_chains'],'sleeves':profile['sleeves'],'limit_degrees':12},reference_pose='T with preserved appearance' if who in ['sora','mio'] else 'A 45 degrees below horizontal')
 if not profile['spring_chains']:extras.pop('character_clothing',None)
 target=OUT/f'CH_{who}.glb';save(doc,blob,target)
 pd,pb=load(SOURCE/f'{who}_modular.glb' if who in ['sora','mio'] else selected);strip_colors(pd);preview=PREVIEW/f'CH_{who}.glb';save(pd,pb,preview)
 original=ROOT/f'art/models/archive/characters_before_apose_20261004/CH_{who}.glb';before=durations(original);after=durations(target);assert all(abs(after[k]-v)<1e-6 for k,v in before.items())
 joints=doc['skins'][0]['joints'];fingers=sum(any(d in doc['nodes'][j].get('name','') for d in ['Thumb','Index','Middle','Ring','Pinky']) for j in joints);assert len(joints)==(66 if who in ['sora','mio'] else 54) and fingers==30
 tris=sum(doc['accessors'][p['indices']]['count']//3 for m in doc['meshes'] for p in m['primitives'])
 item={'id':'CH_'+who,'character':who,'name':name,'file':str(target.relative_to(ROOT)),'preview_path':str(preview.relative_to(ROOT)),'reference_pose':extras['reference_pose'],'base_joints':54,'clothing_joints':12 if who in ['sora','mio'] else 0,'finger_joints':fingers,'animations':list(before),'clip_duration_error':0,'triangles':tris,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'clothing':profile,'status':'candidate'}
 item['authoring_path']=str((BASE/f'clothing/authoring/{who}_spring.blend' if who in ['sora','mio'] else BASE/f'final-binding/authoring/{who}_proxy.blend' if who!='kazuko' else BASE/'final-binding/authoring/kazuko_apron.blend').relative_to(ROOT))
 item['corrective_shapes']=['Shoulder_Left','Cuff_Left','Shoulder_Right','Cuff_Right'] if who in ['sora','mio'] else ['Apron_Clearance'] if who=='kazuko' else []
 if who in POSE_PLAN:item['measured_arm_angles_degrees']=POSE_PLAN[who]['measured_arm_angles_degrees']
 if who not in ['sora','mio']:
  generation=json.loads((ROOT/f'art/models/raw/CH_{who}_rodin_apose_20261004/generation.json').read_text());item.update(generation_id=generation['generation_id'],source_url=generation['display_url'],references=generation['references'],raw_path=f'art/models/raw/CH_{who}_rodin_apose_20261004/model.glb')
 else:item.update(source_url='https://hyper3d.ai/workspace/rodin/'+('ba5bffd2-b85f-489f-b3b8-a098bd9e8284' if who=='sora' else 'c8a042ea-33b7-4d38-82e6-bd8e88e300d3'),raw_path=f'art/poc/character_pipeline_20261003/tpose_20261004/static/{who}_tpose.glb')
 if who in ['sora','mio']:
  approved=ROOT/f'art/models/raw/CH_{who}_approved_20261004/model.glb';approved.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/item['raw_path'],approved);item['raw_path']=str(approved.relative_to(ROOT))
  source_refs=[ROOT/f'art/poc/character_pipeline_20261003/tpose_20261004/references/{who}_tpose_{v}.png' for v in ['front','back']]
 else:source_refs=[ROOT/v for v in item['references']]
 public_refs=[]
 for index,ref in enumerate(source_refs):
  copy=REFS/(who+('_front.png' if index==0 else '_back.png'));shutil.copy2(ref,copy);public_refs.append(str(copy.relative_to(ROOT)))
 item['references']=public_refs
 manifest.append(item)
(ROOT/'art/manifests/character_roster_20261004.json').write_text(json.dumps({'version':1,'status':'candidate verification','characters':manifest,'game_replacement_authorized':True,'browser_preview':'base skin and corrective motion; clothes secondary physics runs in Godot'},ensure_ascii=False,indent=2))
print('Packaged',len(manifest),'characters; 54 body joints / 30 finger joints; sleeves added where validated; source clip timing preserved')

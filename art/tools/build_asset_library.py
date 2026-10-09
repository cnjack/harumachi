"""Build the offline asset catalog from game exports and licensed source packs."""
import json,re,hashlib,struct
from datetime import datetime
from zoneinfo import ZoneInfo
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/library';OUT.mkdir(exist_ok=True)
spec=json.loads((ROOT/'art/models/game_assets.json').read_text())['assets']
integration=json.loads((OUT/'integration.json').read_text())['assets']
roster_path=ROOT/'art/manifests/character_roster_20261004.json'
roster={r['id']:r for r in json.loads(roster_path.read_text())['characters']} if roster_path.exists() else {}

def category(name):
 value=name.lower()
 if any(k in value for k in ['grass','lawn']):return '草地'
 if name.startswith('T0') or any(k in value for k in ['tree','pine','palm','birch']):return '树木'
 if name.startswith(('CH_','PC_')):return '人物'
 if any(k in value for k in ['cat','bird','sparrow','animal','fish']):return '动物'
 if any(k in value for k in ['plant','flower','bush','fern','mushroom','petal','daisy','reed','clover']) or name.startswith(('C0','C1','M12','V0')):return '植物'
 if name.startswith(('H0','S0','M0')):return '建筑'
 if any(k in value for k in ['rock','stone','pebble','terrain','path','sand']):return '地景'
 return '道具'

def gltf(path):
 if path.suffix=='.gltf':return json.loads(path.read_text())
 b=path.read_bytes();length=struct.unpack_from('<I',b,12)[0];return json.loads(b[20:20+length])

def entry(key,path,collection,name,license,source,status):
 data=gltf(path)
 count=sum(data['accessors'][p['indices']]['count']//3 if 'indices' in p else data['accessors'][p['attributes']['POSITION']]['count']//3 for mesh in data.get('meshes',[]) for p in mesh['primitives'] if p.get('mode',4)==4)
 return {'id':key,'name':name,'category':category(name),'collection':collection,'path':str(path.relative_to(ROOT)),'format':path.suffix[1:].upper(),'triangles':count,'bytes':path.stat().st_size,'license':license,'source':source,'status':status,'animations':[a.get('name','动画') for a in data.get('animations',[])],'alpha':any(m.get('alphaMode','OPAQUE')!='OPAQUE' for m in data.get('materials',[])),'preview':'art/library/previews/'+key.replace('/','_')+'.png','uses':[]}

assets=[]
for path in sorted((ROOT/'game/assets/models').glob('*.glb')):
 config=spec.get(path.stem,{})
 item=entry('game/'+path.stem,path,'游戏资产',path.stem,config.get('license','项目素材，来源条款待核对'),config.get('source_page',''),'已接入')
 item['provider']=config.get('provider','项目制作');item['raw_path']='art/models/'+config['src'] if config.get('src') else ''
 if config.get('asset_library_id'):item['library_source']=config['asset_library_id']
 metrics=ROOT/'game/assets/models/_stats'/ (path.stem+'.json')
 if metrics.exists():item['metrics']=json.loads(metrics.read_text())
 for code in list((ROOT/'game/scripts/world').glob('*.gd'))+list((ROOT/'game/scripts/player').glob('*.gd')):
  if '"'+path.stem+'"' in code.read_text():item['uses'].append(str(code.relative_to(ROOT)))
 item['recipe']='world.spawn("'+path.stem+'", Vector3(0, 0, 0), 0, 0)'
 if path.stem in roster:
  person=roster[path.stem]
  if hashlib.sha256(path.read_bytes()).hexdigest()!=person['sha256']:
   candidate=ROOT/person['file']
   item=entry('game/'+path.stem,candidate,'人物角色',person['name'],'项目人物；Hyper3D 账户来源条款',person['source_url'],'候选')
  item.update(name=person['name'],category='人物',collection='人物角色',character_id=person['character'],preview_path=person['preview_path'],source=person['source_url'],raw_path=person['raw_path'],authoring_path=('art/library/characters/authoring/'+person['id']+'.blend') if (ROOT/('art/library/characters/authoring/'+person['id']+'.blend')).exists() else person.get('authoring_path',''),corrective_shapes=person.get('corrective_shapes',[]),measured_arm_angles_degrees=person.get('measured_arm_angles_degrees',{}),rig={'body_bones':person['base_joints'],'clothing_bones':person['clothing_joints'],'finger_bones':person['finger_joints']},reference_pose=person['reference_pose'],references=person.get('references',[]),provider='Hyper3D Rodin / 人物动画管线')
 assets.append(item)
pack=ROOT/'art/models/raw/free_foliage_20261004'
for collection,folder,source in [('Quaternius 免费','quaternius_standard','https://quaternius.com/packs/stylizednaturemegakit.html'),('Kenney 免费','kenney','https://kenney.nl/assets/nature-kit')]:
 for path in sorted((pack/folder/'unpacked').rglob('*')):
  if path.suffix.lower() not in ['.glb','.gltf']:continue
  key=('quaternius' if folder=='quaternius_standard' else 'kenney')+'/'+path.stem
  item=entry(key,path,collection,path.stem,'CC0-1.0',source,'候选')
  item['license_path']=str(next((pack/folder/'unpacked').rglob('*License*'),pack/folder/'provenance.json').relative_to(ROOT))
  if path.suffix=='.gltf':item['bundle_path']=str((pack/folder/'original.zip').relative_to(ROOT))
  linked=[aid for aid,config in spec.items() if config.get('asset_library_id')==key]
  if linked:item['status']='已接入';item['game_ids']=linked;item['recipe']='world.spawn("'+linked[0]+'", Vector3(0, 0, 0), 0, 0)'
  else:item['recipe']='导入配置：art/library/integration.json → integrate_free_foliage.py → game_export.py'
  assets.append(item)
for person in roster.values():
 raw=ROOT/person['raw_path']
 if not raw.is_file():continue
 item=entry('character-source/'+person['id'],raw,'人物原稿',person['name']+' · '+('A pose' if person['reference_pose'].startswith('A ') else 'T pose'),'项目人物原稿；随账户来源条款',person['source_url'],'原稿')
 item.update(category='人物',character_id=person['character'],reference_pose=person['reference_pose'],references=person.get('references',[]),provider='Hyper3D Rodin',recipe='绑定导出：art/tools/characters/，完成后以 CH_'+person['character']+' 接入游戏。')
 assets.append(item)

engine_lock=json.loads((ROOT/'tools/godot-version.json').read_text())
catalog={'schema_version':2,'title':'晴町素材室','updated':datetime.now(ZoneInfo('Asia/Shanghai')).date().isoformat(),'engine':'Godot '+engine_lock['release_tag'],'count':len(assets),'categories':['全部','树木','植物','草地','地景','建筑','道具','人物','动物'],'collections':['全部','人物角色','人物原稿','游戏资产','Quaternius 免费','Kenney 免费'],'assets':assets}
(OUT/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
print('CATALOG',len(assets),'assets')

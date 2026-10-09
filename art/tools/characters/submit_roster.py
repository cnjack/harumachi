"""One Rodin task per NPC; persist intent/IDs and never retry a paid submit."""
from pathlib import Path
import sys,argparse,json,ssl,urllib.request,time,hashlib
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'art/tools'))
from rodin_mcp import RodinMCP
from rodin_asset import unpack
parser=argparse.ArgumentParser();parser.add_argument('--character',required=True);parser.add_argument('--manifest',default='art/manifests/characters_apose_20261004.json');args=parser.parse_args()
record=next(r for r in json.loads((ROOT/args.manifest).read_text())['characters'] if r['character']==args.character)
who=args.character;out=ROOT/record['raw_directory'];out.mkdir(parents=True,exist_ok=True)
refs=[ROOT/p for p in record['references']] if 'references' in record else [ROOT/f'art/references/characters_apose_20261004/{who}_{view}.png' for view in ['front','back']]
assert all(p.is_file() for p in refs)
short={
'sora':'anime young male Sora: tousled brown hair, amber eyes, mint sage open short-sleeve collared shirt/chest pocket over white T-shirt, beige cropped wide trousers, orange canvas sneakers, brown watch on LEFT wrist.',
'mio':'anime young female Mio: brown chin-length bob, yellow hair clip on LEFT, cream cardigan/tan buttons/ribbed elbow cuffs and pockets, light blue blouse, navy knee pleated skirt, white sneakers, cream tote on RIGHT shoulder.',
'ren':'adult anime male baker Ren: dark tousled hair, yellow bandana knot behind, rust-orange rolled-sleeve shirt, white long apron front pocket/back waist bow, beige trousers, brown lace-up shoes.',
'haru':'elderly anime woman Haru: warm lined face, gray low bun, olive quilted button vest and gardening gloves in left pocket, lavender blouse, brown loose trousers, green rubber boots.',
'tanaka':'elderly anime male Tanaka: short white hair, white mustache, indigo open elbow-sleeve work jacket tied at front, white T-shirt, towel around neck, beige trousers and dark green rubber boots.',
'aoi':'anime child girl Aoi: brown chin-length bob and sunflower clip at left, white sunflower T-shirt, blue denim short overalls and brass straps, white calf socks, yellow canvas sneakers.',
'kazuko':'middle-aged anime woman Kazuko: wavy short brown hair, warm round face/body, white rolled-sleeve blouse, yellow knee-length apron front pocket/back bow, pink shoulder-draped cardigan tied in front, charcoal trousers, brown sandals.'}
prompt=('One complete '+short[who]+' Match both references exactly, front/back are same person. Symmetric A pose, straight arms 45 degrees below horizontal. Natural downward shoulder slope, no raised outer shoulder ridge or shrug. Five distinct fingers, neutral wrists, palms toward torso. Clean rounded sleeve tubes and armpits, clear empty space between arms and torso, no membranes or cloth welded to apron/body. Clothes, age, face, hair and proportions unchanged. Apron/towel/cardigan drape follows torso, never joined to arm. Proper separate legs, open garment hems. Clean rig-ready joints. Japanese TV anime flat colours and crisp cel shadows, no realistic skin or glossy PBR.')
if record.get('rodin_prompt'):prompt=(ROOT/record['rodin_prompt']).read_text().strip()
assert len(prompt)<=1024,len(prompt)
request={'prompt':prompt,'tier':'Gen-2.5-High','mesh_mode':'Quad','quality_override':50000,'texture_delight':True,'geometry_file_format':'glb'}
client=RodinMCP();context=ssl.create_default_context(cafile='/opt/homebrew/etc/ca-certificates/cert.pem')
existing=out/'generation.json';intent=out/'submission-started.json'
if existing.exists():
 generation=json.loads(existing.read_text());assert generation.get('generation_id');print('RESUME',who,generation['generation_id'],flush=True)
 if (out/'model.glb').exists():print('ALREADY_DOWNLOADED',who,flush=True);sys.exit(0)
else:
 if intent.exists():raise RuntimeError('Paid submission outcome unknown: inspect saved response / Hyper3D Mine; do not retry')
 uploads=unpack(client.call('rodin_create_uploads',{'files':[{'filename':p.name,'mime_type':'image/png','size_bytes':p.stat().st_size} for p in refs]}))['uploads']
 for p,u in zip(refs,uploads):
  with urllib.request.urlopen(urllib.request.Request(u['upload_url'],data=p.read_bytes(),headers=u['headers'],method=u['method']),context=context,timeout=60) as response:assert response.status in (200,201,204)
 request['reference_upload_ids']=[u['upload_id'] for u in uploads]
 generation={'character':who,'id':record['id'],'references':[str(p.relative_to(ROOT)) for p in refs],'reference_sha256':[hashlib.sha256(p.read_bytes()).hexdigest() for p in refs],'request':request,'arm_angle_below_horizontal':45}
 intent.write_text(json.dumps(generation,ensure_ascii=False,indent=2))
 response=client.call('rodin_generate',request);(out/'submission-response.json').write_text(json.dumps(response,ensure_ascii=False,indent=2))
 generation.update(unpack(response));existing.write_text(json.dumps(generation,ensure_ascii=False,indent=2));print('SUBMITTED',who,generation['generation_id'],flush=True)
deadline=time.time()+1800
while time.time()<deadline:
 status=unpack(client.call('rodin_wait',{'generation_id':generation['generation_id'],'timeout_seconds':30}));print(who,status['status'],status.get('stage',{}).get('name',''),flush=True)
 if status['status']=='failed':raise RuntimeError('Generation failed; retained task ID, no resubmission')
 if status['status']!='completed':continue
 result=unpack(client.call('rodin_get_result',{'generation_id':generation['generation_id']}));files=[f for f in result['files'] if f.get('name','').endswith('.glb')];chosen=next((f for f in files if 'pbr' in f['name']),files[0])
 with urllib.request.urlopen(chosen['url'],context=context,timeout=120) as response:(out/'model.glb').write_bytes(response.read())
 generation.update(status='downloaded',display_url=result['display_url'],selected_file=chosen['name'],sha256=hashlib.sha256((out/'model.glb').read_bytes()).hexdigest());existing.write_text(json.dumps(generation,ensure_ascii=False,indent=2));print('SAVED',who,out/'model.glb',flush=True);break
else:raise RuntimeError('Wait deadline: resume existing generation ID; never resubmit')

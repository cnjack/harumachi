"""Validate the new A-pose model surfaces, all skin channels and source action timings."""
from pathlib import Path
import sys,json,hashlib
root=Path(__file__).resolve().parents[3];sys.path.insert(0,str(Path(__file__).parent));from audit_roster import accessor,preservation,load,durations
ev=root/'evidence/character_leads_apose_20261005';base=root/'art/models/character_leads_apose_20261005';reports=[]
for who in ['sora','mio']:
 target=base/f'exports/CH_{who}.glb';d,b=load(target);joints=d['skins'][0]['joints'];bad=indices=0
 for mesh in d['meshes']:
  for p in mesh['primitives']:
   attrs=p['attributes'];weights=accessor(d,b,attrs['WEIGHTS_0']);ids=accessor(d,b,attrs['JOINTS_0'])
   if 'WEIGHTS_1' in attrs:weights=[a+c for a,c in zip(weights,accessor(d,b,attrs['WEIGHTS_1']))];ids=[a+c for a,c in zip(ids,accessor(d,b,attrs['JOINTS_1']))]
   bad+=sum(abs(sum(row)-1)>1e-5 or min(row)<0 for row in weights);indices+=sum(any(index>=len(joints) for index,weight in zip(ii,ww) if weight>0) for ii,ww in zip(ids,weights))
 fingers=sum(any(part in d['nodes'][j].get('name','') for part in ['Thumb','Index','Middle','Ring','Pinky']) for j in joints);before=durations(root/f'art/models/archive/characters_before_apose_20261004/CH_{who}.glb');after=durations(target);error=max(abs(after.get(k,-1)-v) for k,v in before.items());geometry=preservation(load(base/f'{who}_static.glb'),(d,b))
 row={'character':who,**geometry,'joints':len(joints),'fingers':fingers,'bad_weights':bad,'bad_indices':indices,'max_duration_error':error,'animations':list(after),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()};row['passed']=geometry['original_surface_retained'] and len(joints)==66 and fingers==30 and bad==indices==0 and error<1e-6;reports.append(row);print(json.dumps(row))
(ev/'asset-contract.json').write_text(json.dumps({'passed':all(r['passed'] for r in reports),'characters':reports},indent=2));assert all(r['passed'] for r in reports)

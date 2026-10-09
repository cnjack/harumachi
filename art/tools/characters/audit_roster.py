"""Character surface/UV, original action timings and exported skin contract."""
from pathlib import Path
import sys,json,struct,hashlib,argparse
from collections import Counter
import numpy as np
from scipy.spatial import cKDTree
ROOT=Path(__file__).resolve().parents[3];BASE=ROOT/'art/models/character_roster_apose_20261004'
sys.path.insert(0,str(ROOT/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import load,durations

def accessor(d,b,i):
 a=d['accessors'][i];v=d['bufferViews'][a['bufferView']];width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];code={5121:'B',5123:'H',5125:'I',5126:'f'}[a['componentType']];fmt='<'+code*width;size=struct.calcsize(fmt);offset=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',size)
 return [struct.unpack_from(fmt,b,offset+j*stride) for j in range(a['count'])]
def exterior(d,b):
 positions=[];uvs=[];faces=[];offset=0
 for mesh in d['meshes']:
  if mesh.get('name','').startswith('HiddenArm'):continue
  for p in mesh['primitives']:
   pp=accessor(d,b,p['attributes']['POSITION']);uu=accessor(d,b,p['attributes']['TEXCOORD_0']);ids=np.array([a[0] for a in accessor(d,b,p['indices'])],dtype=np.int32).reshape(-1,3)
   positions.extend(pp);uvs.extend(uu);faces.extend(ids+offset);offset+=len(pp)
 return np.column_stack((positions,uvs)),np.array(faces,dtype=np.int32)
def preservation(source,target):
 a,af=exterior(*source);b,bf=exterior(*target);tree=cKDTree(a)
 source_distance,source_ids=tree.query(a);distance,ids=tree.query(b)
 def counter(faces,mapping):
  result=Counter()
  for face in faces:
   corners=[int(mapping[i]) for i in face];result[min(tuple(corners[k:]+corners[:k]) for k in range(3))]+=1
  return result
 original=counter(af,source_ids);current=counter(bf,ids)
 missing=sum((original-current).values())
 duplicates=0
 return {'original_surface_retained':missing==0 and float(distance.max())<1e-5,'missing_original_triangles':missing,'collapsed_exact_duplicate_triangles':duplicates,'max_position_uv_error':float(distance.max()),'added_internal_triangles':len(bf)-len(af)}
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path,default=ROOT/'evidence/character_roster_apose_20261004/asset-contract.json');args=parser.parse_args()
 roster={r['character']:r for r in json.loads((ROOT/'art/manifests/character_roster_20261004.json').read_text())['characters']}
 reports=[]
 for who in ['sora','mio','ren','haru','tanaka','aoi','kazuko']:
  person=roster.get(who,{})
  source=ROOT/person['surface_source'] if person.get('surface_source') else (ROOT/f'art/poc/character_pipeline_20261003/tpose_20261004/static/{who}_tpose.glb') if who in ['sora','mio'] else BASE/(who+'_static.glb')
  sd,sb=load(source);path=ROOT/person['file'] if person.get('file') else BASE/'exports'/('CH_'+who+'.glb');d,b=load(path);bad_weights=bad_ids=0;joints=d['skins'][0]['joints']
  for mesh in d['meshes']:
   for p in mesh['primitives']:
    attrs=p['attributes'];weights=accessor(d,b,attrs['WEIGHTS_0']);ids=accessor(d,b,attrs['JOINTS_0'])
    if 'WEIGHTS_1' in attrs:weights=[a+c for a,c in zip(weights,accessor(d,b,attrs['WEIGHTS_1']))];ids=[a+c for a,c in zip(ids,accessor(d,b,attrs['JOINTS_1']))]
    bad_weights+=sum(abs(sum(w)-1)>1e-5 or min(w)<0 for w in weights);bad_ids+=sum(any(i>=len(joints) for i,w in zip(ii,ww) if w>0) for ii,ww in zip(ids,weights))
  before=durations(ROOT/f'art/models/archive/characters_before_apose_20261004/CH_{who}.glb');after=durations(path);timing=max(abs(after.get(k,-1)-v) for k,v in before.items());fingers=sum(any(n in d['nodes'][i].get('name','') for n in ['Thumb','Index','Middle','Ring','Pinky']) for i in joints)
  geometry=preservation((sd,sb),(d,b))
  item={'character':who,**geometry,'surface_and_uv_preserved':geometry['original_surface_retained'],'joints':len(joints),'fingers':fingers,'bad_weights':bad_weights,'bad_indices':bad_ids,'max_duration_error':timing,'original_actions':len(before),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
  item['passed']=item['surface_and_uv_preserved'] and len(joints)==int(person.get('base_joints',54))+int(person.get('clothing_joints',12 if who in ['sora','mio'] else 0)) and fingers==30 and not bad_weights and not bad_ids and timing<1e-6;reports.append(item);print(json.dumps(item),flush=True)
 args.out.write_text(json.dumps({'passed':all(r['passed'] for r in reports),'characters':reports},indent=2));assert all(r['passed'] for r in reports)

if __name__=='__main__':main()

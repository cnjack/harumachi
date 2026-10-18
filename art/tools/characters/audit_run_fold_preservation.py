#!/usr/bin/env python3
"""Independent orientation and preservation audit for clip-specific Mio cloth targets."""
import sys,json,hashlib,argparse,numpy as np
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from audit_local_garments import mesh_state,pose
from repair_head_neck import read
parser=argparse.ArgumentParser(description="Independently audit added run fold targets against original triangle orientations and exact non-run animation values.")
parser.add_argument('--source',type=Path,required=True)
parser.add_argument('--candidate',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--samples',type=int,default=128)
parser.add_argument('--clip',default='run')
parser.add_argument('--prefix',default='GarmentFoldFair_run_')
parser.add_argument('--expect-fixed',action='store_true')
args=parser.parse_args()
src,dst=args.source,args.candidate;s=mesh_state(src,'mio');c=mesh_state(dst,'mio');added=[i for i,n in enumerate(c['names']) if n.startswith(args.prefix)];sp=s['d']['meshes'][s['node']['mesh']]['primitives'][0];cp=c['d']['meshes'][c['node']['mesh']]['primitives'][0];faces=read(s['d'],s['b'],sp['indices']).reshape(-1,3)
if not added:raise ValueError('Candidate contains no '+args.prefix+' targets')
r={'original_target_names_exact':c['names'][:len(s['names'])]==s['names'],'scope':'Independent read-only cross-product orientation comparison atauthored phases using original curves plus all requested new clip targets. No runtime garment solve or candidate-native claim.','source':str(src),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'candidate':str(dst),'candidate_sha256':hashlib.sha256(dst.read_bytes()).hexdigest(),'clip':args.clip,'new_target_prefix':args.prefix,'added_names':[c['names'][i] for i in added],'base_attributes_exact':{name:bool(np.array_equal(read(s['d'],s['b'],ai),read(c['d'],c['b'],cp['attributes'][name]))) for name,ai in sp['attributes'].items()},'indices_exact':bool(np.array_equal(faces,read(c['d'],c['b'],cp['indices']).reshape(-1,3))),'old_targets_exact':all(all(np.array_equal(read(s['d'],s['b'],a),read(c['d'],c['b'],cp['targets'][i][key])) for key,a in target.items()) for i,target in enumerate(sp['targets'])),'other_actions':[],'samples':[],'authored_phase_count':args.samples}
for a in s['d']['animations']:
 if a['name']==args.clip:continue
 aa=next(x for x in c['d']['animations'] if x['name']==a['name']);channels=[]
 for ch in a['channels']:
  cc=next(x for x in aa['channels'] if x['target']==ch['target']);sa=a['samplers'][ch['sampler']];ca=aa['samplers'][cc['sampler']];time_equal=np.array_equal(read(s['d'],s['b'],sa['input']),read(c['d'],c['b'],ca['input']));sv=read(s['d'],s['b'],sa['output']);cv=read(c['d'],c['b'],ca['output']);newzero=True
  if ch['target']=={'node':s['ni'],'path':'weights'}:
   sv=sv.reshape(-1,len(s['names']));cv=cv.reshape(-1,len(c['names']));newzero=bool(np.all(cv[:,added]==0));cv=cv[:,:len(s['names'])]
  channels.append(bool(time_equal and np.array_equal(sv,cv) and newzero and sa.get('interpolation')==ca.get('interpolation')))
 r['other_actions'].append({'clip':a['name'],'all_original_track_times_values_exact_and_new_weights_zero':all(channels)})
a=next(x for x in s['d']['animations'] if x['name']==args.clip);T=max(float(read(s['d'],s['b'],x['input']).max()) for x in a['samplers']);flip_union=set();small_union=set()
for phase in np.arange(args.samples)/args.samples:
 before,_=pose(s,args.clip,float(phase*T));after,_=pose(c,args.clip,float(phase*T));x=np.cross(before[faces[:,1]]-before[faces[:,0]],before[faces[:,2]]-before[faces[:,0]]);y=np.cross(after[faces[:,1]]-after[faces[:,0]],after[faces[:,2]]-after[faces[:,0]]);area=np.linalg.norm(x,axis=1);dot=np.einsum('ij,ij->i',x,y);flip=np.flatnonzero((dot<=0)&(area>1e-12));small=np.flatnonzero((np.linalg.norm(y,axis=1)<.15*area)&(area>1e-12));flip_union.update(flip.tolist());small_union.update(small.tolist());r['samples'].append({'phase':float(phase),'new_inverted_face_count':len(flip),'faces':flip.tolist(),'new_near_collapsed_faces':small.tolist(),'max_added_displacement_m':float(np.linalg.norm(after-before,axis=1).max()),'max_body_displacement_m':float(np.linalg.norm((after-before)[s['body']],axis=1).max())})
r.update({'unique_new_inverted_faces':sorted(flip_union),'unique_near_collapsed_faces':sorted(small_union),'maximum_added_displacement_m':max(x['max_added_displacement_m'] for x in r['samples']),'maximum_body_displacement_m':max(x['max_body_displacement_m'] for x in r['samples'])});out=args.output;r['tool_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest();r['failures']=[]
if r['unique_new_inverted_faces'] or r['unique_near_collapsed_faces']:r['failures'].append('Added targets introduce inverted or near-collapsed source triangles')
if not all(r['base_attributes_exact'].values()) or not r['indices_exact'] or not r['old_targets_exact'] or not r['original_target_names_exact']:r['failures'].append('Original mesh/skin/UV/morph payload changed')
if not all(a['all_original_track_times_values_exact_and_new_weights_zero'] for a in r['other_actions']):r['failures'].append('An original other action changed')
if r['maximum_body_displacement_m']>1e-10:r['failures'].append('Added cloth target moved an original body vertex')
out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'output':str(out),'flipped_faces':len(flip_union),'near_collapsed_faces':len(small_union),'failures':r['failures']}))
if args.expect_fixed and r['failures']:raise SystemExit(1)

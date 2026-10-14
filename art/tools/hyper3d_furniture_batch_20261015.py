"""Paid furniture CLI calls: durable intent, exact reference SHA, same principal.

Never retry an ambiguous generation. Fetch always resumes the recorded task.
"""
import argparse,json,os,time
from pathlib import Path
import hyper3d_budget_batch as shared
ROOT=Path(__file__).resolve().parents[2]
SCOPE=ROOT/'art/manifests/hyper3d_furniture_20261015.json'
EVIDENCE=ROOT/'evidence/hyper3d_furniture_20261015'
RAW=ROOT/'art/models/raw/hyper3d_furniture_20261015'
shared.EVIDENCE=EVIDENCE;shared.RAW=RAW

def baseline():
 current=shared.wallet();path=EVIDENCE/'wallet-initial.json'
 if not path.exists():
  if current['total']!=150 or current['frozen']!=0:raise RuntimeError('Initial balance differs from observed 150; reconcile first')
  shared.write(path,current)
 initial=json.loads(path.read_text())
 if current['principal_sha256']!=initial['principal_sha256']:raise RuntimeError('Hyper3D principal changed')
 if current['available']<136:raise RuntimeError('14-credit task bound exhausted')
 shared.write(EVIDENCE/'wallet-latest.json',current)
 return initial,current

def submit(row,candidate):
 folder=RAW/row['id']/candidate;intent=folder/'intent.json'
 if intent.exists():raise RuntimeError('Slot already used or ambiguous: fetch/reconcile only')
 ref=ROOT/row['reference'];review=EVIDENCE/'reference-reviews'/(row['id']+'.json')
 approval=json.loads(review.read_text())
 if approval.get('status')!='pass' or approval.get('sha256')!=shared.sha(ref):raise RuntimeError('Exact reviewed reference missing')
 initial,before=baseline();intents=list(RAW.glob('*/*/intent.json'))
 if len(intents)>=28 or before['available']-.5<136:raise RuntimeError('Generation budget exhausted')
 if any(not (p.parent/'submission.json').exists() for p in intents):raise RuntimeError('Unresolved earlier request: do not resubmit')
 if initial['total']-before['available']!=.5*len(intents):raise RuntimeError('Wallet differs from owned accepted slots; reconcile')
 prompt=row['model_prompt']
 if candidate=='b':
  feedback=EVIDENCE/'candidate-feedback'/(row['id']+'.txt')
  if not feedback.is_file():raise RuntimeError('Review candidate a before requesting a correction')
  prompt+=' Correction after actual model inspection: '+feedback.read_text().strip()
 if not 1<=len(prompt)<=1024:raise RuntimeError('Prompt length invalid')
 request=dict(asset=row['id'],candidate=candidate,reference=row['reference'],reference_sha256=shared.sha(ref),prompt=prompt,tier=row['tier'],mesh_mode=row['mesh_mode'],quality=row['quality'],expected_cost=.5,wallet_before=before,timestamp=time.time(),status='intent_before_request')
 folder.mkdir(parents=True,exist_ok=True)
 with intent.open('x') as stream:json.dump(request,stream,ensure_ascii=False,indent=2);stream.flush();os.fsync(stream.fileno())
 result=shared.cli('generate','--image',str(ref),'--prompt',prompt,'--tier',row['tier'],'--mesh-mode',row['mesh_mode'],'--quality',str(row['quality']),'--texture-delight','--format','glb')
 if not result.get('generation_id'):raise RuntimeError('No generation ID; slot locked pending provider reconciliation')
 shared.write(folder/'submission.json',dict(generation_id=result['generation_id'],status=result.get('status'),timestamp=time.time()))
 for attempt in range(6):
  _,after=baseline();delta=before['available']-after['available']
  if delta!=0:break
  if attempt<5:time.sleep(5)
 shared.write(folder/'charge.json',dict(before=before,after=after,actual_committed_delta=delta,settled_delta=before['total']-after['total'],expected=.5))
 print('ACCEPTED',row['id'],candidate,result['generation_id'],'committed',delta,'available',after['available'],flush=True)
 if delta!=.5:raise RuntimeError('Charge differs from 0.5; reconcile before submitting again')

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['status','submit','fetch']);p.add_argument('--ids',default='');p.add_argument('--candidate',choices=['a','b'],default='a');args=p.parse_args()
 _,wallet=baseline();print('WALLET',json.dumps({k:v for k,v in wallet.items() if k!='principal_sha256'}),flush=True)
 if args.action=='status':return
 rows={row['id']:row for row in json.loads(SCOPE.read_text())['assets']};ids=args.ids.split(',')
 if not args.ids or len(set(ids))!=len(ids) or any(i not in rows for i in ids):p.error('Unique known scope IDs required')
 for aid in ids:
  if args.action=='submit':submit(rows[aid],args.candidate)
  else:shared.fetch(rows[aid],args.candidate)

if __name__=='__main__':main()

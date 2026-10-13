"""Bounded Hyper3D CLI jobs with durable intents; no generation is ever retried.

Run `status`, `submit --ids ID,... --candidate a`, or `fetch --ids ID,... --candidate a`.
References need a SHA-bound visual approval in evidence before a paid submission.
Unknown outcomes remain locked and must be reconciled against the provider first.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import ssl
import subprocess
import time
import urllib.request

ROOT=Path(__file__).resolve().parents[2]
SCOPE=ROOT/'art/manifests/model_diversity_20261013.json'
EVIDENCE=ROOT/'evidence/hyper3d_diversity_20261013'
RAW=ROOT/'art/models/raw/diversity_20261013'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_suffix(path.suffix+'.tmp')
    with temp.open('w') as stream:
        json.dump(data,stream,ensure_ascii=False,indent=2);stream.write('\n')
        stream.flush();os.fsync(stream.fileno())
    os.replace(temp,path)


def cli(*args):
    refresh=subprocess.run(['node',str(Path(__file__).with_name('refresh_hyper3d_session.mjs'))],
                           capture_output=True,text=True,timeout=90)
    if refresh.returncode:
        raise RuntimeError('Existing Hyper3D session cannot refresh; stop before '+args[0]+', do not switch accounts')
    refreshed=json.loads(refresh.stdout)
    if refreshed.get('refreshed'):write(EVIDENCE/'auth-refresh-latest.json',dict(timestamp=time.time(),**refreshed))
    p=subprocess.run(['hyper3d','--output','json',*args],capture_output=True,text=True,
                     env=dict(os.environ,HYPER3D_UPDATE_CHECK='0',CI='1'),timeout=240)
    if p.returncode:
        # CLI messages contain validation/operation errors; strip URL/token forms
        # before retaining diagnostics. Signed result URLs never enter evidence.
        import re
        message=re.sub(r'https?://\S+','[url]',p.stderr.strip())
        message=re.sub(r'(?i)(bearer|access_token|refresh_token)\s*[:=]?\s*\S+',r'\1 [redacted]',message)
        write(EVIDENCE/'cli-last-error.json',dict(action=args[0],timestamp=time.time(),returncode=p.returncode,error=message[:2000]))
        raise RuntimeError('Hyper3D CLI failed for '+args[0]+': '+message[:700]+'; retain intent/task ID, never retry generation blindly')
    return json.loads(p.stdout)


def wallet():
    account=cli('auth','status')
    if not account.get('authenticated'):raise RuntimeError('Existing Hyper3D session is not authenticated')
    w=account['wallet']
    return dict(timestamp=time.time(),principal_sha256=hashlib.sha256(account['user']['uuid'].encode()).hexdigest(),
                balance=w['balance'],subscription_balance=w['subscription_balance'],frozen=w.get('frozen',0),
                total=w['balance']+w['subscription_balance'],available=w['balance']+w['subscription_balance']-w.get('frozen',0))


def baseline():
    path=EVIDENCE/'wallet-initial.json'
    current=wallet()
    if not path.exists():
        if current['total']!=210 or current['frozen']!=0:raise RuntimeError('Initial wallet differs from the verified 210-point baseline')
        write(path,current)
    initial=json.loads(path.read_text())
    if current['principal_sha256']!=initial['principal_sha256']:raise RuntimeError('Hyper3D principal changed; stop')
    if current['available']<150:raise RuntimeError('Available wallet below authorized 150-point floor')
    write(EVIDENCE/'wallet-latest.json',current)
    return initial,current


def submit(row,candidate,initial):
    folder=RAW/row['id']/candidate
    intent=folder/'intent.json'
    if intent.exists():raise RuntimeError(row['id']+': slot already used or ambiguous; only fetch/reconcile is allowed')
    reference=ROOT/row['reference']
    review=EVIDENCE/'reference-reviews'/(row['id']+'.json')
    if not reference.is_file() or not review.is_file():raise RuntimeError(row['id']+': reference or visual approval missing')
    approval=json.loads(review.read_text())
    if approval.get('status')!='pass' or approval.get('sha256')!=sha(reference):raise RuntimeError(row['id']+': approval does not match reference')
    _,before=baseline()
    if before['available']-.5<150:raise RuntimeError('Next generation would cross the 150-point floor')
    known_intents=list(RAW.glob('*/*/intent.json'))
    if len(known_intents)>=120:raise RuntimeError('All authorized submission slots are used')
    unsettled=[p for p in known_intents if not (p.parent/'submission.json').exists()]
    if unsettled:raise RuntimeError('An earlier submission has an ambiguous outcome; reconcile it first')
    expected_spend=.5*len(known_intents)
    actual_committed=initial['total']-before['available']
    if actual_committed!=expected_spend:
        raise RuntimeError('Settled plus frozen charges do not match accepted slots; reconcile before submitting')
    prompt=row['model_prompt']
    if candidate=='b':
        correction=EVIDENCE/'candidate-feedback'/(row['id']+'.txt')
        if not correction.is_file():raise RuntimeError(row['id']+': inspect candidate a and write specific feedback before using b')
        prompt=row['model_style']+'Reconstruct the supplied complete reference object with these corrections: '+correction.read_text().strip()
    if not 1<=len(prompt)<=1024:raise RuntimeError('Prompt outside CLI 1..1024 character range; no intent or paid request created')
    request=dict(asset=row['id'],candidate=candidate,reference=row['reference'],reference_sha256=sha(reference),
                 prompt=prompt,tier=row['tier'],mesh_mode=row['mesh_mode'],quality=row['quality'],
                 expected_cost=.5,wallet_before=before,timestamp=time.time(),status='intent_before_request')
    folder.mkdir(parents=True,exist_ok=True)
    # Exclusive creation is the paid-call idempotency guard, including crashes.
    with intent.open('x') as stream:
        json.dump(request,stream,ensure_ascii=False,indent=2);stream.flush();os.fsync(stream.fileno())
    accepted=cli('generate','--image',str(reference),'--prompt',prompt,'--tier',row['tier'],
                 '--mesh-mode',row['mesh_mode'],'--quality',str(row['quality']),
                 '--texture-delight','--format','glb')
    if not accepted.get('generation_id'):raise RuntimeError('No generation ID returned; intent locked, inspect provider history')
    write(folder/'submission.json',dict(generation_id=accepted['generation_id'],status=accepted.get('status'),timestamp=time.time()))
    # Billing first reserves frozen funds, then settles on task completion.
    # The first read can precede the reservation. Read again, never resubmit.
    for attempt in range(6):
        _,after=baseline()
        delta=before['available']-after['available']
        if delta!=0:break
        if attempt<5:time.sleep(5)
    write(folder/'charge.json',dict(before=before,after=after,actual_committed_delta=delta,
                                   settled_delta=before['total']-after['total'],expected=.5))
    print('ACCEPTED',row['id'],candidate,accepted['generation_id'],'committed',delta,
          'balance',after['total'],'available',after['available'],flush=True)
    if delta!=.5:raise RuntimeError('Observed reserved/settled charge differs from .5; reconcile before further submission')


def fetch(row,candidate):
    folder=RAW/row['id']/candidate
    accepted=json.loads((folder/'submission.json').read_text())
    generation=accepted['generation_id']
    state=cli('status',generation)
    safe={k:state.get(k) for k in ['status','stage','generation_id','error'] if k in state}
    write(folder/'status.json',dict(timestamp=time.time(),**safe))
    print('STATUS',row['id'],candidate,state.get('status'),flush=True)
    if state.get('status')!='completed':return
    if (folder/'model.glb').is_file():
        print('ALREADY_DOWNLOADED',row['id'],candidate,flush=True);return
    result=cli('result',generation)
    files=[f for f in result.get('files',[]) if f.get('name','').lower().endswith('.glb')]
    if not files:raise RuntimeError('Completed task has no GLB; retain task ID')
    chosen=next((f for f in files if 'pbr' in f['name'].lower()),files[0])
    context=ssl.create_default_context(cafile='/opt/homebrew/etc/ca-certificates/cert.pem')
    with urllib.request.urlopen(chosen['url'],context=context,timeout=240) as response:
        data=response.read()
    if data[:4]!=b'glTF':raise RuntimeError('Download is not a binary glTF; no saved asset')
    temp=folder/'model.download';temp.write_bytes(data);os.replace(temp,folder/'model.glb')
    write(folder/'generation.json',dict(asset=row['id'],candidate=candidate,generation_id=generation,
          source='Hyper3D CLI Gen-2.5-High',reference=row['reference'],selected_file=chosen['name'],
          sha256=sha(folder/'model.glb'),bytes=len(data),status='downloaded',
          task_url='https://hyper3d.ai/workspace/rodin/'+generation))
    print('SAVED',row['id'],candidate,len(data),flush=True)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['status','submit','fetch'])
    p.add_argument('--ids',default='')
    p.add_argument('--candidate',choices=['a','b'],default='a')
    args=p.parse_args()
    initial,current=baseline()
    print('WALLET',json.dumps({k:v for k,v in current.items() if k!='principal_sha256'}),flush=True)
    if args.action=='status':return
    rows={r['id']:r for r in json.loads(SCOPE.read_text())['assets']}
    requested=args.ids.split(',')
    if not args.ids or len(requested)!=len(set(requested)) or any(aid not in rows for aid in requested):p.error('Provide unique scope IDs')
    for aid in requested:
        if args.action=='submit':submit(rows[aid],args.candidate,initial)
        else:fetch(rows[aid],args.candidate)


if __name__=='__main__':main()

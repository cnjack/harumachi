"""Submit distinct approved references through the bundled private Pixal client.

Maximum three active accepted jobs. Every accepted job ID is saved immediately;
restart resumes queries/downloads, never resubmits an accepted generation.
"""
import json,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CLIENT=Path('/Users/jack/.agents/skills/pixal3d-image-to-3d/scripts/pixal3d.py')
manifest=Path(sys.argv[1]);jobs=json.loads(manifest.read_text())['jobs']
def call(args):
    result=subprocess.run([sys.executable,str(CLIENT),*args],capture_output=True,text=True)
    if result.returncode:raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout)
for job in jobs:
    folder=ROOT/job['output'];folder.mkdir(parents=True,exist_ok=True)
while True:
    active=[];pending=[];done=0;failed=[]
    for job in jobs:
        folder=ROOT/job['output'];submitted=folder/'submission.json'
        if (folder/'model.glb').exists():done+=1;continue
        if not submitted.exists():pending.append(job);continue
        record=json.loads(submitted.read_text());status=call(['query',record['job_id']])
        (folder/'status.json').write_text(json.dumps(status,indent=2)+'\n')
        if status['status']=='completed':
            result=call(['download',record['job_id'],'--output',str(folder/'model.glb')]);(folder/'result.json').write_text(json.dumps(result,indent=2)+'\n');done+=1;print('COMPLETED',job['id'],record['job_id'],flush=True)
        elif status['status']=='failed':failed.append(job['id'])
        else:active.append(job)
    capacity=max(0,3-len(active))
    for job in pending[:capacity]:
        folder=ROOT/job['output']
        try:record=call(['submit',str(ROOT/job['reference']),'--resolution',str(job.get('resolution',1024)),'--seed',str(job.get('seed',42))])
        except RuntimeError as error:
            (folder/'submission-error.txt').write_text(str(error))
            if '429' in str(error):print('QUEUE_FULL',flush=True);break
            raise
        (folder/'submission.json').write_text(json.dumps(record,indent=2)+'\n');print('SUBMITTED',job['id'],record['job_id'],flush=True)
    print('BATCH',done,'/',len(jobs),'done; failed',failed,flush=True)
    if done+len(failed)==len(jobs):
        sys.exit(1 if failed else 0)
    time.sleep(30)

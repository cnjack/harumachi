"""Split an existing owned Rodin asset; preserve job identity and every GLB.
Paid submissions are never retried automatically. --resume only polls/downloads.
"""
import argparse,json,ssl,time,urllib.request
from pathlib import Path
from rodin_mcp import RodinMCP
from rodin_asset import unpack

ap=argparse.ArgumentParser();ap.add_argument('asset_id');ap.add_argument('out',type=Path);ap.add_argument('--resume');args=ap.parse_args()
args.out.mkdir(parents=True,exist_ok=True);client=RodinMCP();record_path=args.out/'generation.json'
if args.resume:
    record=json.loads(record_path.read_text())
    if record['generation_id']!=args.resume:raise RuntimeError('Job identity mismatch')
else:
    if record_path.exists():raise RuntimeError('Existing paid job: use --resume')
    request={'asset_id':args.asset_id,'strength':5,'explode_strength':0,'resolution':'High','reference_scale':.8,'geometry_file_format':'glb'}
    (args.out/'request.json').write_text(json.dumps(request,indent=2))
    accepted=unpack(client.call('rodin_generate_bang',request));record={'request':request,**accepted};record_path.write_text(json.dumps(record,indent=2))
    print('SUBMITTED',record['generation_id'],flush=True)
deadline=time.time()+1800
while time.time()<deadline:
    status=unpack(client.call('rodin_wait',{'generation_id':record['generation_id'],'timeout_seconds':30}))
    print(status['status'],status.get('stage',{}).get('name',''),flush=True)
    if status['status']=='completed':break
    if status['status']=='failed':raise RuntimeError('BANG failed; do not resubmit automatically')
else:raise RuntimeError('Read timeout; resume this job')
result=unpack(client.call('rodin_get_result',{'generation_id':record['generation_id']}));context=ssl.create_default_context(cafile='/opt/homebrew/etc/ca-certificates/cert.pem');files=[]
for entry in result['files']:
    name=Path(entry['name']).name
    if not name.lower().endswith(('.glb','.zip','.json')):continue
    with urllib.request.urlopen(entry['url'],context=context,timeout=120) as response:(args.out/name).write_bytes(response.read())
    files.append({'name':name,'bytes':(args.out/name).stat().st_size})
record.update(status='downloaded',files=files,display_url=result['display_url']);record_path.write_text(json.dumps(record,indent=2)+'\n');print('SAVED',json.dumps(files),flush=True)

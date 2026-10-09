"""Generate a Rodin asset from prepared references with explicit geometry settings.

Uses the existing rodin_mcp.py connection; does not register clients or switch
accounts. A submitted generation is never retried. Downloads the owned GLB after
completion and retains request/reference provenance without signed URLs.
"""
import argparse
import json
from pathlib import Path
import ssl
import time
import urllib.request
from rodin_mcp import RodinMCP


def unpack(response):
    if response.get('isError'):
        raise RuntimeError('Rodin tool returned an error; generation is not retried')
    if response.get('structuredContent') is not None:
        return response['structuredContent']
    for block in response.get('content', []):
        if block.get('type') == 'text':
            try:
                return json.loads(block['text'])
            except ValueError:
                continue
    raise RuntimeError('Unknown response; do not resubmit a generation')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refs', nargs='+', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--mesh', choices=['Raw','Quad'], default='Quad')
    parser.add_argument('--faces', type=int, default=50000)
    parser.add_argument('--tier', choices=['Gen-2.5-Medium','Gen-2.5-High','Gen-2.5-Extreme-Low'], default='Gen-2.5-High')
    parser.add_argument('--prompt')
    parser.add_argument('--resume', help='Read/wait/download this existing generation; never generate again')
    args = parser.parse_args()
    if not args.resume and (not args.refs or not 1 <= len(args.refs) <= 5 or any(not p.is_file() for p in args.refs)):
        parser.error('Provide one to five existing reference images')
    limit = 50000 if args.mesh == 'Quad' else 1000000
    if not 1000 <= args.faces <= limit:
        parser.error('Requested face count exceeds the mesh-mode range')
    args.out.mkdir(parents=True,exist_ok=True)
    client = RodinMCP()
    context = ssl.create_default_context(cafile='/opt/homebrew/etc/ca-certificates/cert.pem')
    request = {'tier':args.tier,'mesh_mode':args.mesh,'quality_override':args.faces,
               'texture_delight':True,'geometry_file_format':'glb'}
    record = {'references':[str(p.resolve()) for p in args.refs or []], 'request':request}
    if args.resume:
        previous = args.out/'generation.json'
        if previous.exists():
            record = json.loads(previous.read_text())
            if record.get('generation_id') != args.resume:
                raise RuntimeError('Output directory belongs to a different generation')
        else:
            record = {'generation_id':args.resume, 'references':record['references'], 'request':'unknown; recovering an existing task'}
    else:
        mime={'.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.webp':'image/webp'}
        files=[{'filename':p.name,'mime_type':mime[p.suffix.lower()],'size_bytes':p.stat().st_size} for p in args.refs]
        uploads=unpack(client.call('rodin_create_uploads',{'files':files}))['uploads']
        for path,upload in zip(args.refs,uploads):
            put=urllib.request.Request(upload['upload_url'],data=path.read_bytes(),headers=upload['headers'],method=upload['method'])
            with urllib.request.urlopen(put,context=context,timeout=60) as response:
                if response.status not in (200,201,204):raise RuntimeError('Reference upload failed')
        request['reference_upload_ids']=[u['upload_id'] for u in uploads]
        if args.prompt:request['prompt']=args.prompt
        (args.out/'request.json').write_text(json.dumps(record,ensure_ascii=False,indent=2))
        response=client.call('rodin_generate',request)
        (args.out/'submission-response.json').write_text(json.dumps(response,ensure_ascii=False,indent=2))
        accepted=unpack(response)
        record.update(accepted)
        (args.out/'generation.json').write_text(json.dumps(record,ensure_ascii=False,indent=2))
        print('SUBMITTED',record['generation_id'],flush=True)
    deadline=time.time()+1800
    while True:
        status=unpack(client.call('rodin_wait',{'generation_id':record['generation_id'],'timeout_seconds':30}))
        print(status['status'],status.get('stage',{}).get('name',''),flush=True)
        if status['status']=='completed':break
        if status['status']=='failed' or time.time()>deadline:
            raise RuntimeError('Generation did not complete; retain its ID and resume, do not resubmit')
    result=unpack(client.call('rodin_get_result',{'generation_id':record['generation_id']}))
    files=[f for f in result['files'] if f.get('name','').endswith('.glb')]
    selected=next((f for f in files if 'pbr' in f['name']),files[0])
    with urllib.request.urlopen(selected['url'],context=context,timeout=120) as response:
        (args.out/'model.glb').write_bytes(response.read())
    record.update(status='downloaded',display_url=result['display_url'],selected_file=selected['name'])
    (args.out/'generation.json').write_text(json.dumps(record,ensure_ascii=False,indent=2))
    print('SAVED',args.out/'model.glb',flush=True)

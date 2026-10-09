"""Submit each requested reference once; --fetch only resumes owned CLI generations."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import ssl
import subprocess
import time
import urllib.request

ROOT=Path(__file__).resolve().parents[2]
def cli(arguments,error_file=None):
    result=subprocess.run(['hyper3d','--output','json',*arguments],capture_output=True,text=True)
    if result.returncode:
        if error_file:error_file.write_text(result.stderr+'\n'+result.stdout)
        raise RuntimeError('Hyper3D CLI failed; inspect the saved error, do not blindly resubmit')
    return json.loads(result.stdout)
def work(asset,fetch):
    folder=ROOT/'art/models/raw'/(asset['id']+'_hyper3d');folder.mkdir(parents=True,exist_ok=True)
    record_path=folder/'submission.json'
    if not fetch:
        if record_path.exists():raise RuntimeError(asset['id']+': existing submission; use --fetch')
        request={'id':asset['id'],'reference':asset['reference'],'tier':'Gen-2.5-High','mesh_mode':'Raw','quality':500000,'texture_delight':True,'prompt':asset['prompt']}
        (folder/'request.json').write_text(json.dumps(request,ensure_ascii=False,indent=2))
        accepted=cli(['generate','--image',str(ROOT/asset['reference']),'--tier','Gen-2.5-High','--mesh-mode','Raw','--quality','500000','--texture-delight','--format','glb','--prompt',asset['prompt']],folder/'submission-error.log')
        record_path.write_text(json.dumps(accepted,indent=2));print('ACCEPTED',asset['id'],accepted['generation_id'],flush=True)
        return
    accepted=json.loads(record_path.read_text());generation=accepted['generation_id']
    if (folder/'model.glb').exists():
        if not (folder/'generation.json').exists():
            (folder/'generation.json').write_text(json.dumps({'id':asset['id'],'generation_id':generation,'reference':asset['reference'],'status':'downloaded','display_url':'https://hyper3d.ai/workspace/rodin/'+generation},indent=2))
        print('ALREADY_DOWNLOADED',asset['id'],flush=True);return
    deadline=time.monotonic()+1500
    while time.monotonic()<deadline:
        status=cli(['status',generation]);print(asset['id'],status['status'],status.get('stage',{}).get('name',''),flush=True)
        if status['status']=='completed':break
        if status['status']=='failed':raise RuntimeError(asset['id']+': failed; no resubmission')
        time.sleep(25)
    else:raise TimeoutError(asset['id']+': retain task ID and resume')
    result=cli(['result',generation]);files=[file for file in result['files'] if file['name'].lower().endswith('.glb')]
    chosen=next((file for file in files if 'pbr' in file['name'].lower()),files[0])
    context=ssl.create_default_context(cafile='/opt/homebrew/etc/ca-certificates/cert.pem')
    with urllib.request.urlopen(chosen['url'],context=context,timeout=180) as response:(folder/'model.glb').write_bytes(response.read())
    (folder/'generation.json').write_text(json.dumps({'id':asset['id'],'generation_id':generation,'reference':asset['reference'],'status':'downloaded','display_url':result.get('display_url','https://hyper3d.ai/workspace/rodin/'+generation),'selected_file':chosen['name']},indent=2))
    print('SAVED',asset['id'],(folder/'model.glb').stat().st_size,flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('manifest',type=Path);parser.add_argument('--fetch',action='store_true');args=parser.parse_args()
    assets=json.loads(args.manifest.read_text())
    if args.fetch:
        with ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(lambda asset:work(asset,True),assets))
    else:
        for asset in assets:work(asset,False)

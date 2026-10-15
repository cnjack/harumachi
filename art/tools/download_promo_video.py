#!/usr/bin/env python3
"""Resume an already-created Shuqi video through its standard HTTP Range content endpoint.

No generation requests are issued. Secrets stay in the designated skill credential file.
"""
import argparse, concurrent.futures, hashlib, json, sys, urllib.request, time
from pathlib import Path


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--workers',type=int,default=6,choices=range(1,9))
    p.add_argument('--connections',type=int,default=2,choices=range(1,5))
    p.add_argument('--skill-dir',type=Path,default=Path.home()/'.agents/skills/shuqi-video')
    args=p.parse_args();sys.path.insert(0,str(args.skill_dir/'scripts'))
    from video import Client
    state=json.loads((args.out/'job.json').read_text())
    assert state['base']=='https://ai.szshuqi.com' and state.get('id')
    client=Client(state['base'],(Path.home()/'.config/shuqi-video/api-key').read_text().strip())
    url=client.base+'/v1/videos/'+state['id']+'/content'
    def get(start,end):
        request=urllib.request.Request(url,headers={'Authorization':'Bearer '+client.key,'Range':f'bytes={start}-{end}'})
        return client.opener.open(request,timeout=60)
    with get(0,0) as r:
        assert r.status==206
        total=int(r.headers['Content-Range'].split('/')[-1]);assert len(r.read())==1
    parts=args.out/'download-parts';parts.mkdir(exist_ok=True)
    size=(total+args.workers-1)//args.workers
    (args.out/'download-size.json').write_text(json.dumps({'bytes':total,'workers':args.workers})+'\n')
    prefix=args.out/'video.mp4.part'
    if prefix.exists():
        available=prefix.stat().st_size
        with prefix.open('rb') as f:
            for index in range(args.workers):
                start=index*size; length=max(0,min(size,total-start,available-start))
                target=parts/f'{index:02d}.part'
                if length and (not target.exists() or target.stat().st_size<length):
                    f.seek(start);target.write_bytes(f.read(length))
    def fetch(index):
        start=index*size;end=min(total-1,start+size-1);target=parts/f'{index:02d}.part'
        failures=0
        while failures<12:
            offset=target.stat().st_size if target.exists() else 0
            if offset==end-start+1:return target
            assert 0<=offset<end-start+1
            chunk_end=min(end,start+offset+1024*1024-1)
            try:
                with get(start+offset,chunk_end) as r,target.open('ab') as f:
                    assert r.status==206 and r.headers['Content-Range']==f'bytes {start+offset}-{chunk_end}/{total}'
                    while block:=r.read1(64*1024):f.write(block)
                current=target.stat().st_size
                if current==end-start+1:
                    print(f'part {index+1}/{args.workers} complete',flush=True);return target
                failures=0 if current>offset else failures+1
            except (OSError, TimeoutError) as error:
                current=target.stat().st_size if target.exists() else 0
                failures=0 if current>offset else failures+1
                reason=getattr(error,'reason',error)
                print(f'part {index+1} interrupted: {type(reason).__name__}; retaining bytes',flush=True)
            if failures:time.sleep(min(3*failures,15))
        raise RuntimeError(f'Part {index+1} incomplete; resume this exact command')
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.connections) as pool:
        chunks=list(pool.map(fetch,range(args.workers)))
    assembled=args.out/'video-ranged.mp4.part'
    with assembled.open('wb') as f:
        for part in chunks:
            with part.open('rb') as chunk:
                while block:=chunk.read(1024*1024):f.write(block)
    assert assembled.stat().st_size==total
    with assembled.open('rb') as f:assert b'ftyp' in f.read(64)
    target=args.out/'video-ranged.mp4';assembled.replace(target)
    report={'job_id':state['id'],'bytes':total,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'workers':args.workers,'all_ranges_verified':True,'file':str(target.resolve()),'generation_submitted':False}
    (args.out/'range-verification.json').write_text(json.dumps(report,indent=2)+'\n')
    for part in chunks:part.unlink()
    parts.rmdir();print(json.dumps(report,indent=2))

if __name__=='__main__':main()

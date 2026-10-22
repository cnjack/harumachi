#!/usr/bin/env python3
"""Start isolated loopback ASR/TTS workers using already installed audio.cpp weights.
Never changes or stops the user's shared 8300 service. No downloads.
"""
import argparse,json,os,subprocess,time,urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def prepare(home,run):
    source=json.loads((home/'server.json').read_text())
    binary=home/'audio.cpp/build/macos-metal-release/bin/audiocpp_server'
    if not binary.is_file(): raise RuntimeError('Set MIO_AUDIOCPP_HOME to the existing audio.cpp service directory')
    run.mkdir(parents=True,exist_ok=True)
    configs=[]
    for kind,port,modelid in [('asr',8311,'qwen3-asr-0.6b'),('tts',8312,'qwen3-tts-custom')]:
        model=dict(next(m for m in source['models'] if m['id']==modelid))
        if kind=='tts':
            model.update(id='mio-tts-stream',mode='streaming')
            model['default_request_options']={'stream_chunk_policy':'grow','stream_frames_per_event':6}
        config={'host':'127.0.0.1','port':port,'backend':'metal','threads':4,'lazy_load':False,
                'max_loaded_models':1,'idle_unload_ms':0,'log_request_body':False,'ui':False,
                'ui_management':False,'models':[model]}
        path=run/f'{kind}.json';path.write_text(json.dumps(config,indent=2))
        configs.append((kind,port,path))
    return binary,configs

def health(port):
    try:
        with urllib.request.urlopen(f'http://127.0.0.1:{port}/v1/models',timeout=1) as r:
            return json.load(r)
    except Exception:return None

def start_frontend(run):
    python=ROOT/'.build/voice-frontend/bin/python';models=ROOT/'.build/voice-models'
    existing=health(8313)
    if existing:
        if existing.get('service')!='mio-voice-frontend':raise RuntimeError('Port 8313 belongs to another service')
        print('acoustic frontend already ready');return
    if not python.exists() or not (models/'silero_vad.onnx').exists():raise RuntimeError('Run python3 native/mio-companion/tools/setup_voice_frontend.py once for acoustic wake and VAD')
    with open(run/'frontend.log','ab',buffering=0) as log:
        proc=subprocess.Popen([str(python),str(ROOT/'tools/voice_frontend.py'),'--models',str(models)],stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
    (run/'frontend.pid').write_text(str(proc.pid));deadline=time.monotonic()+15
    while not health(8313):
        if proc.poll() is not None or time.monotonic()>deadline:raise RuntimeError('Acoustic frontend failed; see frontend.log')
        time.sleep(.1)
    print('acoustic frontend ready 8313',flush=True)

def main():
    p=argparse.ArgumentParser();p.add_argument('action',choices=['start','status']);p.add_argument('--home',type=Path,default=Path(os.environ.get('MIO_AUDIOCPP_HOME',str(Path.home()/'workpath/research/asr'))));p.add_argument('--run',type=Path,default=ROOT/'.build/voice-services');a=p.parse_args()
    if a.action=='status':
        print(json.dumps({str(port):health(port) for port in [8311,8312,8313]},ensure_ascii=False));return
    binary,configs=prepare(a.home,a.run)
    for kind,port,path in configs:
        existing=health(port)
        expected='mio-tts-stream' if kind=='tts' else 'qwen3-asr-0.6b'
        if existing:
            if expected not in [m['id'] for m in existing.get('data',[])]:raise RuntimeError(f'Port {port} belongs to another service')
            print(kind,'already ready');continue
        log=open(a.run/f'{kind}.log','ab',buffering=0)
        proc=subprocess.Popen([str(binary),'--config',str(path.resolve())],cwd=a.home,stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
        (a.run/f'{kind}.pid').write_text(str(proc.pid))
        deadline=time.monotonic()+60
        while not health(port):
            if proc.poll() is not None:raise RuntimeError(f'{kind} exited; see {a.run}/{kind}.log')
            if time.monotonic()>deadline:raise RuntimeError(f'{kind} startup timeout')
            time.sleep(.25)
        print(kind,'ready',port,flush=True)
    start_frontend(a.run)
if __name__=='__main__':main()

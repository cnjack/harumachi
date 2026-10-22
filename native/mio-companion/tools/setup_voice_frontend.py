#!/usr/bin/env python3
"""Install the optional local acoustic frontend in this project's build cache."""
import hashlib,subprocess,sys,tarfile,venv
from pathlib import Path

root=Path(__file__).resolve().parents[1]/'.build'
environment=root/'voice-frontend';models=root/'voice-models'
models.mkdir(parents=True,exist_ok=True)
if not (environment/'bin/python').exists():venv.create(environment,with_pip=True)
subprocess.run([str(environment/'bin/python'),'-m','pip','install','sherpa-onnx==1.13.8','numpy>=1.26,<3'],check=True)
name='sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20'
assets=[('kws.tar.bz2','https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/'+name+'.tar.bz2','68447f4fbc67e70eee3a93961f36e81e98f47aef73ce7e7ca00885c6cd3616a6'),('silero_vad.onnx','https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx','9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6')]
for filename,url,digest in assets:
    path=models/filename
    if not path.exists():subprocess.run(['/usr/bin/curl','--fail','--location','--max-time','120',url,'-o',str(path)],check=True)
    if hashlib.sha256(path.read_bytes()).hexdigest()!=digest:raise RuntimeError('Model checksum mismatch: '+filename)
if not (models/name).exists():
    with tarfile.open(models/'kws.tar.bz2') as archive:archive.extractall(models,filter='data')
print('Voice frontend installed in project cache. Run tools/voice_services.py start.')

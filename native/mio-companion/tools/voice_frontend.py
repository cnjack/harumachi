#!/usr/bin/env python3
"""Loopback acoustic wake-word + neural VAD. Audio stays in bounded RAM.
No microphone access here: the native app owns consent, AEC and capture.
"""
import argparse,json,re,time,threading
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import numpy as np
import sherpa_onnx

class Frontend:
    def __init__(self,root):
        model=root/'sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20'
        keywords=root/'mio-keywords.txt'
        # Mandarin xiao3 ling2: recognize pronunciation, not the rare character.
        keywords.write_text('x iǎo l íng @小澪\n',encoding='utf-8')
        suffix='epoch-13-avg-2-chunk-8-left-64'
        self.kws=sherpa_onnx.KeywordSpotter(tokens=str(model/'tokens.txt'),encoder=str(model/f'encoder-{suffix}.int8.onnx'),decoder=str(model/f'decoder-{suffix}.onnx'),joiner=str(model/f'joiner-{suffix}.int8.onnx'),keywords_file=str(keywords),num_threads=1,keywords_score=1.5,keywords_threshold=.2)
        self.config=sherpa_onnx.VadModelConfig();self.config.sample_rate=16000
        self.config.silero_vad.model=str(root/'silero_vad.onnx')
        self.config.silero_vad.min_silence_duration=.032
        self.config.silero_vad.min_speech_duration=.064
        self.sessions={}
    def push(self,identity,data):
        now=time.monotonic()
        self.sessions={k:v for k,v in self.sessions.items() if now-v[2]<30}
        if identity not in self.sessions:
            if len(self.sessions)>=4:raise ValueError('session limit')
            self.sessions[identity]=[self.kws.create_stream(),sherpa_onnx.VoiceActivityDetector(self.config,buffer_size_in_seconds=30),now]
        stream,vad,_=self.sessions[identity];self.sessions[identity][2]=now
        samples=np.frombuffer(data,dtype='<i2').astype(np.float32)/32768
        stream.accept_waveform(16000,samples);keyword=''
        while self.kws.is_ready(stream):
            self.kws.decode_stream(stream)
            value=self.kws.get_result(stream)
            if value:keyword=value;self.kws.reset_stream(stream)
        flags=[]
        for at in range(0,len(samples),512):
            vad.accept_waveform(samples[at:at+512]);flags.append(vad.is_speech_detected())
            while not vad.empty():vad.pop()
        return {'wake':bool(keyword),'speech':flags,'processingMs':(time.monotonic()-now)*1000}

def main():
    p=argparse.ArgumentParser();p.add_argument('--models',type=Path,required=True);p.add_argument('--port',type=int,default=8313);a=p.parse_args()
    frontend=Frontend(a.models);lock=threading.Lock()
    class Handler(BaseHTTPRequestHandler):
        protocol_version='HTTP/1.1'
        def log_message(self,*args):pass
        def reply(self,status,value):
            data=json.dumps(value).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
        def do_GET(self):self.reply(200,{'service':'mio-voice-frontend','sampleRate':16000,'chunkSamples':2560})
        def do_DELETE(self):
            with lock:frontend.sessions.pop(self.path.removeprefix('/frames/'),None)
            self.reply(200,{'closed':True})
        def do_POST(self):
            identity=self.path.removeprefix('/frames/')
            if self.headers.get('Origin') or not re.fullmatch(r'[A-Fa-f0-9-]{36}',identity) or self.headers.get('Content-Type')!='application/octet-stream' or self.headers.get('Content-Length')!='5120':
                self.close_connection=True;self.reply(400,{'error':'invalid audio frame'});return
            try:
                self.connection.settimeout(3);data=self.rfile.read(5120)
                if len(data)!=5120:raise ValueError('incomplete frame')
                with lock:result=frontend.push(identity,data)
                self.reply(200,result)
            except Exception:self.close_connection=True;self.reply(503,{'error':'frontend unavailable'})
    print('Mio acoustic frontend ready',flush=True)
    ThreadingHTTPServer(('127.0.0.1',a.port),Handler).serve_forever()
if __name__=='__main__':main()

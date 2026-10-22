#!/usr/bin/env python3
"""Deterministic LM transport fixture, never a substitute for model evaluation.
Run locally only; records synthetic request messages but never authorization.
"""
import argparse,json,time,threading
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path

def main():
    p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=8320);p.add_argument('--log',type=Path,required=True);a=p.parse_args()
    a.log.parent.mkdir(parents=True,exist_ok=True);lock=threading.Lock()
    class Handler(BaseHTTPRequestHandler):
        protocol_version='HTTP/1.1'
        def log_message(self,*args):pass
        def do_POST(self):
            body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
            with lock,a.log.open('a') as f:f.write(json.dumps(body,ensure_ascii=False)+'\n')
            if body['model']=='fixture-http-error':
                self.send_response(503);self.send_header('Content-Length','0');self.end_headers();return
            if body['model'].split('/')[-1].startswith('deepseek') and body.get('thinking')!={'type':'disabled'}:
                self.send_response(400);self.send_header('Content-Length','0');self.end_headers();return
            self.send_response(200);self.send_header('Content-Type','text/event-stream');self.send_header('Connection','close');self.end_headers()
            if body['model']=='fixture-truncated':
                self.wfile.write(b'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n');self.wfile.flush();self.close_connection=True;return
            messages=body['messages'];user=next(m['content'] for m in reversed(messages) if m['role']=='user')
            def send(delta,finish=None):
                event={'choices':[{'index':0,'delta':delta,'finish_reason':finish}]}
                wire=('data: '+json.dumps(event,ensure_ascii=False)+'\n\n').encode()
                # Deliberately split UTF-8 network writes across arbitrary bytes.
                for i in range(0,len(wire),7):self.wfile.write(wire[i:i+7])
                self.wfile.flush()
            try:
                if '进程' in user and messages[-1]['role']!='tool':
                    send({'tool_calls':[{'index':0,'id':'process_fixture','type':'function','function':{'name':'list_processes','arguments':'{"query":'}}]})
                    send({'tool_calls':[{'index':0,'function':{'arguments':'"Mio"}'}}]});send({},'tool_calls')
                else:
                    text='我在这里。今天辛苦了，我们慢慢聊。'
                    if messages[-1]['role']=='tool':
                        text='我查到了，桌面来信正在运行。' if 'MioCompanion' in messages[-1]['content'] else '暂时没有找到匹配的进程。'
                    if '很长' in user:text='别着急，我们可以一步一步来。'*20
                    for char in text:send({'content':char});time.sleep(.015)
                    send({},'stop')
                self.wfile.write(b'data: [DONE]\n\n');self.wfile.flush()
            except (BrokenPipeError,ConnectionResetError):pass
            self.close_connection=True
    ThreadingHTTPServer(('127.0.0.1',a.port),Handler).serve_forever()
if __name__=='__main__':main()

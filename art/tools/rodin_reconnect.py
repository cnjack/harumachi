"""Renew the existing Hyper3D OAuth connection, retaining account and workspace.

Uses the registered client, redirect URI and original scopes. Never registers a
client or accepts tokens belonging to a different principal or billing workspace.
"""
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import secrets
import ssl
import time
import urllib.parse
import urllib.request

base = Path.home()/'.copilot/mcp-oauth-config'
config_path = base/'07fbc0ff9dc7c70ab9e70b0c3fbfbc0ce3a505a1137549f5db3a0edca4b97285.json'
token_path = config_path.with_name(config_path.stem+'.tokens.json')
config=json.loads(config_path.read_text())
old=json.loads(token_path.read_text())
def claims(token):
    part=token.split('.')[1]
    return json.loads(base64.urlsafe_b64decode(part+'='*(-len(part)%4)))
original=claims(old['accessToken'])
context=ssl.create_default_context(cafile='/opt/homebrew/etc/ca-certificates/cert.pem')
with urllib.request.urlopen(config['authorizationServerUrl']+'/.well-known/oauth-authorization-server',context=context) as response:
    metadata=json.load(response)
verifier=secrets.token_urlsafe(48)
challenge=base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
state=secrets.token_urlsafe(24)
redirect=urllib.parse.urlparse(config['redirectUri'])
if redirect.hostname not in ('127.0.0.1','localhost'):
    raise RuntimeError('Only the existing loopback redirect is supported')
result={}
class Callback(BaseHTTPRequestHandler):
    def do_GET(self):
        query=urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if query.get('state') != [state]:
            self.send_response(400);self.end_headers();return
        result.update(query)
        self.send_response(200);self.end_headers()
        self.wfile.write(b'Hyper3D connection received. You may return to Codex.')
    def log_message(self,*args):
        pass
server=HTTPServer((redirect.hostname,redirect.port),Callback)
server.timeout=1
parameters={'response_type':'code','client_id':config['clientId'],'redirect_uri':config['redirectUri'],
            'scope':old.get('requestedScope','rodin:generate rodin:read offline_access'),
            'resource':config['resourceUrl'],'state':state,'code_challenge':challenge,'code_challenge_method':'S256'}
print('AUTHORIZE '+metadata['authorization_endpoint']+'?'+urllib.parse.urlencode(parameters),flush=True)
deadline=time.time()+300
while not result and time.time()<deadline:server.handle_request()
server.server_close()
if 'code' not in result:raise RuntimeError('Existing connection renewal was not completed')
body=urllib.parse.urlencode({'grant_type':'authorization_code','client_id':config['clientId'],
    'code':result['code'][0],'redirect_uri':config['redirectUri'],'code_verifier':verifier}).encode()
request=urllib.request.Request(metadata['token_endpoint'],data=body,headers={'Content-Type':'application/x-www-form-urlencoded'})
with urllib.request.urlopen(request,context=context,timeout=30) as response:new=json.load(response)
identity=claims(new['access_token'])
for field in ('sub','billing_workspace'):
    if identity.get(field)!=original.get(field):raise RuntimeError('Account or billing workspace differs; existing credentials were preserved')
scopes=set(new.get('scope','').split())
if not scopes.issubset(set(old.get('requestedScope','').split())):
    raise RuntimeError('Scope differs; existing credentials were preserved')
old.update(accessToken=new['access_token'],expiresAt=int(time.time())+int(new.get('expires_in',3600)))
if new.get('refresh_token'):old['refreshToken']=new['refresh_token']
old['scope']=new.get('scope',old['scope'])
temp=token_path.with_suffix('.renew.tmp')
fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as stream:json.dump(old,stream)
os.replace(temp,token_path)
print('RECONNECTED same account, same billing workspace, existing scopes',flush=True)

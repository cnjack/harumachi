"""Serve the local read-only asset browser on loopback, without exposing other directories."""
import argparse,http.server,functools,mimetypes
from pathlib import Path
from urllib.parse import unquote,urlsplit
ROOT=Path(__file__).resolve().parents[2]
mimetypes.add_type('text/plain','.md');mimetypes.add_type('model/gltf-binary','.glb');mimetypes.add_type('model/gltf+json','.gltf');mimetypes.add_type('text/javascript','.js')
class Handler(http.server.SimpleHTTPRequestHandler):
 def translate_path(self,path):
  relative=unquote(urlsplit(path).path).lstrip('/')
  target=(ROOT/(relative or 'art/library/index.html')).resolve()
  permitted=[ROOT/'art/library',ROOT/'art/models',ROOT/'game/assets/models',ROOT/'game/assets/fonts',ROOT/'art/references/characters_apose_20261004',ROOT/'art/poc/character_pipeline_20261003/tpose_20261004/static',ROOT/'docs/game-design']
  if not any(target==p or p in target.parents for p in permitted):return str(ROOT/'art/library/__not_found__')
  return str(target)
 def list_directory(self,path):self.send_error(403,'Directory listing disabled');return None
 def end_headers(self):
  self.send_header('Cache-Control','no-cache');self.send_header('X-Content-Type-Options','nosniff');super().end_headers()
 def log_message(self,format,*args):
  if args and str(args[1]).startswith(('4','5')):super().log_message(format,*args)
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,default=8787);args=parser.parse_args()
 server=http.server.ThreadingHTTPServer(('127.0.0.1',args.port),Handler)
 print('Asset library: http://127.0.0.1:'+str(args.port)+'/art/library/',flush=True)
 try:server.serve_forever()
 except KeyboardInterrupt:server.server_close()

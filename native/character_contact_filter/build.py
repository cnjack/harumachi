#!/usr/bin/env python3
"""Verify or rebuild the pinned macOS arm64 CAPI filter, without Godot."""
import argparse,hashlib,json,platform,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--verify-only',action='store_true')
 parser.add_argument('--out',type=Path)
 args=parser.parse_args()
 lock=json.loads((HERE/'source-lock.json').read_text())
 for name,expected in lock['compile_inputs'].items():
  if digest(HERE/name)!=expected:raise ValueError('Frozen compile input changed: '+name)
 if args.verify_only:
  print(json.dumps({'verified':True,'engine':lock['engine'],'godot_started':False}));return
 if args.out is None:parser.error('Choose explicit --out library path')
 if platform.system()!='Darwin' or platform.machine()!='arm64':raise ValueError('Only macOS arm64 is validated')
 if args.out.exists():raise ValueError('Choose a fresh output path; do not overwrite accepted library')
 args.out.parent.mkdir(parents=True,exist_ok=True)
 command=['clang','-std=c11','-O2','-g','-Wall','-Wextra','-Werror','-fno-fast-math','-ffp-contract=off','-fvisibility=hidden','-arch','arm64','-mmacosx-version-min=14.0','-dynamiclib','native_triangle_filter.c','-o',str(args.out.resolve())]
 subprocess.run(command,cwd=HERE,check=True)
 symbols=subprocess.run(['nm','-gU',str(args.out.resolve())],capture_output=True,text=True,check=True).stdout
 if ' T _native_triangle_filter_init' not in symbols:raise ValueError('Missing extension entry point')
 receipt={'engine':lock['engine'],'command':command,'compiler':subprocess.run(['clang','--version'],capture_output=True,text=True,check=True).stdout,'library_sha256':digest(args.out),'compile_inputs':lock['compile_inputs'],'godot_started':False,'scope':'Rebuilt binary requires numerical and native validation; not byte-identical claim across SDKs/signatures'}
 args.out.with_suffix(args.out.suffix+'.build.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print(json.dumps({'compiled':True,'library_sha256':receipt['library_sha256'],'godot_started':False}))
if __name__=='__main__':main()

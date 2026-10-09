"""Run one recorded command with a hard timeout and isolated game storage.

python run_evidence_command.py STEP_JSON LOG TIMEOUT [--save-dir=DIR] -- argv...
Keeps exact argv, wall time, timeout, exit code and parse-error evidence.
"""
import json,os,subprocess,sys,time
from pathlib import Path
split=sys.argv.index('--');options=sys.argv[1:split];command=sys.argv[split+1:]
result_path,log_path,limit=options[:3];env=os.environ.copy()
for option in options[3:]:
    if option.startswith('--save-dir='):env['HARUMACHI_SAVE_DIR']=option.split('=',1)[1]
start=time.monotonic();timed_out=False
with Path(log_path).open('w') as log:
    try:code=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=float(limit)).returncode
    except subprocess.TimeoutExpired:code=124;timed_out=True
text=Path(log_path).read_text(errors='replace')
report={'argv':command,'exit_code':code,'wall_seconds':round(time.monotonic()-start,2),'timeout':timed_out,'script_error':'SCRIPT ERROR' in text,'save_dir':env.get('HARUMACHI_SAVE_DIR'),'log':log_path}
Path(result_path).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
sys.exit(code)

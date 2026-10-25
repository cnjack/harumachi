"""Encode native Movie Maker frames using capture manifests; no simulated frames."""
from pathlib import Path
import argparse,json,subprocess
from PIL import Image,ImageDraw,ImageFont
p=argparse.ArgumentParser();p.add_argument('--evidence',required=True);p.add_argument('--stage',required=True);a=p.parse_args()
e=Path(a.evidence).resolve();stage=Path(a.stage).resolve();out=e/'videos';out.mkdir(exist_ok=True)
font=ImageFont.truetype(str(Path(__file__).resolve().parents[2]/'game/assets/fonts/LXGWWenKai-Medium.ttf'),28)
header=Image.new('RGB',(1440,64),'#162b32');d=ImageDraw.Draw(header);d.text((22,17),'修改前',font=font,fill='#f1ead9');d.text((742,17),'修改后',font=font,fill='#d2ecc7');header_path=out/'comparison-labels.png';header.save(header_path)
def run(args):subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y',*args],check=True)
for kind in ['fish','run']:
 parts=[]
 for version in ['before','after']:
  file=stage/(kind+'-'+version+'.avi');folder=e/version/('fish' if kind=='fish' else 'run-video');meta=json.loads((folder/'clip.json').read_text());cases=[meta] if kind=='fish' else meta['cases'];filters=[]
  for i,case in enumerate(cases):
   filters.append(f"[0:v]trim=start_frame={case['start_frame']}:end_frame={case['start_frame']+case['frames']},setpts=PTS-STARTPTS[v{i}]")
  joined=''.join(f'[v{i}]' for i in range(len(cases)))
  filters.append(joined+f'concat=n={len(cases)}:v=1:a=0[v]')
  target=out/(kind+'-'+version+'.mp4');run(['-i',str(file),'-filter_complex',';'.join(filters),'-map','[v]','-an','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(target)]);parts.append(target)
 crop='crop=1200:720:180:185,scale=720:432' if kind=='fish' else 'crop=960:1080:480:0,scale=720:810'
 filtergraph=f'[0:v]{crop}[b];[1:v]{crop}[a];[b][a]hstack=inputs=2,pad=1440:ih+64:0:64:color=0x162b32[body];[body][2:v]overlay=0:0:shortest=1[v]'
 target=out/(kind+'-comparison.mp4');run(['-i',str(parts[0]),'-i',str(parts[1]),'-loop','1','-i',str(header_path),'-filter_complex',filtergraph,'-map','[v]','-an','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(target)])
 info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-show_streams','-of','json',str(target)]));assert float(info['format']['duration'])>=5.9
 (out/(kind+'-probe.json')).write_text(json.dumps(info,indent=2));print(target,flush=True)

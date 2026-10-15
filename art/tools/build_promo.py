#!/usr/bin/env python3
"""Cut verified native gameplay and already-generated cinematic clips into the trailer.

--prepare renders only available sources; it never substitutes a missing AI video.
"""
import argparse, hashlib, json, subprocess
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
FONT=ROOT/'game/assets/fonts/LXGWWenKai-Medium.ttf'
FFMPEG='ffmpeg'

def caption(path,row,w,h):
    im=Image.new('RGBA',(w,h));draw=ImageDraw.Draw(im)
    def center(text,y,size):
        font=ImageFont.truetype(str(FONT),size)
        draw.text((w/2,y),text,font=font,anchor='mt',fill=(255,248,226,255),stroke_width=max(1,size//16),stroke_fill=(32,42,48,220))
    badge='动画宣传镜头' if row['kind']=='animation' else '游戏实录 · 开发中'
    if row['kind']!='title':center(badge,20,24)
    lines=row['caption'].splitlines()
    if row['kind']=='title':
        for text,y,size in zip(lines,[110,270,335],[126,38,34]):center(text,y,size)
    elif row['id']=='bridge_cg':
        for text,y,size in zip(lines,[810,888],[62,38]):center(text,y,size)
    else:
        for i,text in enumerate(lines):center(text,85+i*55,46)
    im.save(path)

def main():
    a=argparse.ArgumentParser(description=__doc__)
    a.add_argument('--plan',type=Path,default=ROOT/'art/manifests/promo_20261015.json')
    a.add_argument('--prepare',action='store_true')
    a.add_argument('--out',type=Path,default=ROOT/'outputs/harumachi-promo-20261015')
    args=a.parse_args();plan=json.loads(args.plan.read_text())
    if not args.prepare and plan.get('review_status','approved')!='approved':
        raise SystemExit('Trailer review is pending: '+plan['review_status'])
    args.out.mkdir(parents=True,exist_ok=True)
    clips=args.out/'edit-clips';clips.mkdir(exist_ok=True)
    w,h,fps=plan['width'],plan['height'],plan['fps'];pending=[];files=[]
    for index,row in enumerate(plan['shots']):
        source=ROOT/row['file'];target=clips/f'{index:02d}-{row["id"]}.mp4';files.append(target)
        if not source.is_file():pending.append(row['id']);continue
        signature=hashlib.sha256(json.dumps({'row':row,'size':source.stat().st_size,'mtime':source.stat().st_mtime_ns,'renderer':5},sort_keys=True).encode()).hexdigest()
        marker=target.with_suffix('.json')
        if target.exists() and marker.exists() and json.loads(marker.read_text()).get('signature')==signature:continue
        cap=target.with_suffix('.png');caption(cap,row,w,h)
        command=[FFMPEG,'-hide_banner','-loglevel','warning','-y']
        if source.suffix.lower() in ['.png','.jpg']:command+=['-loop','1','-framerate',str(fps)]
        else:command+=['-ss',str(row['start'])]
        command+=['-i',str(source),'-f','lavfi','-i','anullsrc=r=48000:cl=stereo','-loop','1','-i',str(cap)]
        d=row['duration'];fc=f'[0:v]scale={w}:{h}:force_original_aspect_ratio=increase:in_range=auto:out_range=tv:out_color_matrix=bt709,crop={w}:{h},fps={fps},setsar=1,setpts=PTS-STARTPTS[v];[2:v]format=rgba,fade=t=in:st=0:d=0.25:alpha=1,fade=t=out:st={d-.25}:d=0.25:alpha=1[c];[v][c]overlay=0:0:shortest=1,format=yuv420p,setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709[out]'
        command+=['-filter_complex',fc,'-map','[out]','-map','0:a:0' if row['game_audio'] else '1:a:0','-af','aresample=48000,volume=0.32','-t',str(d),'-c:v','libx264','-crf','18','-preset','fast','-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-c:a','aac','-b:a','160k','-movflags','+faststart',str(target)]
        subprocess.run(command,check=True)
        marker.write_text(json.dumps({'signature':signature,'source':row['file'],'source_start':row['start'],'duration':d})+'\n')
        print('cut',row['id'],flush=True)
    if pending:
        print('pending sources:',', '.join(pending))
        if not args.prepare:raise SystemExit(2)
    if args.prepare:return
    command=[FFMPEG,'-hide_banner','-loglevel','warning','-y','-filter_complex_threads','2']
    for file in files:command+=['-i',str(file)]
    command+=['-i',str(ROOT/plan['music'])]
    fc=[]
    for i in range(len(files)):
        fc+=[f'[{i}:v]settb=AVTB,setpts=PTS-STARTPTS[v{i}]',f'[{i}:a]aresample=48000,asetpts=PTS-STARTPTS[a{i}]']
    pv,pa,offset='v0','a0',plan['shots'][0]['duration']-plan['transition_seconds']
    for i in range(1,len(files)):
        xf=plan['transition_seconds'];fc+=[f'[{pv}][v{i}]xfade=transition=fade:duration={xf}:offset={offset:.4f}[x{i}]',f'[{pa}][a{i}]acrossfade=d={xf}:c1=tri:c2=tri[y{i}]'];pv,pa=f'x{i}',f'y{i}';offset+=plan['shots'][i]['duration']-xf
    duration=plan['duration_seconds'];tempo=plan['music_original_seconds']/duration
    fc+=[f'[{len(files)}:a]atempo={tempo:.9f},aresample=48000,atrim=0:{duration},asetpts=PTS-STARTPTS,afade=t=in:d=0.6,afade=t=out:st={duration-1.8}:d=1.8[music]',f'[{pa}][music]amix=inputs=2:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[aout]',f'[{pv}]fade=t=in:d=0.35,fade=t=out:st={duration-.5}:d=0.5,trim=duration={duration},format=yuv420p,setparams=range=limited:color_primaries=bt709:color_trc=bt709:colorspace=bt709[vout]']
    target=args.out/'harumachi-trailer-90s.mp4'
    command+=['-filter_complex',';'.join(fc),'-map','[vout]','-map','[aout]','-t',str(duration),'-r',str(fps),'-c:v','libx264','-crf','18','-preset','medium','-pix_fmt','yuv420p','-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-c:a','aac','-b:a','192k','-movflags','+faststart',str(target)]
    (args.out/'edit-command.json').write_text(json.dumps(command,ensure_ascii=False,indent=2)+'\n')
    subprocess.run(command,check=True);print(target)

if __name__=='__main__':main()

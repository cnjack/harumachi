#!/usr/bin/env python3
"""Record and verify explicit native PNG frames, then encode a silent 1080p POC.

Unlike MovieMaker's window clock, every exported image comes from force_draw.
The script rejects missing/shifted source samples and compares decoded video
pixels to exact PNGs. Removes only its own temporary frames after verification.
"""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]

def sha(p):
    with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def project_inputs(project):
    paths=[project/n for n in ['project.godot','viewer.gd','main.tscn','showcase.json','source-motion.json']]
    paths+=list((project/'assets').glob('*.glb'))+list((project/'assets').glob('*.import'))
    return {str(p.relative_to(project)):sha(p) for p in sorted(paths)}

def encode(folder,project):
    journal=json.loads((folder/'movie-journal.json').read_text());rows=journal['frames'];config=json.loads((project/'showcase.json').read_text())
    expected=[(c['motion_id'],i) for c in config['clips'] for i in range(c['display_frames'])]
    assert [(r['motion_id'],r['source_frame_index']) for r in rows]==expected
    assert journal['fps']==30 and journal['explicit_native_viewport_draw'] and journal['png_frame_count']==len(rows)
    assert not journal['failures']
    for row in rows:
        assert abs(row['source_time']-row['source_frame_index']/30)<1e-6
        for actor,state in row['actors'].items():
            if state.get('source_proxy'):continue
            assert not state['game_modifiers_attached'] and abs(state['clip_time']-row['source_time'])<.0001
    files=sorted((folder/'frames').glob('*.png'));assert len(files)==len(rows)
    hashes={}
    for i,p in enumerate(files):
        assert p.name==f'{i:06d}.png'
        with Image.open(p) as im:assert im.size==(1920,1080)
        hashes[p.name]=sha(p)
    video=folder/'video.mp4';assert not video.exists()
    ffmpeg=shutil.which('ffmpeg');assert ffmpeg
    command=[ffmpeg,'-v','error','-filter_threads','2','-framerate','30','-i',str(folder/'frames/%06d.png'),'-vf','scale=1920:1080:in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p','-an','-c:v','libx264','-threads','2','-preset','fast','-crf','18','-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-movflags','+faststart',str(video)]
    subprocess.run(command,check=True)
    chosen=[i for i,r in enumerate(rows) if r['source_frame_index'] in [30,120,180,300]]
    indices=sorted({i+d for i in chosen for d in [-1,0,1]});select='+'.join('eq(n\\,'+str(i)+')' for i in indices)
    data=subprocess.check_output([ffmpeg,'-v','error','-i',str(video),'-vf',f'select={select},scale=320:180:flags=bilinear,format=rgb24','-fps_mode','passthrough','-f','rawvideo','-'])
    decoded=dict(zip(indices,np.frombuffer(data,np.uint8).reshape(len(indices),180,320,3).astype(float)))
    matches=[]
    for i in chosen:
        data=subprocess.check_output([ffmpeg,'-v','error','-i',str(files[i]),'-vf','scale=320:180:flags=bilinear,format=rgb24','-frames:v','1','-f','rawvideo','-'])
        native=np.frombuffer(data,np.uint8).reshape(180,320,3).astype(float)
        errors={str(d):float(np.abs(native-decoded[i+d]).mean()) for d in [-1,0,1]}
        assert errors['0']<3 and errors['0']<=min(errors.values())+.03,errors
        matches.append({'frame':i,'mean_rgb_error_offsets':errors})
    means={str(d):float(np.mean([r['mean_rgb_error_offsets'][str(d)] for r in matches])) for d in [-1,0,1]}
    assert means['0']<min(means['-1'],means['1']),means
    probe=json.loads(subprocess.check_output([shutil.which('ffprobe'),'-v','error','-count_frames','-show_streams','-show_format','-of','json',str(video)]))
    assert len(probe['streams'])==1
    stream=probe['streams'][0]
    assert (stream['width'],stream['height'],stream['r_frame_rate'],stream['pix_fmt'])==(1920,1080,'30/1','yuv420p')
    assert int(stream['nb_read_frames'])==len(rows) and abs(float(probe['format']['duration'])-len(rows)/30)<.001
    subprocess.run([ffmpeg,'-v','error','-xerror','-err_detect','explode','-i',str(video),'-f','null','-'],check=True)
    receipt={'passed':True,'take':journal['take'],'frames':len(rows),'seconds':len(rows)/30,'silent':True,'resolution':[1920,1080],
             'actual_native_png_per_sample':True,'no_resampling_or_generated_padding':True,'same_frame_pixel_checks':matches,'mean_rgb_error_offsets':means,
             'source_config_sha256':journal['source_config_sha256'],'video_sha256':sha(video),'journal_sha256':sha(folder/'movie-journal.json'),
             'frame_sha256':hashes,'probe':probe,'strict_full_decode_passed':True,'bytes':video.stat().st_size,'sha256':sha(video),'stills':json.loads((folder/'native-stills.json').read_text())['shots'],'command':command,'visual_quality_acceptance':False}
    (folder/'media-verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
    sections=[]
    for clip in config['clips']:
        subset=[r for r in rows if r['motion_id']==clip['motion_id']]
        sections.append({'motion_id':clip['motion_id'],'official_mode':clip['official_mode'],'label':clip['label'],'frames':len(subset),'view_counts':{v:sum(r['view']==v for r in subset) for v in ['front','right','oblique']}})
    (folder/'journal-verification.json').write_text(json.dumps({'passed':True,'frames':len(rows),'sections':sections,'actual_native_png_frames':True},indent=2)+'\n')
    shutil.rmtree(folder/'frames')
    print('VERIFIED',journal['take'],len(rows),'frames',flush=True)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--project',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--takes',nargs='+',required=True);p.add_argument('--encode-only',action='store_true');args=p.parse_args()
    project=args.project.resolve();output=args.output.resolve();assert ROOT/'art/poc/motionbricks_20261018' in project.parents
    output.mkdir(parents=True,exist_ok=True)
    receipt=output/'project-inputs.json';inputs=project_inputs(project)
    if receipt.exists():assert json.loads(receipt.read_text())==inputs,'Recording project changed'
    else:receipt.write_text(json.dumps(inputs,indent=2)+'\n')
    for take in args.takes:
        assert take in ['solo-'+a for a in ['sora','ren','haru','mio','aoi','tanaka','kazuko']]+['group-three','group-four','source-motion']
        folder=output/take
        if not args.encode_only:
            if folder.exists():raise ValueError('Use a new recording directory: '+str(folder))
            folder.mkdir(parents=True)
            command=[str(ROOT/'tools/godot'),'--path',str(project),'--audio-driver','Dummy','--screen','0','--position','50,80','--resolution','1280x720','--','--take='+take,'--record','--out='+str(folder)]
            env=dict(os.environ,HARUMACHI_SAVE_DIR=str(folder/'isolated-save'))
            with (folder/'native.log').open('w') as f:subprocess.run(command,check=True,stdout=f,stderr=subprocess.STDOUT,env=env,timeout=900)
            log=(folder/'native.log').read_text();assert 'SCRIPT ERROR' not in log and 'SHADER ERROR' not in log
            assert '"no_focus":true' in log
        encode(folder,project)
        assert project_inputs(project)==inputs,'Recording inputs changed during native rendering'

if __name__=='__main__':main()

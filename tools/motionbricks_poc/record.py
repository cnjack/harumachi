#!/usr/bin/env python3
"""Record prepared, isolated MotionBricks POC takes (parent schedules engines).

Native MovieMaker -> exact journal trim -> BT.709 H.264 -> strict full decode.
No procedural motion substitution, game project loading, virtual display or sound.
"""
from __future__ import annotations
import argparse, ast, collections, hashlib, json, math, os, re, shutil, signal, subprocess, sys, tempfile, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
POC=ROOT/'art/poc/motionbricks_20261018'
IDS=['sora','ren','haru','mio','aoi','tanaka','kazuko']
TAKES=['solo-'+i for i in IDS]+['group-three','group-four','source-motion']

def sha(p):
 with Path(p).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def read(p):return json.loads(Path(p).read_text())
def write(p,data):Path(p).write_text(json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
def saves():
 root=Path.home()/'Library/Application Support/晴町日常'
 return {str(p.relative_to(root)):sha(p) for p in sorted(root.rglob('*')) if p.is_file() and not {'logs','shader_cache'}.intersection(p.relative_to(root).parts)}
def production():
 game=ROOT/'game'
 return {'gd':{str(p.relative_to(game)):sha(p) for p in sorted(game.rglob('*.gd'))},'data':{p.name:sha(p) for p in sorted((game/'data').glob('*.json'))},'models':{p.name:sha(p) for p in sorted((game/'assets/models').glob('CH_*.glb'))},'native':sha(game/'addons/character_contact_filter/bin/libnative_triangle_filter.arm64.dylib')}
def project_inputs(project):
 return {str(p.relative_to(project)):sha(p) for p in sorted(project.rglob('*')) if p.is_file() and '.godot' not in p.relative_to(project).parts and p.suffix in {'.gd','.godot','.tscn','.glb','.ttf','.json','.gdshader','.cfg'}}
def finite(value):
 if isinstance(value,(int,float)):return math.isfinite(value)
 if isinstance(value,list):return all(finite(x) for x in value)
 if isinstance(value,dict):return all(finite(x) for x in value.values())
 return True

def run(command,folder,env,timeout):
 folder.mkdir(parents=True,exist_ok=True);start=time.monotonic();process=None
 with (folder/'engine.log').open('w') as log:
  try:
   process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,env=env,cwd=ROOT)
   deadline=time.monotonic()+timeout
   while process.poll() is None:
    try:process.wait(timeout=min(1,max(.01,deadline-time.monotonic())))
    except subprocess.TimeoutExpired:
     current=(folder/'engine.log').read_text(errors='replace')
     if 'SCRIPT ERROR' in current or 'SHADER ERROR' in current:raise RuntimeError('Engine script/shader error; see '+str(folder/'engine.log'))
     if time.monotonic()>=deadline:raise TimeoutError('Engine exceeded '+str(timeout)+' seconds')
   code=process.returncode
  except BaseException:
   if process is not None and process.poll() is None:
    process.terminate()
    try:process.wait(timeout=10)
    except subprocess.TimeoutExpired:process.kill();process.wait(timeout=10)
   raise
 text=(folder/'engine.log').read_text(errors='replace')
 errors=[line for line in text.splitlines() if line.startswith('ERROR:')]
 allowed_shutdown=all('resources still in use at exit' in e for e in errors)
 editor_theme="ERROR: Failed to load text editor theme file 'Adaptive': File not found"
 known_editor_errors=[e for e in errors if '--editor' in command and '--import' in command and e==editor_theme]
 unexpected_errors=[e for e in errors if e not in known_editor_errors and 'resources still in use at exit' not in e]
 report={'command':command,'exit':code,'elapsed_seconds':time.monotonic()-start,'raw_error_lines':errors,'script_error':'SCRIPT ERROR' in text,'shader_error':'SHADER ERROR' in text,'raw_errors_only_shutdown_resource_lifetime':allowed_shutdown,'known_import_editor_theme_errors':known_editor_errors,'unexpected_error_lines':unexpected_errors}
 write(folder/'process.json',report)
 if code or report['script_error'] or report['shader_error'] or unexpected_errors:raise RuntimeError('Native run failed; inspect '+str(folder/'engine.log'))
 return text

def verify_journal(journal,config,take):
 assert journal['take']==take and journal['fps']==30 and journal['failures']==[] and journal['no_game_controllers']
 assert journal['engine']=='4.8-dev7 (official)'
 expected=sum(x['display_frames'] for x in config['clips']);rows=journal['frames'];assert len(rows)==expected
 first=rows[0]['drawn_frame'];assert [r['drawn_frame'] for r in rows]==list(range(first,first+expected))
 assert len(journal['sections'])==len(config['clips'])
 selected=['source'] if take=='source-motion' else ['sora','ren','tanaka'] if take=='group-three' else ['mio','haru','aoi','kazuko'] if take=='group-four' else [take.removeprefix('solo-')]
 summaries=[];offset=0
 for clip,section in zip(config['clips'],journal['sections']):
  count=clip['display_frames'];block=rows[offset:offset+count];offset+=count
  assert section['clip']==clip['clip'] and section['display_frames']==count
  assert section['end_drawn_inclusive']-section['start_drawn_exclusive']==count
  assert block[0]['drawn_frame']==section['start_drawn_exclusive']+1 and block[-1]['drawn_frame']==section['end_drawn_inclusive']
  views=[['front','right','oblique'][min(2,k*3//count)] for k in range(count)]
  assert [r['view'] for r in block]==views
  assert all(r['clip']==clip['clip'] and sorted(r['actors'])==sorted(selected) and finite(r['actors']) for r in block)
  actor_reports={}
  for actor in selected:
   states=[r['actors'][actor] for r in block];positions=[x['root'] for x in states];assert all(len(x)==3 for x in positions)
   if actor=='source':
    assert all(len(x['joint_positions'])==34 for x in states)
    times=[x['source_time'] for x in states]
   else:
    assert all(x['assigned_clip']==clip['clip'] or x['assigned_clip'].endswith('/'+clip['clip']) for x in states)
    assert all(len(x['bones'])==17 and all(len(v)==12 for v in x['bones'].values()) for x in states)
    assert all(x['original_materials'] and not x['game_modifiers_attached'] for x in states)
    times=[x['clip_time'] for x in states]
   assert min(times)>=0 and max(times)<=clip['duration_s']+.05
   assert [row['source_frame_index'] for row in block]==list(range(count))
   for frame,time_value in enumerate(times):assert abs(time_value-frame/30)<2e-5, (actor,clip['clip'],frame,time_value)
   if actor!='source':assert all(x['animation_callback_mode_process']==2 for x in states)
   assert abs(times[0])<2e-5 and abs(times[-1]-(count-1)/30)<2e-5
   assert max(times)>=max(0,clip['duration_s']-2/30), (actor,clip['clip'],max(times),clip['duration_s'])
   expected_times=[k/30 for k in range(count)]
   assert max(abs(t-e) for t,e in zip(times,expected_times))<1e-5, (actor,clip['clip'],'missing/duplicated source sample times')
   actor_reports[actor]={'observed_time_range':[min(times),max(times)],'unique_time_samples':len(set(times)),'root_first':positions[0],'root_last':positions[-1],'root_net_displacement_m':math.dist(positions[0],positions[-1]),'root_sampled_path_length_m':sum(math.dist(a,b) for a,b in zip(positions,positions[1:])),'pose_samples_finite':True,'nonplaying_samples':sum(not x.get('playing',True) for x in states),'every_source_sample_exact_n_over_30':True,'source_proxy':actor=='source'}
  summaries.append({'motion_id':clip['motion_id'],'official_mode':clip['official_mode'],'frames':count,'duration_s':count/30,'source_duration_s':clip['duration_s'],'view_counts':dict(collections.Counter(views)),'actors':actor_reports,'reset_at_clip_boundary_disclosed':True,'no_cross_clip_transition_claim':True})
 return {'frames':expected,'continuous_drawn_frames':True,'exact_30fps_source_time_coverage':True,'drawn_first_inclusive':first,'drawn_end_exclusive':first+expected,'sections':summaries,'actors':selected,'all_real_source_clips_shown_to_last_sample':True,'native_AP_manual_exact_sample_clock':True,'native_png_AVI_frame_mapping_requires_independent_confirmation':True,'original_source_looping_not_forced':True,'source_config_sha256':journal['source_config_sha256']}

def movie_frame_alignment(folder,ffmpeg):
 # Match real post-draw PNGs to decoded AVI frames instead of assuming that an
 # engine completed-frame counter is the same as a zero-based movie frame ID.
 shots=read(folder/'native-stills.json')['shots']
 selected=[s for s in shots if s['view']=='right'][:3]
 assert selected
 offsets=[-2,-1,0,1]
 ids=sorted({s['drawn_frame']+d for s in selected for d in offsets})
 selection='+'.join('eq(n\\,'+str(n)+')' for n in ids)
 size=320*180*3
 command=[ffmpeg,'-v','error','-i',str(folder/'native.avi'),'-vf',f'select={selection},scale=320:180:flags=bilinear,format=rgb24','-fps_mode','passthrough','-f','rawvideo','-']
 frames=subprocess.check_output(command,timeout=180)
 assert len(frames)==len(ids)*size
 decoded={n:frames[i*size:(i+1)*size] for i,n in enumerate(ids)}
 measurements=[]
 for shot in selected:
  png=subprocess.check_output([ffmpeg,'-v','error','-i',str(folder/shot['file']),'-vf','scale=320:180:flags=bilinear,format=rgb24','-frames:v','1','-f','rawvideo','-'],timeout=30)
  assert len(png)==size
  scores={d:sum(abs(a-b) for a,b in zip(png,decoded[shot['drawn_frame']+d]))/size for d in offsets}
  measurements.append({'file':shot['file'],'drawn_frame':shot['drawn_frame'],'mean_absolute_rgb_error':scores})
 aggregate={d:sum(m['mean_absolute_rgb_error'][d] for m in measurements)/len(measurements) for d in offsets}
 best=min(aggregate,key=aggregate.get)
 report={'engine_counter_to_avi_zero_index_offset':best,'method':'Decoded AVI vs same-post-draw native PNG, bilinear320x180 RGB MAE','candidate_average_errors':aggregate,'samples':measurements,'ffmpeg_command':command}
 write(folder/'movie-frame-alignment.json',report)
 assert best in [-1,0], 'Unexpected movie frame offset; inspect source PNG/AVI mapping'
 assert aggregate[best]<3.0, 'Native PNG and movie pixels diverge'
 return best

def encode(folder,journal_result,ffmpeg,ffprobe):
 raw=folder/'native.avi';video=folder/'video.mp4';offset=movie_frame_alignment(folder,ffmpeg);first=journal_result['drawn_first_inclusive']+offset;last=journal_result['drawn_end_exclusive']+offset;n=journal_result['frames']
 assert raw.exists() and not video.exists()
 vf=f'trim=start_frame={first}:end_frame={last},setpts=PTS-STARTPTS,scale=1920:1080:in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p'
 encode_command=[ffmpeg,'-hide_banner','-loglevel','error','-y','-i',str(raw),'-vf',vf,'-an','-c:v','libx264','-preset','fast','-crf','18','-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-bsf:v','h264_metadata=colour_primaries=1:transfer_characteristics=1:matrix_coefficients=1:video_full_range_flag=0','-movflags','+faststart',str(video)]
 subprocess.run(encode_command,check=True,timeout=600)
 probe_command=[ffprobe,'-v','error','-count_frames','-show_streams','-show_format','-of','json',str(video)]
 probe=json.loads(subprocess.check_output(probe_command,text=True,timeout=180));streams=probe['streams'];assert len(streams)==1;stream=streams[0]
 assert (stream['width'],stream['height'],stream['r_frame_rate'],stream['pix_fmt'],int(stream['nb_read_frames']))==(1920,1080,'30/1','yuv420p',n)
 assert (stream['color_range'],stream['color_space'],stream['color_transfer'],stream['color_primaries'])==('tv','bt709','bt709','bt709')
 assert abs(float(probe['format']['duration'])-n/30)<.001
 decode_command=[ffmpeg,'-v','error','-xerror','-err_detect','explode','-i',str(video),'-f','null','-'];subprocess.run(decode_command,check=True,timeout=180)
 stills=[];offset=0
 for index,section in enumerate(journal_result['sections']):
  count=section['frames']
  for view_index,view in enumerate(['front','right','oblique']):
   frame=offset+min(count-1,int((view_index+.5)*count/3));second=frame/30
   still=folder/(f'{index+1:02d}-'+re.sub('[^A-Za-z0-9_.-]','_',section['motion_id'])+'-'+view+'.png')
   subprocess.run([ffmpeg,'-v','error','-y','-ss',str(second),'-i',str(video),'-frames:v','1',str(still)],check=True,timeout=30)
   stills.append({'motion_id':section['motion_id'],'view':view,'second':second,'video_frame_zero_based':frame,'file':still.name,'sha256':sha(still)})
  offset+=count
 result={'probe':probe,'strict_full_decode_passed':True,'encode_command':encode_command,'strict_decode_command':decode_command,'sha256':sha(video),'bytes':video.stat().st_size,'trim_start_inclusive':first,'trim_end_exclusive':last,'native_avi_bytes':raw.stat().st_size,'stills':stills,'audio':'Dummy native recording; encoded video has no audio stream','raw_avi_wav_removed_after_successful_verification':True}
 raw.unlink();wav=raw.with_suffix('.wav')
 if wav.exists():wav.unlink()
 write(folder/'media-verification.json',result)
 return {'video':str(video),'sha256':result['sha256'],'frames':n,'seconds':n/30,'bytes':result['bytes']}

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--project',type=Path,default=POC/'godot');p.add_argument('--out',type=Path,default=ROOT/'evidence/motionbricks_poc_20261018/movie');p.add_argument('--take',choices=TAKES,default='solo-sora');p.add_argument('--all',action='store_true');p.add_argument('--check-only',action='store_true');p.add_argument('--stills-only',action='store_true',help='Native same-frame screenshot pass; no AVI or ffmpeg is started')
 args=p.parse_args();project=args.project.resolve();out=args.out.resolve();assert POC in project.parents
 config=read(project/'showcase.json');prepared=read(project/'preparation-receipt.json');inputs=project_inputs(project)
 assert '[autoload]' not in (project/'project.godot').read_text() and 'HarumachiMotionBricksPOC' in (project/'project.godot').read_text()
 assert sha(project/'viewer.gd')==prepared['viewer_source_sha256'];assert sha(Path(prepared['retarget_manifest']['path']))==prepared['retarget_manifest']['sha256']==config['input_manifest_sha256']
 for actor,row in prepared['models'].items():assert sha(project/'assets'/('CH_'+actor+'.glb'))==row['sha256']
 for path,digest in prepared['source_files'].items():assert sha(Path(path))==digest
 ast.parse(Path(__file__).read_text());before=production();before_saves=saves();takes=TAKES if args.all else [args.take]
 for take in takes:
  required=['source'] if take=='source-motion' else ['sora','ren','tanaka'] if take=='group-three' else ['mio','haru','aoi','kazuko'] if take=='group-four' else [take.removeprefix('solo-')]
  assert required==['source'] or set(required).issubset(config['actors']), 'Take includes missing smoke-only actors'
 preflight={'project':str(project),'takes':takes,'clips':len(config['clips']),'frames_per_take':sum(x['display_frames'] for x in config['clips']),'seconds_per_take':sum(x['display_frames'] for x in config['clips'])/30,'no_game_autoloads':True,'stills_only':args.stills_only,'viewer_sha256':sha(project/'viewer.gd'),'production_gd':len(before['gd']),'production_models':len(before['models']),'production_data_json':len(before['data']),'default_save_files':len(before_saves),'virtual_display_created':False,'audio_driver':'Dummy','source_proxy':'real generated G1 FK34-joint bone/point proxy; no human source-model claim'}
 if args.check_only:print(json.dumps(preflight,ensure_ascii=False,indent=2));return
 assert not out.exists(), 'Choose a new immutable output path';out.mkdir(parents=True)
 write(out/'preflight.json',preflight);write(out/'production-before.json',before);write(out/'default-save-before.json',before_saves);write(out/'project-inputs.json',inputs)
 ffmpeg=shutil.which('ffmpeg');ffprobe=shutil.which('ffprobe');assert args.stills_only or (ffmpeg and ffprobe)
 completed=False;error=None;stage=None;deliveries=[]
 def stop(signum,_frame):raise KeyboardInterrupt('POC recording interrupted by signal '+str(signum))
 previous=signal.signal(signal.SIGTERM,stop)
 try:
  with tempfile.TemporaryDirectory(prefix='harumachi-motionbricks-viewer-') as temporary:
   stage=Path(temporary);cow=stage/'godot';subprocess.run(['cp','-cR',str(project),str(cow)],check=True)
   assert project_inputs(cow)==inputs
   write(out/'stage.json',{'temporary_project':str(cow),'same_source_inputs':True,'source_project':str(project),'no_game_project_loaded':True})
   env=dict(os.environ,HARUMACHI_SAVE_DIR=str(stage/'unused-independent-poc-save'))
   run([str(ROOT/'tools/godot'),'--headless','--path',str(cow),'--editor','--import','--audio-driver','Dummy'],out/'import',env,300)
   subprocess.run([sys.executable,str(Path(__file__).with_name('configure_imports.py')),'--project',str(cow),'--receipt',str(out/'import-options.json')],check=True,timeout=60)
   # A fresh editor --import can reuse cached scenes after only a sidecar edit.
   # Discard only this run's private generated cache so the chosen key settings
   # are actually applied to all model copies on the second import.
   shutil.rmtree(cow/'.godot')
   run([str(ROOT/'tools/godot'),'--headless','--path',str(cow),'--editor','--import','--audio-driver','Dummy'],out/'import-exact-keys',env,300)
   write(out/'final-import-sidecars.json',{p.name:p.read_text() for p in (cow/'assets').glob('*.glb.import')})
   for take in takes:
    folder=out/take;folder.mkdir();command=[str(ROOT/'tools/godot'),'--path',str(cow),'--screen','0','-t','--position','1640,50','--resolution','1920x1080','--audio-driver','Dummy']
    if not args.stills_only:command+=['--write-movie',str(folder/'native.avi')]
    command+=['--fixed-fps','30','res://main.tscn','--','--stills' if args.stills_only else '--record','--take='+take,'--out='+str(folder)]
    log=run(command,folder,env,900)
    display=json.loads(next(line.removeprefix('MOTIONBRICKS_POC_DISPLAY ') for line in log.splitlines() if line.startswith('MOTIONBRICKS_POC_DISPLAY ')))
    assert display['no_focus'] and display['screen']==0 and display['size']==[1920,1080]
    write(folder/'native-display.json',{'requested':[1640,50],'actual':display,'virtual_display_created':False})
    verification=verify_journal(read(folder/'movie-journal.json'),config,take);assert verification['source_config_sha256']==config['input_manifest_sha256'];write(folder/'journal-verification.json',verification)
    native_stills=read(folder/'native-stills.json');assert len(native_stills['shots'])==native_stills['expected']==len(config['clips'])*3
    native_rows={row['drawn_frame']:row for row in read(folder/'movie-journal.json')['frames']}
    for shot in native_stills['shots']:
     assert native_rows[shot['drawn_frame']]['actors']==shot['actors']
     shot['sha256']=sha(folder/shot['file'])
    write(folder/'native-stills-verification.json',native_stills)
    if args.stills_only:
     stills=read(folder/'native-stills.json');assert len(stills['shots'])==stills['expected']==len(config['clips'])*3 and stills['same_frame_pose_and_png']
     by_frame={row['drawn_frame']:row for row in read(folder/'movie-journal.json')['frames']}
     for shot in stills['shots']:
      assert (folder/shot['file']).is_file() and by_frame[shot['drawn_frame']]['actors']==shot['actors']
      shot['sha256']=sha(folder/shot['file'])
     write(folder/'stills-verification.json',stills);deliveries.append({'take':take,'native_stills':len(stills['shots']),'same_frame_pose_and_png':True,'movie_encoding_started':False})
    else:deliveries.append(encode(folder,verification,ffmpeg,ffprobe))
    assert project_inputs(cow)==inputs and project_inputs(project)==inputs
    assert production()==before and saves()==before_saves
   completed=True
 except BaseException as exc:
  error=repr(exc);raise
 finally:
  signal.signal(signal.SIGTERM,previous);after=production();after_saves=saves();write(out/'production-after.json',after);write(out/'default-save-after.json',after_saves)
  write(out/'integrity-and-cleanup.json',{'completed':completed,'error':error,'production_unchanged':before==after,'prepared_project_inputs_unchanged':project_inputs(project)==inputs,'default_saves_unchanged':before_saves==after_saves,'default_save_files':len(after_saves),'temporary_COW_removed':stage is None or not stage.exists(),'virtual_display_created':False,'audio_driver':'Dummy','deliveries':deliveries})
  assert before==after and before_saves==after_saves
 print(json.dumps({'completed':completed,'deliveries':deliveries,'COW_removed':not stage.exists()},ensure_ascii=False))

if __name__=='__main__':main()

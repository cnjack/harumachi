#!/usr/bin/env python3
"""Record the real game in an isolated temporary clone; supply measured virtual-screen coordinates.

Prepare first, then run modes serially, then finish. The production game is never edited.
"""
import argparse,json,os,shutil,subprocess,sys,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from visual_qa import save_hashes


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['prepare','scenic','story','lake','water','finish'])
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--screen',type=int)
    parser.add_argument('--position',help='Actual Godot pixel coordinates x,y, measured on the isolated display')
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=True);state_file=out/'capture-stage.json'
    if args.mode=='prepare':
        if state_file.exists():raise SystemExit('An existing stage is recorded; finish it before preparing again')
        stage=Path(tempfile.mkdtemp(prefix='harumachi-promo-'))
        subprocess.run(['cp','-cR',str(ROOT/'game'),str(stage/'game')],check=True)
        (stage/'game/override.cfg').write_text('[display]\nwindow/size/no_focus=true\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/size/window_width_override=1920\nwindow/size/window_height_override=1080\n')
        script=stage/'game/scripts/tools/shots.gd';text=script.read_text()
        text=text.replace('var manifest: Array[Dictionary] = []','var manifest: Array[Dictionary] = []\n\tvar promo=load("res://scripts/tools/promo_take.gd").new()')
        text=text.replace('\t\t\tget_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, n])','\t\t\tawait promo.record(main,dir,n,v)\n\t\t\tget_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, n])')
        text=text.replace('\t\tvar img := get_viewport().get_texture().get_image()','\t\tawait promo.record(main,dir,n,v)\n\t\tvar img := get_viewport().get_texture().get_image()')
        text=text.replace('var names := _arg(', 'catalog["promo_harvest"]=catalog["farm_field"].duplicate(true)\n\tcatalog["promo_water"]=catalog["farm_field"].duplicate(true)\n\tvar names := _arg(')
        script.write_text(text);shutil.copyfile(ROOT/'art/tools/promo_take.gd',stage/'game/scripts/tools/promo_take.gd')
        script=stage/'game/scripts/tools/lake_demo.gd';script.write_text(script.read_text().replace('print("LAKE_DEMO SHOT ",name)','print("LAKE_DEMO SHOT ",name," frame=",Engine.get_frames_drawn())'))
        state={'stage':str(stage),'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'default_saves_before':save_hashes(),'clone_only_capture_hook':True}
        state_file.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n')
        folder=out/'import';folder.mkdir(exist_ok=True)
        with (folder/'process.log').open('w') as log:subprocess.run([str(ROOT/'tools/godot'),'--headless','--path',str(stage/'game'),'--audio-driver','Dummy','--import','--log-file',str(folder/'engine.log')],env=dict(os.environ,HARUMACHI_SAVE_DIR=str(folder/'save')),stdout=log,stderr=subprocess.STDOUT,check=True,timeout=300)
        print(stage);return
    state=json.loads(state_file.read_text());stage=Path(state['stage'])
    assert stage.name.startswith('harumachi-promo-') and stage.parent==Path(tempfile.gettempdir())
    if args.mode=='finish':
        assert save_hashes()==state['default_saves_before'],'Default save changed during recording'
        shutil.rmtree(stage);(out/'cleanup.json').write_text(json.dumps({'stage_removed':True,'default_save_unchanged':True,'default_save_files':len(state['default_saves_before'])})+'\n');return
    if args.screen is None or args.position is None:parser.error('Recording requires the measured --screen and --position')
    folder=out/args.mode;folder.mkdir(exist_ok=True)
    cmd=[str(ROOT/'tools/godot'),'--path',str(stage/'game'),'--screen',str(args.screen),'-t','--position',args.position,'--resolution','1920x1080','--audio-driver','Dummy','--log-file',str(folder/'engine.log'),'--write-movie',str(out/(args.mode+'.avi')),'--fixed-fps','30','--','--no-music']
    if args.mode=='story':cmd+=['--autoplay','--autoplay-report='+str(folder/'report.json'),'--shots-dir='+str(folder/'shots')]
    elif args.mode=='lake':cmd+=['--lake-demo','--lake-demo-out='+str(folder)]
    else:
        views=['promo_water'] if args.mode=='water' else ['town_store','town_morning','promo_harvest','promo_water','farm_bridge2','farm_river','inhabited_bakery','inhabited_cafe','public_workroom_detail','fest_natsu','fest_hanabi']
        cmd+=['--shots='+str(folder),'--views='+','.join(views),'--clean=1']
    started=time.monotonic()
    with (folder/'process.log').open('w') as log:result=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,env=dict(os.environ,HARUMACHI_SAVE_DIR=str(folder/'save')),timeout=2400 if args.mode=='story' else 900)
    body=(folder/'process.log').read_text(errors='replace')
    report={'command':cmd,'exit':result.returncode,'wall_seconds':time.monotonic()-started,'default_save_unchanged':save_hashes()==state['default_saves_before'],'script_errors':'SCRIPT ERROR' in body,'shader_errors':'SHADER ERROR' in body}
    (folder/'process.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    assert result.returncode==0 and report['default_save_unchanged'] and not report['script_errors'] and not report['shader_errors']
    if args.mode=='story':assert json.loads((folder/'report.json').read_text())['passed']
    elif args.mode=='lake':assert json.loads((folder/'demo.json').read_text())['passed']
    else:assert 'passed=false' not in body
    print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':main()

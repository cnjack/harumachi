#!/usr/bin/env python3
"""Reproducible headless Cubism 5.3.04 export using the user's installed Editor.
No Live2D binaries, license data, or account tokens are copied or downloaded.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]

def run(args, cwd, env=None):
    subprocess.run([str(x) for x in args], cwd=cwd, env=env, check=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--editor', type=Path, default=Path('/Applications/Live2D Cubism 5.3'))
    parser.add_argument('--jdk', type=Path, default=Path('/opt/homebrew/opt/openjdk@21/bin'))
    parser.add_argument('--work', type=Path)
    parser.add_argument('--reuse-bake', action='store_true', help='Reuse bake in --work for exporter debugging')
    args = parser.parse_args()
    editor = args.editor.resolve(); res = editor/'res'
    if '5.3.04' not in (editor/'readme/ReadMe_en.txt').read_text():
        raise SystemExit('This bridge is validated with installed Cubism Editor 5.3.04 only')
    with tempfile.TemporaryDirectory(prefix='mio-cubism-') as temporary:
        work = args.work.resolve() if args.work else Path(temporary)
        work.mkdir(parents=True, exist_ok=True)
        bake, built, classes, logs = [work/name for name in ('bake','built','classes','logs')]
        for directory in (bake,built,classes,logs): directory.mkdir(exist_ok=True)
        if not args.reuse_bake:
            env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(work/'clang'), SWIFTPM_MODULECACHE_OVERRIDE=str(work/'clang'))
            run(['swift','run','-c','release','--build-system','native','--disable-sandbox','--package-path',ROOT/'native/mio-companion','--scratch-path',work/'swift','--cache-path',work/'cache','MioCubismBake',ROOT,bake],ROOT,env)
        source = ROOT/'art/tools/live2d'
        run([args.jdk/'javac','-proc:none','-encoding','UTF-8','-cp',str(res/'*'),'-d',classes,source/'MioBindings.java',*sorted((source/'vendor/autolive2d').glob('*.java'))],work)
        result = subprocess.run([str(args.jdk/'java'),'-Xmx4g','-Djava.awt.headless=true',f'-Djava.library.path={res}',f'-Dmio.bindings={bake}',f'-DlogsFilePath={logs}',f'-DlogFilename={logs}/export.log','-cp',f'{classes}:{res}/*','autolive2d.bridge.PsdExportBridge',str(bake/'Mio.psd'),str(built/'Mio.moc3'),str(built/'textures'),'',str(work/'progress.txt')],cwd=work,capture_output=True,text=True)
        (work/'export.log').write_text(result.stdout+'\n'+result.stderr)
        result.check_returncode()
        reports = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{"status"')]
        if not reports: raise SystemExit('Exporter produced no report; see '+str(work/'export.log'))
        report = reports[-1]
        expected_meshes = len(json.loads((bake/'bake.json').read_text())['meshes'])
        assert report['selectedConsistency'] and report['selectedParameterCount']==24 and report['selectedDrawableCount']==expected_meshes, report
        assert report['selectedMocVersion']==3 and report['intermediateArchiveSaved'], report
        runtime = ROOT/'native/mio-companion/Sources/MioApp/Resources/MioCubism'
        runtime.mkdir(exist_ok=True)
        shutil.copy2(built/'Mio.moc3',runtime/'Mio.moc3')
        shutil.copy2(bake/'Mio.bindings.json',runtime/'Mio.bindings.json')
        for name in ('textures','motions'):
            shutil.copytree((built if name=='textures' else bake)/name,runtime/name,dirs_exist_ok=True)
        names = ['idle','wave','stretch','think','talk']
        manifest = {'Version':3,'FileReferences':{'Moc':'Mio.moc3','Textures':[str(p.relative_to(built)) for p in sorted((built/'textures').glob('*.png'))], 'DisplayInfo':'Mio.cdi3.json','Motions':{name:[{'File':f'motions/{name}.motion3.json','FadeInTime':0,'FadeOutTime':0}] for name in names}},'Groups':[{'Target':'Parameter','Name':'EyeBlink','Ids':['ParamEyeLOpen','ParamEyeROpen']},{'Target':'Parameter','Name':'LipSync','Ids':['ParamMouthOpenY']}]}
        (runtime/'Mio.model3.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
        params = json.loads((bake/'bake.json').read_text())['parameters']
        display = {'Version':3,'Parameters':[{'Id':p['id'],'GroupId':'Mio','Name':p['id']} for p in params],'ParameterGroups':[{'Id':'Mio','GroupId':'','Name':'澪'}],'Parts':[]}
        (runtime/'Mio.cdi3.json').write_text(json.dumps(display,ensure_ascii=False,indent=2)+'\n')
        authored = ROOT/'art/live2d/mio/cubism';authored.mkdir(exist_ok=True)
        shutil.copy2(built/'Mio.cmo3',authored/'Mio.cmo3')
        shutil.copy2(bake/'Mio.psd',authored/'Mio.psd')
        (work/'export-report.json').write_text(json.dumps(report,indent=2)+'\n')
        print(f'Official MOC3 exported: {runtime}; editable source: {authored}')
        print('Validation report: '+str(work/'export-report.json'))

if __name__=='__main__': main()

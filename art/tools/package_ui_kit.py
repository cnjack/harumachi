"""Package a self-contained Godot gallery, original artwork and editable resources."""
import argparse,hashlib,json,re,shutil,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
engine_lock=json.loads((ROOT/'tools/godot-version.json').read_text())
parser=argparse.ArgumentParser();parser.add_argument('--previews',type=Path,required=True)
parser.add_argument('--output',type=Path,default=ROOT/'art/ui-kit/Harumachi-UI-Kit-v1.zip')
parser.add_argument('--evidence',type=Path,required=True)
args=parser.parse_args();destination=ROOT/'art/ui-kit/harumachi-v1'
destination.mkdir(parents=True,exist_ok=True)
(destination/'project.godot').write_text('''config_version=5
[application]
config/name="晴町和纸 UI 素材库"
run/main_scene="res://scenes/ui_kit_gallery.tscn"
config/features=PackedStringArray("__GODOT_FEATURE_VERSION__")
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/window_width_override=1440
window/size/window_height_override=900
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
[rendering]
renderer/rendering_method="gl_compatibility"
'''.replace('__GODOT_FEATURE_VERSION__',engine_lock['feature_version']))
shutil.copytree(ROOT/'game/ui_kit',destination/'ui_kit',dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.import','*.uid'))
shutil.copytree(ROOT/'game/assets/fonts',destination/'assets/fonts',dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.import'))
(destination/'scenes').mkdir(exist_ok=True)
shutil.copy2(ROOT/'game/scenes/ui_kit_gallery.tscn',destination/'scenes/ui_kit_gallery.tscn')
shutil.copy2(ROOT/'game/ui_kit/README.md',destination/'README.md')
(destination/'previews').mkdir(exist_ok=True)
for image in args.previews.glob('*.png'):shutil.copy2(image,destination/'previews'/image.name)
records=json.loads((ROOT/'art/manifests/images_codex.json').read_text())['images']
filenames={file.name for file in (destination/'ui_kit/assets').glob('*.png')}
selected=[record for record in records if record.get('file','').startswith(('game/assets/ui/refresh_20261003/','game/ui_kit/assets/')) and Path(record['file']).name in filenames]
(destination/'source_images.json').write_text(json.dumps({'images':selected},ensure_ascii=False,indent=2)+'\n')
(destination/'prompts').mkdir(exist_ok=True)
for filename in ['ui_refresh_20261003.json','ui_frames_20261003.json','ui_kit_20261003.json']:
    source=ROOT/'art/manifests/prompts'/filename
    if source.exists():shutil.copy2(source,destination/'prompts'/filename)
(destination/'ASSET_NOTES.md').write_text('# 素材与字体\n\nUI原图由内置imagegen生成，提示词和摘要保存在本包；独立PNG直接裁出原图区域，没有绘制或抠色。源库和示例均用于晴町的统一界面，未使用星露谷或牧场物语的界面素材。字体为霞鹜文楷，许可原文随包附在 assets/fonts/OFL.txt，复用时保留。\n')
def included(file):
    return file.is_file() and not any(part.startswith('.') for part in file.relative_to(destination).parts) and file.suffix not in ('.import','.uid')
files=sorted(file for file in destination.rglob('*') if included(file) and file.name!='manifest.json')
catalog=json.loads((destination/'ui_kit/catalog.json').read_text())['assets']
counts={'original_png':len(list((destination/'ui_kit/assets').glob('*.png'))),'icons':sum(v['category']=='icon' for v in catalog.values()),'control_artwork':sum(v['category']=='control' for v in catalog.values()),'surfaces':sum(v['category'] in ('surface','overlay') for v in catalog.values()),'cropped_png':len(list((destination/'ui_kit/png').glob('*.png'))),'godot_resources':len([f for f in (destination/'ui_kit/resources').iterdir() if f.suffix in ('.tres','.res')])}
gallery=destination/'ui_kit/gallery.gd'
caption=f"v1.0  ·  {counts['icons']} 图标 / {counts['control_artwork']} 控件底图 / {counts['surfaces']} 背景"
gallery.write_text(re.sub(r'v1\.0\s*·\s*\d+ 图标 / \d+ 控件底图 / \d+ 背景',caption,gallery.read_text()))
manifest={'name':'晴町和纸 UI','version':'1.0.0','engine':'Godot '+engine_lock['release_tag'],'counts':counts,'files':[{'path':file.relative_to(destination).as_posix(),'bytes':file.stat().st_size,'sha256':hashlib.sha256(file.read_bytes()).hexdigest()} for file in files]}
(destination/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
archive=args.output.resolve()
if ROOT/'builds' in archive.parents:raise SystemExit('UI packages belong in art/ui-kit, not builds')
archive.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as bundle:
    for file in sorted(destination.rglob('*')):
        if included(file):bundle.write(file,'harumachi-v1/'+file.relative_to(destination).as_posix())
with zipfile.ZipFile(archive) as bundle:assert bundle.testzip() is None
result={'archive':str(archive),'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'zip_crc':'ok','files':len(manifest['files'])+1,'counts':manifest['counts']}
args.evidence.mkdir(parents=True,exist_ok=True)
(args.evidence/'library-package.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False))

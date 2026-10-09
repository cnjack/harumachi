"""Read-only skin audit: prevent views from adding private flat panel frames."""
import argparse, json, re, sys
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('--game',type=Path,default=Path(__file__).resolve().parents[2]/'game')
parser.add_argument('--out',type=Path)
args=parser.parse_args()
allowed={'scripts/ui/ui_theme.gd':'legacy compatibility factory',
         'scripts/ui/world_map_canvas.gd':'cartographic labels and building footprints',
         'scripts/ui/loading_lantern.gd':'illustrated paper lantern'}
issues=[];scanned=[]
files=list((args.game/'scripts/ui').glob('*.gd'))+list((args.game/'scripts/minigames').glob('*.gd'))+[args.game/'scripts/autoload/loading.gd']
for file in sorted(files):
    relative=file.relative_to(args.game).as_posix();scanned.append(relative)
    if relative in allowed:continue
    for line,text in enumerate(file.read_text().splitlines(),1):
        if re.search(r'\b(?:UITheme\.box|StyleBoxFlat\.new|UIKitStyles\.flat)\s*\(',text):
            issues.append({'file':relative,'line':line,'source':text.strip()})
if not (args.game/'ui_kit/catalog.json').exists():issues.append({'file':'ui_kit/catalog.json','reason':'missing canonical kit'})
report={'ok':not issues,'scanned':scanned,'allowed_artwork':allowed,'issues':issues}
if args.out:args.out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'ok':report['ok'],'scanned':len(scanned),'issues':issues},ensure_ascii=False))
sys.exit(0 if report['ok'] else 1)

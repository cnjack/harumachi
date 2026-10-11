"""Check the full-bleed icon source and native macOS catalog used by the export."""
import argparse
import json
import plistlib
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True, type=Path)
parser.add_argument('--native', type=Path)
parser.add_argument('--bundle', type=Path)
parser.add_argument('--out', required=True, type=Path)
args = parser.parse_args()
checks = {}
with Image.open(args.source) as source:
    checks['square'] = source.width == source.height
    checks['fully_opaque'] = source.convert('RGBA').getchannel('A').getextrema() == (255, 255)
if args.native:
    icon = json.loads((args.native / 'icon.json').read_text())
    groups = icon['groups']
    layers = [layer for group in groups for layer in group['layers']]
    checks['single_full_bleed_layer'] = len(layers) == 1 and not layers[0].get('position')
    checks['layer_glass_disabled'] = all(layer.get('glass') is False for layer in layers)
    checks['group_translucency_disabled'] = all(not group.get('translucency', {}).get('enabled', False) for group in groups)
    checks['group_shadow_disabled'] = all(group.get('shadow', {}).get('kind') == 'none' for group in groups)
    checks['native_image_opaque'] = all(
        Image.open(args.native / 'Assets' / layer['image-name']).convert('RGBA').getchannel('A').getextrema() == (255, 255)
        for layer in layers
    )
if args.bundle:
    resources = args.bundle / 'Contents/Resources'
    info = plistlib.loads((args.bundle / 'Contents/Info.plist').read_bytes())
    checks['native_catalog_present'] = (resources / 'Assets.car').is_file() and (resources / 'Assets.car').stat().st_size > 0
    checks['native_icon_selected'] = info.get('CFBundleIconName') == args.native.stem
    checks['legacy_fallback_present'] = (resources / info['CFBundleIconFile']).is_file()
report = {'passed': all(checks.values()), 'checks': checks}
args.out.parent.mkdir(parents=True, exist_ok=True)
args.out.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
raise SystemExit(0 if report['passed'] else 1)

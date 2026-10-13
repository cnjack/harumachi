"""Render the scoped source, prepared or game GLBs and build four-side/clay sheets.

This is an offline inspection tool. It never calls a generation service.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'evidence/hyper3d_diversity_20261013'
VIEWS = ['front', 'back', 'left', 'right', 'oblique', 'clay_front', 'clay_oblique']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ids', required=True)
    parser.add_argument('--candidate', choices=['a', 'b'], default='a')
    parser.add_argument('--stage', choices=['source', 'ready', 'game'], default='source')
    parser.add_argument('--blender', default='/Applications/Blender.app/Contents/MacOS/Blender')
    args = parser.parse_args()
    scope = {r['id']: r for r in json.loads((ROOT / 'art/manifests/model_diversity_20261013.json').read_text())['assets']}
    ids = args.ids.split(',')
    if len(ids) != len(set(ids)) or any(aid not in scope for aid in ids):
        parser.error('Supply unique scoped IDs')

    def paths(aid):
        if args.stage == 'source':
            return (ROOT / 'art/models/raw/diversity_20261013' / aid / args.candidate / 'model.glb',
                    EVIDENCE / 'candidates' / aid / args.candidate)
        if args.stage == 'ready':
            return (ROOT / 'art/models/raw/diversity_20261013/ready' / (aid + '.glb'),
                    EVIDENCE / 'prepared-review' / aid)
        return ROOT / 'game/assets/models' / (aid + '.glb'), EVIDENCE / 'game-review' / aid

    def render(aid):
        source, out = paths(aid)
        out.mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        report = out / 'review.json'
        if (report.exists() and json.loads(report.read_text()).get('sha256') == digest
                and all((out / (v + '.png')).exists() for v in VIEWS)):
            return aid, 'cached'
        command = [args.blender, '-b', '--factory-startup', '--disable-autoexec', '-P',
                   str(ROOT / 'art/tools/render_diversity_review.py'), '--', str(source), str(out), '1']
        with (out / 'render.log').open('w') as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        if result.returncode:
            raise RuntimeError(f'{aid}: Blender failed; see {out / "render.log"}')
        return aid, 'rendered'

    with ThreadPoolExecutor(max_workers=3) as pool:
        for result in pool.map(render, ids):
            print(*result, flush=True)
    sheets = EVIDENCE / 'candidate-sheets'
    sheets.mkdir(exist_ok=True)
    for start in range(0, len(ids), 3):
        group = ids[start:start + 3]
        sheet = Image.new('RGB', (2100, 325 * len(group)), 'white')
        draw = ImageDraw.Draw(sheet)
        for i, aid in enumerate(group):
            _, folder = paths(aid)
            for j, view in enumerate(VIEWS):
                with Image.open(folder / (view + '.png')) as source:
                    source = source.convert('RGB')
                    source.thumbnail((300, 300))
                    sheet.paste(source, (j * 300, i * 325))
                draw.text((j * 300 + 5, i * 325 + 304), aid + ' ' + view, fill='black')
        target = sheets / f'{args.stage}-{group[0]}-{args.candidate}.jpg'
        sheet.save(target, quality=94)
        print('SHEET', target, flush=True)


if __name__ == '__main__':
    main()

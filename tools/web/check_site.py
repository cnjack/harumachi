#!/usr/bin/env python3
"""Validate the shipped website catalogue, downloads, resources and font coverage."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote
from PIL import Image
from fontTools.ttLib import TTFont
import argparse
import json
import re

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--out', type=Path)
args = parser.parse_args()
SITE = ROOT / 'site'
errors = []
checks = 0


def check(condition, message):
    global checks
    checks += 1
    if not condition:
        errors.append(message)


class Resources(HTMLParser):
    def __init__(self):
        super().__init__()
        self.resources = []
        self.ids = []
        self.copy = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if 'id' in attributes:
            self.ids.append(attributes['id'])
        for key in ('src', 'href', 'srcset'):
            if attributes.get(key):
                self.resources.append(attributes[key].split()[0])

    def handle_data(self, data):
        self.copy.append(data)


page = Resources()
page.feed((SITE / 'index.html').read_text())
check(len(page.ids) == len(set(page.ids)), 'Duplicate HTML id')
for resource in page.resources:
    url = urlsplit(resource)
    if url.scheme or url.netloc or not url.path:
        continue
    check((SITE / unquote(url.path)).exists(), f'Missing page resource: {resource}')
for name in ('style.css', 'ui.css'):
    for quoted, single_quoted, bare in re.findall(r'url\(\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^)]*))\s*\)', (SITE / name).read_text()):
        resource = quoted or single_quoted or bare.strip()
        if not urlsplit(resource).scheme:
            check((SITE / resource).exists(), f'Missing CSS resource: {resource}')

catalogue = json.loads((SITE / 'assets/library.json').read_text())
ids = [item['id'] for item in catalogue['wallpapers']]
check(len(ids) == len(set(ids)), 'Duplicate wallpaper id')
for item in catalogue['wallpapers']:
    for key in ('src', 'preview'):
        file = SITE / item[key]
        check(file.is_file(), f'Missing wallpaper: {file}')
        if file.is_file():
            with Image.open(file) as image:
                image.verify()
    file = SITE / item['src']
    if file.is_file():
        with Image.open(file) as image:
            check(image.size == (item['width'], item['height']), f'Incorrect dimensions: {item["id"]}')
        check(file.stat().st_size == item['bytes'], f'Incorrect file size: {item["id"]}')
    check((item['width'] > item['height']) == (item['device'] == 'desktop'), f'Incorrect orientation: {item["id"]}')
for item in catalogue['tracks']:
    for key in ('src', 'original'):
        check((SITE / item[key]).is_file(), f'Missing audio: {item[key]}')

font = TTFont(SITE / 'assets/fonts/wenkai-sub.woff2')
covered = font.getBestCmap()
copy = ''.join(page.copy) + json.dumps(catalogue, ensure_ascii=False) + (SITE / 'library.js').read_text()
missing = sorted({c for c in copy if '\u4e00' <= c <= '\u9fff' and ord(c) not in covered})
check(not missing, 'Missing font characters: ' + ''.join(missing))
check((ROOT / 'LICENSE').read_text().startswith('MIT License\n'), 'Project MIT licence missing')
check((ROOT / 'ASSET_LICENSES.md').exists(), 'Third-party notices missing')
check('subscribe-form' not in (SITE / 'index.html').read_text(), 'Placeholder email subscription still present')
report = {'passed': not errors, 'checks': checks, 'wallpapers': len(ids), 'desktop': sum(i['device'] == 'desktop' for i in catalogue['wallpapers']), 'mobile': sum(i['device'] == 'mobile' for i in catalogue['wallpapers']), 'tracks': len(catalogue['tracks']), 'errors': errors}
if args.out:
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False))
raise SystemExit(0 if report['passed'] else 1)

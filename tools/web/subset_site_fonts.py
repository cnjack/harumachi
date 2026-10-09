#!/usr/bin/env python3
"""Build the website font subset from shipped copy and the media catalogue."""
from pathlib import Path
from fontTools import subset

ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / 'site'
sources = [SITE / name for name in ('index.html', 'style.css', 'main.js', 'library.js', 'assets/library.json')]
if (SITE / 'play/index.html').exists():
    sources.append(SITE / 'play/index.html')
text = ''.join(path.read_text() for path in sources)
characters = ''.join(sorted(set(c for c in text if ord(c) > 0x2000) | set('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz ')))
options = subset.Options()
options.flavor = 'woff2'
options.layout_features = ['*']
font = subset.load_font(str(ROOT / 'game/assets/fonts/LXGWWenKai-Medium.ttf'), options)
subsetter = subset.Subsetter(options)
subsetter.populate(text=characters)
subsetter.subset(font)
output = SITE / 'assets/fonts/wenkai-sub.woff2'
subset.save_font(font, str(output), options)
print(f'{output.relative_to(ROOT)}: {len(characters)} characters, {output.stat().st_size} bytes')

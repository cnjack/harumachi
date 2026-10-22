#!/usr/bin/env python3
"""Contact sheets of fixed-pose Core/Metal captures; never modifies source art."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype('/System/Library/Fonts/STHeiti Light.ttc', 19)
    bg = '#f6f5ef'

    def panel(directory, x, y):
        with Image.open(directory / f'head-{x}-{y}.png') as raw:
            image = Image.new('RGBA', raw.size, bg)
            image.alpha_composite(raw.convert('RGBA'))
            return image.convert('RGB').crop((270, 85, 485, 295))

    comparison = Image.new('RGB', (1290, 900), bg)
    draw = ImageDraw.Draw(comparison)
    for row, (title, directory) in enumerate([('修复前', args.before), ('修复后', args.directory)]):
        for col, (x, facing) in enumerate([(-30, '向左'), (0, '正面'), (30, '向右')]):
            comparison.paste(panel(directory, x, 0).resize((430, 420)), (col * 430, row * 450 + 30))
            draw.text((col * 430 + 12, row * 450 + 5), title + ' · ' + facing, font=font, fill='#35434b')
    comparison.save(args.output / 'head-before-after.png')
    grid = Image.new('RGB', (1505, 1200), bg)
    draw = ImageDraw.Draw(grid)
    for row, y in enumerate([-30, -15, 0, 15, 30]):
        for col, x in enumerate([-30, -20, -10, 0, 10, 20, 30]):
            grid.paste(panel(args.directory, x, y), (col * 215, row * 240 + 25))
            draw.text((col * 215 + 6, row * 240 + 4), f'X {x} / Y {y}', font=font, fill='#35434b')
    grid.save(args.output / 'head-grid.png')
    with Image.open(args.before / 'head-0-0.png') as before, Image.open(args.directory / 'head-0-0.png') as after:
        difference = ImageChops.difference(before, after)
        body = difference.crop((0, 296, 750, 1000))
        report = {'staticViews': 35, 'bodyDifferenceExtrema': body.getextrema(),
                  'neutralHeadMeanAbsoluteError': ImageStat.Stat(difference.crop((270, 85, 485, 295))).mean,
                  'visualAcceptanceRequired': True}
    (args.output / 'head-pixel-comparison.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

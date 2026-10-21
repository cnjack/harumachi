"""Compare real Core/Metal face renders with the approved original artwork.

This crops QA screenshots only; source artwork is not modified. The neutral
pixel check catches identity drift, while contact sheets need visual review.
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--current', type=Path, required=True)
    parser.add_argument('--rejected', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    try:
        font = ImageFont.truetype('/System/Library/Fonts/STHeiti Light.ttc', 20)
    except OSError:
        font = ImageFont.load_default()

    def load(path):
        with Image.open(path) as source:
            result = Image.new('RGBA', source.size, '#f7f6f0')
            result.alpha_composite(source.convert('RGBA'))
            return result.convert('RGB')

    reference = load(args.reference)
    current = load(args.current / 'default.png')
    box = (330, 185, 420, 224)
    def error(picture):
        difference = ImageChops.difference(reference.crop(box), picture.crop(box))
        return sum(ImageStat.Stat(difference).mean) / 3
    report = {'eyeRegion': box, 'neutralEyeMeanAbsoluteError': error(current),
              'threshold': 3, 'pixelCheckPassed': error(current) <= 3,
              'visualAcceptance': 'Requires review of face and blink contact sheets'}
    if args.rejected:
        report['rejectedEyeMeanAbsoluteError'] = error(load(args.rejected))

    def sheet(name, entries, columns=3, crop=(275, 88, 480, 293), size=(360, 360)):
        panel = Image.new('RGB', (columns * size[0], ((len(entries) + columns - 1) // columns) * (size[1] + 38)), '#f7f6f0')
        draw = ImageDraw.Draw(panel)
        for index, (label, path) in enumerate(entries):
            x, y = index % columns * size[0], index // columns * (size[1] + 38)
            draw.text((x + 12, y + 8), label, font=font, fill='#35434b')
            panel.paste(load(path).crop(crop).resize(size, Image.Resampling.LANCZOS), (x, y + 38))
        panel.save(args.output / name)

    comparison = [('原版', args.reference)]
    if args.rejected:
        comparison.append(('上一版：已撤回', args.rejected))
    comparison.append(('修复后', args.current / 'default.png'))
    sheet('comparison.png', comparison, len(comparison))
    sheet('look-directions.png', [(f'视线 {x}, {y}', args.current / f'face-{x}-{y}.png') for y in [-1, 0, 1] for x in [-1, 0, 1]])
    sheet('blinks.png', [(f'{t:.2f} 秒', args.current / f'eyelids-{t}.png') for t in [4.17, 4.2, 4.23, 4.25, 4.3, 4.35, 4.39]], 7, (310, 175, 440, 275), (230, 177))
    sheet('gesture-faces.png', [(f'{name} {t:.1f} 秒', args.current / f'{gesture}-{t}.png') for gesture, name in [('idle', '放下'), ('wave', '招手'), ('think', '思考'), ('talk', '说话')] for t in [0.0, 1.5, 3.0, 4.9]], 4)
    (args.output / 'face-review.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if not report['pixelCheckPassed']:
        raise SystemExit('Neutral eyes differ from the approved reference')


if __name__ == '__main__':
    main()

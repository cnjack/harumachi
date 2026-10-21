#!/usr/bin/env python3
"""Compare actual Core/Metal side-hair roots against same-pose baseline frames.

Outer wisps are intentionally translucent. A leak is a new loss of coverage at
a previously opaque pixel, not merely an alpha value below 255 near a silhouette.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    directory = args.directory
    report = json.loads((directory / 'hair-review.json').read_text())
    total, opaque, translucent, minimum, maximum_loss = 0, 0, 0, 255, 0
    difference, worst_darkening, failures = 0, 0, []
    for frame, state in enumerate(report['dynamic']):
        with Image.open(directory / f'flow-{frame:04d}.png') as current, Image.open(directory / 'reference-flow' / f'{frame:04d}.png') as reference:
            for x, y in state['roots']:
                darkening = []
                for dx in range(-3, 4):
                    for dy in range(-2, 3):
                        point = round(x) + dx, round(y) + dy
                        a, b = reference.getpixel(point), current.getpixel(point)
                        total += 1
                        maximum_loss = max(maximum_loss, a[3] - b[3])
                        if a[3] < 250:
                            translucent += 1
                            continue
                        opaque += 1
                        minimum = min(minimum, b[3])
                        difference += sum(abs(a[c] - b[c]) for c in range(3)) / 3
                        darkening.append(sum(a[:3]) / 3 - sum(b[:3]) / 3)
                        if a[3] - b[3] > 4:
                            failures.append({'frame': frame, 'point': point, 'beforeAlpha': a[3], 'afterAlpha': b[3]})
                if darkening:
                    worst_darkening = max(worst_darkening, sum(darkening) / len(darkening))

    def composite(path):
        with Image.open(path) as raw:
            image = Image.new('RGBA', raw.size, '#f7f6f0')
            image.alpha_composite(raw.convert('RGBA'))
            return image.convert('RGB')

    before, after = composite(directory / 'reference.png'), composite(directory / 'tips-0-0.png')
    crop = (275, 85, 480, 290)
    head_error = sum(ImageStat.Stat(ImageChops.difference(before.crop(crop), after.crop(crop))).mean) / 3
    result = {'sampledRootPixels': total, 'previouslyOpaquePixels': opaque,
              'existingTranslucentPixels': translucent, 'minimumPreviouslyOpaqueAlpha': minimum,
              'maximumAlphaLoss': maximum_loss, 'rootRGBMeanAbsoluteError': difference / max(1, opaque),
              'maximumMeanRootDarkening': worst_darkening, 'neutralHeadMeanAbsoluteError': head_error,
              'failures': failures, 'sourceStates': report['sourceStates'],
              'maximumRootGap': report['maximumRootGap'], 'inversions': report['inversions'],
              'passed': not failures and worst_darkening < 3 and head_error < 1}
    (directory / 'pixel-review.json').write_text(json.dumps(result, indent=2) + '\n')
    font = ImageFont.truetype('/System/Library/Fonts/STHeiti Light.ttc', 20)

    def sheet(name, entries, columns):
        image = Image.new('RGB', (360 * columns, 390 * ((len(entries) + columns - 1) // columns)), '#f7f6f0')
        draw = ImageDraw.Draw(image)
        for i, (title, path) in enumerate(entries):
            x, y = i % columns * 360, i // columns * 390
            image.paste(composite(path).crop(crop).resize((360, 360), Image.Resampling.LANCZOS), (x, y + 30))
            draw.text((x + 10, y + 5), title, font=font, fill='#35434b')
        image.save(directory / name)

    sheet('neutral-comparison.png', [('整片前发', directory / 'reference.png'), ('前额与两侧独立', directory / 'tips-0-0.png')], 2)
    sheet('extremes.png', [(f'左 {l} / 右 {r}', directory / f'tips-{l}-{r}.png') for l in [-1, 0, 1] for r in [-1, 0, 1]], 3)
    sheet('flow-contact.png', [(f'{frame / 60:.1f} 秒', directory / f'flow-{frame:04d}.png') for frame in [0, 30, 60, 120, 180, 240, 360, 438, 540, 660, 900, 1199]], 4)
    print(json.dumps(result, indent=2))
    if not result['passed']:
        raise SystemExit('Hair coverage, root line or neutral appearance regression')


if __name__ == '__main__':
    main()

"""Verify that both lower sleeves retain the approved continuous sleeve folds.

Compare opaque elbow texels with the original atlas, independently of the packer.
This catches replacing the folds with a separate painted circular sleeve cap;
rendered joint continuity and animation still need their own checks.
"""
import argparse
import json
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]


def bilinear(image, x, y):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x-ix, y-iy
    if ix < 0 or iy < 0 or ix+1 >= image.width or iy+1 >= image.height:
        return (0, 0, 0, 0)
    a, b = image.getpixel((ix, iy)), image.getpixel((ix+1, iy))
    c, d = image.getpixel((ix, iy+1)), image.getpixel((ix+1, iy+1))
    return tuple((a[i]*(1-fx)+b[i]*fx)*(1-fy)+(c[i]*(1-fx)+d[i]*fx)*fy for i in range(4))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resources', type=Path, default=ROOT/'native/mio-companion/Sources/MioApp/Resources/Mio')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    rig = json.loads((args.resources/'Mio.rig.json').read_text())
    atlas = Image.open(ROOT/'art/live2d/mio/articulated/body-arms-atlas.png').convert('RGBA')
    report = {'source': 'art/live2d/mio/articulated/body-arms-atlas.png', 'sides': {}, 'passed': True}
    for side, crop, origin in [('left', (640, 140, 1010, 680), 65), ('right', (1160, 140, 1536, 680), 341)]:
        original = atlas.crop(crop)
        original = original.crop(original.getchannel('A').point(lambda a: 255 if a > 32 else 0).getbbox())
        layer = next(x for x in rig['layers'] if x['id'] == 'lower_sleeve_'+side)
        actual = Image.open(args.resources/layer['texture']).convert('RGBA')
        rect = layer['rect']
        elbow, wrist = layer['joints'][1:]
        length = math.dist(elbow, wrist)
        dx, dy = (wrist[0]-elbow[0])/length, (wrist[1]-elbow[1])/length
        differences = []
        for along in range(12, 43, 2):
            for across in range(-20, 21, 2):
                x, y = elbow[0]+dx*along-dy*across, elbow[1]+dy*along+dx*across
                expected = bilinear(original, (x-origin)/194*original.width, (y-285)/280*original.height)
                found = bilinear(actual, (x-rect[0])/rect[2]*actual.width-.5, (y-rect[1])/rect[3]*actual.height-.5)
                if expected[3] > 250:
                    differences.extend(abs(found[i]-expected[i]) for i in range(4))
        error = sum(differences)/max(1, len(differences))
        passed = len(differences) >= 800 and error < 3
        report['sides'][side] = {'samples': len(differences)//4, 'mean_channel_error': error, 'maximum_mean_error': 3, 'passed': passed}
        report['passed'] &= passed
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

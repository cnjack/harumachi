"""Check actual canonical TV captures; catches a noise shader that renders black.

The crop is inside the measured glass in the 1280x720 shop_tv camera. A tuning
frame must be substantially monochrome and spatially noisy, not simply dark.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


def measure(path):
    with Image.open(path) as image:
        if image.size != (1280, 720):raise ValueError('Use the canonical 1280x720 shop_tv_static capture')
        pixels = np.asarray(image.convert('RGB'), dtype=float)[300:410, 520:700] / 255
    luminance = pixels.mean(axis=2)
    return {'file': str(path), 'luminance_std': float(luminance.std()),
            'monochrome_fraction': float((np.ptp(pixels, axis=2) < .06).mean()),
            'mean_luminance': float(luminance.mean()),
            'pass': bool(luminance.std() > .08 and (np.ptp(pixels, axis=2) < .06).mean() > .85)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser();parser.add_argument('image', type=Path)
    parser.add_argument('--out', type=Path);args = parser.parse_args()
    result = measure(args.image);text = json.dumps(result, indent=2) + '\n'
    if args.out:args.out.write_text(text)
    print(text, end='');raise SystemExit(0 if result['pass'] else 1)

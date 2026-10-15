#!/usr/bin/env python3
"""Decode a video and produce timestamped, unretouched frame contact sheets.

This records media integrity only. Visual approval is a separate review.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--interval', type=float, default=0.5)
    parser.add_argument('--times', help='Comma-separated exact frame times instead of an interval')
    parser.add_argument('--crop', help='Optional normalized x0,y0,x1,y1 inspection region')
    args = parser.parse_args()
    source = args.source.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    probe = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(source)
    ]))
    duration = float(probe['format']['duration'])
    assert args.interval > 0
    times = ([float(value) for value in args.times.split(',')] if args.times
             else [i * args.interval for i in range(int(duration / args.interval))])
    assert times and all(0 <= value < duration for value in times)
    with (args.out / 'decode.log').open('w') as log:
        subprocess.run(['ffmpeg', '-v', 'error', '-i', str(source), '-f', 'null', '-'],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    region = [float(value) for value in args.crop.split(',')] if args.crop else None
    if region:
        assert len(region) == 4 and 0 <= region[0] < region[2] <= 1 and 0 <= region[1] < region[3] <= 1
    frames = []
    for index, timestamp in enumerate(times):
        target = args.out / f'frame-{index:03d}.png'
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', str(timestamp), '-i', str(source),
                        '-frames:v', '1', str(target)], check=True)
        with Image.open(target) as original:
            frame = original.convert('RGB')
        if region:
            frame = frame.crop((int(region[0] * frame.width), int(region[1] * frame.height),
                                int(region[2] * frame.width), int(region[3] * frame.height)))
        frame.thumbnail((672, 384))
        frames.append(frame)
    sheets = []
    for start in range(0, len(frames), 8):
        selected = frames[start:start + 8]
        width = max(frame.width for frame in selected)
        height = max(frame.height for frame in selected) + 24
        canvas = Image.new('RGB', (width * 2, height * ((len(selected) + 1) // 2)), '#18202b')
        draw = ImageDraw.Draw(canvas)
        for offset, frame in enumerate(selected):
            x, y = offset % 2 * width, offset // 2 * height
            canvas.paste(frame, (x, y))
            draw.text((x + 8, y + frame.height + 5), f'{times[start + offset]:.2f}s', fill='white')
        path = args.out / f'contact-{start // 8 + 1:02d}.jpg'
        canvas.save(path, quality=95)
        sheets.append(str(path.resolve()))
    report = {'source': str(source), 'sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'probe': probe, 'full_decode_passed': True, 'times': times, 'crop': region,
              'sheets': sheets, 'visual_review': 'pending'}
    (args.out / 'media.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'duration': duration, 'full_decode_passed': True, 'sheets': sheets}))


if __name__ == '__main__':
    main()

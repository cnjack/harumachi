#!/usr/bin/env python3
"""Encode the actual --review-emotion Metal frames as a silent review movie.

Captions sit outside the character image. This does not generate or edit source
art, interpolate frames, or measure real-time rendering speed.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--font', type=Path, default=Path('/System/Library/Fonts/STHeiti Light.ttc'))
    args = parser.parse_args()
    report = json.loads((args.directory / 'emotion-review.json').read_text())
    transitions = report['transitions']
    frames = args.directory / 'frames'
    if len(transitions) != 3000 or any(not (frames / f'{i:04d}.png').is_file() for i in range(3000)):
        raise SystemExit('Requires all 3,000 original Metal frames; use MIO_REVIEW_SAVE_FRAMES=1')
    ffmpeg, ffprobe = shutil.which('ffmpeg'), shutil.which('ffprobe')
    if not ffmpeg or not ffprobe or not args.font.is_file():
        raise SystemExit('ffmpeg, ffprobe and a Chinese font are required')

    stages = [(0, '平静倾听'), (4, '温柔欢迎 · 招手'), (10, '分享喜悦 · 摊掌'),
              (16, '好奇思考 · 抵住下巴'), (22, '关心安慰 · 放下手'),
              (28, '短暂惊讶 · 圆口形'), (34, '坚定鼓励 · 肩旁握拳'),
              (40, '困倦晚安'), (46, '回到安静陪伴')]
    captions = []
    for _, label in stages:
        caption = Image.new('RGB', (750, 1140), '#f7f6f0')
        draw = ImageDraw.Draw(caption)
        for text, y, size in [('澪 · 眉眼、口形与手势', 20, 27), (label, 62, 21),
                              ('真实 Metal 帧序列 · 50 秒 · 静音', 1106, 18)]:
            font = ImageFont.truetype(str(args.font), size)
            draw.text(((750 - draw.textlength(text, font=font)) / 2, y), text, font=font, fill='#35434b')
        captions.append(caption)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='mio-movie-', dir=args.output.parent) as temporary:
        candidate = Path(temporary) / 'demo.mp4'
        process = subprocess.Popen([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                                    '-f', 'rawvideo', '-pixel_format', 'rgb24', '-video_size', '750x1140',
                                    '-framerate', '60', '-i', '-', '-frames:v', '3000', '-an', '-c:v', 'libx264',
                                    '-crf', '18', '-preset', 'medium', '-pix_fmt', 'yuv420p',
                                    '-movflags', '+faststart', str(candidate)], stdin=subprocess.PIPE)
        try:
            for frame in range(3000):
                stage = max(i for i, (start, _) in enumerate(stages) if start <= frame / 60)
                image = captions[stage].copy()
                with Image.open(frames / f'{frame:04d}.png') as rendered:
                    assert rendered.size == (750, 1000)
                    rendered = rendered.convert('RGBA')
                    image.paste(rendered, (0, 100), rendered)
                process.stdin.write(image.tobytes())
            process.stdin.close()
            if process.wait() != 0:
                raise RuntimeError('Movie encoding failed')
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
        probe = json.loads(subprocess.check_output([ffprobe, '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(candidate)]))
        streams = probe['streams']
        assert len(streams) == 1 and streams[0]['codec_type'] == 'video'
        assert streams[0]['nb_frames'] == '3000' and streams[0]['r_frame_rate'] == '60/1'
        assert abs(float(probe['format']['duration']) - 50) < 0.01
        candidate.replace(args.output)
    result = {'file': str(args.output), 'sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
              'seconds': 50, 'frames': 3000, 'fps': 60, 'width': 750, 'height': 1140, 'audio': False,
              'method': 'Offline native Metal frames; not a real-time FPS measurement',
              'sourceReport': str(args.directory / 'emotion-review.json')}
    args.output.with_suffix('.verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

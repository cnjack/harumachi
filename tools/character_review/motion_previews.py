#!/usr/bin/env python3
"""Build real-time cropped GIFs and phase sheets from existing native PNGs.

No game, renderer, model or review HTML is modified. Timing uses each actual
screenshot's elapsed_s; GIF boundaries round cumulatively to10ms. PNGs remain
the authoritative full-resolution images for fine geometry/garment review.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
from PIL import Image, ImageDraw, ImageFont

ACTORS = ('sora', 'ren', 'haru', 'mio', 'aoi', 'tanaka', 'kazuko')
VIEWS = ('front', 'right', 'back', 'left', 'top')
REFERENCE_SIZE = (1280, 720)
REFERENCE_CROP = (425, 60, 855, 720)


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def crop_box(size: tuple[int, int]) -> tuple[int, int, int, int]:
    width, height = size
    if width <= 0 or height <= 0:
        raise ValueError('Empty source image')
    return tuple(round(v * size[i % 2] / REFERENCE_SIZE[i % 2])
                 for i, v in enumerate(REFERENCE_CROP))


def cropped(path: Path, width: int) -> tuple[Image.Image, tuple[int, ...], tuple[int, ...]]:
    with Image.open(path) as source:
        size = source.size
        box = crop_box(size)
        image = source.convert('RGB').crop(box)
        image = image.resize((width, round(image.height * width / image.width)), Image.Resampling.LANCZOS)
    return image, size, box


def timeline(images: list[dict], final_native_elapsed: float | None = None) -> dict:
    if not images:
        raise ValueError('No screenshots')
    times = [float(row['elapsed_s']) for row in images]
    if any(not math.isfinite(t) for t in times) or any(b <= a for a, b in zip(times, times[1:])):
        raise ValueError('Screenshot elapsed_s must be finite and strictly increasing')
    # The final image has no next screenshot. Hold only until the last measured
    # native frame, with the minimum representable10ms GIF hold when needed.
    measured_end = float(final_native_elapsed) if final_native_elapsed is not None else times[-1]
    if not math.isfinite(measured_end):
        raise ValueError('Nonfinite final native time')
    end = max(measured_end, times[-1] + .010)
    quantize = lambda seconds: int(math.floor(seconds * 100 + .5)) * 10
    boundaries = [quantize(t - times[0]) for t in times]
    # Several very close native images may occupy one GIF centisecond. Keep
    # its latest screenshot, while tracing every original PNG separately.
    selected = []
    for index, at in enumerate(boundaries):
        if selected and at == selected[-1][1]:
            selected[-1] = (index, at)
        else:
            selected.append((index, at))
    final_boundary = max(selected[-1][1] + 10, quantize(end - times[0]))
    durations = [b[1] - a[1] for a, b in zip(selected, selected[1:])] + [final_boundary - selected[-1][1]]
    return {'selected_indices': [x[0] for x in selected], 'durations_ms': durations,
            'source_start_s': times[0], 'source_end_s': end,
            'source_duration_s': end - times[0], 'encoded_duration_ms': sum(durations),
            'rounding_error_ms': sum(durations) - (end - times[0]) * 1000,
            'tail_policy': 'last measured native frame, minimum10ms after last screenshot'}


def fixed_palette(frames: list[Image.Image]) -> Image.Image:
    indices = sorted({round(i * (len(frames) - 1) / min(7, len(frames) - 1))
                      for i in range(min(8, len(frames)))}) if len(frames) > 1 else [0]
    thumb_width = 80
    thumb_height = round(frames[0].height * thumb_width / frames[0].width)
    atlas = Image.new('RGB', (thumb_width * len(indices), thumb_height))
    for column, index in enumerate(indices):
        atlas.paste(frames[index].resize((thumb_width, thumb_height), Image.Resampling.LANCZOS), (column * thumb_width, 0))
    return atlas.quantize(colors=256, method=Image.Quantize.MEDIANCUT)


def write_gif(path: Path, frames: list[Image.Image], durations: list[int]) -> dict:
    palette = fixed_palette(frames)
    indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    indexed[0].save(path, save_all=True, append_images=indexed[1:], duration=durations,
                    loop=0, optimize=False, disposal=2)
    with Image.open(path) as decoded:
        actual_durations = []
        for index in range(decoded.n_frames):
            decoded.seek(index)
            actual_durations.append(int(decoded.info.get('duration', 0)))
    if sum(actual_durations) != sum(durations):
        raise ValueError('GIF encoder changed real-time duration')
    return {'file': path.name, 'sha256': digest(path), 'decoded_frame_count': len(actual_durations),
            'decoded_durations_ms': actual_durations, 'decoded_duration_ms': sum(actual_durations),
            'palette_sha256': hashlib.sha256(bytes(palette.getpalette())).hexdigest(),
            'palette_policy': 'one fixed256-color palette per clip/view; no dithering'}


def safe_image(report_folder: Path, case: dict, filename: str) -> Path:
    path = (report_folder / case['image_folder'] / filename).resolve()
    if not path.is_relative_to(report_folder.resolve()) or path.suffix.lower() != '.png':
        raise ValueError('Screenshot must be a PNG inside the native report folder')
    if not path.is_file():
        raise FileNotFoundError(path)
    return path


def nearest_phase(images: list[dict], target: float) -> int:
    return min(range(len(images)), key=lambda index: (
        abs((float(images[index]['phase']) - target + .5) % 1 - .5),
        float(images[index]['elapsed_s'])))


def phase_sheet(actor: str, rows: list[dict], path: Path) -> dict:
    cell_width = 200
    cell_height = 307
    caption_height = 31
    top = 32
    font = ImageFont.load_default(size=14)
    sheet = Image.new('RGB', (cell_width * 8, top + len(rows) * (cell_height + caption_height)), '#17232d')
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 8), f'{actor} | actual native images | eight nearest measured phases; geometry/cloth acceptance separate', fill='white', font=font)
    records = []
    for row_index, row in enumerate(rows):
        y = top + row_index * (cell_height + caption_height)
        for column, tile in enumerate(row['tiles']):
            image = tile['image'].copy()
            image.thumbnail((cell_width - 4, cell_height), Image.Resampling.LANCZOS)
            x = column * cell_width
            sheet.paste(image, (x + (cell_width - image.width) // 2, y + caption_height))
            draw.text((x + 4, y + 1), f"{row['clip']} {row['view']} p{tile['actual_phase']:.3f}", fill='white', font=font)
            draw.text((x + 4, y + 16), f"target{tile['target_phase']:.3f} t{tile['elapsed_s']:.3f}s", fill='#b9d0db', font=font)
            records.append({k: v for k, v in tile.items() if k != 'image'} | {'row': row_index, 'column': column, 'clip': row['clip'], 'view': row['view']})
    sheet.save(path, quality=93, subsampling=0)
    return {'file': path.name, 'sha256': digest(path), 'rows': len(rows), 'tiles': records}


def build(report_path: Path, output: Path | None = None, width: int = 320) -> dict:
    report_path = report_path.resolve()
    if width < 16:
        raise ValueError('Preview width must be at least16 pixels')
    output = (output or report_path.parent.parent / 'motion-previews').resolve()
    output.mkdir(parents=True, exist_ok=True)
    with report_path.open() as stream:
        source = json.load(stream)
    cases = source.get('cases', [])
    identities = set()
    groups = {}
    for case in cases:
        actor, clip, view = case['character'], case['requested_clip'], case.get('view', 'right')
        if clip not in ['walk', 'run']:
            continue
        if not re.fullmatch(r'[a-z0-9_]+', actor) or view not in VIEWS:
            raise ValueError('Unexpected actor/view identity')
        identity = (actor, clip, view)
        if identity in identities:
            raise ValueError('Duplicate actor/clip/view')
        identities.add(identity)
        groups.setdefault(actor, []).append((clip, view, case))
    if not groups:
        raise ValueError('No walk/run cases')
    result = {'scope': __doc__.strip(), 'source_report': str(report_path), 'source_report_sha256': digest(report_path),
              'tool_sha256': digest(Path(__file__)), 'crop_reference_resolution': REFERENCE_SIZE,
              'crop_reference_box': REFERENCE_CROP, 'preview_width': width,
              'timing_policy': 'actual screenshot elapsed_s; cumulative10ms boundary rounding; no deliberate slow motion',
              'cases': [], 'contact_sheets': [], 'source_pngs': []}
    png_hashes = {}
    for actor in sorted(groups, key=lambda name: ACTORS.index(name) if name in ACTORS else len(ACTORS)):
        sheet_rows = []
        for clip, view, case in sorted(groups[actor], key=lambda row: (['walk', 'run'].index(row[0]), VIEWS.index(row[1]))):
            images = case.get('images', [])
            final_time = max((float(frame['elapsed_s']) for frame in case.get('frames', [])), default=None)
            timing = timeline(images, final_time)
            frames, image_records = [], []
            for index, shot in enumerate(images):
                path = safe_image(report_path.parent, case, shot['file'])
                image, size, box = cropped(path, width)
                frames.append(image)
                sha = png_hashes.setdefault(path, digest(path))
                image_records.append({'file': path.relative_to(report_path.parent).as_posix(), 'sha256': sha,
                                      'elapsed_s': float(shot['elapsed_s']), 'phase': float(shot['phase']),
                                      'source_resolution': size, 'crop_box': box})
            stem = f'{actor}-{clip}' + ('-fast' if clip == 'run' and actor != 'sora' else '')
            gif = write_gif(output / f'{stem}-{view}.gif', [frames[i] for i in timing['selected_indices']], timing['durations_ms'])
            aliases = []
            if view == 'right':
                alias = output / f'{stem}.gif'
                shutil.copyfile(output / gif['file'], alias)
                aliases.append({'file': alias.name, 'sha256': digest(alias)})
            tiles = []
            for phase in [i / 8 for i in range(8)]:
                index = nearest_phase(images, phase)
                shot = image_records[index]
                tiles.append({'image': frames[index], 'target_phase': phase, 'actual_phase': shot['phase'],
                              'elapsed_s': shot['elapsed_s'], 'source_file': shot['file'], 'source_sha256': shot['sha256']})
            sheet_rows.append({'clip': clip, 'view': view, 'tiles': tiles})
            record = {'character': actor, 'clip': clip, 'view': view, 'view_was_defaulted': 'view' not in case,
                      'fixture': case.get('fixture'), 'forced_speed_mps': case.get('forced_speed_mps'),
                      'images': image_records, 'timing': timing, 'gif': gif, 'canonical_aliases': aliases}
            result['cases'].append(record)
            print(f"{actor}/{clip}/{view}: {len(frames)} PNGs, {gif['decoded_duration_ms']}ms", flush=True)
        result['contact_sheets'].append(phase_sheet(actor, sheet_rows, output / f'{actor}-walk-run-phases.jpg'))
    result['source_pngs'] = [{'file': str(path), 'sha256': sha} for path, sha in sorted(png_hashes.items())]
    result['original_pngs_unchanged'] = all(digest(path) == sha for path, sha in png_hashes.items())
    if not result['original_pngs_unchanged']:
        raise ValueError('An original PNG changed during conversion')
    result['case_count'] = len(result['cases'])
    result['gif_count_including_aliases'] = sum(1 + len(c['canonical_aliases']) for c in result['cases'])
    (output / 'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument('--input', '--report', dest='report', type=Path)
    inputs.add_argument('--evidence', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--width', type=int, default=320)
    args = parser.parse_args()
    report = args.report
    if args.evidence:
        candidates = [args.evidence / name / 'continuous-gait.json' for name in ['continuous', 'native-preview']]
        report = next((p for p in candidates if p.is_file()), candidates[0])
    result = build(report, args.out, args.width)
    print(json.dumps({'cases': result['case_count'], 'GIFs_with_aliases': result['gif_count_including_aliases'],
                      'contact_sheets': len(result['contact_sheets']), 'original_PNGs_unchanged': result['original_pngs_unchanged']}))


if __name__ == '__main__':
    main()

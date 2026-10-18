#!/usr/bin/env python3
"""Synthetic timing, palette, provenance and legacy-name regression controls."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image, ImageDraw
import motion_previews as previews


class MotionPreviewsTest(unittest.TestCase):
    def test_actual_timing_uses_cumulative_centisecond_boundaries(self):
        rows = [{'elapsed_s': t} for t in [.021, .074, .138, .207]]
        result = previews.timeline(rows, .250)
        self.assertEqual(result['durations_ms'], [50, 70, 70, 40])
        self.assertEqual(result['encoded_duration_ms'], 230)
        self.assertAlmostEqual(result['rounding_error_ms'], 1)
        self.assertNotEqual(result['encoded_duration_ms'], 100 * len(rows))

    def test_close_screenshots_keep_last_in_same_gif_time_bin(self):
        result = previews.timeline([{'elapsed_s': t} for t in [.020, .024, .033]], .044)
        self.assertEqual(result['selected_indices'], [1, 2])
        self.assertTrue(all(d >= 10 for d in result['durations_ms']))
        with self.assertRaises(ValueError):
            previews.timeline([{'elapsed_s': .03}, {'elapsed_s': .02}])

    def test_crop_scales_from_native_resolution(self):
        self.assertEqual(previews.crop_box((1280, 720)), (425, 60, 855, 720))
        self.assertEqual(previews.crop_box((2560, 1440)), (850, 120, 1710, 1440))

    def test_fixed_palette_keeps_static_pixels_stable_and_duration_exact(self):
        with tempfile.TemporaryDirectory() as folder:
            images = []
            for color in ['red', 'green', 'blue', 'yellow']:
                image = Image.new('RGB', (32, 40), (117, 151, 179))
                ImageDraw.Draw(image).rectangle((8, 10, 23, 29), fill=color)
                images.append(image)
            path = Path(folder) / 'test.gif'
            result = previews.write_gif(path, images, [50, 70, 70, 40])
            self.assertEqual(result['decoded_duration_ms'], 230)
            colors = []
            with Image.open(path) as gif:
                for index in range(gif.n_frames):
                    gif.seek(index)
                    colors.append(gif.convert('RGB').getpixel((0, 0)))
            self.assertEqual(len(set(colors)), 1)

    def test_real_outputs_aliases_sources_and_legacy_missing_view(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            capture = root / 'continuous'
            capture.mkdir()
            (root / 'index.html').write_text('existing review UI untouched')
            cases = []
            for actor, views in [('ren', ['front', 'right', 'back']), ('sora', [None])]:
                for clip in ['walk', 'run']:
                    for view in views:
                        stem = f'{actor}-{clip}-{view or "legacy"}'
                        image_folder = capture / stem
                        image_folder.mkdir()
                        rows = []
                        for index, at in enumerate([.021, .074, .138, .207]):
                            image = Image.new('RGB', (128, 72), (100 + index * 20, 130, 160))
                            ImageDraw.Draw(image).rectangle((52, 20, 75, 65), fill=(180, 70 + index * 20, 50))
                            image.save(image_folder / f'{index}.png')
                            rows.append({'file': f'{index}.png', 'elapsed_s': at, 'phase': index / 4})
                        case = {'character': actor, 'requested_clip': clip, 'image_folder': stem,
                                'images': rows, 'frames': [{'elapsed_s': .25}]}
                        if view is not None:
                            case['view'] = view
                        cases.append(case)
            report = capture / 'continuous-gait.json'
            report.write_text(json.dumps({'cases': cases}))
            original = {p: p.read_bytes() for p in capture.rglob('*.png')}
            with contextlib.redirect_stdout(io.StringIO()):
                result = previews.build(report, width=32)
            output = root / 'motion-previews'
            self.assertEqual(result['case_count'], 8)
            self.assertEqual(result['gif_count_including_aliases'], 12)
            self.assertEqual(len(result['contact_sheets']), 2)
            self.assertEqual((output / 'ren-run-fast.gif').read_bytes(), (output / 'ren-run-fast-right.gif').read_bytes())
            self.assertEqual((output / 'sora-run.gif').read_bytes(), (output / 'sora-run-right.gif').read_bytes())
            self.assertFalse((output / 'sora-run-fast.gif').exists())
            self.assertEqual((root / 'index.html').read_text(), 'existing review UI untouched')
            self.assertTrue(all(p.read_bytes() == raw for p, raw in original.items()))
            self.assertTrue(result['original_pngs_unchanged'])
            self.assertEqual(len(result['source_pngs']), 32)
            self.assertTrue(all(c['gif']['decoded_duration_ms'] == 230 for c in result['cases']))
            self.assertEqual([s['rows'] for s in result['contact_sheets']], [2, 6])


if __name__ == '__main__':
    unittest.main()

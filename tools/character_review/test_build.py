"""Offline metadata fixtures only; never rebuild an existing review directory."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('character_review_build', Path(__file__).with_name('build.py'))
review = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(review)


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='harumachi-review-build-')
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        shots = []
        for actor in review.ACTORS:
            for action in review.ACTIONS:
                for view in review.VIEWS:
                    name = f'{actor}-{action}-{view}.png'
                    path = self.folder / 'joint-poses' / name
                    path.parent.mkdir(exist_ok=True)
                    path.write_bytes(f'frame:{actor}/{action}/{view}'.encode())
                    shots.append({'id': actor, 'action': action, 'view': view, 'phase': 0, 'file': name})
        for batch, rows in [('joint-poses', shots), ('locomotion-poses', [])]:
            (self.folder / batch).mkdir(exist_ok=True)
            (self.folder / batch / 'manifest.json').write_text(json.dumps({'shots': rows}))
        self.previews = self.folder / 'motion-previews'
        self.previews.mkdir()

    def build(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return review.build(self.folder)

    def motion_manifest(self, views=('front', 'right', 'back')):
        cases = []
        for view in views:
            name = f'ren-run-fast-{view}.gif'
            path = self.previews / name
            path.write_bytes(('actual gif:' + view).encode())
            cases.append({'character': 'ren', 'clip': 'run', 'view': view,
                          'fixture': 'explicit_NPC_run_speed_fixture_not_story_flow',
                          'forced_speed_mps': 4.5 if view == 'right' else 3.2,
                          'gif': {'file': name, 'sha256': review.digest(path)}})
        (self.previews / 'manifest.json').write_text(json.dumps({'cases': cases}))
        return cases

    def test_legacy_single_motion_keeps_original_dataset_identity(self):
        (self.previews / 'ren-run-fast.gif').write_bytes(b'legacy right gif')
        (self.folder / 'continuous').mkdir()
        (self.folder / 'continuous/continuous-gait.json').write_text(json.dumps({'cases': [
            {'character': 'ren', 'requested_clip': 'run', 'forced_speed_mps': 3.2}]}))
        data = self.build()
        self.assertEqual(data['source_sha256'], '0508fe2daeb5aa3fbe281e6bfc469445e3eabf7efd2dd7c9248bdb5dcd21225f')
        item = next(row for row in data['cases'] if row['id'] == 'ren/run')
        self.assertEqual(item['motion']['label'], '快速移动对照 · 3.2米/秒')
        self.assertFalse(item.get('motion_views'))

    def test_three_or_five_actual_views_have_individual_hashes_and_speeds(self):
        self.motion_manifest(tuple(review.VIEWS))
        data = self.build()
        item = next(row for row in data['cases'] if row['id'] == 'ren/run')
        self.assertEqual(set(item['motion_views']), set(review.VIEWS))
        for view, motion in item['motion_views'].items():
            self.assertEqual(motion['view'], view)
            self.assertEqual(motion['sha256'], review.digest(self.folder / motion['file']))
            self.assertIn('4.5米/秒' if view == 'right' else '3.2米/秒', motion['label'])
        self.assertEqual(item['motion']['view'], 'right')

    def test_nondefault_gif_change_changes_dataset_id_without_touching_static_or_right(self):
        cases = self.motion_manifest()
        first = self.build()
        path = self.previews / cases[0]['gif']['file']
        path.write_bytes(b'reshot front motion')
        cases[0]['gif']['sha256'] = review.digest(path)
        (self.previews / 'manifest.json').write_text(json.dumps({'cases': cases}))
        second = self.build()
        self.assertNotEqual(first['id'], second['id'])
        old = next(row for row in first['cases'] if row['id'] == 'ren/run')
        new = next(row for row in second['cases'] if row['id'] == 'ren/run')
        self.assertEqual(old['frames'], new['frames'])
        self.assertEqual(old['motion'], new['motion'])
        self.assertNotEqual(old['motion_views']['front']['sha256'], new['motion_views']['front']['sha256'])

    def test_stale_manifest_hash_cannot_label_different_gif_as_current_evidence(self):
        cases = self.motion_manifest()
        (self.previews / cases[0]['gif']['file']).write_bytes(b'different unrecorded capture')
        with self.assertRaisesRegex(ValueError, 'SHA'):
            self.build()

    def test_missing_speed_is_labelled_honestly_instead_of_inventing_4point5(self):
        cases = self.motion_manifest()
        cases[0]['forced_speed_mps'] = None
        cases[0]['fixture'] = 'native_runtime_speed'
        (self.previews / 'manifest.json').write_text(json.dumps({'cases': cases}))
        item = next(row for row in self.build()['cases'] if row['id'] == 'ren/run')
        self.assertEqual(item['motion_views']['front']['speed_label'], '游戏实际速度')
        cases[0]['fixture'] = 'explicit_NPC_run_speed_fixture_not_story_flow'
        (self.previews / 'manifest.json').write_text(json.dumps({'cases': cases}))
        item = next(row for row in self.build()['cases'] if row['id'] == 'ren/run')
        self.assertEqual(item['motion_views']['front']['speed_label'], '速度未记录')
        self.assertNotIn('4.5', item['motion_views']['front']['label'])

    def test_manifest_order_does_not_reset_dataset_or_saved_review_identity(self):
        cases = self.motion_manifest()
        original = self.build()
        (self.previews / 'manifest.json').write_text(json.dumps({'cases': list(reversed(cases))}))
        self.assertEqual(self.build()['id'], original['id'])

    def test_missing_report_does_not_render_a_broken_report_entry(self):
        data = self.build()
        html = (self.folder / 'index.html').read_text()
        self.assertNotIn('href="REPORT.html"', html)
        self.assertNotIn('查看之前的审查报告', html)
        self.assertNotIn('__OPTIONAL_REPORT_LINK__', html)
        self.assertEqual(data['case_count'], 49)

    def test_existing_report_retains_entry_without_changing_dataset_identity(self):
        absent = self.build()
        (self.folder / 'REPORT.html').write_text('<h1>Actual earlier report</h1>')
        present = self.build()
        html = (self.folder / 'index.html').read_text()
        self.assertIn('href="REPORT.html"', html)
        self.assertIn('查看之前的审查报告', html)
        self.assertEqual(present, absent)
        self.assertEqual((self.folder / 'REPORT.html').read_text(), '<h1>Actual earlier report</h1>')

    def focused_shots(self):
        path = self.folder / 'joint-poses/manifest.json'
        shots = [row for row in json.loads(path.read_text())['shots'] if row['id'] == 'ren' and row['action'] == 'walk']
        (self.folder / 'joint-poses/manifest.json').write_text(json.dumps({'shots': []}))
        (self.folder / 'locomotion-poses/manifest.json').write_text(json.dumps({'shots': shots}))
        return shots

    def focused_build(self, actors=None, actions=None):
        with contextlib.redirect_stdout(io.StringIO()):
            return review.build(self.folder, actors=['ren'] if actors is None else actors,
                                actions=['walk'] if actions is None else actions)

    def test_focused_one_case_needs_only_its_five_views_with_empty_joint_manifest(self):
        shots = self.focused_shots()
        # A real focused capture is stored under locomotion-poses, not joint.
        for shot in shots:
            name = shot['file']
            (self.folder / 'locomotion-poses' / name).write_bytes((self.folder / 'joint-poses' / name).read_bytes())
        result = self.focused_build()
        self.assertEqual(result['case_count'], 1)
        self.assertEqual(result['frame_count'], 5)
        self.assertEqual([item['id'] for item in result['cases']], ['ren/walk'])
        self.assertEqual({frame['view'] for frame in result['cases'][0]['frames']}, set(review.VIEWS))
        # Incomplete or absent unrelated actors/actions are outside this review.
        with self.assertRaisesRegex(ValueError, 'Missing selected capture'):
            self.build()

    def test_focused_rejects_missing_direction_at_one_selected_phase_before_writing_ui(self):
        shots = self.focused_shots()
        for shot in shots:
            (self.folder / 'locomotion-poses' / shot['file']).write_bytes(b'actual selected view')
        second_phase = [{**shot, 'phase': .5} for shot in shots[:-1]]
        (self.folder / 'locomotion-poses/manifest.json').write_text(json.dumps({'shots': shots + second_phase}))
        with self.assertRaisesRegex(ValueError, 'Incomplete five-direction'):
            self.focused_build()
        self.assertFalse((self.folder / 'index.html').exists())

    def test_focused_does_not_require_unselected_case_files_or_view_completeness(self):
        path = self.folder / 'joint-poses/manifest.json'
        shots = [row for row in json.loads(path.read_text())['shots'] if row['id'] == 'ren' and row['action'] == 'walk']
        shots.append({'id': 'sora', 'action': 'idle', 'view': 'front', 'phase': 0,
                      'file': 'unselected-missing.png', 'diagnostic_hidden_arm_fill': True})
        path.write_text(json.dumps({'shots': shots}))
        data = self.focused_build()
        self.assertEqual(data['case_count'], 1)
        self.assertEqual(data['cases'][0]['id'], 'ren/walk')

    def test_unknown_duplicate_and_empty_selections_are_rejected_without_output(self):
        for actors, actions in [(['unknown'], ['walk']), (['ren'], ['unknown']),
                                (['ren', 'ren'], ['walk']), (['ren'], ['walk', 'walk']),
                                ([], ['walk']), (['ren'], []), ([''], ['walk'])]:
            with self.subTest(actors=actors, actions=actions):
                with self.assertRaisesRegex(ValueError, 'selection'):
                    self.focused_build(actors, actions)
        self.assertFalse((self.folder / 'index.html').exists())

    def test_explicit_complete_selection_keeps_legacy49_golden_and_focus_has_distinct_identity(self):
        (self.previews / 'ren-run-fast.gif').write_bytes(b'legacy right gif')
        (self.folder / 'continuous').mkdir()
        (self.folder / 'continuous/continuous-gait.json').write_text(json.dumps({'cases': [
            {'character': 'ren', 'requested_clip': 'run', 'forced_speed_mps': 3.2}]}))
        with contextlib.redirect_stdout(io.StringIO()):
            default = review.build(self.folder)
            explicit = review.build(self.folder, actors=list(reversed(review.ACTORS)), actions=list(reversed(review.ACTIONS)))
            focused = review.build(self.folder, actors=['ren'], actions=['walk'])
        self.assertEqual(default['case_count'], 49)
        self.assertEqual(default['source_sha256'], '0508fe2daeb5aa3fbe281e6bfc469445e3eabf7efd2dd7c9248bdb5dcd21225f')
        self.assertEqual(explicit['source_sha256'], default['source_sha256'])
        self.assertNotEqual(focused['id'], default['id'])

    def test_focused_cli_and_repeated_or_empty_filter_flags(self):
        shots = self.focused_shots()
        for shot in shots:
            (self.folder / 'locomotion-poses' / shot['file']).write_bytes(b'actual selected view')
        command = [sys.executable, str(Path(review.__file__)), '--evidence', str(self.folder)]
        result = subprocess.run(command + ['--actors', 'ren', '--actions', 'walk'], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['cases'], 1)
        before = (self.folder / 'index.html').read_bytes()
        for flags in [['--actors', 'ren', '--actors', 'ren', '--actions', 'walk'],
                      ['--actors', 'ren', '--actions', 'walk', '--actions', 'walk'],
                      ['--actors'], ['--actions'], ['--actors', 'unknown']]:
            with self.subTest(flags=flags):
                invalid = subprocess.run(command + flags, text=True, capture_output=True)
                self.assertNotEqual(invalid.returncode, 0)
                self.assertEqual((self.folder / 'index.html').read_bytes(), before)


if __name__ == '__main__': unittest.main()

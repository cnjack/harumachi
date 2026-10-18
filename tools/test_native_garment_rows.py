"""Reject stale/incomplete native packets before a cloth audit can claim coverage."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'art/tools/characters'))
from audit_native_garment_surfaces import continuous_rows, measure_surface, rows, static_rows


class ActualGarmentSurface(unittest.TestCase):
    def test_actual_inward_local_cannot_inherit_source_only_pass(self):
        source = np.asarray([[-1., -1., .1], [1., -1., .1], [0., 1., .1],
                             [-1., -1., -.1], [0., 1., -.1], [1., -1., -.1], [0., 0., 0.]])
        state = {'layers': {'front': np.asarray([[0, 1, 2]]), 'back': np.asarray([[3, 4, 5]])}}
        triangles = np.asarray([[6, 6, 6]])
        bary = np.asarray([[1., 0., 0.]])
        coverage = {'front': np.asarray([True]), 'back': np.asarray([True])}
        before = measure_surface(state, source, triangles, bary, coverage)
        actual = source.copy()
        actual[:3, 2] = -.02
        after = measure_surface(state, actual, triangles, bary, coverage)
        self.assertEqual(before['front']['original_normal_gate_all_hit_over5mm'], 0)
        self.assertEqual(after['front']['original_normal_gate_all_hit_over5mm'], 1)
        self.assertAlmostEqual(after['front']['all_hit_max_depth_m'], .02)
        self.assertEqual(after['back'], before['back'])


class NativeGarmentRows(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'continuous').mkdir()
        self.path = self.root / 'continuous/continuous-gait.json'
        self.model = self.root / 'CH_ren.glb'
        self.model.write_bytes(b'exact source identity fixture')
        self.rotation = np.asarray([[0., 0., 1.], [0., 1., 0.], [-1., 0., 0.]])
        self.origin = np.asarray([8., 2., -3.])
        self.local = np.asarray([.1, .9, -.2])
        world = self.rotation @ self.local + self.origin
        frame = {'frame': 11, 'clip': 'walk', 'clip_time': .137, 'phase': .937,
                 'model_basis': self.rotation.T.tolist(), 'model_position': self.origin.tolist(),
                 'bone_transforms': [[*world, *self.rotation.T.ravel()]],
                 'blend_shape_values': {'mesh': {'Garment_Local_Front_0_0': .27}}}
        for trace in ['natural_pose_trace', 'foot_support_trace']:
            frame[trace] = {key: frame[key] for key in ['frame', 'clip', 'clip_time']}
        self.document = {'failures': [], 'cases': [{'character': 'ren', 'requested_clip': 'walk',
                         'view': 'left', 'bone_layout': [{'name': 'mixamorig:LeftLeg', 'parent': -1}],
                         'frames': [frame]}]}
        (self.root / 'model-hashes.json').write_text(json.dumps({'CH_ren.glb': hashlib.sha256(self.model.read_bytes()).hexdigest()}))

    def save(self):
        self.path.write_text(json.dumps(self.document))

    def test_real_world_transform_is_reversed_without_resampling_time_or_shapes(self):
        self.save()
        result = rows(SimpleNamespace(input=self.model, native=self.path, character='ren'))[0]
        np.testing.assert_allclose(result['bones'][0]['position'], self.local, atol=1e-14)
        np.testing.assert_allclose(result['bones'][0]['basis'], np.eye(3), atol=1e-14)
        self.assertEqual((result['clip_time'], result['phase'], result['view']), (.137, .937, 'left'))
        self.assertEqual(result['blend_shape_values'], self.document['cases'][0]['frames'][0]['blend_shape_values'])

    def test_wrong_source_bytes_are_rejected_before_reading_poses(self):
        self.save()
        self.model.write_bytes(b'a different model')
        with self.assertRaisesRegex(ValueError, 'source hash'):
            rows(SimpleNamespace(input=self.model, native=self.path, character='ren'))

    def test_stale_final_modifier_trace_is_rejected(self):
        self.document['cases'][0]['frames'][0]['foot_support_trace']['frame'] -= 1
        self.save()
        with self.assertRaisesRegex(ValueError, 'Stale'):
            list(continuous_rows(self.path, 'ren'))

    def test_incomplete_bone_packet_is_rejected(self):
        self.document['cases'][0]['frames'][0]['bone_transforms'][0].pop()
        self.save()
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            list(continuous_rows(self.path, 'ren'))

    def test_duplicate_process_frame_is_rejected(self):
        self.document['cases'][0]['frames'] *= 2
        self.save()
        with self.assertRaisesRegex(ValueError, 'frame order'):
            list(continuous_rows(self.path, 'ren'))

    def test_unexpected_clip_is_rejected(self):
        self.document['cases'][0]['frames'][0]['clip'] = 'idle'
        self.save()
        with self.assertRaisesRegex(ValueError, 'clip mismatch'):
            list(continuous_rows(self.path, 'ren'))

    def test_nonfinite_timing_or_geometry_is_rejected(self):
        for field in ['clip_time', 'bone_transforms']:
            with self.subTest(field=field):
                original = copy.deepcopy(self.document)
                frame = self.document['cases'][0]['frames'][0]
                if field == 'clip_time': frame[field] = float('nan')
                else: frame[field][0][0] = float('inf')
                self.save()
                with self.assertRaisesRegex(ValueError, 'Non-finite'):
                    list(continuous_rows(self.path, 'ren'))
                self.document = original

    def test_missing_character_cannot_be_an_empty_success(self):
        self.save()
        with self.assertRaisesRegex(ValueError, 'no complete character frames'):
            list(continuous_rows(self.path, 'mio'))

    def test_static_manifest_cannot_silently_be_an_empty_engine_log(self):
        unsupported = self.root / 'continuous/manifest.json'
        unsupported.write_text(json.dumps({'failures': [], 'shots': []}))
        with self.assertRaisesRegex(ValueError, 'no complete character samples'):
            rows(SimpleNamespace(input=self.model, native=unsupported, character='ren'))

    def static_fixture(self):
        frame = self.document['cases'][0]['frames'][0]
        return {'failures': [], 'shots': [dict(id='ren', file='frame.png', clip='walk', clip_time=.137, phase=.937, view='left',
                model_position=self.origin.tolist(), model_basis=self.rotation.T.tolist(),
                bones=[dict(name='mixamorig:LeftLeg', position=frame['bone_transforms'][0][:3], basis=self.rotation.T.tolist())],
                blend_shape_values=frame['blend_shape_values'],
                pose_sample=dict(request_id=1, acknowledged_request=1, applied_frame=11, captured_frame=11, clip='walk', clip_time=.137))]}

    def test_static_final_packet_uses_explicit_model_inverse(self):
        self.path.write_text(json.dumps(self.static_fixture()))
        actual = list(static_rows(self.path, 'ren'))[0]
        np.testing.assert_allclose(actual['bones'][0]['position'], self.local, atol=1e-14)
        np.testing.assert_allclose(actual['bones'][0]['basis'], np.eye(3), atol=1e-14)
        self.assertEqual(actual['blend_shape_values'], self.document['cases'][0]['frames'][0]['blend_shape_values'])

    def test_static_stale_callback_is_rejected(self):
        data = self.static_fixture()
        data['shots'][0]['pose_sample']['captured_frame'] += 1
        self.path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'Stale'):
            list(static_rows(self.path, 'ren'))

    def test_older_static_packet_without_explicit_transform_is_rejected(self):
        data = self.static_fixture()
        del data['shots'][0]['model_basis']
        self.path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'explicit model transform'):
            list(static_rows(self.path, 'ren'))

    def test_nonfinite_static_timing_is_rejected(self):
        data = self.static_fixture()
        data['shots'][0]['pose_sample']['clip_time'] = float('nan')
        self.path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'Non-finite'):
            list(static_rows(self.path, 'ren'))

    def test_engine_log_without_matching_source_samples_is_rejected(self):
        empty_log = self.root / 'engine.log'
        empty_log.write_text('Godot Engine v4.8\nNo character surface packets\n')
        with self.assertRaisesRegex(ValueError, 'no complete character samples'):
            rows(SimpleNamespace(input=self.model, native=empty_log, character='ren'))


if __name__ == '__main__':
    unittest.main()

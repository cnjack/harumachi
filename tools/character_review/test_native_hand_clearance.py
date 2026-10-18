"""Final-bone coordinate/morph and real-crossing controls; no Godot required."""
from pathlib import Path
import copy
import sys
import unittest
from unittest.mock import patch
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'art/tools/characters'))
import audit_run_hand_clearance as audit


def fixture():
    # Rotated and nonuniformly scaled model, with a different actor position.
    # Expected model points are [1,2,3] and [-1,1,2], respectively.
    row = {'model_basis': [[0, 2, 0], [-3, 0, 0], [0, 0, 4]],
           'model_position': [10, -7, 5], 'position': [-100, 100, 200],
           'bones': [
               {'name': 'mixamorig_Hips', 'position': [4, -5, 17],
                'basis': [[0, 2, 0], [-3, 0, 0], [0, 0, 4]]},
               {'name': 'mixamorig_LeftHand', 'position': [7, -9, 13],
                'basis': [[0, 0, -4], [-3, 0, 0], [0, 2, 0]]}],
           'blend_shape_values': {'Body': {'ActualRuntime': 1.0}}}
    doc = {'nodes': [{'name': 'mixamorig:Hips'}, {'name': 'mixamorig:LeftHand'}]}
    mesh = {'positions': np.array([[.1, .2, .3]]),
            'names': ['ActualRuntime'], 'shapes': [np.array([[0, .1, 0]])],
            'node': {'name': 'Body'}, 'skin': {'joints': [0, 1]},
            'binds': np.array([np.eye(4), np.eye(4)]),
            'joints': np.array([[0, 1]]), 'weights': np.array([[.25, .75]])}
    return {'doc': doc, 's': mesh}, row


class NativeHandClearanceTests(unittest.TestCase):
    def test_complete_basis_model_inverse_and_actual_morph_skinning(self):
        state, row = fixture()
        worlds = audit.native_bone_worlds(state['doc'], [0, 1], row)
        np.testing.assert_allclose(worlds[0][:3, :3], np.eye(3), atol=1e-14)
        np.testing.assert_allclose(worlds[0][:3, 3], [1, 2, 3], atol=1e-14)
        np.testing.assert_allclose(worlds[1][:3, 3], [-1, 1, 2], atol=1e-14)
        np.testing.assert_allclose(worlds[1][:3, :3], [[0, 0, 1], [0, 1, 0], [-1, 0, 0]], atol=1e-14)
        # Analytic weighted point: .25*[1.1,2.3,3.3] + .75*[-.7,1.3,1.9].
        points, actual = audit.native_points(state, row)
        np.testing.assert_allclose(points, [[-.25, 1.55, 2.25]], atol=1e-14)
        self.assertEqual(actual, {'ActualRuntime': 1.0})
        row['blend_shape_values']['Body']['ActualRuntime'] = 0
        unchanged, _ = audit.native_points(state, row)
        np.testing.assert_allclose(unchanged, [[-.25, 1.45, 2.25]], atol=1e-14)

    def test_missing_or_ambiguous_final_skin_joints_never_fall_back_to_source(self):
        state, row = fixture()
        missing = copy.deepcopy(row)
        missing['bones'].pop()
        with self.assertRaisesRegex(ValueError, 'required skin joint'):
            audit.native_bone_worlds(state['doc'], [0, 1], missing)
        duplicate = copy.deepcopy(row)
        duplicate['bones'].append({'name': 'mixamorig:Hips'})
        with self.assertRaisesRegex(ValueError, 'duplicate bone'):
            audit.native_bone_worlds(state['doc'], [0, 1], duplicate)
        incomplete = copy.deepcopy(row)
        incomplete['bones'][0].pop('basis')
        with self.assertRaisesRegex(ValueError, 'complete final transform'):
            audit.native_bone_worlds(state['doc'], [0, 1], incomplete)

    def test_missing_nonfinite_or_singular_model_transform_is_rejected(self):
        state, row = fixture()
        for key, value in [('model_basis', [[0, 0, 0]] * 3),
                           ('model_position', [0, float('nan'), 0]),
                           ('model_basis', [[1, 0, 0], [0, float('inf'), 0], [0, 0, 1]])]:
            changed = copy.deepcopy(row)
            changed[key] = value
            with self.assertRaises(ValueError):
                audit.native_bone_worlds(state['doc'], [0, 1], changed)
        row.pop('model_position')
        with self.assertRaisesRegex(ValueError, 'model_position'):
            audit.native_bone_worlds(state['doc'], [0, 1], row)

    def test_actual_shape_table_is_complete_finite_and_names_the_real_mesh(self):
        state, row = fixture()
        for table in [{}, {'AnotherMesh': {'ActualRuntime': 1}}, {'Body': {}},
                      {'Body': {'ActualRuntime': 1, 'UnknownRuntimeShape': .5}},
                      {'Body': {'ActualRuntime': float('nan')}},
                      {'Body': {'ActualRuntime': [1, 2]}}]:
            row['blend_shape_values'] = table
            with self.assertRaises(ValueError):
                audit.native_morph_positions(state['s'], row)

    def test_exact_edge_domain_rejects_crossing_even_with_zero_paired_queries(self):
        # A hand edge crosses one real coat triangle. A one-sided sheet cannot
        # enclose volume, so paired-ray counts alone miss this exact crossing.
        points = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0],
                           [.25, .25, -.1], [.25, .25, .1]], dtype=float)
        empty_faces = np.empty((0, 3), dtype=int)
        state = {'torso_faces': np.array([[0, 1, 2]]), 'torso_ids': np.array([123]),
                 'hands': {side: {'vertices': np.array([3, 4]), 'faces': empty_faces,
                                  'edges': np.array([[3, 4]])} for side in ['Left', 'Right']}}
        measured = audit.measure(state, points, 'Left')
        crossings = audit.exact_edge_intersections(state, points)
        self.assertEqual(measured['paired_queries'], 0)
        self.assertEqual(crossings['Left']['exact_hand_edge_crossing_count'], 1)
        self.assertEqual(crossings['Left']['crossing_examples'][0]['torso_source_face'], 123)

    def test_native_entry_rejects_empty_or_partial_semantic_domains(self):
        state = {'doc': {'nodes': [{'name': 'Rig', 'extras': {'character_id': 'tanaka'}}]},
                 'torso_faces': np.array([[0, 1, 2]]),
                 'hands': {side: {'vertices': np.array([0, 1, 2]),
                                  'faces': np.array([[0, 1, 2]]),
                                  'edges': np.array([[0, 1], [1, 2], [0, 2]])}
                           for side in ['Left', 'Right']}}
        counts = audit.native_domain_coverage(state)
        self.assertEqual(counts['hands']['Left']['edges'], 3)
        for side in ['Left', 'Right']:
            for key, shape in [('vertices', (0,)), ('faces', (0, 3)), ('edges', (0, 2))]:
                changed = copy.deepcopy(state)
                changed['hands'][side][key] = np.empty(shape, dtype=int)
                # Exercise the actual native entry before file/provenance work;
                # an empty hand must not become an all-zero successful summary.
                with patch.object(audit, 'prepare', return_value=changed):
                    with self.assertRaisesRegex(ValueError, 'semantic hand domain.*' + side):
                        audit.audit_native(Path('unused.glb'), Path('unused/manifest.json'))
        state['torso_faces'] = np.empty((0, 3), dtype=int)
        with patch.object(audit, 'prepare', return_value=state):
            with self.assertRaisesRegex(ValueError, 'blue-torso face domain is empty'):
                audit.audit_native(Path('unused.glb'), Path('unused/manifest.json'))

    def test_native_acknowledgement_time_must_be_finite_and_same_sample(self):
        row = {'clip_time': .25, 'phase': .5,
               'pose_sample': {'request_id': 7, 'acknowledged_request': 7,
                               'applied_frame': 21, 'captured_frame': 21,
                               'clip': 'run', 'clip_time': .25}}
        self.assertEqual(audit.native_sample_clock(row), (.25, .5))
        for value in [float('nan'), float('inf'), -float('inf'), None, .26]:
            changed = copy.deepcopy(row)
            changed['pose_sample']['clip_time'] = value
            with self.assertRaises(ValueError):
                audit.native_sample_clock(changed)
        row['pose_sample']['captured_frame'] += 1
        with self.assertRaisesRegex(ValueError, 'same-frame'):
            audit.native_sample_clock(row)


if __name__ == '__main__':
    unittest.main()

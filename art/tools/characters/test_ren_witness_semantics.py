"""Small topology regression fixtures; requires numpy/scipy/Pillow, no assets."""
import unittest
from unittest.mock import patch

import numpy as np

import audit_native_garment_surfaces as audit


class IsolatedClothingAnchorTests(unittest.TestCase):
    def setUp(self):
        angle = np.arange(8) * np.pi / 4
        ring = np.c_[np.cos(angle) * .01, np.sin(angle) * .01, np.full(8, -.12)]
        self.positions = np.r_[[[0., 0., -.12]], ring, [[1., 0., 0.], [1., 1., 0.], [1., 0., 1.]]]
        fan = np.asarray([[0, i + 1, (i + 1) % 8 + 1] for i in range(8)])
        self.faces = np.r_[fan, [[9, 10, 11]]]
        self.paint = np.asarray([[1, 2, 3], [3, 4, 5], [5, 6, 7], [7, 8, 1]])
        self.color = np.ones((12, 3))
        self.color[0] = [.7686, .7373, .6784]
        shape = np.zeros_like(self.positions)
        shape[1:9, 2] = -.02
        self.state = {'d': {'meshes': [{'primitives': [{'indices': 0}]}]}, 'b': b'',
                      'node': {'mesh': 0}, 'positions': self.positions,
                      'joints': np.zeros((12, 1), int), 'weights': np.ones((12, 1)),
                      'body': np.asarray([0, 9, 10, 11]), 'body_faces': np.asarray([[9, 10, 11]]),
                      'names': ['Garment_Local_Back_0_0'], 'shapes': [shape],
                      'layers': {'front': np.empty((0, 3), int), 'back': self.paint}}

    def classify(self):
        with patch.object(audit, 'read', return_value=self.faces), patch.object(audit, 'colours', return_value=self.color):
            return audit.isolated_pigment_clothing_anchors(self.state)

    def test_warm_texel_surrounded_by_independent_cloth_is_clothing(self):
        result = self.classify()
        self.assertEqual([entry['vertex'] for entry in result], [0])
        self.assertEqual(result[0]['side'], 'back')
        self.assertEqual(len(result[0]['incident_source_faces']), 8)

    def test_any_pure_body_triangle_preserves_anchor(self):
        self.state['body_faces'] = np.r_[self.state['body_faces'], [[0, 1, 2]]]
        self.assertEqual(self.classify(), [])

    def test_uv_copy_on_true_body_preserves_anchor(self):
        self.state['positions'] = np.r_[self.positions, self.positions[[0]]]
        self.state['joints'] = np.zeros((13, 1), int)
        self.state['weights'] = np.ones((13, 1))
        self.state['shapes'] = [np.r_[self.state['shapes'][0], [[0., 0., 0.]]]]
        self.state['body'] = np.r_[self.state['body'], [12]]
        self.state['body_faces'] = np.r_[self.state['body_faces'], [[12, 9, 10]]]
        self.faces = np.r_[self.faces, [[12, 9, 10]]]
        self.color = np.r_[self.color, self.color[[0]]]
        self.assertEqual(self.classify(), [])

    def test_local_support_cannot_replace_independent_paint(self):
        self.state['layers']['back'] = self.paint[~np.any(self.paint == 3, axis=1)]
        self.assertEqual(self.classify(), [])

    def test_one_unsupported_neighbor_preserves_anchor(self):
        self.state['shapes'][0][3] = 0
        self.assertEqual(self.classify(), [])

    def test_exact_one_micrometre_is_below_strict_exclusion(self):
        self.state['shapes'][0][3, 2] = -1e-6
        self.assertEqual(self.classify(), [])


if __name__ == '__main__':
    unittest.main()

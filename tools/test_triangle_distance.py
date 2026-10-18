#!/usr/bin/env python3
"""Independent exact-surface controls for the read-only garment-distance BVH."""
import sys
from pathlib import Path
import unittest
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'art/tools/characters'))
from triangle_distance import closest_points


class SurfaceDistanceContracts(unittest.TestCase):
    def test_triangle_interior_edge_and_vertex(self):
        v = np.array([[0., 0, 0], [10, 0, 0], [0, 10, 0]])
        q = np.array([[3., 3, 2], [6, 6, 2], [-1, -1, 0]])
        distance, face, points = closest_points(v, [[0, 1, 2]], q)
        np.testing.assert_allclose(distance, [2, np.sqrt(6), np.sqrt(2)], atol=1e-12)
        np.testing.assert_allclose(points, [[3, 3, 0], [5, 5, 0], [0, 0, 0]], atol=1e-12)
        self.assertGreater(np.linalg.norm(v-q[0], axis=1).min(), distance[0]+1)
        np.testing.assert_array_equal(face, [0, 0, 0])

    def test_degenerate_triangles_still_contribute(self):
        distance, face, points = closest_points([[0., 0, 0], [2, 0, 0], [1, 0, 0]],
                                                [[0, 0, 0], [0, 1, 2]], [[1, .1, .2]])
        np.testing.assert_allclose(distance, [np.sqrt(.05)], atol=1e-12)
        np.testing.assert_allclose(points, [[1, 0, 0]], atol=1e-12)
        self.assertEqual(face[0], 1)

    def test_equal_faces_return_original_first_face(self):
        _, face, _ = closest_points([[0., 0, 0], [1, 0, 0], [0, 1, 0]],
                                    np.tile([[0, 1, 2]], (40, 1)), [[.2, .2, .1]])
        self.assertEqual(face[0], 0)

    def test_bvh_matches_exhaustive_active_set_oracle(self):
        # Independent exhaustive constrained least-squares: unconstrained
        # barycentric plane solution plus every edge's endpoint constraints.
        rng = np.random.default_rng(725)
        vertices = rng.normal(size=(111, 3))
        faces = rng.integers(0, len(vertices), size=(200, 3))
        queries = rng.normal(size=(80, 3))
        queries[0] = [50, 20, 30]
        a, b, c = (vertices[faces[:, k]] for k in range(3))
        e, g = b-a, c-a
        ee, eg, gg = (np.einsum('ij,ij->i', x, y) for x, y in [(e, e), (e, g), (g, g)])
        determinant = ee*gg-eg*eg
        safe = np.where(determinant == 0, 1, determinant)
        expected = []
        for point in queries:
            ap = point-a
            ae, ag = np.einsum('ij,ij->i', ap, e), np.einsum('ij,ij->i', ap, g)
            u, v = (gg*ae-eg*ag)/safe, (ee*ag-eg*ae)/safe
            inside = (determinant > 1e-20) & (u >= 0) & (v >= 0) & (u+v <= 1)
            projected = a+u[:, None]*e+v[:, None]*g
            square = np.where(inside, np.sum((point-projected)**2, axis=1), np.inf)
            for x, y in [(a, b), (b, c), (c, a)]:
                edge = y-x
                norm = np.einsum('ij,ij->i', edge, edge)
                fraction = np.clip(np.einsum('ij,ij->i', point-x, edge)/np.where(norm == 0, 1, norm), 0, 1)
                candidate = x+fraction[:, None]*edge
                square = np.minimum(square, np.sum((point-candidate)**2, axis=1))
            expected.append(np.sqrt(square.min()))
        distance, face, points = closest_points(vertices, faces, queries)
        np.testing.assert_allclose(distance, expected, atol=1e-12, rtol=0)
        np.testing.assert_allclose(np.linalg.norm(queries-points, axis=1), distance, atol=1e-12, rtol=0)
        self.assertTrue(np.all((face >= 0) & (face < len(faces))))

    def test_invalid_surface_is_not_empty_coverage_success(self):
        with self.assertRaises(ValueError):
            closest_points([[0., 0, 0]], [[0, 0, 2]], [[0, 0, 0]])
        with self.assertRaises(ValueError):
            closest_points([[0., 0, 0]], np.empty((0, 3), dtype=int), [[0, 0, 0]])
        with self.assertRaises(ValueError):
            closest_points([[0., 0, 0]], [[0, 0, 0]], [[np.nan, 0, 0]])


if __name__ == '__main__':
    unittest.main()

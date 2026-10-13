"""Measure closed, connected primary bark separately from intentional leaf cards."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

from model_audit import load, primitives

ROOT = Path(__file__).resolve().parents[2]
IDS = ['T07_summer_maple', 'T08_green_cherry', 'T10_weeping_willow', 'T11_young_zelkova']


def audit(path):
    gltf, binary = load(path)
    parts = [v[indices] for part, v, indices, _ in primitives(gltf, binary)
             if part['_node_name'] == 'Trunk_' + path.stem]
    if not parts:
        return {'passed': False, 'error': 'primary trunk mesh missing'}
    faces = np.concatenate(parts)
    points = faces.reshape(-1, 3)
    cross = np.cross(faces[:, 1] - faces[:, 0], faces[:, 2] - faces[:, 0])
    areas = np.linalg.norm(cross, axis=1) * .5
    tolerance = max(float(np.ptp(points, axis=0).max()) * 1e-6, 1e-8)
    unique, inverse = np.unique(np.round(points / tolerance).astype(np.int64), axis=0, return_inverse=True)
    indices = inverse.reshape(-1, 3)
    edges = np.concatenate([indices[:, [0, 1]], indices[:, [1, 2]], indices[:, [2, 0]]])
    edges.sort(axis=1)
    edges, counts = np.unique(edges, axis=0, return_counts=True)
    graph = coo_matrix((np.ones(len(edges)), (edges[:, 0], edges[:, 1])), shape=(len(unique), len(unique)))
    components, labels = connected_components(graph, directed=False)
    component_areas = np.bincount(labels[indices[:, 0]], weights=areas)
    boundary = float(np.mean(counts == 1))
    dominant = float(component_areas.max() / areas.sum())
    return {'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'source_mtime': path.stat().st_mtime, 'primary_triangles': len(faces),
            'components': int(components), 'boundary_edge_fraction': boundary,
            'largest_component_area_fraction': dominant,
            'passed': boundary <= .005 and dominant >= .95}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=ROOT / 'game/assets/models/_stats/_diversity_bark.json')
    args = parser.parse_args()
    result = {aid: audit(ROOT / 'game/assets/models' / (aid + '.glb')) for aid in IDS}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({'models': result, 'passed': all(r['passed'] for r in result.values())}, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()

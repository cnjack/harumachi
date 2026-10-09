"""Separate existing Rodin groceries and measure the actual CRT glass, retaining UVs.

Run with the project numpy/Pillow Python. No generation or paid API calls.
The original W14/W18 exports and their embedded diffuse images stay untouched.
"""
from pathlib import Path
import copy
import hashlib
import io
import json
import struct

import numpy as np
from PIL import Image
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

from edit_model_atlas import load
from model_audit import accessor

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / 'art/models/raw/shop_refresh_20261009'
IDS = ['W19_flour_bag', 'W20_milk_carton', 'W21_tea_tin', 'W22_soy_bottle', 'W23_egg_carton']


def save_glb(model, binary, path):
    model['buffers'][0]['byteLength'] = len(binary)
    header = json.dumps(model, separators=(',', ':')).encode()
    header += b' ' * (-len(header) % 4)
    binary += b'\0' * (-len(binary) % 4)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(struct.pack('<III', 0x46546C67, 2, 28 + len(header) + len(binary))
                     + struct.pack('<II', len(header), 0x4E4F534A) + header
                     + struct.pack('<II', len(binary), 0x004E4942) + binary)


def separate_groceries():
    source = ROOT / 'game/assets/models/W14_grocery_stock.glb'
    model, binary = load(source)
    primitive = model['meshes'][0]['primitives'][0]
    vertices = accessor(model, binary, primitive['attributes']['POSITION'])
    faces = accessor(model, binary, primitive['indices']).reshape(-1, 3)
    _, welded = np.unique(np.round(vertices, 5), axis=0, return_inverse=True)
    edges = welded[faces]
    graph = coo_matrix((np.ones(len(faces) * 3),
                       (edges[:, [0, 1, 2]].ravel(), edges[:, [1, 2, 0]].ravel())),
                      shape=(welded.max() + 1, welded.max() + 1)).tocsr()
    _, labels = connected_components(graph, directed=False)
    face_labels = labels[welded[faces[:, 0]]]
    groups = np.zeros(len(faces), dtype=int)
    for label in np.unique(face_labels):
        selected = face_labels == label
        points = vertices[np.unique(faces[selected])]
        x, y, z = points.mean(axis=0)
        high = points[:, 1].max()
        if x < -.102:
            group = 0
        elif x < .023:
            group = 1 if z < -.008 else 2
        elif x < .115 and (high > .15 or (y > .035 and z < .025)):
            group = 3
        else:
            group = 4
        if group == 2 and points[:, 0].min() < -.10:group = 0
        groups[selected] = group
    report = {}
    for group, asset_id in enumerate(IDS):
        selected_faces = faces[groups == group]
        old_indices, inverse = np.unique(selected_faces.ravel(), return_inverse=True)
        data = copy.deepcopy(model)
        payload = bytearray(binary)
        attributes = {}
        def append_array(values, kind, component_type):
            payload.extend(b'\0' * (-len(payload) % 4))
            offset = len(payload)
            payload.extend(values.tobytes())
            data['bufferViews'].append({'buffer': 0, 'byteOffset': offset, 'byteLength': values.nbytes})
            item = {'bufferView': len(data['bufferViews']) - 1, 'componentType': component_type,
                    'count': len(values), 'type': kind}
            if kind == 'VEC3':
                item.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
            data['accessors'].append(item)
            return len(data['accessors']) - 1
        points = vertices[old_indices].copy()
        centre = (points.min(axis=0) + points.max(axis=0)) / 2
        centre[1] = points[:, 1].min()
        for name, index in primitive['attributes'].items():
            values = accessor(model, binary, index)[old_indices].astype('<f4')
            if name == 'POSITION':values -= centre
            attributes[name] = append_array(values, model['accessors'][index]['type'], 5126)
        new_indices = append_array(inverse.astype('<u4'), 'SCALAR', 5125)
        data['meshes'] = [{'name': asset_id, 'primitives': [{'attributes': attributes,
                          'indices': new_indices, 'material': primitive.get('material', 0)}]}]
        data['nodes'] = [{'name': asset_id, 'mesh': 0}]
        data['scenes'] = [{'nodes': [0]}];data['scene'] = 0
        output = RAW / (asset_id + '.glb');save_glb(data, bytes(payload), output)
        report[asset_id] = {'source': str(source.relative_to(ROOT)),
                            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                            'raw': str(output.relative_to(ROOT)), 'triangles': len(selected_faces),
                            'size_xyz': (points.max(axis=0) - points.min(axis=0)).tolist(),
                            'uv_and_diffuse_retained': True}
    (RAW / 'groceries.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Separated groceries:', {k: v['triangles'] for k, v in report.items()}, flush=True)


def measure_glass():
    source = ROOT / 'game/assets/models/W18_retro_tv.glb'
    model, binary = load(source);p = model['meshes'][0]['primitives'][0]
    vertices = accessor(model, binary, p['attributes']['POSITION'])
    uv = accessor(model, binary, p['attributes']['TEXCOORD_0'])
    indices = accessor(model, binary, p['indices']).reshape(-1, 3)
    triangles = vertices[indices]
    first = triangles[:, 1] - triangles[:, 0];second = triangles[:, 2] - triangles[:, 0]
    determinant = first[:, 0] * second[:, 1] - first[:, 1] * second[:, 0]
    valid = np.abs(determinant) > 1e-8
    triangles = triangles[valid];indices = indices[valid]
    first = first[valid];second = second[valid];determinant = determinant[valid]
    view = model['bufferViews'][model['images'][0]['bufferView']]
    texture = np.array(Image.open(io.BytesIO(binary[view['byteOffset']:view['byteOffset'] + view['byteLength']])).convert('RGB'))
    def hit(x, y):
        delta = np.array([x, y]) - triangles[:, 0, :2]
        u = (delta[:, 0] * second[:, 1] - delta[:, 1] * second[:, 0]) / determinant
        v = (first[:, 0] * delta[:, 1] - first[:, 1] * delta[:, 0]) / determinant
        z = triangles[:, 0, 2] + u * first[:, 2] + v * second[:, 2]
        z[(u < -1e-6) | (v < -1e-6) | (u + v > 1 + 1e-6)] = -np.inf
        index = np.argmax(z)
        if not np.isfinite(z[index]):return None, False
        tex_uv = uv[indices[index, 0]] + u[index] * (uv[indices[index, 1]] - uv[indices[index, 0]]) + v[index] * (uv[indices[index, 2]] - uv[indices[index, 0]])
        colour = texture[int(np.clip(tex_uv[1], 0, .9999) * texture.shape[0]), int(np.clip(tex_uv[0], 0, .9999) * texture.shape[1])]
        glass = colour[0] < 35 and colour[1] > 32 and colour[2] > 30 and z[index] > .11
        return float(z[index]), glass
    measured = [];rows = []
    for y in np.linspace(.086, .347, 49):
        samples = []
        for x in np.linspace(-.228, .143, 220):
            z, glass = hit(x, y)
            if glass:samples.append((x, y, z))
        if len(samples) < 18:continue
        measured.extend(samples)
        rows.append((y, samples[1][0] + .0008, samples[-2][0] - .0008))
    assert len(rows) >= 40, 'Glass aperture not detected'
    points = np.array(measured)
    def design(x, y):return np.array([1., x, y, x*x, x*y, y*y])
    matrix = np.array([design(x, y) for x, y, z in points]);coefficients = np.linalg.lstsq(matrix, points[:, 2], rcond=None)[0]
    # Fill the source's tiny holes with the measured smooth glass, but retain real depth elsewhere.
    output = [];columns = 49
    for row_index, (y, left, right) in enumerate(reversed(rows)):
        for column, x in enumerate(np.linspace(left, right, columns)):
            z, glass = hit(x, y)
            fitted = float(design(x, y) @ coefficients)
            if not glass or abs(z - fitted) > .004:z = fitted
            output.append([round(float(x), 7), round(float(y), 7), round(float(z + .0018), 7),
                           column / (columns - 1), row_index / (len(rows) - 1)])
    result = {'source_model': 'W18_retro_tv', 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'columns': columns, 'rows': len(rows), 'points': output, 'glass_offset_m': .0018,
              'measured_points': len(measured), 'glass_fit_coefficients': coefficients.tolist(),
              'note': 'Actual frontmost triangle depths and diffuse glass aperture. Small source holes use the fitted quadratic glass. UVs follow the rounded silhouette.'}
    target = ROOT / 'game/data/shop_tv_surface.json';target.write_text(json.dumps(result, separators=(',', ':')) + '\n')
    (RAW / 'television-surface.json').write_text(json.dumps({k: v for k, v in result.items() if k != 'points'}, indent=2) + '\n')
    print('Measured CRT:', len(output), 'vertices,', len(measured), 'source samples', flush=True)


if __name__ == '__main__':
    RAW.mkdir(parents=True, exist_ok=True)
    separate_groceries()
    measure_glass()

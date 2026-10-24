"""Measure the actual UV-mapped timber colours in the seven plaza furniture assets.

Uses embedded GLB images and surface-area-weighted triangle samples. This is an
albedo audit, not a substitute for the fixed-camera native-render comparison.
"""
import argparse
import io
import json
from pathlib import Path
import struct

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
IDS = ('A12_bench', 'P01', 'P03', 'P05', 'P09', 'P10', 'MS14_event_board')
TYPES = {5121: 'u1', 5123: '<u2', 5125: '<u4', 5126: '<f4'}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def linear(value):
    return np.where(value <= .04045, value / 12.92, ((value + .055) / 1.055) ** 2.4)


def srgb(value):
    return np.where(value <= .0031308, value * 12.92, 1.055 * value ** (1 / 2.4) - .055)


def load(path):
    raw = path.read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20 + length])
    return document, raw[28 + length:]


def accessor(document, binary, number):
    item = document['accessors'][number]
    view = document['bufferViews'][item['bufferView']]
    dtype = np.dtype(TYPES[item['componentType']])
    width = WIDTHS[item['type']]
    start = view.get('byteOffset', 0) + item.get('byteOffset', 0)
    stride = view.get('byteStride', width * dtype.itemsize)
    return np.ndarray((item['count'], width), dtype, binary, start,
                      strides=(stride, dtype.itemsize)).copy()


def timber_role(asset, role):
    return (role.startswith('CedarAge_') or role == 'P09_Cedar_Maintained'
            or asset in ('A12_bench', 'P03', 'MS14_event_board'))


def samples(path):
    document, binary = load(path)
    images = {}
    output = {}
    for mesh in document['meshes']:
        for primitive in mesh['primitives']:
            material = document['materials'][primitive['material']]
            role = material['name']
            if not timber_role(path.stem, role):
                continue
            positions = accessor(document, binary, primitive['attributes']['POSITION'])
            indices = accessor(document, binary, primitive['indices']).ravel() if 'indices' in primitive else np.arange(len(positions))
            triangles = positions[indices.reshape(-1, 3)]
            weights = np.linalg.norm(np.cross(triangles[:, 1] - triangles[:, 0],
                                             triangles[:, 2] - triangles[:, 0]), axis=1) * .5
            pbr = material.get('pbrMetallicRoughness', {})
            colour = np.array(pbr.get('baseColorFactor', [1, 1, 1, 1])[:3])
            if 'baseColorTexture' in pbr:
                texture_index = pbr['baseColorTexture']['index']
                image_index = document['textures'][texture_index]['source']
                if image_index not in images:
                    image = document['images'][image_index]
                    view = document['bufferViews'][image['bufferView']]
                    start = view.get('byteOffset', 0)
                    pixels = Image.open(io.BytesIO(binary[start:start + view['byteLength']])).convert('RGB')
                    images[image_index] = linear(np.asarray(pixels, dtype=np.float64) / 255)
                pixels = images[image_index]
                uv = accessor(document, binary, primitive['attributes']['TEXCOORD_0'])
                uv = uv[indices.reshape(-1, 3)].mean(axis=1) % 1
                x = np.minimum((uv[:, 0] * pixels.shape[1]).astype(int), pixels.shape[1] - 1)
                y = np.minimum((uv[:, 1] * pixels.shape[0]).astype(int), pixels.shape[0] - 1)
                colour = pixels[y, x] * colour
            else:
                colour = np.repeat(colour[None], len(weights), axis=0)
            # Mixed generated images contain bolts and dark creases. Only the
            # warm fibre pixels belong to this timber colour comparison.
            selected = (colour[:, 0] > colour[:, 1] * 1.08) & (colour[:, 1] > colour[:, 2] * 1.04)
            selected &= np.min(colour, axis=1) < .82
            selected &= weights > 1e-8
            values = output.setdefault(role, {'colour': [], 'weight': []})
            values['colour'].append(colour[selected])
            values['weight'].append(weights[selected])
    return output


def measure(path):
    output = []
    for role, row in samples(path).items():
        colours, weights = np.concatenate(row['colour']), np.concatenate(row['weight'])
        average = np.average(colours, axis=0, weights=weights)
        luminance = colours @ np.array([.2126, .7152, .0722])
        mean = float(np.average(luminance, weights=weights))
        output.append({'role': role, 'samples': len(weights), 'area_m2': float(weights.sum()),
                       'linear_mean': average.round(6).tolist(), 'srgb_mean': srgb(average).round(6).tolist(),
                       'fibre_reference': round(mean, 6),
                       'fibre_spread': round(float(np.sqrt(np.average((luminance - mean) ** 2, weights=weights))), 6)})
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    assets = {asset: measure(ROOT / 'game/assets/models' / (asset + '.glb')) for asset in IDS}
    representative = {}
    for asset, rows in assets.items():
        representative[asset] = sum(row['fibre_reference'] * row['area_m2'] for row in rows) / sum(row['area_m2'] for row in rows)
    spread = max(representative.values()) - min(representative.values())
    report = {'measurement': 'area-weighted imported albedo in linear RGB; native lighting reviewed separately',
              'assets': assets, 'mean_luminance': representative, 'luminance_spread': spread,
              'unified_cedar_limit': .10, 'raw_sources_within_limit': spread <= .10}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'mean_luminance': representative, 'luminance_spread': spread,
                      'raw_sources_within_limit': spread <= .10}, indent=2))


if __name__ == '__main__':
    main()

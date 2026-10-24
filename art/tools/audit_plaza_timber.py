"""Measure the actual UV-mapped timber colours in the seven plaza furniture assets.

Uses embedded GLB images and surface-area-weighted triangle samples. This is an
albedo audit, not a substitute for the fixed-camera native-render comparison.
"""
import argparse
import ast
import hashlib
import io
import json
from pathlib import Path
import re
import struct

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
IDS = ('A12_bench', 'P01', 'P03', 'P05', 'P09', 'P10', 'MS14_event_board')
TYPES = {5121: 'u1', 5123: '<u2', 5125: '<u4', 5126: '<f4'}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
LUMA = np.array([.2126, .7152, .0722])
DARK_MEAN_LIMITS = (.06, .14)
DARK_SURFACE_LIMITS = (.045, .155)


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


def finish_settings(path):
    """Read the actual courtyard palette, not a second copy of its colours."""
    source = path.read_text()
    palette_line = re.search(r'const CEDAR: Array\[Color\] = \[([^\n]+)\]', source)
    palette = re.findall(r'Color\("([0-9a-fA-F]{6})"\)', palette_line.group(1))
    if len(palette) != 4:
        raise ValueError('Expected four authored cedar tones')
    reference = ast.literal_eval(re.search(r'const FIBRE_MEAN := (\{.*?\n\})', source, re.S).group(1))
    strength = re.search(r'set_shader_parameter\("authored_detail_strength", ([\d.]+) if id == "P03" else ([\d.]+)\)', source)
    return {'palette_srgb': palette,
            'palette': [linear(np.array([int(value[offset:offset + 2], 16) / 255 for offset in (0, 2, 4)])) for value in palette],
            'reference': reference, 'detail_p03': float(strength.group(1)),
            'detail_other': float(strength.group(2)),
            'source_sha256': hashlib.sha256(source.encode()).hexdigest()}


def finish_age(asset, role, part):
    if role.startswith('CedarAge_'):
        return min(3, max(0, int(role.removeprefix('CedarAge_'))))
    if asset == 'MS14_event_board':
        return 0 if 'wall_plaque' in role else 2
    if asset == 'A12_bench':
        return 2 if part.lower().endswith('frame') else 0
    return 1


def smoothstep(low, high, values):
    fraction = np.clip((values - low) / (high - low), 0, 1)
    return fraction * fraction * (3 - 2 * fraction)


def samples(path, finish=None):
    document, binary = load(path)
    images = {}
    output = {}
    parts = {node['mesh']: node.get('name', '') for node in document.get('nodes', []) if 'mesh' in node}
    for mesh_index, mesh in enumerate(document['meshes']):
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
            textured = 'baseColorTexture' in pbr
            if textured:
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
                fibre = pixels[y, x]
                colour = fibre * colour
            else:
                colour = np.repeat(colour[None], len(weights), axis=0)
            # Mixed generated images contain bolts and dark creases. Only the
            # warm fibre pixels belong to this timber colour comparison.
            selected = (colour[:, 0] > colour[:, 1] * 1.08) & (colour[:, 1] > colour[:, 2] * 1.04)
            selected &= np.min(colour, axis=1) < .82
            selected &= weights > 1e-8
            result = colour
            if finish:
                age = finish_age(path.stem, role, parts.get(mesh_index, mesh.get('name', '')))
                tone = finish['palette'][age]
                contrast = np.ones(len(weights))
                if textured:
                    reference = finish['reference'].get(path.stem, {}).get(role, .4)
                    strength = finish['detail_p03'] if path.stem == 'P03' else finish['detail_other']
                    contrast = np.clip(1 + (fibre @ LUMA - reference) * strength, .72, 1.15)
                coated = tone * contrast[:, None]
                if role.startswith('Hyper3D_') or path.stem == 'P03':
                    mask = smoothstep(1.08, 1.24, colour[:, 0] / np.maximum(colour[:, 1], .005))
                    mask *= smoothstep(1.04, 1.22, colour[:, 1] / np.maximum(colour[:, 2], .005))
                    mask *= 1 - smoothstep(.66, .82, np.min(colour, axis=1))
                    result = colour + (coated - colour) * mask[:, None]
                else:
                    result = coated
            values = output.setdefault(role, {'colour': [], 'weight': []})
            values['colour'].append(result[selected])
            values['weight'].append(weights[selected])
    return output


def measure(path, finish=None):
    output = []
    for role, row in samples(path, finish).items():
        colours, weights = np.concatenate(row['colour']), np.concatenate(row['weight'])
        average = np.average(colours, axis=0, weights=weights)
        luminance = colours @ LUMA
        mean = float(np.average(luminance, weights=weights))
        output.append({'role': role, 'samples': len(weights), 'area_m2': float(weights.sum()),
                       'linear_mean': average.round(6).tolist(), 'srgb_mean': srgb(average).round(6).tolist(),
                       'fibre_reference': round(mean, 6),
                       'fibre_spread': round(float(np.sqrt(np.average((luminance - mean) ** 2, weights=weights))), 6)})
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--finish-source', type=Path, default=ROOT / 'game/scripts/world/plaza_timber.gd',
                        help='Palette source; pass the previous source for a real negative control')
    parser.add_argument('--require-dark', action='store_true', help='Exit nonzero if the actual palette is still pale or too dark')
    args = parser.parse_args()
    assets = {asset: measure(ROOT / 'game/assets/models' / (asset + '.glb')) for asset in IDS}
    representative = {}
    for asset, rows in assets.items():
        representative[asset] = sum(row['fibre_reference'] * row['area_m2'] for row in rows) / sum(row['area_m2'] for row in rows)
    spread = max(representative.values()) - min(representative.values())
    report = {'measurement': 'area-weighted imported albedo in linear RGB; native lighting reviewed separately',
              'assets': assets, 'mean_luminance': representative, 'luminance_spread': spread,
              'unified_cedar_limit': .10, 'raw_sources_within_limit': spread <= .10}
    finish = finish_settings(args.finish_source)
    finished = {asset: measure(ROOT / 'game/assets/models' / (asset + '.glb'), finish) for asset in IDS}
    means = {asset: sum(row['fibre_reference'] * row['area_m2'] for row in rows) / sum(row['area_m2'] for row in rows)
             for asset, rows in finished.items()}
    failures = []
    for asset, mean in means.items():
        if not DARK_MEAN_LIMITS[0] <= mean <= DARK_MEAN_LIMITS[1]:
            failures.append({'asset': asset, 'mean': mean, 'reason': 'asset not in dark timber range'})
        for row in finished[asset]:
            if not DARK_SURFACE_LIMITS[0] <= row['fibre_reference'] <= DARK_SURFACE_LIMITS[1]:
                failures.append({'asset': asset, 'role': row['role'], 'mean': row['fibre_reference'], 'reason': 'wood surface not in dark timber range'})
    if max(means.values()) - min(means.values()) > .045:
        failures.append({'reason': 'dark timber asset spread exceeds .045'})
    report['finish'] = {'source': str(args.finish_source), 'source_sha256': finish['source_sha256'],
                        'palette_srgb': finish['palette_srgb'], 'assets': finished, 'mean_luminance': means,
                        'mean_limits': DARK_MEAN_LIMITS, 'surface_limits': DARK_SURFACE_LIMITS,
                        'measurement': 'UV-calibrated base tint before procedural grain on untextured parts, local wear, lighting and reflections; native game sampling is authoritative',
                        'passed': not failures, 'failures': failures}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'mean_luminance': representative, 'luminance_spread': spread,
                      'raw_sources_within_limit': spread <= .10,
                      'finish_mean_luminance': means, 'dark_finish_passed': not failures, 'failures': failures}, indent=2))
    if args.require_dark and failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()

"""Build a texture-only candidate on the existing animated character GLB.

The supplied diffuse must already use the character's original UV layout. This
tool does not infer UV correspondence or adopt a generator's rig or geometry.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import io
import json
import struct
from PIL import Image


def load_glb(path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from('<III', raw)
    assert magic == 0x46546C67 and version == 2 and length == len(raw)
    json_len, json_kind = struct.unpack_from('<II', raw, 12)
    assert json_kind == 0x4E4F534A
    data = json.loads(raw[20:20 + json_len])
    binary_len, binary_kind = struct.unpack_from('<II', raw, 20 + json_len)
    assert binary_kind == 0x004E4942
    return data, raw[28 + json_len:28 + json_len + binary_len]


def apply(source, image_path, target, report, max_size=None):
    assert source.resolve() != target.resolve(), 'Write a separate candidate.'
    data, original = load_glb(source)
    result = copy.deepcopy(data)
    image = Image.open(image_path).convert('RGB')
    input_size = image.size
    if max_size and max(image.size) > max_size:
        image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
    encoded = io.BytesIO()
    image.save(encoded, format='PNG')
    png = encoded.getvalue()
    binary = bytearray(original)
    binary.extend(b'\0' * (-len(binary) % 4))
    view_index = len(result['bufferViews'])
    result['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary),
                                 'byteLength': len(png)})
    binary.extend(png)
    image_index = len(result['images'])
    result['images'].append({'bufferView': view_index, 'mimeType': 'image/png',
                             'name': 'candidate_diffuse'})
    replaced = set()
    for material in result['materials']:
        texture = material.get('pbrMetallicRoughness', {}).get('baseColorTexture')
        if texture:
            result['textures'][texture['index']]['source'] = image_index
            replaced.add(texture['index'])
    assert replaced, 'No diffuse texture found.'
    result['buffers'][0]['byteLength'] = len(binary)
    payload = json.dumps(result, separators=(',', ':')).encode()
    payload += b' ' * (-len(payload) % 4)
    binary.extend(b'\0' * (-len(binary) % 4))
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(struct.pack('<III', 0x46546C67, 2, 28 + len(payload) + len(binary))
                       + struct.pack('<II', len(payload), 0x4E4F534A) + payload
                       + struct.pack('<II', len(binary), 0x004E4942) + binary)
    checked, saved_binary = load_glb(target)
    preserved = ['nodes', 'meshes', 'skins', 'animations', 'accessors', 'materials']
    assert all(checked.get(key) == data.get(key) for key in preserved)
    assert saved_binary[:len(original)] == original
    evidence = {'source': str(source), 'candidate': str(target),
                'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                'candidate_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                'input_texture_pixels': input_size, 'candidate_texture_pixels': image.size,
                'preserved_json_sections': preserved, 'original_binary_unchanged': True,
                'original_uv_required': True, 'diffuse_textures_replaced': sorted(replaced)}
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
    print(json.dumps(evidence, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--target', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--max-size', type=int)
    args = parser.parse_args()
    apply(args.source, args.image, args.target, args.report, args.max_size)

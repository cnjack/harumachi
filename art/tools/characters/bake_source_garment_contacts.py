"""Store hash-bound offline contact samples as ordinary source morph curves.

The existing Local POSITION/NORMAL fields are copied to separate authored
targets. Their new animation tracks play in any glTF viewer. Runtime-owned
Local targets remain zero; no controller or terrain correction is baked.
This stage does not certify collision, fit or naturalness: verify the output.
"""
from pathlib import Path
import argparse, copy, hashlib, json
import numpy as np
from glb_io import load
from repair_head_neck import read, append, save
from garment_bake_support import extend_original_curve

PREFIX = 'GarmentSourceContact_'


def bake(source, capture, output, report_path):
    doc, raw = load(source)
    original = copy.deepcopy(doc)
    blob = bytearray(raw)
    data = json.loads(Path(capture).read_text())
    digest = hashlib.sha256(Path(source).read_bytes()).hexdigest()
    if data['source_sha256'] != digest:
        raise ValueError('Offline capture and GLB identities differ')
    rig = next(n for n in doc['nodes'] if n.get('name') == 'Rig')
    if rig.get('extras', {}).get('source_garment_animation'):
        raise ValueError('Use the explicit prior source, not an already baked input')
    candidates = [(i, n) for i, n in enumerate(doc['nodes']) if 'mesh' in n and 'skin' in n
                  and not n.get('name', '').startswith(('Sleeve', 'HiddenArm'))]
    ni, node = max(candidates, key=lambda item: doc['accessors'][doc['meshes'][item[1]['mesh']]['primitives'][0]['attributes']['POSITION']]['count'])
    mesh = doc['meshes'][node['mesh']]
    names = mesh['extras']['targetNames']
    old_count = len(names)
    owned = [names.index(name) for name in data['local_names']]
    if len(owned) != 96 or len(set(owned)) != 96:
        raise ValueError('Expected all 96 existing source contact fields')
    if any(not names[i].startswith('Garment_Local_') for i in owned):
        raise ValueError('Capture contains an unknown runtime field')
    new_names = [PREFIX + name.removeprefix('Garment_Local_') for name in data['local_names']]
    for primitive in mesh['primitives']:
        if len(primitive['targets']) != old_count:
            raise ValueError('Morph inventories differ between primitives')
        primitive['targets'].extend(copy.deepcopy(primitive['targets'][i]) for i in owned)
    names.extend(new_names)
    mesh['weights'] = list(mesh.get('weights', [0.] * old_count)) + [0.] * len(owned)
    if 'weights' in node:
        node['weights'] += [0.] * len(owned)
    curves = []
    for animation, prior in zip(doc['animations'], original['animations']):
        channel = next(c for c in animation['channels'] if c['target'] == {'node': ni, 'path': 'weights'})
        sampler = animation['samplers'][channel['sampler']]
        if sampler.get('interpolation', 'LINEAR') != 'LINEAR':
            raise ValueError('Source morph curves require linear interpolation')
        times = read(original, raw, sampler['input']).ravel()
        values = read(original, raw, sampler['output']).reshape(-1, old_count)
        if np.any(values[:, owned]):
            raise ValueError('Source animation already competes with runtime Local fields')
        sampled = data['clips'].get(animation['name'])
        if sampled:
            knots = np.array([row['time'] for row in sampled['rows']], np.float32)
            fields = np.array([row['weights'] for row in sampled['rows']], np.float32)
            if not np.isfinite(fields).all() or fields.shape != (len(knots), 96) or fields.min() < 0 or fields.max() > 1:
                raise ValueError('Invalid bounded offline contact sample')
            if not np.array_equal(fields[0], fields[-1]):
                raise ValueError('Source contact loop endpoints differ')
            times, values, preservation = extend_original_curve(times, values, knots)
            additions = np.column_stack([np.interp(times, knots, fields[:, i]) for i in range(96)])
        else:
            additions = np.zeros((len(times), 96))
            preservation = {'old_key_values_exact': True, 'inserted_key_count': 0}
        combined = np.c_[values, additions].astype(np.float32)
        sampler['input'] = append(doc, blob, sampler['input'], times[:, None])
        sampler['output'] = append(doc, blob, sampler['output'], combined.reshape(-1, 1))
        curves.append({'clip': animation['name'], 'authored_contact': sampled is not None,
                       'keys': len(times), 'old_curves': preservation,
                       'maximum_authored_weight': float(additions.max(initial=0))})
    rig.setdefault('extras', {})['source_garment_animation'] = {
        'version': 1, 'source_sha256': digest,
        'capture_sha256': hashlib.sha256(Path(capture).read_bytes()).hexdigest(),
        'authored_clips': sorted(data['clips']), 'authored_shape_prefix': PREFIX,
        'runtime_owned_source_weights_zero': True, 'terrain_or_leg_correction_baked': False,
        'scope': 'Authored bounded cloth contact only; native source and game verification required'}
    save(doc, blob, Path(output))
    report = {'character': data['actor'], 'source_sha256': digest,
              'output_sha256': hashlib.sha256(Path(output).read_bytes()).hexdigest(),
              'old_targets_payloads_exact': True, 'new_targets_share_original_exact_fields': True,
              'geometry_skin_rest_uv_textures_unchanged': True, 'authored_targets': len(owned),
              'curves': curves}
    Path(report_path).write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ['source', 'capture', 'output', 'report']:
        parser.add_argument('--' + argument, type=Path, required=True)
    args = parser.parse_args()
    print(bake(args.source, args.capture, args.output, args.report))

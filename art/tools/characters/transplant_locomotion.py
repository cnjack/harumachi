"""Copy selected locomotion bone tracks onto a dressed GLB without losing morphs.

Recipient geometry, skins, targets, textures and other clips are retained. Existing
morph/helper tracks in the selected clip keep their values and normalized phases;
their time accessors are retimed to the donor duration. Skeleton rest must match.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import numpy as np
from glb_io import load
from repair_head_neck import read, append, save
from motion_math import world_matrices


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def transplant(source, donor, output, clips):
    d, raw = load(source)
    dd, db = load(donor)
    b = bytearray(raw)
    names = {n.get('name'): i for i, n in enumerate(d['nodes'])}
    dw, _ = world_matrices(dd, db)
    rw, _ = world_matrices(d, raw)
    for skin in dd['skins']:
        for joint in skin['joints']:
            name = dd['nodes'][joint]['name']
            if name not in names or not np.allclose(dw[joint], rw[names[name]], atol=1e-7):
                raise ValueError(f'Rest skeleton mismatch at {name}; rebase structure first')
    report = {'source': str(source), 'source_sha256': sha(source), 'donor': str(donor), 'donor_sha256': sha(donor), 'clips': []}
    for clip in clips:
        original = next(a for a in d['animations'] if a['name'] == clip)
        supplied = next(a for a in dd['animations'] if a['name'] == clip)
        duration = max(float(read(dd, db, s['input']).max()) for s in supplied['samplers'])
        old_duration = max(float(read(d, raw, s['input']).max()) for s in original['samplers'])
        tracks = {(dd['nodes'][c['target']['node']]['name'], c['target']['path']) for c in supplied['channels'] if c['target']['path'] != 'weights'}
        merged = copy.deepcopy(original)
        merged['channels'], merged['samplers'] = [], []
        retained = []
        for channel in original['channels']:
            target = channel['target']
            name = d['nodes'][target['node']]['name']
            if (name, target['path']) in tracks:
                continue
            sampler = copy.deepcopy(original['samplers'][channel['sampler']])
            times = read(d, raw, sampler['input']).astype(np.float32) * (duration / old_duration)
            sampler['input'] = append(d, b, sampler['input'], times)
            out = copy.deepcopy(channel)
            out['sampler'] = len(merged['samplers'])
            merged['samplers'].append(sampler)
            merged['channels'].append(out)
            retained.append({'node': name, 'path': target['path'], 'output_values_exact': True})
        for channel in supplied['channels']:
            if channel['target']['path'] == 'weights':
                continue
            sampler = copy.deepcopy(supplied['samplers'][channel['sampler']])
            for field in ['input', 'output']:
                donor_accessor = dd['accessors'][sampler[field]]
                template = next(i for i, a in enumerate(d['accessors']) if a['componentType'] == donor_accessor['componentType'] and a['type'] == donor_accessor['type'])
                sampler[field] = append(d, b, template, read(dd, db, sampler[field]))
            out = copy.deepcopy(channel)
            out['target']['node'] = names[dd['nodes'][channel['target']['node']]['name']]
            out['sampler'] = len(merged['samplers'])
            merged['samplers'].append(sampler)
            merged['channels'].append(out)
        original.clear()
        original.update(merged)
        report['clips'].append({'clip': clip, 'duration_before_s': old_duration, 'duration_after_s': duration, 'retained_recipient_tracks': retained, 'donor_bone_tracks': len(tracks)})
    rig = next(n for n in d['nodes'] if n.get('name') == 'Rig')
    donor_rig = next(n for n in dd['nodes'] if n.get('name') == 'Rig')
    rig.setdefault('extras', {})['locomotion_rebuild'] = copy.deepcopy(donor_rig['extras']['locomotion_rebuild'])
    for clip in clips:
        rig['extras'][clip + '_speed'] = donor_rig['extras'][clip + '_speed']
    save(d, b, output)
    report.update({'output': str(output), 'output_sha256': sha(output), 'geometry_skin_targets_uv_texture_payload_retained': True})
    return report


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input-dir', type=Path, required=True)
    p.add_argument('--donor-dir', type=Path, required=True)
    p.add_argument('--output-dir', type=Path, required=True)
    p.add_argument('--characters', nargs='+', required=True)
    p.add_argument('--clips', nargs='+', choices=['walk', 'run'], default=['walk'])
    args = p.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    if any((args.output_dir / f'CH_{who}.glb').exists() for who in args.characters):
        p.error('Use a fresh immutable output directory')
    rows = [transplant(args.input_dir / f'CH_{who}.glb', args.donor_dir / f'CH_{who}.glb', args.output_dir / f'CH_{who}.glb', args.clips) for who in args.characters]
    (args.output_dir / 'manifest.json').write_text(json.dumps({'stage': 'locomotion-track-transplant-retaining-recipient-morphs', 'tool_sha256': sha(Path(__file__)), 'characters': rows}, indent=2))
    print(args.output_dir / 'manifest.json')


if __name__ == '__main__':
    main()

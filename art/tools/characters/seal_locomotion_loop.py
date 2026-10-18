#!/usr/bin/env python3
"""Close only an accepted clip's seam, preserving its absolute authored key times.

The recipient supplies geometry, rest, garments, morph/helper tracks and all other
clips. The reference supplies accepted bone TRS motion outside a small circular
Hermite bridge. Neither global phase normalization nor periodic splines are used.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import numpy as np
from scipy.interpolate import CubicHermiteSpline
from scipy.spatial.transform import Rotation, Slerp
from glb_io import load
from repair_head_neck import read, append, save
from motion_math import world_matrices


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def interpolate(times, values, path, at):
    at = np.clip(np.asarray(at), times[0], times[-1])
    if path == 'rotation':
        return Slerp(times, Rotation.from_quat(values))(at).as_quat()
    return np.stack([np.interp(at, times, values[:, i]) for i in range(values.shape[1])], axis=-1)


def bridge_track(times, values, path, duration, before, after, step):
    start, end = duration - before, after
    h = min(.0001, step / 10)
    if path == 'rotation':
        for i in range(1, len(values)):
            if values[i] @ values[i - 1] < 0:
                values[i] *= -1
    first, last = values[0].copy(), values[-1].copy()
    if path == 'rotation' and first @ last < 0:
        last *= -1
    middle = (first + last) * .5
    if path == 'rotation':
        middle /= np.linalg.norm(middle)
    # The accepted clip holds its first key before that key's absolute time.
    # Blend only a local *correction* over that existing curve. Connecting the
    # entire cross-seam arc with a fresh spline would alter small source details.
    first_derivative = (interpolate(times, values, path, [h])[0] - interpolate(times, values, path, [0.])[0]) / h
    last_derivative = (interpolate(times, values, path, [duration])[0] - interpolate(times, values, path, [duration - h])[0]) / h
    seam_derivative = (first_derivative + last_derivative) * .5
    if path == 'rotation':
        seam_derivative -= middle * (middle @ seam_derivative)
    left = CubicHermiteSpline([start, duration], [np.zeros_like(first), middle - last], [np.zeros_like(first), seam_derivative - last_derivative])
    right = CubicHermiteSpline([0., end], [middle - first, np.zeros_like(first)], [seam_derivative - first_derivative, np.zeros_like(first)])
    # Original absolute keys stay in place. Only bridge samples and its exact
    # boundary keys are added; the source's untouched LINEAR/Slerp spans remain.
    dense = np.linspace(start, duration + end, int(np.ceil((before + after) / step)) + 1)
    out_times = np.unique(np.r_[times, 0., duration, start, end, dense[dense <= duration], dense[dense > duration] - duration].astype(np.float32)).astype(float)
    out_values = interpolate(times, values, path, out_times)
    left_mask, right_mask = out_times >= start - 1e-10, out_times <= end + 1e-10
    out_values[left_mask] += left(out_times[left_mask])
    out_values[right_mask] += right(out_times[right_mask])
    if path == 'rotation':
        out_values /= np.linalg.norm(out_values, axis=1)[:, None]
        for i in range(1, len(out_values)):
            if out_values[i] @ out_values[i - 1] < 0:
                out_values[i] *= -1
    # Same endpoint representation, not merely the same rotation.
    out_values[-1] = out_values[0]
    return out_times.astype(np.float32), out_values.astype(np.float32)


def seal(source, reference, output, clip='run', before=.08, after=.08, step=.0025):
    d, raw = load(source)
    ref, rb = load(reference)
    b = bytearray(raw)
    original_document = copy.deepcopy(d)
    target = next(a for a in d['animations'] if a['name'] == clip)
    accepted = next(a for a in ref['animations'] if a['name'] == clip)
    duration = max(float(read(ref, rb, s['input']).max()) for s in accepted['samplers'])
    if before <= 0 or after <= 0 or before + after >= duration * .5:
        raise ValueError('Use positive local windows covering less than half the clip')
    names = {n.get('name'): i for i, n in enumerate(d['nodes'])}
    current_worlds, _ = world_matrices(d, raw)
    accepted_worlds, _ = world_matrices(ref, rb)
    accepted_tracks = {}
    for channel in accepted['channels']:
        name = ref['nodes'][channel['target']['node']].get('name', '')
        path = channel['target']['path']
        if not name.startswith('mixamorig:') or path not in ['rotation', 'translation', 'scale']:
            continue
        if name not in names or not np.allclose(accepted_worlds[channel['target']['node']], current_worlds[names[name]], atol=1e-7):
            raise ValueError('Accepted reference rest differs: ' + name)
        accepted_tracks[(name, path)] = channel
    channels, samplers, retained, restored = [], [], [], []
    for channel in target['channels']:
        name = d['nodes'][channel['target']['node']].get('name', '')
        path = channel['target']['path']
        if (name, path) in accepted_tracks:
            continue
        out = copy.deepcopy(channel)
        out['sampler'] = len(samplers)
        samplers.append(copy.deepcopy(target['samplers'][channel['sampler']]))
        channels.append(out)
        retained.append({'node': name, 'path': path})
    for (name, path), channel in accepted_tracks.items():
        rs = accepted['samplers'][channel['sampler']]
        times = read(ref, rb, rs['input']).ravel().astype(float)
        values = read(ref, rb, rs['output']).astype(float)
        if rs.get('interpolation', 'LINEAR') == 'STEP':
            if np.max(abs(values - values[0])) > 1e-6:
                raise ValueError('Animated STEP track cannot be sealed as an almost constant exporter track')
            nt = np.unique(np.r_[0., times, duration].astype(np.float32))
            nv = np.broadcast_to(values[0], (len(nt), len(values[0]))).astype(np.float32).copy()
        elif rs.get('interpolation', 'LINEAR') == 'LINEAR':
            nt, nv = bridge_track(times, values, path, duration, before, after, step)
        else:
            raise ValueError('Only LINEAR/Slerp and almost constant STEP tracks are supported')
        templates = [next(i for i, a in enumerate(d['accessors']) if a['componentType'] == 5126 and a['type'] == kind) for kind in ['SCALAR', 'VEC4' if path == 'rotation' else 'VEC3']]
        samplers.append({'input': append(d, b, templates[0], nt), 'output': append(d, b, templates[1], nv), 'interpolation': 'LINEAR'})
        channels.append({'sampler': len(samplers) - 1, 'target': {'node': names[name], 'path': path}})
        restored.append({'node': name, 'path': path, 'original_absolute_keys_s': times.tolist()})
    target['channels'], target['samplers'] = channels, samplers
    if output.exists():
        raise ValueError('Use a new immutable output path')
    output.parent.mkdir(parents=True, exist_ok=True)
    save(d, b, output)
    nonclip = lambda doc: [a for a in doc['animations'] if a['name'] != clip]
    assert nonclip(d) == nonclip(original_document)
    assert d['meshes'] == original_document['meshes'] and d['skins'] == original_document['skins'] and d['nodes'] == original_document['nodes']
    assert bytes(b[:len(raw)]) == raw
    return {'stage': 'accepted-absolute-time-local-loop-seal', 'source': str(source), 'source_sha256': sha(source), 'accepted_reference': str(reference), 'accepted_reference_sha256': sha(reference), 'output': str(output), 'output_sha256': sha(output), 'tool_sha256': sha(__file__), 'clip': clip, 'duration_s': duration, 'bridge_intervals_s': [[0, after], [duration - before, duration]], 'original_curve_fraction_exact': 1 - (before + after) / duration, 'rest_geometry_skin_morph_payload_and_nonclip_json_exact': True, 'retained_recipient_clip_tracks_exact': retained, 'accepted_bone_tracks': restored}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--reference', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--report', type=Path, required=True)
    p.add_argument('--clip', default='run')
    p.add_argument('--before', type=float, default=.08)
    p.add_argument('--after', type=float, default=.08)
    args = p.parse_args()
    report = seal(args.input, args.reference, args.output, args.clip, args.before, args.after)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(args.report)


if __name__ == '__main__':
    main()

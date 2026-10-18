"""Build an isolated native A/B viewer and a shared, controlled leg-flexion clip."""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import math
import shutil

import numpy as np
from scipy.spatial.transform import Rotation

from glb_io import load, durations
from motion_math import world_matrices, sample_channel
from rebuild_locomotion import Pose, append_values
from repair_head_neck import read, save

ROOT = Path(__file__).resolve().parents[3]


def prepare_model(source, destination):
    doc, raw = load(source)
    blob = bytearray(raw)
    idle = next(a for a in doc['animations'] if a['name'] == 'idle')
    rest, parents = world_matrices(doc, blob)
    values = {(c['target']['node'], c['target']['path']): sample_channel(doc, blob, idle, c, 0.)
              for c in idle['channels'] if c['target']['path'] != 'weights'}
    ids = {n.get('name'): i for i, n in enumerate(doc['nodes'])}
    times = np.linspace(0., 6., 181)
    tracks = {ids['mixamorig:' + side + suffix]: [] for side in ['Left', 'Right'] for suffix in ['UpLeg', 'Leg']}
    for time in times:
        pose = Pose(doc, rest, parents, copy.deepcopy(values))
        for side, start in [('Left', 0.), ('Right', 3.)]:
            amount = math.sin(math.pi * (time - start) / 3.) ** 2 if start <= time <= start + 3. else 0.
            # One leg at a time: 90deg hip flexion / 120deg knee flexion.
            # This deliberately tests skinning beyond the normal walk envelope.
            for suffix, angle in [('UpLeg', -90. * amount), ('Leg', 120. * amount)]:
                node = ids['mixamorig:' + side + suffix]
                delta = Rotation.from_rotvec([math.radians(angle), 0., 0.]).as_matrix()
                pose.set_global(node, basis=delta @ pose.world(node)[:3, :3])
                tracks[node].append(pose.values[(node, 'rotation')])
    animation = {'name': 'binding_probe', 'channels': [], 'samplers': []}
    for channel in idle['channels']:
        target = channel['target']
        old = idle['samplers'][channel['sampler']]
        data = read(doc, blob, old['output'])
        count = len(read(doc, blob, old['input']))
        if target['path'] == 'rotation' and target['node'] in tracks:
            data = np.asarray(tracks[target['node']])
            for index in range(1, len(data)):
                if data[index] @ data[index - 1] < 0:
                    data[index] *= -1
            inputs = times
        else:
            if old.get('interpolation') == 'CUBICSPLINE':
                data = data.reshape(count, 3, -1)[0, 1].reshape(-1, data.shape[1])
            else:
                data = data[:len(data)//count]
            data = np.concatenate([data, data])
            inputs = np.array([0., 6.])
        sampler = {'input': append_values(doc, blob, inputs.reshape(-1, 1), 'SCALAR'),
                   'output': append_values(doc, blob, data, doc['accessors'][old['output']]['type']),
                   'interpolation': 'LINEAR'}
        animation['channels'].append({'target': target.copy(), 'sampler': len(animation['samplers'])})
        animation['samplers'].append(sampler)
    doc['animations'].append(animation)
    save(doc, blob, destination)


def main(args):
    project = args.project.resolve()
    if project.exists():
        raise ValueError('Use a new isolated preview folder')
    (project / 'assets').mkdir(parents=True)
    for name, source in [('before', args.before), ('after', args.after)]:
        prepare_model(source, project / 'assets' / (name + '.glb'))
    shutil.copyfile(Path(__file__).with_name('leg_foundation_preview.gd'), project/'preview.gd')
    shutil.copyfile(ROOT/'game/assets/fonts/LXGWWenKai-Medium.ttf', project/'font.ttf')
    (project/'project.godot').write_text('''config_version=5
[application]
config/name="Leg foundation A/B"
config/use_custom_user_dir=true
config/custom_user_dir_name="HarumachiLegFoundationPOC"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.8", "Forward Plus")
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/window_width_override=1920
window/size/window_height_override=1080
window/size/no_focus=true
window/stretch/mode="viewport"
[rendering]
renderer/rendering_method="forward_plus"
[debug]
file_logging/enable_file_logging=false
''')
    (project/'main.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://preview.gd" id="1"]\n[node name="Preview" type="Node"]\nscript=ExtResource("1")\n')
    lengths = durations(args.before)
    samples = []
    for clip, phases in [('idle', [0.]), ('walk', [0., .25, .5, .75]), ('run', [.25, .75])]:
        for phase in phases:
            for view in ['front', 'right']:
                samples.append({'id': f'{clip}-{int(phase*100):02}-{view}', 'clip': clip,
                                'time': phase * lengths[clip], 'view': view,
                                'label': f'{clip} · {phase:.0%} · {view} · 源动画独立播放'})
    for time, side in [(1.5, '左'), (4.5, '右')]:
        for view in ['front', 'right']:
            samples.append({'id': f'probe-{int(time*10)}-{view}', 'clip': 'binding_probe', 'time': time,
                            'view': view, 'label': f'{side}腿独立压力测试 · 抬髋90° / 屈膝120° · {view}'})
    settings = {'title': ('空' if args.character == 'sora' else '莲') + ' · 基础绑定与源动画对照',
                'output': str(args.output.resolve()), 'samples': samples,
                'sources': {name: {'path': str(source.resolve()), 'sha256': hashlib.sha256(source.read_bytes()).hexdigest()}
                            for name, source in [('before', args.before), ('after', args.after)]}}
    (project/'preview.json').write_text(json.dumps(settings, ensure_ascii=False, indent=2)+'\n')
    print(project)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['before', 'after', 'project', 'output']:
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--character', choices=['sora', 'ren'], required=True)
    main(parser.parse_args())

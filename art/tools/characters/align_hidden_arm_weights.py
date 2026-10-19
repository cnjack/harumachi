"""Match existing sleeve-fill skin to adjacent real arm skin; geometry stays exact.

This is a diagnostic candidate tool. Apply only after the same-pose HiddenArm
visibility A/B confirms a fill tube is the protruding surface.
"""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np
from scipy.spatial import cKDTree

from glb_io import load
from prepare_local_garments import read, colours
from repair_head_neck import append, save

ARM_BONES = ('mixamorig:{side}Arm', 'mixamorig:{side}ForeArm', 'TWIST_{side}')


def _body_arrays(document, binary):
    node = next(n for n in document['nodes'] if n.get('name') == 'CharacterBody')
    skin = document['skins'][node['skin']]
    primitive = document['meshes'][node['mesh']]['primitives'][0]
    positions = read(document, binary, primitive['attributes']['POSITION'])
    joints = read(document, binary, primitive['attributes']['JOINTS_0'])
    weights = read(document, binary, primitive['attributes']['WEIGHTS_0'])
    if 'JOINTS_1' in primitive['attributes']:
        joints = np.c_[joints, read(document, binary, primitive['attributes']['JOINTS_1'])]
        weights = np.c_[weights, read(document, binary, primitive['attributes']['WEIGHTS_1'])]
    bone_names = [document['nodes'][i].get('name', '') for i in skin['joints']]
    return skin['joints'], positions, colours(document, binary, primitive), joints, weights, bone_names


def _visible_arm_skin(rgb, joints, weights, bone_names, side):
    own = np.array([name in [t.format(side=side) for t in ARM_BONES] for name in bone_names])
    arm_share = np.sum(weights * own[joints], axis=1)
    skin_hue = (rgb[:, 0] > rgb[:, 1] * 1.07) & (rgb[:, 0] > rgb[:, 2] * 1.15)
    # Body RGB is used only to pick donor vertices; it does not alter the mesh.
    return np.flatnonzero(skin_hue & (arm_share > 0.75))


def _fit_node(document, binary, node, body_skin_joints, body):
    _, positions, rgb, joints, weights, bone_names = body
    side = node['name'].split('_')[-1]
    select = _visible_arm_skin(rgb, joints, weights, bone_names, side)
    tree = cKDTree(positions[select])
    target_skin = document['skins'][node['skin']]
    target_index = {joint: index for index, joint in enumerate(target_skin['joints'])}

    for primitive in document['meshes'][node['mesh']]['primitives']:
        attributes = primitive['attributes']
        tube_positions = read(document, binary, attributes['POSITION'])
        tube_joints = read(document, binary, attributes['JOINTS_0'])
        tube_weights = read(document, binary, attributes['WEIGHTS_0'])
        distances, nearest = tree.query(tube_positions, k=min(12, len(select)))
        dense = np.zeros((len(tube_positions), len(target_skin['joints'])))

        for vertex in range(len(tube_positions)):
            strength = np.exp(-((distances[vertex] - distances[vertex].min()) / 0.012) ** 2)
            strength /= strength.sum()
            for source, amount in zip(select[nearest[vertex]], strength):
                for joint, weight in zip(joints[source], weights[source]):
                    target = target_index.get(int(body_skin_joints[int(joint)]))
                    if target is not None:
                        dense[vertex, target] += float(weight * amount)

        old_dense = np.zeros_like(dense)
        for slot in range(tube_joints.shape[1]):
            np.add.at(old_dense, (np.arange(len(tube_positions)), tube_joints[:, slot]), tube_weights[:, slot])
        chosen = np.argsort(dense, axis=1)[:, -tube_joints.shape[1]:][:, ::-1]
        values = np.take_along_axis(dense, chosen, axis=1)
        values /= np.maximum(values.sum(1, keepdims=True), 1e-9)
        attributes['JOINTS_0'] = append(document, binary, attributes['JOINTS_0'], chosen.astype(tube_joints.dtype))
        attributes['WEIGHTS_0'] = append(document, binary, attributes['WEIGHTS_0'], values.astype(tube_weights.dtype))

        yield {
            'mesh': node['name'],
            'vertices': len(tube_positions),
            'source_visible_skin_vertices': len(select),
            'nearest_skin_distance_p95_m': float(np.percentile(distances[:, 0], 95)),
            'maximum_weight_change': float(np.abs(dense - old_dense).max()),
        }


def fit(args):
    document, binary = load(args.input)
    binary = bytearray(binary)
    body = _body_arrays(document, binary)
    body_skin_joints = body[0]
    report = {
        'input': str(args.input),
        'input_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
        'preserved': [
            'all positions', 'all normals', 'UVs', 'textures',
            'real CharacterBody weights', 'sleeve cloth weights',
            'skeleton', 'animations',
        ],
        'tubes': [],
    }

    for node in document['nodes']:
        if not node.get('name', '').startswith('HiddenArm_'):
            continue
        report['tubes'].extend(_fit_node(document, binary, node, body_skin_joints, body))

    save(document, binary, args.output)
    report['output'] = str(args.output)
    report['output_sha256'] = hashlib.sha256(args.output.read_bytes()).hexdigest()
    args.report.write_text(json.dumps(report, indent=2))
    print(args.report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    fit(parser.parse_args())


if __name__ == '__main__':
    main()

"""Repair duplicate physical cloth vertices in existing action correctives.

Only POSITION/NORMAL payloads of SleeveFit_<clip>_* targets change. All base
attributes, skins, skeletons, UVs, images, other targets and animation streams
remain untouched. A native source manifest supplies the exact peak bone poses.
This preflight does not replace candidate native visual acceptance.
"""
from pathlib import Path
import argparse, hashlib, heapq, json
import numpy as np
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix, diags
from scipy.sparse.csgraph import connected_components
from glb_io import load
from prepare_local_garments import read
from prepare_sleeve_weights import cloth_mask
from sew_arm_seams import dense_part
from repair_head_neck import append, save
from corrective_normals import unit, geometry_normals, rotate_between
from motion_math import world_matrices


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def posed_part(d, b, part, row, shapes=None):
    rest_world, _ = world_matrices(d, b)
    ids = {n.get('name'): i for i, n in enumerate(d['nodes'])}
    for bone in row['bones']:
        at = ids.get(bone['name'].replace('mixamorig_', 'mixamorig:'))
        if at is None:
            continue
        rest_world[at] = np.eye(4)
        rest_world[at][:3, :3] = np.asarray(bone['basis']).T
        rest_world[at][:3, 3] = np.asarray(bone['position']) - row['position']
    skin = d['skins'][part['node']['skin']]
    binds = read(d, b, skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    matrices = np.asarray([rest_world[j] @ ib for j, ib in zip(skin['joints'], binds)])
    B = np.zeros((len(part['pos']), 3, 3))
    T = np.zeros_like(part['pos'], dtype=float)
    for slot in range(part['j'].shape[1]):
        B += matrices[part['j'][:, slot], :3, :3] * part['w'][:, slot, None, None]
        T += matrices[part['j'][:, slot], :3, 3] * part['w'][:, slot, None]
    position = part['pos'].copy()
    normal = unit(read(d, b, part['a']['NORMAL'])).copy()
    source_shapes = part['shapes'] if shapes is None else shapes
    for index, name in enumerate(part['names']):
        value = row['blend_shape_values'][part['node']['name']][name]
        if not value:
            continue
        position += value * source_shapes[name]
        target = part['p']['targets'][index]
        if 'NORMAL' in target:
            normal += value * (unit(unit(read(d, b, part['a']['NORMAL'])) + read(d, b, target['NORMAL'])) - unit(read(d, b, part['a']['NORMAL'])))
    return np.einsum('nij,nj->ni', B, position) + T, B, normal


def garment_vertices(part, character):
    allowed = cloth_mask(character, part['rgb'])
    # Separate Sleeve meshes contain only the extracted garment, including its
    # warm shaded cloth texels. Bare neck/arm/hand skin remains in CharacterBody.
    if part['node'].get('name') == 'CharacterBody':
        r, g, blue = part['rgb'].T
        allowed &= ~((r > g * 1.10) & (g > blue * 1.02) & (r > .30))
    return allowed


def physical_groups(parts, character, position_epsilon=1e-6, skin_epsilon=1e-3):
    order = list(parts)
    offsets = np.cumsum([0] + [len(parts[name]['pos']) for name in order])
    positions = np.concatenate([parts[name]['pos'] for name in order])
    weights = np.concatenate([parts[name]['dense'] for name in order])
    height = float(positions[:, 1].max())
    allowed = np.concatenate([garment_vertices(parts[name], character) for name in order])
    allowed &= (positions[:, 1] > .52 * height) & (abs(positions[:, 0]) > .04 * height)
    pairs = cKDTree(positions).query_pairs(position_epsilon, output_type='ndarray')
    compatible = allowed[pairs].all(1) & (np.max(abs(weights[pairs[:, 0]] - weights[pairs[:, 1]]), axis=1) <= skin_epsilon)
    pairs = pairs[compatible]
    graph = coo_matrix((np.ones(2 * len(pairs)), (np.r_[pairs[:, 0], pairs[:, 1]], np.r_[pairs[:, 1], pairs[:, 0]])), shape=(len(positions), len(positions))).tocsr()
    count, labels = connected_components(graph, directed=False)
    sizes = np.bincount(labels, minlength=count)
    groups = [np.flatnonzero(labels == label) for label in np.flatnonzero(sizes > 1)]
    return order, offsets, groups, pairs


def topology_field(part, anchors, allowed, radius):
    adjacency = [[] for _ in part['pos']]
    for a, c in part['edges']:
        if not allowed[a] or not allowed[c]: continue
        length = float(np.linalg.norm(part['pos'][a] - part['pos'][c]))
        adjacency[a].append((int(c), length)); adjacency[c].append((int(a), length))
    distance = np.full(len(adjacency), np.inf); owner = np.full(len(adjacency), -1, int)
    queue = []
    for a in anchors:
        distance[a] = 0; owner[a] = a; queue.append((0., int(a), int(a)))
    heapq.heapify(queue)
    while queue:
        dist, at, source = heapq.heappop(queue)
        if dist != distance[at]: continue
        for to, length in adjacency[at]:
            candidate = dist + length
            if candidate < distance[to] and candidate < radius:
                distance[to] = candidate; owner[to] = source
                heapq.heappush(queue, (candidate, to, source))
    t = np.clip(distance / radius, 0, 1)
    return owner, 1 - t * t * (3 - 2 * t)


def prepare(args):
    d, binary = load(args.input)
    b = bytearray(binary)
    source_hash = digest(args.input)
    provenance = args.manifest.parent.parent / 'model-hashes.json'
    if json.loads(provenance.read_text())[f'CH_{args.character}.glb'] != source_hash:
        raise ValueError('Native source model SHA does not match input')
    nodes = {n.get('name'): n for n in d['nodes']}
    parts = {name: dense_part(d, b, nodes[name]) for name in ['CharacterBody', 'Sleeve_Left', 'Sleeve_Right']}
    order, offsets, groups, pairs = physical_groups(parts, args.character)
    # Collapse physical copies before smoothing the corrective field. Averaging
    # just the seam copies creates a new abrupt field jump one edge away.
    total = int(offsets[-1])
    labels = np.arange(total)
    for group in groups: labels[group] = group[0]
    _, physical = np.unique(labels, return_inverse=True)
    size = int(physical.max()) + 1
    count = np.bincount(physical, minlength=size)
    edges = np.concatenate([part['edges'] + offsets[i] for i, part in enumerate(parts.values())])
    positions = np.concatenate([part['pos'] for part in parts.values()])
    H = float(positions[:, 1].max())
    allowed = np.concatenate([garment_vertices(part, args.character) for part in parts.values()])
    allowed &= (positions[:, 1] > .52 * H) & (abs(positions[:, 0]) > .04 * H)
    edges = edges[allowed[edges].all(1)]
    edges = np.unique(np.sort(physical[edges], axis=1), axis=0)
    edges = edges[edges[:, 0] != edges[:, 1]]
    graph = coo_matrix((np.ones(2 * len(edges)), (np.r_[edges[:, 0], edges[:, 1]], np.r_[edges[:, 1], edges[:, 0]])), shape=(size, size)).tocsr()
    degree = np.asarray(graph.sum(1)).ravel()
    mean = diags(1 / np.maximum(degree, 1)) @ graph
    prefix = f'SleeveFit_{args.clip}_'
    target_names = [name for name in parts['CharacterBody']['names'] if name.startswith(prefix)]
    if not target_names or any(name not in part['names'] for part in parts.values() for name in target_names):
        raise ValueError('Expected synchronized existing corrective names on all garment parts')
    # A shared target is safe to edit only if no protected action uses its column.
    for animation in d['animations']:
        if animation['name'] == args.clip:
            continue
        for name, part in parts.items():
            ni = d['nodes'].index(part['node'])
            for channel in animation['channels']:
                if channel['target'] != {'node': ni, 'path': 'weights'}:
                    continue
                values = read(d, b, animation['samplers'][channel['sampler']]['output']).reshape(-1, len(part['names']))
                if np.any(values[:, [part['names'].index(n) for n in target_names]] != 0):
                    raise ValueError('A protected action uses the corrective being repaired')
    raw_rows = json.loads(args.manifest.read_text())['shots']
    rows = [row for row in raw_rows if row['id'] == args.character and row['clip'] == args.clip]
    report = {'input': str(args.input), 'input_sha256': source_hash, 'manifest': str(args.manifest), 'manifest_sha256': digest(args.manifest), 'method': 'one rest-space corrective displacement per coincident cloth/compatible-skin physical vertex; per-part average before cross-part averaging', 'position_epsilon_m': 1e-6, 'skin_max_component_epsilon': 1e-3, 'feather_m': args.feather, 'smoothing_iterations': args.smoothing_iterations, 'physical_groups': len(groups), 'compatible_pairs': len(pairs), 'targets': [], 'preserved': ['base attributes', 'skin weights and binds', 'skeleton', 'UVs and images', 'all animations', 'all other target payloads', 'all non-stretch evaluated geometry']}
    for target_name in target_names:
        phase = int(target_name.rsplit('_', 1)[1]) / 1000
        row = next(row for row in rows if abs(row['phase'] - phase) < 1e-6)
        fields = np.concatenate([parts[name]['shapes'][target_name] for name in order])
        fixed = fields.copy()
        for group in groups:
            means = [fields[group[(group >= offsets[i]) & (group < offsets[i + 1])]].mean(0) for i in range(len(order)) if np.any((group >= offsets[i]) & (group < offsets[i + 1]))]
            fixed[group] = np.mean(means, axis=0)
        shared = fixed.copy()
        for part_index, name in enumerate(order):
            part = parts[name]
            lo, hi = offsets[part_index:part_index + 2]
            anchors = np.unique(np.concatenate([group[(group >= lo) & (group < hi)] - lo for group in groups]))
            if args.feather <= 0: continue
            owner, envelope = topology_field(part, anchors, allowed[lo:hi], args.feather)
            active = np.flatnonzero(envelope > 0)
            fixed[lo + active] = fields[lo + active] + (shared[lo + owner[active]] - fields[lo + owner[active]]) * envelope[active, None]
        physical_field = np.zeros((size, 3))
        np.add.at(physical_field, physical, fixed)
        physical_field /= count[:, None]
        smoothing_active = degree > 0
        for _ in range(args.smoothing_iterations):
            averaged = mean @ physical_field
            physical_field[smoothing_active] = .5 * physical_field[smoothing_active] + .5 * averaged[smoothing_active]
        fixed[allowed] = physical_field[physical[allowed]]
        target_report = {'target': target_name, 'phase': phase, 'smoothing_iterations': args.smoothing_iterations, 'parts': []}
        for part_index, name in enumerate(order):
            part = parts[name]
            old = part['shapes'][target_name]
            new = fixed[offsets[part_index]:offsets[part_index + 1]]
            before, B, rest_normal = posed_part(d, b, part, row)
            delta = np.einsum('nij,nj->ni', B, new - old)
            after = before + delta
            moved = np.linalg.norm(delta, axis=1) > 1e-9
            faces = read(d, b, part['p']['indices']).reshape(-1, 3)
            affected_faces = np.any(moved[faces], axis=1)
            affected = np.zeros(len(old), bool)
            affected[np.unique(faces[affected_faces])] = True
            # Rotate the existing authored normal offset with the repaired
            # geometric direction; preserve UV and hard-edge normal copies.
            base_normal = unit(read(d, b, part['a']['NORMAL']))
            old_geo = geometry_normals(before, faces)
            new_geo = geometry_normals(after, faces)
            old_render = unit(np.einsum('nij,nj->ni', B, unit(rest_normal)))
            desired_world = unit(rotate_between(old_geo, new_geo, old_render))
            desired_rest = unit(np.einsum('nij,nj->ni', np.linalg.pinv(B), desired_world))
            ti = part['names'].index(target_name)
            old_normal_delta = unit(base_normal + read(d, b, part['p']['targets'][ti]['NORMAL'])) - base_normal
            rest_without = rest_normal - old_normal_delta
            offset = base_normal - rest_without
            along = np.sum(offset * desired_rest, axis=1)
            discriminant = along * along + 1 - np.sum(offset * offset, axis=1)
            if np.any(discriminant[affected] < -1e-8):
                raise ValueError('Unit target normal is unreachable')
            scale = -along + np.sqrt(np.maximum(discriminant, 0))
            normal_delta = unit(offset + scale[:, None] * desired_rest) - base_normal
            normal_delta[~affected] = read(d, b, part['p']['targets'][ti]['NORMAL'])[~affected]
            part['p']['targets'][ti]['POSITION'] = append(d, b, part['a']['POSITION'], new.astype(np.float32))
            part['p']['targets'][ti]['NORMAL'] = append(d, b, part['a']['NORMAL'], normal_delta.astype(np.float32))
            target_report['parts'].append({'mesh': name, 'moved_vertices': int(moved.sum()), 'maximum_world_repair_m': float(np.linalg.norm(delta, axis=1).max())})
        report['targets'].append(target_report)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    save(d, b, args.output)
    report['output'] = str(args.output)
    report['output_sha256'] = digest(args.output)
    report['tool_sha256'] = digest(__file__)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(args.report)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--manifest', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--report', type=Path, required=True)
    p.add_argument('--character', default='mio')
    p.add_argument('--clip', default='stretch')
    p.add_argument('--smoothing-iterations', type=int, default=0)
    p.add_argument('--feather', type=float, default=.04)
    prepare(p.parse_args())

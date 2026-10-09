"""Blender regression: short mesh edges must not become long needles in any clip.

Blender -b --factory-startup --python-exit-code 1 -P art/tools/characters/audit_pose_tears.py -- OUT_JSON GLB... [--require-pass]
Checks all eleven game clips at nine phases. Does not judge facial proportions or motion taste.
"""
import json
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix

args = sys.argv[sys.argv.index('--') + 1:]
out = Path(args[0])
require_pass = '--require-pass' in args
paths = [Path(p) for p in args[1:] if p != '--require-pass']
clips = ['idle', 'walk', 'run', 'wave', 'dance', 'stretch', 'bow', 'look', 'tend', 'talk', 'cheer']
reports = []
for source in paths:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
    rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    for obj in bpy.context.scene.objects:
        if obj.animation_data:
            obj.animation_data.action = None
            for track in obj.animation_data.nla_tracks:
                track.mute = True
        if obj.type == 'MESH' and obj.data.shape_keys:
            keys = obj.data.shape_keys
            for key in keys.key_blocks:
                key.value = 0
            if keys.animation_data:
                keys.animation_data.action = None
                for track in keys.animation_data.nla_tracks:
                    track.mute = True
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' for m in o.modifiers)]
    rest_data = []
    for mesh in meshes:
        edges = np.array([tuple(e.vertices) for e in mesh.data.edges])
        if not len(edges):
            continue
        world = np.array(mesh.matrix_world)
        points = np.array([tuple(v.co) for v in mesh.data.vertices]) @ world[:3, :3].T + world[:3, 3]
        lengths = np.linalg.norm(points[edges[:, 0]] - points[edges[:, 1]], axis=1)
        rest_data.append((mesh, edges, lengths, world))
    tracks = {t.name.split('|')[-1]: t for t in rig.animation_data.nla_tracks}
    assert all(c in tracks for c in clips), f'Missing clips: {source}'
    samples = []
    for clip in clips:
        action = tracks[clip].strips[0].action
        rig.animation_data.action = action
        for mesh, _, _, _ in rest_data:
            keys = mesh.data.shape_keys
            if keys and keys.animation_data:
                shape_track = next((t for t in keys.animation_data.nla_tracks if t.name.split('|')[-1] == clip), None)
                keys.animation_data.action = shape_track.strips[0].action if shape_track else None
        start, end = action.frame_range
        for phase in np.linspace(0, 1, 9):
            frame = start + (end - start) * phase
            bpy.context.scene.frame_set(int(frame), subframe=float(frame % 1))
            bpy.context.view_layer.update()
            needles = 0
            largest = 0.0
            failures = []
            for mesh, edges, lengths, world in rest_data:
                evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
                data = evaluated.to_mesh()
                points = np.array([tuple(v.co) for v in data.vertices]) @ world[:3, :3].T + world[:3, 3]
                evaluated.to_mesh_clear()
                posed_lengths = np.linalg.norm(points[edges[:, 0]] - points[edges[:, 1]], axis=1)
                short = lengths < .012
                bad = short & (posed_lengths > .07) & (posed_lengths > lengths * 8)
                needles += int(bad.sum())
                for index in np.flatnonzero(bad)[np.argsort(posed_lengths[bad])[-3:]]:
                    failures.append({'mesh': mesh.name, 'rest_length_m': float(lengths[index]), 'posed_length_m': float(posed_lengths[index]), 'vertices': [{'local': list(mesh.data.vertices[vi].co), 'weights': {mesh.vertex_groups[g.group].name: g.weight for g in mesh.data.vertices[vi].groups}} for vi in edges[index]]})
                if short.any():
                    largest = max(largest, float(posed_lengths[short].max()))
            samples.append({'clip': clip, 'phase': float(phase), 'needle_edges': needles, 'largest_short_edge_m': largest, 'failures': failures})
    row = {'source': str(source), 'passed': not any(s['needle_edges'] for s in samples), 'max_needle_edges': max(s['needle_edges'] for s in samples), 'samples': samples}
    reports.append(row)
    print(json.dumps({k: v for k, v in row.items() if k != 'samples'}), flush=True)
result = {'passed': all(r['passed'] for r in reports), 'criteria': {'original_edge_max_m': .012, 'posed_edge_min_m': .07, 'stretch_ratio_min': 8, 'phases': 9}, 'characters': reports}
out.write_text(json.dumps(result, indent=2) + '\n')
if require_pass:
    assert result['passed'], 'Animation tore short mesh edges; see report'

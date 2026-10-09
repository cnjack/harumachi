"""Report how far each exported model leans off its base.

  $BLENDER -b --factory-startup -P art/tools/level_check.py -- [--rest-pose] [out.json] [glb ...]

With no GLBs given it checks every game/assets/models/*.glb and writes
game/assets/models/_stats/_level.json, which the PROPS tests read (so rerun it after every
export). For each model it prints the angle between its standing face (see
level_util.support_plane) and the ground, and how much of its footprint that face covers.
"""
import glob
import json
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from level_util import support_plane, squareness  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
rest_pose = "--rest-pose" in argv
argv = [argument for argument in argv if argument != "--rest-pose"]
root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../game/assets/models"))
out_path = argv[0] if argv else os.path.join(root, "_stats", "_level.json")
files = argv[1:] or sorted(glob.glob(os.path.join(root, "*.glb")))

report = {}
for path in files:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    try:
        bpy.ops.import_scene.gltf(filepath=path)
    except Exception as e:
        print("SKIP", path, e)
        continue
    if rest_pose or any(actor.type == 'ARMATURE' for actor in bpy.context.scene.objects):
        # Imported GLB animation tracks otherwise stack in Blender. Measure the
        # authored standing surface, not a mixture of Walk/Sit/Jump tracks.
        for actor in bpy.context.scene.objects:
            if actor.type == 'MESH' and actor.data.shape_keys:
                keys = actor.data.shape_keys
                keys.animation_data_clear()
                for shape in keys.key_blocks:
                    shape.value = 0
            if actor.type != 'ARMATURE':
                continue
            actor.animation_data_clear()
            for pose_bone in actor.pose.bones:
                pose_bone.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
    pts = []
    dg = bpy.context.evaluated_depsgraph_get()
    bone_shapes = {bone.custom_shape for actor in bpy.context.scene.objects
                   if actor.type == 'ARMATURE' for bone in actor.pose.bones
                   if bone.custom_shape is not None}
    for o in bpy.context.scene.objects:
        if o.type != 'MESH' or o in bone_shapes:
            continue
        me = o.evaluated_get(dg).to_mesh()
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        m = np.array(o.matrix_world)
        pts.append(co @ m[:3, :3].T + m[:3, 3])
    if not pts:
        continue
    pts = np.concatenate(pts)
    n, tilt, area, foot = support_plane(pts)
    sq, rect = squareness(pts)
    aid = os.path.splitext(os.path.basename(path))[0]
    report[aid] = {"tilt": round(tilt, 2), "normal": [round(float(x), 4) for x in n],
                   "base_frac": round(area / foot, 3) if foot else 0, "verts": int(len(pts)),
                   "square_deg": round(sq, 2), "rect_fill": round(rect, 3)}
    print("LEVEL %-24s %6.2f deg  base %.2f  turned %5.1f deg (rect %.2f)" % (aid, tilt, report[aid]["base_frac"], sq, rect))

json.dump(report, open(out_path, "w"), indent=1, sort_keys=True)
print("WROTE", out_path, len(report))

"""Measure the actual shipping cats after GLB reimport, across every action.

Run with Blender, not system Python:
  blender -b --factory-startup --python-exit-code 1 -P art/tools/audit_cat_surface.py -- --out <json>
The measurements concern the clip's deformed mesh. World foot locking and
attention are checked separately by animal_visual_audit.gd's live mode.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
DURATIONS = {
    "Idle": 8, "Walk": 10, "Run": 4, "Sneak": 8.4, "Sit": 8,
    "SitDown": .9, "StandUp": .9, "Jump": 1.2, "Stretch": 4,
}
FLOOR = -.008


def audit(who: str, samples: int) -> dict:
    source = ROOT / "game/assets/models" / f"AN_cat_{who}_walk.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=str(source))
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    mesh = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    rests = {bone.name: bone.matrix_local.copy() for bone in rig.data.bones}
    names = list(rests)
    vertices = np.asarray([tuple(vertex.co) for vertex in mesh.data.vertices])
    weights = np.zeros((len(vertices), len(names)))
    for vertex in mesh.data.vertices:
        for group in vertex.groups:
            name = mesh.vertex_groups[group.group].name
            if name in rests:
                weights[vertex.index, names.index(name)] = group.weight
    actions = {}
    for track in rig.animation_data.nla_tracks:
        actions[track.name] = track.strips[0].action
        track.mute = True
    limbs = [("Back", "L", 0), ("Front", "L", .25), ("Back", "R", .5), ("Front", "R", .75)]
    foot_masks = []
    for kind, side, _ in limbs:
        columns = [index for index, name in enumerate(names)
                   if name.startswith(kind + "_Leg_") and name.endswith("_" + side)
                   and ("Foot" in name or "Ankle" in name)]
        foot_masks.append((weights[:, columns].sum(1) > .5) & (vertices[:, 2] < .050))
    edges = np.asarray([tuple(edge.vertices) for edge in mesh.data.edges])
    rest_lengths = np.linalg.norm(vertices[edges[:, 0]] - vertices[edges[:, 1]], axis=1)
    # Sub-2 mm edges amplify tiny seam rounding, obscuring visible surface folds.
    valid_edges = rest_lengths > .002
    clips = []
    for clip, duration in DURATIONS.items():
        if clip not in actions:
            clips.append({"clip": clip, "passed": False, "error": "missing action"})
            continue
        action = actions[clip]
        rig.animation_data.action = action
        first, last = action.frame_range
        rows = []
        maximum_stretch = 0.0
        for seconds in np.linspace(0, duration, samples):
            frame = first + (last - first) * seconds / duration
            bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
            evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
            surface = np.asarray([tuple(vertex.co) for vertex in evaluated.data.vertices])
            feet = []
            for limb_index, (_, _, phase) in enumerate(limbs):
                moving = clip in ["Walk", "Run", "Sneak"]
                period = {"Walk": 10 / 12, "Run": .5, "Sneak": 1.2}.get(clip, 1)
                duty = {"Walk": float(rig.get("gait_duty_factor", .76)), "Run": .62, "Sneak": .84}.get(clip, 1)
                speed = {"Walk": .12, "Run": .42, "Sneak": .07}.get(clip, 0)
                if clip == "Walk":
                    phase = float(rig.get("gait_walk_phases", [0, .25, .5, .75])[limb_index])
                elif clip == "Run":
                    phase = 0 if limb_index in [0, 3] else .5
                phase = (seconds / period - phase) % 1
                contact = not moving or phase < duty
                # A linear imported key interval straddling takeoff/landing is
                # airborne too; do not label its interpolated 2 mm lift as planted.
                boundary_margin = (1 / 60) / duration
                if clip == "Jump" and .18 - boundary_margin < seconds / duration < .84 + boundary_margin:
                    contact = False
                cloud = surface[foot_masks[limb_index]]
                minimum = float(cloud[:, 2].min())
                center = cloud[cloud[:, 2] < minimum + .005].mean(0)
                center[1] -= speed * seconds
                feet.append({"contact": bool(contact), "phase": float(phase), "min_z": minimum, "center": center.tolist()})
            ratios = np.linalg.norm(surface[edges[:, 0]] - surface[edges[:, 1]], axis=1)[valid_edges] / rest_lengths[valid_edges]
            maximum_stretch = max(maximum_stretch, float(ratios.max()))
            rows.append({"seconds": float(seconds), "feet": feet, "min_z": float(surface[:, 2].min()),
                         "max_z": float(surface[:, 2].max())})
        grounded = [foot for row in rows for foot in row["feet"] if foot["contact"]]
        contact_error = max(abs(foot["min_z"] - FLOOR) for foot in grounded)
        slip_runs = []
        if clip in ["Walk", "Run", "Sneak"]:
            duty = {"Walk": float(rig.get("gait_duty_factor", .76)), "Run": .62, "Sneak": .84}[clip]
            for limb_index in range(4):
                run = []
                for row in rows:
                    foot = row["feet"][limb_index]
                    if foot["contact"] and .04 < foot["phase"] < duty - .04:
                        run.append(foot["center"])
                    else:
                        if run:
                            slip_runs.append(float(np.linalg.norm(np.ptp(np.asarray(run)[:, :2], axis=0))))
                        run = []
        slip = max(slip_runs, default=0)
        # Keep the established centimetre-scale support tolerances and bound visible stretching.
        # The visual review remains necessary, especially around folded thighs in Sit.
        stretch_gate = 8.0 if clip in ["Sit", "SitDown", "StandUp"] else 5.0
        passed = contact_error < .002 and slip < .008 and maximum_stretch < stretch_gate
        clips.append({"clip": clip, "passed": passed, "contact_error_m": contact_error,
                      "stance_slip_m": slip, "max_surface_stretch": maximum_stretch,
                      "stretch_gate": stretch_gate, "samples": rows})
        print("CAT_SURFACE", who, clip, passed, contact_error, slip, maximum_stretch, flush=True)
    _, inverse, counts = np.unique(np.round(vertices / 1e-6).astype(np.int64), axis=0, return_inverse=True, return_counts=True)
    sums = np.zeros((len(counts), len(names)))
    np.add.at(sums, inverse, weights)
    seam_error = float(np.abs(weights - (sums / counts[:, None])[inverse]).max())
    weight_error = float(np.abs(weights.sum(1) - 1).max())
    max_influences = int((weights > 1e-6).sum(1).max())
    passed = len(names) == 59 and max_influences <= 8 and weight_error < .00001 and seam_error < .00001 and all(row["passed"] for row in clips)
    return {"cat": who, "passed": passed, "source": str(source.relative_to(ROOT)),
            "sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "joints": len(names),
            "max_influences": max_influences, "weight_sum_error": weight_error,
            "seam_error": seam_error, "clips": clips}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=121)
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    result = {"assets": [audit(who, arguments.samples) for who in ["orange", "calico"]]}
    result["passed"] = all(row["passed"] for row in result["assets"])
    result["samples_per_clip"] = arguments.samples
    result["scope"] = "reimported shipping geometry, nine clips, full-cycle support and deformation; world IK/attention checked separately"
    arguments.out.parent.mkdir(parents=True, exist_ok=True)
    arguments.out.write_text(json.dumps(result, indent=2))
    if not result["passed"]:
        raise RuntimeError("Cat surface audit failed; inspect metrics and native screenshots")


if __name__ == "__main__":
    main()

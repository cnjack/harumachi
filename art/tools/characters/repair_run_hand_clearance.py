#!/usr/bin/env python3
"""Keep Tanaka's returning running hands clear of his torso jacket.

Only the two run ForeArm rotation outputs change. A smooth periodic, opposite-side
return-stroke offset yaws the forearm outward without changing either upper-arm
trajectory or elbow location. Arm/Hand/finger local channels, all other clips, mesh/UV/skin/rest/morphs,
input times and existing binary bytes remain exact. This produces an authored
candidate; native final-pose/visual acceptance is a separate required step.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation

from glb_io import load
from motion_math import world_matrices
from repair_head_neck import append, read, save


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def repair(source, output, left_yaw_deg=24.5, right_yaw_deg=14.):
    if output.exists():
        raise ValueError("Use a fresh immutable candidate path")
    d, raw = load(source)
    original = copy.deepcopy(d)
    ids = {node.get("name"): index for index, node in enumerate(d["nodes"])}
    if d["nodes"][ids["Rig"]].get("extras", {}).get("character_id") != "tanaka":
        raise ValueError("This measured source fix is qualified for Tanaka only")
    if not 0 <= left_yaw_deg <= 30 or not 0 <= right_yaw_deg <= 30:
        raise ValueError("Requested correction exceeds the small authored-pose search domain")
    action = next(action for action in d["animations"] if action["name"] == "run")
    duration = max(float(read(d, raw, sampler["input"]).max()) for sampler in action["samplers"])
    _, parents = world_matrices(d, raw)
    expected = copy.deepcopy(original)
    binary = bytearray(raw)
    reports = []
    # Compute every output against the unchanged input, so processing one arm
    # cannot feed an already corrected pose into the opposite side.
    for side, sign, return_phase, yaw_deg in [("Left", 1., 0., left_yaw_deg), ("Right", -1., .5, right_yaw_deg)]:
        bone = ids["mixamorig:" + side + "ForeArm"]
        channel = next(channel for channel in action["channels"]
                       if channel["target"] == {"node": bone, "path": "rotation"})
        sampler = action["samplers"][channel["sampler"]]
        if sum(other["sampler"] == channel["sampler"] for other in action["channels"]) != 1:
            raise ValueError("ForeArm sampler is shared")
        if sampler.get("interpolation", "LINEAR") != "LINEAR":
            raise ValueError("Expected the existing periodic LINEAR/Slerp ForeArm curve")
        times = read(d, raw, sampler["input"]).ravel()
        values = []
        for at in times:
            phase = float(at) / duration
            weight = .5 + .5 * np.cos(2 * np.pi * (phase - return_phase))
            offset = Rotation.from_euler("y", sign * yaw_deg * weight, degrees=True).as_matrix()
            current, _ = world_matrices(original, raw, next(a for a in original["animations"] if a["name"] == "run"), float(at))
            desired = offset @ current[bone][:3, :3]
            local = np.linalg.inv(current[parents[bone]][:3, :3]) @ desired
            q = Rotation.from_matrix(local).as_quat()
            if values and np.dot(q, values[-1]) < 0:
                q = -q
            values.append(q)
        values = np.asarray(values, dtype="<f4")
        values[-1] = values[0]
        sampler["output"] = append(d, binary, sampler["output"], values)
        expected_action = next(a for a in expected["animations"] if a["name"] == "run")
        expected_action["samplers"][channel["sampler"]]["output"] = sampler["output"]
        reports.append({"node": "mixamorig:" + side + "ForeArm", "path": "rotation", "keys": len(values),
                        "return_phase": return_phase, "outward_yaw_deg_max": yaw_deg,
                        "periodic_window": "0.5+0.5*cos(2*pi*(phase-return_phase))", "endpoint_bitexact": bool(np.array_equal(values[0], values[-1]))})
    expected["accessors"] = d["accessors"]
    expected["bufferViews"] = d["bufferViews"]
    if d != expected or bytes(binary[:len(raw)]) != raw:
        raise AssertionError("Unrelated source payload changed")
    output.parent.mkdir(parents=True, exist_ok=True)
    save(d, binary, output)
    return {"stage": "tanaka-run-returning-hand-clearance", "source": str(source), "source_sha256": sha(source),
            "output": str(output), "output_sha256": sha(output), "tool_sha256": sha(__file__),
            "duration_s": duration, "changed_channels": reports, "old_bin_prefix_exact": True,
            "all_existing_mesh_skin_rest_uv_morph_and_material_payload_exact": True,
            "all_11_nonrun_animations_exact": True, "all_other_run_channels_and_input_times_exact": True,
            "scope": __doc__}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--left-yaw-deg", type=float, default=24.5)
    parser.add_argument("--right-yaw-deg", type=float, default=14.)
    args = parser.parse_args()
    result = repair(args.input, args.output, args.left_yaw_deg, args.right_yaw_deg)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()

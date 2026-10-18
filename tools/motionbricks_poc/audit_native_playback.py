#!/usr/bin/env python3
"""Read-only comparison of rendered native movie journals with their actual GLBs.

This checks logged post-draw Skeleton3D transforms, not pixels or physical validity.
It samples glTF local tracks and hierarchy at the AnimationPlayer's logged time.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from scipy.spatial.transform import Rotation

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "art/tools/characters"))
from glb_io import load  # noqa: E402
from motion_math import world_matrices  # noqa: E402

WATCH = {
    "Hips", "Spine2", "Head", "LeftArm", "RightArm", "LeftForeArm",
    "RightForeArm", "LeftHand", "RightHand", "LeftUpLeg", "RightUpLeg",
    "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftToeBase",
    "RightToeBase",
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def short_name(name: str) -> str:
    return name.removeprefix("mixamorig:").removeprefix("mixamorig_")


def rigid_rotation(basis: np.ndarray) -> np.ndarray:
    u, _, vh = np.linalg.svd(basis)
    out = u @ vh
    if np.linalg.det(out) < 0:
        raise ValueError("A reflected world basis cannot be silently normalized")
    return out


def errors(observed: np.ndarray, expected: np.ndarray) -> dict:
    return {
        "position_m": float(np.linalg.norm(observed[:3, 3] - expected[:3, 3])),
        "basis_component": float(np.max(np.abs(observed[:3, :3] - expected[:3, :3]))),
        "rotation_deg": float(np.degrees(Rotation.from_matrix(
            rigid_rotation(observed[:3, :3]).T @ rigid_rotation(expected[:3, :3])
        ).magnitude())),
        "singular_scale": float(np.max(np.abs(
            np.linalg.svd(observed[:3, :3], compute_uv=False)
            - np.linalg.svd(expected[:3, :3], compute_uv=False)
        ))),
    }


def native_matrix(flat: list) -> np.ndarray:
    values = np.asarray(flat, dtype=float)
    if values.shape != (12,) or not np.isfinite(values).all():
        raise ValueError("Native bone transform must contain twelve finite numbers")
    out = np.eye(4)
    out[:3, 3] = values[:3]
    # viewer.gd serializes Godot Basis.x, Basis.y, Basis.z (columns).
    out[:3, :3] = values[3:].reshape(3, 3).T
    return out


def maxima(records: list[dict]) -> dict:
    if not records:
        raise ValueError("Empty native bone domain")
    result = {}
    for metric in ("position_m", "basis_component", "rotation_deg", "singular_scale"):
        worst = max(records, key=lambda row: row[metric])
        result[metric] = {
            "max": worst[metric],
            "worst": {key: worst[key] for key in ("journal_row", "drawn_frame", "clip_time", "bone")},
        }
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--journal", type=Path, required=True)
    ap.add_argument("--retarget-manifest", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--position-tolerance-m", type=float, default=5e-5)
    ap.add_argument("--rotation-tolerance-deg", type=float, default=0.02)
    ap.add_argument("--basis-tolerance", type=float, default=5e-5)
    args = ap.parse_args()
    for tolerance in (args.position_tolerance_m, args.rotation_tolerance_deg, args.basis_tolerance):
        if not np.isfinite(tolerance) or tolerance <= 0:
            ap.error("Tolerances must be positive and finite")

    journal = json.loads(args.journal.read_text())
    manifest = json.loads(args.retarget_manifest.read_text())
    frames = journal["frames"]
    if not frames or journal.get("failures"):
        raise ValueError("Journal is empty or reports native failures")
    if journal.get("no_game_controllers") is not True:
        raise ValueError("Journal does not attest isolation from game controllers")
    fps = float(journal["fps"])
    if not np.isfinite(fps) or fps <= 0:
        raise ValueError("Journal fps must be positive and finite")
    characters = {x["character"]: x for x in manifest["characters"]}
    actor_ids = sorted({actor for frame in frames for actor in frame["actors"] if actor != "source"})
    if not actor_ids:
        raise ValueError("This auditor requires native character bones; source proxy has no Skeleton3D")
    input_receipt = args.journal.parent.parent / "project-inputs.json"
    receipts = json.loads(input_receipt.read_text()) if input_receipt.exists() else {}
    reports = []
    failures = []
    for actor in actor_ids:
        character = characters[actor]
        glb = Path(character["output_glb"])
        actual_sha = sha(glb)
        identity_ok = actual_sha == character["output_sha256"]
        recorded_sha = receipts.get(f"assets/CH_{actor}.glb")
        identity_ok = identity_ok and recorded_sha == actual_sha
        if not identity_ok:
            failures.append(f"{actor}: native/retarget GLB identity mismatch or absent receipt")
        doc, binary = load(glb)
        node_ids = {short_name(node.get("name", "")): index for index, node in enumerate(doc["nodes"])
                    if node.get("name", "").startswith(("mixamorig:", "mixamorig_"))}
        clips = {clip["motion_id"]: clip for clip in character["clips"]}
        for motion_id in dict.fromkeys(frame["motion_id"] for frame in frames if actor in frame["actors"]):
            clip = clips[motion_id]
            animation = next(a for a in doc["animations"] if a["name"] == clip["clip"])
            npz_path = Path(clip["audit_npz"])
            npz_sha = sha(npz_path)
            if npz_sha != clip["audit_npz_sha256"]:
                failures.append(f"{actor}/{motion_id}: audit NPZ SHA mismatch")
            expected_n = int(clip["frames"])
            expected_fps = float(clip["fps"])
            if abs(expected_fps - fps) > 1e-9:
                failures.append(f"{actor}/{motion_id}: source and native fps differ")
            samples = [(i, f) for i, f in enumerate(frames)
                       if f["motion_id"] == motion_id and actor in f["actors"]]
            records = []
            offset_errors = {-1: [], 1: []}
            root_errors = []
            actual_times = []
            assigned_clips = set()
            sampled_indices = []
            for row, frame in samples:
                state = frame["actors"][actor]
                time = float(state["clip_time"])
                if not np.isfinite(time):
                    raise ValueError("Nonfinite AnimationPlayer time")
                actual_times.append(time)
                assigned_clips.add(state["assigned_clip"])
                if state.get("game_modifiers_attached") is not False:
                    failures.append(f"{actor}/{motion_id}: unexpected or unknown game modifier state")
                observed_bones = {short_name(name): native_matrix(value) for name, value in state["bones"].items()}
                if set(observed_bones) != WATCH:
                    raise ValueError("Journal must contain the exact nonempty seventeen-bone native domain")
                worlds, _ = world_matrices(doc, binary, animation, time)
                neighbor_worlds = {offset: world_matrices(doc, binary, animation, time + offset / fps)[0]
                                   for offset in offset_errors}
                for bone, observed in observed_bones.items():
                    record = errors(observed, worlds[node_ids[bone]])
                    record.update(journal_row=row, drawn_frame=frame["drawn_frame"], clip_time=time, bone=bone)
                    records.append(record)
                    for offset in offset_errors:
                        offset_errors[offset].append(float(np.linalg.norm(
                            observed[:3, 3] - neighbor_worlds[offset][node_ids[bone]][:3, 3]
                        )))
                native_root = np.asarray(state["root"], dtype=float)
                if native_root.shape != (3,) or not np.isfinite(native_root).all():
                    raise ValueError("Native root must contain three finite numbers")
                root_errors.append(float(np.linalg.norm(native_root - observed_bones["Hips"][:3, 3])))
                sampled_indices.append(int(round(time * fps)))
            if assigned_clips != {clip["clip"]}:
                failures.append(f"{actor}/{motion_id}: assigned native clip differs")
            metrics = maxima(records)
            if metrics["position_m"]["max"] > args.position_tolerance_m:
                failures.append(f"{actor}/{motion_id}: native world positions exceed strict tolerance")
            if metrics["rotation_deg"]["max"] > args.rotation_tolerance_deg:
                failures.append(f"{actor}/{motion_id}: native world rotations exceed strict tolerance")
            if metrics["basis_component"]["max"] > args.basis_tolerance:
                failures.append(f"{actor}/{motion_id}: native full world bases exceed strict tolerance")
            if max(root_errors) > args.position_tolerance_m:
                failures.append(f"{actor}/{motion_id}: native root field differs from actual Hips")
            missing = sorted(set(range(expected_n)) - set(sampled_indices))
            extra_terminal_samples = max(0, sampled_indices.count(expected_n - 1) - 1)
            sequential = len(samples) == expected_n and sampled_indices == list(range(expected_n))
            max_grid_error = max(abs(time - index / fps) for time, index in zip(actual_times, sampled_indices))
            drawn = [int(frame["drawn_frame"]) for _, frame in samples]
            drawn_contiguous = all(right == left + 1 for left, right in zip(drawn, drawn[1:]))
            if not sequential or max_grid_error > 1e-6 or not drawn_contiguous:
                failures.append(f"{actor}/{motion_id}: native journal does not cover every source sample exactly once in drawn-frame order")
            with np.load(npz_path, allow_pickle=False) as audit:
                names = list(audit["semantic_joint_names"].astype(str))
                npz_p_errors, npz_r_errors = [], []
                for index in range(expected_n):
                    worlds, _ = world_matrices(doc, binary, animation, index / fps)
                    for semantic in WATCH:
                        ni = names.index(semantic)
                        world = worlds[node_ids[semantic]]
                        npz_p_errors.append(float(np.linalg.norm(world[:3, 3] - audit["final_global_positions"][index, ni])))
                        npz_r_errors.append(float(np.degrees(Rotation.from_matrix(
                            rigid_rotation(world[:3, :3]).T
                            @ Rotation.from_quat(audit["final_global_quaternions_xyzw"][index, ni]).as_matrix()
                        ).magnitude())))
            if max(npz_p_errors) > args.position_tolerance_m or max(npz_r_errors) > args.rotation_tolerance_deg:
                failures.append(f"{actor}/{motion_id}: actual GLB differs from writer NPZ")
            reports.append({
                "actor": actor, "motion_id": motion_id,
                "glb": str(glb.resolve()), "glb_sha256": actual_sha,
                "recorded_native_glb_sha256": recorded_sha, "identity_ok": identity_ok,
                "audit_npz": str(npz_path.resolve()), "audit_npz_sha256": npz_sha,
                "frames": len(samples), "native_bones": sorted(WATCH),
                "native_bone_samples": len(records), "same_ap_time_errors": metrics,
                "neighbor_time_negative_controls_position_max_m": {
                    str(offset): max(value) for offset, value in offset_errors.items()
                },
                "root_field_vs_native_hips_max_m": max(root_errors),
                "timing": {
                    "first_clip_time_s": actual_times[0], "last_clip_time_s": actual_times[-1],
                    "drawn_first": drawn[0], "drawn_last": drawn[-1], "drawn_contiguous": drawn_contiguous,
                    "source_samples_expected": expected_n, "sample_indices": sampled_indices,
                    "missing_source_sample_indices": missing,
                    "extra_terminal_sample_rows": extra_terminal_samples,
                    "every_source_sample_once_in_order": sequential,
                    "max_source_grid_rounding_error_s": max_grid_error,
                },
                "glb_vs_writer_npz_all_source_key_samples": {
                    "position_max_m": max(npz_p_errors), "rotation_max_deg": max(npz_r_errors),
                    "interpretation": "Secondary provenance check; native comparison independently uses the actual GLB local tracks and hierarchy.",
                },
            })
    report = {
        "schema": "motionbricks_native_playback_audit_v1",
        "pass": not failures, "failures": failures,
        "journal": str(args.journal.resolve()), "journal_sha256": sha(args.journal),
        "retarget_manifest": str(args.retarget_manifest.resolve()),
        "retarget_manifest_sha256": sha(args.retarget_manifest),
        "native_input_receipt": str(input_receipt.resolve()),
        "native_input_receipt_sha256": sha(input_receipt) if input_receipt.exists() else None,
        "method": "Sample glTF local TRS with source LINEAR/Slerp interpolation and full parent hierarchy at logged AP clip_time. Compare post-draw native world position, full basis, polar rotation and singular scales. No fitted axis alignment, phase shift, inferred model transform or normalized-scale substitution.",
        "tolerances": {"position_m": args.position_tolerance_m, "rotation_deg": args.rotation_tolerance_deg,
                       "basis_component": args.basis_tolerance,
                       "purpose": "Strict import/playback identity; does not assess visual naturalness or physical correctness."},
        "limitations": ["Relies on the renderer's post-draw bone journal; it does not independently decode pixels.",
                        "Covers the seventeen explicitly watched body bones, not all fingers, clothing, morphs or skin vertices.",
                        "Neighbor-time errors are same-data diagnostic negative controls, not separate native engine runs."],
        "actors_and_clips": reports,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"pass": report["pass"], "report": str(args.out), "failures": failures}, ensure_ascii=False))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

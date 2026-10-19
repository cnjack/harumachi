#!/usr/bin/env python3
"""Convert real NVIDIA Kimodo G1 NPZ output into the MotionBricks G1 input schema.

The Kimodo skeleton is the same 34-joint Unitree G1 skeleton used by
tools/motionbricks_poc/retarget.py, only saved without names, fps, reference
pose or MuJoCo qpos. Nothing is synthesized: positions and rotations come from
Kimodo's own `posed_joints` and `global_rot_mats`.

A single reference clip supplies the shared neutral frame-0 pose all clips are
calibrated against. `qpos` is zero-filled because the retargeter validates but
never consumes it; exported TRS is the actual reference.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation

G1_JOINTS = [
    "pelvis_skel",
    "left_hip_pitch_skel", "left_hip_roll_skel", "left_hip_yaw_skel", "left_knee_skel",
    "left_ankle_pitch_skel", "left_ankle_roll_skel", "left_toe_base",
    "right_hip_pitch_skel", "right_hip_roll_skel", "right_hip_yaw_skel", "right_knee_skel",
    "right_ankle_pitch_skel", "right_ankle_roll_skel", "right_toe_base",
    "waist_yaw_skel", "waist_roll_skel", "waist_pitch_skel",
    "left_shoulder_pitch_skel", "left_shoulder_roll_skel", "left_shoulder_yaw_skel",
    "left_elbow_skel", "left_wrist_roll_skel", "left_wrist_pitch_skel", "left_wrist_yaw_skel",
    "left_hand_roll_skel",
    "right_shoulder_pitch_skel", "right_shoulder_roll_skel", "right_shoulder_yaw_skel",
    "right_elbow_skel", "right_wrist_roll_skel", "right_wrist_pitch_skel", "right_wrist_yaw_skel",
    "right_hand_roll_skel",
]
FPS = 30


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def continuous_quaternions(rotations: np.ndarray) -> np.ndarray:
    quat = Rotation.from_matrix(rotations.reshape(-1, 3, 3)).as_quat().reshape(*rotations.shape[:-2], 4)
    for frame in range(1, len(quat)):
        flip = np.sum(quat[frame] * quat[frame - 1], axis=-1) < 0
        quat[frame, flip] *= -1
    return quat


def load(path: Path) -> dict:
    with np.load(path, allow_pickle=False) as payload:
        data = {key: payload[key].copy() for key in payload.files}
    for key in ("posed_joints", "global_rot_mats", "foot_contacts"):
        if key not in data:
            raise ValueError(f"Kimodo NPZ lacks {key}: {path}")
    positions = np.asarray(data["posed_joints"], dtype=np.float32)
    rotations = np.asarray(data["global_rot_mats"], dtype=np.float32)
    contacts = np.asarray(data["foot_contacts"], dtype=bool)
    frames = len(positions)
    if (frames < 2 or positions.shape != (frames, 34, 3)
            or rotations.shape != (frames, 34, 3, 3) or contacts.shape != (frames, 4)):
        raise ValueError(f"Unexpected Kimodo shapes in {path}: {positions.shape}")
    if not (np.isfinite(positions).all() and np.isfinite(rotations).all()):
        raise ValueError(f"Non-finite Kimodo output: {path}")
    return {"positions": positions, "rotations": rotations, "contacts": contacts}


def write(reference: dict, source: dict, source_path: Path, output: Path) -> dict:
    frames = len(source["positions"])
    positions = source["positions"]
    quat = continuous_quaternions(source["rotations"])
    ref_positions = reference["positions"][0]
    ref_quat = continuous_quaternions(reference["rotations"])[0]
    core = {
        "fps": np.asarray(FPS, dtype=np.float32),
        "joint_names": np.asarray(G1_JOINTS, dtype="<U32"),
        "global_positions": positions,
        "global_quaternions_xyzw": quat,
        "reference_global_positions": ref_positions,
        "reference_global_quaternions_xyzw": ref_quat,
        "qpos": np.zeros((frames, 36), dtype=np.float32),
        "foot_contacts": source["contacts"],
        "kimodo_source_npz": np.asarray(source_path.name),
        "kimodo_source_sha256": np.asarray(sha(source_path)),
    }
    np.savez(output, **core)
    root = positions[:, 0]
    return {
        "source": str(source_path), "source_sha256": sha(source_path),
        "output": str(output), "output_sha256": sha(output),
        "frames": frames, "seconds": frames / FPS, "fps": FPS,
        "root_start_m": root[0].tolist(), "root_end_m": root[-1].tolist(),
        "root_horizontal_travel_m": float(np.linalg.norm((root[-1] - root[0])[[0, 2]])),
        "contact_frames": {name: int(source["contacts"][:, i].sum())
                           for i, name in enumerate(("left_ankle", "left_toe", "right_ankle", "right_toe"))},
        "detail": "Kimodo posed_joints/global_rot_mats converted as-is; reference is neutral clip frame 0",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", nargs="+", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    reference = load(args.reference)
    report = {"kind": "NVIDIA Kimodo G1 NPZ -> MotionBricks schema adapter",
              "joint_source": "kimodo/skeleton/definitions.py G1Skeleton34",
              "reference": str(args.reference), "reference_sha256": sha(args.reference),
              "clips": []}
    for path in args.inputs:
        output = args.output_dir / path.name
        report["clips"].append(write(reference, load(path), path, output))
    (args.output_dir / "conversion.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(args.output_dir / "conversion.json")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate independent, real MotionBricks G1 POC motion on CPU, without a GUI.

No game assets are written. All 34-joint exports are official FK of the same
final qpos stream; raw neural features are retained separately, never substituted
for the exported positions. Running is deliberately absent from the action menu.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
import math
import os
from pathlib import Path
import platform
import random
import sys
import time
import traceback

from official_cpu import (EXPECTED_COMMIT, checkpoint_paths, inspect_source,
                          load_agent, package_versions, prepare_overlay,
                          qualify_checkpoints, sha, write_json)


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REPO = ROOT / "art/poc/motionbricks_20261018/vendor/GR00T-WholeBodyControl"
ACTIONS = {mode: mode for mode in ("idle", "slow_walk", "walk", "walk_left", "walk_right",
           "stealth_walk", "walk_stealth", "injured_walk", "walk_happy_dance",
           "walk_boxing", "hand_crawling", "elbow_crawling", "walk_zombie", "walk_scared", "walk_gun")}
ALIASES = {"left": "walk_left", "right": "walk_right", "stealth": "stealth_walk",
           "crouch": "walk_stealth", "injured": "injured_walk", "happy": "walk_happy_dance",
           "boxing": "walk_boxing", "zombie": "walk_zombie"}


def action_list(value: str) -> list[str]:
    actions = [ALIASES.get(a, a) for a in value.split(",")]
    if not actions or len(set(actions)) != len(actions) or any(a not in ACTIONS for a in actions):
        raise argparse.ArgumentTypeError("Choose distinct actions from " + ",".join(ACTIONS))
    return actions


def segment_frames(seconds: float, fps: int = 30) -> int:
    frames = round(seconds * fps)
    if seconds < 0 or abs(frames - seconds * fps) > 1e-7:
        raise ValueError("Durations must be nonnegative whole 30fps frame counts")
    return frames


def command_sequence(action: str, lead: float, duration: float, tail: float) -> list[dict]:
    result = []
    start = 0
    for name, seconds in (("idle", lead), (action, duration), ("idle", tail)):
        count = segment_frames(seconds)
        if not count:
            continue
        movement = [0.0, 0.0, 0.0] if name == "idle" else (
            [0.0, 1.0, 0.0] if name == "walk_left" else
            [0.0, -1.0, 0.0] if name == "walk_right" else [1.0, 0.0, 0.0])
        result.append({"start_frame": start, "end_frame_exclusive": start + count,
                       "action": name, "mode": ACTIONS[name],
                       "movement_direction_mujoco": movement,
                       "facing_direction_mujoco": [1.0, 0.0, 0.0]})
        start += count
    if start < 2:
        raise ValueError("At least two frames must be generated")
    return result


def load_schedules(path: Path) -> dict:
    """Validate steering/style commands without accepting arbitrary pose edits."""
    payload = json.loads(path.read_text())
    result = {}
    for item in payload['sequences']:
        name = item['id']
        if not name or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789_' for c in name) or name in result:
            raise ValueError('Schedule IDs must be unique lowercase safe filenames')
        start, commands = 0, []
        for segment in item['segments']:
            mode = segment['mode']
            count = segment_frames(float(segment['seconds']))
            if mode not in ACTIONS or count < 4:
                raise ValueError('Each segment needs a released official mode and at least four frames')
            vectors = {}
            for key in ['movement_direction_mujoco', 'facing_direction_mujoco']:
                vector = [float(v) for v in segment[key]]
                if len(vector) != 3 or not all(math.isfinite(v) for v in vector) or abs(vector[2]) > 1e-8:
                    raise ValueError('Expected finite horizontal MuJoCo direction')
                length = math.sqrt(sum(v*v for v in vector))
                if abs(length-1) > 1e-6 and not (key.startswith('movement') and mode == 'idle' and length == 0):
                    raise ValueError('Directions must have unit length; no hidden speed scaling')
                vectors[key] = vector
            commands.append({'start_frame': start, 'end_frame_exclusive': start+count,
                             'action': mode, 'mode': mode, **vectors})
            start += count
        if not commands:
            raise ValueError('Empty control schedule')
        result[name] = commands
    if not result:
        raise ValueError('No schedules')
    return result


def npz_qualification(data: dict) -> dict:
    import numpy as np
    qpos = data["qpos"]
    names = data["joint_names"]
    frames, joints = qpos.shape[0], len(names)
    expected = {"qpos": (frames, 36), "global_positions": (frames, joints, 3),
                "global_quaternions_xyzw": (frames, joints, 4),
                "global_scales": (frames, joints, 3), "joint_parents": (joints,),
                "reference_qpos": (36,), "reference_global_positions": (joints, 3),
                "reference_global_quaternions_xyzw": (joints, 4)}
    if frames < 2 or joints != 34 or len(set(names.tolist())) != 34:
        raise ValueError("Incomplete final frame/joint coverage")
    for name, shape in expected.items():
        if data[name].shape != shape or not np.isfinite(data[name]).all():
            raise ValueError(f"Invalid finite output shape for {name}: {data[name].shape}")
    if int(data["fps"]) != 30 or not np.all(data["global_scales"] == 1):
        raise ValueError("Unexpected sampling rate or joint scale")
    norm_error = float(np.max(np.abs(np.linalg.norm(data["global_quaternions_xyzw"], axis=-1) - 1)))
    if norm_error > 1e-5:
        raise ValueError("Exported quaternion is not normalized")
    return {"frames": frames, "joints": joints, "fps": 30,
            "finite": True, "maximum_quaternion_norm_error": norm_error,
            "coordinate_system": "right-handed Y-up/Z-forward, metres",
            "qpos_coordinate_system": "MuJoCo right-handed Z-up/X-forward; root wxyz"}


def export_fk(agent, qpos):
    import numpy as np
    import torch
    from scipy.spatial.transform import Rotation
    q = torch.from_numpy(np.asarray(qpos, dtype=np.float32))[None]
    with torch.inference_mode():
        position, rotation = agent._converter.convert_mujoco_qpos_to_motion_transforms(q)
    p = position[0].detach().cpu().numpy()
    r = rotation[0].detach().cpu().numpy()
    quat = Rotation.from_matrix(r.reshape(-1, 3, 3)).as_quat().reshape(*p.shape[:2], 4)
    # Choose continuous quaternion signs; rotations themselves remain identical.
    for frame in range(1, len(quat)):
        flip = np.sum(quat[frame] * quat[frame - 1], axis=-1) < 0
        quat[frame, flip] *= -1
    orthogonal = np.einsum("...ji,...jk->...ik", r, r)
    qualification = {"rotation_matrix_orthogonality_max": float(np.max(np.abs(orthogonal - np.eye(3)))),
                     "rotation_matrix_determinant_error_max": float(np.max(np.abs(np.linalg.det(r) - 1)))}
    if qualification["rotation_matrix_orthogonality_max"] > 1e-4 or qualification["rotation_matrix_determinant_error_max"] > 1e-4:
        raise ValueError("Official converter returned invalid rotation matrices")
    return p, quat, qualification


def make_control(agent, command: dict, context):
    import torch
    modes = list(agent._clip_holder.CLIPS)
    mode = command["mode"]
    if mode not in modes:
        raise ValueError(f"Official G1 mode is unavailable: {mode}")
    allowed = agent._clip_holder.CLIPS[mode].get("allowed_pred_num_tokens")
    allowed = allowed if allowed is not None else [1] * 11
    return {"mode": torch.tensor([[modes.index(mode)]], dtype=torch.int64),
            "movement_direction": torch.tensor([command["movement_direction_mujoco"]], dtype=torch.float32),
            "facing_direction": torch.tensor([command["facing_direction_mujoco"]], dtype=torch.float32),
            "allowed_pred_num_tokens": torch.tensor([allowed], dtype=torch.int32),
            "context_mujoco_qpos": context}


def generate_motion(agent, models: dict, action: str, seed: int, args, reference: dict, schedule=None) -> dict:
    import numpy as np
    import torch
    np.random.seed(seed)
    random.seed(seed)
    torch.manual_seed(seed)
    agent.reset()
    commands = schedule if schedule is not None else command_sequence(action, args.lead_in, args.duration, args.tail)
    frames = commands[-1]["end_frame_exclusive"]
    calls, last_plan = Counter(), {}
    def counted_forward(label):
        def record(_module, _inputs, output):
            calls.update([label])
            if label == "pose":
                # Official full_agent uses argmax pose-token sampling.
                last_plan["pose_tokens_argmax"] = output["pose_logits"].argmax(dim=-1).detach().cpu().tolist()
            elif label == "root":
                last_plan["pred_num_tokens"] = output["pred_num_tokens"].detach().cpu().tolist()
        return record
    hooks = [m.backbone_net.register_forward_hook(counted_forward(label)) for label, m in models.items()]
    hooks.append(agent._inferencer._vqvae_pose_model.decoder.register_forward_hook(counted_forward("vq_decoder")))
    qpos, features, command_modes, buffer_indices, timings = [], [], [], [], []
    generation_ids, buffer_roles = [], []
    generation_id = 0
    previous_sample = None
    start = time.perf_counter()
    try:
        with torch.inference_mode():
            for frame in range(frames):
                command = next(c for c in commands if c["start_frame"] <= frame < c["end_frame_exclusive"])
                index = int(agent._current_frame_idx)
                buffer_length = int(agent.frames["mujoco_qpos"].shape[1])
                role = ("initial_reference" if generation_id == 0 else
                        "start_context" if index < 4 else
                        "end_style_constraint" if index >= buffer_length - 4 else "predicted_interior")
                if previous_sample == (generation_id, index):
                    role = "held_terminal"
                previous_sample = (generation_id, index)
                qpos.append(agent.get_next_frame().copy())
                features.append(agent.frames["model_features"][0, index].detach().cpu().numpy().copy())
                buffer_indices.append(index)
                generation_ids.append(generation_id)
                buffer_roles.append(role)
                command_modes.append(command["mode"])
                context = agent.get_context_mujoco_qpos()
                control = make_control(agent, command, context)
                before_calls = calls.copy()
                before = time.perf_counter()
                # Same 16/30 cadence as the demo, including idle. The official
                # force_generation API avoids idle-buffer freezing in this POC.
                agent.generate_new_frames(control, controller_dt=16 / 30,
                    force_generation=frame == command["start_frame"] or int(agent._current_frame_idx) >= 16)
                elapsed = time.perf_counter() - before
                if sum(calls.values()) > sum(before_calls.values()):
                    generation_id += 1
                    timings.append({"generation_id": generation_id, "command_frame": frame,
                        "first_consumed_export_frame": frame + 1 if frame + 1 < frames else None,
                        "mode": command["mode"], "seconds": elapsed,
                        "forward_counts": dict(calls - before_calls),
                        "output_buffer_frames": int(agent.frames["mujoco_qpos"].shape[1]),
                        "conditioned_start_buffer_interval": [0, 4],
                        "conditioned_end_buffer_interval": [int(agent.frames["mujoco_qpos"].shape[1]) - 4,
                                                             int(agent.frames["mujoco_qpos"].shape[1])],
                        **last_plan})
    finally:
        for hook in hooks:
            hook.remove()
    generation_seconds = time.perf_counter() - start
    if any(calls[name] == 0 for name in ("pose", "root", "vq_decoder")):
        raise RuntimeError("No real pose/root/VQ neural inference occurred; refusing a source-clip-only export")
    qpos = np.asarray(qpos, dtype=np.float32)
    positions, quaternions, fk_check = export_fk(agent, qpos)
    skeleton = agent._motion_rep.skeleton
    names = np.asarray(skeleton.bone_order_names, dtype=str)
    raw_features = np.asarray(features, dtype=np.float32)
    contact_indices = np.asarray(agent._motion_rep.indices["foot_contacts"], dtype=int)
    if len(contact_indices) != 4 or int(contact_indices.max()) >= raw_features.shape[1]:
        raise ValueError("Cannot qualify official model contact feature indices")
    data = {"fps": np.asarray(30), "joint_names": names,
            "seed": np.asarray(seed), "mode": np.asarray(ACTIONS.get(action, "multi-mode-sequence")),
            "source_commit": np.asarray(EXPECTED_COMMIT),
            "coordinate_system": np.asarray("right-handed Y-up/Z-forward; metres; quaternion xyzw"),
            "qpos_coordinate_system": np.asarray("MuJoCo right-handed Z-up/X-forward; root wxyz"),
            "joint_parents": skeleton.joint_parents.detach().cpu().numpy(),
            "qpos": qpos, "global_positions": positions,
            "global_quaternions_xyzw": quaternions,
            "global_scales": np.ones_like(positions),
            "root_positions": positions[:, skeleton.root_idx],
            "source_model_features": raw_features,
            "foot_contacts": raw_features[:, contact_indices],
            "command_modes": np.asarray(command_modes, dtype=str),
            "source_buffer_indices": np.asarray(buffer_indices),
            "generation_ids": np.asarray(generation_ids),
            "buffer_roles": np.asarray(buffer_roles, dtype=str), **reference}
    qualification = {**npz_qualification(data), **fk_check}
    dead = agent._converter.joint_indice_mapping["motion_to_mujoco"].detach().cpu().numpy() < 0
    metadata = {"action": action, "official_mode": ACTIONS.get(action, "multi-mode-sequence"), "seed": seed,
        "commands": commands, "generation_wall_seconds": generation_seconds,
        "neural_generation_calls": timings, "neural_forward_counts": dict(calls),
        "backbone_forward_counts": {name:calls[name] for name in ("root", "pose")},
        "frame_provenance_counts": dict(Counter(buffer_roles)),
        "finite_export_frames": frames,
        "requested_action_frames": sum(c["end_frame_exclusive"]-c["start_frame"] for c in commands if c["mode"] != "idle"),
        "neural_plan_consumed_frames": sum(x > 0 for x in generation_ids),
        "source_conditioning_note": "Initial reference and each plan's four start-context/end-style constraint frames "
                                    "are separately marked; they are not claimed as unconstrained new poses.",
        "host_schedule": "Fixed16/30s replanning using the official force_generation API, including idle. "
                         "Demo's idle-to-idle buffer freeze is not used. Timing includes evidence hooks and host bookkeeping.",
        "fps": 30, "qualification": qualification,
        "export_basis": "All exported34-joint positions AND rotations are official converter FK of the exact exported final qpos. "
                        "Original neural features/contact scalars are separate and may differ from filtered qpos.",
        "foot_contacts_source": "Unmodified four raw contact feature scalars from the official, unnormalized model_features; "
                                "not independently measured physical contacts or thresholded truth.",
        "dead_joint_rotation_scheme": agent._converter._dead_joint_rotation_scheme,
        "dead_joint_names": names[dead].tolist(),
        "dead_joint_note": "Official dummy global rotation retained. Retarget active wrist_yaw/ankle_roll orientation, "
                           "not dummy Hand/toe identity rotation.",
        "qpos_note": "MuJoCo Z-up/X-forward, root quaternion wxyz; qpos is kinematic generator output, not physics rollout.",
        "reference_note": "Same initialized official idle reference_qpos/FK shared by all actions; never each action's first pose."}
    return data, metadata


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--vendor", type=Path, default=DEFAULT_REPO)
    p.add_argument("--out", type=Path, required=True, help="New standalone output folder; existing paths are refused")
    p.add_argument("--device", choices=["cpu"], default="cpu")
    p.add_argument("--actions", type=action_list, default=["walk"])
    p.add_argument("--seeds", default="1234")
    p.add_argument("--schedule", type=Path, help="JSON authored control commands; never pose/keyframe overrides")
    p.add_argument("--duration", type=float, default=7.0, help="Action interval in seconds, excluding idle lead/tail; default total8s")
    p.add_argument("--lead-in", type=float, default=.5)
    p.add_argument("--tail", type=float, default=.5)
    p.add_argument("--threads", type=int, default=6)
    p.add_argument("--json-frames", action="store_true", help="Duplicate full TRS frame arrays into JSON; NPZ is always exported")
    p.add_argument("--fail-fast", action="store_true", help="Stop after first failed action; default preserves a failure report and tries the next")
    p.add_argument("--prepare-only", action="store_true", help="Only qualify source and create disclosed CPU overlay; no torch/model imports")
    return p


def main() -> None:
    args = parser().parse_args()
    args.vendor, args.out = args.vendor.resolve(), args.out.resolve()
    if args.out.exists():
        raise ValueError("Preserve earlier evidence; choose a new --out directory")
    if args.threads < 1 or not math.isfinite(args.duration) or args.duration <= 0:
        raise ValueError("Use positive threads and duration")
    seeds = [int(s) for s in args.seeds.split(",")]
    if not seeds or len(seeds) != len(set(seeds)) or any(not 0 <= s < 2 ** 32 for s in seeds):
        raise ValueError("Use distinct integer seeds in [0,2**32)")
    schedules = load_schedules(args.schedule) if args.schedule else {}
    if schedules:
        args.actions = list(schedules)
    else:
        for action in args.actions:
            command_sequence(action, args.lead_in, args.duration, args.tail)
    args.out.mkdir(parents=True)
    cache = ROOT / "art/poc/motionbricks_20261018/cache"
    for variable, subfolder in (("MPLCONFIGDIR", "matplotlib"), ("XDG_CACHE_HOME", "xdg"),
                               ("HF_HOME", "huggingface"), ("TORCH_HOME", "torch")):
        folder = cache / subfolder
        folder.mkdir(parents=True, exist_ok=True)
        os.environ[variable] = str(folder)
    receipt = prepare_overlay(args.vendor, args.out)
    plan = {"status": "prepared-not-inferred", "upstream_commit": EXPECTED_COMMIT,
            "device": "cpu", "versions": package_versions(), "platform": platform.platform(),
            "source_receipt_sha256": sha(args.out / "cpu-source/receipt.json"),
            "generator_sha256": sha(Path(__file__)),
            "host_adapter_sha256": sha(Path(__file__).with_name("official_cpu.py")),
            "actions": args.actions, "seeds": seeds,
            "control_schedule": schedules,
            "output_scope": "Independent POC; no game asset/runtime write, no GUI, keyboard, other generation model or fake run.",
            "neural_math_changes": False}
    write_json(args.out / "manifest.json", plan)
    if args.prepare_only:
        print(json.dumps(plan, indent=2))
        return
    project = args.vendor / "motionbricks"
    os.environ.setdefault("OMP_NUM_THREADS", str(args.threads))
    os.environ.setdefault("OPENBLAS_NUM_THREADS", str(args.threads))
    start = time.perf_counter()
    plan["checkpoints"] = qualify_checkpoints(project)
    import numpy as np
    import torch
    torch.set_num_threads(args.threads)
    torch.set_num_interop_threads(1)
    torch.set_default_device("cpu")
    torch.manual_seed(seeds[0])
    original_cwd = Path.cwd()
    # Official relative assets (standard T-pose, if needed) remain source-relative.
    os.chdir(project)
    try:
        agent, models, config_changes = load_agent(project, args.out / "cpu-source")
        plan["model_loading_wall_seconds"] = time.perf_counter() - start
        write_json(args.out / "effective-configs.json", config_changes)
        reference_qpos = agent.frames["mujoco_qpos"][0, 0].detach().cpu().numpy().copy()
        ref_position, ref_quaternion, _ = export_fk(agent, reference_qpos[None])
        reference = {"reference_qpos": reference_qpos,
                     "reference_global_positions": ref_position[0],
                     "reference_global_quaternions_xyzw": ref_quaternion[0]}
        plan["motions"], plan["failures"] = [], []
        for action in args.actions:
            for seed in seeds:
                motion_id = f"{action}_seed{seed}"
                print(f"GENERATE {motion_id}", flush=True)
                try:
                    data, metadata = generate_motion(agent, models, action, seed, args, reference, schedules.get(action))
                except Exception as error:
                    failure = {"motion_id": motion_id, "action": action, "seed": seed,
                               "error": repr(error), "traceback": traceback.format_exc(),
                               "no_substitute_motion_created": True}
                    write_json(args.out / (motion_id + ".failure.json"), failure)
                    plan["failures"].append(failure)
                    plan["status"] = "partial-failure-not-visually-reviewed"
                    write_json(args.out / "manifest.json", plan)
                    if args.fail_fast:
                        raise
                    continue
                target = args.out / (motion_id + ".npz")
                np.savez_compressed(target, **data)
                metadata.update({"motion_id": motion_id, "file": target.name,
                                 "npz_sha256": sha(target), "upstream_commit": EXPECTED_COMMIT,
                                 "device": "cpu", "checkpoint_sha256": {k:v["sha256"] for k,v in plan["checkpoints"].items()}})
                if args.json_frames:
                    metadata["arrays"] = {k:v.tolist() for k,v in data.items()}
                write_json(args.out / (motion_id + ".json"), metadata)
                plan["motions"].append({k:metadata[k] for k in ("motion_id", "file", "npz_sha256", "generation_wall_seconds", "qualification", "neural_forward_counts", "frame_provenance_counts", "requested_action_frames", "neural_plan_consumed_frames")})
                write_json(args.out / "manifest.json", plan)
                print(json.dumps(plan["motions"][-1]), flush=True)
        # Do not call any model speed or renderer performance figure a measured result.
        plan["status"] = "partial-failure-not-visually-reviewed" if plan["failures"] else "generated-qualified-not-visually-reviewed"
        plan["total_wall_seconds"] = time.perf_counter() - start
        plan["upstream_source_after"] = inspect_source(args.vendor)
        if plan["upstream_source_after"] != receipt["upstream"]:
            raise RuntimeError("Upstream source changed during generation")
        write_json(args.out / "manifest.json", plan)
    except Exception as error:
        plan["status"] = "failed-not-visually-reviewed"
        plan["fatal_error"] = {"error": repr(error), "traceback": traceback.format_exc()}
        write_json(args.out / "manifest.json", plan)
        raise
    finally:
        os.chdir(original_cwd)
    if plan["failures"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

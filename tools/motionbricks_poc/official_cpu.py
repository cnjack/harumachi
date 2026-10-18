"""Host-side CPU loading for an unmodified, pinned NVIDIA MotionBricks model.

The official Python sources are copied into the output's CPU overlay. Only the
five checkpoint-deserialization calls below are changed. Neural networks,
sampling, motion representation, agent, and MuJoCo conversion remain upstream.
"""
from __future__ import annotations

import difflib
import hashlib
import importlib.metadata
import json
from pathlib import Path
import shutil
import subprocess
import sys


EXPECTED_COMMIT = "45c03facbf848e0c743091b7d9c17952096ff908"
PATCHES = {
    "motion_backbone/models/pose_model.py": [
        ("t.load(vqvae_model_ckpt_path)",
         't.load(vqvae_model_ckpt_path, map_location="cpu", weights_only=False)'),
    ],
    "motion_backbone/demo/clips.py": [
        ("t.load(ckpt_path)",
         't.load(ckpt_path, map_location="cpu", weights_only=False)'),
    ],
    "motionlib/core/skeletons/base.py": [
        ('torch.load(osp.join(folder, "joints.p"))',
         'torch.load(osp.join(folder, "joints.p"), map_location="cpu", weights_only=False)'),
        ('torch.load(osp.join(folder, "parents.p"))',
         'torch.load(osp.join(folder, "parents.p"), map_location="cpu", weights_only=False)'),
    ],
    "motionlib/core/motion_reps/tools/changing_t_pose.py": [
        ("torch.load(t_pose_path)",
         'torch.load(t_pose_path, map_location="cpu", weights_only=False)'),
    ],
}


def sha(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n")


def inspect_source(repo: Path) -> dict:
    repo = repo.resolve()
    commit = subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    if commit != EXPECTED_COMMIT:
        raise ValueError(f"Review a new upstream commit explicitly: {commit}")
    package = repo / "motionbricks/motionbricks"
    tracked = subprocess.check_output(
        ["git", "-C", str(repo), "ls-files", "motionbricks"], text=True).splitlines()
    source = {str(p.relative_to(repo)): sha(p) for p in sorted(package.rglob("*.py"))}
    # Verify the Python implementation really is the committed upstream source.
    changed = subprocess.check_output(
        ["git", "-C", str(repo), "diff", "--name-only", "HEAD", "--",
         "motionbricks/motionbricks", ":(glob)motionbricks/out/**/*.yaml",
         ":(glob)motionbricks/out/**/*.npy", ":(glob)motionbricks/out/**/*.p",
         ":(glob)motionbricks/assets/skeletons/g1/*.xml"],
        text=True).splitlines()
    if changed:
        raise ValueError(f"Upstream source/assets have local changes: {changed}")
    if not source:
        raise ValueError("MotionBricks sparse source has not been expanded")
    if set(source) - set(tracked):
        raise ValueError("Unexpected untracked Python implementation in official package")
    project = repo / "motionbricks"
    auxiliary = sorted(p for p in (project / "out").rglob("*")
                       if p.is_file() and p.suffix in (".yaml", ".yml", ".npy", ".p", ".json"))
    auxiliary += sorted((project / "assets/skeletons/g1").glob("*.xml"))
    return {"repository": str(repo), "commit": commit, "python_files": source,
            "configs_stats_skeletons_xml": {str(p.relative_to(repo)): sha(p) for p in auxiliary},
            "binary_scope": "Checkpoints separately verified against pinned Git LFS OIDs; STL meshes are not loaded by this headless FK/generation path.",
            "tracked_motionbricks_files": len(tracked)}


def prepare_overlay(repo: Path, out: Path) -> dict:
    """No torch import or checkpoint deserialization; safe preparation step."""
    identity = inspect_source(repo)
    source = repo / "motionbricks/motionbricks"
    destination = out / "cpu-source/motionbricks"
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    changes = []
    diff = []
    for relative, substitutions in PATCHES.items():
        target = destination / relative
        old = target.read_text()
        new = old
        for before, after in substitutions:
            if new.count(before) != 1:
                raise ValueError(f"Inspect changed upstream load call: {relative}: {before}")
            new = new.replace(before, after)
        target.write_text(new)
        diff.extend(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                    fromfile="upstream/" + relative, tofile="cpu-overlay/" + relative))
        changes.append({"file": relative, "upstream_sha256": sha(source / relative),
                        "cpu_sha256": sha(target), "load_calls": len(substitutions)})
    shutil.copyfile(repo / "LICENSE", out / "cpu-source/UPSTREAM_LICENSE")
    patch = out / "cpu-source/cpu-deserialization.patch"
    patch.write_text("".join(diff))
    receipt = {"upstream": identity, "overlay_package": str(destination.resolve()),
               "changes": changes, "patch_sha256": sha(patch),
               "scope": "Only CPU map_location and explicit trusted official checkpoint loading. "
                        "No model/weight, inference, sampling or converter math changes.",
               "entrypoint_bypasses": ["demo.utils (keyboard/controller GUI imports)",
                                        "exp_setup.test (training setup/CUDA selection/datasets)"],
               "explicit_device": "cpu"}
    write_json(out / "cpu-source/receipt.json", receipt)
    return receipt


def checkpoint_paths(project: Path) -> dict[str, Path]:
    paths = {name: project / "out" / f"motionbricks_{name}" / "version_1" /
             "checkpoints/model-step=2000000.ckpt" for name in ("vqvae", "pose", "root")}
    paths["clips"] = project / "out/G1-clip.ckpt"
    return paths


def qualify_checkpoints(project: Path) -> dict:
    paths = checkpoint_paths(project)
    result = {}
    for name, path in paths.items():
        if not path.is_file():
            raise ValueError(f"Official checkpoint not downloaded: {path}")
        with path.open("rb") as stream:
            first = stream.read(128)
        if first.startswith(b"version https://git-lfs.github.com/spec/v1") or path.stat().st_size < 1_000_000:
            raise ValueError(f"Checkpoint is still a Git LFS pointer/incomplete file: {path}")
        relative = str(path.relative_to(project.parent))
        pointer = subprocess.check_output(
            ["git", "-C", str(project.parent), "show", "HEAD:" + relative], text=True)
        expected_oid = next(line.split(":", 1)[1] for line in pointer.splitlines() if line.startswith("oid sha256:"))
        expected_size = int(next(line.split(" ", 1)[1] for line in pointer.splitlines() if line.startswith("size ")))
        digest = sha(path)
        if digest != expected_oid or path.stat().st_size != expected_size:
            raise ValueError(f"Checkpoint differs from pinned official Git LFS object: {name}")
        result[name] = {"path": str(path.resolve()), "bytes": path.stat().st_size,
                        "sha256": digest, "official_git_lfs_oid_verified": True}
    return result


def package_versions() -> dict:
    names = ("torch", "numpy", "scipy", "mujoco", "hydra-core", "omegaconf",
             "pytorch-lightning", "transformers", "vector-quantize-pytorch", "einops")
    result = {"python": sys.version, "executable": sys.executable}
    for name in names:
        try:
            result[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            result[name] = None
    return result


def load_agent(project: Path, overlay: Path):
    """Follow official experiment.test construction without training setup.

    All original hparams and strict checkpoint state dicts are retained. Paths,
    unused trainer device settings and training-only optimizer keys are adapted.
    """
    sys.path.insert(0, str(overlay))
    import torch
    from hydra.utils import instantiate
    from omegaconf import OmegaConf, open_dict
    from motionbricks.motion_backbone.inference.motion_inference import motion_inference
    from motionbricks.motion_backbone.demo.full_agent import full_navigation_agent

    imported = Path(sys.modules["motionbricks"].__file__).resolve()
    if overlay.resolve() not in imported.parents:
        raise RuntimeError(f"CPU overlay shadowed by another MotionBricks install: {imported}")
    paths = checkpoint_paths(project)
    models, configs, changes = {}, {}, []
    for name in ("pose", "root"):
        version = project / "out" / f"motionbricks_{name}/version_1"
        config_path = version / "hparams.yaml"
        conf = OmegaConf.load(config_path)
        original = OmegaConf.to_container(conf, resolve=False)
        with open_dict(conf):
            conf.ckpt_path = str(paths[name])
            conf.skeleton.folder = str(version / "skeleton")
            conf.motion_rep.stats.folder = str(version / "stats/motion")
            conf.trainer.accelerator = "cpu"
            conf.trainer.devices = 1
            conf.trainer.num_nodes = 1
            if isinstance(conf.model.args.vqvae_model_ckpt_path, str):
                conf.model.args.vqvae_model_ckpt_path = str(paths["vqvae"])
            for training_key in ("optimizer", "scheduler"):
                if training_key in conf.model:
                    del conf.model[training_key]
        skeleton = instantiate(conf.skeleton)
        rep = instantiate(conf.motion_rep, fps=conf.fps, skeleton=skeleton)
        vq_network = None
        if conf.model.pose_vqvae_network is not None:
            use_local = getattr(conf.model, "pose_vqvae_motion_rep", "local") == "local"
            vq_rep = rep.dual_rep.local_motion_rep if use_local else rep.dual_rep.global_motion_rep
            vq_network = instantiate(conf.model.pose_vqvae_network, motion_rep=vq_rep)
        elif name == "pose":
            raise ValueError("Review upstream fallback VQVAE config explicitly before using this model")
        backbone = instantiate(conf.model.backbone_network, motion_rep=rep)
        # Preserve upstream constructor registration exactly. Passing device here
        # would additionally register pose_net and alter checkpoint state keys.
        model = instantiate(conf.model, pose_vqvae_network=vq_network,
                            backbone_network=backbone, motion_rep=rep)
        checkpoint = torch.load(paths[name], map_location="cpu", weights_only=False)
        model.load_state_dict(checkpoint["state_dict"], strict=True)
        del checkpoint
        model.eval().to("cpu")
        model.requires_grad_(False)
        models[name], configs[name] = model, conf
        changes.append({"model": name, "config": str(config_path),
                        "config_sha256": sha(config_path), "original": original,
                        "effective": OmegaConf.to_container(conf, resolve=False)})
    inferencer = motion_inference(models, models["pose"].args, device="cpu")
    # Use the exact official agent and its default pose filtering/dead-joint scheme.
    agent = full_navigation_agent(inferencer, None, device="cpu", speed_scale=[1.0, 1.0],
            skeleton_xml=str(project / "assets/skeletons/g1/g1.xml"),
            clips="G1", ckpt_path=str(paths["clips"]), reprocess_clips=False,
            target_root_realignment=True, source_root_realignment=True,
            force_canonicalization=True, skip_ending_target_cond=False, filter_qpos=True).eval().to("cpu")
    if float(agent._fps) != 30.0:
        raise ValueError(f"Expected official 30fps, got {agent._fps}")
    for name, model in models.items():
        if any(p.device.type != "cpu" for p in model.parameters()):
            raise RuntimeError(f"Non-CPU model parameter: {name}")
    return agent, models, changes

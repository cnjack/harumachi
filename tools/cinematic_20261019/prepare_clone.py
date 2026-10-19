#!/usr/bin/env python3
"""Create an APFS clone of game/, swap in the Kimodo-retargeted characters and the
cinematic driver. The production game/ tree is only read."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
RETARGET = ROOT / "art/poc/motionbricks_20261018/retargeted/cinematic-film-v1"
DRIVER = Path(__file__).resolve().parent / "godot"
EVIDENCE = ROOT / "evidence/cinematic_20261019"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, check=True, **kw)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clone", type=Path, help="destination directory; default: fresh /tmp path")
    ap.add_argument("--godot", default=str(ROOT / "tools/godot"))
    ap.add_argument("--no-import", action="store_true")
    args = ap.parse_args()

    if args.clone is None:
        args.clone = Path(tempfile.mkdtemp(prefix="harumachi-film-clone."))
    clone = args.clone.resolve()
    if clone.exists() and any(clone.iterdir()):
        marker = clone / ".cinematic_clone"
        if not marker.is_file():
            raise SystemExit(f"refusing to write into non-clone directory: {clone}")
        raise SystemExit(f"clone already exists: {clone}")
    clone.mkdir(parents=True, exist_ok=True)

    sources = [
        GAME / "assets/models/CH_sora.glb",
        GAME / "assets/models/CH_mio.glb",
    ]
    before = {str(p.relative_to(ROOT)): sha256(p) for p in sources}
    commit = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"],
                            capture_output=True, text=True, check=True).stdout.strip()

    print(f"cloning {GAME} -> {clone / 'game'}", flush=True)
    t0 = time.time()
    try:
        run(["cp", "-cR", str(GAME), str(clone / "game")])
    except subprocess.CalledProcessError:
        run(["cp", "-R", str(GAME), str(clone / "game")])
    print(f"clone done in {time.time() - t0:.1f}s", flush=True)

    target = clone / "game"
    for stem in ("CH_sora", "CH_mio"):
        dst = target / f"assets/models/{stem}.glb"
        shutil.copy2(RETARGET / f"{stem}.glb", dst)
        for p in [target / f"assets/models/{stem}.glb.import"]:
            p.unlink(missing_ok=True)
        for p in (target / ".godot/imported").glob(f"{stem}.glb-*"):
            p.unlink(missing_ok=True)

    driver_dst = target / "cinematic"
    driver_dst.mkdir(exist_ok=True)
    for p in DRIVER.iterdir():
        if p.suffix in {".gd", ".tscn", ".tres"}:
            shutil.copy2(p, driver_dst / p.name)

    after = {str(p.relative_to(ROOT)): sha256(p) for p in sources}
    if before != after:
        raise SystemExit("production character models changed while preparing the clone")

    manifest = {
        "kind": "isolated cinematic clone",
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "source_commit": commit,
        "clone": str(clone),
        "game": str(target),
        "production_model_hashes_before": before,
        "production_model_hashes_after": after,
        "retargeted_models": {
            "CH_sora": {
                "path": str(RETARGET / "CH_sora.glb"),
                "sha256": sha256(RETARGET / "CH_sora.glb"),
            },
            "CH_mio": {
                "path": str(RETARGET / "CH_mio.glb"),
                "sha256": sha256(RETARGET / "CH_mio.glb"),
            },
        },
    }
    (clone / ".cinematic_clone").write_text(json.dumps(manifest, indent=2))
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / "clone.json").write_text(json.dumps(manifest, indent=2))
    (EVIDENCE / "clone_path.txt").write_text(str(clone) + "\n")

    if not args.no_import:
        env = dict(os.environ)
        env["HARUMACHI_SAVE_DIR"] = str(clone / "save")
        run([args.godot, "--headless", "--path", str(target), "--import"], env=env)
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()

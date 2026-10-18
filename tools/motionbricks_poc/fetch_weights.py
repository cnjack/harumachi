#!/usr/bin/env python3
"""Fetch official LFS objects by pinned revision and verify pointer SHA/size."""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess
import time
import urllib.parse


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vendor", type=Path)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    vendor = args.vendor.resolve()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=vendor, text=True).strip()
    relative_files = subprocess.check_output(
        ["git", "ls-files", "motionbricks/out", "motionbricks/assets/skeletons/g1"],
        cwd=vendor, text=True,
    ).splitlines()
    objects = []
    for relative in relative_files:
        # Read the committed pointer, also when the worktree file is hydrated.
        committed = subprocess.check_output(["git", "show", f"{revision}:{relative}"], cwd=vendor)
        if not committed.startswith(b"version https://git-lfs.github.com/spec/v1\n"):
            continue
        fields = dict(line.split(" ", 1) for line in committed.decode().splitlines())
        objects.append({"path": relative, "sha256": fields["oid"].split(":", 1)[1], "bytes": int(fields["size"])})
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()

    def fetch(item: dict) -> dict:
        target = vendor / item["path"]
        if target.stat().st_size == item["bytes"]:
            with target.open("rb") as existing:
                if hashlib.file_digest(existing, "sha256").hexdigest() == item["sha256"]:
                    return dict(item, status="already_verified")
        url = "https://media.githubusercontent.com/media/NVlabs/GR00T-WholeBodyControl/" + revision + "/" + urllib.parse.quote(item["path"], safe="/")
        temporary = target.with_name(target.name + ".download-part")
        print(json.dumps({"download": item["path"], "bytes": item["bytes"]}), flush=True)
        # System curl uses the configured OS trust store. TLS verification stays on.
        subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error",
                        "--retry", "2", "--connect-timeout", "30", "--max-time", "1200",
                        "--output", str(temporary), url], check=True)
        count = temporary.stat().st_size
        with temporary.open("rb") as downloaded:
            actual_sha = hashlib.file_digest(downloaded, "sha256").hexdigest()
        if count != item["bytes"] or actual_sha != item["sha256"]:
            raise ValueError(f"Official LFS size/SHA mismatch for {item['path']}")
        temporary.replace(target)
        print(json.dumps({"verified": item["path"], "bytes": count}), flush=True)
        return dict(item, status="downloaded_verified", url=url)

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(fetch, objects))
    receipt = {"official_repository": "https://github.com/NVlabs/GR00T-WholeBodyControl", "revision": revision,
               "license_sha256": hashlib.sha256((vendor / "LICENSE").read_bytes()).hexdigest(),
               "elapsed_seconds": time.monotonic() - started, "verified": True, "objects": results}
    args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"verified_objects": len(results), "total_bytes": sum(x["bytes"] for x in results), "receipt": str(args.receipt)}), flush=True)


if __name__ == "__main__":
    main()

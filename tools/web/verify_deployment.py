#!/usr/bin/env python3
"""Check the published Web build without stressing the server with parallel PCK downloads."""
from pathlib import Path
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from zoneinfo import ZoneInfo
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--site", type=Path, default=ROOT / "site")
parser.add_argument("--evidence", type=Path, required=True)
parser.add_argument("--manifest", type=Path, required=True)
parser.add_argument("--base", default="https://harumachi.nightc.com/")
parser.add_argument("--release", required=True)
args = parser.parse_args()
SITE = args.site.resolve()
OUT = args.evidence.resolve()
OUT.mkdir(parents=True, exist_ok=True)
BASE = args.base.rstrip("/") + "/"
MANIFEST = [line.split("  ", 1) for line in args.manifest.read_text().splitlines()]


def curl(*args):
    return subprocess.check_output(["curl", "--fail", "--silent", "--show-error", "--connect-timeout", "10", "--max-time", "40", *args])


def headers(name, *args):
    raw = curl("--head", *args, BASE + name).decode()
    values = {key.lower(): value.strip() for line in raw.splitlines() if ":" in line for key, value in [line.split(":", 1)]}
    return int(raw.splitlines()[0].split()[1]), values


def check(item):
    digest, name = item
    status, values = headers(name)
    return {"path": name, "status": status, "bytes_match": int(values["content-length"]) == (SITE / name).stat().st_size}


with ThreadPoolExecutor(max_workers=3) as pool:
    public_files = list(pool.map(check, MANIFEST))
body_checks = []
for name in ("index.html", "library.js", "style.css", "ui.css", "play.css", "main.js", "play/index.html", "play/index.js", "assets/library.json", "release.json"):
    data = curl(BASE + name)
    body_checks.append({"path": name, "sha256": hashlib.sha256(data).hexdigest(), "matches": data == (SITE / name).read_bytes()})
wasm_checks = []
for name in ("play/index.wasm", "play/index.side.wasm", "play/libgdsqlite.web.template_release.wasm32.nothreads.wasm"):
    _, wasm = headers(name, "--header", "Accept-Encoding: gzip")
    assert wasm["content-type"].startswith("application/wasm")
    assert wasm["content-encoding"] == "gzip"
    assert wasm["cross-origin-opener-policy"] == "same-origin"
    assert wasm["cross-origin-embedder-policy"] == "require-corp"
    wasm_checks.append({"path": name, "headers": wasm})
_, home = headers("")
assert "cross-origin-opener-policy" not in home
pack = SITE / "play/index.pck"
size = pack.stat().st_size
range_checks = []
for start, end in ((0, 63), (size - 64, size - 1)):
    header_file = OUT / f"range-{start}.txt"
    data = curl("--dump-header", str(header_file), "--header", f"Range: bytes={start}-{end}", BASE + "play/index.pck")
    with pack.open("rb") as source:
        source.seek(start)
        expected = source.read(end - start + 1)
    assert "206" in header_file.read_text().splitlines()[0]
    range_checks.append({"start": start, "end": end, "matches": data == expected})
report = {"release": args.release, "checked_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(), "files": public_files, "body_sha256": body_checks, "wasm_headers": wasm_checks, "game_headers_scoped": True, "pck_ranges": range_checks, "passed": all(f["status"] == 200 and f["bytes_match"] for f in public_files) and all(c["matches"] for c in body_checks) and all(c["matches"] for c in range_checks)}
(OUT / "verification-live.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"files": len(public_files), "passed": report["passed"], "wasm_mime": wasm["content-type"], "gzip": wasm["content-encoding"], "pck_ranges": range_checks}))
assert report["passed"]

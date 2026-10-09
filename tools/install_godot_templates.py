#!/usr/bin/env python3
"""Install selected templates from the pinned official archive, with ZIP CRC checks."""
import argparse
import binascii
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import zlib

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "tools/godot-version.json").read_text())
parser = argparse.ArgumentParser()
parser.add_argument("--platform", choices=["macos", "web", "all"], default="all")
parser.add_argument("--evidence", type=Path, required=True)
args = parser.parse_args()
args.evidence.mkdir(parents=True, exist_ok=True)
url = "https://godot-releases.nbg1.your-objectstorage.com/{tag}/Godot_v{tag}_export_templates.tpz".format(tag=LOCK["release_tag"])
headers = subprocess.check_output(["curl", "-fLsSI", "--connect-timeout", "15", "--max-time", "45", url], text=True)
size = int(re.findall(r"(?im)^content-length:\s*(\d+)", headers)[-1])

def ranged(start, count):
    header_file = args.evidence / "template-fetch-headers.txt"
    end = start + count - 1
    data = subprocess.check_output(["curl", "-fLsS", "--retry", "2", "--connect-timeout", "15",
        "--max-time", "240", "--max-filesize", str(count), "--range", f"{start}-{end}",
        "--dump-header", str(header_file), url])
    expected = f"content-range: bytes {start}-{end}/{size}"
    if expected not in header_file.read_text().lower() or len(data) != count:
        raise RuntimeError("Server did not honor the exact requested ZIP range")
    return data

tail = ranged(max(0, size - 65557), min(size, 65557))
(args.evidence / "template-zip-tail.bin").write_bytes(tail)
offset = tail.rfind(b"PK\x05\x06")
if offset < 0:
    raise RuntimeError("ZIP directory not found")
eocd = struct.unpack_from("<4s4H2IH", tail, offset)
central_size, central_offset = eocd[5:7]
central = ranged(central_offset, central_size)
names = {"templates/version.txt"}
if args.platform in ("macos", "all"):
    names.add("templates/macos.zip")
if args.platform in ("web", "all"):
    names.update({"templates/web_dlink_nothreads_release.zip", "templates/web_dlink_nothreads_debug.zip"})
cursor = 0
records = []
while cursor < len(central):
    entry = struct.unpack_from("<4s6H3I5H2I", central, cursor)
    if entry[0] != b"PK\x01\x02":
        raise RuntimeError("Invalid ZIP directory")
    name = central[cursor + 46:cursor + 46 + entry[10]].decode()
    if name in names:
        records.append((name, entry[4], entry[7], entry[8], entry[9], entry[16]))
    cursor += 46 + entry[10] + entry[11] + entry[12]
if {r[0] for r in records} != names:
    raise RuntimeError("Required templates missing: " + str(names - {r[0] for r in records}))
target = Path.home() / "Library/Application Support/Godot/export_templates" / LOCK["template_version"]
target.mkdir(parents=True, exist_ok=True)
installed = []
for name, method, crc, compressed_size, unpacked_size, local_offset in records:
    output = target / Path(name).name
    if output.exists() and binascii.crc32(output.read_bytes()) == crc:
        data = output.read_bytes()
    else:
        local = struct.unpack("<4s5H3I2H", ranged(local_offset, 30))
        if local[0] != b"PK\x03\x04":
            raise RuntimeError("Invalid local ZIP header")
        print("Fetching", output.name, compressed_size, "bytes", flush=True)
        compressed = ranged(local_offset + 30 + local[9] + local[10], compressed_size)
        data = zlib.decompress(compressed, -15) if method == 8 else compressed
        if len(data) != unpacked_size or binascii.crc32(data) != crc:
            raise RuntimeError("Template CRC or size mismatch")
        temporary = output.with_suffix(output.suffix + ".partial")
        temporary.write_bytes(data)
        temporary.replace(output)
    installed.append({"file": str(output), "bytes": len(data), "crc32": f"{crc:08x}", "sha256": hashlib.sha256(data).hexdigest()})
    print("Verified", output.name, flush=True)
if (target / "version.txt").read_text().strip() != LOCK["template_version"]:
    raise RuntimeError("Template version does not match engine")
(args.evidence / "installed-templates.json").write_text(json.dumps({"engine": LOCK["version"], "url": url, "archive_bytes": size, "templates": installed}, indent=2) + "\n")

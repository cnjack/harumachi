#!/usr/bin/env python3
"""Normalize numeric SCALAR accessor min/max metadata into one-element arrays.

Only those JSON values change. Existing arrays, all other JSON, and every chunk
after JSON (including exact BIN bytes) are preserved. Decoded accessor equality
is verified independently with the existing sparse-aware reader. No rigging,
geometry, animation, normal or image operation is performed.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import struct


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse(data: bytes) -> tuple[dict, bytes]:
    if len(data) < 20:
        raise ValueError("Truncated GLB")
    magic, version, size, json_size, kind = struct.unpack_from("<IIIII", data)
    if (magic, version, size, kind) != (0x46546C67, 2, len(data), 0x4E4F534A):
        raise ValueError("Expected glTF 2 GLB with leading JSON chunk")
    if json_size % 4 or 20 + json_size > len(data):
        raise ValueError("Invalid JSON chunk length")
    return json.loads(data[20:20 + json_size]), data[20 + json_size:]


def normalize_bytes(data: bytes) -> tuple[bytes, dict]:
    original, tail = parse(data)
    document = copy.deepcopy(original)
    changes = []
    for index, accessor in enumerate(document.get("accessors", [])):
        if accessor.get("type") != "SCALAR":
            continue
        for key in ("min", "max"):
            if key not in accessor or isinstance(accessor[key], list):
                continue
            value = accessor[key]
            if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value):
                raise ValueError(f"Nonfinite/nonnumeric SCALAR {key} at accessor {index}")
            accessor[key] = [value]
            changes.append({"path": f"/accessors/{index}/{key}", "accessor": index,
                            "key": key, "before": value, "after": [value]})
    if changes:
        encoded = json.dumps(document, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode()
        encoded += b" " * ((-len(encoded)) % 4)
        result = struct.pack("<IIIII", 0x46546C67, 2, 20 + len(encoded) + len(tail),
                             len(encoded), 0x4E4F534A) + encoded + tail
    else:
        result = data
    decoded, new_tail = parse(result)
    restored = copy.deepcopy(decoded)
    for change in changes:
        restored["accessors"][change["accessor"]][change["key"]] = change["before"]
    if restored != original or new_tail != tail:
        raise AssertionError("Unexpected JSON/chunk mutation")
    report = {"source_sha256": digest(data), "output_sha256": digest(result),
              "changes_count": len(changes), "changes": changes,
              "other_json_semantically_exact": restored == original,
              "all_chunks_after_json_byte_exact": new_tail == tail,
              "tail_sha256": digest(tail), "unchanged_input_byte_exact": not changes and result == data}
    return result, report


def normalize_file(source: Path, output: Path, report_path: Path) -> dict:
    if source.resolve() == output.resolve() or output.exists() or report_path.exists():
        raise ValueError("Use distinct new output/report paths; source is never modified")
    source_bytes = source.read_bytes()
    result, report = normalize_bytes(source_bytes)
    # Import only for the actual decoded-data audit, keeping metadata unit tests
    # available in the ordinary standard-library Python.
    from glb_io import load
    from repair_head_neck import read
    old_doc, old_bin = load(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(result)
    new_doc, new_bin = load(output)
    if old_bin != new_bin:
        raise AssertionError("BIN changed")
    count = len(old_doc.get("accessors", []))
    if len(new_doc.get("accessors", [])) != count:
        raise AssertionError("Accessor count changed")
    values = hashlib.sha256()
    for index in range(count):
        before = read(old_doc, old_bin, index)
        after = read(new_doc, new_bin, index)
        if before.shape != after.shape or before.dtype != after.dtype or before.tobytes() != after.tobytes():
            raise AssertionError("Decoded accessor changed: " + str(index))
        values.update(struct.pack("<Q", index))
        values.update(before.dtype.str.encode() + b"\0")
        values.update(json.dumps(list(before.shape)).encode() + b"\0")
        values.update(before.tobytes())
    if source.read_bytes() != source_bytes:
        raise ValueError("Source changed during normalization/audit")
    report.update(source=str(source.resolve()), output=str(output.resolve()),
                  source_bytes=len(source_bytes), output_bytes=len(result),
                  bin_sha256=digest(old_bin), all_decoded_accessors_bit_exact=True,
                  decoded_accessor_count=count, decoded_accessors_sha256=values.hexdigest(),
                  source_modified=False, tool_sha256=digest(Path(__file__).read_bytes()))
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    report = normalize_file(args.input, args.output, args.report)
    print(json.dumps({key: report[key] for key in ("changes_count", "output_sha256", "decoded_accessor_count",
                                                   "all_decoded_accessors_bit_exact")}))


if __name__ == "__main__":
    main()

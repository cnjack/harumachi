#!/usr/bin/env python3
"""Disable animation key reduction only in an isolated MotionBricks viewer.

Run after the first editor import, then run editor import again. This tool does
not start Godot. Godot Variant dictionaries are patched in place; unrelated
settings retain their exact original text. Only Python's standard library is used.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POC = ROOT / "art/poc/motionbricks_20261018"
SETTINGS = {
    "animation/remove_immutable_tracks": False,
    "_subresources/nodes/PATH:AnimationPlayer/optimizer/enabled": False,
    "_subresources/nodes/PATH:AnimationPlayer/compression/enabled": False,
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def whitespace(text: str, pos: int) -> int:
    while pos < len(text):
        if text[pos].isspace():
            pos += 1
        elif text[pos] in "#;":
            newline = text.find("\n", pos)
            pos = len(text) if newline < 0 else newline + 1
        else:
            break
    return pos


def string_end(text: str, pos: int) -> int:
    if text[pos] != '"':
        raise ValueError("Expected a quoted Godot dictionary key")
    pos += 1
    while pos < len(text):
        if text[pos] == "\\":
            pos += 2
        elif text[pos] == '"':
            return pos + 1
        else:
            pos += 1
    raise ValueError("Unterminated Godot string")


def value_end(text: str, pos: int) -> int:
    """Scan one Variant, including nested constructors/dictionaries/arrays."""
    stack: list[str] = []
    pairs = {"(": ")", "[": "]", "{": "}"}
    while pos < len(text):
        char = text[pos]
        if char == '"':
            pos = string_end(text, pos)
            continue
        if char in "#;":
            pos = whitespace(text, pos)
            continue
        if char in pairs:
            stack.append(pairs[char])
        elif char in ")]}":
            if not stack:
                return pos
            if stack.pop() != char:
                raise ValueError("Mismatched Godot Variant delimiter")
        elif char == "," and not stack:
            return pos
        pos += 1
    if stack:
        raise ValueError("Unterminated Godot Variant")
    return pos


def dictionary(text: str) -> tuple[dict[str, tuple[int, int]], int]:
    start = whitespace(text, 0)
    if start >= len(text) or text[start] != "{":
        raise ValueError("Expected a Godot Dictionary")
    pos = whitespace(text, start + 1)
    entries: dict[str, tuple[int, int]] = {}
    while pos < len(text) and text[pos] != "}":
        end = string_end(text, pos)
        key = json.loads(text[pos:end])
        if key in entries:
            raise ValueError("Duplicate dictionary key: " + key)
        pos = whitespace(text, end)
        if pos >= len(text) or text[pos] != ":":
            raise ValueError("Expected dictionary colon")
        begin = whitespace(text, pos + 1)
        end = value_end(text, begin)
        trimmed = len(text[begin:end].rstrip()) + begin
        if trimmed == begin:
            raise ValueError("Empty Godot Variant value")
        entries[key] = (begin, trimmed)
        pos = whitespace(text, end)
        if pos < len(text) and text[pos] == ",":
            pos = whitespace(text, pos + 1)
        elif pos >= len(text) or text[pos] != "}":
            raise ValueError("Expected dictionary comma or closing brace")
    if pos >= len(text) or text[pos] != "}" or whitespace(text, pos + 1) != len(text):
        raise ValueError("Invalid dictionary boundary")
    return entries, pos


def setting(text: str, keys: tuple[str, ...]) -> str | None:
    entries, _ = dictionary(text)
    if keys[0] not in entries:
        return None
    begin, end = entries[keys[0]]
    value = text[begin:end]
    return setting(value, keys[1:]) if len(keys) > 1 else value


def patch_dictionary(text: str, keys: tuple[str, ...]) -> str:
    entries, close = dictionary(text)
    if keys[0] in entries:
        begin, end = entries[keys[0]]
        value = patch_dictionary(text[begin:end], keys[1:]) if len(keys) > 1 else "false"
        return text[:begin] + value + text[end:]
    value = "false"
    for key in reversed(keys[1:]):
        value = "{" + json.dumps(key) + ": " + value + "}"
    # Retain existing whitespace/comments and an optional trailing comma.
    previous = text[:close].rstrip()
    separator = "" if not entries or previous.endswith(",") else ","
    addition = separator + "\n" + json.dumps(keys[0]) + ": " + value + "\n"
    return text[:close] + addition + text[close:]


def parameter_span(text: str, name: str) -> tuple[int, int] | None:
    section = re.search(r"(?m)^\[params\][ \t]*\r?$", text)
    if section is None:
        raise ValueError("Missing [params] import section")
    section_end = re.search(r"(?m)^\[", text[section.end():])
    stop = section.end() + section_end.start() if section_end else len(text)
    matches = list(re.finditer(r"(?m)^" + re.escape(name) + r"=", text[section.end():stop]))
    if len(matches) > 1:
        raise ValueError("Duplicate import parameter: " + name)
    if not matches:
        return None
    begin = section.end() + matches[0].end()
    if name == "_subresources":
        # The root dictionary ends before the next parameter, not at EOF.
        depth_start = whitespace(text, begin)
        if depth_start >= len(text) or text[depth_start] != "{":
            raise ValueError("_subresources must be a Dictionary")
        cursor = depth_start + 1
        while cursor < len(text):
            cursor = whitespace(text, cursor)
            if cursor >= len(text):
                raise ValueError("Unterminated _subresources")
            if text[cursor] == "}":
                return begin, cursor + 1
            cursor = value_end(text, cursor)
            if cursor < len(text) and text[cursor] == ",":
                cursor += 1
            elif cursor < len(text) and text[cursor] == "}":
                return begin, cursor + 1
            else:
                raise ValueError("Invalid _subresources content")
        raise ValueError("Unterminated _subresources")
    end = text.find("\n", begin, stop)
    end = stop if end < 0 else end
    return begin, len(text[begin:end].rstrip()) + begin


def patch_import(text: str) -> tuple[str, dict]:
    before: dict[str, str | None] = {}
    span = parameter_span(text, "animation/remove_immutable_tracks")
    before["animation/remove_immutable_tracks"] = None if span is None else text[slice(*span)]
    if span is None:
        marker = re.search(r"(?m)^\[params\][ \t]*\r?$", text)
        assert marker is not None
        text = text[:marker.end()] + "\nanimation/remove_immutable_tracks=false" + text[marker.end():]
    else:
        text = text[:span[0]] + "false" + text[span[1]:]
    span = parameter_span(text, "_subresources")
    original = "{}" if span is None else text[slice(*span)]
    modified = original
    for leaf in ["optimizer/enabled", "compression/enabled"]:
        keys = ("nodes", "PATH:AnimationPlayer", leaf)
        before["_subresources/nodes/PATH:AnimationPlayer/" + leaf] = setting(original, keys)
        modified = patch_dictionary(modified, keys)
    if span is None:
        text += ("" if text.endswith("\n") else "\n") + "_subresources=" + modified + "\n"
    else:
        text = text[:span[0]] + modified + text[span[1]:]
    for leaf in ["optimizer/enabled", "compression/enabled"]:
        if setting(modified, ("nodes", "PATH:AnimationPlayer", leaf)) != "false":
            raise ValueError("Dictionary patch verification failed")
    return text, before


def safe_project(path: Path) -> Path:
    path = path.resolve(strict=True)
    temporary = path.name == "godot" and path.parent.name.startswith("harumachi-motionbricks-viewer-")
    poc = POC.resolve() in path.parents
    if not (temporary or poc) or not path.is_dir():
        raise ValueError("Only harumachi-motionbricks-viewer-*/godot or a POC subproject is allowed")
    config = (path / "project.godot").read_text()
    if "HarumachiMotionBricksPOC" not in config or re.search(r"(?m)^\[autoload\]", config):
        raise ValueError("Not an isolated MotionBricks POC project")
    for marker in ["preparation-receipt.json", "showcase.json"]:
        if not (path / marker).is_file():
            raise ValueError("Missing prepared viewer marker: " + marker)
    if (path / "assets").is_symlink():
        raise ValueError("Refuse symlinked assets directory")
    return path


def atomic_write(path: Path, data: bytes) -> None:
    descriptor, name = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
        os.chmod(name, path.stat().st_mode & 0o777)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, help="New immutable JSON receipt; default is inside project")
    args = parser.parse_args()
    project = safe_project(args.project)
    receipt = (args.receipt or project / "import-configuration-receipt.json").resolve()
    if receipt.exists():
        raise ValueError("Choose a new receipt path; existing evidence is immutable")
    if receipt.suffix != ".json" or not receipt.parent.is_dir():
        raise ValueError("Receipt needs an existing parent directory and .json suffix")
    if not (project in receipt.parents or POC.resolve() in receipt.parents or (ROOT / "evidence").resolve() in receipt.parents):
        raise ValueError("Receipt must be inside this viewer, POC, or repository evidence")
    models = sorted((project / "assets").glob("*.glb"))
    if not models:
        raise ValueError("No viewer assets/*.glb files")
    planned = []
    # Validate and compute every edit before mutating any sidecar.
    for model in models:
        sidecar = model.with_suffix(model.suffix + ".import")
        if model.is_symlink() or sidecar.is_symlink() or not sidecar.is_file():
            raise ValueError("Expected regular first-import GLB and sidecar: " + str(sidecar))
        original = sidecar.read_bytes()
        text = original.decode("utf-8")
        changed, before = patch_import(text)
        rewritten, _ = patch_import(changed)
        if rewritten != changed:
            raise ValueError("Import patch is not idempotent")
        planned.append((sidecar, original, changed.encode("utf-8"), model, sha(model.read_bytes()), before))
    rows = []
    for path, original, modified, model, model_sha, before in planned:
        if path.read_bytes() != original:
            raise ValueError("Sidecar changed during configuration: " + str(path))
        if original != modified:
            atomic_write(path, modified)
        if path.read_bytes() != modified or sha(model.read_bytes()) != model_sha:
            raise ValueError("Post-write identity verification failed")
        rows.append({"file": str(path.relative_to(project)), "changed": original != modified,
                     "before_sha256": sha(original), "after_sha256": sha(modified),
                     "before_settings": before, "after_settings": SETTINGS,
                     "before_text": original.decode("utf-8"), "after_text": modified.decode("utf-8"),
                     "glb_sha256_before_and_after": model_sha})
    result = {"schema": 1, "utc": datetime.now(timezone.utc).isoformat(), "project": str(project),
              "script_sha256": sha(Path(__file__).read_bytes()), "files": rows,
              "animation_player_import_id": "PATH:AnimationPlayer",
              "unrelated_field_text_preserved": True, "game_project_written": False,
              "engine_started": False, "needs_second_editor_import": True}
    with receipt.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")
    print(json.dumps({"receipt": str(receipt), "files": len(rows),
                      "changed": sum(row["changed"] for row in rows), "engine_started": False}))


if __name__ == "__main__":
    main()

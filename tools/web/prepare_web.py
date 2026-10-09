#!/usr/bin/env python3
"""Prepare a separate browser project; never rewrite the desktop art or renderer."""
from pathlib import Path
from io import BytesIO
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import shutil
import struct
import subprocess
import re
import argparse
from PIL import Image
from fontTools import subset

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, default=ROOT / "game")
parser.add_argument("--target", type=Path, required=True)
parser.add_argument("--evidence", type=Path, required=True)
args = parser.parse_args()
SOURCE = args.source.resolve()
TARGET = args.target.resolve()
EVIDENCE = args.evidence.resolve()
if TARGET.exists() and any(TARGET.iterdir()):
    raise SystemExit("Use a fresh staging directory; existing staging is preserved: " + str(TARGET))
EVIDENCE.mkdir(parents=True, exist_ok=True)
TARGET.parent.mkdir(parents=True, exist_ok=True)
shutil.copytree(SOURCE, TARGET, dirs_exist_ok=True, ignore=shutil.ignore_patterns(".godot"))


def optimize_glb(path):
    # Buildings retain more painted detail; mesh, skeleton and animation buffers stay exact.
    limit = 1024 if path.stem in {"H01","H02","H03","S01","S02","S03","S05","S06","S08","M01_timber_machiya","M03_gable_house","M05_residential"} or path.stem.startswith("CH_") else 512
    original = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", original)
    assert magic == b"glTF" and version == 2 and length == len(original)
    json_length, json_kind = struct.unpack_from("<I4s", original, 12)
    assert json_kind == b"JSON"
    document = json.loads(original[20:20 + json_length])
    if any(ext in document.get("extensionsUsed", []) for ext in ("KHR_draco_mesh_compression", "EXT_meshopt_compression")):
        return {"file": path.name, "optimized": False}
    binary_at = 20 + json_length
    if binary_at + 8 > len(original):
        return {"file": path.name, "optimized": False}
    binary_length, binary_kind = struct.unpack_from("<I4s", original, binary_at)
    assert binary_kind == b"BIN\x00"
    binary = original[binary_at + 8:binary_at + 8 + binary_length]
    views = document.get("bufferViews", [])
    if any(view.get("buffer", 0) != 0 for view in views):
        return {"file": path.name, "optimized": False}
    chunks = [binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]] for view in views]
    original_chunks = list(chunks)
    image_views = set()
    changed = 0
    for image in document.get("images", []):
        if "bufferView" not in image:
            continue
        index = image["bufferView"]
        image_views.add(index)
        with Image.open(BytesIO(chunks[index])) as bitmap:
            if max(bitmap.size) <= limit:
                continue
            bitmap.thumbnail((limit, limit), Image.Resampling.LANCZOS)
            result = BytesIO()
            if image.get("mimeType") == "image/jpeg":
                bitmap.convert("RGB").save(result, format="JPEG", quality=85, optimize=True)
            else:
                bitmap.save(result, format="PNG", optimize=True)
            chunks[index] = result.getvalue()
            changed += 1
    if not changed:
        return {"file": path.name, "optimized": False, "bytes": len(original)}
    rebuilt = bytearray()
    for index, (view, chunk) in enumerate(zip(views, chunks)):
        rebuilt.extend(b"\x00" * ((-len(rebuilt)) % 4))
        view["byteOffset"] = len(rebuilt)
        view["byteLength"] = len(chunk)
        rebuilt.extend(chunk)
        if index not in image_views:
            assert chunk == original_chunks[index], "Geometry or animation data changed"
    document["buffers"][0]["byteLength"] = len(rebuilt)
    rebuilt.extend(b"\x00" * ((-len(rebuilt)) % 4))
    encoded = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode()
    encoded += b" " * ((-len(encoded)) % 4)
    result = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(encoded) + 8 + len(rebuilt))
    result += struct.pack("<I4s", len(encoded), b"JSON") + encoded
    result += struct.pack("<I4s", len(rebuilt), b"BIN\x00") + rebuilt
    path.write_bytes(result)
    return {"file": path.name, "optimized": True, "old_bytes": len(original), "bytes": len(result), "images": changed, "texture_limit": limit,"geometry_and_animation_unchanged": True}


print("Preparing browser textures and fonts...", flush=True)
with ThreadPoolExecutor(max_workers=4) as pool:
    models = list(pool.map(optimize_glb, sorted((TARGET / "assets/models").glob("*.glb"))))
images = 0
for path in (TARGET / "assets").rglob("*"):
    if path.suffix.lower() not in (".png", ".jpg", ".jpeg"):
        continue
    limit = 1280 if "title" in path.name or "prologue" in path.parts else (512 if "models" in path.parts else 1024)
    with Image.open(path) as bitmap:
        if max(bitmap.size) <= limit:
            continue
        bitmap.thumbnail((limit, limit), Image.Resampling.LANCZOS)
        if path.suffix.lower() in (".jpg", ".jpeg"):
            bitmap.convert("RGB").save(path, quality=88, optimize=True)
        else:
            bitmap.save(path, optimize=True)
        images += 1
for imported in (TARGET / "assets").rglob("*.import"):
    if imported.name.endswith((".png.import", ".jpg.import", ".jpeg.import")):
        settings = imported.read_text()
        settings = re.sub(r"(?m)^compress/mode=\d+$", "compress/mode=1", settings)
        settings = re.sub(r"(?m)^compress/lossy_quality=[\d.]+$", "compress/lossy_quality=0.82", settings)
        imported.write_text(settings)
text = "".join(p.read_text() for p in TARGET.rglob("*") if p.suffix in (".gd", ".json") and ".godot" not in p.parts)
chars = "".join(sorted(set(text) | set(chr(c) for c in range(32, 127))))
options = subset.Options()
options.layout_features = ["*"]
font_path = TARGET / "assets/fonts/LXGWWenKai-Medium.ttf"
font = subset.load_font(str(font_path), options)
subsetter = subset.Subsetter(options)
subsetter.populate(text=chars)
subsetter.subset(font)
subset.save_font(font, str(font_path), options)


# Preserve the authored OGG audio. Only derived textures/fonts are reduced here;
# compressed HTTP delivery reduces transfer size without a second audio encode.
for temporary in (TARGET / "assets/audio").rglob("*.web.ogg"):
    temporary.unlink()
project = TARGET / "project.godot"
config = project.read_text()
engine_lock = json.loads((ROOT / "tools/godot-version.json").read_text())
features = re.search(r'config/features=PackedStringArray\(([^)]*)\)', config)
if features is None or '"' + engine_lock["feature_version"] + '"' not in features.group(1):
    raise SystemExit("Source project version does not match tools/godot-version.json")
config = config.replace('"Forward Plus"', '"GL Compatibility"')
config = config.replace("[rendering]\n", '[rendering]\n\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"\n')
config = config.replace("lights_and_shadows/directional_shadow/size=8192", "lights_and_shadows/directional_shadow/size=2048")
config = config.replace("anti_aliasing/quality/screen_space_aa=1", "anti_aliasing/quality/screen_space_aa=0")
project.write_text(config)
report = {"staging": str(TARGET), "models": models, "standalone_images_resized": images, "font_bytes": font_path.stat().st_size, "assets_bytes": sum(p.stat().st_size for p in (TARGET / "assets").rglob("*") if p.is_file()), "desktop_project_unchanged": True, "authored_audio_preserved": True}
(EVIDENCE / "web-asset-preparation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({k: v for k, v in report.items() if k != "models"}, ensure_ascii=False), flush=True)

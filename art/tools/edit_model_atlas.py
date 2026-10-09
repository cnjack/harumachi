"""Embed an imagegen-edited albedo atlas without changing GLB geometry or UVs.

Only the PNG bytes and the referenced image buffer view change. All node,
accessor, mesh, index, vertex, normal and UV bytes are verified unchanged.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def load(path):
    raw = Path(path).read_bytes()
    magic, version, total = struct.unpack_from("<III", raw)
    if magic != 0x46546C67 or version != 2 or total != len(raw):
        raise ValueError("Invalid GLB header")
    json_len, kind = struct.unpack_from("<II", raw, 12)
    if kind != 0x4E4F534A:
        raise ValueError("Expected JSON chunk")
    model = json.loads(raw[20:20 + json_len])
    offset = 20 + json_len
    bin_len, kind = struct.unpack_from("<II", raw, offset)
    if kind != 0x004E4942:
        raise ValueError("Expected BIN chunk")
    return model, raw[offset + 8:offset + 8 + bin_len]


def signature(model, binary):
    metadata = {key: model.get(key) for key in ("nodes", "meshes", "accessors", "scenes", "scene", "skins", "animations")}
    digest = hashlib.sha256(json.dumps(metadata, sort_keys=True).encode())
    used = {a["bufferView"] for a in model["accessors"] if "bufferView" in a}
    for index in sorted(used):
        view = model["bufferViews"][index]
        start = view.get("byteOffset", 0)
        digest.update(binary[start:start + view["byteLength"]])
    return digest.hexdigest()


def edit(source, atlas, output, material=0):
    model, binary = load(source)
    before = signature(model, binary)
    texture = model["materials"][material]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    image_index = model["textures"][texture]["source"]
    image = Path(atlas).read_bytes()
    if not image.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("Expected a PNG imagegen edit")
    width, height = struct.unpack_from(">II", image, 16)
    padding = b"\x00" * (-len(binary) % 4)
    offset = len(binary) + len(padding)
    binary += padding + image
    model["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(image)})
    model["images"][image_index] = {
        "bufferView": len(model["bufferViews"]) - 1, "mimeType": "image/png",
        "name": Path(atlas).stem,
    }
    model["buffers"][0]["byteLength"] = len(binary)
    binary += b"\x00" * (-len(binary) % 4)
    header = json.dumps(model, ensure_ascii=False, separators=(",", ":")).encode()
    header += b" " * (-len(header) % 4)
    data = struct.pack("<III", 0x46546C67, 2, 28 + len(header) + len(binary))
    data += struct.pack("<II", len(header), 0x4E4F534A) + header
    data += struct.pack("<II", len(binary), 0x004E4942) + binary
    target = Path(output)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    checked, checked_binary = load(target)
    after = signature(checked, checked_binary)
    if before != after:
        raise ValueError("Geometry or UV data changed")
    return {"source": str(source), "atlas": str(atlas), "output": str(output),
            "size": [width, height], "geometry_uv_sha256": after, "geometry_uv_unchanged": True}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("atlas")
    parser.add_argument("output")
    parser.add_argument("--material", type=int, default=0)
    args = parser.parse_args()
    print(json.dumps(edit(args.source, args.atlas, args.output, args.material), ensure_ascii=False, indent=2))

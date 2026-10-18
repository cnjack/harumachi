"""Read embedded glTF 2 binary assets without depending on ignored experiments."""
import json
from pathlib import Path
import struct


def load(path):
    raw = Path(path).read_bytes()
    if len(raw) < 20:
        raise ValueError("Truncated GLB")
    magic, version, length = struct.unpack_from("<III", raw)
    if (magic, version, length) != (0x46546C67, 2, len(raw)):
        raise ValueError("Invalid glTF 2 binary header")
    document = None
    binary = None
    offset = 12
    while offset < length:
        if offset + 8 > length:
            raise ValueError("Truncated GLB chunk header")
        size, kind = struct.unpack_from("<II", raw, offset)
        offset += 8
        if offset + size > length:
            raise ValueError("Truncated GLB chunk")
        chunk = raw[offset:offset + size]
        if kind == 0x4E4F534A:
            if document is not None:
                raise ValueError("Duplicate GLB JSON chunk")
            document = json.loads(chunk)
        elif kind == 0x004E4942:
            if binary is not None:
                raise ValueError("Duplicate GLB binary chunk")
            binary = chunk
        offset += size
    if document is None or binary is None:
        raise ValueError("GLB must contain JSON and embedded binary chunks")
    return document, binary


def durations(path):
    document, binary = load(path)
    result = {}
    for animation in document.get("animations", []):
        end = 0.0
        for sampler in animation["samplers"]:
            accessor = document["accessors"][sampler["input"]]
            if accessor["componentType"] != 5126 or accessor["type"] != "SCALAR":
                raise ValueError("Animation times must be scalar floats")
            view = document["bufferViews"][accessor["bufferView"]]
            start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
            stride = view.get("byteStride", 4)
            end = max(end, max((struct.unpack_from("<f", binary, start + i * stride)[0]
                                for i in range(accessor["count"])), default=0.0))
        result[animation.get("name", "")] = end
    return result

"""Rebuild the existing P02 front skin only beneath its posted notice.

The generated panel has folded paper relief. Clip it at the paper and transition
boundaries, preserving UVs on the retained skin, and replace the inner region
with one planar, joined surface. This edits the support itself; it adds no cover
plate. Unmodified triangle attributes and the encoded image are retained.
"""
from __future__ import annotations

from collections import Counter
from copy import deepcopy
from hashlib import sha256
from pathlib import Path
import json
import math
import struct

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art/library/signage/source/P02_textured_predecessor.glb"
TARGET = ROOT / "art/library/signage/P02.glb"
MANIFEST = ROOT / "art/manifests/noticeboard_mount_20261024.json"
# Godot/glTF metres: x is horizontal, y vertical, z points out of the board.
PAPER = (.07, .65, .77, 1.59)
INNER = (PAPER[0] - .004, PAPER[1] + .004, PAPER[2] - .004, PAPER[3] + .004)
TRANSITION = .02
OUTER = (INNER[0] - TRANSITION, INNER[1] + TRANSITION,
         INNER[2] - TRANSITION, INNER[3] + TRANSITION)
FRONT = .080


def load_glb(path):
    raw = path.read_bytes()
    assert raw[:4] == b"glTF" and struct.unpack_from("<I", raw, 4)[0] == 2
    length = struct.unpack_from("<I", raw, 12)[0]
    return json.loads(raw[20:20 + length]), raw[28 + length:]


def accessor(document, binary, index):
    spec = document["accessors"][index]
    view = document["bufferViews"][spec["bufferView"]]
    channels = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[spec["type"]]
    code = {5123: "H", 5125: "I", 5126: "f"}[spec["componentType"]]
    stride = view.get("byteStride", channels * struct.calcsize(code))
    start = view.get("byteOffset", 0) + spec.get("byteOffset", 0)
    return [struct.unpack_from("<" + code * channels, binary, start + row * stride)
            for row in range(spec["count"])]


def image_bytes(document, binary):
    chunks = []
    for image in document["images"]:
        view = document["bufferViews"][image["bufferView"]]
        begin = view.get("byteOffset", 0)
        chunks.append(binary[begin:begin + view["byteLength"]])
    return chunks


def clip(polygon, axis, edge, less):
    """Clip position, normal and UV together along a vertical plane."""
    if not polygon:
        return []
    result = []
    previous = polygon[-1]
    was_inside = previous[axis] <= edge if less else previous[axis] >= edge
    for vertex in polygon:
        inside = vertex[axis] <= edge if less else vertex[axis] >= edge
        if inside != was_inside:
            ratio = (edge - previous[axis]) / (vertex[axis] - previous[axis])
            result.append(tuple(a + (b - a) * ratio for a, b in zip(previous, vertex)))
        if inside:
            result.append(vertex)
        previous, was_inside = vertex, inside
    return result


def overlap(triangle, bounds):
    return not (max(v[0] for v in triangle) < bounds[0] or min(v[0] for v in triangle) > bounds[1]
                or max(v[1] for v in triangle) < bounds[2] or min(v[1] for v in triangle) > bounds[3])


def inside_polygon(triangle, bounds):
    polygon = list(triangle)
    for axis, edge, less in [(0, bounds[0], False), (0, bounds[1], True),
                            (1, bounds[2], False), (1, bounds[3], True)]:
        polygon = clip(polygon, axis, edge, less)
    return polygon


def flatten(vertex):
    x, y, z, nx, ny, nz, u, v = vertex
    wx = min(1., (x - OUTER[0]) / TRANSITION, (OUTER[1] - x) / TRANSITION)
    wy = min(1., (y - OUTER[2]) / TRANSITION, (OUTER[3] - y) / TRANSITION)
    weight = max(0., min(wx, wy))
    if weight < 1e-10:
        return vertex
    # A continuous narrow bevel ties the flattened front back into its old skin.
    normal = (nx * (1 - weight), ny * (1 - weight), nz * (1 - weight) + weight)
    length = math.sqrt(sum(c * c for c in normal))
    return (x, y, z + (FRONT - z) * weight, *(c / length for c in normal), u, v)


def nondegenerate(triangle):
    a, b, c = triangle
    ab = tuple(b[i] - a[i] for i in range(3))
    ac = tuple(c[i] - a[i] for i in range(3))
    cross = (ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0])
    return sum(value * value for value in cross) > 1e-20


def surface_range(triangles):
    depths = []
    for triangle in triangles:
        if min(vertex[2] for vertex in triangle) <= .045 or not overlap(triangle, PAPER):
            continue
        depths.extend(vertex[2] for vertex in inside_polygon(triangle, PAPER))
    return min(depths), max(depths)


def sample_front(triangles, x, y):
    hits = []
    for a, b, c in triangles:
        det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(det) < 1e-12:
            continue
        u = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / det
        v = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / det
        if min(u, v, 1-u-v) >= -1e-7:
            z = a[2] * u + b[2] * v + c[2] * (1-u-v)
            if z > .045:
                hits.append(z)
    return sorted(set(round(hit, 6) for hit in hits))


def texture_vertex(triangles, x, y):
    """Sample the original visible skin's UVs for the remeshed surface."""
    candidates = []
    for a, b, c in triangles:
        if min(vertex[2] for vertex in (a, b, c)) <= .045:
            continue
        det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(det) < 1e-12:
            continue
        u = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / det
        v = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / det
        if min(u, v, 1-u-v) >= -1e-7:
            candidates.append(tuple(a[index] * u + b[index] * v + c[index] * (1-u-v) for index in range(8)))
    assert candidates, (x, y)
    visible = max(candidates, key=lambda vertex: vertex[2])
    return (x, y, FRONT, 0., 0., 1., *visible[6:])


def write_glb(document, original_images, triangles, target):
    result = deepcopy(document)
    result["bufferViews"], result["accessors"] = [], []
    blob = bytearray()

    def view(payload, kind=None):
        while len(blob) % 4:
            blob.append(0)
        index = len(result["bufferViews"])
        record = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(payload)}
        if kind is not None:
            record["target"] = kind
        result["bufferViews"].append(record)
        blob.extend(payload)
        return index

    vertices, indices, lookup = [], [], {}
    for triangle in triangles:
        for vertex in triangle:
            key = tuple(round(value, 11) for value in vertex)
            if key not in lookup:
                lookup[key] = len(vertices)
                vertices.append(vertex)
            indices.append(lookup[key])
    attributes = {}
    for name, begin, channels in [("POSITION", 0, 3), ("NORMAL", 3, 3), ("TEXCOORD_0", 6, 2)]:
        values = [vertex[begin:begin + channels] for vertex in vertices]
        payload = b"".join(struct.pack("<" + "f" * channels, *value) for value in values)
        attributes[name] = len(result["accessors"])
        record = {"bufferView": view(payload, 34962), "componentType": 5126,
                  "count": len(values), "type": f"VEC{channels}"}
        if name == "POSITION":
            record["min"] = [min(value[axis] for value in values) for axis in range(3)]
            record["max"] = [max(value[axis] for value in values) for axis in range(3)]
        result["accessors"].append(record)
    index_accessor = len(result["accessors"])
    result["accessors"].append({"bufferView": view(struct.pack("<" + "I" * len(indices), *indices), 34963),
                                "componentType": 5125, "count": len(indices), "type": "SCALAR"})
    primitive = result["meshes"][0]["primitives"][0]
    primitive["attributes"], primitive["indices"] = attributes, index_accessor
    for image, encoded in zip(result["images"], original_images):
        image["bufferView"] = view(encoded)
    result["buffers"] = [{"byteLength": len(blob)}]
    while len(blob) % 4:
        blob.append(0)
    encoded_json = json.dumps(result, separators=(",", ":")).encode()
    encoded_json += b" " * (-len(encoded_json) % 4)
    contents = (struct.pack("<4sII", b"glTF", 2, 28 + len(encoded_json) + len(blob))
                + struct.pack("<I4s", len(encoded_json), b"JSON") + encoded_json
                + struct.pack("<I4s", len(blob), b"BIN\0") + blob)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(contents)
    return len(vertices)


def main():
    document, binary = load_glb(SOURCE)
    assert len(document["meshes"]) == 1 and len(document["meshes"][0]["primitives"]) == 1
    assert document["nodes"] == [{"mesh": 0, "name": "P02"}], "Expected the metric, already-levelled P02 source"
    primitive = document["meshes"][0]["primitives"][0]
    arrays = {name: accessor(document, binary, index) for name, index in primitive["attributes"].items()}
    index_list = [row[0] for row in accessor(document, binary, primitive["indices"])]
    vertices = [(*p, *n, *uv) for p, n, uv in zip(arrays["POSITION"], arrays["NORMAL"], arrays["TEXCOORD_0"])]
    before = [tuple(vertices[index_list[offset + corner]] for corner in range(3))
              for offset in range(0, len(index_list), 3)]
    after, unchanged, repaired = [], [], 0
    boundary = {(INNER[x], INNER[y]) for x in [0, 1] for y in [2, 3]}
    replaced_pieces = 0
    for triangle in before:
        if min(vertex[2] for vertex in triangle) <= .045 or not overlap(triangle, OUTER):
            after.append(triangle)
            unchanged.append(triangle)
            continue
        repaired += 1
        pieces = [list(triangle)]
        for axis, edge in [(0, edge) for edge in sorted((*INNER[:2], *OUTER[:2]))] + [(1, edge) for edge in sorted((*INNER[2:], *OUTER[2:]))]:
            next_pieces = []
            for piece in pieces:
                if min(v[axis] for v in piece) < edge < max(v[axis] for v in piece):
                    next_pieces.extend([clip(piece, axis, edge, True), clip(piece, axis, edge, False)])
                else:
                    next_pieces.append(piece)
            pieces = [piece for piece in next_pieces if len(piece) >= 3]
        for piece in pieces:
            if all(INNER[0]-1e-9 <= vertex[0] <= INNER[1]+1e-9 and INNER[2]-1e-9 <= vertex[1] <= INNER[3]+1e-9 for vertex in piece):
                replaced_pieces += 1
                for vertex in piece:
                    if min(abs(vertex[0]-INNER[0]), abs(vertex[0]-INNER[1]), abs(vertex[1]-INNER[2]), abs(vertex[1]-INNER[3])) < 1e-9:
                        boundary.add((round(vertex[0], 10), round(vertex[1], 10)))
                continue
            flattened = [flatten(vertex) for vertex in piece]
            for corner in range(1, len(flattened) - 1):
                new_triangle = (flattened[0], flattened[corner], flattened[corner + 1])
                if nondegenerate(new_triangle):
                    after.append(new_triangle)
    # Connect every cut boundary point to the same interior surface. Reusing
    # the complete boundary avoids gaps; removing the old inner triangles
    # prevents folded poster edges becoming overlapping coplanar geometry.
    center = texture_vertex(before, (INNER[0]+INNER[1])*.5, (INNER[2]+INNER[3])*.5)
    perimeter = sorted(boundary, key=lambda xy: math.atan2(xy[1]-center[1], xy[0]-center[0]))
    rim = [texture_vertex(before, x, y) for x, y in perimeter]
    for index, vertex in enumerate(rim):
        after.append((center, vertex, rim[(index+1) % len(rim)]))
    front_before, front_after = surface_range(before), surface_range(after)
    assert max(abs(z - FRONT) for z in front_after) < 1e-8, front_after
    retained_triangles = Counter(after)
    assert all(retained_triangles[triangle] > 0 for triangle in unchanged)
    histogram = Counter()
    for x in range(17):
        for y in range(17):
            hits = sample_front(after, PAPER[0] + (.017 + x) / 17 * (PAPER[1] - PAPER[0]),
                                PAPER[2] + (.013 + y) / 17 * (PAPER[3] - PAPER[2]))
            assert hits == [FRONT], hits
            histogram[len(hits)] += 1
    images = image_bytes(document, binary)
    vertex_count = write_glb(document, images, after, TARGET)
    written, written_binary = load_glb(TARGET)
    assert image_bytes(written, written_binary) == images
    report = {"asset": "P02", "provider": "Tencent Hunyuan 3.1; local support-surface repair",
              "source": str(SOURCE.relative_to(ROOT)), "source_sha256": sha256(SOURCE.read_bytes()).hexdigest(),
              "authored": str(TARGET.relative_to(ROOT)), "authored_sha256": sha256(TARGET.read_bytes()).hexdigest(),
              "authoring_tool": str(Path(__file__).relative_to(ROOT)),
              "repair": "Existing relief removed only beneath the notice, remeshed into a single planar support with sampled original UVs, and joined to a 20 mm transition. No added cover mesh.",
              "paper_bounds_xy": PAPER, "flat_bounds_xy": INNER, "transition_bounds_xy": OUTER,
              "front_before_m": front_before, "front_after_m": front_after,
              "paper_gap_m": .003, "triangles_before": len(before), "triangles_after": len(after),
              "source_triangles_partitioned": repaired, "unmodified_triangles_preserved_exactly": len(unchanged),
              "relief_pieces_replaced": replaced_pieces, "support_boundary_vertices": len(rim),
              "vertices_after": vertex_count, "front_ray_hits": dict(histogram),
              "original_encoded_images_unchanged": True, "image_sha256": [sha256(image).hexdigest() for image in images],
              "game_export": "game/assets/models/P02.glb", "game_export_options": {
                  "src": "../library/signage/P02.glb", "preserve_parts": True, "preserve_origin": True,
                  "level": False, "tex": 1024, "image_format": "AUTO", "provider": "Hunyuan 3.1 with local planar notice mount"}}
    MANIFEST.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

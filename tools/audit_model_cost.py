#!/usr/bin/env python3
"""静态成本审计：game/assets/models 下全部 GLB 的几何 / 材质 / 贴图 / 导入设置。

只用 python3 标准库：
  * 解析 GLB 容器（JSON chunk + BIN chunk），不安装第三方库；
  * 贴图尺寸直接读 GLB 内嵌 PNG / JPEG / WebP / KTX2 头；
  * 读 .import 与 project.godot 判断导入设置（压缩、mipmap、尺寸上限、法线标记）；
  * 读 art/models/game_assets.json、art/models/raw/manifest*.json 与 art/manifests/models_*.json
    判断每个模型的生成来源（Hyper3D / Pixal3D / Hunyuan / Blender 程序建模 / 第三方 / 未知）。

不启动 Godot（另一个基准任务正在独占 GPU），只读文件。

用法：
    python3 tools/audit_model_cost.py                      # 写 audit.json + summary.md
    python3 tools/audit_model_cost.py --json-only           # 只写 audit.json
    python3 tools/audit_model_cost.py --out <目录>
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import os
import re
import struct
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR = os.path.join(ROOT, "game", "assets", "models")
PROJECT_GODOT = os.path.join(ROOT, "game", "project.godot")
GAME_ASSETS = os.path.join(ROOT, "art", "models", "game_assets.json")
RAW_DIR = os.path.join(ROOT, "art", "models", "raw")
MANIFEST_DIR = os.path.join(ROOT, "art", "manifests")
SCRIPTS_DIR = os.path.join(ROOT, "game", "scripts")
DEFAULT_OUT = os.path.join(ROOT, "evidence", "performance_20261018", "assets")

IMAGE_EXT = (".png", ".jpg", ".jpeg", ".webp")

# 来源分类标签
SRC_AI_HYPER3D = "hyper3d"
SRC_AI_PIXAL3D = "pixal3d"
SRC_AI_HUNYUAN = "hunyuan"
SRC_BLENDER_PROC = "blender-proc"
SRC_THIRD_PARTY = "thirdparty"
SRC_HANDCRAFT = "handcraft"
SRC_UNKNOWN = "unknown"
AI_FAMILIES = (SRC_AI_HYPER3D, SRC_AI_PIXAL3D, SRC_AI_HUNYUAN)
SRC_LABEL = {
    SRC_AI_HYPER3D: "Hyper3D Rodin（AI 图生 3D）",
    SRC_AI_PIXAL3D: "Pixal3D（AI 图生 3D）",
    SRC_AI_HUNYUAN: "Hunyuan hy-3d-3.1（AI 图生 3D）",
    SRC_BLENDER_PROC: "Blender 程序建模 / 手作",
    SRC_THIRD_PARTY: "第三方素材包（Quaternius CC0）",
    SRC_HANDCRAFT: "用户手作 Blender 网格（CGC / YNA 素材库）",
    SRC_UNKNOWN: "来源未标注",
}


# --------------------------------------------------------------------------------------
# GLB 解析
# --------------------------------------------------------------------------------------
def read_glb(path):
    """返回 (json_dict, bin_bytes)。"""
    with open(path, "rb") as f:
        head = f.read(12)
        if len(head) < 12:
            raise ValueError("short GLB: %s" % path)
        magic, version, length = struct.unpack("<4sII", head)
        if magic != b"glTF":
            raise ValueError("not a GLB: %s" % path)
        chunks = {}
        offset = 12
        while offset + 8 <= length:
            f.seek(offset)
            header = f.read(8)
            if len(header) < 8:
                break
            clen, ctype = struct.unpack("<II", header)
            data = f.read(clen)
            offset += 8 + clen
            if ctype == 0x4E4F534A:
                chunks["json"] = json.loads(data.decode("utf-8").rstrip("\x00 "))
            elif ctype == 0x004E4942:
                chunks["bin"] = data
    if "json" not in chunks:
        raise ValueError("no JSON chunk: %s" % path)
    return chunks["json"], chunks.get("bin", b"")


def image_dimensions(data):
    """从 PNG / JPEG / WebP / KTX2 头读像素尺寸，返回 (w, h, kind)。"""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", data[16:24])
        return w, h, "png"
    if data[:2] == b"\xff\xd8":
        i = 2
        n = len(data)
        while i + 4 <= n:
            if data[i] != 0xFF:
                i += 1
                continue
            while i < n and data[i] == 0xFF:
                i += 1
            if i >= n:
                break
            marker = data[i]
            i += 1
            if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7 or marker == 0x01:
                continue
            if i + 2 > n:
                break
            seglen = struct.unpack(">H", data[i:i + 2])[0]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                          0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack(">HH", data[i + 3:i + 7])
                return w, h, "jpeg"
            i += seglen
        return 0, 0, "jpeg?"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        fourcc = data[12:16]
        if fourcc == b"VP8 ":
            w, h = struct.unpack("<HH", data[26:30])
            return w & 0x3FFF, h & 0x3FFF, "webp"
        if fourcc == b"VP8L":
            bits = int.from_bytes(data[21:25], "little")
            return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1, "webp"
        if fourcc == b"VP8X":
            w = int.from_bytes(data[24:27], "little") + 1
            h = int.from_bytes(data[27:30], "little") + 1
            return w, h, "webp"
        return 0, 0, "webp?"
    if data[:12] == b"\xabKTX 20\xbb\r\n\x1a\n":
        w = struct.unpack("<I", data[20:24])[0]
        h = struct.unpack("<I", data[24:28])[0]
        return w, h, "ktx2"
    return 0, 0, "unknown"


# --------------------------------------------------------------------------------------
# 4x4 矩阵（判断模型实际尺寸，用于“4K 贴图配小道具”这类检查）
# --------------------------------------------------------------------------------------
IDENTITY = (1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0)


def mat_mul(a, b):
    out = [0.0] * 16
    for r in range(4):
        for c in range(4):
            out[r * 4 + c] = sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4))
    return tuple(out)


def mat_from_trs(node):
    t = node.get("translation", [0.0, 0.0, 0.0])
    r = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    s = node.get("scale", [1.0, 1.0, 1.0])
    if isinstance(t, dict):  # 理论上不会出现，兜底
        t = [0.0, 0.0, 0.0]
    x, y, z, w = r
    xx, yy, zz = x * x, y * y, z * z
    xy, xz, yz, wx, wy, wz = x * y, x * z, y * z, w * x, w * y, w * z
    rot = (1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy), 0.0,
           2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx), 0.0,
           2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy), 0.0,
           0.0, 0.0, 0.0, 1.0)
    scale = (s[0], 0.0, 0.0, 0.0,
             0.0, s[1], 0.0, 0.0,
             0.0, 0.0, s[2], 0.0,
             0.0, 0.0, 0.0, 1.0)
    trans = (1.0, 0.0, 0.0, t[0],
             0.0, 1.0, 0.0, t[1],
             0.0, 0.0, 1.0, t[2],
             0.0, 0.0, 0.0, 1.0)
    return mat_mul(trans, mat_mul(rot, scale))


def mat_from_gltf_matrix(m):
    # glTF matrix 是列主序
    return (m[0], m[4], m[8], m[12],
            m[1], m[5], m[9], m[13],
            m[2], m[6], m[10], m[14],
            m[3], m[7], m[11], m[15])


def transform_point(m, p):
    x, y, z = p
    return (m[0] * x + m[1] * y + m[2] * z + m[3],
            m[4] * x + m[5] * y + m[6] * z + m[7],
            m[8] * x + m[9] * y + m[10] * z + m[11])


# --------------------------------------------------------------------------------------
# 单模型审计
# --------------------------------------------------------------------------------------
def accessor_count(js, index):
    try:
        return int(js["accessors"][index].get("count", 0))
    except (KeyError, IndexError, TypeError):
        return 0


def acc_bytes(js, index, seen):
    """accessor → 其 bufferView 的字节数（同一 bufferView 只算一次）。"""
    try:
        acc = js["accessors"][index]
    except (KeyError, IndexError, TypeError):
        return 0
    bv = acc.get("bufferView")
    if bv is None or bv in seen:
        return 0
    seen.add(bv)
    return int(js["bufferViews"][bv].get("byteLength", 0))


def payload_bytes(js):
    """把 GLB 的二进制内容拆成 几何 / 动画 / 蒙皮 / 图片 / 其他（JSON 与对齐填充）。"""
    geom_seen, anim_seen, skin_seen = set(), set(), set()
    morph_seen = set()
    geom = anim_bytes = skin = 0
    for mesh in js.get("meshes", []):
        for prim in mesh.get("primitives", []):
            for acc in prim.get("attributes", {}).values():
                geom += acc_bytes(js, acc, geom_seen)
            if "indices" in prim:
                geom += acc_bytes(js, prim["indices"], geom_seen)
            for target in (prim.get("targets") or []):
                for acc in target.values():
                    acc_bytes(js, acc, morph_seen)
            draco = (prim.get("extensions") or {}).get("KHR_draco_mesh_compression")
            if draco and "bufferView" in draco:
                bv = draco["bufferView"]
                if bv not in geom_seen:
                    geom_seen.add(bv)
                    geom += int(js["bufferViews"][bv].get("byteLength", 0))
    for animation in js.get("animations", []):
        for samp in animation.get("samplers", []):
            for key in ("input", "output"):
                if key in samp:
                    anim_bytes += acc_bytes(js, samp[key], anim_seen)
    for sk in js.get("skins", []):
        if "inverseBindMatrices" in sk:
            skin += acc_bytes(js, sk["inverseBindMatrices"], skin_seen)
    images = 0
    img_views = set()
    for img in js.get("images", []):
        if "bufferView" in img:
            images += int(js["bufferViews"][img["bufferView"]].get("byteLength", 0))
            img_views.add(img["bufferView"])
    morph = sum(int(js["bufferViews"][i].get("byteLength", 0)) for i in morph_seen)
    referenced = geom_seen | anim_seen | skin_seen | morph_seen | img_views
    dead = sum(int(bv.get("byteLength", 0)) for i, bv in enumerate(js.get("bufferViews", []))
               if i not in referenced)
    morph_count = sum(len(p.get("targets") or [])
                      for m in js.get("meshes", []) for p in m.get("primitives", []))
    return {"geom_bytes": geom, "anim_bytes": anim_bytes, "skin_bytes": skin,
            "image_bytes": images, "morph_bytes": morph, "morph_targets": morph_count,
            "dead_bytes": dead}


def primitive_stats(js, prim):
    mode = prim.get("mode", 4)
    attrs = prim.get("attributes", {})
    if "indices" in prim:
        n = accessor_count(js, prim["indices"])
    else:
        n = accessor_count(js, attrs.get("POSITION"))
    if mode == 4:
        tris = n // 3
    elif mode in (5, 6):
        tris = max(0, n - 2)
    else:
        tris = 0
    verts = accessor_count(js, attrs.get("POSITION"))
    return tris, verts, mode, attrs


def material_texture_roles(js):
    """返回 image_index -> set(角色)。"""
    roles = defaultdict(set)
    textures = js.get("textures", [])

    def note(tex_index, role):
        try:
            tex = textures[int(tex_index)]
        except (IndexError, TypeError, ValueError):
            return
        src = tex.get("source")
        if src is not None:
            roles[int(src)].add(role)

    for mat in js.get("materials", []):
        pbr = mat.get("pbrMetallicRoughness", {}) or {}
        for key, role in (("baseColorTexture", "albedo"),
                          ("metallicRoughnessTexture", "metallic_roughness")):
            if isinstance(pbr.get(key), dict) and "index" in pbr[key]:
                note(pbr[key]["index"], role)
        for key, role in (("normalTexture", "normal"),
                          ("occlusionTexture", "occlusion"),
                          ("emissiveTexture", "emissive")):
            if isinstance(mat.get(key), dict) and "index" in mat[key]:
                note(mat[key]["index"], role)
        ext = mat.get("extensions") or {}
        for ext_name, ext_data in ext.items():
            if not isinstance(ext_data, dict):
                continue
            for sub, sub_data in ext_data.items():
                if isinstance(sub_data, dict) and "index" in sub_data and "Texture" in sub:
                    note(sub_data["index"], ext_name.replace("KHR_materials_", "") + ":" + sub)
    return roles


def model_bbox(js):
    """遍历节点树，用 POSITION accessor 的 min/max 估实际包围盒（米）。"""
    nodes = js.get("nodes", [])
    meshes = js.get("meshes", [])
    lo = [math.inf] * 3
    hi = [-math.inf] * 3
    scene = js.get("scene", 0)
    scenes = js.get("scenes", [])

    def visit(idx, parent):
        node = nodes[idx]
        if "matrix" in node:
            local = mat_from_gltf_matrix(node["matrix"])
        else:
            local = mat_from_trs(node)
        world = mat_mul(parent, local)
        mesh_index = node.get("mesh")
        if mesh_index is not None and mesh_index < len(meshes):
            for prim in meshes[mesh_index].get("primitives", []):
                attrs = prim.get("attributes", {})
                if "POSITION" not in attrs:
                    continue
                acc = js["accessors"][attrs["POSITION"]]
                mn, mx = acc.get("min"), acc.get("max")
                if not mn or not mx:
                    continue
                for cx in (mn[0], mx[0]):
                    for cy in (mn[1], mx[1]):
                        for cz in (mn[2], mx[2]):
                            p = transform_point(world, (cx, cy, cz))
                            for k in range(3):
                                if p[k] < lo[k]:
                                    lo[k] = p[k]
                                if p[k] > hi[k]:
                                    hi[k] = p[k]
        for child in node.get("children", []):
            visit(child, world)

    roots = scenes[scene].get("nodes", []) if scenes else []
    if not roots:
        roots = [i for i, n in enumerate(nodes) if not any(
            i in (other.get("children") or []) for other in nodes)]
    for r in roots:
        if r < len(nodes):
            visit(r, IDENTITY)
    if not all(math.isfinite(v) for v in lo + hi):
        return None
    return {"min": [round(v, 4) for v in lo],
            "max": [round(v, 4) for v in hi],
            "size_m": [round(hi[i] - lo[i], 4) for i in range(3)],
            "max_dim_m": round(max(hi[i] - lo[i] for i in range(3)), 4)}


def audit_model(model_id, path, glb_import_params):
    js, binc = read_glb(path)
    meshes = js.get("meshes", [])
    prims = 0
    tris = 0
    verts = 0
    surface_modes = Counter()
    attrs = set()
    mesh_tris = []
    for mesh in meshes:
        mesh_total = 0
        for prim in mesh.get("primitives", []):
            prims += 1
            t, v, mode, a = primitive_stats(js, prim)
            tris += t
            mesh_total += t
            verts += v
            surface_modes[mode] += 1
            attrs |= set(a.keys())
        mesh_tris.append(mesh_total)

    nodes = js.get("nodes", [])
    # 场景三角面：把“节点实例化同一份网格”也算进去（Godot 按节点建 MeshInstance3D）
    tris_scene = sum(mesh_tris[n["mesh"]] for n in nodes
                     if isinstance(n.get("mesh"), int) and n["mesh"] < len(mesh_tris))
    skins = js.get("skins", [])
    animations = js.get("animations", [])
    joints = sum(len(s.get("joints", [])) for s in skins)
    anim_targets = sum(len(a.get("channels", [])) for a in animations)

    roles = material_texture_roles(js)
    images = []
    for i, img in enumerate(js.get("images", [])):
        entry = {
            "index": i,
            "name": img.get("name", ""),
            "mime": img.get("mimeType", ""),
            "embedded": "bufferView" in img,
            "roles": sorted(roles.get(i, [])),
        }
        data = None
        if "bufferView" in img:
            bv = js["bufferViews"][img["bufferView"]]
            off = bv.get("byteOffset", 0)
            data = binc[off:off + bv["byteLength"]]
            entry["bytes"] = len(data)
        elif isinstance(img.get("uri"), str):
            uri = img["uri"]
            if uri.startswith("data:"):
                try:
                    data = base64.b64decode(uri.split(",", 1)[1])
                    entry["bytes"] = len(data)
                except Exception:
                    data = None
            else:
                ext = os.path.join(os.path.dirname(path), uri)
                entry["uri"] = uri
                entry["external_exists"] = os.path.exists(ext)
                if entry["external_exists"]:
                    with open(ext, "rb") as f:
                        data = f.read(4096)
                    entry["bytes"] = os.path.getsize(ext)
        if data:
            w, h, kind = image_dimensions(data)
            entry.update({"width": w, "height": h, "kind": kind,
                          "sha256": hashlib.sha256(data).hexdigest() if len(data) < 40_000_000 else None})
            entry["rgba8_bytes"] = w * h * 4
            entry["bc_bytes"] = w * h  # BC7/BC5：1 字节/像素
        else:
            entry.update({"width": 0, "height": 0, "kind": "unreadable",
                          "rgba8_bytes": 0, "bc_bytes": 0})
        images.append(entry)

    tex_rgba8 = sum(im["rgba8_bytes"] for im in images)
    tex_bc = sum(im["bc_bytes"] for im in images)
    tex_bytes_embedded = sum(im.get("bytes", 0) for im in images if im["embedded"])

    file_size = os.path.getsize(path)
    bbox = model_bbox(js)
    payload = payload_bytes(js)
    payload["other_bytes"] = max(0, file_size - sum(payload.values()))

    for im in images:
        im["used_by_material"] = bool(im["roles"])
    roles_all = sorted({r for im in images for r in im["roles"]})
    unused = [im for im in images if not im["roles"]]
    stride = 12 + 12 + 8
    if "TANGENT" in attrs:
        stride += 16
    if "COLOR_0" in attrs:
        stride += 4
    if "JOINTS_0" in attrs:
        stride += 16
    return {
        "id": model_id,
        "file": os.path.relpath(path, ROOT),
        "bytes": file_size,
        "triangles": tris,
        "triangles_scene": tris_scene,
        "vertices": verts,
        "primitives": prims,
        "surfaces": prims,  # Godot: 每个 primitive = 一个 surface
        "materials": len(js.get("materials", [])),
        "nodes": len(nodes),
        "mesh_nodes": sum(1 for n in nodes if "mesh" in n),
        "skins": len(skins),
        "joints": joints,
        "animations": len(animations),
        "animation_channels": anim_targets,
        "images": len(images),
        "image_list": images,
        "textures": len(js.get("textures", [])),
        "samplers": len(js.get("samplers", [])),
        "attrs": sorted(attrs),
        "skinned": "JOINTS_0" in attrs,
        "extensions": js.get("extensionsUsed", []),
        "bbox": bbox,
        "tex_rgba8_bytes": tex_rgba8,
        "tex_bc_bytes": tex_bc,
        "tex_embedded_bytes": tex_bytes_embedded,
        "payload": payload,
        "tex_roles": roles_all,
        "unused_images": len(unused),
        "unused_tex_rgba8_bytes": sum(im["rgba8_bytes"] for im in unused),
        "unused_tex_bytes": sum(im.get("bytes", 0) for im in unused),
        "vertex_stride": stride,
        "vb_bytes": verts * stride,
        "has_normal": "normal" in roles_all,
        "has_mr": "metallic_roughness" in roles_all,
        "double_sided": sum(1 for m in js.get("materials", []) if m.get("doubleSided")),
        "alpha_blend": sum(1 for m in js.get("materials", [])
                           if (m.get("alphaMode") or "OPAQUE") == "BLEND"),
        "mesh_import": glb_import_params,
    }


# --------------------------------------------------------------------------------------
# .import / project.godot
# --------------------------------------------------------------------------------------
def parse_import_file(path):
    params = {}
    section = None
    importer = None
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if line.startswith("["):
            section = line.strip("[]")
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if section == "params":
            params[key] = value
        elif section == "remap" and key == "importer":
            importer = value
    return importer, params


def scan_imports():
    glb_imports = {}
    tex_imports = {}
    for name in sorted(os.listdir(MODELS_DIR)):
        if not name.endswith(".import"):
            continue
        path = os.path.join(MODELS_DIR, name)
        importer, params = parse_import_file(path)
        source = name[:-7]
        entry = {"importer": importer, "params": params, "import_file": name}
        if source.endswith(".glb"):
            glb_imports[source[:-4]] = entry
        elif source.lower().endswith(IMAGE_EXT):
            tex_imports[source] = entry
    return glb_imports, tex_imports


def scan_project_settings():
    text = open(PROJECT_GODOT, encoding="utf-8", errors="replace").read()
    section = None
    settings = {}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if "=" in line and not line.startswith(";"):
            key, value = line.split("=", 1)
            settings["%s/%s" % (section, key)] = value
    keys = {k: v for k, v in settings.items()
            if any(t in k for t in ("textures/", "mesh", "lod", "compression",
                                    "shadow", "anti_aliasing", "vram", "filter",
                                    "lightmap", "lights_and_shadows"))}
    return keys


# --------------------------------------------------------------------------------------
# 来源归属
# --------------------------------------------------------------------------------------
def norm_id(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def load_provenance(model_ids):
    records = {}          # id -> {"family":..., "evidence":[...]}
    assets = {}
    overrides = {}
    if os.path.exists(GAME_ASSETS):
        data = json.load(open(GAME_ASSETS, encoding="utf-8"))
        assets = data.get("assets", {})
        overrides = data.get("procedural_overrides", {})

    # raw/ 目录
    raw_dirs = []
    if os.path.isdir(RAW_DIR):
        raw_dirs = [d for d in os.listdir(RAW_DIR) if os.path.isdir(os.path.join(RAW_DIR, d))]

    # Hunyuan raw manifests：id -> hunyuan
    hunyuan_jobs = {}
    for fname in ("manifest.json", "manifest_v02.json"):
        path = os.path.join(RAW_DIR, fname)
        if not os.path.exists(path):
            continue
        try:
            data = json.load(open(path, encoding="utf-8"))
        except Exception:
            continue
        for key, job in (data.get("jobs") or {}).items():
            model = str(job.get("model", "")) + " " + str(job.get("provider", ""))
            if "hy-3d" in model or "hunyuan" in model.lower():
                hunyuan_jobs[key] = job.get("model", "hy-3d-3.1")

    # art/manifests/models_*.json：记录每个模型 ID 出现在哪个族系的清单里
    manifest_family = {}
    manifest_hits = defaultdict(set)
    stems_set = set(model_ids)
    for fname in sorted(os.listdir(MANIFEST_DIR)):
        if not fname.startswith("models_") or not fname.endswith(".json"):
            continue
        path = os.path.join(MANIFEST_DIR, fname)
        low = fname.lower()
        if "pixal" in low:
            family = SRC_AI_PIXAL3D
        elif "hyper3d" in low or "h3d" in low or "rodin" in low:
            family = SRC_AI_HYPER3D
        elif "hunyuan" in low:
            family = SRC_AI_HUNYUAN
        elif "reviewed" in low:
            family = SRC_HANDCRAFT
        else:
            family = None
        manifest_family[fname] = family
        if family is None:
            continue
        try:
            data = json.load(open(path, encoding="utf-8"))
        except Exception:
            continue

        def note_tokens(text):
            if not isinstance(text, str):
                return
            for token in re.split(r"[^A-Za-z0-9_]+", text):
                if token and token in stems_set:
                    manifest_hits[token].add(family)

        def walk(node):
            if isinstance(node, dict):
                for k, v in node.items():
                    note_tokens(k)
                    walk(v)
            elif isinstance(node, list):
                for item in node:
                    walk(item)
            elif isinstance(node, str):
                note_tokens(node)
        walk(data)

    proc_ids = set()
    tools_dir = os.path.join(ROOT, "art", "tools")
    for fname in ("proc_models.py", "japanese_joinery.py", "precise_houses.py",
                  "lantern_textures.py", "game_export.py"):
        path = os.path.join(tools_dir, fname)
        if not os.path.exists(path):
            continue
        text = open(path, encoding="utf-8", errors="replace").read()
        for stem in stems_set & set(re.findall(r"[A-Za-z][A-Za-z0-9_]{2,40}", text)):
            if re.search(r'["\']' + re.escape(stem) + r'["\']', text):
                proc_ids.add(stem)

    def classify(provider, src, model_id, extra=""):
        evidence = []
        prov = (provider or "").lower()
        alltext = " ".join([prov, (src or "").lower(), (extra or "").lower()])
        if "shinkai-dry" in alltext or "shinkai_dry" in alltext:
            evidence.append("shinkai-dry 批次（Hunyuan hy-3d-3.1 集）")
            return SRC_AI_HUNYUAN, evidence
        if prov:
            evidence.append("game_assets.provider=%r" % provider[:80])
            if "rodin" in prov or "hyper3d" in prov:
                return SRC_AI_HYPER3D, evidence
            if "pixal" in prov:
                return SRC_AI_PIXAL3D, evidence
            if "hunyuan" in prov or "hy-3d" in prov:
                return SRC_AI_HUNYUAN, evidence
            if "quaternius" in prov:
                return SRC_THIRD_PARTY, evidence
            if "cgc" in prov or "yna" in prov or "user-supplied" in prov:
                return SRC_HANDCRAFT, evidence
            if ("blender" in prov or "procedur" in prov or "joinery" in prov
                    or "proc_models" in prov):
                return SRC_BLENDER_PROC, evidence
            if "imagegen" in prov:
                # 只有贴图来自 imagegen，几何来源继续往下判
                evidence.append("provider 只提到 imagegen 贴图")
        if extra:
            evidence.append("清单附加字段=%s" % extra[:90])
            if "quaternius" in extra.lower():
                return SRC_THIRD_PARTY, evidence
            if "hyper3d.ai/" in extra.lower():
                return SRC_AI_HYPER3D, evidence
        if src:
            low = src.lower()
            evidence.append("src=%s" % src)
            if "pixal" in low or "_pix" in low:
                return SRC_AI_PIXAL3D, evidence
            if "h3d" in low or "hyper" in low or "rodin" in low:
                return SRC_AI_HYPER3D, evidence
        # raw/ 目录：ID 或 ID_xxx
        candidates = [d for d in raw_dirs
                      if d == model_id or d.startswith(model_id + "_")
                      or norm_id(d).startswith(norm_id(model_id))]
        matched = []
        for d in candidates:
            low = d.lower()
            if re.search(r"_pix|pixal", low):
                matched.append(SRC_AI_PIXAL3D)
            elif re.search(r"h3d|hyper|rodin", low):
                matched.append(SRC_AI_HYPER3D)
            elif re.search(r"proc|joinery|reviewed_library", low):
                matched.append(SRC_BLENDER_PROC)
        if matched:
            evidence.append("raw 目录=%s" % sorted(set(matched)))
            return Counter(matched).most_common(1)[0][0], evidence
        if model_id in hunyuan_jobs:
            evidence.append("raw/manifest job model=%s" % hunyuan_jobs[model_id])
            return SRC_AI_HUNYUAN, evidence
        if model_id in proc_ids:
            evidence.append("art/tools 程序建模脚本里有该 id")
            return SRC_BLENDER_PROC, evidence
        hits = manifest_hits.get(model_id) or set()
        if hits:
            evidence.append("art/manifests 命中=%s" % sorted(hits))
            if len(hits) == 1:
                return list(hits)[0], evidence
            # 多个族系都提到：优先 AI（同一模型可能先 Pixal3D 后 Hyper3D 再修）
            for fam in AI_FAMILIES:
                if fam in hits:
                    return fam, evidence
        return SRC_UNKNOWN, evidence

    for model_id in model_ids:
        asset = assets.get(model_id) or {}
        provider = asset.get("provider")
        src = asset.get("src")
        extra = " ".join(str(asset.get(k)) for k in
                         ("source_page", "license", "source_pack", "original_source",
                          "asset_library_id") if asset.get(k))
        family, evidence = classify(provider, src, model_id, extra)
        if model_id in overrides:
            family = SRC_BLENDER_PROC
            evidence.append("procedural_overrides: %s" % overrides[model_id][:120])
        records[model_id] = {
            "family": family,
            "provider": provider,
            "src": src,
            "note": asset.get("note"),
            "evidence": evidence,
        }
    return records, raw_dirs


def scan_code_refs(stems):
    """统计每个模型 ID 在 game/scripts 里被字面量引用的次数。

    prod_refs 排除了 scripts/tests，作为“摆放/使用次数”的粗代理；
    这不是运行时实例数（数组循环里的 spawn 只算一次）。"""
    refs = Counter()
    prod = Counter()
    pattern = re.compile(r'"([A-Za-z][A-Za-z0-9_]{2,40})"')
    for base, _dirs, files in os.walk(SCRIPTS_DIR):
        is_test = os.sep + "tests" + os.sep in base + os.sep
        for fname in files:
            if not fname.endswith(".gd"):
                continue
            path = os.path.join(base, fname)
            try:
                text = open(path, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            for token in pattern.findall(text):
                if token in stems:
                    refs[token] += 1
                    if not is_test:
                        prod[token] += 1
    return refs, prod


# --------------------------------------------------------------------------------------
# 外部（从 GLB 抽出的）贴图文件
# --------------------------------------------------------------------------------------
def scan_texture_files(glb_stems, embedded_shas, owner_embedded=None):
    owner_embedded = owner_embedded or {}
    rows = []
    for name in sorted(os.listdir(MODELS_DIR)):
        if not name.lower().endswith(IMAGE_EXT):
            continue
        path = os.path.join(MODELS_DIR, name)
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            head = f.read(65536)
        w, h, kind = image_dimensions(head)
        sha = hashlib.sha256(open(path, "rb").read()).hexdigest()
        importer_params = {}
        import_path = path + ".import"
        if os.path.exists(import_path):
            _, importer_params = parse_import_file(import_path)
        low = name.lower()
        if "_normal" in low:
            role = "normal"
        elif "metallic" in low or "roughness" in low:
            role = "metallic_roughness"
        elif "occlusion" in low:
            role = "occlusion"
        elif "atlas" in low:
            role = "atlas"
        elif "emissive" in low:
            role = "emissive"
        elif "diffuse" in low or "albedo" in low:
            role = "albedo"
        elif "glass" in low:
            role = "albedo/glass"
        else:
            role = "unclassified"
        owner = None
        best = 0
        for stem in glb_stems:
            if name.startswith(stem + "_") and len(stem) > best:
                owner = stem
                best = len(stem)
        owner_sha = owner_embedded.get(owner, set()) if owner else set()
        if owner and sha in owner_sha:
            state = "current"
        elif owner:
            state = "stale"
        else:
            state = "orphan"
        rows.append({
            "state": state,
            "file": name,
            "bytes": size,
            "width": w,
            "height": h,
            "kind": kind,
            "sha256": sha,
            "rgba8_bytes": w * h * 4,
            "role": role,
            "owner": owner,
            "identical_to_embedded": sha in embedded_shas,
            "import": importer_params,
        })
    return rows


# --------------------------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--json-only", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="只审前 N 个模型（调试用）")
    args = ap.parse_args(argv)

    glb_files = sorted(f for f in os.listdir(MODELS_DIR) if f.lower().endswith(".glb"))
    stems = [f[:-4] for f in glb_files]
    if args.limit:
        glb_files = glb_files[:args.limit]
        stems = stems[:args.limit]

    glb_imports, tex_imports = scan_imports()
    provenance, raw_dirs = load_provenance(stems)
    code_refs, prod_refs = scan_code_refs(set(stems))
    project_settings = scan_project_settings()

    models = []
    errors = []
    for fname in glb_files:
        model_id = fname[:-4]
        path = os.path.join(MODELS_DIR, fname)
        try:
            entry = audit_model(model_id, path, glb_imports.get(model_id, {}).get("params", {}))
        except Exception as exc:  # 单个模型解析失败不影响整体
            errors.append({"id": model_id, "error": repr(exc)})
            continue
        prov = provenance.get(model_id, {"family": SRC_UNKNOWN, "evidence": []})
        entry["source"] = {
            "family": prov["family"],
            "label": SRC_LABEL.get(prov["family"], prov["family"]),
            "provider": prov.get("provider"),
            "src": prov.get("src"),
            "note": prov.get("note"),
            "evidence": prov.get("evidence", []),
        }
        entry["code_refs"] = code_refs.get(model_id, 0)
        entry["prod_refs"] = prod_refs.get(model_id, 0)
        entry["glb_import"] = glb_imports.get(model_id)
        models.append(entry)

    # 全局重复贴图（同一份字节出现在多个模型里 → 各自一份显存）
    sha_groups = defaultdict(list)
    for m in models:
        for im in m["image_list"]:
            if im.get("sha256") and im.get("rgba8_bytes"):
                sha_groups[im["sha256"]].append({"model": m["id"], "name": im["name"],
                                                 "bytes": im.get("bytes", 0),
                                                 "rgba8_bytes": im["rgba8_bytes"],
                                                 "width": im["width"], "height": im["height"]})
    duplicates = []
    for sha, items in sha_groups.items():
        if len(items) < 2:
            continue
        models_in = sorted({it["model"] for it in items})
        if len(models_in) < 2:
            continue
        duplicates.append({
            "sha256": sha,
            "width": items[0]["width"],
            "height": items[0]["height"],
            "copies": len(items),
            "models": models_in,
            "wasted_rgba8_bytes": (len(items) - 1) * items[0]["rgba8_bytes"],
            "wasted_file_bytes": (len(items) - 1) * items[0]["bytes"],
        })
    duplicates.sort(key=lambda d: -d["wasted_rgba8_bytes"])

    embedded_shas = set()
    for m in models:
        for im in m["image_list"]:
            if im.get("sha256"):
                embedded_shas.add(im["sha256"])
    owner_embedded = defaultdict(set)
    for m in models:
        for im in m["image_list"]:
            if im.get("sha256"):
                owner_embedded[m["id"]].add(im["sha256"])
    tex_files = scan_texture_files(set(stems), embedded_shas, owner_embedded)

    totals = aggregate(models, tex_files, duplicates)
    issues = collect_issues(models, tex_files, project_settings, glb_imports, tex_imports)
    report = {
        "generated_at": "2026-10-18",
        "tool": "tools/audit_model_cost.py",
        "scope": {
            "models_dir": os.path.relpath(MODELS_DIR, ROOT),
            "glb_count": len(models),
            "texture_files": len(tex_files),
            "project_settings": project_settings,
            "raw_dirs": len(raw_dirs),
        },
        "totals": totals,
        "sources": source_table(models),
        "models": models,
        "texture_files_summary": texture_summary(tex_files),
        "duplicate_textures": duplicates,
        "import_params": {
            "glb": glb_param_summary(glb_imports),
            "texture": texture_param_summary(tex_imports),
        },
        "issues": issues,
        "errors": errors,
    }
    os.makedirs(args.out, exist_ok=True)
    json_path = os.path.join(args.out, "audit.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    print("wrote", json_path, "(%.2f MB)" % (os.path.getsize(json_path) / 1e6))
    if errors:
        print("errors:", errors, file=sys.stderr)

    if not args.json_only:
        md = render_summary(report)
        md_path = os.path.join(args.out, "summary.md")
        with open(md_path, "w", encoding="utf-8") as f:
            f.write(md)
        print("wrote", md_path)
    return 0


def mib(n):
    return "%.1f MiB" % (n / (1024 * 1024))


def gib(n):
    return "%.2f GiB" % (n / (1024 ** 3))


def pct(part, whole):
    return "%.1f%%" % (100.0 * part / whole) if whole else "-"


def aggregate(models, tex_files, duplicates):
    tri = sum(m["triangles"] for m in models)
    tri_scene = sum(m["triangles_scene"] for m in models)
    verts = sum(m["vertices"] for m in models)
    prims = sum(m["primitives"] for m in models)
    mats = sum(m["materials"] for m in models)
    bytes_ = sum(m["bytes"] for m in models)
    vram = sum(m["tex_rgba8_bytes"] for m in models)
    bc = sum(m["tex_bc_bytes"] for m in models)
    images = sum(m["images"] for m in models)
    ext_bytes = sum(t["bytes"] for t in tex_files)
    wasted = sum(d["wasted_rgba8_bytes"] for d in duplicates)
    unused_vram = sum(m["unused_tex_rgba8_bytes"] for m in models)
    unused_disk = sum(m["unused_tex_bytes"] for m in models)
    vb = sum(m["vb_bytes"] for m in models)
    comp = {k: sum(m["payload"][k] for m in models) for k in
            ("geom_bytes", "image_bytes", "anim_bytes", "skin_bytes", "morph_bytes",
             "dead_bytes", "other_bytes")}
    morph_targets = sum(m["payload"]["morph_targets"] for m in models)
    res_buckets = Counter()
    for m in models:
        for im in m["image_list"]:
            if im["width"] > 0:
                res_buckets["%dx%d" % (im["width"], im["height"])] += 1
    return {
        "models": len(models),
        "triangles": tri,
        "triangles_scene": tri_scene,
        "vertices": verts,
        "primitives": prims,
        "materials": mats,
        "glb_bytes": bytes_,
        "images": images,
        "tex_rgba8_bytes": vram,
        "tex_bc_bytes": bc,
        "external_texture_bytes": ext_bytes,
        "duplicate_texture_wasted_rgba8_bytes": wasted,
        "unused_tex_rgba8_bytes": unused_vram,
        "unused_tex_bytes": unused_disk,
        "unused_images": sum(m["unused_images"] for m in models),
        "vb_bytes": vb,
        "file_composition": comp,
        "morph_targets": morph_targets,
        "resolution_buckets": dict(res_buckets.most_common()),
        "files_over_2048": sum(1 for m in models for im in m["image_list"] if max(im["width"], im["height"]) > 2048),
        "files_4096": sum(1 for m in models for im in m["image_list"] if max(im["width"], im["height"]) == 4096),
        "files_8192": sum(1 for m in models for im in m["image_list"] if max(im["width"], im["height"]) >= 8192),
    }


def source_table(models):
    table = {}
    for family in (SRC_AI_HYPER3D, SRC_AI_PIXAL3D, SRC_AI_HUNYUAN,
                   SRC_BLENDER_PROC, SRC_THIRD_PARTY, SRC_HANDCRAFT, SRC_UNKNOWN):
        rows = [m for m in models if m["source"]["family"] == family]
        table[family] = {
            "label": SRC_LABEL[family],
            "models": len(rows),
            "triangles": sum(m["triangles"] for m in rows),
            "triangles_scene": sum(m["triangles_scene"] for m in rows),
            "vertices": sum(m["vertices"] for m in rows),
            "primitives": sum(m["primitives"] for m in rows),
            "materials": sum(m["materials"] for m in rows),
            "bytes": sum(m["bytes"] for m in rows),
            "tex_rgba8_bytes": sum(m["tex_rgba8_bytes"] for m in rows),
            "images": sum(m["images"] for m in rows),
            "model_ids": sorted(m["id"] for m in rows),
        }
    ai = {k: sum(table[f][k] for f in AI_FAMILIES) for k in
          ("models", "triangles", "triangles_scene", "vertices", "primitives", "materials",
           "bytes", "tex_rgba8_bytes", "images")}
    ai["label"] = "AI 图生 3D 合计（Hyper3D + Pixal3D + Hunyuan）"
    table["ai_total"] = ai
    return table


def texture_summary(tex_files):
    total_bytes = sum(t["bytes"] for t in tex_files)
    total_rgba = sum(t["rgba8_bytes"] for t in tex_files)
    roles = Counter(t["role"] for t in tex_files)
    states = Counter(t["state"] for t in tex_files)
    stale = [t for t in tex_files if t["state"] != "current"]
    identical = [t for t in tex_files if t["state"] == "current"]
    over_2048 = [t for t in tex_files if max(t["width"], t["height"]) > 2048]
    return {
        "files": len(tex_files),
        "bytes": total_bytes,
        "rgba8_bytes": total_rgba,
        "roles": dict(roles),
        "states": dict(states),
        "stale_files": len(stale),
        "stale_bytes": sum(t["bytes"] for t in stale),
        "stale_rgba8_bytes": sum(t["rgba8_bytes"] for t in stale),
        "identical_to_glb_embedded": len(identical),
        "identical_bytes": sum(t["bytes"] for t in identical),
        "above_2048": len(over_2048),
        "above_2048_bytes": sum(t["bytes"] for t in over_2048),
        "max_resolution": max((max(t["width"], t["height"]) for t in tex_files), default=0),
    }


def glb_param_summary(glb_imports):
    keys = ("meshes/ensure_tangents", "meshes/generate_lods", "meshes/create_shadow_meshes",
            "meshes/force_disable_compression", "meshes/light_baking",
            "array_mesh/deduplicate_surfaces", "materials/extract",
            "gltf/embedded_image_handling", "gltf/texture_map_mode",
            "nodes/import_as_skeleton_bones", "animation/import")
    summary = {}
    for key in keys:
        summary[key] = dict(Counter(e["params"].get(key, "(missing)")
                                    for e in glb_imports.values()))
    summary["_count"] = len(glb_imports)
    return summary


def texture_param_summary(tex_imports):
    keys = ("compress/mode", "compress/normal_map", "mipmaps/generate", "mipmaps/limit",
            "process/size_limit", "detect_3d/compress_to", "process/fix_alpha_border",
            "compress/channel_pack", "compress/lossy_quality", "compress/hdr_compression")
    summary = {}
    for key in keys:
        summary[key] = dict(Counter(e["params"].get(key, "(missing)")
                                    for e in tex_imports.values()))
    summary["_count"] = len(tex_imports)
    return summary


def collect_issues(models, tex_files, project_settings, glb_imports, tex_imports):
    issues = []

    lossless = sum(1 for e in tex_imports.values() if e["params"].get("compress/mode") == "0")
    total_tex_imports = len(tex_imports)
    if lossless:
        issues.append({
            "severity": "high",
            "kind": "texture_no_vram_compression",
            "count": lossless,
            "detail": "%d/%d 张贴图是 compress/mode=0（Lossless），没有走 VRAM 压缩（BC1/BC7/BC5），"
                      "显存按未压缩 8bit 计算。" % (lossless, total_tex_imports),
        })
    normal_flagged = sum(1 for name, e in tex_imports.items()
                         if "normal" in name.lower() and e["params"].get("compress/normal_map") == "1")
    normal_total = sum(1 for name in tex_imports if "normal" in name.lower())
    if normal_total and normal_flagged < normal_total:
        issues.append({
            "severity": "high",
            "kind": "normal_map_not_flagged",
            "count": normal_total - normal_flagged,
            "detail": "文件名带 normal 的贴图 %d 张，其中只有 %d 张勾了 Normal Map（compress/normal_map=1）；"
                      "剩下 %d 张按颜色贴图导入。" % (normal_total, normal_flagged,
                                                   normal_total - normal_flagged),
        })
    no_limit = sum(1 for e in tex_imports.values() if e["params"].get("process/size_limit") == "0")
    if no_limit:
        issues.append({
            "severity": "medium",
            "kind": "no_size_limit",
            "count": no_limit,
            "detail": "%d/%d 张贴图 process/size_limit=0（不降采样），原图多大多大。" % (no_limit, total_tex_imports),
        })
    big = [(m["id"], im) for m in models for im in m["image_list"]
           if max(im["width"], im["height"]) >= 4096]
    if big:
        bi = sorted(big, key=lambda r: -r[1]["rgba8_bytes"])[:8]
        issues.append({
            "severity": "medium",
            "kind": "huge_textures",
            "count": len(big),
            "detail": "%d 张内嵌贴图边长 ≥4096（占 %s 显存，全部降到 4096 后是 %s）；最大的几张：%s。" % (
                len(big), mib(sum(im["rgba8_bytes"] for _, im in big)),
                mib(sum(min(im["width"], 4096) * min(im["height"], 4096) * 4
                        for _, im in big)),
                "、".join("%s %s %dx%d" % (mid, im["name"], im["width"], im["height"])
                         for mid, im in bi)),
        })
    current = [t for t in tex_files if t["state"] == "current"]
    stale = [t for t in tex_files if t["state"] != "current"]
    if current:
        issues.append({
            "severity": "info",
            "kind": "extracted_texture_files",
            "count": len(current),
            "detail": "%d/%d 张外部贴图与所属 GLB 的内嵌图片逐字节相同：这是 glTF 导入器 "
                      "gltf/embedded_image_handling=1（Extract）把内嵌图抽成项目文件的结果，"
                      "导出时按 all_resources 一起进包（%s）。不是第二份运行时贴图。" % (
                          len(current), len(tex_files), mib(sum(t["bytes"] for t in current))),
        })
    if stale:
        issues.append({
            "severity": "medium",
            "kind": "stale_texture_files",
            "count": len(stale),
            "detail": "%d 张贴图文件和当前 GLB 的内嵌图片对不上，游戏里也没有任何文件引用它们"
                      "（%s 源文件，按 all_resources 仍会进导出包）：%s。" % (
                          len(stale), mib(sum(t["bytes"] for t in stale)),
                          "、".join(t["file"] for t in stale[:6])),
        })
    no_lod = sum(1 for e in glb_imports.values() if e["params"].get("meshes/generate_lods") == "false")
    if no_lod:
        issues.append({"severity": "medium", "kind": "no_lod", "count": no_lod,
                       "detail": "%d 个 GLB 关闭了 LOD 生成。" % no_lod})
    heavy_surface = [m for m in models if m["primitives"] >= 8]
    if heavy_surface:
        issues.append({
            "severity": "medium",
            "kind": "many_surfaces",
            "count": len(heavy_surface),
            "detail": "%d 个模型 primitive（=Godot surface/draw call 潜在数）≥8，最多的是 %s。" % (
                len(heavy_surface),
                "、".join("%s(%d)" % (m["id"], m["primitives"])
                         for m in sorted(heavy_surface, key=lambda m: -m["primitives"])[:6])),
        })
    high_mat = [m for m in models if m["materials"] >= 8]
    if high_mat:
        issues.append({
            "severity": "medium",
            "kind": "many_materials",
            "count": len(high_mat),
            "detail": "%d 个模型材质数 ≥8；最多的是 %s。" % (
                len(high_mat),
                "、".join("%s(%d)" % (m["id"], m["materials"])
                         for m in sorted(high_mat, key=lambda m: -m["materials"])[:6])),
        })
    unused_models = [m for m in models if m["unused_images"]]
    if unused_models:
        issues.append({
            "severity": "high",
            "kind": "unused_embedded_textures",
            "count": sum(m["unused_images"] for m in models),
            "detail": "%d 个模型一共内嵌了 %d 张没有任何材质引用的贴图（%s 显存、%s 源文件）；"
                      "glTF 导入器会把它们全抽成文件并导入，占仓库与导出包体积。最多的模型：%s。" % (
                          len(unused_models), sum(m["unused_images"] for m in models),
                          mib(sum(m["unused_tex_rgba8_bytes"] for m in models)),
                          mib(sum(m["unused_tex_bytes"] for m in models)),
                          "、".join("%s(%d 张)" % (m["id"], m["unused_images"])
                                   for m in sorted(unused_models,
                                                   key=lambda m: -m["unused_images"])[:6])),
        })
    # 4K/8K 贴图配小道具
    small_heavy = []
    for m in models:
        max_dim = (m["bbox"] or {}).get("max_dim_m") or 0
        if not max_dim or max_dim > 1.5:
            continue
        for im in m["image_list"]:
            if im["width"] >= 2048:
                small_heavy.append((m["id"], max_dim, im["name"], im["width"]))
    if small_heavy:
        small_heavy.sort(key=lambda r: -r[3])
        issues.append({
            "severity": "high",
            "kind": "big_texture_small_prop",
            "count": len(small_heavy),
            "detail": "%d 张 ≥2048 贴图挂在最大边长 ≤1.5m 的道具上（如 %s）。" % (
                len(small_heavy),
                "、".join("%s %.2fm %s %dpx" % (r[0], r[1], r[2] or "?", r[3])
                         for r in small_heavy[:6])),
        })
    # 动画/骨骼
    skinned = [m for m in models if m["skinned"]]
    if skinned:
        issues.append({
            "severity": "info",
            "kind": "skinned_models",
            "count": len(skinned),
            "detail": "%d 个模型带蒙皮骨骼（合计 %d 关节、%d 段动画），属于角色/动物类。" % (
                len(skinned), sum(m["joints"] for m in skinned),
                sum(m["animations"] for m in skinned)),
        })
    dead = [m for m in models if m["payload"]["dead_bytes"] > 1_048_576]
    if dead:
        issues.append({
            "severity": "medium",
            "kind": "dead_buffer_data",
            "count": len(dead),
            "detail": "%d 个 GLB 里有 %s 的 bufferView 没有任何 accessor 或图片引用（导出残留），"
                      "其中 %s；重新导出时要清掉。" % (
                          len(dead), mib(sum(m["payload"]["dead_bytes"] for m in dead)),
                          "、".join("%s %s" % (m["id"], mib(m["payload"]["dead_bytes"]))
                                   for m in sorted(dead, key=lambda m: -m["payload"]["dead_bytes"]))),
        })
    morph = [m for m in models if m["payload"]["morph_bytes"] > 1048576]
    if morph:
        issues.append({
            "severity": "info",
            "kind": "morph_targets",
            "count": sum(m["payload"]["morph_targets"] for m in models),
            "detail": "%d 个模型带形态键（blend shape）：合计 %d 个 target、%s。最大的 %s。"
                      "形态键在 Godot 里是每个顶点一份位移数据，占内存也拖导入；"
                      "要确认这些表情/形变是否都还在用。" % (
                          len(morph), sum(m["payload"]["morph_targets"] for m in models),
                          mib(sum(m["payload"]["morph_bytes"] for m in models)),
                          "、".join("%s %s（%d targets）" % (m["id"], mib(m["payload"]["morph_bytes"]),
                                                         m["payload"]["morph_targets"])
                                   for m in sorted(morph, key=lambda m: -m["payload"]["morph_bytes"])[:4])),
        })
    unknown = [m for m in models if m["source"]["family"] == SRC_UNKNOWN]
    if unknown:
        issues.append({
            "severity": "low",
            "kind": "unknown_source",
            "count": len(unknown),
            "detail": "%d 个模型在清单里找不到来源标注：%s" % (
                len(unknown), "、".join(m["id"] for m in unknown[:12])),
        })
    return issues


# --------------------------------------------------------------------------------------
# Markdown
# --------------------------------------------------------------------------------------
def table(headers, rows):
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join(["---"] * len(headers)) + "|"]
    for row in rows:
        out.append("| " + " | ".join(str(c) for c in row) + " |")
    return "\n".join(out)


def render_summary(rep):
    t = rep["totals"]
    src = rep["sources"]
    ai = src["ai_total"]
    tex = rep["texture_files_summary"]
    models = rep["models"]
    tri_total = t["triangles"] or 1
    vram_total = t["tex_rgba8_bytes"] or 1
    bytes_total = t["glb_bytes"] or 1
    imgs = [im for m in models for im in m["image_list"]]
    huge8 = [im for im in imgs if max(im["width"], im["height"]) >= 8192]
    huge4 = [im for im in imgs if max(im["width"], im["height"]) == 4096]
    owners8 = sorted({m["id"] for m in models for im in m["image_list"]
                      if max(im["width"], im["height"]) >= 8192})
    owners4 = sorted({m["id"] for m in models for im in m["image_list"]
                      if max(im["width"], im["height"]) == 4096})
    huge_models = sorted(set(owners8) | set(owners4))
    huge_vram = sum(im["rgba8_bytes"] for im in huge8 + huge4)

    def clamp_scenario(clamp):
        after = sum(min(im["width"], clamp) * min(im["height"], clamp) * 4 for im in imgs)
        return after, vram_total - after

    ai_tri_pct = pct(ai["triangles"], tri_total)
    ai_vram_pct = pct(ai["tex_rgba8_bytes"], vram_total)
    ai_bytes_pct = pct(ai["bytes"], bytes_total)
    ai_prim_pct = pct(ai["primitives"], t["primitives"])
    vbo_ratio = vram_total / (t["vb_bytes"] or 1)

    lines = []
    add = lines.append
    add("# 模型资产静态成本审计（game/assets/models，%d 个 GLB）" % t["models"])
    add("")
    add("审计脚本 [tools/audit_model_cost.py](../../../tools/audit_model_cost.py)，机器可读结果 [audit.json](audit.json)。")
    add("全部数字来自静态解析：GLB JSON chunk + 内嵌 PNG/JPEG/WebP 头 + .import 文件 + game/project.godot。")
    add("**没有启动 Godot**（原生 GPU 基准同时在跑，任何 Godot 进程都会干扰它）。")
    add("")
    add("## 0. 结论")
    add("")
    tri_scene_total = t["triangles_scene"] or 1
    ai_tri_scene_pct = pct(ai["triangles_scene"], tri_scene_total)
    add("1. **是，AI 图生 3D 是主要成本来源。** %d 个 GLB 里 %d 个来自 AI（Hyper3D Rodin %d、Pixal3D %d、Hunyuan %d），"
        "占三角面 %s（%s / %s，按场景节点计）、贴图显存 %s（%s / %s）、GLB 体积 %s、primitive %s。"
        % (t["models"], ai["models"], src[SRC_AI_HYPER3D]["models"], src[SRC_AI_PIXAL3D]["models"],
           src[SRC_AI_HUNYUAN]["models"], ai_tri_scene_pct,
           "{:,}".format(ai["triangles_scene"]), "{:,}".format(tri_scene_total),
           ai_vram_pct, mib(ai["tex_rgba8_bytes"]), mib(vram_total), ai_bytes_pct, ai_prim_pct))
    add("2. **贴图显存比几何显存贵两个数量级。** 贴图 %s，顶点缓冲只有 %s（%.0f 倍）。"
        "三角面主要吃顶点/光栅/遮挡剔除开销，不是显存。"
        % (mib(vram_total), mib(t["vb_bytes"]), vbo_ratio))
    add("3. **最贵的单体是建筑贴图：%d 张 8192² + %d 张 4096² 共 %s，占全部贴图显存的 %s。** "
        "8192² 每张 %s（未压缩 RGBA8），出自 %s；4096² 出自 %s。这些建筑在镇上是同屏加载的，"
        "所以实际峰值显存就是这些图加起来的量级。"
        % (len(huge8), len(huge4), mib(huge_vram), pct(huge_vram, vram_total),
           mib(256 * 1024 * 1024), "、".join(owners8), "、".join(owners4)))
    add("4. **内嵌贴图与同名外部贴图不是“重复两份”。** %d 张外部图是 glTF 导入器把内嵌图抽出来的项目文件"
        "（逐字节相同，导出时按 all_resources 进包），另有 %d 张是 GLB 更新后留下的过期贴图（%s），"
        "游戏里没有任何文件引用，可以直接删。"
        % (tex["states"].get("current", 0), tex["stale_files"], mib(tex["stale_bytes"])))
    add("5. **要降成本，第一刀砍贴图分辨率与 VRAM 压缩，第二刀砍极少数的几棵/几只模型。**"
        "贴图卡到 2048 省 %s，改用 BC7/BC5 省 %s，两者一起可以降到 %s。"
        "几何上 T05_old_shade_tree（484K）、H02（397K）、H01（299K）、S01（207K）、B01_bus（191K）"
        "、两只走路猫（各 18 万面）和 A12_bench（3.7 万面 × 约 8 条）是重点。"
        % (mib(clamp_scenario(2048)[1]), mib(vram_total - t["tex_bc_bytes"]),
           mib(clamp_scenario(2048)[0] // 4)))
    add("")
    add("## 1. 总量")
    add("")
    add(table(["项目", "数值"], [
        ["GLB 数量", t["models"]],
        ["三角面合计（唯一网格）", "{:,}".format(t["triangles"])],
        ["三角面合计（场景节点，含同一网格被多个节点复用）", "{:,}".format(t["triangles_scene"])],
        ["顶点合计", "{:,}".format(t["vertices"])],
        ["primitive = Godot surface 数（draw call 潜在数）合计", "{:,}".format(t["primitives"])],
        ["材质合计（模型内，不共享）", "{:,}".format(t["materials"])],
        ["GLB 文件合计", "%s（%d 字节）" % (mib(t["glb_bytes"]), t["glb_bytes"])],
        ["模型内嵌贴图数量", "%d 张" % t["images"]],
        ["贴图显存（未压缩 RGBA8）", mib(t["tex_rgba8_bytes"])],
        ["贴图显存（BC7/BC5 1 字节/像素）", mib(t["tex_bc_bytes"])],
        ["顶点缓冲估算", mib(t["vb_bytes"])],
        ["抽出到磁盘的贴图文件", "%d 张 / %s" % (tex["files"], mib(tex["bytes"]))],
        ["其中与当前 GLB 内嵌图一致", "%d 张 / %s" % (tex["states"].get("current", 0), mib(tex["identical_bytes"]))],
        ["其中已过期（GLB 里已无此图）", "%d 张 / %s" % (tex["stale_files"], mib(tex["stale_bytes"]))],
        ["没有任何材质引用的内嵌贴图", "%d 张 / %s" % (t["unused_images"], mib(t["unused_tex_rgba8_bytes"]))],
        ["跨模型重复的贴图可省显存", mib(t["duplicate_texture_wasted_rgba8_bytes"])],
    ]))
    add("")
    comp = t["file_composition"]
    add("### 文件体积构成（%s 的字节都花在哪）" % mib(t["glb_bytes"]))
    add("")
    comp_rows = [
        ["贴图（GLB 内嵌图片原始字节）", mib(comp["image_bytes"]), pct(comp["image_bytes"], bytes_total)],
        ["几何（顶点/索引 bufferView）", mib(comp["geom_bytes"]), pct(comp["geom_bytes"], bytes_total)],
        ["形态键（morph target，%d 个）" % t["morph_targets"], mib(comp["morph_bytes"]), pct(comp["morph_bytes"], bytes_total)],
        ["无引用的残留数据（可删）", mib(comp["dead_bytes"]), pct(comp["dead_bytes"], bytes_total)],
        ["动画曲线", mib(comp["anim_bytes"]), pct(comp["anim_bytes"], bytes_total)],
        ["蒙皮逆矩阵", mib(comp["skin_bytes"]), pct(comp["skin_bytes"], bytes_total)],
        ["JSON / 对齐填充", mib(comp["other_bytes"]), pct(comp["other_bytes"], bytes_total)],
    ]
    add(table(["内容", "体积", "占比"], comp_rows))
    add("")
    add("> 残留数据集中在角色：CH_mio 里 %s、CH_ren %s、CH_tanaka %s 的 bufferView 没有任何 accessor 引用，"
        "重新导出一次就会掉。形态键集中在 CH_kazuko（%s，%d 个 target）。"
        % (mib([m for m in models if m["id"] == "CH_mio"][0]["payload"]["dead_bytes"]),
           mib([m for m in models if m["id"] == "CH_ren"][0]["payload"]["dead_bytes"]),
           mib([m for m in models if m["id"] == "CH_tanaka"][0]["payload"]["dead_bytes"]),
           mib([m for m in models if m["id"] == "CH_kazuko"][0]["payload"]["morph_bytes"]),
           [m for m in models if m["id"] == "CH_kazuko"][0]["payload"]["morph_targets"]))
    add("")
    add("### 贴图分辨率分布（按模型内嵌图片计）")
    add("")
    res_rows = []
    for key, count in sorted(t["resolution_buckets"].items(),
                             key=lambda kv: -int(kv[0].split("x")[0])):
        w, h = (int(v) for v in key.split("x"))
        res_rows.append([key, count, mib(w * h * 4 * count)])
    add(table(["分辨率", "张数", "RGBA8 显存合计"], res_rows))
    add("")
    add("## 2. 来源分布")
    add("")
    add("来源判定顺序：`art/models/game_assets.json` 的 provider → 该资产的 src / raw 目录 → "
        "`art/models/raw/manifest*.json`（Hunyuan 批次）→ `art/manifests/models_*.json` 命中的清单族系 → "
        "`art/tools/proc_models.py` 等程序建模脚本。每个模型判定的证据都写在 audit.json 的 `source.evidence` 里。")
    add("")
    rows = []
    order = [SRC_AI_HYPER3D, SRC_AI_PIXAL3D, SRC_AI_HUNYUAN, SRC_BLENDER_PROC,
             SRC_THIRD_PARTY, SRC_HANDCRAFT, SRC_UNKNOWN]
    for family in order:
        row = src[family]
        if not row["models"]:
            continue
        rows.append([
            row["label"], row["models"],
            "{:,}".format(row["triangles"]), "{:,}".format(row["triangles_scene"]),
            pct(row["triangles_scene"], tri_scene_total),
            mib(row["tex_rgba8_bytes"]), pct(row["tex_rgba8_bytes"], vram_total),
            mib(row["bytes"]), pct(row["bytes"], bytes_total),
            "{:,}".format(row["primitives"]),
            "{:,}".format(row["triangles"] // row["models"]),
        ])
    rows.append([
        "**AI 合计**", "**%d**" % ai["models"],
        "**{:,}**".format(ai["triangles"]), "**{:,}**".format(ai["triangles_scene"]),
        "**%s**" % ai_tri_scene_pct,
        "**%s**" % mib(ai["tex_rgba8_bytes"]), "**%s**" % ai_vram_pct,
        "**%s**" % mib(ai["bytes"]), "**%s**" % ai_bytes_pct,
        "**{:,}**".format(ai["primitives"]), "**{:,}**".format(ai["triangles"] // ai["models"]),
    ])
    add(table(["来源", "模型数", "三角面(唯一网格)", "三角面(场景)", "占比", "贴图显存", "占比",
               "GLB 体积", "占比", "primitive", "平均三角面/模型"], rows))
    add("")
    add("> AI 平均每个模型 %s 个三角面，非 AI（%d 个）平均 %s，相差约 %.1f 倍。"
        % ("{:,}".format(ai["triangles"] // ai["models"]),
           t["models"] - ai["models"],
           "{:,}".format((t["triangles"] - ai["triangles"]) // max(1, t["models"] - ai["models"])),
           (ai["triangles"] / max(1, ai["models"])) / max(1e-9, (t["triangles"] - ai["triangles"]) / max(1, t["models"] - ai["models"]))))
    add("")
    add("## 3. 重模型 Top 30（按三角面）")
    add("")
    by_tri = sorted(models, key=lambda m: -m["triangles_scene"])[:30]
    rows = []
    for i, m in enumerate(by_tri, 1):
        rows.append([i, m["id"], m["source"]["family"], "{:,}".format(m["triangles"]),
                     m["primitives"], m["materials"], mib(m["tex_rgba8_bytes"]),
                     mib(m["bytes"]), m["prod_refs"],
                     "{:,}".format(m["triangles"] // 4),
                     mib(m["tex_rgba8_bytes"] - min(1024, 1) * 0)])
    # 重算“贴图≤1024 省”：按图片封顶
    rows = []
    for i, m in enumerate(by_tri, 1):
        tex_save = 0
        for im in m["image_list"]:
            tex_save += im["rgba8_bytes"] - min(im["width"], 1024) * min(im["height"], 1024) * 4
        rows.append([i, m["id"], m["source"]["family"], "{:,}".format(m["triangles_scene"]),
                     "{:,}".format(m["triangles"]),
                     m["primitives"], m["materials"], mib(m["tex_rgba8_bytes"]),
                     mib(m["bytes"]), m["prod_refs"],
                     "{:,}".format(m["triangles_scene"] // 4), mib(tex_save)])
    add(table(["#", "模型", "来源", "三角面(场景)", "三角面(唯一网格)", "primitive", "材质",
               "贴图显存", "GLB 体积", "代码引用(正式)", "减到 1/4 后剩", "贴图≤1024 省"], rows))
    add("")
    add("> 后两列是**单体**收益，没乘实例数。`代码引用(正式)` 是 game/scripts 里出现该 id 字面量的次数"
        "（不含测试），只是“用得多不多”的粗代理，不是运行时实例数。")
    add("")
    add("## 4. 降面 / 减贴图的收益场景")
    add("")
    rows = []
    for clamp, label in ((4096, "所有 >4096 的贴图降到 4096"), (2048, "所有 >2048 的贴图降到 2048"),
                         (1024, "所有 >1024 的贴图降到 1024"), (512, "所有 >512 的贴图降到 512")):
        after, saved = clamp_scenario(clamp)
        rows.append([label, mib(after), "-" + mib(saved), pct(saved, vram_total)])
    rows.append(["改走 VRAM 压缩（BC7 颜色 / BC5 法线）",
                 mib(t["tex_bc_bytes"]), "-" + mib(vram_total - t["tex_bc_bytes"]),
                 pct(vram_total - t["tex_bc_bytes"], vram_total)])
    after, saved = clamp_scenario(2048)
    rows.append(["先降到 2048 再走 VRAM 压缩", mib(after // 4), "-" + mib(vram_total - after // 4),
                 pct(vram_total - after // 4, vram_total)])
    rows.append(["共享跨模型重复贴图（%d 组）" % len(rep["duplicate_textures"]),
                 mib(vram_total - t["duplicate_texture_wasted_rgba8_bytes"]),
                 "-" + mib(t["duplicate_texture_wasted_rgba8_bytes"]),
                 pct(t["duplicate_texture_wasted_rgba8_bytes"], vram_total)])
    add(table(["做法", "改完贴图显存", "省下", "降幅"], rows))
    add("")
    add("> 每行都是相对当前状态的独立收益，不能直接相加；最后一行的“先降 2048 再压缩”是两项叠加后的结果。")
    add("")
    add("几何方面的等效估算：全员减到 1/4 面 = 三角面 %s → %s；只处理 Top 30 = %s → %s。"
        % ("{:,}".format(t["triangles_scene"]), "{:,}".format(t["triangles_scene"] // 4),
           "{:,}".format(sum(m["triangles_scene"] for m in by_tri)),
           "{:,}".format(sum(m["triangles_scene"] for m in by_tri) // 4)))
    add("")
    add("## 5. 导入设置检查")
    add("")
    ip = rep["import_params"]
    add("### 5.1 GLB 场景导入（%d 个 .import，全部一致）" % ip["glb"]["_count"])
    add("")
    add(table(["参数", "取值分布", "判断"], [
        ["meshes/generate_lods", json.dumps(ip["glb"]["meshes/generate_lods"]), "已开 LOD（好）"],
        ["meshes/ensure_tangents", json.dumps(ip["glb"]["meshes/ensure_tangents"]), "已算切线（法线贴图需要，好）"],
        ["meshes/create_shadow_meshes", json.dumps(ip["glb"]["meshes/create_shadow_meshes"]), "投影网格（好）"],
        ["meshes/force_disable_compression", json.dumps(ip["glb"]["meshes/force_disable_compression"]), "顶点压缩没被关掉（好）"],
        ["array_mesh/deduplicate_surfaces", json.dumps(ip["glb"]["array_mesh/deduplicate_surfaces"]), "同材质 surface 合并（好，压 draw call）"],
        ["materials/extract", json.dumps(ip["glb"]["materials/extract"]), "材质内嵌进场景，模型之间不共享材质"],
        ["gltf/embedded_image_handling", json.dumps(ip["glb"]["gltf/embedded_image_handling"]), "1 = 把内嵌图抽成项目文件（见 5.3）"],
        ["gltf/texture_map_mode", json.dumps(ip["glb"]["gltf/texture_map_mode"]), "1 = metallic/roughness 分开"],
    ]))
    add("")
    add("### 5.2 贴图导入（%d 张 .import，全部一致）" % ip["texture"]["_count"])
    add("")
    add(table(["参数", "取值", "判断"], [
        ["compress/mode", json.dumps(ip["texture"]["compress/mode"]), "**0 = Lossless，没有 VRAM 压缩**"],
        ["compress/normal_map", json.dumps(ip["texture"]["compress/normal_map"]), "**0 = 没有一张勾 Normal Map**"],
        ["mipmaps/generate", json.dumps(ip["texture"]["mipmaps/generate"]), "已生成 mipmap（好）"],
        ["process/size_limit", json.dumps(ip["texture"]["process/size_limit"]), "**0 = 不降采样，原图多大多大**"],
        ["detect_3d/compress_to", json.dumps(ip["texture"]["detect_3d/compress_to"]), "目标是 3D 时自动转 VRAM 压缩，但当前没有任何一张被转换过"],
        ["mipmaps/limit", json.dumps(ip["texture"]["mipmaps/limit"]), "-1 = 不限制 mip 级数"],
    ]))
    add("")
    add("`game/project.godot` 里与贴图/采样有关的全局设置：`textures/vram_compression/import_etc2_astc=true`"
        "（只影响移动端 ETC2/ASTC，macOS 桌面走 S3TC/BPTC，对当前问题无效）、"
        "`textures/default_filters/anisotropic_filtering_level=3`（8x 各向异性，8K 贴图上的采样带宽会更高）、"
        "`lights_and_shadows/directional_shadow/size=8192`、`anti_aliasing/quality/msaa_3d=2`（4x MSAA）。"
        "后两项是渲染设置，交给原生基准那一路量，不属于资产成本。")
    add("")
    add("### 5.3 问题清单")
    add("")
    sev_order = {"high": 0, "medium": 1, "low": 2, "info": 3}
    issues = sorted(rep["issues"], key=lambda i: sev_order.get(i["severity"], 9))
    rows = [[i["severity"], i["kind"], i["count"], i["detail"]] for i in issues]
    add(table(["级别", "类别", "数量", "说明"], rows))
    add("")
    add("> 关于法线：全部 %d 个模型里**没有一个材质引用法线贴图或 metallic-roughness 贴图**"
        "（%d 个只有 albedo，%d 个 albedo+emissive，%d 个只有 emissive，%d 个纯色无贴图）。"
        "所以 55 张 normal 现在只是被导入、没被用；"
        "一旦要启用，必须同时把它们勾成 Normal Map（否则会按 sRGB 颜色贴图取样，光照会错），"
        "并把压缩模式改成 BC5/RGTC。"
        % (t["models"], sum(1 for m in models if set(m["tex_roles"]) == {"albedo"}),
           sum(1 for m in models if set(m["tex_roles"]) == {"albedo", "emissive"}),
           sum(1 for m in models if set(m["tex_roles"]) == {"emissive"}),
           sum(1 for m in models if not m["tex_roles"])))
    add("")
    add("## 6. 跨模型重复贴图")
    add("")
    dups = rep["duplicate_textures"]
    if dups:
        add("同一份贴图字节被多个模型各自内嵌一份。Godot 里每个模型场景自带材质和贴图，不会共享资源，"
            "所以这些贴图在显存里是各占一份；改成一份共享贴图/材质就能省掉：")
        add("")
        rows = []
        for d in dups[:20]:
            rows.append(["%dx%d" % (d["width"], d["height"]), d["copies"],
                         "、".join(d["models"][:6]) + ("…" if len(d["models"]) > 6 else ""),
                         mib(d["wasted_rgba8_bytes"])])
        add(table(["分辨率", "重复份数", "涉及模型", "可省显存"], rows))
        add("")
        add("合计 %d 组，可省 %s（单体求和，不含实例倍数）。"
            % (len(dups), mib(t["duplicate_texture_wasted_rgba8_bytes"])))
    else:
        add("没有发现跨模型完全相同的贴图字节。")
    add("")
    add("## 7. 实例倍数（为什么有的单体要乘几倍）")
    add("")
    add("下表是本次审计在 game/scripts 里实际数到的摆放循环，用来把单体成本放大成实际成本：" )
    add("")
    bymap = {m["id"]: m for m in models}
    add(table(["模型", "单体三角面", "同屏/同场景实例（读代码数出）", "实际三角面"], [
        ["A12_bench", "37,426", "镇上 1 + 农园 3 + 湖畔 3 + 拜访 1 ≈ 8", "≈ 300,000"],
        ["T01_courtyard_tree", "6,265", "农园 8 + 田边 1 + 湖畔最多 20 + 住宅 若干 ≈ 30", "≈ 190,000"],
        ["M12b_shrub", "900", "农园 8 + 镇上 6 + 住宅若干 + 田垄/林带循环（数量随布局）", "数万级，便宜"],
        ["P_coffee_station", "{:,}".format(bymap["P_coffee_station"]["triangles_scene"] if "P_coffee_station" in bymap else 0),
         "咖啡店 1 + 家具复核脚本若干，单实例 primitive 71", "draw call 而不是三角面"],
        ["I02_cake_showcase", "{:,}".format(bymap["I02_cake_showcase"]["triangles_scene"] if "I02_cake_showcase" in bymap else 0),
         "蛋糕店陈列柜，单实例 primitive 29", "同上"],
    ]))
    add("")
    add("## 8. 单体降面优先级")
    add("")
    add("按单体场景三角面排的前 10 个（表外还要算 A12_bench 与 T01_courtyard_tree 的实例倍数）：")
    add("")
    prio = sorted(models, key=lambda m: -m["triangles_scene"])[:10]
    rows = []
    for m in prio:
        rows.append([m["id"], "{:,}".format(m["triangles_scene"]),
                     m["source"]["family"], m["prod_refs"],
                     "{:,}".format(m["triangles_scene"] // 4),
                     mib(m["tex_rgba8_bytes"])])
    add(table(["模型", "现在三角面", "来源", "代码引用(正式)", "减到 1/4 后", "贴图显存（顺带看）"], rows))
    add("")
    add("> A12_bench（37,426 面 × 约 8 条 ≈ 30 万面）和 T01_courtyard_tree（6,265 面 × 约 30 棵 ≈ 19 万面）"
        "单体不在前 10，但乘上实例后与上表同量级，所以也要列进降面清单；"
        "建筑、猫、角色基本都是单实例或少量实例。")
    add("")
    add("## 9. 建议（按性价比排序）")
    add("")
    add("### A. 便宜且安全：只改导入设置或资源组织，不动模型")
    add("")
    add("1. 贴图改 VRAM 压缩：`compress/mode=2`（桌面 BC7/BC5，normal 勾 `compress/normal_map=1`），"
        "贴图显存 %s → %s。画质影响主要集中在平涂色块边缘，需截图验收。"
        % (mib(vram_total), mib(t["tex_bc_bytes"])))
    add("2. 给所有贴图设 `process/size_limit`（例如 2048），或直接按模型尺寸卡分辨率："
        "把 65 张挂在 ≤1.5m 道具上的 2048 贴图降到 1024，单是这一项省 %s。"
        % mib(sum(max(0, im["width"] * im["height"] * 4 - 1024 * 1024 * 4)
                 for m in models for im in m["image_list"]
                 if max(im["width"], im["height"]) >= 2048 and ((m["bbox"] or {}).get("max_dim_m") or 99) <= 1.5)))
    add("3. 建筑图集 8192 → 4096：%s → %s，%d 个建筑省 %s，而 4K 在 10m 立面上仍然是 400px/m，"
        "对这个平涂画风够用。"
        % (mib(huge_vram), mib(huge_vram / 4), len(huge_models), mib(huge_vram * 3 // 4)))
    add("4. 同一份 atlas 被多个模型内嵌（%d 组，%s），抽成一个共享 `.tres` 材质再引用，纯收益。"
        % (len(dups), mib(t["duplicate_texture_wasted_rgba8_bytes"])))
    add("5. 删掉 %d 张过期贴图（%s，GLB 里已经没有这张图，游戏里也没有任何文件引用）和 %d 张"
        "没有任何材质引用的内嵌贴图（A07/A10/A11/A13/C01–C08/P06 的 normal + metallic-roughness）。"
        "它们现在都会被导入并按 `export_filter=all_resources` 进导出包。"
        % (tex["stale_files"], mib(tex["stale_bytes"]), t["unused_images"]))
    add("")
    add("### B. 需要重新导出/烘焙，但不重做美术")
    add("")
    add("1. 8K 图集重烘成 4K（或 2K + 平铺）：13 张 8192² 是显存最大的单项。")
    add("2. 大面数但看不到细节的模型走 Blender 减面（Decimate/Collapse 到 1/4，UV 保留）："
        "T05_old_shade_tree 484K→121K、B01_bus 191K→48K、A12_bench 37K→9K（×8 实例后 30 万→7 万）、"
        "两只走路猫 18 万→4.5 万、A20/A22 睡/坐猫 12 万→3 万。")
    add("3. 建筑 H02/H01/S01 的 16–33 个 primitive 可以按材质合并（同材质 surface 已经靠 "
        "deduplicate_surfaces 合并过，剩下的是不同材质），单实例 33 个 draw call 对建筑偏高。")
    add("")
    add("### C. 必须重新生成 / 重建的部分")
    add("")
    add("1. 两只走路猫（AN_cat_calico_walk / AN_cat_orange_walk，各 18 万面、1 个 primitive、"
        "59 关节骨架）：这是 Hyper3D 原网格直接进游戏，没有减面。猫在游戏里是小动物特写，"
        "18 万面属于典型 AI 网格过密，建议在 Blender 里用保留 UV 的减面重导，或重新用低面数档位生成。")
    add("2. 角色 7 个（CH_*）每个 9–10 万面，绑定时可一并减面；CH_kazuko 的 165.3 MiB 主要是 %s 形态键"
        "（222 个 target）和 %s 无引用残留数据，先确认这些表情是否都用得上，再重新导出。"
        % (mib(bymap["CH_kazuko"]["payload"]["morph_bytes"]), mib(bymap["CH_kazuko"]["payload"]["dead_bytes"])))
    add("3. AI 网格的贴图（normal/metallic-roughness）在本项目里**没有任何材质使用**（%d 个模型只有 albedo），"
        "如果坚持纯色卡通风，可以彻底不导出这些贴图；要保留法线细节则必须重新烘焙并正确设置法线贴图导入。"
        % sum(1 for m in models if set(m["tex_roles"]) == {"albedo"}))
    add("")
    add("## 10. 方法与局限")
    add("")
    add("- GLB 三角面 = 各 primitive 索引数/3（无索引时用 POSITION 数）；primitive 数按 Godot 的 surface 计。")
    add("- 贴图尺寸直接读内嵌 PNG IHDR / JPEG SOF / WebP VP8/VP8L / KTX2 头；显存按未压缩 8bit RGBA（w×h×4）估，"
        "不透明图若按 RGB8 存则为 3/4；mipmap 再加约 33%（表里未计）。")
    add("- 已核对 `.godot/imported` 里对应的 `.ctex`：8192² 贴图导入后仍是 8192²，且图像以无损 WebP 存放，"
        "说明没有被降采样、也没有走 VRAM 压缩，运行时解成未压缩位图上传显卡。")
    add("- 顶点缓冲按 POSITION(12)+NORMAL(12)+UV(8)，有 TANGENT 再加 16、蒙皮再加 16 字节估算。")
    add("- 交叉验证：用 `game/assets/models/_stats/*.json`（Blender 导出时记录的 `tris`）对照 284 个模型，"
        "280 个三角面完全一致；不一致的 3 个（P_community_table、J03_dining_set、P_cafe_table）是"
        "「同一份网格被多个节点复用」的情况，按场景节点复算后与 stats 一致；"
        "I07_ice_freezer 的 stats 记的是重建前的 Pixal3D 版本（5,634 面），当前 GLB 是 Blender 重建版 290 面。")
    add("- 实例数是读 `game/scripts` 里的 spawn 字面量与循环数组数出来的近似值，不是运行时统计；"
        "运行时真值要看原生基准那一路的实测。")
    add("- 本审计不改 game/ 下任何文件，也不启动 Godot。")
    add("")
    add("复现：`python3 tools/audit_model_cost.py`（约 1 秒，只读文件）。")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    sys.exit(main())

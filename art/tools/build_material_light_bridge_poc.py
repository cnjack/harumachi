"""Build an opt-in bridge variant with real millimetre edge bevels; preserve the source GLB."""
from pathlib import Path
import hashlib
import json
import math
import bpy
import bmesh

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "game/assets/models/P_bridge.glb"
OUTPUT = ROOT / "game/assets/material_light_poc/P_bridge_beveled.glb"
MANIFEST = ROOT / "art/manifests/material_light_bridge_poc_20261025.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    source_hash = digest(SOURCE)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    parts = []
    for obj in sorted(bpy.context.scene.objects, key=lambda item: item.name):
        if obj.type != "MESH":
            continue
        before = len(obj.data.polygons)
        before_vertices = len(obj.data.vertices)
        # glTF splits vertices at face normals / UV seams. Reconnect coincident
        # geometry before beveling; UVs remain attached to their individual loops.
        editable = bmesh.new()
        editable.from_mesh(obj.data)
        bmesh.ops.remove_doubles(editable, verts=list(editable.verts), dist=.000001)
        editable.to_mesh(obj.data)
        editable.free()
        width = .006 if obj.name == "planks" else .012
        if obj.name == "abutments":
            width = .008
        bpy.context.view_layer.objects.active = obj
        bevel = obj.modifiers.new("POC real rounded edges", "BEVEL")
        bevel.width = width
        bevel.segments = 3
        bevel.limit_method = "ANGLE"
        bevel.angle_limit = math.radians(30)
        bevel.use_clamp_overlap = True
        bevel.harden_normals = True
        bpy.ops.object.modifier_apply(modifier=bevel.name)
        weighted = obj.modifiers.new("POC flat face normals", "WEIGHTED_NORMAL")
        weighted.keep_sharp = True
        bpy.ops.object.modifier_apply(modifier=weighted.name)
        if obj.name != "deck":  # This curved backing sheet has no closed sharp corners.
            assert len(obj.data.polygons) > before, f"Bevel did not create geometry for {obj.name}"
        parts.append({"name": obj.name, "width_m": width, "segments": 3,
                      "polygons_before": before, "polygons_after": len(obj.data.polygons),
                      "vertices_before": before_vertices, "vertices_after": len(obj.data.vertices),
                      "material_slots": [slot.material.name for slot in obj.material_slots]})
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", export_yup=True,
                             export_apply=True, export_animations=False, export_image_format="AUTO")
    assert digest(SOURCE) == source_hash
    MANIFEST.write_text(json.dumps({"purpose": "opt-in material/light POC, not a replacement game asset",
                                   "source": str(SOURCE.relative_to(ROOT)), "source_sha256": source_hash,
                                   "output": str(OUTPUT.relative_to(ROOT)), "sha256": digest(OUTPUT),
                                   "blender": bpy.app.version_string, "parts": parts,
                                   "generator": str(Path(__file__).resolve().relative_to(ROOT))},
                                  ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()

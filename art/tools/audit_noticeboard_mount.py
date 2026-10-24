"""Check the complete P02 paper footprint in source and actual exported geometry."""
from __future__ import annotations

from hashlib import sha256
from pathlib import Path
import json

import repair_noticeboard_mount as repair


def read_geometry(path):
    document, binary = repair.load_glb(path)
    primitive = document["meshes"][0]["primitives"][0]
    vertices = repair.accessor(document, binary, primitive["attributes"]["POSITION"])
    indices = [row[0] for row in repair.accessor(document, binary, primitive["indices"])]
    triangles = [tuple(vertices[indices[offset + corner]] for corner in range(3))
                 for offset in range(0, len(indices), 3)]
    return {"triangles": triangles, "images": repair.image_bytes(document, binary),
            "bounds": [[function(vertex[axis] for vertex in vertices) for axis in range(3)]
                       for function in [min, max]], "sha256": sha256(path.read_bytes()).hexdigest()}


def coverage(triangles):
    area = 0.
    for triangle in triangles:
        if min(vertex[2] for vertex in triangle) <= .045 or not repair.overlap(triangle, repair.PAPER):
            continue
        polygon = repair.inside_polygon(triangle, repair.PAPER)
        area += abs(sum(polygon[i - 1][0] * vertex[1] - vertex[0] * polygon[i - 1][1]
                        for i, vertex in enumerate(polygon))) * .5
    return area


def measurement(geometry):
    low, high = repair.surface_range(geometry["triangles"])
    paper = high + .003
    gaps = []
    for x in [-.45, 0., .45]:
        for y in [-.45, 0., .45]:
            hits = repair.sample_front(geometry["triangles"], .36 + x * .58, 1.18 + y * .82)
            gaps.append(paper - max(hits) if hits else float("inf"))
    return {"front_envelope_m": high, "front_low_m": low, "front_variation_m": high - low,
            "paper_depth_m": paper, "nine_ray_gaps_m": gaps,
            "no_penetrating_triangle": paper - high >= .001,
            "original_25_mm_mount_limit_passes": all(-.001 <= gap <= .025 for gap in gaps),
            "front_projected_coverage_m2": coverage(geometry["triangles"])}


def main():
    source = read_geometry(repair.SOURCE)
    authored = read_geometry(repair.TARGET)
    exported_path = repair.ROOT / "game/assets/models/P02.glb"
    exported = read_geometry(exported_path)
    before, after = measurement(source), measurement(exported)
    full_area = (repair.PAPER[1] - repair.PAPER[0]) * (repair.PAPER[3] - repair.PAPER[2])
    checks = {
        "old_envelope_offset_still_fails_original_mount_distance": not before["original_25_mm_mount_limit_passes"],
        "exported_whole_paper_footprint_is_one_flat_support": after["front_variation_m"] <= 1e-6,
        "exported_front_has_full_projected_coverage": abs(after["front_projected_coverage_m2"] - full_area) <= 1e-6,
        "exported_paper_has_no_penetration": after["no_penetrating_triangle"],
        "exported_paper_passes_original_mount_limit": after["original_25_mm_mount_limit_passes"],
        "actual_export_matches_authored_support": abs(after["front_envelope_m"] - measurement(authored)["front_envelope_m"]) < 1e-6,
        "original_encoded_texture_unchanged_in_source_and_game": source["images"] == authored["images"] == exported["images"],
        "overall_shape_bounds_unchanged": max(abs(a - b) for arow, brow in zip(source["bounds"], exported["bounds"]) for a, b in zip(arow, brow)) < 1e-6,
    }
    report = {"checks": checks, "failed": sum(not passed for passed in checks.values()),
              "before": before, "after": after, "game_sha256": exported["sha256"],
              "source_sha256": source["sha256"], "authored_sha256": authored["sha256"],
              "game_file": str(exported_path.relative_to(repair.ROOT))}
    output = repair.ROOT / "evidence/visual_rework_20261024/signs/source_repair_verification.json"
    output.write_text(json.dumps(report, indent=2) + "\n")
    manifest = json.loads(repair.MANIFEST.read_text())
    manifest["exported_sha256"] = exported["sha256"]
    manifest["exported_texture_matches_original"] = checks["original_encoded_texture_unchanged_in_source_and_game"]
    repair.MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if report["failed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

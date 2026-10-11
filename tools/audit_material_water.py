#!/usr/bin/env python3
"""Measure SHA-bound native water pairs; no assets or screenshots are edited.

Run with the project's PIL/numpy/scipy Python:
  python tools/audit_material_water.py /path/to/native-water-probe
The artificial gate toggles isolate real shader contributions. Normal weather
screenshots and human inspection are still required for scene-level acceptance.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def quad_mask(size, quad):
    height, width = size
    yy, xx = np.mgrid[:height, :width]
    signs = []
    for index, a in enumerate(quad):
        b = quad[(index + 1) % len(quad)]
        signs.append((b[0] - a[0]) * (yy + .5 - a[1]) -
                     (b[1] - a[1]) * (xx + .5 - a[0]))
    crosses = np.stack(signs)
    return (crosses >= 0).all(axis=0) | (crosses <= 0).all(axis=0)


def audit(folder, report_name="pixel-audit.json"):
    manifest = json.loads((folder / "manifest.json").read_text())
    shots = {row["file"]: row for row in manifest["shots"]}
    arrays = {}
    for filename, row in shots.items():
        path = folder / filename
        if digest(path) != row["sha256"]:
            raise ValueError("PNG changed after native capture: " + filename)
        with Image.open(path) as image:
            if list(image.size) != row["png_size_px"]:
                raise ValueError("Incorrect PNG size: " + filename)
            arrays[filename] = np.asarray(image.convert("RGB"), dtype=np.float64) / 255.0
    checks = []
    metrics = {}
    for name, limit in [("sun", .45), ("moon", .45), ("lamp", .70)]:
        on, off = name + "_on.png", name + "_off.png"
        if shots[on]["analysis_water_quad_png_px"] != shots[off]["analysis_water_quad_png_px"]:
            raise ValueError("Paired camera changed: " + name)
        mask = quad_mask(arrays[on].shape[:2], shots[on]["analysis_water_quad_png_px"])
        if mask.sum() < 200:
            raise ValueError("Water-only measurement region is empty/tiny: " + name)
        delta = np.max(np.abs(arrays[on] - arrays[off]), axis=2)
        changed = delta[mask] > 2.0 / 255.0
        fraction = float(changed.mean())
        p99 = float(np.quantile(delta[mask], .99))
        metrics[name] = {"water_roi_pixels": int(mask.sum()),
                         "changed_fraction_over_two_png_levels": fraction,
                         "maximum_changed_fraction": limit,
                         "p99_delta": p99,
                         "mean_delta": float(delta[mask].mean()),
                         "files": [on, off]}
        checks.append({"name": name + "_has_localized_rendered_reflection",
                       "passed": .0005 <= fraction <= limit and p99 > 3.0 / 255.0,
                       "detail": metrics[name]})
    sun_mask = quad_mask(arrays["sun_on.png"].shape[:2], shots["sun_on.png"]["analysis_water_quad_png_px"])
    motion = np.max(np.abs(arrays["sun_next.png"] - arrays["sun_on.png"]), axis=2)
    motion_fraction = float((motion[sun_mask] > 2.0 / 255.0).mean())
    checks.append({"name": "real_wave_render_changes_after_point_seven_seconds",
                   "passed": motion_fraction > .005,
                   "detail": {"changed_fraction": motion_fraction}})
    rain_on, rain_off = arrays["rain_on.png"], arrays["rain_off.png"]
    rain_mask = quad_mask(rain_on.shape[:2], shots["rain_on.png"]["analysis_water_quad_png_px"])
    rain_delta = np.max(np.abs(rain_on - rain_off), axis=2)
    rings = (rain_delta > 1.5 / 255.0) & rain_mask
    labels, _ = ndimage.label(rings)
    components = ndimage.find_objects(labels)
    pixels_per_metre = rain_on.shape[0] / float(shots["rain_on.png"]["ortho_height_metres"])
    spans = []
    for label, component in enumerate(components, start=1):
        if component is None or (labels[component] == label).sum() < 4:
            continue
        # Ignore truncated rings on the analysis-region/image boundary.
        if not rain_mask[component].all():
            continue
        span_px = max(part.stop - part.start for part in component)
        spans.append(span_px / pixels_per_metre)
    median = float(np.median(spans)) if spans else None
    p90 = float(np.quantile(spans, .90)) if spans else None
    metrics["rain"] = {"connected_ring_components": len(spans), "median_span_metres": median,
                       "p90_span_metres": p90, "png_pixels_per_metre": pixels_per_metre,
                       "scope": "thresholded rendered rain-only difference; intersecting rings can join"}
    checks.append({"name": "rendered_rain_components_are_small_not_metre_hoops",
                   "passed": len(spans) >= 12 and median < .34 and p90 < .65,
                   "detail": metrics["rain"]})
    # A ring-size check alone misses AA seams that follow hashed cell boundaries.
    # Measure long straight steps in the rain-only difference, not the underlying
    # painted bed. A real thin circle cannot run straight beyond its diameter.
    rain_rgb_difference = rain_on - rain_off
    straight_edges = {}
    for axis, orientation in [(0, "horizontal"), (1, "vertical")]:
        steps = np.max(np.abs(np.diff(rain_rgb_difference, axis=axis)), axis=2)
        valid = ((rain_mask[:-1] & rain_mask[1:]) if axis == 0 else
                 (rain_mask[:, :-1] & rain_mask[:, 1:]))
        bits = (steps > 1.5 / 255.0) & valid
        scan = bits if axis == 0 else bits.T
        runs = []
        for row in scan:
            transitions = np.diff(np.r_[False, row, False].astype(np.int8))
            starts = np.flatnonzero(transitions == 1)
            ends = np.flatnonzero(transitions == -1)
            runs.extend((ends - starts).tolist())
        longest = max(runs, default=0)
        straight_edges[orientation] = {
            "longest_straight_edge_png_px": longest,
            "longest_straight_edge_metres": longest / pixels_per_metre,
            "runs_exceeding_36cm": sum(run / pixels_per_metre > .36 for run in runs)}
    metrics["rain_straight_edges"] = straight_edges
    checks.append({"name": "rain_has_no_long_rectangular_cell_seams",
                   "passed": all(value["longest_straight_edge_metres"] <= .36
                                 for value in straight_edges.values()),
                   "detail": straight_edges})
    report = {"schema_version": 1, "scope": "native paired shader diagnostics; human production-view review also required",
              "passed": all(check["passed"] for check in checks), "checks": checks,
              "metrics": metrics, "source_manifest_sha256": digest(folder / "manifest.json"),
              "files": [{"file": name, "sha256": digest(folder / name)} for name in sorted(shots)]}
    (folder / report_name).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--report-name", default="pixel-audit.json")
    args = parser.parse_args()
    result = audit(args.folder, args.report_name)
    print(json.dumps({"passed": result["passed"], "checks": result["checks"]}, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result["passed"] else 1)

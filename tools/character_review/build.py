#!/usr/bin/env python3
"""Build a local, offline character review UI beside an existing native capture."""
import argparse
import hashlib
import json
import math
import shutil
from pathlib import Path

ACTORS = {"sora": "空", "ren": "莲", "haru": "春", "mio": "澪", "aoi": "小葵", "tanaka": "田中", "kazuko": "和子"}
ACTIONS = {"idle": "站立", "walk": "走路", "run": "跑步", "wave": "挥手", "stretch": "伸展", "bow": "鞠躬", "dance": "舞蹈"}
VIEWS = {"front": "正面", "right": "右侧", "back": "背面", "left": "左侧", "top": "正上方"}


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def motion_evidence(folder):
    preview_manifest = folder / 'motion-previews/manifest.json'
    if preview_manifest.is_file():
        preview = json.loads(preview_manifest.read_text())
        if 'cases' in preview:
            return preview['cases'], True
    # Older collections have a single right-side GIF and no preview manifest.
    # Prefer the lean preview metadata above instead of re-reading full bones.
    for capture in ('continuous', 'native-preview'):
        report = folder / capture / 'continuous-gait.json'
        if report.is_file():
            return json.loads(report.read_text()).get('cases', []), False
    return [], False


def view_motion(folder, actor, view, row, gif, kind):
    speed = row.get('forced_speed_mps')
    if speed is not None and (isinstance(speed, bool) or not isinstance(speed, (int, float)) or not math.isfinite(speed) or speed < 0):
        raise ValueError('Invalid motion speed')
    speed_label = f'{speed:g}米/秒' if speed is not None else '游戏实际速度' if kind == 'native' else '速度未记录'
    label = '真实连续移动' if kind == 'native' else '快速移动对照' if actor in {'ren', 'haru', 'mio'} else '跑步动作对照（非日程）'
    return {'file': gif.as_posix(), 'view': view, 'view_label': VIEWS[view],
            'label': label + ' · ' + speed_label, 'speed_label': speed_label,
            'forced_speed_mps': speed, 'kind': kind, 'sha256': digest(folder / gif)}


def selected_names(values, catalog, label):
    if values is None:
        return catalog
    if not isinstance(values, (list, tuple)) or not values:
        raise ValueError('Empty or invalid ' + label + ' selection')
    if any(not isinstance(value, str) or value not in catalog for value in values):
        raise ValueError('Unknown ' + label + ' selection')
    if len(set(values)) != len(values):
        raise ValueError('Duplicate ' + label + ' selection')
    # Stable catalog order also keeps an explicit full selection identical to
    # the legacy default dataset, independently of CLI argument ordering.
    return {name: label for name, label in catalog.items() if name in values}


def build(folder, actors=None, actions=None):
    folder = folder.resolve()
    selected_actors = selected_names(actors, ACTORS, 'actor')
    selected_actions = selected_names(actions, ACTIONS, 'action')
    movement = {}
    motion_records, has_motion_manifest = motion_evidence(folder)
    for record in motion_records:
        actor, action, view = record['character'], record.get('clip', record.get('requested_clip')), record.get('view', 'right')
        if actor not in ACTORS or action not in ACTIONS:
            raise ValueError('Unknown motion identity')
        if actor not in selected_actors or action not in selected_actions:
            continue
        if view not in VIEWS:
            raise ValueError('Unknown motion identity')
        if (actor, action, view) in movement:
            raise ValueError('Duplicate motion view')
        movement[(actor, action, view)] = record
    groups = {}
    for batch in ("locomotion-poses", "joint-poses"):
        manifest = json.loads((folder / batch / "manifest.json").read_text())
        for row in manifest["shots"]:
            actor, action = row["id"], row["action"]
            if actor not in ACTORS or action not in ACTIONS:
                raise ValueError("Unknown capture identity")
            if actor not in selected_actors or action not in selected_actions:
                continue
            if row.get("diagnostic_hidden_arm_fill") or row.get("diagnostic_disabled_lod"):
                raise ValueError("Diagnostic hidden geometry cannot serve as final character review evidence")
            if row.get("garment_support", {}).get("diagnostic_proxy_override"):
                raise ValueError("A diagnostic garment proxy cannot serve as final character review evidence")
            actor, action, view = row["id"], row["action"], row["view"]
            if actor not in ACTORS or action not in ACTIONS or view not in VIEWS:
                raise ValueError("Unknown capture identity")
            path = folder / batch / row["file"]
            if not path.is_file():
                raise FileNotFoundError(path)
            phase = float(row["phase"])
            key = f"{actor}/{action}/{round(phase * 1000)}/{view}"
            overlay = Path("skeleton-overlay") / batch / row["file"]
            frame = {"key": key, "phase": phase, "view": view, "view_label": VIEWS[view],
                     "file": f"{batch}/{row['file']}", "sha256": digest(path),
                     "overlay": overlay.as_posix() if (folder / overlay).is_file() else None,
                     "overlay_sha256": digest(folder / overlay) if (folder / overlay).is_file() else None}
            groups.setdefault((actor, action), []).append(frame)
    cases = []
    for actor, actor_label in selected_actors.items():
        for action, action_label in selected_actions.items():
            frames = sorted(groups.get((actor, action), []), key=lambda x: (x["phase"], list(VIEWS).index(x["view"])))
            if not frames:
                raise ValueError('Missing selected capture: ' + actor + '/' + action)
            if len({f["key"] for f in frames}) != len(frames):
                raise ValueError("Duplicate frame identity")
            phases = sorted({f["phase"] for f in frames})
            if len(frames) != len(phases) * len(VIEWS):
                raise ValueError("Incomplete five-direction capture")
            motion = None
            # Keep the exact legacy object/hash when a collection only contains
            # the old canonical right-side GIF. New per-view metadata is additive.
            for suffix, label, kind in ([] if has_motion_manifest else [("", "真实连续移动", "native"), ("-fast", "快速移动对照 · 4.5米/秒", "fast_fixture")]):
                gif = Path("motion-previews") / f"{actor}-{action}{suffix}.gif"
                if (folder / gif).is_file():
                    measured = movement.get((actor, action, 'right'), {})
                    speed = measured.get("forced_speed_mps")
                    if kind == "fast_fixture" and speed is not None:
                        label = ("快速移动对照" if actor in {"ren", "haru", "mio"} else "跑步动作对照（非日程）") + f" · {speed:g}米/秒"
                    motion = {"file": gif.as_posix(), "label": label, "kind": kind,
                              "sha256": digest(folder / gif)}
                    break
            motion_views = {}
            for view in VIEWS:
                measured = movement.get((actor, action, view), {})
                if has_motion_manifest:
                    if not measured: continue
                    gif = Path('motion-previews') / measured['gif']['file']
                    (folder / gif).resolve().relative_to((folder / 'motion-previews').resolve())
                    if not (folder / gif).is_file(): raise FileNotFoundError(folder / gif)
                    recorded_hash = measured['gif'].get('sha256')
                    if recorded_hash is not None and recorded_hash != digest(folder / gif):
                        raise ValueError('Motion GIF SHA does not match preview manifest: ' + str(gif))
                    kind = 'fast_fixture' if measured.get('forced_speed_mps') is not None or 'fixture' in str(measured.get('fixture', '')) else 'native'
                    motion_views[view] = view_motion(folder, actor, view, measured, gif, kind)
                else:
                    for suffix, kind in [('', 'native'), ('-fast', 'fast_fixture')]:
                        gif = Path('motion-previews') / f'{actor}-{action}{suffix}-{view}.gif'
                        if (folder / gif).is_file():
                            motion_views[view] = view_motion(folder, actor, view, measured, gif, kind)
                            break
            if motion_views:
                motion = motion_views.get('right', next(iter(motion_views.values())))
            cases.append({"id": f"{actor}/{action}", "actor": actor, "actor_label": actor_label,
                          "action": action, "action_label": action_label, "phases": phases,
                          "frames": frames, "motion": motion, "motion_views": motion_views})
    identity = [{"key": f["key"], "sha256": f["sha256"], "overlay_sha256": f["overlay_sha256"]}
                for c in cases for f in c["frames"]]
    source_identity = {"frames": identity, "motion": [{"id": c["id"], "motion": c["motion"]} for c in cases]}
    for item, case in zip(source_identity['motion'], cases):
        if case['motion_views']: item['motion_views'] = case['motion_views']
    source_hash = hashlib.sha256(json.dumps(source_identity, sort_keys=True).encode()).hexdigest()
    dataset = {"id": "harumachi-character-" + source_hash[:16], "evidence_id": folder.name,
               "source_sha256": source_hash, "case_count": len(cases),
               "frame_count": len(identity), "views": VIEWS, "cases": cases}
    source = Path(__file__).resolve().parent
    template = (source / "index.template.html").read_text()
    encoded = json.dumps(dataset, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    report_link = ('<a class="report-link" href="REPORT.html" target="_blank" rel="noopener">查看之前的审查报告 ↗</a>'
                   if (folder / 'REPORT.html').is_file() else '')
    (folder / "index.html").write_text(template.replace("__REVIEW_DATA__", encoded)
                                      .replace("__OPTIONAL_REPORT_LINK__", report_link))
    for name in ("review.css", "review-model.js", "review.js"):
        shutil.copyfile(source / name, folder / name)
    print(json.dumps({"cases": len(cases), "frames": len(identity), "dataset_id": dataset["id"], "ui": str(folder / "index.html")}, ensure_ascii=False))
    return dataset


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument('--actors', nargs='+', action='extend', help='Only these actors, for example --actors ren')
    parser.add_argument('--actions', nargs='+', action='extend', help='Only these actions, for example --actions walk')
    args = parser.parse_args()
    try:
        build(args.evidence, actors=args.actors, actions=args.actions)
    except ValueError as error:
        parser.error(str(error))

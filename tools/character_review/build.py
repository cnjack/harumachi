#!/usr/bin/env python3
"""Build a local, offline character review UI beside an existing native capture."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ACTORS = {"sora": "空", "ren": "莲", "haru": "春", "mio": "澪", "aoi": "小葵", "tanaka": "田中", "kazuko": "和子"}
ACTIONS = {"idle": "站立", "walk": "走路", "run": "跑步", "wave": "挥手", "stretch": "伸展", "bow": "鞠躬", "dance": "舞蹈"}
VIEWS = {"front": "正面", "right": "右侧", "back": "背面", "left": "左侧", "top": "正上方"}


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def build(folder):
    folder = folder.resolve()
    groups = {}
    for batch in ("locomotion-poses", "joint-poses"):
        manifest = json.loads((folder / batch / "manifest.json").read_text())
        for row in manifest["shots"]:
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
    for actor, actor_label in ACTORS.items():
        for action, action_label in ACTIONS.items():
            frames = sorted(groups[(actor, action)], key=lambda x: (x["phase"], list(VIEWS).index(x["view"])))
            if len({f["key"] for f in frames}) != len(frames):
                raise ValueError("Duplicate frame identity")
            phases = sorted({f["phase"] for f in frames})
            if len(frames) != len(phases) * len(VIEWS):
                raise ValueError("Incomplete five-direction capture")
            motion = None
            for suffix, label, kind in [("", "真实连续移动", "native"), ("-fast", "快速移动对照 · 4.5米/秒", "fast_fixture")]:
                gif = Path("motion-previews") / f"{actor}-{action}{suffix}.gif"
                if (folder / gif).is_file():
                    motion = {"file": gif.as_posix(), "label": label, "kind": kind,
                              "sha256": digest(folder / gif)}
                    break
            cases.append({"id": f"{actor}/{action}", "actor": actor, "actor_label": actor_label,
                          "action": action, "action_label": action_label, "phases": phases,
                          "frames": frames, "motion": motion})
    identity = [{"key": f["key"], "sha256": f["sha256"], "overlay_sha256": f["overlay_sha256"]}
                for c in cases for f in c["frames"]]
    source_identity = {"frames": identity, "motion": [{"id": c["id"], "motion": c["motion"]} for c in cases]}
    source_hash = hashlib.sha256(json.dumps(source_identity, sort_keys=True).encode()).hexdigest()
    dataset = {"id": "harumachi-character-" + source_hash[:16], "evidence_id": folder.name,
               "source_sha256": source_hash, "case_count": len(cases),
               "frame_count": len(identity), "views": VIEWS, "cases": cases}
    source = Path(__file__).resolve().parent
    template = (source / "index.template.html").read_text()
    encoded = json.dumps(dataset, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    (folder / "index.html").write_text(template.replace("__REVIEW_DATA__", encoded))
    for name in ("review.css", "review-model.js", "review.js"):
        shutil.copyfile(source / name, folder / name)
    print(json.dumps({"cases": len(cases), "frames": len(identity), "dataset_id": dataset["id"], "ui": str(folder / "index.html")}, ensure_ascii=False))
    return dataset


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    build(parser.parse_args().evidence)

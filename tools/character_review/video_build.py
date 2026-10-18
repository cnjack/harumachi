#!/usr/bin/env python3
"""Build an independent offline video review beside an explicitly delivered nine-take batch."""
import argparse
from collections import Counter
import hashlib
import json
from fractions import Fraction
from pathlib import Path
import shutil

ACTORS = {"sora": "空", "ren": "莲", "haru": "春", "mio": "澪", "aoi": "小葵", "tanaka": "田中", "kazuko": "和子"}
ACTIONS = {"idle": "站立", "walk": "走路", "run": "跑步", "wave": "挥手", "stretch": "伸懒腰", "bow": "鞠躬", "dance": "舞蹈"}
VIEWS = {"front": "正面", "right": "右侧", "back": "背面", "left": "左侧", "top": "顶部", "oblique": "斜视"}
TAKES = ["solo-" + actor for actor in ACTORS] + ["group-walk-run", "group-all-actions"]
MARKER = "harumachi-video-review-entry/v1"
RUNTIME = "scripts/characters/character_garment_support.gd"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read(path):
    return json.loads(path.read_text())


def require(condition, message):
    if not condition:
        raise ValueError(message)


def identity_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def local_file(folder, relative):
    path = folder / relative
    path.resolve().relative_to(folder)
    require(path.is_file() and not path.is_symlink(), "Missing or redirected evidence file: " + relative)
    return path


def take_sections(take, journal, frames, fps):
    actors = [take.removeprefix("solo-")] if take.startswith("solo-") else ["ren", "mio", "kazuko"] if take == "group-walk-run" else list(ACTORS)
    order = list(ACTIONS)[:-1] if take.startswith("solo-") else ["walk", "run", "wave", "bow"] if take == "group-walk-run" else ["idle", "wave", "stretch", "bow", "dance"]
    require(journal.get("take") == take and journal.get("fps") == fps and journal.get("failures") == [], "Journal identity/failure: " + take)
    rows = journal.get("frames", [])
    sections = journal.get("sections", [])
    require(len(rows) == frames and [s.get("action") for s in sections] == order, "Incomplete journal sections: " + take)
    result, offset = [], 0
    for section in sections:
        count, action = section.get("count"), section["action"]
        require(type(count) is int and count > 0 and offset + count <= frames, "Invalid section count: " + take)
        selected = rows[offset:offset + count]
        observed = Counter()
        view_segments = []
        for relative_index, row in enumerate(selected):
            require(row.get("action") == action and set(row.get("actors", {})) == set(actors), "Row outside section/actor identity: " + take)
            view = row.get("view")
            require(view in VIEWS, "Unknown actual journal view: " + take)
            frame_index = offset + relative_index
            if not view_segments or view_segments[-1]["view"] != view:
                view_segments.append({"view": view, "view_label": VIEWS[view], "frame_start": frame_index,
                                      "frame_end": frame_index + 1, "start_s": frame_index / fps, "end_s": (frame_index + 1) / fps})
            else:
                view_segments[-1]["frame_end"] = frame_index + 1
                view_segments[-1]["end_s"] = (frame_index + 1) / fps
            for actor in actors:
                observed[actor + "/" + row["actors"][actor]["clip"]] += 1
        require(dict(observed) == section.get("observed_clips"), "Observed clip counts differ: " + take)
        require(all(observed[actor + "/" + action] > 0 for actor in actors), "Requested action never appears: " + take)
        # The MP4 trim starts at journal row zero. Absolute engine drawn_frame
        # values deliberately never enter this timeline mapping.
        result.append({"action": action, "count": count, "frame_start": offset, "frame_end": offset + count,
                       "start_s": offset / fps, "end_s": (offset + count) / fps, "view_segments": view_segments})
        if take == "group-all-actions" and action == "dance":
            require(all(sorted(actors, key=lambda actor: row["actors"][actor]["position"][0]) == list(ACTORS) for row in selected), "Seven-person left-to-right order differs")
        offset += count
    require(offset == frames, "Unassigned journal rows: " + take)
    return result, actors


def dataset(folder):
    folder = folder.resolve()
    delivery_path = local_file(folder, "delivery.json")
    delivery = read(delivery_path)
    require(delivery.get("fps") == 30 and set(delivery.get("takes", {})) == set(TAKES), "Expected delivered nine-take 30fps batch")
    check_receipt = delivery["checks"]
    require(check_receipt.get("report") == "final-take-verification.json", "Only the delivered local final-take report is allowed")
    checks_path = local_file(folder, "final-take-verification.json")
    checks = read(checks_path)
    require(digest(checks_path) == check_receipt["sha256"] and check_receipt.get("failed") == 0 and checks.get("all_completed") is True
            and checks.get("failed_checks") == 0 and checks.get("completed") == len(TAKES) and checks.get("expected") == len(TAKES)
            and checks.get("pending") == [] and {r.get("take") for r in checks.get("results", [])} == set(TAKES)
            and len(checks["results"]) == len(TAKES) and all(r.get("failed") == 0 for r in checks["results"]), "Final nine-take verification is incomplete or differs")
    final = delivery["final_freeze"]
    freeze_path = local_file(folder, "final-freeze.snapshot.json")
    freeze = read(freeze_path)
    require(digest(freeze_path) == final["sha256"] and freeze.get("ready_for_recording") is True, "Final freeze is not the delivered qualified snapshot")
    models = final["models"]
    require(set(models) == {"CH_" + actor + ".glb" for actor in ACTORS} and freeze["models"] == models, "Final seven-model identity differs")
    require(freeze["runtime_files"][RUNTIME] == final["runtime_sha256"] and freeze["native_addon_files"] == final["native_files"], "Runtime/native identity differs")
    context_path = local_file(folder, "recording-context.json")
    context = read(context_path)
    require(context["models"] == models and context["final_freeze_sha256"] == final["sha256"], "Recording context differs")
    require(context["runtime_addon_proof_sha256"][RUNTIME] == final["runtime_sha256"], "Actual recording runtime differs")
    takes = []
    for take in TAKES:
        receipt = delivery["takes"][take]
        media_file = take + "/video.mp4"
        require(receipt.get("file") == media_file, "Only verified take/video.mp4 media paths are allowed")
        media = local_file(folder, media_file)
        require(digest(media) == receipt["sha256"] and receipt.get("strict_full_decode_passed") is True, "Delivered video SHA/qualification differs: " + take)
        frames = receipt["frames"]
        require(type(frames) is int and frames > 0 and receipt["duration_s"] == frames / 30, "Media duration/frame count differs")
        media_receipt_path = local_file(folder, take + "/media-verification.json")
        media_receipt = read(media_receipt_path)
        require(media_receipt.get("sha256") == receipt["sha256"] and media_receipt.get("bytes") == media.stat().st_size
                and media_receipt.get("full_decode_passed") is True and media_receipt.get("strict_full_decode_passed") is True, "Media verification SHA/bytes/decode differs: " + take)
        streams = media_receipt["probe"]["streams"]
        require(len(streams) == 1 and streams[0].get("codec_type") == "video", "Expected one silent video stream: " + take)
        stream = streams[0]
        require(int(stream["nb_frames"]) == frames and int(stream["nb_read_frames"]) == frames
                and Fraction(stream["avg_frame_rate"]) == 30 and Fraction(stream["r_frame_rate"]) == 30
                and abs(float(stream["duration"]) - frames / 30) < 1e-6
                and abs(float(media_receipt["probe"]["format"]["duration"]) - frames / 30) < 1e-6, "Media probe frames/duration/fps differ: " + take)
        journal_path = local_file(folder, take + "/movie-journal.json")
        sections, actors = take_sections(take, read(journal_path), frames, 30)
        inputs_path = local_file(folder, take + "/input-hashes.json")
        inputs = read(inputs_path)
        require(inputs["models"] == models and inputs["garment_runtime_sha256"] == final["runtime_sha256"] and inputs["final_freeze_sha256"] == final["sha256"] and inputs["recording_context_sha256"] == digest(context_path), "Take does not bind final recording source: " + take)
        takes.append({"id": take, "label": "七人同场动作" if take == "group-all-actions" else "莲 · 澪 · 和子同行" if take == "group-walk-run" else ACTORS[actors[0]] + " · 单人",
                      "file": media_file, "sha256": receipt["sha256"], "journal_sha256": digest(journal_path),
                      "input_sha256": digest(inputs_path), "media_receipt_sha256": digest(media_receipt_path), "duration_s": frames / 30, "frames": frames, "fps": 30,
                      "actors": actors, "sections": sections})
    by_take = {take["id"]: take for take in takes}
    cases = []
    for index, (actor, name) in enumerate(ACTORS.items()):
        for action, label in ACTIONS.items():
            take = by_take["group-all-actions" if action == "dance" else "solo-" + actor]
            section = next(s for s in take["sections"] if s["action"] == action)
            case = {"id": actor + "/" + action, "actor": actor, "actor_label": name, "action": action, "action_label": label,
                    "take": take["id"], "media_file": take["file"], "media_sha256": take["sha256"], "journal_sha256": take["journal_sha256"],
                    "model_sha256": models["CH_" + actor + ".glb"], "fps": 30, **section,
                    "group_position": index + 1 if action == "dance" else None,
                    "context": "七人同场 · 请看左起第%d位：%s（空、莲、春、澪、小葵、田中、和子）" % (index + 1, name) if action == "dance" else "单人实际录像 · 含该动作起势、收势与片段内停留"}
            case["source_sha256"] = identity_hash(case)
            cases.append(case)
    identity = {"delivery_sha256": digest(delivery_path), "final_verification_sha256": digest(checks_path), "freeze_sha256": final["sha256"], "context_sha256": digest(context_path),
                "models": models, "runtime_sha256": final["runtime_sha256"], "native_files": final["native_files"],
                "takes": takes, "cases": cases}
    source_hash = identity_hash(identity)
    return {"schema": "harumachi-video-dataset/v1", "id": "harumachi-video-" + source_hash[:16], "source_sha256": source_hash,
            "evidence_id": folder.name, "fps": 30, "identity": identity, "takes": takes, "cases": cases}


def build(folder):
    folder = folder.resolve()
    index = folder / "index.html"
    require(not index.exists() or MARKER in index.read_text(), "Existing non-video review index is immutable; choose the new movie evidence directory")
    data = dataset(folder)  # Validate every byte/range before writing any UI file.
    source = Path(__file__).resolve().parent
    encoded = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    template = (source / "video-index.template.html").read_text().replace("__VIDEO_DATA__", encoded)
    for name in ["video-model.js", "video-review.js", "video-review.css"]:
        shutil.copyfile(source / name, folder / name)
    shutil.copyfile(source / "review.css", folder / "video-base.css")
    index.write_text(template)
    return data


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    try:
        value = build(args.evidence)
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.error(str(error))
    print(json.dumps({"dataset_id": value["id"], "cases": len(value["cases"]), "takes": len(value["takes"]), "index": str(args.evidence.resolve() / "index.html")}, ensure_ascii=False))

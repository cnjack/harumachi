#!/usr/bin/env python3
"""Run a native visual review job with isolated saves, logs and bounded runtime.

Examples:
  python3 tools/visual_qa.py environments -- --qa-conditions=noon
  python3 tools/visual_qa.py characters -- --pilot
  python3 tools/visual_qa.py characters --out /tmp/harumachi-fishing-review -- --mode=fishing
  python3 tools/visual_qa.py animals
  python3 tools/visual_qa.py rain-probe --out /tmp/harumachi-rain-review
  python3 tools/visual_qa.py gallery
"""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "evidence/comprehensive_visual_qa_20261011"


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def save_hashes():
    folder = Path.home() / "Library/Application Support/晴町日常"
    return {str(p.relative_to(folder)): digest(p) for p in sorted(folder.rglob("*"))
            if p.is_file() and not {"logs", "shader_cache"}.intersection(p.relative_to(folder).parts)}


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def gallery(out):
    final_folders = [out / "after/environments", out / "characters", out / "after/animals", out / "activities",
                     out / "character-extra/characters", out / "character-details/characters"]
    folders = [p for p in final_folders if p.exists()]
    metadata = {}
    images = set()
    for folder in folders:
        found = False
        for manifest in folder.rglob("*.json"):
            if manifest.name not in {"manifest.json", "all.json", "native-demo.json", "demo.json", "diagnostic-manifest.json"}:
                continue
            data = json.loads(manifest.read_text())
            records = data.get("shots", data.get("screenshots", []))
            if not isinstance(records, list):
                continue
            # The lake input demo predates the common shot manifest and records
            # its pass/fail facts separately from the native PNG files.
            if manifest.name == "demo.json" and data.get("passed") and not records:
                records = [p.name for p in manifest.parent.glob("*.png")]
            for row in records:
                file = row if isinstance(row, str) else row.get("file", "")
                path = manifest.parent / file
                if path.is_file() and path.suffix.lower() == ".png":
                    images.add(path.resolve())
                    if isinstance(row, dict): metadata[path.resolve()] = row
                    else: metadata.setdefault(path.resolve(), {})
                    found = True
        if not found:
            images.update(p.resolve() for p in folder.glob("*.png"))
    images = sorted(images)
    if not images:
        images = sorted(p for p in out.rglob("*.png") if "sheets" not in p.parts and "thumbs" not in p.parts)
    try:
        from PIL import Image
    except ImportError:
        Image = None
    thumbs = out / "thumbs"
    if Image is not None:
        thumbs.mkdir(exist_ok=True)
    cards = []
    labels = {"sora": "空", "ren": "莲", "haru": "春", "mio": "澪", "aoi": "小葵", "tanaka": "田中", "kazuko": "和子",
              "wave": "挥手", "idle": "站立", "walk": "走路", "run": "跑步", "sit": "坐下", "sip": "喝茶咖啡", "dance": "跳舞",
              "bow": "鞠躬", "look": "张望", "stretch": "伸懒腰", "tend": "照料", "talk": "说话", "cheer": "欢呼",
              "morning": "早晨", "noon": "正午", "sunset": "夕阳", "night": "夜晚", "rain": "雨天", "cloudy": "阴天", "sunny": "晴天",
              "home": "自家", "community": "社区中心", "workroom": "社区中心", "plaza": "广场", "street": "街道", "store": "商店",
              "bakery": "面包房", "river": "河边", "farm": "农场", "lake": "湖边", "orange": "橘猫", "calico": "三花猫", "cat": "猫",
              "sparrow": "麻雀", "butterfly": "蝴蝶", "dragonfly": "蜻蜓", "goldfish": "金鱼", "festival": "夏祭", "gathering": "晚会分食"}
    labels.update({"reading": "阅读", "cafe": "咖啡角", "shared": "共用桌", "workshop": "灯笼制作试挂",
                   "fishing": "钓鱼", "cast": "抛竿", "bite": "咬钩", "reeling": "收线", "catch": "收获",
                   "ready": "准备", "wait": "等鱼", "reel": "收线", "landed": "收鱼", "closed": "结束恢复"})
    labels.update({"activities": "活动", "daily": "首餐麦茶与试吃牌", "resident": "晨间交谈与桌面茶托",
                   "neighbour": "邻里餐食", "meal": "餐食"})
    labels.update({"animals": "动物", "characters": "人物", "environments": "场景",
                   "front": "正面", "back": "背面", "left": "左侧", "right": "右侧",
                   "oblique": "斜侧", "high": "俯视", "low": "低机位", "angle": "机位",
                   "sitdown": "坐下", "standup": "起身", "jump": "跳跃", "sneak": "慢走", "sleep": "睡觉", "house": "自家", "indoor": "室内", "outdoor": "室外",
                   "town": "镇上", "workroom": "社区中心", "seat": "座椅", "seats": "坐姿",
                   "dance": "跳舞盆踊", "fireworks": "烟花花火", "market": "集市", "tanabata": "七夕",
                   "obon": "盂兰盆河灯", "natsu": "夏祭", "sample": "试吃"})
    capture_labels = {"authored_pose_seek": "动作定相位", "native_locomotion": "真实移动",
                      "native_context_locomotion": "真实移动", "native_fishing_modifier": "固定钓鱼状态",
                      "real_seat_modifier": "真实坐姿", "real_seat_and_living_action": "真实坐饮",
                      "real_stand_transition": "真实起身", "native_gesture": "真实手势",
                      "diagnostic_paused_activity": "活动暂停补拍", "real_world_light_weather": "实际天气光照",
                      "static_rendered_support_fixture": "静态地面支撑", "controlled_actual_asset_clip": "动物动作定相位",
                      "actual_world_decisions": "实际猫活动", "existing_static_display_geometry": "静态鱼缸摆饰",
                      "caught_goldfish_swimming": "实际游鱼"}
    for p in images:
        relative = p.relative_to(out).as_posix()
        escaped = html.escape(relative, quote=True)
        row = metadata.get(p, {})
        configuration = row.get("configuration", {})
        description = configuration.get("label", "")
        capture_label = capture_labels.get(row.get("kind", row.get("review", "")), "")
        if capture_label: description = " · ".join(filter(None, [description, capture_label]))
        tokens = str(Path(relative).with_suffix("")).lower().replace("/", "_").replace("-", "_").split("_")
        for field in ["id", "scene", "activity", "action", "weather", "subject", "clip", "view"]:
            tokens.extend(str(row.get(field, configuration.get(field, ""))).lower().replace("-", "_").split("_"))
        minute = row.get("time")
        if minute is None and isinstance(row.get("hour"), (int, float)):
            minute = row["hour"] * 60
        if isinstance(minute, (int, float)):
            tokens.append("night" if minute >= 1170 or minute < 330 else "morning" if minute < 540
                          else "sunset" if minute >= 1020 else "noon" if minute >= 660 and minute < 840 else "sunny")
        aliases = " ".join(dict.fromkeys(labels[token] for token in tokens if token in labels))
        search = html.escape(relative.lower() + " " + description + " " + aliases, quote=True)
        preview = escaped
        if Image is not None:
            thumbnail = thumbs / (hashlib.sha256(relative.encode()).hexdigest()[:20] + ".jpg")
            if not thumbnail.exists() or thumbnail.stat().st_mtime < p.stat().st_mtime:
                with Image.open(p) as source:
                    source.thumbnail((480, 270))
                    source.convert("RGB").save(thumbnail, quality=83)
            preview = html.escape(thumbnail.relative_to(out).as_posix(), quote=True)
        caption = html.escape(description + " · " + aliases) if description else html.escape(aliases)
        cards.append(f'<a class="shot" href="{escaped}" data-name="{search}">'
                     f'<img loading="lazy" src="{preview}" alt="{escaped}"><span>{caption}<br>{escaped}</span></a>')
    content = '''<!doctype html><html lang="zh"><meta charset="utf-8">
<title>明年夏祭 · 全场景视觉检查</title><style>
body{margin:24px;background:#101b26;color:#eef4fa;font:15px system-ui}h1{font-size:24px}
input{padding:12px;width:min(560px,90%);font:inherit;position:sticky;top:8px;z-index:2}
main{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:16px;margin-top:24px}
a{color:inherit;text-decoration:none;background:#20313f}img{width:100%;aspect-ratio:16/9;object-fit:contain}
span{display:block;padding:10px;overflow-wrap:anywhere}.shot[hidden]{display:none}</style>
<h1>明年夏祭 · 全场景视觉检查</h1><p>修后原生游戏截图；点击查看原图。搜索场景、人物、动作、天气或时间。动作定相位、固定钓鱼状态和活动暂停补拍用于检查细节；真实移动与活动流程单独记录。旧失败与试拍保留在证据目录。</p>
<input id="filter" placeholder="例如 社区中心 / 小葵 / 挥手 / 雨天"><main>'''
    content += "\n".join(cards)
    content += r'''</main><script>filter.oninput=()=>{const q=filter.value.toLowerCase().trim().split(/\s+/);
document.querySelectorAll('.shot').forEach(x=>x.hidden=!q.every(word=>x.dataset.name.includes(word)))}</script></html>'''
    (out / "index.html").write_text(content)
    write(out / "gallery.json", {"screenshots": len(images), "gallery": str(out / "index.html"),
                                 "files": [{"file": p.relative_to(out).as_posix(), "sha256": digest(p)} for p in images]})
    print(f"Gallery: {len(images)} images, {out / 'index.html'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("job", choices=["environments", "model-diversity", "characters", "animals", "activities", "rain-probe", "gallery"])
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--project", type=Path, default=ROOT / "game")
    parser.add_argument("--limit", type=int, default=2400)
    parser.add_argument("--activity", default="workshop,gathering,resident-morning,daily-life,neighbour-meal,bakery-sample,festival,lake")
    args, extra = parser.parse_known_args()
    if extra[:1] == ["--"]:
        extra = extra[1:]
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    if args.job == "gallery":
        gallery(out)
        return
    if args.job == "activities":
        for activity in args.activity.split(","):
            if activity not in {"workshop", "gathering", "resident-morning", "daily-life", "neighbour-meal", "bakery-sample", "festival", "lake"}:
                raise SystemExit("Unknown activity: " + activity)
            native_activity(out, activity, args.limit, args.project.resolve())
        return
    output = out / args.job
    output.mkdir(exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    logs = output / "logs"
    logs.mkdir(exist_ok=True)
    log_path = logs / (stamp + ".log")
    command = [str(ROOT / "tools/godot"), "--path", str(args.project.resolve()),
               "--resolution", "1280x720", "-t", "--position", "80,80"]
    if args.job == "rain-probe":
        command += ["res://scenes/tools/rain_visual_probe.tscn", "--", "--out=" + str(output)]
    elif args.job == "environments":
        command += ["res://scenes/main.tscn", "--", "--shots=" + str(output),
                    "--qa-environments=1", "--clean=1"]
    elif args.job == "model-diversity":
        command += ["res://scenes/main.tscn", "--", "--shots=" + str(output),
                    "--qa-model-diversity=1", "--clean=1"]
    elif args.job == "characters":
        command += ["res://scenes/main.tscn", "--", "--qa-characters", "--out=" + str(output)]
    else:
        command += ["res://scenes/main.tscn", "--", "--qa-animals=" + str(output)]
        if extra and not extra[0].startswith("--"):
            extra[0] = "--qa-animals-mode=" + extra[0]
    command += extra
    before = save_hashes()
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="harumachi-visual-save-") as save_dir:
        with log_path.open("w") as log:
            process = subprocess.Popen(command, cwd=ROOT, env=dict(os.environ, HARUMACHI_SAVE_DIR=save_dir),
                                       stdout=log, stderr=subprocess.STDOUT)
            try:
                code = process.wait(timeout=args.limit)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                code = 124
    contents = log_path.read_text(errors="replace")
    after = save_hashes()
    write(logs / (stamp + "-save-hashes.json"), {"before": before, "after": after,
          "changed": [key for key in sorted(before.keys() | after.keys()) if before.get(key) != after.get(key)]})
    record = {"job": args.job, "command": command, "exit_code": code,
              "seconds": round(time.monotonic() - started, 3), "log": str(log_path),
              "script_errors": "SCRIPT ERROR" in contents, "default_save_unchanged": before == after,
              "pngs": len(list(output.rglob("*.png")))}
    record["shader_errors"] = any(s in contents for s in ["SHADER ERROR", "Shader compilation failed", "Failed to compile shader"])
    record["render_errors"] = any(s in contents for s in ["instance_set_transform", "!v.is_finite()", "!p_transform.is_finite()"] )
    write(logs / (stamp + ".json"), record)
    print(json.dumps(record, ensure_ascii=False, indent=2))
    if code or record["script_errors"] or record["shader_errors"] or record["render_errors"] or not record["default_save_unchanged"]:
        print(contents[-6000:], file=sys.stderr)
        raise SystemExit(1)


def native_activity(out, activity, limit, project):
    output = out / "activities" / activity
    output.mkdir(parents=True, exist_ok=True)
    log_path = output / "native.log"
    command = [str(ROOT / "tools/godot"), "--path", str(project), "--resolution", "1280x720",
               "-t", "--position", "80,80", "res://scenes/main.tscn", "--", "--" + ("daily-life" if activity == "bakery-sample" else activity) + "-demo",
               "--evidence=" + str(output), "--qa-multiangle"]
    if activity == "festival":
        command = command[:command.index("--") + 1] + ["--qa-festival=" + str(output)]
    elif activity == "lake":
        command = command[:command.index("--") + 1] + ["--lake-demo", "--lake-demo-out=" + str(output), "--qa-multiangle"]
    elif activity == "bakery-sample":
        command.append("--qa-bakery-sample")
    before = save_hashes()
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="harumachi-activity-save-") as save_dir:
        with log_path.open("w") as log:
            try:
                result = subprocess.run(command, cwd=ROOT, env=dict(os.environ, HARUMACHI_SAVE_DIR=save_dir),
                                        stdout=log, stderr=subprocess.STDOUT, timeout=limit)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = 124
    contents = log_path.read_text(errors="replace")
    report_path = output / ("demo.json" if activity == "lake" else "native-demo.json")
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    record = {"activity": activity, "command": command, "exit_code": code,
              "seconds": round(time.monotonic() - started, 3), "script_errors": "SCRIPT ERROR" in contents,
              "default_save_unchanged": before == save_hashes(), "passed": report.get("passed", False),
              "pngs": len(list(output.glob("*.png")))}
    record["shader_errors"] = any(s in contents for s in ["SHADER ERROR", "Shader compilation failed", "Failed to compile shader"])
    record["render_errors"] = any(s in contents for s in ["instance_set_transform", "!v.is_finite()", "!p_transform.is_finite()"] )
    write(output / "process.json", record)
    print(json.dumps(record, ensure_ascii=False), flush=True)
    if code or record["script_errors"] or record["shader_errors"] or record["render_errors"] or not record["default_save_unchanged"] or not record["passed"]:
        print(contents[-4000:], file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Run the isolated material/light POC on an existing display, or build its review gallery."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = ROOT / "evidence/material_light_refine_20261025/round4"
CONDITIONS = "morning,noon,overcast,rain,sunset,night"
MODES = "baseline,material,lighting,combined"


def save_hashes():
    folder = Path.home() / "Library/Application Support/晴町日常"
    return {str(p.relative_to(folder)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(folder.rglob("*")) if p.is_file()
            and not {"logs", "shader_cache"}.intersection(p.relative_to(folder).parts)}


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def run(args):
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    before = save_hashes()
    command = [str(ROOT / "tools/godot"), "--path", str(ROOT / "game"),
               "--screen", "0", "-t", "--position", "60,80", "--resolution", args.resolution,
               "--audio-driver", "Dummy", "--script", "res://scripts/tools/material_light_poc_entry.gd",
               "--", "--graphics-profile=quality", "--graphics-benchmark", "--poc-orbit=" + str(args.orbit)]
    if args.action == "capture":
        command += ["--poc-out=" + str(out), "--poc-scenes=" + args.scenes,
                    "--poc-conditions=" + args.conditions, "--poc-modes=" + args.modes,
                    "--poc-sample-frames=" + str(args.sample_frames)]
    if args.uncapped:
        command.append("--benchmark-uncapped")
    if args.verbose:
        command.insert(1, "--verbose")
    started = time.monotonic()
    code = -1
    with tempfile.TemporaryDirectory(prefix="harumachi-material-light-") as save:
        with (out / "run.log").open("w") as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                       env=dict(os.environ, HARUMACHI_SAVE_DIR=save))
            write(out / "process.json", {"pid": process.pid, "command": command})
            try:
                while process.poll() is None:
                    time.sleep(.5)
                    current_log = (out / "run.log").read_text()
                    if "SCRIPT ERROR" in current_log or "SHADER ERROR" in current_log:
                        process.terminate()
                        break
                    if time.monotonic() - started > args.timeout:
                        raise subprocess.TimeoutExpired(command, args.timeout)
                code = process.wait(timeout=10)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    after = save_hashes()
    log_text = (out / "run.log").read_text()
    errors = [line for line in log_text.splitlines()
              if any(word in line for word in ("SCRIPT ERROR", "SHADER ERROR", "Parse Error", "ERROR:"))]
    report = {"exit_code": code, "seconds": time.monotonic() - started,
              "default_save_unchanged": before == after, "default_save_files": len(before),
              "audio_driver": "Dummy", "existing_screen": 0, "virtual_display_created": False,
              "errors": errors, "command": command}
    write(out / "run.json", report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if code != 0 or before != after or errors:
        print(log_text[-8000:])
        raise SystemExit(1)
    if args.action == "capture":
        manifest = json.loads((out / "manifest.json").read_text())
        expected = {(s, c, m) for s in args.scenes.split(",")
                    for c in args.conditions.split(",") for m in args.modes.split(",")}
        actual = {(r["scene"], r["condition"]["id"], r["mode"]) for r in manifest["shots"]}
        if expected != actual or len(manifest["shots"]) != len(expected):
            raise SystemExit("Missing, duplicate or unexpected capture combinations")
        if not all((out / row["file"]).is_file() for row in manifest["shots"]):
            raise SystemExit("Missing native screenshot")
        preserved = manifest.get("source_geometry_and_collisions_preserved", manifest["geometry_unchanged"])
        if not preserved or any(row["frames"] < 60 for row in manifest["shots"]):
            raise SystemExit("Source geometry/collisions could not be restored or native frames did not advance")
        gallery(out)


def gallery(out):
    manifest = json.loads((out / "manifest.json").read_text())
    manifest["history"] = []
    versions = [("initial", "优化前 POC", ROOT / "evidence/material_light_poc_20261025/final")]
    versions += [(f"round{i}", f"第 {i} 轮", ROOT / f"evidence/material_light_refine_20261025/round{i}") for i in (1, 2, 3)]
    for ident, label, folder in versions:
        if folder.resolve() == out or not (folder / "manifest.json").exists():
            continue
        shots = json.loads((folder / "manifest.json").read_text())["shots"]
        combined = [dict(r, file=os.path.relpath(folder / r["file"], out))
                    for r in shots if r["mode"] == "combined"]
        manifest["history"].append({"id": ident, "label": label, "shots": combined})
    payload = json.dumps(manifest, ensure_ascii=False).replace("</", "<\\/")
    for scene in ("bakery", "lake"):
        shutil.copy2(ROOT / f"art/direction/material_light_20261025/{scene}-direction.png",
                     out / f"concept-{scene}.png")
    html = """<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>明年夏祭 · 材质与光影 POC</title>
<style>
:root{color-scheme:dark;font-family:system-ui,sans-serif;background:#101924;color:#e8edf3}body{max-width:1500px;margin:32px auto;padding:0 24px}h1{font-size:28px;font-weight:600;margin-bottom:8px}p{color:#b6c4d4;line-height:1.6}nav{display:flex;gap:12px;flex-wrap:wrap;margin:24px 0}select,button{font:inherit;padding:9px 14px;background:#233345;border:1px solid #496077;color:inherit;border-radius:6px}.stage{position:relative;aspect-ratio:16/9;overflow:hidden;background:#080c12}.stage img{display:block;position:absolute;width:100%;height:100%;object-fit:contain}.stage .after{clip-path:inset(0 0 0 50%)}.line{position:absolute;top:0;bottom:0;left:50%;width:2px;background:white;pointer-events:none}.labels{display:flex;justify-content:space-between;margin:10px 0}.range{width:100%;accent-color:#e6bc7d}.grid{display:grid;grid-template-columns:repeat(2,1fr);gap:16px;margin:26px 0}.grid img{width:100%;display:block}figure{margin:0}figcaption{padding:7px 0;color:#c5d1de}small{color:#93a7bd}a{color:#e8c28d}.hint{border-left:3px solid #e8c28d;padding-left:14px}details{line-height:1.6;margin-top:20px}button{cursor:pointer}@media(max-width:700px){.grid{grid-template-columns:1fr}body{padding:0 12px}}
</style>
<h1>材质与光影 / 两处实景迭代</h1>
<p>真实 Godot 4.8-dev7 渲染。选择原版或此前轮次，拖动分隔线比较；下方四张图拆开材质、局部模型细化与光照的贡献。</p>
<nav><select id="scene" aria-label="场景"></select><select id="condition" aria-label="天气与时间"></select><select id="version" aria-label="对照轮次"><option value="baseline">正式游戏原版</option></select><select id="mode" aria-label="比较模式"><option value="combined">完整候选</option><option value="material">材质与局部细化</option><option value="lighting">只改灯光</option></select><button id="original">打开候选原图</button></nav>
<div class="labels"><span id="before-label">原版</span><span id="candidate">完整候选</span></div>
<div class="stage"><img id="before" alt="原版实景"><img id="after" class="after" alt="候选实景"><div class="line"></div></div>
<input class="range" id="wipe" type="range" min="0" max="100" value="50" aria-label="对照分隔线">
<small id="meta"></small><div class="grid" id="grid"></div>
<p class="hint">这是待审的视觉方案，未替换正式游戏或交付包。帧率取自静态场景短样本，不能代表完整游戏性能；动态树叶、水面和雨滴的相位可能不同。</p>
<details><summary>四轮改动与边界</summary><p>第一轮：树冠分组明暗、草地与天空。第二轮：接缝、草叶透光、木材与夜景可读性。第三轮：水面岸树／桥身倒影、桥下阴影、远景树冠。第四轮：独立桥模型倒角、天空构图、阴雨配色和月光方向。增加 3615 丛近岸草；桥候选保留原材质槽和碰撞，正式 GLB 未改。原图没有后期修饰。</p><p>水面 SSR 只能反射屏幕内的不透明物体，离屏时回退天空；这仍有边缘缺失和透明物体缺失的限制。夜间月亮、主光和水面高光采用统一的美术方向，不是天文模拟。</p></details>
<details open><summary>imagegen 视觉方向图（生成参考，不是游戏实拍）</summary><p>从场景截图生成的四时天气方向，顺序为晴午、雨天、夕照、夜晚。用于比较色彩、明暗、材质和空间层次；生成图调整了树形、建筑比例与局部细节，不能当作引擎已经达到的效果。</p><img id="concept" alt="imagegen 方向图，非游戏画面" style="width:100%"></details>
<script>const data=PAYLOAD;
const names={bakery:'面包房门前',lake:'湖畔木栈桥'}, modes={baseline:'正式游戏原版',material:'材质与局部细化',lighting:'只改灯光',combined:'完整候选'};
const byId=id=>document.getElementById(id), scene=byId('scene'),condition=byId('condition'),mode=byId('mode'),version=byId('version');
for(const v of data.history)version.add(new Option(v.label,v.id));
if(data.history.some(v=>v.id==='initial'))version.value='initial';
for(const id of [...new Set(data.shots.map(x=>x.scene))])scene.add(new Option(names[id],id));
for(const row of data.shots){if(![...condition.options].some(x=>x.value===row.condition.id))condition.add(new Option(row.condition.label,row.condition.id));}
if([...condition.options].some(x=>x.value==='noon'))condition.value='noon';
function find(m){return data.shots.find(x=>x.scene===scene.value&&x.condition.id===condition.value&&x.mode===m)}
function oldShot(id){return data.history.find(v=>v.id===id)?.shots.find(x=>x.scene===scene.value&&x.condition.id===condition.value)}
function refresh(){for(const option of version.options)option.disabled=option.value!=='baseline'&&!oldShot(option.value);if(version.selectedOptions[0].disabled)version.value='baseline';byId('concept').src='concept-'+scene.value+'.png';const b=oldShot(version.value)||find('baseline'),a=find(mode.value)||find('baseline');byId('before').src=b.file;byId('before-label').textContent=version.selectedOptions[0].text;byId('after').src=a.file;byId('candidate').textContent=modes[a.mode];byId('meta').textContent=`${a.size.join(' × ')} · ${data.engine.string} · ${a.frames} 帧 / ${a.seconds.toFixed(2)} 秒 · ${a.fps.toFixed(1)} FPS（静态短样本）`;byId('grid').replaceChildren();for(const m of Object.keys(modes)){const r=find(m);if(!r)continue;const f=document.createElement('figure'),img=document.createElement('img'),caption=document.createElement('figcaption');img.src=r.file;img.alt=modes[m];img.loading='lazy';caption.textContent=modes[m];f.append(img,caption);byId('grid').append(f)}}
for(const el of [scene,condition,mode,version])el.onchange=refresh;
byId('wipe').oninput=e=>{byId('after').style.clipPath=`inset(0 0 0 ${e.target.value}%)`;document.querySelector('.line').style.left=e.target.value+'%'};
byId('original').onclick=()=>window.open((find(mode.value)||find('baseline')).file,'_blank');refresh();
</script></html>""".replace("PAYLOAD", payload)
    (out / "index.html").write_text(html)
    print(out / "index.html")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["capture", "review", "gallery"], default="review", nargs="?")
    parser.add_argument("--out", type=Path, default=DEFAULT)
    parser.add_argument("--scenes", default="bakery,lake")
    parser.add_argument("--conditions", default=CONDITIONS)
    parser.add_argument("--modes", default=MODES)
    parser.add_argument("--resolution", default="1600x900")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--uncapped", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--orbit", type=float, default=0)
    parser.add_argument("--sample-frames", type=int, default=60)
    args = parser.parse_args()
    if args.sample_frames < 60:
        parser.error("--sample-frames must be at least 60")
    if not -35 <= args.orbit <= 35:
        parser.error("--orbit must be between -35 and 35 degrees")
    for values, allowed in ((args.scenes, "bakery,lake"), (args.conditions, CONDITIONS), (args.modes, MODES)):
        if not set(values.split(",")) <= set(allowed.split(",")):
            parser.error("Unknown scene, condition or mode")
    if args.action == "capture" and "baseline" not in args.modes.split(","):
        parser.error("Capture comparisons require baseline in --modes")
    if args.action == "gallery": gallery(args.out.resolve())
    else: run(args)


if __name__ == "__main__":
    main()

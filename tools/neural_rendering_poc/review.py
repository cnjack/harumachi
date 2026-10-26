#!/usr/bin/env python3
"""Build a local, full-resolution before/after viewer from completed measurements."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("evidence", type=Path)
args = parser.parse_args()
out = args.evidence.resolve()
rows = json.loads((out / "measurements.json").read_text())
payload = json.dumps(rows, ensure_ascii=False).replace("</", "<\\/")
content = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>明年夏祭 · 两场景神经渲染对照</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#10151a;color:#eaf0f3;font:16px/1.6 system-ui,sans-serif}
main{max-width:1340px;margin:36px auto;padding:0 24px}h1{font-size:28px;line-height:1.3;margin:0 0 12px}
h2{font-size:21px;margin:32px 0 8px}p{color:#b9c7d1;margin:8px 0}a{color:#a6d4ff}
.controls{display:flex;gap:14px;align-items:center;flex-wrap:wrap;margin:22px 0}
select,button{font:inherit;padding:8px 12px;background:#23313d;color:#fff;border:1px solid #4d6578;border-radius:6px}
.image{position:relative;aspect-ratio:16/9;overflow:hidden;background:#000}.image img{position:absolute;width:100%;height:100%;object-fit:contain}
.before{clip-path:inset(0 50% 0 0)}.divider{position:absolute;top:0;bottom:0;left:50%;border-left:2px solid white;pointer-events:none}
.labels{display:flex;justify-content:space-between;font-size:14px;color:#fff;margin:8px 0}
input[type=range]{width:100%;accent-color:#84c6ee;margin:14px 0}video{width:100%;display:block;background:#000}
.metrics{font-variant-numeric:tabular-nums;color:#9dcced}details{margin:16px 0 32px}summary{cursor:pointer;color:#b6d8f3}
footer{border-top:1px solid #3c4a55;padding-top:20px;margin-top:35px;color:#9cafbe;font-size:14px}
</style><main>
<h1>明年夏祭 · 两场景神经渲染对照</h1>
<p>2026-10-26 · Apple M5 Max · 游戏原生 1280 × 720 · 均衡画质</p>
<p>使用 gtrg55/dlss5-macos-overlay 的实际 MLX / Metal 推理。拖动分隔线查看原图与处理结果；这是独立实验，正式游戏未接入。</p>
<div class="controls"><label>效果 <select id="variant"><option value="natural-512">Natural · 512</option><option value="natural-768" selected>Natural · 768</option><option value="cinematic-768">Cinematic · 768</option></select></label>
<button id="original">全部原图</button><button id="half">左右对照</button><button id="result">全部结果</button></div>
<div id="scenes"></div>
<footer>处理速度包括缩放、估算光流、神经网络与合成，不包括游戏渲染、屏幕捕获、显示和文件读写。视频以 30 FPS 播放，属于离线逐帧处理，不能当作实时运行速度。Windows NeuralScreen 未在 Windows 硬件上实测；人物、UI、长时间游玩和实时覆盖延迟也未验证。</footer>
</main><script>
const rows=__DATA__;
const names={bakery_scene_front:'面包房街景',lake_pier:'湖边栈桥'};
const container=document.querySelector('#scenes');
for(const [id,title] of Object.entries(names)){
 const section=document.createElement('section');section.dataset.scene=id;
 section.innerHTML=`<h2>${title}</h2><p class="metrics"></p><div class="labels"><span>原版游戏</span><span>神经渲染</span></div>
 <div class="image"><img class="after" alt="神经渲染结果"><img class="before" src="source/${id}.png" alt="原版游戏画面"><div class="divider"></div></div>
 <input aria-label="${title}前后对照分隔线" type="range" min="0" max="100" value="50">
 <p><a class="full" target="_blank">打开完整处理图</a> · <a href="source/${id}.png" target="_blank">打开完整原图</a></p>
 <details><summary>观看实际运镜对照：左原图 / 右 Natural 768</summary><p>每段 90 帧、3 秒：前 1 秒固定镜头，后 2 秒相机平移。离线推理后按原时序播放。</p>
 <video muted loop playsinline controls preload="none" src="videos/${id}-comparison.mp4"></video></details>`;
 section.querySelector('input').addEventListener('input',e=>split(section,Number(e.target.value)));
 container.append(section);
}
function split(section,value){section.querySelector('.before').style.clipPath=`inset(0 ${100-value}% 0 0)`;section.querySelector('.divider').style.left=value+'%';section.querySelector('input').value=value;}
function refresh(){const variant=document.querySelector('#variant').value;for(const section of container.children){const id=section.dataset.scene;const row=rows.find(r=>r.scene===id&&r.variant===variant);const src=`results/${id}/${variant}/processed.png`;section.querySelector('.after').src=src;section.querySelector('.full').href=src;section.querySelector('.metrics').textContent=`网络工作尺寸 ${row.processingSize.join(' × ')} · 平均处理 ${row.averageMilliseconds.toFixed(1)} ms / 帧 · ${row.processingFPS.toFixed(1)} 处理帧 / 秒 · 强度 ${row.intensity}`;}}
document.querySelector('#variant').addEventListener('change',refresh);
for(const [id,value] of [['original',100],['half',50],['result',0]])document.getElementById(id).onclick=()=>{for(const section of container.children)split(section,value);};
refresh();
</script></html>'''
(out / "index.html").write_text(content.replace("__DATA__", payload))
print(out / "index.html")

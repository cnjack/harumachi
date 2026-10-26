#!/usr/bin/env python3
"""Show measured live results and recordings; do not relabel preview latency as overlay latency."""
import argparse
import html
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('evidence', type=Path)
parser.add_argument('--prefix', default='live')
args = parser.parse_args()
root = args.evidence.resolve()
rows = json.loads((root / f'{args.prefix}-summary.json').read_text())
if any(r['presentation_scope'] not in ('none', 'preview') for r in rows):
    raise SystemExit('This report template describes preview measurements; inspect other presentation targets first.')

def value(row, key, stat='p50'):
    data = row.get(key)
    return f'{data[stat]:.1f}' if data else '—'

body = []
for scene, title in [('bakery_scene_front', '面包房街景'), ('lake_pier', '湖边栈桥')]:
    body.append(f'<section><h2>{title}</h2><table><thead><tr><th>配置</th><th>游戏 FPS</th><th>增强预览 FPS</th><th>处理 ms</th><th>捕获→预览显示 ms<br>中位 / P95</th></tr></thead><tbody>')
    modes = [('baseline', '原生'), ('bypass', '仅捕获显示'), ('natural-512-60', 'Natural 512 · 捕获 60'), ('natural-768-60', 'Natural 768 · 捕获 60'), ('natural-512-30', 'Natural 512 · 捕获 30'), ('baseline-repeat', '原生复测')]
    for mode, label in modes:
        match = [r for r in rows if r['scene'] == scene and r['mode'] == mode]
        if not match:
            continue
        row = match[0]
        shown = f"{row['overlay_presented_fps']:.1f}" if row['presented_frames'] else '—'
        body.append(f'<tr><td>{label}</td><td>{row["game_fps"]:.1f}</td><td>{shown}</td><td>{value(row,"processing_ms")}</td><td>{value(row,"capture_to_present_ms")} / {value(row,"capture_to_present_ms","p95")}</td></tr>')
    body.append('</tbody></table>')
    for mode in ['natural-512-60', 'natural-768-60']:
        stem = f'{args.prefix}-{scene}-{mode}-recording'
        if (root / (stem + '.mp4')).exists():
            body.append(f'<details {"open" if "512" in mode else ""}><summary>{html.escape(mode)} · 8 秒实时运镜</summary><p>左：原版同一帧；右：增强结果。实际实时输出，保留捕获时间戳，无补帧。录屏在计时结束后另跑。</p><video controls muted loop playsinline preload="metadata" poster="{stem}.png" src="{stem}.mp4"></video></details>')
    body.append('</section>')
page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>明年夏祭 · Mac 实时神经渲染测试</title><style>
*{box-sizing:border-box}body{margin:0;background:#11171c;color:#e4edf1;font:16px/1.65 system-ui,sans-serif}main{max-width:1280px;margin:38px auto;padding:0 24px}h1{font-size:29px;line-height:1.3}h2{font-size:23px;margin:40px 0 14px}p{color:#bdcbd4}table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}th,td{text-align:right;padding:10px 12px;border-bottom:1px solid #394650}th:first-child,td:first-child{text-align:left}th{color:#a9c9dc;font-weight:500}details{margin:22px 0}summary{cursor:pointer;color:#bee5fa}video{width:100%;display:block;background:#000}a{color:#a9dbfa}.scope{border-left:3px solid #e6bb77;padding:10px 20px;background:#1e272d}footer{margin:35px 0 20px;border-top:1px solid #394650;padding-top:16px;color:#aebec9} @media(max-width:700px){main{padding:0 14px}td,th{padding:8px 4px;font-size:13px}}
</style><main><h1>明年夏祭 · Mac 实时神经渲染测试</h1>
<p>2026-10-26 · Apple M5 Max / 128 GB · Godot 4.8-dev7 · 均衡 1280 × 720 / 60 Hz</p>
<p>原生游戏与用户指定的 macOS MLX 程序同时运行。每组预热 8 秒、计时 30 秒，真实时间运镜；未改正式游戏或发布包。</p>
<div class="scope"><strong>已验证：并排实时增强预览。</strong><p>直接覆盖窗口的 Metal 呈现时间为零，游戏区域采样也未确认显示延迟后的增强帧，因此不把它标成可用的覆盖方案。下表“显示”专指实际增强预览窗口，不是输入到光子的硬件延迟。</p></div>
__BODY__<footer>512 / 768 指网络工作长边；实际捕获包含窗口标题栏，为 1280 × 784，输出保持该大小。处理 FPS、游戏 FPS、预览显示 FPS 分别采样；显示探针全程启用，功耗、真人操作、快速镜头和长时间游玩未测。<p><a href="live-summary.json">逐组测量数据</a> · <a href="verification.json">验证记录</a></p></footer></main></html>'''
(root / 'index.html').write_text(page.replace('__BODY__', '\n'.join(body)))
print(root / 'index.html')

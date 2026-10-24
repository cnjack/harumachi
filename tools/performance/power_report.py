#!/usr/bin/env python3
"""Build a local, self-contained-data comparison page from power_compare output."""
import argparse
import html
import json
from pathlib import Path

PROFILES = ['before', 'quality', 'balanced', 'eco']
LABELS = {'before': '优化前', 'quality': '原画质 · 60帧', 'balanced': '均衡 · 60帧', 'eco': '节能 · 30帧'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    args = parser.parse_args()
    data = {'labels': LABELS, 'raw': {}, 'sustained': {}}
    for kind in ['raw', 'sustained', 'movement-repeat-raw', 'movement-play']:
        if kind.startswith('movement') and not (args.evidence / kind).exists():
            continue
        data.setdefault(kind, {})
        for profile in (['before', 'quality', 'eco'] if kind == 'movement-repeat-raw' else PROFILES):
            file = args.evidence / kind / profile / 'result.json'
            result = json.loads(file.read_text())
            process = json.loads((file.parent / 'process.json').read_text())
            expected = {'street', 'plaza_day', 'farm', 'lake', 'store_interior', 'bedroom', 'plaza_festival_night', 'street_walk', 'street_run'} if kind == 'raw' else ({'farm', 'plaza_festival_night'} if kind == 'sustained' else {'street_walk', 'street_run'})
            actual = [row['view'] for row in result['samples']]
            if result['status'] != 'complete' or process.get('exit') != 0 or process.get('failure') or set(actual) != expected or len(actual) != len(expected):
                raise ValueError('Incomplete or failed comparison: ' + str(file))
            if kind == 'sustained' and any(row.get('process_cpu_percent') is None for row in result['samples']):
                raise ValueError('Missing CPU measurements: ' + str(file))
            data[kind][profile] = [{key: value for key, value in row.items()
                                   if key in ['view', 'label', 'fps_mean', 'median_ms', 'p95_ms', 'render_gpu_ms',
                                              'rendered_image_size', 'process_cpu_percent', 'thermal_states',
                                              'gpu_ms_per_second_estimate', 'graphics', 'elapsed_seconds', 'rendered_frames', 'physics_frames', 'player_travel_m']}
                                  for row in result['samples']]
    context_file = args.evidence / 'report-context.json'
    data['context'] = json.loads(context_file.read_text()) if context_file.exists() else {}
    durations = [row['elapsed_seconds'] for rows in data['sustained'].values() for row in rows]
    duration_text = str(round(min(durations))) if round(min(durations)) == round(max(durations)) else f'{min(durations):.0f}–{max(durations):.0f}'
    (args.evidence / 'comparison.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>明年夏祭 · 性能与画面对照</title><style>
:root{color-scheme:light;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;color:#233535;background:#f6f5f0}*{box-sizing:border-box}body{margin:0 auto;max-width:1280px;padding:40px 28px 80px}h1{font-size:34px;margin-bottom:12px}h2{margin-top:42px;font-size:23px}p{line-height:1.8}small,.note{color:#5d6c68}a{color:#15665a}select,button{font:inherit;padding:9px 14px;background:white;border:1px solid #b7c6be;border-radius:7px}label{display:inline-flex;gap:10px;align-items:center;margin:8px 24px 12px 0}.stage{position:relative;aspect-ratio:16/9;overflow:hidden;background:#dce2df;border-radius:10px}.stage img{position:absolute;inset:0;width:100%;height:100%;object-fit:contain}.tag{position:absolute;top:15px;background:#fffffff0;border-radius:5px;padding:7px 11px;z-index:2}.left{left:15px}.right{right:15px}.slider{width:100%;margin:15px 0;accent-color:#25745b}.line{position:absolute;top:0;bottom:0;width:2px;background:white;left:50%;box-shadow:0 0 3px #333}.scroll{overflow:auto}table{border-collapse:collapse;width:100%;min-width:800px;margin-top:15px;font-variant-numeric:tabular-nums}th,td{border-bottom:1px solid #d6ded8;padding:12px 13px;text-align:left;white-space:nowrap}th{background:#e7ede7;color:#435b50}td small{display:block;margin-top:5px}.good{color:#17664b}.regression{color:#9a493a}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}.card{border-top:3px solid #487c65;padding:14px 0}.card strong{font-size:27px;display:block;margin-bottom:6px}details{margin-top:32px}summary{cursor:pointer;font-weight:600}.native-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}.native-grid figure{margin:0}.native-grid img{display:block;width:100%;border-radius:6px}.native-grid figcaption{padding-top:7px;color:#435b50}@media(max-width:650px){body{padding:20px 14px}.native-grid{grid-template-columns:1fr}.cards{grid-template-columns:1fr}h1{font-size:27px}}
</style><h1>明年夏祭 · 性能与画面对照</h1>
<p>__CONTEXT__三个新档位均可在标题或暂停菜单的「设置 → 画面与耗电」切换，默认均衡。</p>
<div class="cards"><div class="card"><strong>60 帧</strong>原画质与均衡游玩上限</div><div class="card"><strong>30 帧</strong>节能档与暂停画面上限</div><div class="card"><strong>10 / 5 帧</strong>后台 / 最小化上限</div></div>
<h2>同机位画面</h2><label>场景 <select id="scene"></select></label><label>对照档位 <select id="profile"><option value="balanced">均衡 · 60帧</option><option value="eco">节能 · 30帧</option><option value="quality">原画质 · 60帧</option></select></label>
<div class="stage"><img id="after" alt="优化后的实际游戏截图"><img id="before" alt="优化前的实际游戏截图" style="clip-path:inset(0 50% 0 0)"><span class="tag left">优化前</span><span id="after-label" class="tag right">均衡</span><div id="line" class="line"></div></div><input id="split" class="slider" type="range" min="0" max="100" value="50" aria-label="拖动比较优化前后画面"><p class="note">拖动分界线对照。人物、风和环境动画持续运行，截图不是相同动画相位；走跑场景按同样的六秒路线采样。降低的是 3D 分辨率，HUD 和菜单保留原输出分辨率。<a id="original-link" target="_blank">查看原始截图</a> · <a id="new-link" target="_blank">查看对照截图</a></p>
<h2>单帧计算成本</h2><p class="note">此组关闭限帧与垂直同步，比较每一帧要做多少工作。主值为 GPU 渲染时间中位数，越小越好；小字为实际出帧率。它不是正常游玩的目标帧率；短时采样仍受系统频率与帧调度影响。</p><div class="scroll"><table id="raw"></table></div>
<h2>正常限帧下的持续负载</h2><p class="note">农园与夏祭夜晚分别连续采样 __DURATION__ 秒，各档串行运行。CPU 100% 表示占用约一个 CPU 核心。GPU 毫秒/秒为单帧 GPU 时间 × 实际帧率的估算，不能换算成瓦数或温度。</p><div class="scroll"><table id="sustained"></table></div>
<section id="movement-section" hidden><h2>移动专项复测</h2><p class="note">初测原画质步行和节能跑步出现单帧 GPU 耗时上升，因此另开进程复测。下表保留两次数据，正常游玩另用各自帧率上限跑相同六秒路线；短时数据会随系统频率与帧调度波动。</p><div class="scroll"><table id="movement"></table></div></section><p id="thermal" class="note"></p><p class="note">本机没有取得需要管理员权限的功耗/温度数据，因此这里只报告计算负载。机身降温幅度、长时间手感与个人画质偏好仍需实际试玩。原画质保留完整场景精度；均衡降低远处细节与阴影成本；节能进一步降低 3D 分辨率、部分光照效果和帧率。</p><details><summary>查看新设置与人物近景</summary><p class="note">以下是三个新档位的实际近景；人物源模型和动作保持一致，截图动画相位不同。点击可查看完整分辨率。</p><div class="native-grid"><figure><a href="native-review-final-v7/mio_near_quality.png" target="_blank"><img loading="lazy" src="native-review-final-v7/mio_near_quality.png" alt="原画质档位的人物近景"></a><figcaption>原画质 · 60帧</figcaption></figure><figure><a href="native-review-final-v7/mio_near_balanced.png" target="_blank"><img loading="lazy" src="native-review-final-v7/mio_near_balanced.png" alt="均衡档位的人物近景"></a><figcaption>均衡 · 60帧</figcaption></figure><figure><a href="native-review-final-v7/mio_near_eco.png" target="_blank"><img loading="lazy" src="native-review-final-v7/mio_near_eco.png" alt="节能档位的人物近景"></a><figcaption>节能 · 30帧</figcaption></figure><figure><a href="native-review-final-v7/game_settings.png" target="_blank"><img loading="lazy" src="native-review-final-v7/game_settings.png" alt="游戏内的画面与耗电设置"></a><figcaption>暂停 → 设置 → 画面与耗电</figcaption></figure></div></details><p><a href="comparison.json">汇总数据</a> · <a href="native-review-final-v7/result.json">原生交互检查</a></p>
<script>const data=__DATA__;
const scene=document.getElementById('scene'),profile=document.getElementById('profile');
for(const row of data.raw.before){const option=document.createElement('option');option.value=row.view;option.textContent=row.label;scene.append(option)}
scene.value='farm';function show(){const name=scene.value,p=profile.value;document.getElementById('before').src=`raw/before/${name}.png`;document.getElementById('after').src=`raw/${p}/${name}.png`;document.getElementById('after-label').textContent=data.labels[p];document.getElementById('original-link').href=`raw/before/${name}.png`;document.getElementById('new-link').href=`raw/${p}/${name}.png`};scene.onchange=profile.onchange=show;show();
document.getElementById('split').oninput=event=>{const value=Number(event.target.value);document.getElementById('before').style.clipPath=`inset(0 ${100-value}% 0 0)`;document.getElementById('line').style.left=`${value}%`};
const profiles=['before','quality','balanced','eco'];let html='<tr><th>场景</th>'+profiles.map(p=>`<th>${data.labels[p]}</th>`).join('')+'</tr>';
for(const base of data.raw.before){html+=`<tr><td>${base.label}</td>`;for(const p of profiles){const r=data.raw[p].find(r=>r.view===base.view),gain=(1-r.render_gpu_ms.median/base.render_gpu_ms.median)*100;html+=`<td>${r.render_gpu_ms.median.toFixed(2)} ms${p!=='before'?` <span class="${gain>=0?'good':'regression'}">${gain>=0?'−':'+'}${Math.abs(gain).toFixed(0)}%</span>`:''}<small>${r.fps_mean.toFixed(1)} FPS</small></td>`}html+='</tr>'}document.getElementById('raw').innerHTML=html;
html='<tr><th>场景 / 档位</th><th>实际帧率</th><th>进程 CPU</th><th>GPU 毫秒/秒估算</th><th>真实渲染帧</th></tr>';const states=new Set();for(const base of data.sustained.before){for(const p of profiles){const r=data.sustained[p].find(r=>r.view===base.view);for(const s of r.thermal_states||[])states.add(s);html+=`<tr><td>${base.label}<small>${data.labels[p]}</small></td><td>${r.fps_mean.toFixed(1)} FPS</td><td>${r.process_cpu_percent.toFixed(1)}%<small>相对旧版 ${((r.process_cpu_percent/base.process_cpu_percent-1)*100).toFixed(0)}%</small></td><td>${r.gpu_ms_per_second_estimate.toFixed(0)} ms/s<small>相对旧版 ${((r.gpu_ms_per_second_estimate/base.gpu_ms_per_second_estimate-1)*100).toFixed(0)}%</small></td><td>${r.rendered_frames}<small>${r.elapsed_seconds.toFixed(1)} 秒</small></td></tr>`}}document.getElementById('sustained').innerHTML=html;
if(data['movement-play']&&data['movement-repeat-raw']){document.getElementById('movement-section').hidden=false;let m='<tr><th>路线 / 档位</th><th>初测 GPU</th><th>复测 GPU</th><th>正常游玩</th><th>帧间隔 P95</th></tr>';for(const base of data['movement-play'].before){for(const p of profiles){const first=data.raw[p].find(r=>r.view===base.view),repeat=(data['movement-repeat-raw'][p]||[]).find(r=>r.view===base.view),play=data['movement-play'][p].find(r=>r.view===base.view);m+=`<tr><td>${base.label}<small>${data.labels[p]}</small></td><td>${first.render_gpu_ms.median.toFixed(2)} ms</td><td>${repeat?repeat.render_gpu_ms.median.toFixed(2)+' ms':'未另测'}</td><td>${play.fps_mean.toFixed(1)} FPS</td><td>${play.p95_ms.toFixed(2)} ms</td></tr>`}}document.getElementById('movement').innerHTML=m}
document.getElementById('thermal').textContent='采样期间系统热状态：'+[...states].sort().map(s=>['正常','轻度热压力','严重热压力','临界热压力'][s]||s).join('、')+'。这是系统分级，不是机身温度。';
</script></html>'''
    (args.evidence / 'index.html').write_text(page.replace('__CONTEXT__', html.escape(data['context'].get('description', '各档在同一设备、同一输出尺寸下串行测量。'))).replace('__DURATION__', duration_text).replace('__DATA__', json.dumps(data, ensure_ascii=False).replace('</', '<\\/')))
    print(args.evidence / 'index.html')


if __name__ == '__main__':
    main()

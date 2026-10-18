#!/usr/bin/env python3
"""Build a local Chinese video/chapter review page; no server or media processes.

Select recordings explicitly; duplicate takes are refused. Notes remain in the
browser and can be exported as JSON for the reviewer to return to the agent.
"""
from __future__ import annotations
import argparse, hashlib, json, math, os
from pathlib import Path
from urllib.parse import quote
ROOT=Path(__file__).resolve().parents[2]
IDS=['sora','ren','haru','mio','aoi','tanaka','kazuko']
NAMES={'sora':'空','ren':'莲','haru':'春','mio':'澪','aoi':'小葵','tanaka':'田中爷爷','kazuko':'和子'}
TAKES=['solo-'+x for x in IDS]+['group-three','group-four','source-motion']
LABELS={'idle':'静止','slow_walk':'慢走','walk':'行走','walk_left':'向左行走','walk_right':'向右行走','stealth_walk':'轻步潜行','walk_stealth':'低身潜行','injured_walk':'负伤步态','walk_happy_dance':'欢快舞步','walk_boxing':'拳击步态','hand_crawling':'手足爬行','walk_zombie':'僵尸步态'}
def read(p):return json.loads(Path(p).read_text())
def sha(p):
 with Path(p).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def relative_url(path,base):return quote(os.path.relpath(Path(path).resolve(),base),safe='/._-')

TEMPLATE=r'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MotionBricks 人物动作实验 · 逐项点评</title>
<style>
:root{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif;color:#233448;background:#eef2f5;font-size:15px}*{box-sizing:border-box}body{margin:0}button,select,textarea{font:inherit}button,select{cursor:pointer}button:focus-visible,a:focus-visible,select:focus-visible,textarea:focus-visible{outline:3px solid #3c89b8;outline-offset:2px}header{padding:26px 32px 20px;background:#fff;border-bottom:1px solid #d5dee6}h1{font-size:27px;margin:5px 0 10px;font-weight:650;letter-spacing:.02em}.eyebrow{color:#52748e;font-size:12px;letter-spacing:.12em}p{line-height:1.75;margin:6px 0}.warning{background:#fff3d7;color:#73591b;border-left:3px solid #c39b39;padding:10px 14px;margin-top:14px;max-width:1100px}.muted{color:#667b8e}a{color:#2a6c93}main{max-width:1560px;margin:24px auto;padding:0 24px}.layout{display:grid;grid-template-columns:minmax(0,1fr) 340px;gap:22px}.stage,.review,.catalog{background:#fff;border:1px solid #d5dee6;border-radius:8px;overflow:hidden}.stage video{display:block;width:100%;aspect-ratio:16/9;background:#1f2a35}.toolbar{padding:12px 16px;display:flex;align-items:center;gap:8px;flex-wrap:wrap}button,select{border:1px solid #ccd7e1;border-radius:5px;background:#fff;padding:8px 12px;color:#294258}button:hover{background:#edf4f8}button.active{background:#285c7d;color:white;border-color:#285c7d}button:disabled{cursor:default;opacity:.4}.chapter-wrap{padding:0 16px 16px}.chapters{display:flex;flex-wrap:wrap;gap:7px}.chapters button{font-size:13px;padding:7px 10px}.caption{padding:2px 16px 12px;color:#64788b;font-size:13px;line-height:1.65}.review{padding:18px;align-self:start}h2{font-size:18px;margin:0 0 12px}h3{font-size:15px;margin:16px 0 8px}.review label{display:block;margin:12px 0 6px}.review select,.review textarea{width:100%}.review textarea{min-height:155px;resize:vertical;border:1px solid #ccd7e1;border-radius:5px;padding:10px;line-height:1.7}.review .primary{background:#285c7d;color:#fff;border-color:#285c7d;width:100%;margin-top:12px}.small{font-size:12px;line-height:1.7}.status{min-height:40px;margin-top:10px;color:#3f6e82}.catalog{margin-top:22px;padding:18px}.take-tabs{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:10px}.take-tabs button{text-align:left;min-height:74px}.take-tabs strong{display:block;font-size:16px;margin-bottom:5px}.take-tabs span{display:block;font-size:12px;line-height:1.5}.progress{margin-top:12px;color:#61788a;font-size:13px}.source-link{font-size:12px;margin-left:auto}.pill{display:inline-block;border-radius:4px;background:#e7eef4;color:#456780;padding:2px 6px;font-size:11px}.feedback-links{display:flex;gap:8px;margin-top:8px}.feedback-links button{flex:1;font-size:13px}#viewButtons{display:inline-flex;gap:5px}#viewButtons button{font-size:12px;padding:6px 8px}@media(max-width:1080px){.layout{grid-template-columns:1fr}.review{width:100%}.take-tabs{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:650px){header{padding:20px}main{padding:0 12px;margin:14px auto}.take-tabs{grid-template-columns:repeat(2,minmax(0,1fr))}h1{font-size:22px}.toolbar{padding:10px}.source-link{margin-left:0}.review{padding:14px}}
</style>
<header><div class="eyebrow">MOTIONBRICKS / INDEPENDENT POC</div><h1>人物动作实验，逐项看、逐项点评</h1><p>七名单人、两组多人比较，以及一条 G1 生成源骨架。先选人物，再选动作；可以慢放和逐帧检查。</p><div class="warning"><strong>POC 尚未通过自然度验收。</strong>这些是公开 G1 模型生成的动作，经人物重定向、校准、IK 与接触校正形成；并非官方原生人类模型，也未接入游戏。本批没有跑步模式。每个章节独立 reset；若章节包含多个控制动作，章内过渡来自模型连续生成。章节之间直接切换。已知接地、衣物与姿态问题保留展示。</div><p class="small muted"><a id="qualityLink">查看已知问题与分析</a> · <a id="manifestLink">本页来源清单</a> · 点评只留在本机浏览器；下载 JSON 后可交给助手继续修改。</p></header>
<main><div class="layout"><section class="stage"><video id="player" controls preload="metadata" playsinline></video><div class="toolbar"><strong id="takeTitle"></strong><span class="pill" id="chapterTitle"></span><select id="speed" aria-label="播放速度"><option value="1">1× 正常</option><option value="0.5">0.5× 慢放</option><option value="0.25">0.25× 慢放</option></select><button id="prevFrame" title="暂停并后退约一帧">−1 帧</button><button id="nextFrame" title="暂停并前进约一帧">+1 帧</button><a class="source-link" id="videoLink">打开原视频</a></div><div class="chapter-wrap"><div class="chapters" id="chapters"></div></div><div class="caption"><span id="clipInfo"></span><br><span id="viewButtons"></span></div></section><aside class="review"><h2>当前这一项</h2><div id="reviewTarget" class="muted"></div><label for="decision">你的判断</label><select id="decision"><option value="unreviewed">未点评</option><option value="acceptable">可以接受</option><option value="needs_change">需要修改</option><option value="unclear">看不清，需要补拍</option></select><label for="comment">具体点评</label><textarea id="comment" placeholder="例如：左手太向内、手臂穿过衣服、脚有滑动；也可以记录出现问题的时间。"></textarea><button id="stamp">插入当前视频时间</button><button id="save" class="primary">保存这一项</button><div id="saveStatus" class="status small" aria-live="polite"></div><div class="feedback-links"><button id="export">下载点评 JSON</button><button id="nextItem">下一项 →</button></div><p class="small muted">以“人物/组别 × 动作”保存。切换前会保留草稿。浏览器若不支持本地持久保存，页面会提示；关闭前请先下载 JSON。</p></aside></div><section class="catalog"><h2>选择人物与对照</h2><div id="takes" class="take-tabs"></div><div id="progress" class="progress"></div></section></main>
<script id="reviewData" type="application/json">__DATA__</script>
<script>
'use strict';
const data=JSON.parse(document.getElementById('reviewData').textContent),byId=id=>document.getElementById(id),video=byId('player');
let takeIndex=0,chapterIndex=0,notes={},storageWorking=true,lastSaved='',pendingChapter=null,initialized=false,switchingTake=false;
const storageKey='motionbricks-human-review:'+data.review_id;
try{notes=JSON.parse(localStorage.getItem(storageKey)||'{}');if(!notes||typeof notes!=='object')notes={}}catch(e){storageWorking=false}
byId('qualityLink').href=data.quality_findings;byId('manifestLink').href='index-manifest.json';
const time=t=>`${Math.floor(t/60)}:${(t%60).toFixed(2).padStart(5,'0')}`;
const item=()=>data.takes[takeIndex],chapter=()=>item().chapters[chapterIndex],key=()=>item().take+'|'+chapter().motion_id;
function persist(){try{localStorage.setItem(storageKey,JSON.stringify(notes));storageWorking=true}catch(e){storageWorking=false}}
function saveDraft(explicit=false){if(!data.takes.length||!initialized)return;const c=byId('comment').value,d=byId('decision').value,k=key();if(c||d!=='unreviewed'||notes[k]){notes[k]={take:item().take,take_title:item().title,motion_id:chapter().motion_id,official_mode:chapter().official_mode,decision:d,comment:c,video_time_seconds:Number(video.currentTime.toFixed(3)),video_sha256:item().sha256,updated_at:new Date().toISOString()};persist()}if(explicit){lastSaved=k;byId('saveStatus').textContent=storageWorking?'已保存在本机浏览器。':'本次草稿已保留在页面内，浏览器阻止持久保存；关闭前请下载 JSON。'}updateProgress()}
function updateProgress(){const total=data.takes.reduce((n,t)=>n+t.chapters.length,0),done=Object.values(notes).filter(x=>x.decision&&x.decision!=='unreviewed').length;byId('progress').textContent=`已点评 ${done} / ${total} 项 · ${data.complete?'十条视频已齐':'部分视频尚未收齐，当前只列已验证的输出'} · 生成于 ${data.generated_at}`}
function loadNote(){const n=notes[key()]||{};byId('decision').value=n.decision||'unreviewed';byId('comment').value=n.comment||'';byId('reviewTarget').textContent=item().title+' · '+chapter().label;byId('saveStatus').textContent=storageWorking?(n.updated_at?'已有本地记录，可继续修改。':''):'本地持久保存不可用；请在关闭前下载 JSON。'}
function renderChapters(){byId('chapters').replaceChildren();item().chapters.forEach((c,i)=>{const b=document.createElement('button');b.textContent=(i+1)+'. '+c.label;b.className=i===chapterIndex?'active':'';b.onclick=()=>selectChapter(i,true);byId('chapters').append(b)});byId('chapterTitle').textContent=chapter().label;byId('clipInfo').textContent=`源模式 ${chapter().official_mode} · ${time(chapter().start_s)}–${time(chapter().end_s)} · ${chapter().frames} 个真实源采样 / 30 fps · G1源帧与人物重定向按同一采样时钟评估`;byId('viewButtons').replaceChildren();chapter().views.forEach(v=>{const b=document.createElement('button');b.textContent='看'+v.label;b.onclick=()=>{video.currentTime=v.start_s;video.pause()};byId('viewButtons').append(b)});loadNote()}
function selectChapter(index,seek){saveDraft();chapterIndex=index;renderChapters();if(seek){if(video.readyState>=1)video.currentTime=chapter().start_s;else pendingChapter=chapter().start_s}}
function renderTakes(){byId('takes').replaceChildren();data.takes.forEach((t,i)=>{const b=document.createElement('button');b.className=i===takeIndex?'active':'';const strong=document.createElement('strong');strong.textContent=t.title;const sub=document.createElement('span');sub.textContent=t.kind+' · '+t.chapters.length+'动作 · '+Math.round(t.duration_s)+'秒';b.append(strong,sub);b.onclick=()=>selectTake(i);byId('takes').append(b)})}
function selectTake(index){if(initialized)saveDraft();switchingTake=true;const previous=chapter()?.motion_id;takeIndex=index;chapterIndex=Math.max(0,item().chapters.findIndex(c=>c.motion_id===previous));video.pause();video.src=item().video;video.poster=item().poster||'';video.playbackRate=Number(byId('speed').value);byId('takeTitle').textContent=item().title;byId('videoLink').href=item().video;pendingChapter=chapter().start_s;renderTakes();renderChapters();initialized=true;updateProgress()}
video.addEventListener('loadedmetadata',()=>{if(pendingChapter!==null){video.currentTime=pendingChapter;pendingChapter=null}switchingTake=false});
video.addEventListener('timeupdate',()=>{if(switchingTake||!initialized)return;const idx=item().chapters.findIndex(c=>video.currentTime>=c.start_s&&video.currentTime<c.end_s);if(idx>=0&&idx!==chapterIndex){saveDraft();chapterIndex=idx;renderChapters()}});
byId('speed').onchange=()=>video.playbackRate=Number(byId('speed').value);byId('prevFrame').onclick=()=>{video.pause();video.currentTime=Math.max(0,video.currentTime-1/30)};byId('nextFrame').onclick=()=>{video.pause();video.currentTime=Math.min(video.duration||item().duration_s,video.currentTime+1/30)};byId('save').onclick=()=>saveDraft(true);byId('stamp').onclick=()=>{byId('comment').value+=`${byId('comment').value?'\n':''}[${time(video.currentTime)}] `;byId('comment').focus()};byId('nextItem').onclick=()=>{saveDraft(true);if(chapterIndex+1<item().chapters.length)selectChapter(chapterIndex+1,true);else if(takeIndex+1<data.takes.length){selectTake(takeIndex+1);selectChapter(0,true)}else byId('saveStatus').textContent='已到最后一项，可以下载点评 JSON。'};
byId('export').onclick=()=>{saveDraft();const result={kind:'MotionBricks G1→人物重定向 POC 人工逐项点评',review_id:data.review_id,exported_at:new Date().toISOString(),quality_findings:data.quality_findings,source_notice:data.source_notice,recordings:data.takes.map(t=>({take:t.take,video_sha256:t.sha256,frames:t.frames})),reviews:Object.values(notes)};const url=URL.createObjectURL(new Blob([JSON.stringify(result,null,2)],{type:'application/json'})),a=document.createElement('a');a.href=url;a.download='motionbricks-human-review.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};
window.addEventListener('beforeunload',()=>saveDraft());
if(data.takes.length){renderTakes();selectTake(0)}
</script></html>'''

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--recordings',nargs='+',type=Path,required=True,help='Explicit recording batches or exact take folders; duplicate takes are refused');p.add_argument('--out',type=Path,default=ROOT/'evidence/motionbricks_poc_20261018/review');p.add_argument('--findings',type=Path,default=ROOT/'evidence/motionbricks_poc_20261018/quality-findings-v1.md');p.add_argument('--allow-partial',action='store_true');p.add_argument('--verify-video-hashes',action='store_true')
 args=p.parse_args();out=args.out.resolve();assert not out.exists(),'Choose a new immutable index directory';assert args.findings.is_file(),'Known-findings report must exist'
 found={};source_receipts={}
 for base in args.recordings:
  candidates=[base/'media-verification.json'] if (base/'media-verification.json').is_file() else sorted(base.rglob('media-verification.json'))
  for receipt in candidates:
   take=receipt.parent.name
   if take not in TAKES:continue
   if take in found:raise ValueError('Duplicate take '+take+'; select one explicit current source folder')
   media=read(receipt);journal_path=receipt.parent/'journal-verification.json';journal=read(journal_path);video=receipt.parent/'video.mp4'
   assert media['strict_full_decode_passed'] and video.is_file() and video.stat().st_size==media['bytes']
   if args.verify_video_hashes:assert sha(video)==media['sha256']
   stream=next(x for x in media['probe']['streams'] if x['codec_type']=='video');assert int(stream['nb_read_frames'])==journal['frames'] and stream['r_frame_rate']=='30/1'
   chapters=[];offset=0
   for sec in journal['sections']:
    mode=sec['official_mode'];count=sec['frames'];start=offset/30;views=[];v_offset=offset
    for key,label in [('front','正面'),('right','右侧'),('oblique','斜侧')]:
     n=sec['view_counts'][key];views.append({'view':key,'label':label,'start_s':v_offset/30,'end_s':(v_offset+n)/30});v_offset+=n
    assert v_offset==offset+count
    chapters.append({'motion_id':sec['motion_id'],'official_mode':mode,'label':sec.get('label',LABELS.get(mode,mode)),'frames':count,'start_s':start,'end_s':(offset+count)/30,'views':views});offset+=count
   assert offset==journal['frames'] and chapters
   poster=None
   stills=media.get('stills',[])
   if stills and (receipt.parent/stills[0]['file']).is_file():poster=relative_url(receipt.parent/stills[0]['file'],out)
   title=NAMES[take.removeprefix('solo-')] if take.startswith('solo-') else '三人比较 · 空 / 莲 / 田中' if take=='group-three' else '四人比较 · 澪 / 春 / 小葵 / 和子' if take=='group-four' else 'G1 生成源骨架'
   kind='单人' if take.startswith('solo-') else '生成源对照' if take=='source-motion' else '同源动作比较面板'
   found[take]={'take':take,'title':title,'kind':kind,'video':relative_url(video,out),'poster':poster,'sha256':media['sha256'],'frames':journal['frames'],'duration_s':journal['frames']/30,'chapters':chapters}
   source_receipts[take]={'media':{'path':str(receipt.resolve()),'sha256':sha(receipt)},'journal':{'path':str(journal_path.resolve()),'sha256':sha(journal_path)},'video_bytes':media['bytes'],'video_hash_recomputed':args.verify_video_hashes}
 missing=sorted(set(TAKES)-set(found))
 if missing and not args.allow_partial:raise ValueError('Missing takes: '+','.join(missing)+'; use --allow-partial only for an explicit incomplete index')
 if not found:raise ValueError('No verified POC videos found')
 reference_sequence=[c['motion_id'] for c in next(iter(found.values()))['chapters']]
 for take,item in found.items():
  if [c['motion_id'] for c in item['chapters']]!=reference_sequence:raise ValueError('Take action sequence differs: '+take)
  assert math.isfinite(item['duration_s']) and item['duration_s']>0
 import datetime
 review_id=hashlib.sha256(json.dumps({k:v['sha256'] for k,v in found.items()},sort_keys=True).encode()).hexdigest()[:20]
 data={'review_id':review_id,'generated_at':datetime.datetime.now().astimezone().isoformat(timespec='seconds'),'complete':not missing,'missing_takes':missing,'quality_findings':relative_url(args.findings,out),'source_notice':{'source':'MotionBricks public G1 model, not an official human-native model','human_retargeting_corrections_disclosed':True,'no_run_mode':True,'clips_reset_independently':True,'naturalness_accepted':False,'game_integration':False},'takes':[found[k] for k in TAKES if k in found]}
 out.mkdir(parents=True);encoded=json.dumps(data,ensure_ascii=False).replace('<',chr(92)+'u003c')
 (out/'index.html').write_text(TEMPLATE.replace('__DATA__',encoded))
 manifest={'page_data':data,'recording_receipts':source_receipts,'known_findings_sha256':sha(args.findings),'builder_sha256':sha(Path(__file__)),'page_sha256':sha(out/'index.html'),'network_requests_created':False,'media_process_started':False,'notes_storage':'Browser localStorage with explicit JSON export; no server/upload/send'}
 (out/'index-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'index':str(out/'index.html'),'takes':len(found),'review_items':sum(len(x['chapters']) for x in found.values()),'missing':missing,'engine_started':False},ensure_ascii=False))

if __name__=='__main__':main()

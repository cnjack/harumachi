'use strict';

// Offline DOM tests for the actual video review template and scripts.
// This harness uses only synthetic metadata and an in-memory localStorage.
// No browser, media decoder, HTTP server, Godot, or real review storage is used.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const timers = require('node:timers');
const test = require('node:test');
const { parseHTML } = require('linkedom');

const tick = () => new Promise(setImmediate);
const hash = n => n.toString(16).padStart(64, '0');
const actorLabels = { sora:'空', ren:'莲', haru:'春', mio:'澪', aoi:'小葵', tanaka:'田中', kazuko:'和子' };
const actionLabels = { idle:'站立', walk:'走路', run:'跑步', wave:'挥手', stretch:'伸懒腰', bow:'鞠躬', dance:'舞蹈' };

function makeDataset(transform) {
  const takes = Object.entries(actorLabels).map(([actor, actor_label], i) => ({
    id:`solo-${actor}`, take:`solo-${actor}`, actor, actor_label,
    file:`solo-${actor}/video.mp4`, label:`${actor_label} · 原片`,
    media_file:`solo-${actor}/video.mp4`, media_sha256:hash(10 + i),
    journal_sha256:hash(30 + i), model_sha256:hash(50 + i),
    source_sha256:hash(70 + i), duration_s:32, fps:30, frame_count:960
  }));
  takes.push(...['group-front', 'group-orbit'].map((id, i) => ({
    id, take:id, file:`${id}/video.mp4`, label:id, media_file:`${id}/video.mp4`, media_sha256:hash(90 + i),
    journal_sha256:hash(100 + i), source_sha256:hash(110 + i),
    duration_s:32, fps:30, frame_count:960
  })));
  const cases = [];
  Object.entries(actorLabels).forEach(([actor, actor_label], actorIndex) => {
    const take = takes[actorIndex];
    Object.entries(actionLabels).forEach(([action, action_label], actionIndex) => {
      const start_s = actionIndex === 0 ? 0 : 1 + actionIndex * 4;
      const end_s = start_s + 3;
      const views = action === 'walk' || action === 'run'
        ? [['front','正面'],['right','右侧'],['back','背面'],['left','左侧'],['top','顶部']]
        : action === 'dance' || action === 'idle' ? [['front','正面']] : [['oblique','斜前方']];
      const framesPerView = Math.round((end_s-start_s)*30/views.length);
      const view_segments = views.map(([view,view_label], viewIndex) => ({
        view,view_label,frame_start:Math.round(start_s*30)+viewIndex*framesPerView,
        frame_end:Math.round(start_s*30)+(viewIndex+1)*framesPerView,
        start_s:start_s+viewIndex*framesPerView/30,
        end_s:start_s+(viewIndex+1)*framesPerView/30
      }));
      cases.push({
        id:`${actor}/${action}`, actor, actor_label, action, action_label,
        take:take.id, media_file:take.media_file, media_sha256:take.media_sha256,
        journal_sha256:take.journal_sha256, model_sha256:take.model_sha256,
        source_sha256:hash(300 + actorIndex * 7 + actionIndex),
        start_s, end_s, frame_start:Math.round(start_s * 30),
        frame_end:Math.round(end_s * 30), fps:30,
        context:`离线夹具：${actor_label} · ${action_label}`, view_segments
      });
    });
  });
  const dataset = {
    schema:'harumachi-video-dataset/v1', id:'video-dom-offline-fixture-v1',
    source_sha256:hash(200),
    identity:{ models:Object.fromEntries(takes.slice(0,7).map(take => [take.actor,take.model_sha256])), runtime_sha256:hash(201), context:'offline-dom-fixture' },
    case_count:49,
    takes, cases
  };
  if (transform) transform(dataset);
  return dataset;
}

function createEnvironment(options = {}) {
  const data = makeDataset(options.datasetTransform);
  const html = fs.readFileSync(path.join(__dirname, 'video-index.template.html'), 'utf8');
  const { document, window } = parseHTML(html);
  const el = id => { const found = document.getElementById(id); assert.ok(found, `DOM element #${id}`); return found; };
  el('video-data').textContent = JSON.stringify(data);
  const storage = options.storage || new Map();
  const downloads = [], errors = [], storageWrites = [], blobs = new Map();
  let nextBlob = 0;

  Object.defineProperty(window.HTMLSelectElement.prototype, 'value', {
    configurable:true,
    get() {
      const opts = Array.from(this.querySelectorAll('option'));
      const selected = opts.find(item => item.hasAttribute('selected')) || opts[0];
      return selected ? (selected.getAttribute('value') ?? selected.textContent) : '';
    },
    set(value) {
      for (const option of this.querySelectorAll('option')) {
        if ((option.getAttribute('value') ?? option.textContent) === String(value)) option.setAttribute('selected', '');
        else option.removeAttribute('selected');
      }
    }
  });
  const nativeClick = window.HTMLElement.prototype.click;
  window.HTMLElement.prototype.click = function () {
    if (this.disabled || this.hasAttribute('disabled')) return;
    if (this.tagName === 'A' && this.hasAttribute('download')) {
      downloads.push({ filename:this.getAttribute('download'), blob:blobs.get(this.href) });
      return;
    }
    return nativeClick.call(this);
  };
  window.HTMLElement.prototype.scrollIntoView = function () {};
  window.HTMLElement.prototype.focus = function () { document.activeElement = this; };
  window.HTMLElement.prototype.showModal = function () { this.setAttribute('open', ''); };
  window.HTMLElement.prototype.close = function () { this.removeAttribute('open'); };
  Object.defineProperty(window.HTMLAnchorElement.prototype, 'download', {
    configurable:true,
    get() { return this.getAttribute('download') || ''; },
    set(value) { this.setAttribute('download', value); }
  });
  const location = { protocol:'file:', href:'file:///offline-video-review/index.html', hash:'' };
  const absolute = value => new URL(String(value), location.href).href;
  const media = el('reviewVideo');
  const mock = {
    currentSrc:'', currentTime:0, requestedTime:null, readyState:0, duration:NaN,
    seeking:false, paused:true, ended:false, loadCalls:0, playCalls:0, pauseCalls:0,
    seekRequests:[], playbackRate:1
  };
  for (const prop of ['currentSrc','readyState','duration','seeking','paused','ended']) {
    Object.defineProperty(media, prop, { configurable:true, get:() => mock[prop] });
  }
  Object.defineProperty(media, 'src', {
    configurable:true,
    get:() => media.getAttribute('src') ? absolute(media.getAttribute('src')) : '',
    set:value => media.setAttribute('src', String(value))
  });
  Object.defineProperty(media, 'currentTime', {
    configurable:true,
    get:() => mock.currentTime,
    set:value => {
      // Deliberately do not acknowledge the new position or emit media events.
      // A browser can expose the requested time before the frame is available.
      mock.requestedTime = Number(value);
      mock.seekRequests.push(Number(value));
    }
  });
  Object.defineProperty(media, 'playbackRate', {
    configurable:true, get:() => mock.playbackRate, set:value => { mock.playbackRate = Number(value); }
  });
  media.load = () => { mock.loadCalls++; mock.readyState=0; mock.duration=NaN; mock.paused=true; };
  media.play = () => { mock.playCalls++; mock.paused=false; return Promise.resolve(); };
  media.pause = () => { mock.pauseCalls++; mock.paused=true; };
  const event = (id, kind) => el(id).dispatchEvent(new window.Event(kind, { bubbles:true }));
  function metadata(src = media.src) {
    mock.currentSrc=absolute(src); mock.duration=32; mock.readyState=1;
    event('reviewVideo', 'loadedmetadata');
  }
  function loadeddata(src = mock.currentSrc) {
    mock.currentSrc=src ? absolute(src) : ''; mock.readyState=2; mock.seeking=false;
    event('reviewVideo', 'loadeddata');
  }
  function seeking(src = mock.currentSrc) {
    mock.currentSrc=src ? absolute(src) : ''; mock.seeking=true;
    mock.currentTime=Number(mock.requestedTime);
    event('reviewVideo', 'seeking');
  }
  function seeked(time = mock.requestedTime, src = mock.currentSrc) {
    mock.currentSrc=src ? absolute(src) : '';
    mock.currentTime=Number(time); mock.seeking=false; mock.readyState=2;
    event('reviewVideo', 'seeked');
  }
  function timeupdate(time) { mock.currentTime=Number(time); event('reviewVideo', 'timeupdate'); }
  function nativePlay(time = mock.currentTime) {
    mock.currentTime=Number(time); mock.paused=false;
    event('reviewVideo','play');
  }
  function acknowledge() {
    metadata();
    if ((mock.requestedTime === null || mock.requestedTime === 0) && mock.currentTime === 0) loadeddata();
    else { seeking(); seeked(); loadeddata(); }
  }
  class FakeURL extends URL {}
  FakeURL.createObjectURL = blob => { const id=`blob:video-dom-${++nextBlob}`; blobs.set(id, blob); return id; };
  FakeURL.revokeObjectURL = () => {};
  const fakeStorage = {
    getItem(key) { if (options.storageReadFails) throw new Error('storage denied'); return storage.get(key) ?? null; },
    setItem(key, value) {
      storageWrites.push({ key, value:String(value) });
      if (options.storageWriteFails) throw new Error('quota exceeded');
      if (!options.storageSilentNoop) storage.set(key, String(value));
    },
    removeItem(key) { if (options.storageWriteFails) throw new Error('storage denied'); storage.delete(key); }
  };
  const globals = {
    window, document, location, localStorage:fakeStorage, URL:FakeURL,
    navigator:{ clipboard:{ writeText:async () => {} } },
    console, Blob, File, crypto, structuredClone, Event:window.Event,
    CustomEvent:window.CustomEvent, HTMLElement:window.HTMLElement,
    HTMLInputElement:window.HTMLInputElement, Node:window.Node, Element:window.Element,
    setTimeout:(fn, ms) => { const timer=timers.setTimeout(fn, ms); timer.unref(); return timer; },
    clearTimeout:timers.clearTimeout,
    setInterval:(fn, ms) => { const timer=timers.setInterval(fn, ms); timer.unref(); return timer; },
    clearInterval:timers.clearInterval,
    requestAnimationFrame:fn => { const timer=timers.setTimeout(fn, 0); timer.unref(); return timer; },
    cancelAnimationFrame:timers.clearTimeout,
    matchMedia:() => ({ matches:false, addEventListener() {}, removeEventListener() {} }),
    alert:message => errors.push(String(message)), confirm:() => true
  };
  for (const [key, value] of Object.entries(globals)) {
    if (key !== 'window' && key !== 'document') {
      try { Object.defineProperty(window, key, { value, configurable:true, writable:true }); } catch (_) {}
    }
  }
  const context = vm.createContext(globals);
  for (const filename of ['video-model.js','video-review.js']) {
    vm.runInContext(fs.readFileSync(path.join(__dirname, filename), 'utf8'), context, { filename, timeout:15000 });
    if (context.VideoReviewModel) window.VideoReviewModel=context.VideoReviewModel;
    if (context.VideoReviewApp) window.VideoReviewApp=context.VideoReviewApp;
  }
  document.dispatchEvent(new window.Event('DOMContentLoaded'));
  if (context.VideoReviewApp) window.VideoReviewApp=context.VideoReviewApp;
  assert.ok(window.VideoReviewModel, 'real VideoReviewModel loaded');
  assert.ok(window.VideoReviewApp, 'real VideoReviewApp loaded');
  const environment = {
    data, window, document, el, media, mock, storage, storageWrites, downloads, errors,
    metadata, loadeddata, seeking, seeked, timeupdate, nativePlay, acknowledge, absolute, event,
    click:id => el(id).click(),
    type:(id, value) => { el(id).value=value; event(id, 'input'); },
    chooseCase:id => {
      const button=document.querySelector(`#videoCaseList [data-case-id="${id}"]`);
      assert.ok(button, `case ${id}`); button.click();
    },
    verdict:value => {
      const button=document.querySelector(`#videoVerdicts [data-verdict="${value}"]`);
      assert.ok(button, `verdict ${value}`); button.click();
    },
    export:() => JSON.parse(JSON.stringify(window.VideoReviewApp.exportDocument())),
    state:() => JSON.parse(JSON.stringify(window.VideoReviewApp.getState())),
    async import(doc) {
      Object.defineProperty(el('videoImportFile'), 'files', {
        configurable:true, value:[{ size:JSON.stringify(doc).length, text:async () => JSON.stringify(doc) }]
      });
      event('videoImportFile', 'change'); await tick(); await tick();
    }
  };
  return environment;
}

const itemList = doc => Array.isArray(doc.items) ? doc.items : Object.values(doc.items);
const exportedItem = (e, id='sora/idle') => itemList(e.export()).find(item => item.id === id);
const itemNotes = item => item.time_comments;
const noteTime = note => note.video_time_s;
const content = e => JSON.stringify({ reviewer:e.export().reviewer, items:itemList(e.export()) });
const isDisabled = element => element.disabled || element.hasAttribute('disabled');

test('49项与9段来源渲染，原生controls可用且选项不自动播放', () => {
  const e=createEnvironment();
  assert.equal(e.data.cases.length,49);
  assert.equal(e.data.takes.length,9);
  assert.equal(e.document.querySelectorAll('#videoCaseList [data-case-id]').length,49);
  assert.match(e.el('videoCaseNumber').textContent,/1\s*\/\s*49/);
  assert.match(e.el('videoProgressText').textContent,/0\s*\/\s*49/);
  assert.ok(e.media.hasAttribute('controls'));
  const takes=Array.from(e.el('videoTakeLinks').querySelectorAll('a'));
  assert.equal(takes.length,9);
  for (let i=0;i<takes.length;i++) {
    assert.equal(takes[i].getAttribute('href'),e.data.takes[i].file);
    assert.match(takes[i].textContent,new RegExp(e.data.takes[i].label));
  }
  assert.equal(e.mock.playCalls,0);
  assert.ok(isDisabled(e.el('videoNoteButton')));
  const doc=e.export();
  assert.equal(itemList(doc).length,49);
  assert.ok(itemList(doc).every(item => item.verdict === 'unreviewed'));
  e.chooseCase('sora/walk'); e.chooseCase('ren/run');
  assert.equal(e.mock.playCalls,0);
});

test('项目意见和点评人input即存，换项和刷新保留', () => {
  let e=createEnvironment();
  e.type('videoReviewer','离线人评测试');
  e.type('videoComment','第一项人工意见');
  assert.equal(exportedItem(e).comment,'第一项人工意见');
  assert.ok(e.storage.size > 0);
  e.click('videoNext'); e.type('videoComment','第二项意见');
  e.click('videoPrevious');
  assert.equal(e.el('videoComment').value,'第一项人工意见');
  e=createEnvironment({ storage:e.storage });
  e.click('videoExportButton');
  assert.equal(e.el('videoReviewer').value,'离线人评测试');
  assert.equal(exportedItem(e).comment,'第一项人工意见');
  assert.equal(exportedItem(e,'sora/walk').comment,'第二项意见');
});

test('pass issue unsure计为已评，later不计，下一未评跳过已有判断', () => {
  const e=createEnvironment();
  for (const [id, verdict] of [['sora/idle','pass'],['sora/walk','issue'],['sora/run','unsure'],['sora/wave','later']]) {
    e.chooseCase(id); e.verdict(verdict);
  }
  assert.match(e.el('videoProgressText').textContent,/3\s*\/\s*49/);
  e.chooseCase('sora/idle'); e.click('videoNextPending');
  assert.match(e.el('videoCaseTitle').textContent,/挥手/);
  assert.equal(exportedItem(e,'sora/wave').verdict,'later');
});

test('metadata和currentTime setter都不能提前允许记录，必须实际seek完成', () => {
  const e=createEnvironment(); e.chooseCase('sora/walk');
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.metadata();
  assert.ok(e.mock.seekRequests.length > 0);
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.seeking();
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.seeked();
  assert.equal(Boolean(isDisabled(e.el('videoNoteButton'))),false);
  assert.equal(e.mock.playCalls,0);
});

test('同视频换动作也需本次seeked，旧位置不能记录到新动作', () => {
  const e=createEnvironment(); e.acknowledge();
  const oldTime=e.mock.currentTime;
  e.chooseCase('sora/walk');
  assert.equal(e.mock.currentTime,oldTime);
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.click('videoNoteButton');
  assert.equal(itemNotes(exportedItem(e,'sora/walk')).length,0);
  e.seeking(); e.seeked();
  assert.equal(Boolean(isDisabled(e.el('videoNoteButton'))),false);
  assert.equal(e.mock.playCalls,0);
});

test('方向快捷键只显示本片实际方向，定位后重新等待seeking与seeked', () => {
  const e=createEnvironment(); e.chooseCase('sora/walk'); e.acknowledge();
  const fixture=e.data.cases.find(item => item.id === 'sora/walk');
  let buttons=Array.from(e.el('videoViewButtons').querySelectorAll('button'));
  assert.equal(buttons.length,5);
  for (const segment of fixture.view_segments) {
    assert.ok(buttons.some(button => button.dataset.view === segment.view || button.textContent.includes(segment.view_label)),segment.view);
  }
  const top=fixture.view_segments.find(segment => segment.view === 'top');
  const button=buttons.find(value => value.dataset.view === 'top' || value.textContent.includes(top.view_label));
  assert.equal(Boolean(isDisabled(e.el('videoNoteButton'))),false);
  button.click();
  assert.ok(Math.abs(e.mock.requestedTime-top.frame_start/fixture.fps) < 1e-9);
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.seeked(); // A late seeked without this request's seeking cannot acknowledge it.
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.seeking(); e.seeked();
  assert.equal(Boolean(isDisabled(e.el('videoNoteButton'))),false);
  e.timeupdate(top.start_s+.1); e.click('videoNoteButton'); e.type('videoNoteComment','顶部时间点');
  assert.ok(Math.abs(itemNotes(exportedItem(e,'sora/walk'))[0].video_time_s-(top.start_s+.1)) < 1e-9);
  assert.equal(e.mock.playCalls,0);
  e.chooseCase('sora/wave');
  buttons=Array.from(e.el('videoViewButtons').querySelectorAll('button'));
  assert.equal(buttons.length,1);
  assert.ok(buttons[0].dataset.view === 'oblique' || buttons[0].textContent.includes('斜前方'));
  e.chooseCase('sora/dance');
  buttons=Array.from(e.el('videoViewButtons').querySelectorAll('button'));
  assert.equal(buttons.length,1);
  assert.ok(buttons[0].dataset.view === 'front' || buttons[0].textContent.includes('正面'));
});

test('快速跨人物后旧currentSrc和迟到媒体事件不能确认新项目', () => {
  const e=createEnvironment(); e.acknowledge();
  const staleSrc=e.mock.currentSrc;
  e.chooseCase('ren/walk');
  const renSrc=e.media.src;
  e.chooseCase('mio/run');
  const expectedSrc=e.media.src;
  assert.notEqual(staleSrc,expectedSrc);
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.metadata(staleSrc); e.seeking(staleSrc); e.seeked(1.5,staleSrc);
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.metadata(renSrc); e.seeking(renSrc); e.seeked(5.5,renSrc);
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.metadata(expectedSrc); e.seeking(expectedSrc); e.seeked(undefined,expectedSrc);
  assert.equal(Boolean(isDisabled(e.el('videoNoteButton'))),false);
  assert.equal(e.mock.currentSrc,expectedSrc);
  assert.equal(e.mock.playCalls,0);
});

test('时间点记录实际currentTime且input即存，换项刷新保留', () => {
  let e=createEnvironment(); e.chooseCase('sora/walk'); e.acknowledge();
  const fixture=e.data.cases.find(item => item.id === 'sora/walk');
  const actual=fixture.start_s+1.234;
  e.timeupdate(actual); e.click('videoNoteButton');
  assert.equal(e.el('videoNoteEditor').hidden,false);
  e.type('videoNoteComment','右膝在这个时间有疑问');
  let notes=itemNotes(exportedItem(e,'sora/walk'));
  assert.equal(notes.length,1);
  assert.ok(Math.abs(noteTime(notes[0])-actual) < 1e-9);
  assert.ok(noteTime(notes[0]) >= fixture.start_s && noteTime(notes[0]) <= fixture.end_s);
  assert.match(e.el('videoNoteContext').textContent,/走路/);
  e.click('videoNoteDone'); e.chooseCase('ren/run');
  e=createEnvironment({ storage:e.storage });
  notes=itemNotes(exportedItem(e,'sora/walk'));
  assert.equal(notes.length,1);
  assert.match(JSON.stringify(notes),/右膝在这个时间有疑问/);
});

test('原生controls移到项目范围外时禁止记点', () => {
  const e=createEnvironment(); e.chooseCase('sora/walk'); e.acknowledge();
  const fixture=e.data.cases.find(item => item.id === 'sora/walk');
  for (const time of [fixture.start_s-.25, fixture.end_s, fixture.end_s+.25]) {
    e.timeupdate(time);
    assert.ok(isDisabled(e.el('videoNoteButton')));
    e.click('videoNoteButton');
    assert.equal(itemNotes(exportedItem(e,'sora/walk')).length,0);
  }
});

test('前后单帧按钮按30fps移动，范围边界不越界且每次等待seek确认', () => {
  const e=createEnvironment(); e.chooseCase('sora/walk'); e.acknowledge();
  const fixture=e.data.cases.find(item => item.id === 'sora/walk');
  e.timeupdate(fixture.start_s+1);
  e.click('videoStepForward');
  assert.ok(Math.abs(e.mock.requestedTime-(fixture.start_s+1+1/30)) < 1e-8);
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.seeking(); e.seeked();
  e.click('videoStepBack');
  assert.ok(Math.abs(e.mock.requestedTime-(fixture.start_s+1)) < 1e-8);
  e.seeking(); e.seeked();
  e.timeupdate(fixture.start_s);
  let requests=e.mock.seekRequests.length;
  e.click('videoStepBack');
  if (e.mock.seekRequests.length > requests) {
    assert.equal(e.mock.requestedTime,fixture.start_s); e.seeking(); e.seeked();
  } else assert.equal(e.mock.currentTime,fixture.start_s);
  const lastFrame=fixture.end_s-1/30;
  e.timeupdate(lastFrame); requests=e.mock.seekRequests.length; e.click('videoStepForward');
  if (e.mock.seekRequests.length > requests) assert.ok(Math.abs(e.mock.requestedTime-lastFrame) < 1e-8);
  else assert.ok(Math.abs(e.mock.currentTime-lastFrame) < 1e-8);
  assert.equal(e.mock.playCalls,0);
});

test('速度切换传给媒体，重播定位仍需seek确认', () => {
  const e=createEnvironment(); e.chooseCase('sora/walk'); e.acknowledge();
  e.el('videoSpeed').value='0.5'; e.event('videoSpeed','change');
  assert.equal(e.mock.playbackRate,.5);
  e.timeupdate(6.75); e.click('videoReplay');
  assert.equal(e.mock.requestedTime,e.data.cases.find(item => item.id === 'sora/walk').start_s);
  assert.ok(isDisabled(e.el('videoNoteButton')));
});

test('导出按钮下载完整49项并保留人工意见与来源', async () => {
  const e=createEnvironment(); e.type('videoComment','导出意见');
  e.click('videoExportButton');
  assert.equal(e.el('videoExportDialog').hasAttribute('open'),true);
  e.click('videoDownload');
  assert.equal(e.downloads.length,1);
  assert.ok(e.downloads[0].blob);
  const doc=JSON.parse(await e.downloads[0].blob.text());
  assert.equal(itemList(doc).length,49);
  assert.equal(itemList(doc)[0].comment,'导出意见');
  assert.equal(doc.schema,'harumachi-video-review/v1');
  assert.deepEqual(doc.dataset,{ id:e.data.id, source_sha256:e.data.source_sha256, identity:e.data.identity });
  const source=itemList(doc)[0].source, fixture=e.data.cases[0];
  assert.deepEqual(Object.keys(source).sort(),[
    'case_id','case_sha256','media_file','media_sha256','journal_sha256','model_sha256','start_s','end_s','fps'
  ].sort());
  assert.equal(source.case_id,fixture.id);
  assert.equal(source.case_sha256,fixture.source_sha256);
  assert.equal(source.media_file,fixture.media_file);
  assert.match(JSON.stringify(doc),new RegExp(e.data.source_sha256));
  assert.match(JSON.stringify(doc),new RegExp(e.data.cases[0].media_sha256));
});

test('导入先预览，取消保留原状态；确认后一次应用', async () => {
  const source=createEnvironment(); source.type('videoComment','待导入意见'); source.verdict('issue');
  const incoming=source.export();
  const e=createEnvironment(); e.type('videoReviewer','本地点评人');
  const before=content(e);
  await e.import(incoming);
  assert.ok(e.el('videoImportDialog').hasAttribute('open'));
  assert.equal(content(e),before);
  assert.ok(e.el('videoImportSummary').textContent.trim());
  e.click('videoCancelImport');
  assert.equal(content(e),before);
  await e.import(incoming); e.click('videoConfirmImport');
  assert.equal(exportedItem(e).comment,'待导入意见');
  assert.equal(exportedItem(e).verdict,'issue');
  assert.equal(e.el('videoImportDialog').hasAttribute('open'),false);
});

test('错数据集和错source identity导入均拒绝，当前意见及storage不变', async () => {
  const e=createEnvironment(); e.type('videoComment','原意见保留');
  const before=content(e), stored=JSON.stringify([...e.storage]);
  const original=e.export();
  const badId=structuredClone(original); badId.dataset.id='another-dataset';
  const badSource=structuredClone(original); badSource.dataset.source_sha256=hash(999);
  const badIdentity=structuredClone(original); badIdentity.dataset.identity=hash(998);
  const badCaseIdentity=structuredClone(original); itemList(badCaseIdentity)[0].source.case_sha256=hash(997);
  for (const doc of [badId,badSource,badIdentity,badCaseIdentity]) {
    await e.import(doc);
    assert.equal(e.el('videoImportDialog').hasAttribute('open'),false);
    assert.equal(content(e),before);
    assert.equal(JSON.stringify([...e.storage]),stored);
    assert.ok(e.el('videoToast').textContent.trim());
  }
});

test('时间意见源身份篡改也拒绝，不能转贴到其它视频', async () => {
  const source=createEnvironment(); source.chooseCase('sora/walk'); source.acknowledge();
  source.timeupdate(6.25); source.click('videoNoteButton'); source.type('videoNoteComment','源身份负例');
  const invalid=source.export();
  const note=itemNotes(itemList(invalid).find(item => item.id === 'sora/walk'))[0];
  assert.ok(note);
  note.source.media_sha256=hash(996);
  const e=createEnvironment(); e.type('videoComment','仍保留原意见');
  const before=content(e), stored=JSON.stringify([...e.storage]);
  await e.import(invalid);
  assert.equal(e.el('videoImportDialog').hasAttribute('open'),false);
  assert.equal(content(e),before);
  assert.equal(JSON.stringify([...e.storage]),stored);
});

test('含越界时间点的整份导入拒绝，不部分应用其它有效意见', async () => {
  const source=createEnvironment(); source.chooseCase('sora/walk'); source.acknowledge();
  source.timeupdate(6.25); source.click('videoNoteButton'); source.type('videoNoteComment','越界负例');
  const invalid=source.export();
  const note=itemNotes(itemList(invalid).find(item => item.id === 'sora/walk'))[0];
  assert.ok(note);
  note.video_time_s=9999;
  itemList(invalid)[0].comment='此项也不得部分应用';
  const e=createEnvironment(); e.type('videoComment','现有原意见');
  const before=content(e), stored=JSON.stringify([...e.storage]);
  await e.import(invalid);
  assert.equal(e.el('videoImportDialog').hasAttribute('open'),false);
  assert.equal(content(e),before);
  assert.equal(JSON.stringify([...e.storage]),stored);
});

test('localStorage读写失败时仍能导出，警告跨换项和媒体确认持续存在', async () => {
  const e=createEnvironment({ storageReadFails:true, storageWriteFails:true });
  e.type('videoComment','内存意见仍应导出'); e.verdict('issue');
  assert.equal(e.el('videoSaveWarning').hidden,false);
  assert.match(e.el('videoSaveStatus').textContent,/导出|备份|未保存/);
  e.chooseCase('sora/walk'); e.acknowledge(); e.chooseCase('sora/idle');
  assert.equal(e.el('videoSaveWarning').hidden,false);
  assert.equal(exportedItem(e).comment,'内存意见仍应导出');
  e.click('videoExportButton');
  e.click('videoDownload');
  const doc=JSON.parse(await e.downloads.at(-1).blob.text());
  assert.equal(itemList(doc).length,49);
  assert.equal(itemList(doc)[0].comment,'内存意见仍应导出');
  assert.equal(e.el('videoSaveWarning').hidden,false);
});

test('损坏或身份无效的本机raw不会被普通输入覆盖，仅确认导入才替换', async () => {
  const key='harumachi-video-review:v1:video-dom-offline-fixture-v1';
  const clean=createEnvironment(); clean.type('videoComment','用户明确导入的替换意见');
  const incoming=clean.export();
  for (const raw of ['{broken-json',JSON.stringify({ schema:'harumachi-video-review/v1',dataset:{ id:'wrong-batch' } })]) {
    const storage=new Map([[key,raw]]);
    const e=createEnvironment({ storage });
    assert.equal(e.el('videoSaveWarning').hidden,false);
    e.type('videoComment','当前session仅内存的意见'); e.verdict('issue');
    e.chooseCase('sora/walk'); e.type('videoComment','第二项仅内存意见');
    assert.equal(storage.get(key),raw);
    assert.equal(e.storageWrites.length,0,'invalid raw must be write-protected until explicit replacement');
    assert.equal(exportedItem(e).comment,'当前session仅内存的意见');
    await e.import(incoming);
    assert.equal(storage.get(key),raw,'preview cannot overwrite invalid raw');
    e.click('videoCancelImport');
    assert.equal(storage.get(key),raw,'cancel cannot overwrite invalid raw');
    await e.import(incoming); e.click('videoConfirmImport');
    assert.notEqual(storage.get(key),raw);
    assert.equal(JSON.parse(storage.get(key)).items[0].comment,'用户明确导入的替换意见');
    assert.ok(e.storageWrites.length > 0);
  }
});

test('setItem静默不落盘时回读失败必须常驻告警，不显示已保存', () => {
  const e=createEnvironment({ storageSilentNoop:true });
  e.type('videoComment','静默拒写也不能丢失导出意见');
  assert.ok(e.storageWrites.length > 0);
  assert.equal(e.storage.size,0);
  assert.equal(e.el('videoSaveWarning').hidden,false);
  assert.doesNotMatch(e.el('videoSaveStatus').textContent,/已在本机保存/);
  e.chooseCase('sora/walk'); e.acknowledge(); e.verdict('unsure');
  assert.equal(e.el('videoSaveWarning').hidden,false);
  assert.doesNotMatch(e.el('videoSaveStatus').textContent,/已在本机保存/);
  assert.equal(exportedItem(e).comment,'静默拒写也不能丢失导出意见');
});

test('零秒新source无seeking事件时仅本片loadeddata首帧可解锁，metadata不足', () => {
  const e=createEnvironment({ datasetTransform:data => {
    for (const item of data.cases.filter(item => item.action === 'idle')) {
      item.start_s=0; item.end_s=3; item.frame_start=0; item.frame_end=90;
      item.view_segments=[{ view:'front',view_label:'正面',start_s:0,end_s:3,frame_start:0,frame_end:90 }];
    }
  } });
  assert.equal(e.mock.currentTime,0);
  e.metadata();
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.mock.readyState=2; e.timeupdate(0);
  assert.ok(isDisabled(e.el('videoNoteButton')),'readyState alone is not a loaded first-frame acknowledgement');
  e.loadeddata();
  assert.equal(Boolean(isDisabled(e.el('videoNoteButton'))),false);
  const oldSrc=e.mock.currentSrc;
  e.chooseCase('ren/idle');
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.loadeddata(oldSrc);
  assert.ok(isDisabled(e.el('videoNoteButton')),'stale source data cannot acknowledge another character');
  e.metadata();
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.loadeddata();
  assert.equal(Boolean(isDisabled(e.el('videoNoteButton'))),false);
  e.chooseCase('ren/walk');
  e.loadeddata();
  assert.ok(isDisabled(e.el('videoNoteButton')),'an old decoded time cannot acknowledge a different action target');
  e.seeking(); e.seeked();
  assert.equal(Boolean(isDisabled(e.el('videoNoteButton'))),false);
  assert.equal(e.mock.playCalls,0);
});

test('原生controls触发play也在本项end自动暂停，不跨入下个动作', () => {
  const e=createEnvironment(); e.chooseCase('sora/walk'); e.acknowledge();
  const fixture=e.data.cases.find(item => item.id === 'sora/walk');
  e.nativePlay(fixture.start_s+.5);
  assert.equal(e.mock.paused,false);
  e.timeupdate(fixture.end_s-.001);
  assert.equal(e.mock.paused,false);
  e.timeupdate(fixture.end_s);
  assert.equal(e.mock.paused,true);
  assert.ok(Math.abs(e.mock.requestedTime-(fixture.end_s-1/fixture.fps)) < 1e-8);
  assert.ok(isDisabled(e.el('videoNoteButton')));
});

test('范围外原生起播先暂停并回本段start，实际seek确认后才继续', () => {
  const e=createEnvironment(); e.chooseCase('sora/walk'); e.acknowledge();
  const fixture=e.data.cases.find(item => item.id === 'sora/walk');
  for (const time of [fixture.start_s-.5,fixture.end_s+.5]) {
    const previousPlays=e.mock.playCalls;
    e.nativePlay(time);
    assert.equal(e.mock.paused,true);
    assert.equal(e.mock.requestedTime,fixture.start_s);
    assert.equal(e.mock.playCalls,previousPlays,'cannot resume until acknowledged');
    assert.ok(isDisabled(e.el('videoNoteButton')));
    e.seeking();
    assert.equal(e.mock.paused,true);
    e.seeked();
    assert.equal(e.mock.playCalls,previousPlays+1);
    assert.equal(e.mock.paused,false);
    e.timeupdate(fixture.end_s);
    assert.equal(e.mock.paused,true);
  }
});

test('筛选未评时标记当前项仍留在列表并保持可编辑', () => {
  const e=createEnvironment();
  e.el('videoFilter').value='pending'; e.event('videoFilter','change');
  e.type('videoComment','当前项的连续意见'); e.verdict('issue');
  const current=e.document.querySelector('#videoCaseList [data-case-id="sora/idle"]');
  assert.ok(current,'reviewing the current item cannot make it disappear under pending filter');
  assert.ok(current.classList.contains('active'));
  assert.match(e.el('videoCaseTitle').textContent,/站立/);
  e.type('videoComment','标记后仍可继续写意见');
  assert.equal(exportedItem(e).comment,'标记后仍可继续写意见');
  assert.match(e.el('videoProgressText').textContent,/1\s*\/\s*49/);
  e.click('videoNextPending');
  assert.match(e.el('videoCaseTitle').textContent,/走路/);
  assert.equal(e.document.querySelector('#videoCaseList [data-case-id="sora/idle"]'),null);
  e.el('videoFilter').value='all'; e.event('videoFilter','change'); e.chooseCase('sora/idle');
  assert.equal(e.el('videoComment').value,'标记后仍可继续写意见');
});

test('同一群舞原片已确认20秒暂停后换人物可复用画面，意见只归新人物', () => {
  const e=createEnvironment({ datasetTransform:data => {
    const take=data.takes.find(take => take.id === 'group-front');
    Object.assign(take,{ id:'group-all',take:'group-all',file:'group-all/video.mp4',media_file:'group-all/video.mp4' });
    for (const item of data.cases.filter(item => item.action === 'dance')) {
      Object.assign(item,{ take:'group-all',media_file:take.file,media_sha256:take.media_sha256,journal_sha256:take.journal_sha256,
        start_s:20,end_s:23,frame_start:600,frame_end:690,
        view_segments:[{ view:'front',view_label:'正面',start_s:20,end_s:23,frame_start:600,frame_end:690 }] });
    }
  } });
  e.chooseCase('sora/dance'); e.metadata(); e.seeking(); e.seeked();
  assert.equal(e.mock.currentTime,20);
  assert.equal(e.mock.paused,true);
  const seeks=e.mock.seekRequests.length;
  e.chooseCase('ren/dance');
  assert.equal(e.mock.seekRequests.length,seeks,'the confirmed same-source same-time frame needs no new seek');
  assert.equal(e.mock.currentTime,20);
  assert.equal(Boolean(isDisabled(e.el('videoNoteButton'))),false);
  e.click('videoNoteButton'); e.type('videoNoteComment','这是莲在群舞中的时间点');
  assert.equal(itemNotes(exportedItem(e,'sora/dance')).length,0);
  const notes=itemNotes(exportedItem(e,'ren/dance'));
  assert.equal(notes.length,1);
  assert.equal(notes[0].video_time_s,20);
  assert.equal(notes[0].source.case_id,'ren/dance');
  assert.match(e.el('videoNoteContext').textContent,/莲/);
  assert.equal(e.mock.playCalls,0);
});

test('同片已有真实seeking时快切回同目标，最终seeked无需再发seeking也可确认', () => {
  const e=createEnvironment(); e.chooseCase('sora/walk'); e.acknowledge();
  const target=e.data.cases.find(item => item.id === 'sora/run').start_s;
  e.chooseCase('sora/run'); e.seeking();
  assert.equal(e.mock.seeking,true);
  assert.equal(e.mock.currentTime,target);
  e.chooseCase('sora/walk'); e.chooseCase('sora/run');
  assert.ok(isDisabled(e.el('videoNoteButton')));
  assert.equal(e.mock.seeking,true);
  e.seeked(target); // The media was already seeking; a second seeking event is not guaranteed.
  assert.equal(Boolean(isDisabled(e.el('videoNoteButton'))),false);
  e.click('videoNoteButton'); e.type('videoNoteComment','快速切换后的跑步时间点');
  const notes=itemNotes(exportedItem(e,'sora/run'));
  assert.equal(notes.length,1);
  assert.equal(notes[0].video_time_s,target);
  assert.equal(notes[0].source.case_id,'sora/run');
  assert.equal(e.mock.playCalls,0);
});

test('初始idle未载入即同片切wave再回idle，随后metadata和loadeddata仍可确认首帧', () => {
  const e=createEnvironment();
  assert.equal(e.mock.readyState,0);
  assert.equal(e.mock.currentTime,0);
  const loads=e.mock.loadCalls;
  e.chooseCase('sora/wave'); e.chooseCase('sora/idle');
  assert.equal(e.mock.loadCalls,loads,'same src selection must not reload the media');
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.metadata();
  assert.ok(isDisabled(e.el('videoNoteButton')));
  e.loadeddata();
  assert.equal(Boolean(isDisabled(e.el('videoNoteButton'))),false);
  e.click('videoNoteButton'); e.type('videoNoteComment','载入完成后的空站立首帧');
  assert.equal(itemNotes(exportedItem(e))[0].video_time_s,0);
  assert.equal(itemNotes(exportedItem(e))[0].source.case_id,'sora/idle');
  assert.equal(e.mock.playCalls,0);
});

module.exports = { makeDataset, createEnvironment };

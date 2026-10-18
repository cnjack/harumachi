'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const { execFileSync } = require('node:child_process');
const { createReviewEnvironment } = require('./dom-harness.cjs');
const test = require('node:test');

// Exercise the real template and scripts with small, deterministic metadata.
// No ignored evidence directory, image files, browser, or Godot process is needed.
function fixtureHtml(transform) {
  const actors = { sora:'空', ren:'莲', haru:'春', mio:'澪', aoi:'小葵', tanaka:'田中', kazuko:'和子' };
  const actions = { idle:'站立', walk:'走路', run:'跑步', wave:'挥手', stretch:'伸展', bow:'鞠躬', dance:'舞蹈' };
  const views = { front:'正面', right:'右侧', back:'背面', left:'左侧', top:'正上方' };
  const cases = [];
  for (const [actor, actor_label] of Object.entries(actors)) {
    for (const [action, action_label] of Object.entries(actions)) {
      const phases = action === 'walk' || action === 'run' ? [0,.125,.25,.5,.75] : [0,.5];
      const frames = phases.flatMap(phase => Object.entries(views).map(([view, view_label]) => {
        const file = `test-poses/${actor}-${action}-p${Math.round(phase * 100)}-${view}.png`;
        const overlay = phase === .125 ? null : `skeleton-overlay/${file}`;
        return { key:`${actor}/${action}/${Math.round(phase * 1000)}/${view}`, phase, view, view_label, file,
          sha256:'a'.repeat(64), overlay, overlay_sha256:overlay ? 'b'.repeat(64) : null };
      }));
      let motion = null;
      if (action === 'walk') motion = { file:`motion/${actor}-walk.gif`, label:'真实连续移动', kind:'native', sha256:'c'.repeat(64) };
      if (actor === 'mio' && action === 'run') motion = { file:'motion/mio-run-fast.gif', label:'快速移动对照 · 4.5米/秒', kind:'fast_fixture', sha256:'d'.repeat(64) };
      cases.push({ id:`${actor}/${action}`, actor, actor_label, action, action_label, phases, frames, motion });
    }
  }
  const data = { id:'human-review-dom-fixture-v1', evidence_id:'memory-only-fixture', case_count:cases.length,
    frame_count:cases.reduce((sum, item) => sum + item.frames.length, 0), views, cases };
  if (transform) transform(data);
  return fs.readFileSync(path.join(__dirname, 'index.template.html'), 'utf8').replace('__REVIEW_DATA__', JSON.stringify(data).replace(/</g, '\\u003c')).replace('__OPTIONAL_REPORT_LINK__', '');
}

function generatedFocusedHtml(reportExists) {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'harumachi-review-report-'));
  try {
    const shots = ['front','right','back','left','top'].map(view => ({id:'ren', action:'walk', view, phase:0, file:`ren-walk-${view}.png`}));
    for (const batch of ['joint-poses','locomotion-poses']) fs.mkdirSync(path.join(folder,batch));
    fs.writeFileSync(path.join(folder,'joint-poses/manifest.json'), JSON.stringify({shots:[]}));
    fs.writeFileSync(path.join(folder,'locomotion-poses/manifest.json'), JSON.stringify({shots}));
    for (const shot of shots) fs.writeFileSync(path.join(folder,'locomotion-poses',shot.file), 'synthetic metadata fixture');
    if (reportExists) fs.writeFileSync(path.join(folder,'REPORT.html'), '<h1>Actual earlier report</h1>');
    execFileSync('python3', [path.join(__dirname,'build.py'),'--evidence',folder,'--actors','ren','--actions','walk']);
    return fs.readFileSync(path.join(folder,'index.html'),'utf8');
  } finally { fs.rmSync(folder, {recursive:true, force:true}); }
}

test('真实builder在无报告的单项collection不产生报告入口', () => {
  const e=createReviewEnvironment(generatedFocusedHtml(false));
  assert.equal(e.document.querySelector('a.report-link'),null);
  assert.equal(e.document.querySelectorAll('[href="REPORT.html"]').length,0);
  assert.equal(e.document.getElementById('caseNumber').textContent,'第 1 / 1 项');
});
test('真实builder在有报告的collection保留原报告入口', () => {
  const e=createReviewEnvironment(generatedFocusedHtml(true));
  const link=e.document.querySelector('a.report-link');
  assert.ok(link);
  assert.equal(link.getAttribute('href'),'REPORT.html');
  assert.equal(link.getAttribute('target'),'_blank');
  assert.match(link.textContent,/查看之前的审查报告/);
});

const tick = () => new Promise(setImmediate);

function env(options) {
  const e = createReviewEnvironment(fixtureHtml(options && options.datasetTransform), options);
  e.el = id => e.document.getElementById(id);
  e.click = id => e.el(id).click();
  e.type = (id, value) => { e.el(id).value = value; e.event(id, 'input'); };
  e.chooseCase = id => e.document.querySelector('[data-case-id="' + id + '"]').click();
  e.stateKey = [...e.storage.keys()].find(k => k.startsWith('harumachi-human-review:') && !k.endsWith(':view'));
  e.state = () => JSON.parse(e.storage.get(e.stateKey));
  e.export = async () => { e.click('downloadJson'); assert.ok(e.downloads.length); return JSON.parse(await e.downloads.at(-1).blob.text()); };
  e.import = async doc => {
    Object.defineProperty(e.el('importFile'), 'files', { configurable: true, value: [{ size: 1, text: async () => JSON.stringify(doc) }] });
    e.event('importFile', 'change'); await tick();
  };
  return e;
}
test('49项与五向画面初始渲染，默认未点评', async () => {
    const e = env();
    assert.equal(e.document.querySelectorAll('.case-button').length, 49);
    assert.equal(e.document.querySelectorAll('.angle-button').length, 5);
    assert.equal(e.el('progressText').textContent, '0 / 49 项已点评');
    const doc = await e.export();
    assert.equal(doc.items.length, 49);
    assert.ok(doc.items.every(i => i.verdict === 'unreviewed'));
  });
function focusRenWalk(data) {
  data.id = 'focused-ren-walk-dom-fixture-v1';
  data.cases = data.cases.filter(item => item.id === 'ren/walk');
  data.case_count = data.cases.length;
  data.frame_count = data.cases.reduce((sum,item) => sum + item.frames.length,0);
}
test('单项莲走路可五向点评和导出，总览与完成提示按1项计算', async () => {
  const e=env({datasetTransform:focusRenWalk});
  assert.equal(e.document.querySelectorAll('.case-button').length,1);
  assert.equal(e.el('caseTitle').textContent,'莲 · 走路');
  assert.equal(e.el('caseNumber').textContent,'第 1 / 1 项');
  assert.equal(e.el('queueCount').textContent,'1 项');
  assert.equal(e.el('progressText').textContent,'0 / 1 项已点评');
  assert.equal(e.document.querySelectorAll('#angleButtons [data-view]').length,5);
  e.document.querySelector('[data-view="top"]').click();
  assert.match(e.el('stageImage').src,/ren-walk-p0-top/);
  e.type('itemComment','只复评莲走路，其他人物不在本次范围');
  e.document.querySelector('[data-verdict="pass"]').click();
  e.click('nextUnreviewed');
  assert.equal(e.el('toastText').textContent,'1项都有判断了，可以导出结果。');
  e.click('overviewButton');
  assert.equal(e.document.querySelectorAll('#overviewRows tr').length,1);
  assert.match(e.el('overviewSummary').textContent,/已点评 1 \/ 1/);
  assert.equal(e.document.querySelector('#overviewDialog h2').textContent,'你的逐项判断');
  const doc=await e.export();
  assert.equal(doc.schema_version,1);
  assert.equal(doc.items.length,1);
  assert.equal(doc.items[0].id,'ren/walk');
  assert.equal(doc.items[0].comment,'只复评莲走路，其他人物不在本次范围');
  assert.equal(doc.items[0].verdict,'pass');
});
test('单项批次刷新和导入保留意见，不能覆盖另一49项批次进度', async () => {
  const old=env();old.type('itemComment','原49项批次意见');
  let e=env({datasetTransform:focusRenWalk,storage:old.storage});
  assert.equal(e.el('itemComment').value,'');
  e.type('itemComment','莲走路单项复评');
  const doc=await e.export();
  e=env({datasetTransform:focusRenWalk,storage:e.storage});
  assert.equal(e.el('itemComment').value,'莲走路单项复评');
  const original=env({storage:e.storage});
  assert.equal(original.el('itemComment').value,'原49项批次意见');
  await original.import(doc);
  assert.match(original.el('toastText').textContent,/没有导入/);
  assert.equal(original.el('itemComment').value,'原49项批次意见');
  const imported=env({datasetTransform:focusRenWalk});
  await imported.import(doc);imported.click('confirmImport');
  assert.equal(imported.el('itemComment').value,'莲走路单项复评');
});
test('单项只有非零相位时从实际首相位开始，保留精确帧来源', async () => {
  const transform=data => {
    focusRenWalk(data);
    data.cases[0].phases=[.25,.75];
    data.cases[0].frames=data.cases[0].frames.filter(frame => [.25,.75].includes(frame.phase));
    data.frame_count=data.cases[0].frames.length;
  };
  const e=env({datasetTransform:transform});
  assert.match(e.el('frameTitle').textContent,/25%/);
  assert.match(e.el('stageImage').src,/ren-walk-p25-front/);
  e.click('frameNoteButton');e.type('frameComment','这个相位复评');
  const doc=await e.export();
  assert.equal(doc.items[0].frame_comments[0].source.phase,.25);
  assert.equal(doc.items[0].frame_comments[0].frame_key,'ren/walk/250/front');
});
test('输入即保存，跨项与刷新后意见和分项不丢', async () => {
    let e = env();
    e.type('itemComment', '第一项的人工点评');
    e.el('criterion-rig').value = 'issue'; e.event('criterion-rig', 'change');
    e.click('nextCase');
    assert.equal(e.el('itemComment').value, '');
    e.type('itemComment', '第二项的点评');
    e.click('previousCase');
    assert.equal(e.el('itemComment').value, '第一项的人工点评');
    assert.equal(e.el('criterion-rig').value, 'issue');
    e = env({ storage: e.storage });
    assert.equal(e.el('itemComment').value, '第一项的人工点评');
    assert.equal(e.el('criterion-rig').value, 'issue');
    assert.equal(e.state().items['sora/walk'].comment, '第二项的点评');
  });
test('帧意见跨相位/方向保留，精确原图坐标与源素材可导出', async () => {
    const e = env();
    e.chooseCase('sora/walk');
    e.document.querySelector('[data-phase="0.125"]').click();
    e.document.querySelector('[data-view="right"]').click();
    e.el('bones').checked = true; e.event('bones', 'change');
    const image = e.el('stageImage');
    Object.defineProperty(image, 'naturalWidth', { configurable: true, value: 1920 });
    Object.defineProperty(image, 'naturalHeight', { configurable: true, value: 1080 });
    image.getBoundingClientRect = () => ({ left: 10, top: 20, width: 1600, height: 900 });
    e.click('pinButton');
    const event = new e.window.Event('click', { bubbles: true });
    Object.assign(event, { clientX: 410, clientY: 695 });
    e.el('imageSurface').dispatchEvent(event);
    assert.equal(e.el('frameEditor').hidden, false);
    e.type('frameComment', '这个相位右膝过弯');
    e.el('bodyPart').value = '膝盖'; e.event('bodyPart', 'change');
    e.document.querySelector('[data-phase="0.25"]').click();
    e.click('nextCase'); e.click('previousCase');
    const doc = await e.export();
    const note = doc.items.find(i => i.id === 'sora/walk').frame_comments[0];
    assert.equal(note.frame_key, 'sora/walk/125/right');
    assert.deepEqual(note.position, { x: .25, y: .75 });
    assert.equal(note.source.phase, .125);
    assert.equal(note.source.view, 'right');
    assert.equal(note.part, '膝盖');
    assert.ok(note.source.file.includes('p13-right'));
    assert.equal(note.mode, 'original'); // This phase has no overlay; fallback must retain real source mode.
    e.document.querySelector('.note-location').click();
    assert.ok(e.el('editorContext').textContent.includes('12.5%'));
    assert.equal(e.el('frameComment').value, '这个相位右膝过弯');
    assert.equal(e.document.querySelector('.pin').style.left, '25%');
  });
test('总评与未点评筛选不使当前编辑项消失', async () => {
    const e = env();
    e.el('filter').value = 'unreviewed'; e.event('filter', 'change');
    e.document.querySelector('[data-verdict="issue"]').click();
    assert.equal(e.el('caseTitle').textContent, '空 · 站立');
    assert.equal(e.document.querySelector('.case-button.active').dataset.caseId, 'sora/idle');
    assert.equal(e.el('progressText').textContent, '1 / 49 项已点评');
    e.document.querySelector('[data-verdict="issue"]').click();
    assert.equal(e.el('progressText').textContent, '0 / 49 项已点评');
  });
test('localStorage读取和写入失败仍可完整导出，并常驻提示', async () => {
    const e = env({ storageReadFails: true, storageWriteFails: true });
    e.type('itemComment', '浏览器不能存储时，意见仍保存在内存');
    e.document.querySelector('[data-verdict="issue"]').click();
    assert.equal(e.el('saveWarning').hidden, false);
    assert.equal(e.el('saveStatus').textContent, '请导出备份');
    const doc = await e.export();
    assert.equal(doc.items[0].comment, '浏览器不能存储时，意见仍保存在内存');
    assert.equal(doc.items[0].verdict, 'issue');
    assert.equal(e.el('saveWarning').hidden, false);
  });
test('错误数据集与无效状态导入不改变当前意见', async () => {
    const e = env();
    e.type('itemComment', '已有意见应当保留');
    const before = await e.export();
    const wrong = structuredClone(before); wrong.dataset.id = 'wrong';
    await e.import(wrong);
    assert.ok(!e.el('importDialog').hasAttribute('open'));
    assert.ok(e.el('toastText').textContent.includes('没有导入'));
    assert.equal(e.state().items['sora/idle'].comment, '已有意见应当保留');
    const invalid = structuredClone(before); invalid.items[0].verdict = 'evil';
    await e.import(invalid);
    assert.ok(e.el('toastText').textContent.includes('没有导入'));
    assert.equal(e.state().items['sora/idle'].comment, '已有意见应当保留');
  });
test('同批次合并保留已有项目，替换后可撤销', async () => {
    const e = env();
    e.type('itemComment', '本地意见');
    const incoming = await e.export();
    incoming.items[0].comment = '导入文件对同项的意见';
    incoming.items[1].comment = '导入文件新增的第二项意见';
    incoming.items[1].verdict = 'issue';
    await e.import(incoming); e.click('confirmImport');
    assert.equal(e.state().items['sora/idle'].comment, '本地意见');
    assert.equal(e.state().items['sora/walk'].comment, '导入文件新增的第二项意见');
    await e.import(incoming);
    e.document.querySelector('input[name="importMode"][value="replace"]').checked = true;
    e.click('confirmImport');
    assert.equal(e.state().items['sora/idle'].comment, '导入文件对同项的意见');
    e.click('undoButton');
    assert.equal(e.state().items['sora/idle'].comment, '本地意见');
    assert.equal(e.state().items['sora/walk'].comment, '导入文件新增的第二项意见');
  });
test('导入后继续写的新意见，不会被旧导入撤销静默抹掉', async () => {
    let e = env();
    const incoming = await e.export(); incoming.items[1].comment = '导入的内容';
    await e.import(incoming); e.click('confirmImport');
    e.type('itemComment', '导入后新写的意见');
    e.click('undoButton');
    assert.equal(e.state().items['sora/idle'].comment, '导入后新写的意见');
    e = env();
    const next = await e.export(); next.items[1].comment = '另一次导入的内容';
    await e.import(next); e.click('confirmImport'); e.click('exportButton');
    e.type('reviewer', '导入后填写的名字'); e.click('undoButton');
    assert.equal(e.state().reviewer, '导入后填写的名字');
  });
test('导入自由文本作为纯文本显示，JSON与Markdown保留', async () => {
    const e = env();
    const incoming = await e.export();
    const text = '<img src=x onerror="window.pwned=true"> & 人工意见';
    incoming.items[0].comment = text;
    incoming.items[0].frame_comments = [{ id:'xss-test', frame_key:'sora/idle/0/front', text, part:'<b>膝盖</b>', position:null, mode:'original', created_at:'2026-10-17T00:00:00Z' }];
    await e.import(incoming); e.click('confirmImport');
    assert.equal(e.el('itemComment').value, text);
    assert.equal(e.document.querySelector('.note-content').textContent, text);
    assert.equal(e.document.querySelector('.note-content img'), null);
    assert.equal(e.window.pwned, undefined);
    const doc = await e.export(); assert.equal(doc.items[0].frame_comments[0].text, text);
    e.click('downloadMarkdown');
    assert.ok((await e.downloads.at(-1).blob.text()).includes(text));
  });
test('无法读取的旧进度不会被静默覆盖', async () => {
    const first = env(); const storage = first.storage; const key = first.stateKey;
    storage.set(key, '{broken-json');
    const e = env({ storage });
    assert.equal(e.el('saveWarning').hidden, false);
    e.type('itemComment', '新意见');
    assert.equal(storage.get(key), '{broken-json');
    const doc = await e.export(); assert.equal(doc.items[0].comment, '新意见');
    assert.equal(storage.get(key), '{broken-json');
  });
test('连续动作仅存在时可进入，快速移动对照有明确说明', async () => {
    const e = env();
    assert.equal(e.el('motionTab').disabled, true);
    e.chooseCase('mio/run'); e.click('motionTab');
    assert.equal(e.el('staticControls').hidden, true);
    assert.equal(e.el('pinButton').disabled, true);
    assert.ok(e.el('imageMessage').textContent.includes('4.5米/秒'));
    e.click('nextCase');
    assert.equal(e.el('staticControls').hidden, false);
  });
test('骨架模式的意见带有骨架来源路径与哈希', async () => {
    const e = env(); e.chooseCase('sora/walk');
    e.el('bones').checked = true; e.event('bones', 'change');
    e.click('frameNoteButton'); e.type('frameComment', '骨架意见');
    const doc = await e.export();
    const note = doc.items.find(i => i.id === 'sora/walk').frame_comments[0];
    assert.equal(note.mode, 'bones');
    assert.ok(JSON.stringify(note.source).includes('skeleton-overlay'));
    assert.equal(note.source.overlay_sha256.length, 64);
  });
test('图片未载入不记已看，过期load回调不污染新项目', async () => {
    const e = env(); const staleLoad = e.el('stageImage').onload;
    assert.equal(e.state().items['sora/idle'].seen_frames.length, 0);
    e.click('nextCase'); staleLoad();
    assert.equal(e.state().items['sora/idle'].seen_frames.length, 0);
    assert.equal(e.state().items['sora/walk'].seen_frames.length, 0);
    e.el('stageImage').onerror();
    assert.equal(e.state().items['sora/walk'].seen_frames.length, 0);
    assert.ok(e.el('imageMessage').classList.contains('error'));
    e.el('stageImage').onload();
    assert.equal(e.state().items['sora/walk'].seen_frames.length, 1);
    assert.equal(e.el('progressText').textContent, '0 / 49 项已点评');
  });
test('帧意见删除可撤销，跨项撤销恢复到原人物动作', async () => {
    const e = env(); e.click('frameNoteButton'); e.type('frameComment', '待删意见');
    e.document.querySelector('.note-actions button:last-child').click();
    assert.equal(e.state().items['sora/idle'].frame_comments.length, 0);
    e.click('nextCase'); e.click('undoButton');
    assert.equal(e.state().items['sora/idle'].frame_comments[0].text, '待删意见');
    assert.equal(e.state().items['sora/walk'].frame_comments.length, 0);
  });

function threeViewData(data) {
  const item = data.cases.find(c => c.id === 'ren/run');
  item.motion = null; // A new collection need not contain the old right alias.
  item.motion_views = Object.fromEntries(['front','right','back'].map(view => [view,{
    file:`motion/ren-run-fast-${view}.gif`,view,view_label:data.views[view],
    label:`快速移动对照 · ${view === 'right' ? '4.5' : '3.2'}米/秒`,
    speed_label:`${view === 'right' ? '4.5' : '3.2'}米/秒`,kind:'fast_fixture',sha256:view.repeat(16)
  }]));
}
const motionView = (e,view) => e.document.querySelector('[data-motion-view="' + view + '"]');

test('真实连续移动按当前正右背视角选择各自GIF，速度来自该视角记录', () => {
  const e = env({datasetTransform:threeViewData});
  e.chooseCase('ren/run'); e.click('motionTab');
  assert.equal(e.el('motionControls').hidden,false);
  assert.equal(e.el('stageImage').src,'motion/ren-run-fast-front.gif');
  assert.match(e.el('frameTitle').textContent,/正面.*3\.2米\/秒/);
  assert.match(e.el('imageMessage').textContent,/3\.2米\/秒/);
  assert.doesNotMatch(e.el('imageMessage').textContent,/4\.5米\/秒/);
  motionView(e,'right').click();
  assert.equal(e.el('stageImage').src,'motion/ren-run-fast-right.gif');
  assert.match(e.el('frameTitle').textContent,/右侧.*4\.5米\/秒/);
  assert.match(e.el('imageMessage').textContent,/4\.5米\/秒/);
  motionView(e,'back').click();
  assert.equal(e.el('stageImage').src,'motion/ren-run-fast-back.gif');
  assert.match(e.el('stageImage').alt,/背面/);
  assert.equal(motionView(e,'back').getAttribute('aria-pressed'),'true');
});

test('缺少正上方连续录制时显示实际右侧和已有方向，静态正上方选择保留', () => {
  const e = env({datasetTransform:threeViewData});
  e.chooseCase('ren/run');
  e.document.querySelector('[data-view="top"]').click(); e.click('motionTab');
  assert.equal(e.el('stageImage').src,'motion/ren-run-fast-right.gif');
  assert.match(e.el('frameTitle').textContent,/^右侧/);
  assert.doesNotMatch(e.el('stageImage').alt,/正上方/);
  assert.match(e.el('motionViewNotice').textContent,/尚未录制正上方.*当前显示右侧/);
  assert.match(e.el('motionViewNotice').textContent,/正面、右侧、背面/);
  assert.equal(motionView(e,'top').disabled,true);
  assert.equal(motionView(e,'left').disabled,true);
  motionView(e,'top').click();
  assert.equal(e.el('stageImage').src,'motion/ren-run-fast-right.gif');
  e.click('staticTab');
  assert.match(e.el('stageImage').src,/-top\.png$/);
  assert.equal(e.el('motionControls').hidden,true);
});

test('没有右侧时只回退到真实已有方向，旧单motion始终标明右侧', () => {
  const e = env({datasetTransform:data => {threeViewData(data);delete data.cases.find(c => c.id === 'ren/run').motion_views.right;}});
  e.chooseCase('ren/run');e.document.querySelector('[data-view="right"]').click();e.click('motionTab');
  assert.equal(e.el('stageImage').src,'motion/ren-run-fast-front.gif');
  assert.match(e.el('motionViewNotice').textContent,/尚未录制右侧.*当前显示正面/);
  const legacy = env();legacy.chooseCase('mio/run');legacy.document.querySelector('[data-view="top"]').click();legacy.click('motionTab');
  assert.equal(legacy.el('stageImage').src,'motion/mio-run-fast.gif');
  assert.match(legacy.el('frameTitle').textContent,/^右侧/);
  assert.match(legacy.el('motionViewNotice').textContent,/已有实际录制方向：右侧/);
});

test('五向连续素材存在时左侧和顶部独立显示，不共用右侧GIF', () => {
  const e = env({datasetTransform:data => {
    threeViewData(data);const item=data.cases.find(c => c.id === 'ren/run');
    for(const view of ['left','top'])item.motion_views[view]={...item.motion_views.front,view,file:`motion/ren-run-fast-${view}.gif`};
  }});
  e.chooseCase('ren/run');e.click('motionTab');
  for(const view of ['left','top']) {
    assert.equal(motionView(e,view).disabled,false);motionView(e,view).click();
    assert.equal(e.el('stageImage').src,`motion/ren-run-fast-${view}.gif`);
    assert.equal(e.el('stageImage').dataset.view,view);
  }
});

test('连续模式不显示或新建静态XY标记，也不把GIF载入记成已看静态帧', async () => {
  const e = env({datasetTransform:threeViewData});e.chooseCase('ren/run');
  Object.defineProperty(e.el('stageImage'),'naturalWidth',{configurable:true,value:1600});
  Object.defineProperty(e.el('stageImage'),'naturalHeight',{configurable:true,value:900});
  e.click('pinButton');
  const click=new e.window.Event('click',{bubbles:true});Object.assign(click,{clientX:250,clientY:350});
  e.el('imageSurface').dispatchEvent(click);
  e.type('frameComment','静态正面膝盖意见');e.click('finishFrameEditor');
  assert.equal(e.el('pinLayer').children.length,1);
  const before=e.state().items['ren/run'];
  assert.deepEqual(before.frame_comments[0].position,{x:.25,y:.5});
  e.click('motionTab');e.el('stageImage').onload();e.click('pinButton');e.click('frameNoteButton');
  assert.equal(e.el('pinLayer').children.length,0);
  assert.equal(e.el('frameEditor').hidden,true);
  assert.equal(e.el('imageSurface').classList.contains('pin-mode'),false);
  assert.deepEqual(e.state().items['ren/run'].seen_frames,before.seen_frames);
  assert.deepEqual(e.state().items['ren/run'].frame_comments,before.frame_comments);
  const doc=await e.export();const item=doc.items.find(i=>i.id==='ren/run');
  assert.equal(item.frame_comments[0].source.view,'front');
  assert.deepEqual(item.frame_comments[0].position,{x:.25,y:.5});
  assert.match(item.frame_comments[0].source.file,/\.png$/);
  e.document.querySelector('.note-location').click();
  assert.equal(e.el('staticControls').hidden,false);
  assert.match(e.el('stageImage').src,/\.png$/);
});

test('新多视角界面的选择和意见可刷新恢复，继续沿用原JSON导入协议', async () => {
  let e=env({datasetTransform:threeViewData});e.chooseCase('ren/run');e.click('motionTab');motionView(e,'back').click();
  e.type('itemComment','背面连续动作仍需复评');const doc=await e.export();
  e=env({datasetTransform:threeViewData,storage:e.storage});
  assert.equal(e.el('stageImage').src,'motion/ren-run-fast-back.gif');
  assert.equal(e.el('itemComment').value,'背面连续动作仍需复评');
  const imported=env({datasetTransform:threeViewData});await imported.import(doc);imported.click('confirmImport');
  imported.chooseCase('ren/run');assert.equal(imported.el('itemComment').value,'背面连续动作仍需复评');
  assert.equal(doc.schema_version,1);
});

'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const { createReviewEnvironment } = require('./dom-harness.cjs');
const test = require('node:test');

// Exercise the real template and scripts with small, deterministic metadata.
// No ignored evidence directory, image files, browser, or Godot process is needed.
function fixtureHtml() {
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
  return fs.readFileSync(path.join(__dirname, 'index.template.html'), 'utf8').replace('__REVIEW_DATA__', JSON.stringify(data).replace(/</g, '\\u003c'));
}

const tick = () => new Promise(setImmediate);

function env(options) {
  const e = createReviewEnvironment(fixtureHtml(), options);
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

'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const M = require('./review-model.js');

const dataset = {
  id: 'character-rig-v1', evidence_id: 'rig_audit_20261017',
  cases: [
    { id: 'sora/walk', actor: 'sora', actor_label: '空', action: 'walk', action_label: '走路', motion: 'walk.webm', frames: [
      { key: 'sora/walk/125/right', phase: 0.125, view: 'right', view_label: '右侧', file: 'walk-125-right.png', sha256: 'abc', overlay: 'walk-125-right-bones.png', overlay_sha256: 'overlay-abc' },
      { key: 'sora/walk/150/right', phase: 0.15, view: 'right', view_label: '右侧', file: 'walk-150-right.png', sha256: 'def', overlay: null }
    ] },
    { id: 'tanaka/run', actor: 'tanaka', actor_label: '田中', action: 'run', action_label: '跑步', motion: null, frames: [{ key: 'tanaka/run/0/front', phase: 0, view: 'front', view_label: '正面', file: 'run-0-front.png', sha256: 'ghi', overlay: null }] }
  ]
};
const copy = value => JSON.parse(JSON.stringify(value));
const note = () => ({ id: 'note-1', frame_key: 'sora/walk/125/right', text: '右膝弯曲过深', part: '右膝', position: { x: 0.234567, y: 0.876543 }, mode: 'bones', created_at: '2026-10-17T00:00:00.000Z' });

test('新建状态保留所有未点评项，各项互不共享可变对象', () => {
  const state = M.createState(dataset);
  assert.equal(Object.keys(state.items).length, 2);
  assert.equal(state.items['sora/walk'].verdict, 'unreviewed');
  state.items['sora/walk'].criteria.rig = 'issue';
  assert.equal(state.items['tanaka/run'].criteria.rig, 'unreviewed');
  assert.deepEqual(M.progress(state), { total: 2, reviewed: 0, pass: 0, issue: 0, unsure: 0, later: 0, unreviewed: 2, notes: 0 });
});

test('跨数据集与跨证据批次拒绝导入', () => {
  const state = M.createState(dataset);
  state.dataset.id = 'another-dataset';
  assert.throws(() => M.normalizeImport(state, dataset), /其他数据集/);
  state.dataset.id = dataset.id; state.dataset.evidence_id = 'older-evidence';
  assert.throws(() => M.normalizeImport(state, dataset), /证据批次/);
});

test('未给总评但有局部意见的项目完整导出，未点评项也保留', () => {
  const state = M.createState(dataset);
  state.items['sora/walk'].frame_comments.push(note());
  state.items['sora/walk'].comment = '先记录右膝，其他尚未确认。';
  state.items['sora/walk'].criteria.joints = 'issue';
  const before = copy(state), doc = M.exportDocument(state, dataset);
  assert.equal(doc.items.length, 2);
  assert.equal(doc.items[0].verdict, 'unreviewed');
  assert.equal(doc.items[0].frame_comments[0].text, '右膝弯曲过深');
  assert.equal(doc.items[1].verdict, 'unreviewed');
  assert.equal(doc.progress.reviewed, 0);
  assert.equal(doc.progress.notes, 1);
  assert.equal(M.hasFeedback(state.items['sora/walk']), true);
  assert.deepEqual(state, before);
  const markdown = M.toMarkdown(state, dataset);
  assert.match(markdown, /未点评 2/);
  assert.match(markdown, /先记录右膝/);
  assert.match(markdown, /右膝弯曲过深/);
  assert.match(markdown, /田中 · 跑步/);
});

test('帧坐标与精确相位不变，不把相邻相位的素材混淆', () => {
  const state = M.createState(dataset);
  state.items['sora/walk'].frame_comments.push(note());
  const doc = M.exportDocument(state, dataset), exportedNote = doc.items[0].frame_comments[0];
  assert.deepEqual(exportedNote.position, { x: 0.234567, y: 0.876543 });
  assert.deepEqual(exportedNote.source, { file: 'walk-125-right.png', sha256: 'abc', phase: 0.125, view: 'right', overlay_file: 'walk-125-right-bones.png', overlay_sha256: 'overlay-abc' });
  assert.match(M.toMarkdown(state, dataset), /相位：0\.125（12\.5%）/);
  assert.equal(M.normalizeImport(doc, dataset).items['sora/walk'].frame_comments[0].frame_key, 'sora/walk/125/right');
});

test('已看记录去重，查看和稍后再看均不算完成点评', () => {
  const state = M.createState(dataset);
  state.items['sora/walk'].seen_frames = ['sora/walk/125/right', 'sora/walk/125/right'];
  const imported = M.normalizeImport(state, dataset);
  assert.deepEqual(imported.items['sora/walk'].seen_frames, ['sora/walk/125/right']);
  assert.equal(M.hasFeedback(imported.items['sora/walk']), false);
  imported.items['sora/walk'].verdict = 'later';
  imported.items['tanaka/run'].verdict = 'unsure';
  assert.equal(M.progress(imported).reviewed, 1);
  assert.equal(M.progress(imported).later, 1);
});

test('对象和数组格式都可导入，缺失项目补为未点评', () => {
  const state = M.createState(dataset);
  state.items['sora/walk'].verdict = 'issue';
  delete state.items['tanaka/run'];
  const imported = M.normalizeImport(state, dataset);
  assert.equal(imported.items['sora/walk'].verdict, 'issue');
  assert.equal(imported.items['tanaka/run'].verdict, 'unreviewed');
  assert.equal(Object.keys(M.normalizeImport(M.exportDocument(imported, dataset), dataset).items).length, 2);
});

test('未知项目、未知帧与项目内错放的帧必须拒绝', () => {
  const state = M.createState(dataset);
  const unknown = copy(state); unknown.items = [{ ...unknown.items['sora/walk'], id: 'unknown' }];
  assert.throws(() => M.normalizeImport(unknown, dataset), /未知项目/);
  state.items['sora/walk'].frame_comments.push({ ...note(), frame_key: 'sora/walk/126/right' });
  assert.throws(() => M.normalizeImport(state, dataset), /未知帧/);
  state.items['sora/walk'].frame_comments = [];
  state.items['sora/walk'].seen_frames = ['tanaka/run/0/front'];
  assert.throws(() => M.normalizeImport(state, dataset), /不属于项目/);
});

test('恶意状态、越界坐标、过长文本、重复项目拒绝', () => {
  const invalids = [
    state => { state.items['sora/walk'].verdict = '<script>alert(1)</script>'; },
    state => { state.items['sora/walk'].criteria.rig = 'later'; },
    state => { state.items['sora/walk'].criteria.unknown = 'pass'; },
    state => { state.items['sora/walk'].frame_comments = [{ ...note(), position: { x: -0.01, y: 0.2 } }]; },
    state => { state.items['sora/walk'].frame_comments = [{ ...note(), position: { x: Infinity, y: 0.2 } }]; },
    state => { state.items['sora/walk'].frame_comments = [{ ...note(), mode: 'html' }]; },
    state => { state.items['sora/walk'].comment = 'a'.repeat(12001); },
    state => { state.items = [state.items['sora/walk'], state.items['sora/walk']]; }
  ];
  invalids.forEach(mutate => { const state = M.createState(dataset); mutate(state); assert.throws(() => M.normalizeImport(state, dataset), Error); });
});

test('导入文本按文本保留，导出独立副本且不信任旧 source 元数据', () => {
  const state = M.createState(dataset);
  state.items['sora/walk'].comment = '<img src=x onerror=alert(1)>';
  state.items['sora/walk'].frame_comments = [{ ...note(), source: { file: 'wrong.png', phase: 0.15 } }];
  const imported = M.normalizeImport(state, dataset), doc = M.exportDocument(imported, dataset);
  assert.equal(imported.items['sora/walk'].comment, '<img src=x onerror=alert(1)>');
  assert.equal(doc.items[0].frame_comments[0].source.file, 'walk-125-right.png');
  doc.items[0].frame_comments[0].position.x = 0;
  assert.equal(imported.items['sora/walk'].frame_comments[0].position.x, 0.234567);
});

test('骨架意见携带叠图来源，无骨架叠图的帧拒绝骨架模式意见', () => {
  const state = M.createState(dataset);
  state.items['sora/walk'].frame_comments.push(note());
  const doc = M.exportDocument(state, dataset), source = doc.items[0].frame_comments[0].source;
  assert.equal(source.overlay_file, 'walk-125-right-bones.png');
  assert.equal(source.overlay_sha256, 'overlay-abc');
  assert.match(M.toMarkdown(state, dataset), /骨架叠图：`walk-125-right-bones\.png`/);
  assert.match(M.toMarkdown(state, dataset), /骨架叠图 SHA-256：`overlay-abc`/);
  state.items['sora/walk'].frame_comments[0].mode = 'original';
  assert.equal(Object.hasOwn(M.exportDocument(state, dataset).items[0].frame_comments[0].source, 'overlay_file'), false);
  state.items['sora/walk'].frame_comments[0].frame_key = 'sora/walk/150/right';
  state.items['sora/walk'].frame_comments[0].mode = 'bones';
  assert.throws(() => M.normalizeImport(state, dataset), /没有骨架叠图/);
});

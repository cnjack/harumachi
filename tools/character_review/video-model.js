(function (root) {
  'use strict';
  const SCHEMA = 'harumachi-video-review/v1';
  const VERDICTS = ['unreviewed', 'pass', 'issue', 'unsure', 'later'];
  const REVIEWED = ['pass', 'issue', 'unsure'];
  const fail = message => { throw new Error(message); };
  const clone = value => JSON.parse(JSON.stringify(value));
  function canonical(value) {
    if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
    if (value && typeof value === 'object') return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
    return JSON.stringify(value);
  }
  function keys(value, expected, label) {
    if (!value || typeof value !== 'object' || Array.isArray(value) || canonical(Object.keys(value).sort()) !== canonical([...expected].sort())) fail(label + ' 字段不完整或包含未知字段');
  }
  function text(value, max, label) {
    if (typeof value !== 'string' || value.length > max) fail(label + ' 无效或过长');
  }
  function caseSource(item) {
    return {case_id: item.id, case_sha256: item.source_sha256, media_file: item.media_file, media_sha256: item.media_sha256,
      journal_sha256: item.journal_sha256, model_sha256: item.model_sha256, start_s: item.start_s, end_s: item.end_s, fps: item.fps};
  }
  function createReview(data) {
    return {schema: SCHEMA, dataset: {id: data.id, source_sha256: data.source_sha256, identity: clone(data.identity)}, reviewer: '',
      exported_at: new Date().toISOString(), items: data.cases.map(item => ({id: item.id, source: caseSource(item), verdict: 'unreviewed', comment: '', time_comments: []}))};
  }
  function validateReview(document, data) {
    keys(document, ['schema', 'dataset', 'reviewer', 'exported_at', 'items'], '点评');
    if (document.schema !== SCHEMA) fail('这不是新版视频点评文件');
    keys(document.dataset, ['id', 'source_sha256', 'identity'], '数据批次');
    if (canonical(document.dataset) !== canonical({id: data.id, source_sha256: data.source_sha256, identity: data.identity})) fail('数据批次或模型／媒体身份不同');
    text(document.reviewer, 100, '称呼');
    if (typeof document.exported_at !== 'string' || !Number.isFinite(Date.parse(document.exported_at))) fail('导出时间无效');
    if (!Array.isArray(document.items) || document.items.length !== data.cases.length) fail('必须包含完整的逐项点评');
    const seen = new Set();
    for (const item of document.items) {
      keys(item, ['id', 'source', 'verdict', 'comment', 'time_comments'], '项目');
      const original = data.cases.find(value => value.id === item.id);
      if (!original || seen.has(item.id)) fail('项目未知或重复');
      seen.add(item.id);
      const expected = caseSource(original);
      if (canonical(item.source) !== canonical(expected)) fail('项目媒体、范围或模型身份不同');
      if (!VERDICTS.includes(item.verdict)) fail('判断状态无效');
      text(item.comment, 20000, '本项意见');
      if (!Array.isArray(item.time_comments) || item.time_comments.length > 2000) fail('时间点意见列表无效');
      const ids = new Set();
      for (const note of item.time_comments) {
        keys(note, ['id', 'video_time_s', 'text', 'source'], '时间点意见');
        text(note.id, 160, '意见编号');
        if (!note.id || ids.has(note.id)) fail('时间点意见编号重复');
        ids.add(note.id);
        if (typeof note.video_time_s !== 'number' || !Number.isFinite(note.video_time_s) || note.video_time_s < original.start_s || note.video_time_s >= original.end_s) fail('时间点必须在本项视频范围内');
        text(note.text, 20000, '时间点意见');
        if (canonical(note.source) !== canonical(expected)) fail('时间点意见属于其他项目或媒体');
      }
    }
    // Validate everything before returning a fresh object for atomic replacement.
    return clone(document);
  }
  const api = {SCHEMA, VERDICTS, REVIEWED, canonical, clone, caseSource, createReview, validateReview,
    reviewedCount: review => review.items.filter(item => REVIEWED.includes(item.verdict)).length};
  root.VideoReviewModel = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);

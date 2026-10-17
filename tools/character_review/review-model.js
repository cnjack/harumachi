(function (root, factory) {
  'use strict';
  var api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.ReviewModel = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  var FORMAT = 'harumachi-character-human-review';
  var VERSION = 1;
  var VERDICTS = Object.freeze(['unreviewed', 'pass', 'issue', 'unsure', 'later']);
  var CRITERIA = Object.freeze(['rig', 'clothing', 'joints', 'motion']);
  var CRITERION_VERDICTS = ['unreviewed', 'pass', 'issue', 'unsure'];
  var LABELS = { unreviewed: '未点评', pass: '通过', issue: '有问题', unsure: '不确定', later: '稍后再看' };
  var CRITERION_LABELS = { rig: '骨骼绑定', clothing: '衣服贴合', joints: '关节弯曲', motion: '动作自然度' };
  var own = function (value, key) { return Object.prototype.hasOwnProperty.call(value, key); };

  function fail(message) { throw new Error(message); }
  function record(value) { return !!value && typeof value === 'object' && !Array.isArray(value); }
  function string(value, max, label) {
    if (typeof value !== 'string' || value.length > max) fail(label + '必须是长度不超过 ' + max + ' 的文本。');
    return value;
  }
  function identifier(value, label) {
    string(value, 256, label);
    if (!value.trim()) fail(label + '不能为空。');
    return value;
  }
  function timestamp(value, label, nullable) {
    if (nullable && value === null) return null;
    string(value, 64, label);
    if (!value || !Number.isFinite(Date.parse(value))) fail(label + '不是有效时间。');
    return value;
  }
  function status(value, allowed, label) {
    if (typeof value !== 'string' || allowed.indexOf(value) < 0) fail(label + '包含无效状态。');
    return value;
  }
  function indexDataset(dataset) {
    if (!record(dataset)) fail('缺少有效的点评数据集。');
    identifier(dataset.id, '数据集 ID');
    identifier(dataset.evidence_id, '证据 ID');
    if (!Array.isArray(dataset.cases) || dataset.cases.length > 1000) fail('点评项目列表无效。');
    var cases = new Map();
    dataset.cases.forEach(function (item) {
      if (!record(item)) fail('点评项目格式无效。');
      identifier(item.id, '项目 ID');
      if (cases.has(item.id)) fail('数据集内有重复的项目 ID：' + item.id);
      if (!Array.isArray(item.frames) || item.frames.length > 10000) fail('项目的帧列表无效：' + item.id);
      var frames = new Map();
      item.frames.forEach(function (frame) {
        if (!record(frame)) fail('帧格式无效：' + item.id);
        identifier(frame.key, '帧 ID');
        if (frames.has(frame.key)) fail('数据集内有重复的帧 ID：' + frame.key);
        if (typeof frame.phase !== 'number' || !Number.isFinite(frame.phase) || frame.phase < 0 || frame.phase > 1) fail('帧相位无效：' + frame.key);
        frames.set(frame.key, frame);
      });
      cases.set(item.id, { item: item, frames: frames });
    });
    return cases;
  }
  function newItem(id) {
    return { id: id, verdict: 'unreviewed', criteria: { rig: 'unreviewed', clothing: 'unreviewed', joints: 'unreviewed', motion: 'unreviewed' }, comment: '', frame_comments: [], seen_frames: [], updated_at: null };
  }
  function createState(dataset) {
    indexDataset(dataset);
    var now = new Date().toISOString();
    return {
      format: FORMAT,
      schema_version: VERSION,
      dataset: { id: dataset.id, evidence_id: dataset.evidence_id },
      reviewer: '',
      created_at: now,
      updated_at: now,
      items: Object.fromEntries(dataset.cases.map(function (item) { return [item.id, newItem(item.id)]; }))
    };
  }
  function normalizeImport(raw, dataset) {
    var cases = indexDataset(dataset);
    if (typeof raw === 'string') {
      if (raw.length > 10 * 1024 * 1024) fail('点评文件超过 10 MB，请检查是否选择了正确文件。');
      try { raw = JSON.parse(raw); } catch (error) { fail('点评文件不是有效 JSON。'); }
    }
    if (!record(raw) || raw.format !== FORMAT || raw.schema_version !== VERSION) fail('点评文件格式或版本不匹配。');
    if (!record(raw.dataset) || raw.dataset.id !== dataset.id || raw.dataset.evidence_id !== dataset.evidence_id) fail('点评文件属于其他数据集或证据批次，不能导入。');
    var state = createState(dataset);
    if (own(raw, 'reviewer')) state.reviewer = string(raw.reviewer, 120, '点评人');
    if (own(raw, 'created_at')) state.created_at = timestamp(raw.created_at, '创建时间');
    if (own(raw, 'updated_at')) state.updated_at = timestamp(raw.updated_at, '更新时间');
    if (!Array.isArray(raw.items) && !record(raw.items)) fail('点评项目必须是对象或数组。');
    var entries = Array.isArray(raw.items) ? raw.items.map(function (item) { return [record(item) ? item.id : undefined, item]; }) : Object.entries(raw.items);
    if (entries.length > cases.size) fail('点评文件中的项目数量超出当前数据集。');
    var imported = new Set();
    var totalNotes = 0;
    entries.forEach(function (entry) {
      var id = entry[0], source = entry[1];
      if (!record(source) || typeof id !== 'string' || !cases.has(id)) fail('点评文件包含未知项目：' + String(id).slice(0, 256));
      if (source.id !== id) fail('项目 ID 与索引不一致：' + id);
      if (imported.has(id)) fail('点评文件包含重复项目：' + id);
      imported.add(id);
      var target = state.items[id], frames = cases.get(id).frames;
      if (own(source, 'verdict')) target.verdict = status(source.verdict, VERDICTS, '项目 ' + id);
      if (own(source, 'criteria')) {
        if (!record(source.criteria)) fail('项目分项结论格式无效：' + id);
        Object.keys(source.criteria).forEach(function (criterion) {
          if (CRITERIA.indexOf(criterion) < 0) fail('包含未知点评分项：' + criterion);
          target.criteria[criterion] = status(source.criteria[criterion], CRITERION_VERDICTS, '分项 ' + criterion);
        });
      }
      if (own(source, 'comment')) target.comment = string(source.comment, 12000, '项目意见');
      if (own(source, 'updated_at')) target.updated_at = timestamp(source.updated_at, '项目更新时间', true);
      if (own(source, 'seen_frames')) {
        if (!Array.isArray(source.seen_frames) || source.seen_frames.length > 10000) fail('已看帧列表无效：' + id);
        var seen = new Set();
        source.seen_frames.forEach(function (key) {
          if (typeof key !== 'string' || !frames.has(key)) fail('包含不属于项目的已看帧：' + String(key).slice(0, 256));
          seen.add(key);
        });
        target.seen_frames = Array.from(seen);
      }
      if (own(source, 'frame_comments')) {
        if (!Array.isArray(source.frame_comments) || source.frame_comments.length > 1000) fail('单帧意见列表无效或过长：' + id);
        var noteIds = new Set();
        target.frame_comments = source.frame_comments.map(function (note) {
          totalNotes += 1;
          if (totalNotes > 10000) fail('单帧意见总数超过上限。');
          if (!record(note)) fail('单帧意见格式无效：' + id);
          identifier(note.id, '意见 ID');
          if (noteIds.has(note.id)) fail('同一项目包含重复的意见 ID。');
          noteIds.add(note.id);
          if (typeof note.frame_key !== 'string' || !frames.has(note.frame_key)) fail('单帧意见引用了未知帧：' + String(note.frame_key).slice(0, 256));
          var mode = status(note.mode, ['original', 'bones'], '图片模式');
          if (mode === 'bones' && !frames.get(note.frame_key).overlay) fail('该帧没有骨架叠图，不能导入骨架模式意见：' + note.frame_key);
          var position = null;
          if (note.position !== null && note.position !== undefined) {
            if (!record(note.position) || typeof note.position.x !== 'number' || typeof note.position.y !== 'number' || !Number.isFinite(note.position.x) || !Number.isFinite(note.position.y) || note.position.x < 0 || note.position.x > 1 || note.position.y < 0 || note.position.y > 1) fail('标记坐标必须在 0 到 1 之间。');
            position = { x: note.position.x, y: note.position.y };
          }
          return {
            id: note.id,
            frame_key: note.frame_key,
            text: string(note.text, 6000, '单帧意见'),
            part: own(note, 'part') ? string(note.part, 120, '身体部位') : '',
            position: position,
            mode: mode,
            created_at: timestamp(note.created_at, '单帧意见时间')
          };
        });
      }
    });
    return state;
  }
  function progress(state) {
    var result = { total: 0, reviewed: 0, pass: 0, issue: 0, unsure: 0, later: 0, unreviewed: 0, notes: 0 };
    Object.values(state.items).forEach(function (item) {
      result.total += 1;
      if (VERDICTS.indexOf(item.verdict) >= 0) result[item.verdict] += 1;
      if (['pass', 'issue', 'unsure'].indexOf(item.verdict) >= 0) result.reviewed += 1;
      result.notes += item.frame_comments.length;
    });
    return result;
  }
  function hasFeedback(item) {
    return item.verdict !== 'unreviewed' || CRITERIA.some(function (key) { return item.criteria[key] !== 'unreviewed'; }) || !!item.comment.trim() || item.frame_comments.length > 0;
  }
  function exportDocument(state, dataset) {
    var clean = normalizeImport(state, dataset);
    var cases = indexDataset(dataset);
    return {
      format: FORMAT,
      schema_version: VERSION,
      dataset: { id: dataset.id, evidence_id: dataset.evidence_id },
      reviewer: clean.reviewer,
      created_at: clean.created_at,
      updated_at: clean.updated_at,
      exported_at: new Date().toISOString(),
      progress: progress(clean),
      items: dataset.cases.map(function (item) {
        var result = clean.items[item.id];
        return {
          id: result.id,
          actor: item.actor,
          actor_label: item.actor_label,
          action: item.action,
          action_label: item.action_label,
          motion: item.motion ? Object.assign({}, item.motion) : null,
          verdict: result.verdict,
          criteria: Object.assign({}, result.criteria),
          comment: result.comment,
          frame_comments: result.frame_comments.map(function (note) {
            var frame = cases.get(item.id).frames.get(note.frame_key);
            var source = { file: frame.file, sha256: frame.sha256, phase: frame.phase, view: frame.view };
            if (note.mode === 'bones' && frame.overlay) {
              source.overlay_file = frame.overlay;
              source.overlay_sha256 = frame.overlay_sha256;
            }
            return Object.assign({}, note, { position: note.position ? Object.assign({}, note.position) : null, source: source });
          }),
          seen_frames: result.seen_frames.slice(),
          updated_at: result.updated_at
        };
      })
    };
  }
  function mdText(value) { return String(value).replace(/\r\n?/g, '\n'); }
  function toMarkdown(state, dataset) {
    var doc = exportDocument(state, dataset), p = doc.progress;
    var lines = [
      '# 人物骨骼与动作人工点评', '',
      '- 数据集：' + doc.dataset.id,
      '- 证据批次：' + doc.dataset.evidence_id,
      '- 点评人：' + (doc.reviewer || '未填写'),
      '- 导出时间：' + doc.exported_at,
      '- 进度：已点评 ' + p.reviewed + ' / ' + p.total + '；通过 ' + p.pass + '；有问题 ' + p.issue + '；不确定 ' + p.unsure + '；稍后再看 ' + p.later + '；未点评 ' + p.unreviewed + '。',
      '- 单帧意见：' + p.notes + ' 条。', '',
      '说明：仅查看图片不算完成点评；“稍后再看”也不计入已点评。', ''
    ];
    doc.items.forEach(function (item) {
      lines.push('## ' + item.actor_label + ' · ' + item.action_label + '（' + item.id + '）', '');
      lines.push('结论：' + LABELS[item.verdict] + '。');
      lines.push(CRITERIA.map(function (key) { return CRITERION_LABELS[key] + '：' + LABELS[item.criteria[key]]; }).join('；') + '。', '');
      if (item.motion) lines.push('连续预览：' + item.motion.label + '；`' + item.motion.file + '`。', '');
      if (item.comment.trim()) lines.push('整体意见：', '', mdText(item.comment), '');
      item.frame_comments.forEach(function (note, index) {
        var frame = dataset.cases.find(function (c) { return c.id === item.id; }).frames.find(function (f) { return f.key === note.frame_key; });
        lines.push('### 单帧意见 ' + (index + 1), '');
        lines.push('- 精确帧：`' + note.frame_key + '`');
        lines.push('- 视角：' + (frame.view_label || frame.view) + '；相位：' + String(frame.phase) + '（' + String(frame.phase * 100) + '%）；模式：' + (note.mode === 'bones' ? '骨架透视' : '原图') + '。');
        if (note.part) lines.push('- 部位：' + mdText(note.part));
        if (note.position) lines.push('- 标记坐标：x=' + String(note.position.x) + '，y=' + String(note.position.y) + '（归一化图片坐标）。');
        lines.push('- 原图：`' + note.source.file + '`', '- SHA-256：`' + note.source.sha256 + '`');
        if (note.source.overlay_file) lines.push('- 骨架叠图：`' + note.source.overlay_file + '`', '- 骨架叠图 SHA-256：`' + note.source.overlay_sha256 + '`');
        lines.push('', mdText(note.text), '');
      });
      if (!hasFeedback(item)) lines.push('尚未填写意见。', '');
    });
    return lines.join('\n');
  }
  return Object.freeze({ FORMAT: FORMAT, SCHEMA_VERSION: VERSION, VERDICTS: VERDICTS, CRITERIA: CRITERIA, createState: createState, normalizeImport: normalizeImport, progress: progress, hasFeedback: hasFeedback, exportDocument: exportDocument, toMarkdown: toMarkdown });
});

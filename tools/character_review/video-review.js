(function () {
  'use strict';
  const M = window.VideoReviewModel;
  const data = JSON.parse(document.getElementById('video-data').textContent);
  const $ = id => document.getElementById(id);
  const video = $('reviewVideo');
  const labels = {unreviewed: '未点评', pass: '通过', issue: '有问题', unsure: '不确定', later: '稍后'};
  const key = 'harumachi-video-review:v1:' + data.id;
  let state = M.createReview(data), index = 0, storageFailed = false, storageBlocked = false, ticket = null, serial = 0, draft = null, noteSerial = 0, pendingImport = null, importSerial = 0, replaying = false, loadedSource = '';
  function warnStorage(message) {
    storageFailed = true;
    $('videoSaveWarning').hidden = false;
    $('videoSaveWarning').textContent = message + ' 当前意见仅保留在本页内存中，请手动导出 JSON；关闭或刷新可能丢失。';
    $('videoSaveStatus').textContent = '本机保存不可用 · 请手动导出';
  }
  try {
    const stored = window.localStorage.getItem(key);
    if (stored) state = M.validateReview(JSON.parse(stored), data);
    $('videoSaveStatus').textContent = '输入后保存在本机';
  } catch (error) { storageBlocked = true; warnStorage('无法读取本批次的有效本机进度；原数据不会被自动覆盖。'); }
  function persist() {
    state.exported_at = new Date().toISOString();
    if (!storageBlocked) {
      try {
        const encoded = JSON.stringify(state);
        window.localStorage.setItem(key, encoded);
        if (window.localStorage.getItem(key) !== encoded) throw new Error('Storage read-back differs');
        if (!storageFailed) $('videoSaveStatus').textContent = '已在本机保存';
      } catch (error) { warnStorage('浏览器未能可靠保存本机进度。'); }
    }
    renderProgress();
    renderList();
  }
  function current() { return data.cases[index]; }
  function item() { return state.items.find(value => value.id === current().id); }
  function toast(message) { $('videoToast').textContent = message; $('videoToast').hidden = false; }
  function dialog(id, open) {
    const element = $(id);
    if (open) { if (element.showModal) element.showModal(); else element.setAttribute('open', ''); }
    else { if (element.close) element.close(); else element.removeAttribute('open'); }
  }
  function seconds(value) { return Number(value).toFixed(3) + ' 秒'; }
  function absolute(path) { return new URL(path, document.baseURI || window.location.href).href; }
  function sameSource() {
    if (!ticket || !video.currentSrc) return false;
    try { return absolute(video.currentSrc) === ticket.url; } catch (error) { return false; }
  }
  function inRange(time) { return typeof time === 'number' && Number.isFinite(time) && time >= current().start_s && time < current().end_s; }
  function ready() { return ticket && ticket.caseId === current().id && ticket.complete && sameSource() && video.readyState >= 2 && !video.seeking && inRange(video.currentTime); }
  function mediaControls() {
    const confirmed = Boolean(ready());
    $('videoNoteButton').disabled = !confirmed;
    $('videoStepBack').disabled = !confirmed;
    $('videoStepForward').disabled = !confirmed;
    $('videoTime').textContent = '视频时间 ' + (Number.isFinite(video.currentTime) ? seconds(video.currentTime) : '—');
    if (confirmed) $('videoMediaStatus').textContent = '已定位，可记录时间点。';
    else if (ticket && ticket.complete && !inRange(video.currentTime)) $('videoMediaStatus').textContent = '当前时间已离开本项范围。重播这一段后再记录意见。';
  }
  function assignSeek() {
    if (!ticket || !sameSource() || video.readyState < 1) return;
    // A real loadeddata observation belongs to the media, not to one actor's
    // case. Reusing its already displayed time also covers seven dance cases
    // sharing one source and rapid idle -> wave -> idle before initial load.
    if (loadedSource === ticket.url && video.readyState >= 2 && !video.seeking && Math.abs(video.currentTime - ticket.target) <= 1e-6) {
      ticket.assigned = true;
      ticket.complete = true;
      mediaControls();
      if (ticket.play) { ticket.play = false; const result = video.play(); if (result && result.catch) result.catch(() => toast('已定位，请点击视频播放按钮。')); }
      return;
    }
    if (ticket.assigned) return;
    // A zero-distance assignment need not emit seeking/seeked. Wait for this
    // source's actual first decoded data instead of treating the setter as ack.
    if (!video.seeking && Math.abs(video.currentTime - ticket.target) <= 1e-6) return;
    ticket.assigned = true;
    ticket.sawSeeking = false;
    ticket.seekWasActive = Boolean(video.seeking);
    video.currentTime = ticket.target;
    ticket.seekWasActive = ticket.seekWasActive || Boolean(video.seeking);
    mediaControls();
  }
  function seek(time, play = false) {
    video.pause();
    const c = current();
    const target = Math.max(c.start_s, Math.min(c.end_s - 1 / c.fps, time));
    ticket = {serial: ++serial, caseId: c.id, url: absolute(c.media_file), target, assigned: false, sawSeeking: false, seekWasActive: Boolean(video.seeking), complete: false, play};
    $('videoMediaStatus').classList.remove('error');
    $('videoMediaStatus').textContent = '正在载入并定位本段，暂不能记录时间点。';
    mediaControls();
    assignSeek();
  }
  video.addEventListener('loadedmetadata', assignSeek);
  video.addEventListener('loadeddata', () => {
    if (video.currentSrc && video.readyState >= 2) loadedSource = absolute(video.currentSrc);
    assignSeek();
  });
  video.addEventListener('seeking', () => {
    if (!ticket || !ticket.assigned || !sameSource()) return;
    // Native controls can seek within the selected source too. A fresh seeked
    // acknowledgement is required, including when only the action changes.
    if (ticket.complete) {
      ticket.complete = false;
      ticket.target = video.currentTime;
    }
    if (Math.abs(video.currentTime - ticket.target) <= 1 / 120) ticket.sawSeeking = true;
    mediaControls();
  });
  video.addEventListener('seeked', () => {
    if (!ticket || ticket.caseId !== current().id || !ticket.assigned || !(ticket.sawSeeking || ticket.seekWasActive) || !sameSource() || video.readyState < 2 || video.seeking || Math.abs(video.currentTime - ticket.target) > 1 / 120 || !inRange(video.currentTime)) { mediaControls(); return; }
    ticket.complete = true;
    loadedSource = ticket.url;
    mediaControls();
    if (ticket.play) {
      ticket.play = false;
      replaying = true;
      const result = video.play();
      if (result && result.catch) result.catch(() => toast('已定位，请使用视频原生播放按钮开始。'));
    }
  });
  video.addEventListener('timeupdate', () => {
    if (replaying && video.currentTime >= current().end_s) { video.pause(); replaying = false; seek(current().end_s - 1 / current().fps); }
    mediaControls();
  });
  video.addEventListener('play', () => {
    if (!sameSource() || !inRange(video.currentTime)) { seek(current().start_s, true); return; }
    if (!ready()) { video.pause(); if (ticket) ticket.play = true; assignSeek(); return; }
    replaying = true;
  });
  video.addEventListener('error', () => {
    if (ticket) ticket.complete = false;
    mediaControls();
    $('videoMediaStatus').classList.add('error');
    $('videoMediaStatus').textContent = '视频未能加载，不能记录时间点；可以从左侧直接打开原片。';
  });
  function renderProgress() {
    const count = M.reviewedCount(state);
    $('videoProgressText').textContent = count + ' / ' + data.cases.length + ' 项已点评';
    $('videoProgress').max = data.cases.length;
    $('videoProgress').value = count;
  }
  function renderList() {
    const list = $('videoCaseList');
    list.replaceChildren();
    const filter = $('videoFilter').value || 'all';
    for (const actor of [...new Set(data.cases.map(c => c.actor))]) {
      const group = document.createElement('div'); group.className = 'actor-group';
      const name = document.createElement('div'); name.className = 'actor-label'; name.textContent = data.cases.find(c => c.actor === actor).actor_label; group.append(name);
      for (const c of data.cases.filter(c => c.actor === actor)) {
        const saved = state.items.find(value => value.id === c.id);
        if (c.id !== current().id && filter !== 'all' && !(filter === 'pending' ? !M.REVIEWED.includes(saved.verdict) : saved.verdict === filter)) continue;
        const button = document.createElement('button'); button.className = 'case-button' + (current().id === c.id ? ' active' : ''); button.dataset.caseId = c.id;
        const dot = document.createElement('span'); dot.className = 'status-dot ' + saved.verdict; button.append(dot, document.createTextNode(c.action_label));
        button.setAttribute('aria-label', c.actor_label + ' · ' + c.action_label + ' · ' + labels[saved.verdict]);
        button.addEventListener('click', () => choose(c.id)); group.append(button);
      }
      if (group.children.length > 1) list.append(group);
    }
  }
  function renderVerdicts() {
    $('videoItemStatus').textContent = labels[item().verdict];
    for (const button of $('videoVerdicts').querySelectorAll('[data-verdict]')) {
      const selected = button.dataset.verdict === item().verdict;
      button.classList.toggle('selected', selected);
      button.setAttribute('aria-pressed', String(selected));
    }
  }
  function renderNotes() {
    const notes = $('videoNotes'); notes.replaceChildren();
    $('videoNotesCount').textContent = item().time_comments.length + ' 条';
    for (const note of item().time_comments) {
      const card = document.createElement('article'); card.className = 'frame-note';
      const location = document.createElement('button'); location.className = 'note-location'; location.textContent = '视频时间 ' + seconds(note.video_time_s) + ' · 定位查看';
      location.addEventListener('click', () => seek(note.video_time_s));
      const content = document.createElement('p'); content.className = 'note-content'; content.textContent = note.text;
      const actions = document.createElement('div'); actions.className = 'note-actions';
      const edit = document.createElement('button'); edit.textContent = '编辑'; edit.addEventListener('click', () => openNote(note));
      const remove = document.createElement('button'); remove.textContent = '删除'; remove.addEventListener('click', () => { item().time_comments = item().time_comments.filter(n => n.id !== note.id); if (draft && draft.id === note.id) closeNote(); persist(); renderNotes(); });
      actions.append(edit, remove); card.append(location, content, actions); notes.append(card);
    }
    if (!item().time_comments.length) { const empty = document.createElement('p'); empty.className = 'empty-notes'; empty.textContent = '可暂停在有疑问的时刻，再记录视频时间意见。'; notes.append(empty); }
  }
  function openNote(note) {
    draft = note;
    $('videoNoteEditor').hidden = false;
    $('videoNoteContext').textContent = current().actor_label + ' · ' + current().action_label + ' / 视频时间 ' + seconds(note.video_time_s);
    $('videoNoteComment').value = note.text;
    $('videoNoteComment').focus();
  }
  function closeNote() { draft = null; $('videoNoteEditor').hidden = true; }
  function choose(id) {
    const next = data.cases.findIndex(c => c.id === id);
    if (next < 0) return;
    index = next;
    replaying = false;
    closeNote();
    const c = current();
    $('videoCaseTitle').textContent = c.actor_label + ' · ' + c.action_label;
    $('videoCaseNumber').textContent = '第 ' + (index + 1) + ' / ' + data.cases.length + ' 项';
    $('videoCaseContext').textContent = c.context;
    $('videoRange').textContent = '本段 ' + seconds(c.start_s) + ' — ' + seconds(c.end_s);
    $('videoIdentity').textContent = c.take + ' / 媒体 ' + c.media_sha256.slice(0, 16) + '… / 模型 ' + c.model_sha256.slice(0, 16) + '…';
    $('videoViewButtons').replaceChildren();
    for (const segment of c.view_segments || []) {
      const button = document.createElement('button'); button.className = 'outline'; button.dataset.view = segment.view;
      button.textContent = segment.view_label; button.title = '定位至视频时间 ' + seconds(segment.start_s);
      button.addEventListener('click', () => seek(segment.start_s)); $('videoViewButtons').append(button);
    }
    $('videoViewNotice').textContent = '点击方向定位镜头；只显示本项实际录制的方向。';
    $('videoComment').value = item().comment;
    $('videoPrevious').disabled = index === 0;
    $('videoNext').disabled = index === data.cases.length - 1;
    $('videoNextBottom').disabled = index === data.cases.length - 1;
    renderVerdicts(); renderNotes(); renderList();
    video.pause();
    const sourceChanged = video.getAttribute('src') !== c.media_file;
    if (sourceChanged) { loadedSource = ''; video.src = c.media_file; video.load(); }
    seek(c.start_s);
  }
  function move(delta) { const c = data.cases[index + delta]; if (c) choose(c.id); }
  for (const verdict of M.VERDICTS) {
    const button = document.createElement('button'); button.dataset.verdict = verdict; button.className = 'verdict-button'; button.textContent = labels[verdict];
    button.addEventListener('click', () => { item().verdict = verdict; persist(); renderVerdicts(); }); $('videoVerdicts').append(button);
  }
  $('videoComment').addEventListener('input', () => { item().comment = $('videoComment').value; persist(); });
  $('videoNoteComment').addEventListener('input', () => { if (!draft) return; draft.text = $('videoNoteComment').value; if (!item().time_comments.some(n => n.id === draft.id)) item().time_comments.push(draft); persist(); renderNotes(); });
  $('videoNoteButton').addEventListener('click', () => {
    if (!ready()) { toast('视频尚未确认定位到本项范围，暂不能记录时间点。'); return; }
    video.pause();
    openNote({id: 'note-' + Date.now() + '-' + (++noteSerial), video_time_s: video.currentTime, text: '', source: M.caseSource(current())});
  });
  $('videoNoteDone').addEventListener('click', closeNote);
  $('videoPrevious').addEventListener('click', () => move(-1)); $('videoNext').addEventListener('click', () => move(1)); $('videoNextBottom').addEventListener('click', () => move(1));
  $('videoNextPending').addEventListener('click', () => {
    for (let delta = 1; delta <= data.cases.length; delta++) { const c = data.cases[(index + delta) % data.cases.length]; if (!M.REVIEWED.includes(state.items.find(i => i.id === c.id).verdict)) { choose(c.id); return; } }
    toast('全部项目都有判断了，可以导出结果。');
  });
  $('videoFilter').addEventListener('change', renderList);
  $('videoReplay').addEventListener('click', () => seek(current().start_s, true));
  $('videoStepBack').addEventListener('click', () => { if (ready()) seek(video.currentTime - 1 / current().fps); });
  $('videoStepForward').addEventListener('click', () => { if (ready()) seek(video.currentTime + 1 / current().fps); });
  $('videoSpeed').addEventListener('change', () => { const rate = Number($('videoSpeed').value); if ([.25, .5, .75, 1].includes(rate)) video.playbackRate = rate; });
  for (const take of data.takes) { const link = document.createElement('a'); link.href = take.file; link.target = '_blank'; link.rel = 'noopener'; link.textContent = take.label + ' ↗'; link.dataset.take = take.id; $('videoTakeLinks').append(link); }
  function exportDocument() { const value = M.clone(state); value.exported_at = new Date().toISOString(); return M.validateReview(value, data); }
  $('videoExportButton').addEventListener('click', () => { $('videoReviewer').value = state.reviewer; $('videoExportSummary').textContent = '完整 ' + data.cases.length + ' 项，其中 ' + M.reviewedCount(state) + ' 项已作判断。'; dialog('videoExportDialog', true); });
  $('videoReviewer').addEventListener('input', () => { state.reviewer = $('videoReviewer').value; persist(); });
  $('videoCloseExport').addEventListener('click', () => dialog('videoExportDialog', false));
  $('videoDownload').addEventListener('click', () => {
    const blob = new Blob([JSON.stringify(exportDocument(), null, 2)], {type: 'application/json'});
    const url = URL.createObjectURL(blob), link = document.createElement('a'); link.href = url; link.download = data.id + '-点评.json'; document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  });
  $('videoImportButton').addEventListener('click', () => { $('videoImportFile').value = ''; $('videoImportFile').click(); });
  $('videoImportFile').addEventListener('change', async () => {
    const file = $('videoImportFile').files && $('videoImportFile').files[0];
    const request = ++importSerial; pendingImport = null;
    if (!file) return;
    try {
      if (file.size > 10 * 1024 * 1024) throw new Error('文件过大');
      const candidate = M.validateReview(JSON.parse(await file.text()), data);
      if (request !== importSerial) return;
      pendingImport = candidate;
      $('videoImportSummary').textContent = '已核对同批次全部 ' + candidate.items.length + ' 项、模型／媒体／范围与时间点意见。文件中 ' + M.reviewedCount(candidate) + ' 项已作判断。';
      dialog('videoImportDialog', true);
    } catch (error) { if (request === importSerial) toast('没有导入：' + error.message); }
  });
  $('videoCancelImport').addEventListener('click', () => { pendingImport = null; ++importSerial; dialog('videoImportDialog', false); });
  $('videoImportDialog').addEventListener('cancel', () => { pendingImport = null; ++importSerial; });
  $('videoConfirmImport').addEventListener('click', () => {
    if (!pendingImport) return;
    const replacement = M.validateReview(pendingImport, data);
    pendingImport = null; ++importSerial; state = replacement; storageBlocked = false; persist(); choose(current().id); dialog('videoImportDialog', false); toast('已替换本批视频点评进度。');
  });
  window.VideoReviewApp = {getState: () => M.clone(state), exportDocument};
  renderProgress(); choose(data.cases[0].id);
})();

(function () {
  'use strict';
  const data = JSON.parse(document.getElementById('review-data').textContent);
  const M = window.ReviewModel;
  const $ = id => document.getElementById(id);
  const labels = {unreviewed:'未点评',pass:'通过',issue:'有问题',unsure:'不确定',later:'稍后再看'};
  const criterionLabels = {rig:'骨骼绑定',clothing:'衣服贴合',joints:'关节弯曲',motion:'动作自然度'};
  const key = 'harumachi-human-review:' + data.id;
  const uiKey = key + ':view';
  const cases = new Map(data.cases.map(c => [c.id,c]));
  const frames = new Map(data.cases.flatMap(c => c.frames.map(f => [f.key,f])));
  let state = M.createState(data);
  let ui = {caseId:data.cases[0].id,phase:0,view:'front',bones:false,mode:'static',filter:'all'};
  let storageFailed = false;
  let unreadableSavedState = null;
  let pinMode = false;
  let draft = null;
  let pendingImport = null;
  let undoAction = null;
  let undoReplacesState = false;
  let toastTimer;
  let imageGeneration = 0;
  const now = () => new Date().toISOString();
  const currentCase = () => cases.get(ui.caseId);
  const currentItem = () => state.items[ui.caseId];
  const currentFrame = () => currentCase().frames.find(f => f.phase === ui.phase && f.view === ui.view);
  const phaseLabel = phase => String(phase * 100) + '%';
  const actualMode = frame => ui.bones && frame.overlay ? 'bones' : 'original';
  const element = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  function showToast(message, undo, replacesState) {
    clearTimeout(toastTimer);
    $('toastText').textContent = message;
    $('toast').hidden = false;
    undoAction = undo || null;
    undoReplacesState = !!replacesState;
    $('undoButton').hidden = !undo;
    toastTimer = setTimeout(() => {$('toast').hidden = true;}, undo ? 12000 : 4500);
  }
  function warnStorage(message) {
    storageFailed = true;
    $('saveStatus').textContent = '请导出备份';
    $('saveWarning').hidden = false;
    $('saveWarning').textContent = message || '这个浏览器暂时无法保存进度。意见仍在当前页面中，请及时点“导出结果”备份；关闭页面可能丢失。';
  }
  function persist() {
    state.updated_at = now();
    if (unreadableSavedState !== null) return;
    try {
      const encoded = JSON.stringify(state);
      localStorage.setItem(key, encoded);
      if (localStorage.getItem(key) !== encoded) throw new Error('Storage verification failed');
      localStorage.setItem(uiKey, JSON.stringify(ui));
      storageFailed = false;
      $('saveWarning').hidden = true;
      $('saveStatus').textContent = '已保存到此浏览器';
    } catch (_) { warnStorage(); }
  }
  function changed() {
    cancelSnapshotUndo();
    currentItem().updated_at = now();
    persist();
    updateProgress();
  }
  function cancelSnapshotUndo() {
    if (undoAction && undoReplacesState) {
      undoAction = null;
      undoReplacesState = false;
      $('undoButton').hidden = true;
      $('toast').hidden = true;
    }
  }
  function openDialog(id) {
    const node = $(id);
    if (typeof node.showModal === 'function') node.showModal();
    else node.setAttribute('open','');
  }
  function closeDialog(id) {
    const node = $(id);
    if (typeof node.close === 'function') node.close();
    else node.removeAttribute('open');
  }
  function updateProgress() {
    const p = M.progress(state);
    $('progressText').textContent = p.reviewed + ' / ' + p.total + ' 项已点评';
    $('progressBar').value = p.reviewed;
    $('progressBar').max = p.total;
    $('itemStatus').textContent = labels[currentItem().verdict];
    $('itemStatus').className = 'status-label ' + currentItem().verdict;
    $('notesCount').textContent = currentItem().frame_comments.length + ' 条';
    $('seenCount').textContent = '看过 ' + currentItem().seen_frames.length + ' / ' + currentCase().frames.length + ' 张';
    document.title = currentCase().actor_label + ' · ' + currentCase().action_label + ' — 人物人工点评';
  }
  function matches(item) {
    return ui.filter === 'all' || state.items[item.id].verdict === ui.filter;
  }
  function renderQueue() {
    const list = $('caseList');
    list.replaceChildren();
    const actors = [...new Set(data.cases.map(c => c.actor))];
    const visible = data.cases.filter(c => matches(c) || c.id === ui.caseId);
    $('queueCount').textContent = (ui.filter === 'all' ? data.cases.length : data.cases.filter(matches).length) + ' 项';
    for (const actor of actors) {
      const actorCases = data.cases.filter(c => c.actor === actor);
      const shown = visible.filter(c => c.actor === actor);
      if (!shown.length) continue;
      const group = element('section','actor-group');
      const heading = element('h3','actor-label',actorCases[0].actor_label);
      heading.append(element('span','',actorCases.filter(c => ['pass','issue','unsure'].includes(state.items[c.id].verdict)).length + ' / ' + actorCases.length));
      group.append(heading);
      for (const c of shown) {
        const item = state.items[c.id];
        const button = element('button','case-button' + (c.id === ui.caseId ? ' active' : ''));
        button.dataset.caseId = c.id;
        button.setAttribute('aria-current',c.id === ui.caseId ? 'step' : 'false');
        button.setAttribute('aria-label',c.actor_label + ' ' + c.action_label + '，' + labels[item.verdict]);
        button.append(element('span','status-dot ' + item.verdict),element('span','',c.action_label));
        if (item.frame_comments.length) button.append(element('span','case-count',String(item.frame_comments.length) + ' 条'));
        button.addEventListener('click',() => navigate(c.id));
        group.append(button);
      }
      list.append(group);
    }
  }
  function stopDraft() {
    draft = null;
    pinMode = false;
    $('frameEditor').hidden = true;
    $('pinButton').textContent = '＋ 在画面上标记位置';
    $('imageSurface').classList.remove('pin-mode');
  }
  function navigate(id) {
    if (!cases.has(id)) return;
    persist();
    stopDraft();
    ui.caseId = id;
    const c = currentCase();
    if (!c.phases.includes(ui.phase)) ui.phase = c.phases[0];
    if (ui.mode === 'motion' && !c.motion) ui.mode = 'static';
    persist();
    renderAll();
  }
  function moveCase(delta) {
    const list = data.cases.filter(c => matches(c) || c.id === ui.caseId);
    const index = list.findIndex(c => c.id === ui.caseId);
    const next = list[index + delta];
    if (next) navigate(next.id);
    else showToast(delta > 0 ? '已到最后一项。可以查看总览或导出已有点评。' : '已到第一项。');
  }
  function nextUnreviewed() {
    const index = data.cases.findIndex(c => c.id === ui.caseId);
    const ordered = data.cases.slice(index + 1).concat(data.cases.slice(0,index + 1));
    const next = ordered.find(c => ['unreviewed','later'].includes(state.items[c.id].verdict));
    if (next) navigate(next.id);
    else showToast('49项都有判断了，可以导出结果。');
  }
  function setVerdict(verdict) {
    currentItem().verdict = verdict;
    changed();
    renderVerdicts();
    renderQueue();
  }
  function renderVerdicts() {
    $('verdictButtons').replaceChildren();
    for (const [i,verdict] of ['pass','issue','unsure','later'].entries()) {
      const button = element('button','verdict-button' + (currentItem().verdict === verdict ? ' selected' : ''),labels[verdict]);
      button.dataset.verdict = verdict;
      button.setAttribute('aria-pressed',String(currentItem().verdict === verdict));
      button.append(element('kbd','',String(i+1)));
      button.addEventListener('click',() => setVerdict(currentItem().verdict === verdict ? 'unreviewed' : verdict));
      $('verdictButtons').append(button);
    }
  }
  function renderFeedback() {
    renderVerdicts();
    $('criteriaFields').replaceChildren();
    for (const [criterion,label] of Object.entries(criterionLabels)) {
      const row = element('div','criterion');
      const name = element('label','',label);
      const select = element('select');
      select.id = 'criterion-' + criterion;
      name.htmlFor = select.id;
      for (const value of ['unreviewed','pass','issue','unsure']) select.add(new Option(value === 'unreviewed' ? '还没判断' : labels[value],value));
      select.value = currentItem().criteria[criterion];
      select.addEventListener('change',() => {currentItem().criteria[criterion] = select.value; changed(); renderQueue();});
      row.append(name,select);
      $('criteriaFields').append(row);
    }
    $('itemComment').value = currentItem().comment;
    renderNotes();
  }
  function frameDescription(frame,mode) {
    return frame.view_label + ' · 相位 ' + phaseLabel(frame.phase) + ' · ' + (mode === 'bones' ? '骨架透视' : '原图');
  }
  function renderControls() {
    const c = currentCase();
    $('phaseButtons').replaceChildren();
    for (const phase of c.phases) {
      const button = element('button','phase-button' + (phase === ui.phase ? ' active' : ''),phaseLabel(phase));
      button.setAttribute('aria-pressed',String(phase === ui.phase));
      button.dataset.phase = String(phase);
      button.addEventListener('click',() => {stopDraft();ui.phase = phase;persist();renderControls();renderImage();});
      $('phaseButtons').append(button);
    }
    $('angleButtons').replaceChildren();
    for (const [view,label] of Object.entries(data.views)) {
      const frame = c.frames.find(f => f.phase === ui.phase && f.view === view);
      const button = element('button','angle-button' + (view === ui.view ? ' active' : ''));
      button.dataset.view = view;
      button.setAttribute('aria-pressed',String(view === ui.view));
      button.setAttribute('aria-label',label);
      const image = element('img');
      image.src = frame.file;
      image.alt = '';
      image.loading = 'lazy';
      button.append(image,element('span','',label));
      button.addEventListener('click',() => {stopDraft();ui.view=view;persist();renderControls();renderImage();});
      $('angleButtons').append(button);
    }
    $('motionTab').disabled = !c.motion;
    $('motionTab').title = c.motion ? c.motion.label : '这一动作没有连续移动预览，可检查五向姿态';
    $('staticTab').classList.toggle('active',ui.mode === 'static');
    $('motionTab').classList.toggle('active',ui.mode === 'motion');
    $('staticControls').hidden = ui.mode === 'motion';
    $('bones').checked = ui.bones;
    $('bones').disabled = ui.mode === 'motion';
    $('pinButton').disabled = ui.mode === 'motion';
    $('frameNoteButton').disabled = ui.mode === 'motion';
    $('inspectionHelp').textContent = ui.mode === 'motion' ? '连续动作的意见写在右侧“本项意见”里。切回五向画面，可以标记某一相位、某个部位。GIF末尾重新播放，是预览本身的回放。' : '可以逐相位、逐方向看，也可以只给有疑问的画面写意见。键盘 1 / 2 / 3 / 4 标记判断，← / → 切换项目。';
  }
  function renderImage() {
    const c = currentCase(),frame = currentFrame();
    const generation = ++imageGeneration;
    const image = $('stageImage');
    const motion = ui.mode === 'motion';
    const src = motion ? c.motion.file : actualMode(frame) === 'bones' ? frame.overlay : frame.file;
    $('imageSurface').classList.toggle('motion',motion);
    $('frameTitle').textContent = motion ? c.motion.label : frameDescription(frame,actualMode(frame));
    $('imageCounter').textContent = motion ? '连续两个动作周期' : '五向原生画面';
    $('imageMessage').classList.remove('error');
    $('imageMessage').textContent = motion ? (c.motion.kind === 'fast_fixture' ? '这是4.5米/秒的快速移动对照，用于检查跑步；不代表居民通常就以这个速度行动。' : '实际移动录制，按原采集时间播放。') : ui.bones && !frame.overlay ? '这个相位只有原图；其他相位可切换查看骨架透视。当前点评仍准确对应这张原图。' : pinMode ? '点击画面中的具体位置，再在右侧写意见。' : '原图与骨架透视共用同一张画面的点评；切换显示不会丢失意见。';
    image.alt = c.actor_label + ' ' + c.action_label + ' ' + (motion ? '实际连续移动' : frame.view_label + ' ' + phaseLabel(frame.phase));
    image.onload = () => {
      if (generation !== imageGeneration) return;
      if (!motion && !currentItem().seen_frames.includes(frame.key)) {
        currentItem().seen_frames.push(frame.key);
        persist();
        updateProgress();
      }
    };
    image.onerror = () => {
      if (generation !== imageGeneration) return;
      $('imageMessage').textContent = '这张画面没有载入。请保留原证据目录结构；尚未将它记为已看。';
      $('imageMessage').classList.add('error');
    };
    image.src = src;
    renderPins();
  }
  function renderPins() {
    const layer = $('pinLayer');
    layer.replaceChildren();
    if (ui.mode !== 'static') return;
    const frame = currentFrame();
    const notes = currentItem().frame_comments.filter(n => n.frame_key === frame.key);
    for (const note of notes) {
      if (!note.position) continue;
      const index = currentItem().frame_comments.findIndex(n => n.id === note.id) + 1;
      const button = element('button','pin',String(index));
      button.style.left = (note.position.x*100) + '%';
      button.style.top = (note.position.y*100) + '%';
      button.setAttribute('aria-label','查看画面意见 ' + index);
      button.title = note.text;
      button.addEventListener('click',event => {event.stopPropagation();editNote(note);});
      layer.append(button);
    }
    if (draft && !draft.id && draft.frame_key === frame.key && draft.position) {
      const marker = element('span','pin pending','＋');
      marker.style.left = (draft.position.x*100) + '%';
      marker.style.top = (draft.position.y*100) + '%';
      layer.append(marker);
    }
  }
  function startNote(position) {
    if (ui.mode !== 'static') return;
    draft = {id:null,frame_key:currentFrame().key,text:'',part:'',position:position || null,mode:actualMode(currentFrame()),created_at:now()};
    pinMode = false;
    $('imageSurface').classList.remove('pin-mode');
    $('pinButton').textContent = '＋ 在画面上标记位置';
    showEditor();
    renderPins();
    $('frameComment').focus();
  }
  function showEditor() {
    $('frameEditor').hidden = false;
    const frame = frames.get(draft.frame_key);
    $('editorContext').textContent = currentCase().actor_label + ' · ' + currentCase().action_label + ' · ' + frameDescription(frame,draft.mode) + (draft.position ? ' · 已标记位置' : '');
    $('bodyPart').value = draft.part;
    if ($('bodyPart').value !== draft.part) {
      $('bodyPart').add(new Option(draft.part,draft.part));
      $('bodyPart').value = draft.part;
    }
    $('frameComment').value = draft.text;
  }
  function editNote(note) {
    const frame = frames.get(note.frame_key);
    ui.mode = 'static';ui.phase=frame.phase;ui.view=frame.view;ui.bones=note.mode==='bones';
    pinMode = false;
    $('imageSurface').classList.remove('pin-mode');
    $('pinButton').textContent = '＋ 在画面上标记位置';
    draft = {...note,position:note.position ? {...note.position} : null};
    persist();
    renderControls();renderImage();showEditor();
    $('frameComment').focus();
  }
  function saveDraft() {
    if (!draft) return;
    draft.text = $('frameComment').value;
    draft.part = $('bodyPart').value;
    if (!draft.id && !draft.text.trim()) return;
    if (!draft.id) {
      if (currentItem().frame_comments.length >= 1000) {showToast('这一项的画面意见已达上限，请先导出备份。');return;}
      draft.id = window.crypto && typeof window.crypto.randomUUID === 'function' ? window.crypto.randomUUID() : 'note-' + Date.now() + '-' + Math.random().toString(36).slice(2);
      currentItem().frame_comments.push({...draft,position:draft.position ? {...draft.position}:null});
    } else {
      const index = currentItem().frame_comments.findIndex(n => n.id === draft.id);
      if (index >= 0) currentItem().frame_comments[index] = {...draft,position:draft.position ? {...draft.position}:null};
    }
    changed();renderNotes();renderPins();renderQueue();
  }
  function renderNotes() {
    const container = $('frameNotes');
    container.replaceChildren();
    if (!currentItem().frame_comments.length) container.append(element('p','empty-notes','还没有画面意见。可以点击画面标记位置，也可以直接填写本项意见。'));
    for (const [index,note] of currentItem().frame_comments.entries()) {
      const frame = frames.get(note.frame_key);
      const card = element('article','frame-note');
      const location = element('button','note-location',(index+1) + '. ' + frameDescription(frame,note.mode) + (note.part ? ' · ' + note.part : ''));
      location.addEventListener('click',() => editNote(note));
      card.append(location,element('p','note-content',note.text || '（尚未填写文字）'));
      const actions = element('div','note-actions');
      const edit = element('button','','编辑');
      edit.addEventListener('click',() => editNote(note));
      const remove = element('button','','删除');
      remove.addEventListener('click',() => {
        const id = ui.caseId;
        const saved = {...note,position:note.position ? {...note.position}:null};
        state.items[id].frame_comments = state.items[id].frame_comments.filter(n => n.id !== note.id);
        if (draft && draft.id === note.id) stopDraft();
        changed();renderNotes();renderPins();renderQueue();
        showToast('已删除这条画面意见。',() => {
          state.items[id].frame_comments.splice(index,0,saved);
          persist();renderAll();
        });
      });
      actions.append(edit,remove);card.append(actions);container.append(card);
    }
    $('notesCount').textContent = currentItem().frame_comments.length + ' 条';
  }
  function renderAll() {
    const c = currentCase();
    const index = data.cases.findIndex(x => x.id === c.id);
    $('caseNumber').textContent = '第 ' + (index+1) + ' / ' + data.cases.length + ' 项';
    $('caseTitle').textContent = c.actor_label + ' · ' + c.action_label;
    $('filter').value = ui.filter;
    renderQueue();renderControls();renderImage();renderFeedback();updateProgress();
  }
  function renderOverview() {
    const p = M.progress(state);
    $('overviewSummary').textContent = '已点评 ' + p.reviewed + ' / ' + p.total + ' · 通过 ' + p.pass + ' · 有问题 ' + p.issue + ' · 不确定 ' + p.unsure + ' · 稍后 ' + p.later + ' · 画面意见 ' + p.notes + ' 条';
    $('overviewRows').replaceChildren();
    for (const c of data.cases) {
      const item = state.items[c.id];
      const row = element('tr');
      row.append(element('td','',c.actor_label),element('td','',c.action_label),element('td','',labels[item.verdict]),element('td','',item.comment || (item.frame_comments.length ? item.frame_comments.length + ' 条画面意见' : '—')));
      const cell = element('td');
      const button = element('button','outline','查看');
      button.addEventListener('click',() => {closeDialog('overviewDialog');navigate(c.id);});
      cell.append(button);row.append(cell);$('overviewRows').append(row);
    }
  }
  function download(text,mime,extension) {
    const blob = new Blob([text],{type:mime});
    const url = URL.createObjectURL(blob);
    const link = element('a');
    link.href=url;link.download='harumachi-character-review-' + new Date().toISOString().replace(/[-:]/g,'').slice(0,15) + '.' + extension;
    document.body.append(link);link.click();link.remove();
    setTimeout(() => URL.revokeObjectURL(url),30000);
  }
  function exportResult(kind) {
    try {
      persist();
      if (kind === 'json') download(JSON.stringify(M.exportDocument(state,data),null,2),'application/json;charset=utf-8','json');
      else download(M.toMarkdown(state,data),'text/markdown;charset=utf-8','md');
      showToast('已生成下载文件，请把 JSON 文件发到聊天里。');
    } catch (error) {showToast('导出失败：' + error.message);}
  }
  function backupForUndo(snapshot) {
    try {localStorage.setItem(key+':before-import',JSON.stringify(snapshot));} catch (_) {/* In-memory undo remains available. */}
  }
  function importResult() {
    if (!pendingImport) return;
    const before = M.normalizeImport(state,data);
    const imported = M.normalizeImport(pendingImport,data);
    const mode = document.querySelector('input[name="importMode"]:checked').value;
    let importedCount = 0,keptCount = 0;
    backupForUndo(before);
    if (mode === 'replace') {
      state=imported;importedCount=M.progress(imported).reviewed;
    } else {
      for (const c of data.cases) {
        if (M.hasFeedback(state.items[c.id])) {if(M.hasFeedback(imported.items[c.id]))keptCount++;continue;}
        state.items[c.id] = imported.items[c.id];
        if (M.hasFeedback(imported.items[c.id])) importedCount++;
      }
      if (!state.reviewer) state.reviewer=imported.reviewer;
    }
    pendingImport=null;
    closeDialog('importDialog');stopDraft();persist();renderAll();
    showToast('已导入 ' + importedCount + ' 项意见' + (keptCount ? '，跳过并保留当前 ' + keptCount + ' 项已有意见。' : '。'),() => {state=before;stopDraft();persist();renderAll();},true);
  }
  // Restore only data bound to this exact image collection. An unreadable prior save
  // is left untouched and offered as a downloadable backup, rather than overwritten.
  try {
    const saved = localStorage.getItem(key);
    if (saved) {
      try {state=M.normalizeImport(saved,data);} catch (error) {
        unreadableSavedState=saved;
        warnStorage('检测到无法读取的旧进度，已保留。请先下载旧进度备份，再继续自动保存。');
        const backupButton=element('button','outline','备份旧进度并继续');
        backupButton.addEventListener('click',() => {download(unreadableSavedState,'application/json;charset=utf-8','json');unreadableSavedState=null;persist();});
        $('saveWarning').append(backupButton);
      }
    }
    const savedUI = JSON.parse(localStorage.getItem(uiKey) || 'null');
    if (savedUI && cases.has(savedUI.caseId)) {
      ui.caseId=savedUI.caseId;
      if (currentCase().phases.includes(savedUI.phase)) ui.phase=savedUI.phase;
      if (Object.hasOwn(data.views,savedUI.view)) ui.view=savedUI.view;
      ui.bones=savedUI.bones===true;
      if (savedUI.mode==='motion'&&currentCase().motion)ui.mode='motion';
      if (['all','unreviewed','pass','issue','unsure','later'].includes(savedUI.filter))ui.filter=savedUI.filter;
    }
  } catch (_) {warnStorage();}
  $('itemComment').maxLength=12000;
  $('frameComment').maxLength=6000;
  $('itemComment').addEventListener('input',() => {currentItem().comment=$('itemComment').value;changed();renderQueue();});
  $('frameComment').addEventListener('input',saveDraft);
  $('bodyPart').addEventListener('change',saveDraft);
  $('closeFrameEditor').addEventListener('click',() => {stopDraft();renderPins();});
  $('finishFrameEditor').addEventListener('click',() => {saveDraft();stopDraft();renderPins();});
  $('previousCase').addEventListener('click',() => moveCase(-1));
  $('nextCase').addEventListener('click',() => moveCase(1));
  $('nextCaseBottom').addEventListener('click',() => moveCase(1));
  $('nextUnreviewed').addEventListener('click',nextUnreviewed);
  $('filter').addEventListener('change',() => {ui.filter=$('filter').value;persist();renderQueue();});
  $('bones').addEventListener('change',() => {ui.bones=$('bones').checked;persist();renderImage();});
  $('staticTab').addEventListener('click',() => {stopDraft();ui.mode='static';persist();renderControls();renderImage();});
  $('motionTab').addEventListener('click',() => {if(!currentCase().motion)return;stopDraft();ui.mode='motion';persist();renderControls();renderImage();});
  $('pinButton').addEventListener('click',() => {
    pinMode=!pinMode;
    $('imageSurface').classList.toggle('pin-mode',pinMode);
    $('pinButton').textContent=pinMode?'取消标记位置':'＋ 在画面上标记位置';
    $('imageMessage').textContent=pinMode?'点击画面中的具体位置，再在右侧写意见。':'可以继续切换相位和方向。';
  });
  $('frameNoteButton').addEventListener('click',() => startNote(null));
  $('imageSurface').addEventListener('click',event => {
    if (!pinMode||ui.mode!=='static')return;
    const image=$('stageImage');
    if (!image.naturalWidth||!image.naturalHeight) {showToast('请等待图片载入后再标记。');return;}
    const rect=image.getBoundingClientRect();
    // The static stage and native images both use 16:9. Calculate the actual
    // object-fit rectangle anyway, so the coordinate stays valid at any size.
    const scale=Math.min(rect.width/image.naturalWidth,rect.height/image.naturalHeight);
    const width=image.naturalWidth*scale,height=image.naturalHeight*scale;
    const left=rect.left+(rect.width-width)/2,top=rect.top+(rect.height-height)/2;
    const x=(event.clientX-left)/width,y=(event.clientY-top)/height;
    if (x>=0&&x<=1&&y>=0&&y<=1)startNote({x,y});
  });
  $('zoomButton').addEventListener('click',() => {$('zoomTitle').textContent=currentCase().actor_label+' · '+currentCase().action_label+' · '+$('frameTitle').textContent;$('zoomImage').src=$('stageImage').src;openDialog('zoomDialog');});
  $('overviewButton').addEventListener('click',() => {renderOverview();openDialog('overviewDialog');});
  $('exportButton').addEventListener('click',() => {const p=M.progress(state);$('exportSummary').textContent='已点评 '+p.reviewed+' / '+p.total+' 项，画面意见 '+p.notes+' 条。'+(p.reviewed<p.total?'剩余 '+(p.total-p.reviewed)+' 项仍会明确标为未完成，可以先导出已有意见。':'全部项目都有判断了。');$('reviewer').value=state.reviewer;openDialog('exportDialog');});
  $('reviewer').addEventListener('input',() => {cancelSnapshotUndo();state.reviewer=$('reviewer').value;persist();});
  $('downloadJson').addEventListener('click',() => exportResult('json'));
  $('downloadMarkdown').addEventListener('click',() => exportResult('markdown'));
  $('importButton').addEventListener('click',() => {$('importFile').value='';$('importFile').click();});
  $('importFile').addEventListener('change',async () => {
    const file=$('importFile').files[0];if(!file)return;
    try {
      if(file.size>10*1024*1024)throw new Error('文件超过10MB，请选择导出的点评JSON。');
      pendingImport=M.normalizeImport(await file.text(),data);
      const p=M.progress(pendingImport);
      $('importSummary').textContent='这份文件已点评 '+p.reviewed+' / '+p.total+' 项，含 '+p.notes+' 条画面意见。';
      document.querySelector('input[name="importMode"][value="merge"]').checked=true;
      openDialog('importDialog');
    } catch(error){pendingImport=null;showToast('没有导入：'+error.message+' 当前点评保持不变。');}
  });
  $('confirmImport').addEventListener('click',importResult);
  $('undoButton').addEventListener('click',() => {if(undoAction){const action=undoAction;undoAction=null;action();$('toast').hidden=true;}});
  document.querySelectorAll('[data-close]').forEach(button => button.addEventListener('click',() => closeDialog(button.dataset.close)));
  document.addEventListener('keydown',event => {
    if (event.ctrlKey||event.metaKey||event.altKey||event.repeat||document.querySelector('dialog[open]')||event.target.closest('input,textarea,select,[contenteditable="true"]'))return;
    const verdicts={'1':'pass','2':'issue','3':'unsure','4':'later'};
    if(verdicts[event.key]){event.preventDefault();setVerdict(verdicts[event.key]);}
    if(event.key==='ArrowLeft'){event.preventDefault();moveCase(-1);}
    if(event.key==='ArrowRight'){event.preventDefault();moveCase(1);}
  });
  window.addEventListener('beforeunload',persist);
  persist();
  renderAll();
})();

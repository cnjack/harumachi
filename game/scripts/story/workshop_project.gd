class_name WorkshopProject
extends RefCounted
## One representative work. The town's remaining lanterns have separate authorship.
const TARGETS := [0.0, 120.0, 240.0]

static func state() -> Dictionary:
	var G := GameState
	if not G.flags.get("summer_workshop", {}) is Dictionary or G.flags.get("summer_workshop", {}).get("version", 0) != 1:
		G.flags["summer_workshop"] = {"version": 1, "phase": "invitation", "mode": "", "purpose": "meeting", "pattern": "leaf",
			"joints": 0, "angle": 60.0, "failed_fits": 0, "materials_received": false, "materials_committed": false,
			"height": 2.4, "facing": 0.0, "trial": {}, "work_id": "", "maker": "", "designer": "", "tester": "", "installed": {}, "site_preview": false, "archive_seen": []}
	var p: Dictionary = G.flags.summer_workshop
	p.merge({"stored":false, "use_history":[],"mount":"path","mount_decided":false}, false)
	p.version = 1
	for index in p.archive_seen.size(): p.archive_seen[index] = int(p.archive_seen[index])
	if p.installed.has("day"): p.installed.day = int(p.installed.day)
	for entry: Dictionary in p.use_history:
		if entry.has("day"): entry.day = int(entry.day)
	if not p.installed.is_empty(): _remember_use(p)
	p.joints = int(p.joints)
	p.failed_fits = int(p.failed_fits)
	return p

static func _remember_use(p: Dictionary) -> void:
	var current: Dictionary = p.installed
	if p.use_history.any(func(entry: Dictionary): return str(entry.get("work_id", "")) == str(current.get("work_id", "")) and str(entry.get("revision", "")) == str(current.get("revision", "")) and int(entry.get("day", -1)) == int(current.get("day", -1)) and str(entry.get("context", "legacy_unknown")) == str(current.get("context", "legacy_unknown"))): return
	p.use_history.append(current.duplicate(true))

static func start(mode: String, purpose: String, pattern: String) -> String:
	var G := GameState
	var p: Dictionary = state()
	if G.qstate("Q11") != "done": return "先把账本带给春和澪，弄清今年要用什么。"
	if p.phase != "invitation": return "这一盏开工了。材料已经领过，去工作台接着做。"
	if mode not in ["hand", "plan"] or purpose not in ["meeting", "guide"] or pattern not in ["leaf", "wave"]: return "先选好这一盏的用途和纸面。"
	if not G.can_add_bundle({"washi": 1, "bamboo_strip": 1}): return "背包先留出一张和纸和一份竹篾的位置。"
	if not p.materials_received:
		G.add_item("washi", 1, true)
		G.add_item("bamboo_strip", 1, true)
		p.materials_received = true
	p.mode = mode
	p["designer"] = "player"
	p.purpose = purpose
	p.pattern = pattern
	p.phase = "assembly"
	if G.qstate("Q12") == "available": G.start_quest("Q12")
	if SummerProjects.uses_cooperation_mainline():
		G.advance("Q12", "buy_washi")
		G.advance("Q12", "get_bamboo")
	if mode == "plan":
		var why: String = _consume_materials()
		if why != "": return why
		p.joints = 3
		p.maker = "town"
		p.phase = "assembled"
	_commit()
	return ""

static func _consume_materials() -> String:
	var p: Dictionary = state()
	if p.materials_committed: return ""
	if GameState.unreserved_count("washi") + held("washi") < 1 or GameState.unreserved_count("bamboo_strip") + held("bamboo_strip") < 1: return "这一盏的和纸与竹篾先带回来，接头还留着。"
	GameState.remove_item("washi", 1)
	GameState.remove_item("bamboo_strip", 1)
	p.materials_committed = true
	p.work_id = "representative-lantern-1"
	return ""

static func rotate_part(delta: float) -> void:
	var p: Dictionary = state()
	if p.phase != "assembly" or p.mode != "hand": return
	p.angle = fposmod(float(p.angle) + delta, 360.0)
	_commit()

static func fit() -> String:
	var p: Dictionary = state()
	if p.phase != "assembly" or p.mode != "hand" or int(p.joints) >= 3: return "三个接头都扣牢了，可以拿去试挂。"
	var distance: float = absf(wrapf(float(p.angle) - float(TARGETS[int(p.joints)]), -180.0, 180.0))
	if distance > 10.0:
		p.failed_fits = int(p.failed_fits) + 1
		_commit()
		return "还没对齐。转到绿色接头处再扣，不会损坏材料。"
	var why: String = _consume_materials()
	if why != "": return why
	p.joints = int(p.joints) + 1
	p.maker = "player"
	if int(p.joints) == 3: p.phase = "assembled"
	else: p.angle = float(TARGETS[int(p.joints)]) + float([60.0, -75.0, 90.0][int(p.joints)])
	_commit()
	return ""

static func configure(height: float, facing: float, mount: String="") -> String:
	var p: Dictionary = state()
	if p.phase not in ["assembled", "tested", "retained"]: return "先把三个接头固定好，再试挂。"
	if height not in [1.55, 2.4] or facing not in [0.0, 180.0]: return "先选架上要挂的位置。"
	if mount!="" and mount not in ["path","side"]: return "选通道上方，或通道侧边的吊点。"
	var selected: String=str(p.mount) if mount=="" else mount
	if not p.installed.is_empty() and (float(p.height) != height or float(p.facing) != facing or str(p.mount)!=selected): p.installed = {}
	p.height = height
	p.facing = facing
	p.mount=selected
	if mount!="": p.mount_decided=true
	p.stored = false
	if not p.get("site_preview", false):
		p.trial = {}
		p.phase = "assembled"
	_commit()
	return ""

static func revision() -> String:
	var p: Dictionary = state()
	return JSON.stringify([2,p.work_id, int(p.joints), p.purpose, p.pattern, float(p.height), float(p.facing),str(p.mount)]).sha256_text()

static func record_trial(result: Dictionary) -> String:
	var p: Dictionary = state()
	if str(result.get("place", "")) == "missing": return "当前没有试挂的灯体，先把这一盏带回试挂架。"
	if int(p.joints) != 3 or p.work_id == "": return "接头还没接牢。先到工作台接好，再来试挂。"
	if str(result.get("revision", "")) != revision(): return "高度或朝向改过了，再按现在的样子看一次。"
	p.trial = result.duplicate(true)
	p["tester"] = "player"
	p.phase = "tested"
	_commit()
	return ""

static func retain() -> String:
	var p: Dictionary = state()
	if p.trial.is_empty() or str(p.trial.get("revision", "")) != revision(): return "先按现在的高度和朝向亮灯试挂。"
	if not p.trial.get("lit", false): return "灯还没点亮，先看看亮起来的样子。"
	if not p.trial.get("clear", false): return "通道里会碰到。可以把吊点挪到侧边，也可以挂高再试。"
	if not p.trial.get("readable", false): return "近处和来路都辨不出纸面，先看遮挡与朝向再试。"
	p.phase = "retained"
	if SummerProjects.uses_cooperation_mainline(): GameState.advance("Q12", "make_lanterns")
	_commit()
	return ""

static func begin_site() -> String:
	var p: Dictionary = state()
	if p.phase != "retained": return "先把工作间试好的这一盏收好，再带到现场。"
	if SummerGathering.context() == "": return "夏祭现场，或和澪明确重约后，再把这一盏挂出来。"
	p.site_preview = true
	p.stored = false
	_commit()
	return ""

static func install(result: Dictionary) -> String:
	var p: Dictionary = state()
	if p.phase != "retained": return "先在工作间试挂，保留能用的方案。"
	var context: String = SummerGathering.context()
	if context == "": return "这一盏先收好，夏祭或明确重约后再挂到现场。"
	if not result.get("lit", false) or not result.get("clear", false) or not result.get("readable", false): return "现场的走道和来路与工作间不同，先调好高度与朝向。"
	if str(result.get("revision", "")) != revision(): return "刚调整过，再检查这个位置。"
	p.installed = result.duplicate(true)
	p.installed["work_id"] = p.work_id
	p.installed["day"] = GameState.day
	p.installed["context"] = context
	p.installed["session_id"] = context + ":" + str(GameState.day)
	if not p.use_history.any(func(entry: Dictionary): return str(entry.get("session_id", "")) == str(p.installed.session_id) and str(entry.get("revision", "")) == str(p.installed.revision)):
		p.use_history.append(p.installed.duplicate(true))
	_commit()
	return ""

static func stow() -> String:
	var p: Dictionary = state()
	if p.installed.is_empty() and not p.site_preview: return "灯已经放回工作间了。"
	p.installed = {}
	p.site_preview = false
	p.stored = true
	p["stored_day"] = GameState.day
	_commit()
	return ""

static func restore_to_rack() -> void:
	var p: Dictionary=state()
	if not p.stored: return
	p.stored=false
	p.site_preview=false
	_commit()

static func _commit() -> void:
	GameState.state_changed.emit()
	GameState.save_game()

static func return_to_workroom() -> void:
	var p: Dictionary = state()
	if p.get("site_preview", false) and p.installed.is_empty():
		p.site_preview = false
		p.phase = "assembled"
		p.trial = {}
		_commit()

static func held(iid: String) -> int:
	var p: Dictionary = state()
	return 1 if iid in ["washi", "bamboo_strip"] and p.materials_received and not p.materials_committed else 0

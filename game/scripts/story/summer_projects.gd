class_name SummerProjects
extends RefCounted
## One finite cooperation, later reused at the festival. Recipes and portions have identities.
const MENUS := {"sandwich": "veg_sandwich", "focaccia": "focaccia"}
const MENU_NAMES := {"sandwich": "街坊三明治", "focaccia": "番茄佛卡夏"}
const TRIAL_RECIPE := "opening_trial"
const KIT := "opening_trial_kit"

static func initialize(fresh: bool = false, restored: bool = false) -> void:
	var G := GameState
	if not G.flags.get("summer_projects", {}) is Dictionary or G.flags.get("summer_projects", {}).get("version", 0) != 1:
		G.flags["summer_projects"] = {"version": 1, "old_save": not fresh, "mainline_mode": "cooperation" if fresh else "legacy", "tracked": false,
			"opening": {"phase": "invitation", "role": "", "menu": "", "source": "", "next_batch": 1,
				"batches": [], "borrowed_trials": 0, "kit_held": false, "layout_trial": {}, "final": {}, "service": {}, "followup": false}}
	var data: Dictionary = G.flags.summer_projects
	data.version = 1
	if not data.has("mainline_mode"): data["mainline_mode"] = "legacy"
	if not data.has("opening") or not data.opening is Dictionary: data["opening"] = {}
	var p: Dictionary = data.opening
	p.merge({"phase": "invitation", "role": "", "menu": "", "source": "", "next_batch": 1, "batches": [],
		"borrowed_trials": 0, "kit_held": false, "layout_trial": {}, "final": {}, "service": {}, "followup": false}, false)
	if not data.has("tracked"): data["tracked"] = false
	p.next_batch = int(p.next_batch)
	p.borrowed_trials = int(p.borrowed_trials)
	for batch: Dictionary in p.batches:
		if not batch.has("usage_feedback"): batch["usage_feedback"] = []
		if not batch.has("received_feedback"): batch["received_feedback"] = []
		for feedback: Dictionary in batch.usage_feedback:
			feedback.day = int(feedback.get("day",0))
		for feedback: Dictionary in batch.received_feedback:
			feedback.day = int(feedback.get("day",0))
		for field: String in ["id", "total", "self_eaten", "day"]:
			if batch.has(field): batch[field] = int(batch[field])
		for who: String in batch.get("tasters", {}): batch.tasters[who] = int(batch.tasters[who])
	for field: String in ["servings", "remaining", "day", "trial_batch", "packed", "self_eaten"]:
		if p.service.has(field): p.service[field] = int(p.service[field])
	for who: String in p.service.get("served", {}): p.service.served[who] = int(p.service.served[who])
	for iid: String in p.service.get("ingredients", {}): p.service.ingredients[iid] = int(p.service.ingredients[iid])
	for field: String in ["trial_batch", "decided_day"]:
		if p.final.has(field): p.final[field] = int(p.final[field])
	if restored and p.service.has("pending"):
		p.service.remaining = int(p.service.remaining) + 1
		p.service.erase("pending")
	_register_data()

static func state() -> Dictionary:
	initialize()
	return GameState.flags.summer_projects

static func opening() -> Dictionary:
	return state().opening

static func phase() -> String:
	return str(opening().phase)

static func accept(role: String) -> String:
	var G := GameState
	if G.qstate("Q01") != "done": return "先看看澪的公告栏，了解这次集市。"
	if role not in ["food", "host"]: return "先选一件自己想做的事。"
	var p: Dictionary = opening()
	if str(p.phase) != "invitation": return "已经留过这张合作纸签了，可以继续或改天再来。"
	if not G.can_add_bundle({"picnic_table": 1, "bench": 1}): return "背包装不下桌和长椅。先腾点地方，纸签放着。"
	p.role = role
	p.phase = "plan"
	# A finite borrowed set; this is handed over once, not a renewable money reward.
	GameState.add_item("picnic_table", 1, true)
	GameState.add_item("bench", 1, true)
	p["furniture_received"] = true
	track()
	_commit()
	return ""

static func choose_plan(menu: String, source: String) -> String:
	var p: Dictionary = opening()
	if menu not in MENUS or source not in ["own", "shop"]: return "先选这回想做哪种面包。"
	if str(p.phase) not in ["plan", "trial", "feedback", "decision"]: return "这一批先收好，别把材料和下一批混在一起。"
	if p.kit_held: return "试料还在手上。先归还这一包，再换方案。"
	p.menu = menu
	p.source = source
	p.phase = "trial"
	_register_data()
	_commit()
	return ""

static func ingredients(menu: String) -> Dictionary:
	var rid: String = str(MENUS.get(menu, ""))
	return GameState.recipe(rid).get("inputs", {}).duplicate(true)

static func claim_kit() -> String:
	var p: Dictionary = opening()
	if str(p.phase) != "trial" or str(p.source) != "shop": return "这次用自己带来的食材，不用另领试料。"
	if p.kit_held: return "这一包已经交给你了。"
	if int(p.borrowed_trials) >= 2: return "两包试料已经用过。之后想比较别的味道，可以自己带材料来。"
	p.borrowed_trials = int(p.borrowed_trials) + 1
	p.kit_held = true
	_register_data()
	GameState.add_item(KIT, 1, true)
	_commit()
	return ""

static func return_kit() -> String:
	var p: Dictionary = opening()
	if not p.kit_held or not GameState.has(KIT): return "没有未用的试料要归还。"
	GameState.remove_item(KIT, 1)
	p.kit_held = false
	p.borrowed_trials = maxi(0, int(p.borrowed_trials) - 1)
	p.phase = "plan"
	_commit()
	return ""

static func active_recipe(rid: String) -> bool:
	return rid != TRIAL_RECIPE or phase() == "trial" and str(opening().role) == "food"

static func _sample_id(number: int) -> String:
	return "opening_sample_%d" % number

static func _register_data() -> void:
	var G := GameState
	var p: Dictionary = G.flags.summer_projects.opening
	for batch: Dictionary in p.batches:
		G.items_db[str(batch.iid)] = {"name": "%s · 试吃小份" % MENU_NAMES.get(str(batch.menu), "面包"),
			"icon": str(GameState.item(str(MENUS.get(str(batch.menu), "veg_sandwich"))).get("icon", "onigiri")), "key": true, "dish": true, "sell": 0,
			"desc": "这次试做切下的小份，可以尝，也可以送给街坊。"}
	if not p.service.is_empty():
		G.items_db["opening_leftover"] = {"name": "%s · 这一篮留下的小份" % MENU_NAMES.get(str(p.final.menu), "面包"),
			"icon": str(GameState.item(str(MENUS.get(str(p.final.menu), "veg_sandwich"))).get("icon", "onigiri")), "key": true, "dish": true, "sell": 0,
			"desc": "开摊后剩下的一份，已经包好，可以带回家吃。"}
	if str(p.menu) == "": return
	var menu: String = p.menu
	var recipe: Dictionary = G.recipe(str(MENUS[menu])).duplicate(true)
	var iid: String = _sample_id(int(p.next_batch))
	G.items_db[iid] = {"name": "%s · 试吃小份" % MENU_NAMES[menu], "icon": str(GameState.item(str(MENUS[menu])).get("icon", "onigiri")),
		"key": true, "dish": true, "sell": 0, "desc": "一份面包切成三小份，够三个人各尝一点。"}
	G.items_db[KIT] = {"name": "%s的试料" % MENU_NAMES[menu], "icon": str(G.item("flour").get("icon", "ing_flour")), "key": true, "sell": 0,
		"desc": "莲装好的一包试料：" + _ingredient_text(ingredients(menu))}
	recipe.name = "%s · 一份切三小份" % MENU_NAMES[menu]
	recipe.output = {iid: 3}
	recipe.unlock = {"story": true}
	if str(p.source) == "shop": recipe.inputs = {KIT: 1}
	G.recipes_db[TRIAL_RECIPE] = recipe
	if str(p.phase) == "trial" and str(p.role) == "food": G.recipes_known[TRIAL_RECIPE] = true
	else: G.recipes_known.erase(TRIAL_RECIPE)

static func _ingredient_text(bundle: Dictionary) -> String:
	var parts: Array[String] = []
	for iid: String in bundle: parts.append("%s×%d" % [GameState.item_name(iid), int(bundle[iid])])
	return "、".join(parts)

static func record_craft(rid: String) -> void:
	if rid != TRIAL_RECIPE or phase() != "trial": return
	var p: Dictionary = opening()
	_record_batch("player", str(p.source))

static func shop_prepares() -> String:
	var p: Dictionary = opening()
	if str(p.phase) != "trial" or str(p.role) != "host": return "这次由自己试做，去莲的烤箱看看。"
	if str(p.source) == "own":
		var inputs: Dictionary = ingredients(str(p.menu))
		for iid: String in inputs:
			if GameState.unreserved_count(iid) < int(inputs[iid]): return "还差：" + _ingredient_text(inputs)
		for iid: String in inputs: GameState.remove_item(iid, int(inputs[iid]))
	else:
		if not p.kit_held or not GameState.has(KIT): return "先和莲领这一包试料。"
		GameState.remove_item(KIT, 1)
	var iid: String = _sample_id(int(p.next_batch))
	GameState.add_item(iid, 3, true)
	_record_batch("ren", str(p.source))
	return ""

static func _record_batch(maker: String, source: String) -> void:
	var G := GameState
	var p: Dictionary = opening()
	var batch: Dictionary = {"id": int(p.next_batch), "iid": _sample_id(int(p.next_batch)), "menu": str(p.menu),
		"maker": maker, "source": source, "materials": ingredients(str(p.menu)), "total": 3,
		"tasters": {}, "usage_feedback": [], "received_feedback": [], "self_eaten": 0, "day": G.day}
	p.batches.append(batch)
	p.next_batch = int(p.next_batch) + 1
	p.kit_held = false
	p.phase = "feedback"
	G.recipes_known.erase(TRIAL_RECIPE)
	_commit()

static func current_batch() -> Dictionary:
	var batches: Array = opening().batches
	return batches.back() if not batches.is_empty() else {}

static func held(iid: String) -> int:
	var batch: Dictionary = current_batch()
	if batch.is_empty() or str(batch.iid) != iid or phase() != "feedback": return 0
	return maxi(0, 2 - batch.tasters.size())

static func taste_error(who: String, actually_present: bool, batch_id: int = -1) -> String:
	var batch: Dictionary = current_batch()
	if phase() != "feedback" or who not in ["mio", "haru", "kazuko"]: return "先把这一份做出来，再请街坊尝。"
	if batch_id >= 0 and int(batch.id) != batch_id: return "纸签换过了，这份先收着，按现在这一批再约。"
	if not actually_present: return "对方现在不在这里，改天带着小份再来。"
	if batch.tasters.has(who): return "这一位已经尝过，不用再递一份。"
	if not GameState.has(str(batch.iid)): return "试吃小份不在背包里，先从收纳箱取回来。"
	return ""

static func taste(who: String, actually_present: bool, usage: Dictionary = {}) -> String:
	var why: String = taste_error(who,actually_present,int(usage.get("batch_id",-1)))
	if why != "": return why
	var batch: Dictionary = current_batch()
	var receipt: bool=str(usage.get("mode",""))=="received"
	if not usage.is_empty():
		if str(usage.get("menu","")) != str(batch.menu) or str(usage.get("presentation","")) not in ["paper","plate"] or str(usage.get("purpose","")) != tasting_purpose(who) or not bool(usage.get("completed",false)):
			return "这一份还没有在桌边尝完，先收着。"
		if receipt and (batch.usage_feedback.is_empty() or str(usage.get("reference_who",""))!=str(batch.usage_feedback[0].who)):
			return "先请一位在桌边尝尝，再问问另一位。"
	var old_phase: String=phase()
	var feedback: Dictionary={"who":who,"menu":str(batch.menu),"presentation":str(usage.get("presentation","")),"purpose":tasting_purpose(who),"day":GameState.day}
	GameState.remove_item(str(batch.iid), 1)
	batch.tasters[who] = GameState.day
	if not usage.is_empty():
		if receipt:
			feedback["reference_who"]=str(usage.reference_who)
			batch.received_feedback.append(feedback)
		else:batch.usage_feedback.append(feedback)
	if batch.tasters.size() >= 2: opening().phase = "decision"
	if not _commit():
		batch.tasters.erase(who)
		if not usage.is_empty():
			if receipt:batch.received_feedback.pop_back()
			else:batch.usage_feedback.pop_back()
		opening().phase=old_phase
		GameState.add_item(str(batch.iid),1,true)
		return "没能保存这次意见，小份已留回背包。先收着，保存恢复后再来。"
	return ""

static func tasting_purpose(who: String) -> String:
	return str({"mio":"忙完公告栏，带一小份去河边","haru":"下午配茶，坐着分食","kazuko":"轮班歇口气，给下一位留出取餐位置"}.get(who,""))

static func record_eaten(iid: String) -> void:
	if iid == "opening_leftover" and not opening().service.is_empty():
		opening().service["self_eaten"] = int(opening().service.get("self_eaten", 0)) + 1
		return
	for batch: Dictionary in opening().batches:
		if str(batch.iid) == iid:
			batch.self_eaten = int(batch.self_eaten) + 1
			GameState.state_changed.emit()
			return

static func confirm_plan(portion: String, presentation: String) -> String:
	var p: Dictionary = opening()
	if str(p.phase) != "decision": return "先听过两位街坊的具体意见，再决定摆哪一篮。"
	if portion not in ["bite", "whole"] or presentation not in ["paper", "plate"]: return "先选小份或整份，再选用纸包还是盘子。"
	p.final = {"menu": str(p.menu), "portion": portion, "presentation": presentation,
		"trial_batch": int(current_batch().id), "recipe": str(MENUS[p.menu]), "decided_day": GameState.day}
	p.phase = "site"
	_commit()
	return ""

static func layout_fingerprint() -> String:
	var chosen: Array=[]
	var prior: Array=opening().layout_trial.get("seating",[])
	for kind: String in ["bench","picnic_table"]:
		var options: Array=GameState.placements.filter(func(entry: Dictionary):return str(entry.item)==kind)
		options.sort_custom(func(a: Dictionary,b: Dictionary):return int(a.uid)<int(b.uid))
		var selected: Dictionary={}
		for entry: Dictionary in options:
			if prior.has(int(entry.uid)):selected=entry;break
		if selected.is_empty() and not options.is_empty():selected=options[0]
		chosen.append(LayoutValidity.anchor(selected))
	return JSON.stringify(chosen).sha256_text()

static func current_layout_valid() -> bool:
	var trial: Dictionary=opening().layout_trial
	if trial.is_empty() or not GameState.seating_ready():return false
	var token: String=str(trial.get("revision",""))
	if int(trial.get("scope_version",0))==1 and not LayoutValidity.measured(trial.get("path",[])):return false
	var expected: String=layout_fingerprint() if int(trial.get("scope_version",0))==1 else JSON.stringify(GameState.placements).sha256_text()
	return token==expected and LayoutValidity.path_clear(trial.get("path",[]))

static func record_layout(result: Dictionary, who: String, actually_present: bool) -> String:
	if phase() not in ["site", "ready", "applied", "done"]: return "先把试吃和份量定下来，再请人试走。"
	if not actually_present: return "人还没来，等他到了再一起走。"
	if not GameState.seating_ready(): return "先摆好这组桌椅，再请人走走。"
	if not result.get("ok", false): return str(result.get("reason", "路还没通。"))
	if str(result.get("revision", "")) != layout_fingerprint(): return "摆放已经变了，再按现在的样子走一次。"
	var prior_seating: Array=opening().layout_trial.get("seating",[]).duplicate()
	var saved_path: Array = []
	for point: Variant in result.get("path", []):
		if point is Vector3: saved_path.append({"x": point.x, "y": point.y, "z": point.z})
		elif point is Dictionary: saved_path.append(point.duplicate(true))
	if not LayoutValidity.measured(saved_path):return "还没走到桌边，等这一趟走完再继续。"
	if LayoutValidity.point(saved_path[-1]).distance_to(Vector3(2,0,13))>.2:return "还没到取餐的地方，这一趟先留着。"
	if not LayoutValidity.path_clear(saved_path):return "刚才那条路被挡住了，先看看挡住的位置，食物留着。"
	opening().layout_trial = result.duplicate(true)
	opening().layout_trial["path"] = saved_path
	opening().layout_trial["who"] = who
	opening().layout_trial["scope_version"]=1
	var selected_ids: Array=[]
	for kind: String in ["bench","picnic_table"]:
		var options: Array=GameState.placements.filter(func(entry: Dictionary):return str(entry.item)==kind)
		options.sort_custom(func(a: Dictionary,b: Dictionary):return int(a.uid)<int(b.uid))
		var selected: Dictionary={}
		for entry: Dictionary in options:
			if prior_seating.has(int(entry.uid)):selected=entry;break
		if selected.is_empty() and not options.is_empty():selected=options[0]
		if not selected.is_empty():selected_ids.append(int(selected.uid))
	opening().layout_trial["seating"]=selected_ids
	if opening().service.is_empty(): opening().phase = "ready"
	else: opening().service.revision = str(result.revision)
	_commit()
	return ""

static func ready() -> bool:
	var p: Dictionary = opening()
	return str(p.phase) in ["ready", "applied", "done"] and not p.final.is_empty() \
		and current_layout_valid()

static func apply(source: String) -> String:
	var p: Dictionary = opening()
	if uses_cooperation_mainline() and GameState.phase != "market": return "先把方案告诉澪。集市开摊后，再摆这一篮，免得食物提前放凉。"
	if not ready(): return "摆放有变化，先按现在的路线请人试走。"
	if not p.service.is_empty(): return "这一篮已经摆好了，先招待来的人。"
	if source not in ["own", "shop"]: return "选好这一篮食材由谁准备。"
	var required: Dictionary = service_ingredients(str(p.final.menu), str(p.final.portion))
	if source == "own":
		for iid: String in required:
			if GameState.unreserved_count(iid) < int(required[iid]): return "这一篮还差食材：" + _ingredient_text(required)
		for iid: String in required: GameState.remove_item(iid, int(required[iid]))
	p.service = {"source": source, "maker": "ren", "ingredients": required, "servings": 3, "remaining": 3,
		"served": {}, "day": GameState.day, "trial_batch": int(p.final.trial_batch), "revision": layout_fingerprint()}
	p.phase = "applied"
	_commit()
	return ""

static func service_ingredients(menu: String, portion: String) -> Dictionary:
	var required: Dictionary = {}
	var contents: Dictionary = ingredients(menu)
	for iid: String in contents: required[iid] = int(contents[iid]) * (1 if portion == "bite" else 3)
	return required

static func _handoff_check(who: String, actually_present: bool, receiver_at: Vector3, giver_at: Vector3, finishing: bool = false) -> String:
	var p: Dictionary = opening()
	var service: Dictionary = p.service
	if str(p.phase) not in ["applied", "done"] or service.is_empty(): return "先按选好的菜单把这一篮摆出来。"
	if not actually_present or who not in ["mio", "haru", "kazuko"]: return "人还没到摊边，先等他过来。"
	if not current_layout_valid() or str(service.revision) not in [layout_fingerprint(),str(p.layout_trial.get("revision",""))]: return "取餐的路或桌椅变了，先看看这一处；篮里的食物还留着。"
	var stop := Vector3(2, 0, 13)
	if not receiver_at.is_finite() or not giver_at.is_finite() or receiver_at.distance_to(stop) > 1.0 or giver_at.distance_to(receiver_at) > 1.35:
		return "先到取餐停点，再当面递这一份。"
	if service.served.has(who): return "这一位已经领过了。"
	if not finishing and int(service.remaining) <= 0: return "这一篮已经分完了。"
	return ""

static func begin_handoff(who: String, actually_present: bool, receiver_at: Vector3, giver_at: Vector3) -> String:
	var why: String = _handoff_check(who, actually_present, receiver_at, giver_at)
	if why != "": return why
	var service: Dictionary = opening().service
	if service.has("pending"): return "手上这一份先交好，不同时拿两份。"
	service.remaining = int(service.remaining) - 1
	service["pending"] = {"who": who, "day": GameState.day, "units": 1}
	_commit()
	return ""

static func finish_handoff(who: String, actually_present: bool, receiver_at: Vector3, giver_at: Vector3) -> String:
	var service: Dictionary = opening().service
	if not service.has("pending") or str(service.pending.who) != who: return "没有这一份正在交接的食物。"
	var why: String = _handoff_check(who, actually_present, receiver_at, giver_at, true)
	if why != "":
		cancel_handoff()
		return why
	service.served[who] = GameState.day
	service.erase("pending")
	_commit()
	return ""

static func cancel_handoff() -> void:
	var service: Dictionary = opening().service
	if service.has("pending"):
		service.remaining = int(service.remaining) + 1
		service.erase("pending")
		_commit()

static func serve(who: String, actually_present: bool, receiver_at: Vector3 = Vector3.INF, giver_at: Vector3 = Vector3.INF) -> String:
	var why: String = begin_handoff(who, actually_present, receiver_at, giver_at)
	return why if why != "" else finish_handoff(who, actually_present, receiver_at, giver_at)

static func pack_leftovers() -> String:
	var p: Dictionary = opening()
	if p.service.is_empty() or p.service.served.is_empty(): return "还没招待客人呢。先递一份，再收剩的。"
	if p.service.has("pending"): return "手上这一份先交好，再收剩下的。"
	var remaining: int = int(p.service.remaining)
	if remaining <= 0: return "这一篮已经分好，没有多出来的份量。"
	p.service["packed"] = int(p.service.get("packed", 0)) + remaining
	p.service.remaining = 0
	_register_data()
	GameState.add_item("opening_leftover", remaining, true)
	_commit()
	return ""

static func finish() -> String:
	var p: Dictionary = opening()
	if str(p.phase) == "done": return "这张纸签已经收好了；剩下的食物仍可以递出或打包。"
	if str(p.phase) != "applied" or p.service.served.size() < 1: return "先招待一位来摊边的街坊，再收这张纸签。"
	p.phase = "done"
	p.followup = true
	state().tracked = false
	_commit()
	return ""

static func hint() -> String:
	match phase():
		"invitation", "plan": return "面包店柜台旁有合作纸签；可以试做，也可以帮忙安排取餐。"
		"trial": return "和莲确认试料，再用店里的烤箱试做一份。" if str(opening().role) == "food" else "把试料交给莲，再去庭院看看取餐与歇脚的位置。"
		"feedback": return "带着这一批的小份，请澪、春、和子中的两位尝尝；留下一份也能自己吃。"
		"decision": return "回面包店，保留或调整菜单，决定小份/整份和纸包/盘子。"
		"site": return "在庭院合作纸签请人试走，摆放改过也可以重试。"
		"ready": return "菜单和路线已试过。告诉澪、邀请街坊；开摊后在合作纸签摆出这一篮。"
		"applied": return "到庭院摊边招待一位街坊，之后可以收好纸签。"
	return "这次合作记下来了，夏祭时可以继续用这份经验。"

static func _commit() -> bool:
	checks()
	GameState.state_changed.emit()
	return GameState.save_game()

static func uses_cooperation_mainline() -> bool:
	return str(state().mainline_mode) == "cooperation"

static func checks() -> void:
	var G := GameState
	if uses_cooperation_mainline() and G.qstate("Q01") == "done" and G.qstate("Q05") == "locked" and ready():
		G.quests["Q05"] = {"state": "available", "step": 0}
		G.toast.emit("菜单和取餐路线试好了，把方案告诉澪吧")
		G.quest_changed.emit("Q05")

static func market_used() -> bool:
	return not opening().service.get("served", {}).is_empty()

static func clear_tracking() -> void:
	if GameState.flags.get("summer_projects", {}) is Dictionary and GameState.flags.summer_projects.has("tracked"):
		GameState.flags.summer_projects.tracked = false

static func track() -> void:
	state().tracked = true
	DailyLife.clear_tracking()
	GameState.flags.erase("request_tracked")
	GameState.state_changed.emit()

static func notes() -> String:
	var p: Dictionary = opening()
	var lines: Array[String] = [hint()]
	if str(p.menu) != "": lines.append("菜单：" + str(MENU_NAMES[p.menu]))
	for batch: Dictionary in p.batches:
		var people: Array[String] = []
		for who: String in batch.tasters: people.append(GameState.npc_display(who))
		lines.append("第%d批：%s制作，%s；试吃：%s；自己吃过%d小份" % [int(batch.id), "空" if batch.maker == "player" else "莲", "自带食材" if batch.source == "own" else "店里试料", "、".join(people) if not people.is_empty() else "尚未递出", int(batch.self_eaten)])
		for feedback: Dictionary in batch.get("usage_feedback",[]):
			lines.append("%s：%s，用%s尝过；%s" % [GameState.npc_display(str(feedback.who)),str(MENU_NAMES.get(str(feedback.menu),"面包")),"纸托" if feedback.presentation=="paper" else "餐盘",str(feedback.purpose)])
		for feedback: Dictionary in batch.get("received_feedback",[]):
			lines.append("%s收下了一小份，提到%s；可与%s的桌边意见比较" % [GameState.npc_display(str(feedback.who)),str(feedback.purpose),GameState.npc_display(str(feedback.reference_who))])
	if not p.final.is_empty(): lines.append("决定：%s，%s；取餐试走：%s" % ["每份切三小份" if p.final.portion == "bite" else "每人一整份", "纸包" if p.final.presentation == "paper" else "盘子", GameState.npc_display(str(p.layout_trial.get("who", ""))) if not p.layout_trial.is_empty() else "尚未试走"])
	if not p.service.is_empty():
		var served: Array[String] = []
		for who: String in p.service.served: served.append(GameState.npc_display(who))
		lines.append("现场：莲制作，%s；已递给%s；篮内%d份、打包%d份、自己吃过%d份" % ["自带食材" if p.service.source == "own" else "店里食材", "、".join(served) if not served.is_empty() else "尚无人领取", int(p.service.remaining), int(p.service.get("packed", 0)), int(p.service.get("self_eaten", 0))])
	return "\n".join(lines)

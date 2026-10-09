class_name SummerGathering
extends RefCounted
## A finite new basket reuses earlier decisions, never the first market's food ledger.
static func state() -> Dictionary:
	var G := GameState
	if not G.flags.get("summer_gathering", {}) is Dictionary: G.flags["summer_gathering"] = {}
	if not G.flags.has("summer_gathering"): G.flags["summer_gathering"] = {}
	var data: Dictionary = G.flags.summer_gathering
	data.merge({"version":1, "sessions":{}, "reunion_day":-1}, false)
	data.version = 1
	data.reunion_day = int(data.reunion_day)
	for id: String in data.sessions:
		var entry: Dictionary = data.sessions[id]
		for field: String in ["day", "remaining", "packed", "self_eaten", "trial_batch"]: entry[field] = int(entry.get(field, 0))
		if entry.has("closed_day"): entry.closed_day = int(entry.closed_day)
		for iid: String in entry.get("ingredients", {}): entry.ingredients[iid] = int(entry.ingredients[iid])
		for who: String in entry.get("served", {}): entry.served[who].day = int(entry.served[who].day)
		for unit: Dictionary in entry.get("units",[]):
			unit.index=int(unit.index)
			for field: String in ["planned_day","received_day","packed_day","eaten_day"]:
				if unit.has(field): unit[field]=int(unit[field])
			if unit.get("use",{}).has("placed_day"): unit.use.placed_day=int(unit.use.placed_day)
		_register_leftover(id, entry)
	return data

static func context() -> String:
	if GameState.festival_now() == "natsumatsuri": return "festival"
	if int(state().reunion_day) == GameState.day: return "reunion"
	return ""

static func agree_reunion(mio_present: bool) -> String:
	if GameState.qstate("Q05") != "done" or GameState.day <= 17: return "夏祭之后再另约树下的一晚。"
	if not mio_present: return "先找到澪，问她今晚有空没有。"
	state().reunion_day = GameState.day
	if GameState.minute < 18.5 * 60: GameState.skip_to(18.5 * 60)
	_commit()
	return ""

static func current() -> Dictionary:
	return state().sessions.get(context(), {})

static func service_cost(menu: String, portion: String) -> Dictionary:
	return SummerProjects.service_ingredients(menu, portion)

static func prepare(portion: String, presentation: String, source: String, ren_present: bool) -> String:
	var mode: String = context()
	if mode == "" or GameState.qstate("Q05") != "done": return "等夏祭现场，或和澪明确约好的树下晚会再准备。"
	if state().sessions.has(mode): return "今晚这篮已经备过了，先分桌上的，剩的还能收好。"
	var earlier: Dictionary = SummerProjects.opening().final
	if earlier.is_empty(): return "还没有试好的合作菜单。先继续面包店的那张纸签，也可以只来看晚会。"
	if not ren_present: return "莲还没来，等他到了再烤这一篮。"
	if portion not in ["bite", "whole"] or presentation not in ["paper", "plate"] or source not in ["own", "shop"]: return "先选做多少、怎么装，还有谁出食材。"
	if presentation == "plate" and not plate_ready(): return "用盘子的话，把桌子放到歇脚处5米以内，端着才不太远。"
	var cost: Dictionary = service_cost(str(earlier.menu), portion)
	if source == "own":
		for iid: String in cost:
			if GameState.unreserved_count(iid) < int(cost[iid]): return "带来的食材还不够。先去取些，或请莲用店里的。"
		for iid: String in cost: GameState.remove_item(iid, int(cost[iid]))
	var entry := {"session_id":mode + ":" + str(GameState.day), "context":mode, "day":GameState.day,
		"menu":str(earlier.menu), "portion":portion, "presentation":presentation, "source":source,
		"maker":"ren", "trial_batch":int(earlier.trial_batch), "ingredients":cost,
		"remaining":3, "served":{}, "packed":0, "self_eaten":0, "closed":false}
	state().sessions[mode] = entry
	FoodPurpose.initialize(entry)
	_register_leftover(mode, entry)
	_commit()
	return ""

static func take(who: String, result: Dictionary, target: Vector3) -> String:
	var entry: Dictionary = current()
	if entry.is_empty() or entry.closed or int(entry.day) != GameState.day: return "这是上回那篮。剩的可以收好，今晚的另外准备。"
	if who not in ["mio", "haru", "ren"] or not result.get("present", false): return "人还没到，饭菜先放桌上。"
	if entry.served.has(who) or int(entry.remaining) <= 0: return "这一位已领过，或这一篮已经分完。"
	if not FoodPurpose.units(entry).is_empty() and FoodPurpose.eligible(entry,who).is_empty(): return "剩的都写了名字，先留给说好的那几位。"
	if entry.presentation == "plate" and not plate_ready(): return "桌椅移远了，盘子先留在桌上。把歇脚处与取放处安排在5米内再领。"
	if str(result.get("revision", "")) != SummerSpace.revision(): return "桌椅改过了，按现在的位置重新走到取餐处。"
	var at: Dictionary = result.get("position", {})
	if not target.is_finite() or not result.get("arrived", false) or Vector3(float(at.get("x", INF)), float(at.get("y", INF)), float(at.get("z", INF))).distance_to(target) > .7: return "还没走到取餐的地方，饭菜先留在桌上。"
	if context() == "festival" and result.get("crossed_dance", false): return "这条来路穿过了盆舞圈，先给跳舞的人留开。"
	entry.remaining = int(entry.remaining) - 1
	entry.served[who] = result.duplicate(true)
	entry.served[who]["day"] = GameState.day
	var unit: Dictionary=FoodPurpose.received(entry,who)
	if not unit.is_empty(): entry.served[who]["unit_id"]=unit.id
	_commit()
	return ""

static func cleanup(id: String) -> String:
	var entry: Dictionary = state().sessions.get(id, {})
	if entry.is_empty(): return "这里还没有摆饭菜，没东西要打包。"
	if entry.closed: return "这一篮已经收好了，手账上还有记着。"
	var count: int = int(entry.remaining)
	var iid: String = leftover_id(id)
	_register_leftover(id, entry)
	if count > 0 and not GameState.can_add_bundle({iid:count}): return "背包先留出剩食的位置，桌上的份量还在。"
	if count > 0: GameState.add_item(iid, count, true)
	entry.packed = int(entry.packed)+count
	entry.remaining = 0
	FoodPurpose.packed(entry)
	entry.closed = true
	entry["closed_day"] = GameState.day
	_register_leftover(id, entry)
	var lamp: Dictionary = WorkshopProject.state().installed
	if not lamp.is_empty() and str(lamp.get("session_id", "")) == str(entry.session_id): WorkshopProject.stow()
	_commit()
	return ""

static func leftover_id(id: String) -> String: return "gathering_leftover_" + id

static func plate_ready() -> bool:
	var target: Vector3 = SummerSpace.stop_for("picnic_table") if SummerSpace.state().phase != "invitation" else Vector3(2,0,13)
	if not target.is_finite(): return false
	if SummerSpace.state().phase != "invitation":
		var resting: Vector3 = SummerSpace.stop_for("bench")
		return resting.is_finite() and resting.distance_to(target) <= 5
	for placement: Dictionary in GameState.placements:
		if placement.item != "bench": continue
		var at: Vector3 = Vector3(float(placement.x),0,float(placement.z)) + (Vector3.BACK*.9).rotated(Vector3.UP, deg_to_rad(90.0*int(placement.rot)))
		if at.distance_to(target) <= 5: return true
	return false

static func record_eaten(iid: String) -> void:
	for id: String in state().sessions:
		if iid == leftover_id(id):
			var entry: Dictionary = state().sessions[id]
			entry.self_eaten = int(entry.self_eaten) + 1
			FoodPurpose.consume(entry)
			return

static func _register_leftover(id: String, entry: Dictionary) -> void:
	var output: String = str(SummerProjects.MENUS.get(str(entry.menu), "veg_sandwich"))
	GameState.items_db[leftover_id(id)] = {"name":("夏祭" if id == "festival" else "树下晚会") + "留下的" + str(SummerProjects.MENU_NAMES.get(str(entry.menu), "面包")),
		"icon":str(GameState.item(output).get("icon", "onigiri")), "key":false, "dish":true, "sell":0,
		"desc":"莲在第%d天做的一篮，第%d天收好，留着带回家吃。" % [int(entry.day), int(entry.get("closed_day", entry.day))]}

static func _commit() -> void:
	GameState.state_changed.emit()
	GameState.save_game()

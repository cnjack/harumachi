class_name MainlineProgress
extends RefCounted
const DIRECTION_OPTIONS := ["留在晴町，先照料一块小菜地", "和街坊商量，再一起开一次摊", "以后再回来，把这个家好好留着", "先不决定，慢慢想一想"]
const DIRECTION_NOTES := ["先照料一块小菜地，够自己吃，也能分一点。", "下次开摊前，先问问街坊想吃什么、怎样拿着方便。", "以后再回来。钥匙和这个夏天的记忆，好好留着。", "今年先记到这里。下一步，我再慢慢想。"]
const DIRECTION_CAPTIONS := ["种点菜","再开摊","再回来","慢慢想"]
## `ended` is the legacy first-weekend milestone, never the end of summer.
static func initialize() -> void:
	var G := GameState
	var data: Dictionary = G.flags.get("mainline_progress", {})
	data["version"] = 2
	data["first_weekend"] = G.qstate("Q05") == "done" or bool(G.flags.get("ended", false))
	data["summer_complete"] = G.qstate("Q15") == "done"
	G.flags["mainline_progress"] = data
	# Existing active/completed projects keep their facts; only a new offer uses both gates.
	if G.qstate("Q11") == "locked" and can_offer_revival():
		G.quests["Q11"] = {"state": "available", "step": 0}

static func can_offer_revival() -> bool:
	var G := GameState
	if G.qstate("Q11") in ["active", "done"]: return true
	if G.flags.get("revival_accepted", false): return true
	if G.flags.get("summer_invitation", {}).get("presented", false): return true
	# These saved works are stronger evidence than a missing quest flag in an old profile.
	if str(G.flags.get("summer_workshop", {}).get("phase", "invitation")) != "invitation": return true
	if str(G.flags.get("summer_space", {}).get("phase", "invitation")) != "invitation": return true
	return G.qstate("Q10") == "done" and G.qstate("Q05") == "done"

static func accept_revival() -> bool:
	if not can_offer_revival(): return false
	initialize()
	if not GameState.start_quest("Q11"): return false
	GameState.flags["revival_accepted"] = true
	GameState.save_game()
	return true

static func season_goal() -> String:
	if GameState.qstate("Q15") == "done": return "夏祭之后 · 下一次相约"
	if GameState.qstate("Q11") in ["active", "done"]: return "今年夏祭 · 做给今天的人"
	if GameState.qstate("Q10") == "done": return "旧约定 · 先让树下有人坐"
	return "回到晴町 · 找回树下的约定"

## Select exactly one player-tracked action. A commitment remains visible without taking it over.
static func objective(house_room: String = "") -> Dictionary:
	var G := GameState
	var result: Dictionary = {"title": season_goal(), "text": "", "source": "mainline"}
	var visit: Dictionary = ResidentVisits.hud()
	var request: Dictionary = G.request()
	var life_id: String = str(DailyLife.state().tracked)
	var q: String = G.tracked_quest
	if ResidentVisits.tracked() and not visit.is_empty():
		result.text = str(visit.title) + "：" + str(visit.text)
		result.source = "visits"
	elif SummerProjects.state().tracked:
		result.text = "一小篮的合作：" + SummerProjects.hint()
		result.source = "cooperation"
	elif G.flags.get("request_tracked", false) and not request.is_empty() and not request.get("done", false):
		result.text = "%s的小事：%s ×%d · 可交 %d" % [G.npc_display(str(request.who)), G.item_name(str(request.item)), int(request.n), mini(G.unreserved_count(str(request.item)), int(request.n))]
		result.source = "request"
	elif life_id != "" and not DailyLife.done(life_id):
		result.text = DailyLife.title(life_id) + "：" + DailyLife.hint(life_id, house_room)
		result.source = "life"
	elif not direction_action().is_empty() and G.qstate(q) != "active":
		result.text = str(direction_action().text)
		result.source = "direction"
	elif G.qstate(q) == "active":
		result.text = G.quest_title(q) + "：" + G.quest_step_text(q)
		result.source = "quest"
	elif G.qstate("Q10") == "available":
		result.text = "回家打开卧室壁橱的箱子，看看奶奶留下的照片"
	elif not visit.is_empty() and G.qstate("Q05") == "done":
		result.text = str(visit.title) + "：" + str(visit.text)
		result.source = "visits"
	elif G.qstate("Q11") == "available" and can_offer_revival():
		result.text = "找澪商量是否复办夏祭；接下后一起翻旧账本"
	else:
		result.text = G.objective_text()
	var promise: String = ResidentVisits.promise_text()
	if promise != "" and not str(result.text).contains(promise): result.text += "\n约定：" + promise
	return result

static func summer_complete() -> bool:
	initialize()
	return bool(GameState.flags.mainline_progress.summer_complete)

static func weekend_complete() -> void:
	GameState.flags["ended"] = true
	initialize()

static func direction() -> Dictionary:
	var data: Dictionary = GameState.flags.get("summer_direction",{})
	if data.has("choice"): data.choice=int(data.choice)
	if data.has("day"): data.day=int(data.day)
	return data

static func choose_direction(choice: int, origin: String) -> bool:
	if choice<0 or choice>=DIRECTION_OPTIONS.size(): return false
	if origin=="hanabi" and not GameState.flags.get("fest_hanabi",false): return false
	if origin=="record" and not GameState.flags.get("hanabi_revisit",false): return false
	if origin=="home" and GameState.qstate("Q15")!="done": return false
	if origin not in ["hanabi","record","home"]: return false
	GameState.flags["summer_direction"]={"choice":choice,"day":GameState.day,"origin":origin,"action_done":false}
	ResidentVisits.clear_tracking()
	DailyLife.clear_tracking()
	SummerProjects.clear_tracking()
	GameState.flags.erase("request_tracked")
	GameState.tracked_quest = ""
	GameState.state_changed.emit()
	GameState.save_game()
	return true

static func direction_action() -> Dictionary:
	var next: Dictionary = direction()
	if GameState.qstate("Q15") != "done" or next.is_empty() or next.get("action_done", false): return {}
	match int(next.choice):
		0:
			for pid: String in GameState.plot_ids():
				if GameState.plot_state(pid) in ["wild", "tilled"]:
					return {"text":"下一步：到一块空菜地播下种子；种子不够可去农园工具屋旁购买", "target":"planter" if pid == "court" else "plot_" + pid}
			return {"text":"下一步：去农园照料现有作物，收下一块地后再播种", "target":"farm_sign"}
		1: return {"text":"下一步：带一份自己种的菜去周六集市实际卖出；未到周六可在日历查看日期", "target":"stall"}
		2: return {"text":"下一步：到邮局亲手投一封回乡邀请，写清下次想一起做的事", "target":"visit_post_door"}
		3: return {"text":"下一步：挑一户已邀请你的街坊回访。试过的位置和寄来的信都留着", "target":"visit_home_haru_door"}
	return {}

static func record_direction_action(kind: String) -> bool:
	var next: Dictionary = direction()
	if next.is_empty() or next.get("action_done", false) or GameState.qstate("Q15") != "done": return false
	var expected: String = ["plant", "market", "letter", "visit"][int(next.choice)]
	if kind != expected: return false
	next.action_done = true
	next.action_day = GameState.day
	GameState.state_changed.emit()
	return true

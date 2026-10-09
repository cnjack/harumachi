class_name DailyLife
extends RefCounted
## Persisted life-event facts. The player starts an event; mornings never play one.
const IDS := ["meal", "tea", "card"]
const DAYS := {"meal": 0, "tea": 1, "card": 2}
const TITLES := {"meal": "第一顿自己的饭", "tea": "春的麦茶", "card": "莲的小纸牌"}


static func initialize(fresh: bool = false) -> void:
	var G := GameState
	if G.flags.get("daily_life", {}) is Dictionary and G.flags.get("daily_life", {}).get("version", 0) == 1:
		var data: Dictionary = G.flags.daily_life
		for key: String in ["version", "introduced_day", "last_major_day", "last_meal_day"]:
			if data.has(key): data[key] = int(data[key])
		for life_event: Dictionary in data.events.values():
			for key: String in ["deferred_day", "started_day", "completed_day", "choice", "temperature", "portions"]:
				if life_event.has(key): life_event[key] = int(life_event[key])
		if data.has("eaten"):
			for iid: String in data.eaten: data.eaten[iid] = int(data.eaten[iid])
		return
	var events: Dictionary = {}
	for id: String in IDS:
		events[id] = {"state": "pending", "deferred_day": -1, "started_day": -1, "completed_day": -1}
	G.flags["daily_life"] = {"version": 1, "introduced_day": G.day, "old_save": not fresh,
		"last_major_day": -1, "last_major_source": "", "events": events, "tracked": "", "followups": {}}


static func state() -> Dictionary:
	initialize()
	return GameState.flags.daily_life


static func event(id: String) -> Dictionary:
	return state().events.get(id, {})


static func done(id: String) -> bool:
	return str(event(id).get("state", "")) == "done"


static func quota_used() -> bool:
	return int(state().last_major_day) == GameState.day


static func available(id: String) -> bool:
	var G := GameState
	var e: Dictionary = event(id)
	if e.is_empty() or done(id) or G.qstate("Q00") != "done" or int(e.deferred_day) == G.day:
		return false
	if G.day < int(state().introduced_day) + int(DAYS.get(id, 0)):
		return false
	# Cooking follow-ups can continue; a resumed tea/chat still occupies today's scene.
	if str(e.state) == "in_progress":
		return id == "meal" or not quota_used() or str(state().last_major_source) == "life:" + id
	return not quota_used()


static func begin(id: String) -> bool:
	if not available(id):
		return false
	var e: Dictionary = event(id)
	if str(e.state) == "pending":
		e.state = "in_progress"
		e.started_day = GameState.day
		mark_major("life:" + id)
	elif id != "meal":
		mark_major("life:" + id)
	return true


static func defer(id: String) -> void:
	if not done(id):
		event(id).deferred_day = GameState.day
		if str(state().tracked) == id:
			state().tracked = ""
		GameState.state_changed.emit()


static func resume(id: String) -> bool:
	event(id).deferred_day = -1
	return available(id)


static func mark_major(source: String) -> void:
	state().last_major_day = GameState.day
	state().last_major_source = source
	GameState.state_changed.emit()


static func track(id: String) -> void:
	SummerProjects.clear_tracking()
	state().tracked = id
	GameState.flags.erase("request_tracked")
	GameState.state_changed.emit()


static func clear_tracking() -> void:
	if GameState.flags.has("daily_life"):
		state().tracked = ""


static func title(id: String) -> String:
	return "今天给自己做饭" if id == "meal" and state().old_save else str(TITLES.get(id, "生活小事"))


static func hint(id: String, house_room: String = "") -> String:
	if id == "meal":
		if house_room == "bedroom":
			return "从卧室门到客厅，沿走廊去厨房；也可以先出门。"
		if house_room == "living":
			return "从客厅的门到走廊，左转进厨房。"
		if house_room in ["hall", "genkan"]:
			return "沿走廊向左，穿过暖帘就是厨房。"
		if event(id).get("cooked", false):
			return "去厨房饭桌，吃一份或把饭团收好。"
		if event(id).get("parcel_claimed", false):
			return "在厨房灶台做「自家的饭团」，然后回饭桌。"
		return "看看厨房碗柜上的食材便笺；也可以先安顿。"
	if id == "tea":
		return "春在菜圃时，去育苗台旁的麦茶托盘看看。"
	return "莲有空时，看看面包推车旁的小纸牌；改天也行。"


static func claim_meal() -> String:
	var G := GameState
	var e: Dictionary = event("meal")
	if e.get("parcel_claimed", false):
		return "食材已经领过了，灶台和饭桌都还在。"
	if not begin("meal"):
		return "今天先忙别的也行，食材便笺会留着。"
	e.parcel_claimed = true
	G.add_item("home_meal_parcel", 1, true)
	G.recipes_known["first_home_onigiri"] = true
	track("meal")
	G.save_game()
	return ""


static func record_craft(rid: String) -> void:
	if rid != "first_home_onigiri":
		return
	var e: Dictionary = event("meal")
	e.cooked = true
	e.portions = 2
	GameState.state_changed.emit()
	GameState.save_game()


static func held(iid: String) -> int:
	return 2 if iid == "onigiri" and event("meal").get("cooked", false) and not done("meal") else 0


static func finish_meal(choice: int) -> String:
	var G := GameState
	var e: Dictionary = event("meal")
	if done("meal"):
		return "饭桌已经收好了。以后想吃，再做一点就行。"
	if not e.get("cooked", false) or G.count("onigiri") < 2:
		return "先在灶台做两份饭团；放进收纳箱的饭团也可以取回来。"
	if choice not in [0, 1]:
		return "先放着，改天再决定。"
	if choice == 0:
		G.remove_item("onigiri", 1)
		_note_food("onigiri")
	e.choice = choice
	e.ate = choice == 0
	e.packed = choice == 1
	G.recipes_known["plain_onigiri"] = true
	FoodPurpose.register_meal()
	G.recipes_known.erase("first_home_onigiri")
	_complete("meal")
	return ""


static func finish_tea(temperature: int, help_intent: bool) -> String:
	if done("tea"):
		return ""
	if str(event("tea").state) != "in_progress" or temperature not in [0, 1]:
		return "春有空的时候，再一起喝一杯。"
	event("tea").temperature = temperature
	event("tea").drank = true
	event("tea").help_intent = help_intent
	_complete("tea")
	return ""


static func is_weekend_stall() -> bool:
	var G := GameState
	return G.weekday() == G.SATURDAY and G.minute >= G.MARKET_OPEN and G.minute < G.MARKET_CLOSE


static func claim_tasting() -> String:
	var G := GameState
	var e: Dictionary = event("card")
	if str(e.state) != "in_progress":
		return "先和莲聊聊这张纸牌。"
	if not e.get("sample_claimed", false):
		e.sample_claimed = true
		G.add_item("life_bread_sample", 1, true)
		G.save_game()
	return ""


static func finish_card(choice: int) -> String:
	var G := GameState
	var e: Dictionary = event("card")
	if done("card"):
		return ""
	if str(e.state) != "in_progress" or choice not in [0, 1, 2]:
		return "下次路过，纸牌还在这儿。"
	if choice == 1:
		if not G.has("life_bread_sample"):
			return "试吃的那一小份，莲还没拿出来。"
		G.remove_item("life_bread_sample", 1)
		e.tasted = true
	else:
		# A reserved sample never becomes an unrelated reward after choosing a different action.
		if G.has("life_bread_sample"):
			G.remove_item("life_bread_sample", 1)
	e.helped_sign = choice == 0
	e.choice = choice
	e.weekend_stall = is_weekend_stall()
	_complete("card")
	return ""


static func record_market() -> void:
	var G := GameState
	if G.qstate("Q05") != "done" or not G.flags.get("ended", false):
		return
	mark_major("Q05")
	if not done("card") and G.day >= int(state().introduced_day) + 2:
		if G.has("life_bread_sample"):
			G.remove_item("life_bread_sample", 1)
		event("card").main_market = true
		event("card").choice = 3
		_complete("card", false)


static func edible(iid: String) -> bool:
	return GameState.item(iid).has("dish") or iid in ["onigiri", "melon_pan", "candy_apple"]


static func eat_food(iid: String,together: bool=false) -> String:
	var G := GameState
	if not edible(iid) or G.unreserved_count(iid) < 1:
		return "这份已经预留，或者还没做好。先留着它。"
	G.remove_item(iid, 1)
	SummerProjects.record_eaten(iid)
	SummerGathering.record_eaten(iid)
	FoodPurpose.record_eaten(iid,together)
	NeighbourMeals.record_eaten(iid,together)
	_note_food(iid)
	G.state_changed.emit()
	G.save_game()
	return ""


static func _note_food(iid: String) -> void:
	var eaten: Dictionary = state().get("eaten", {})
	eaten[iid] = int(eaten.get(iid, 0)) + 1
	state().eaten = eaten
	state().last_meal_day = GameState.day
	GameState.daily["meals"] = int(GameState.daily.get("meals", 0)) + 1


static func _complete(id: String, save_now: bool = true) -> void:
	event(id).state = "done"
	event(id).completed_day = GameState.day
	if str(state().tracked) == id:
		state().tracked = ""
	GameState.state_changed.emit()
	if save_now:
		GameState.save_game()

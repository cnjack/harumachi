extends RefCounted
## Behavioural regressions from the independent fun audit, not a subjective fun score.
var t: Node
var G: Node
var main: Node


func _init(runner: Node) -> void:
	t = runner
	G = GameState
	main = t.main


func _entry(id: String) -> Dictionary:
	for entry: Dictionary in Dialogue.entries:
		if str(entry.id) == id:
			return entry
	return {}


func _text(node: Node) -> String:
	var result := ""
	if node is Label or node is Button:
		result += str(node.text) + "\n"
	for child in node.get_children():
		result += _text(child)
	return result


func _button(node: Node, prefix: String) -> Button:
	if node is Button and str(node.text).begins_with(prefix):
		return node as Button
	for child in node.get_children():
		var found: Button = _button(child, prefix)
		if found != null:
			return found
	return null


func _capture_number_choice(sink: Array) -> void:
	sink.append(await main.ui.choose(["一", "二", "三", "四", "下一页", "上一页", "算了"]))


func run() -> void:
	var original: Dictionary = G.to_dict().duplicate(true)
	if main.in_room:
		if main.room_kind == "house":
			await main.exit_room()
		else:
			await main.exit_interior()
	main.world.set_region("town")
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	G.quests["Q01"] = {"state": "available", "step": 0}
	await t.use("mio", [1])
	t.check("FUN_CHOICE", "exploring first really leaves the invitation unaccepted", G.qstate("Q01") == "available" and G.qstep("Q01") == 0)
	await t.use("mio", [0])
	t.check("FUN_CHOICE", "a deferred invitation can later be accepted normally", G.at_step("Q01", "read_board"))
	G.quests["Q01"] = {"state": "available", "step": 0}
	main.ui.open_quests()
	await t.frames(3)
	var neighbour: Button = _button(main.ui.modal_layer, "新邻居")
	if neighbour:
		neighbour.pressed.emit()
		await t.frames(2)
		var accept: Button = _button(main.ui.modal_layer, "接受委托")
		if accept:
			accept.pressed.emit()
	main.ui.close_modal(false)
	await t.use("mio")
	t.check("FUN_CHOICE", "accepting the deferred invitation in J still lets Mio continue", G.at_step("Q01", "read_board"))
	G.flags["request_tracked"] = true
	G.daily["request"] = {"who": "tanaka", "item": "radish", "n": 2, "done": false, "reward": 110}
	G.tracked_quest = "Q01"
	main.ui.open_quests()
	await t.frames(3)
	neighbour = _button(main.ui.modal_layer, "新邻居")
	if neighbour:
		neighbour.pressed.emit()
		await t.frames(2)
	var retrack: Button = _button(main.ui.modal_layer, "设为追踪")
	if retrack:
		retrack.pressed.emit()
	t.check("FUN_CHOICE", "street-request tracking can switch back to the same main quest", not G.flags.get("request_tracked", false) and G.tracked_quest == "Q01")
	main.ui.close_modal(false)
	G.new_game()
	G.clock_paused = true
	G.add_item("hoe", 1, true)
	G.open_plots(["farm0"])
	G.till("farm0")
	var seeds := ["seed_radish", "seed_komatsuna", "seed_tomato", "seed_potato", "seed_cucumber"]
	for index in seeds.size():
		G.add_item(seeds[index], 10 - index, true)
	main.ui.auto_choices = [4, 0]
	await main.story.farm.plot_act("farm0")
	t.check("FUN_CHOICE", "the fifth seed can be selected rather than disappearing", str(G.plots.farm0.crop) == "cucumber")
	G.inventory.clear()
	for item_id in ["radish", "komatsuna", "tomato", "cucumber", "potato"]:
		G.add_item(item_id, 1, true)
	var gifts: Array = G.giftables()
	gifts.sort_custom(func(a, b): return G.gift_points("mio", a) > G.gift_points("mio", b))
	var fifth_gift: String = str(gifts[4])
	main.ui.auto_choices = [4, 0]
	await main.story.farm._offer_gift("mio")
	t.check("FUN_CHOICE", "the fifth gift remains available and is actually transferred", str(G.daily.get("gifted", {}).get("mio", "")) == fifth_gift and G.count(fifth_gift) == 0)
	G.daily = {}
	G.inventory = {"tomato": 2, "cucumber": 1}
	G.flags["bakery_order_active"] = true
	var previous_line: String = main.ui.dlg_text.text
	main.ui.auto_choices = [0]
	await main.story.farm._offer_gift("mio")
	t.check("FUN_FACT", "fully reserved produce is neither offered nor thanked as a delivered gift", main.ui.dlg_text.text == previous_line and G.count("tomato") == 2 and not G.gifted_today("mio"))
	G.flags.erase("bakery_order_active")
	main.ui.auto_choices.clear()
	main.ui.instant = false
	var number_choice: Array = []
	_capture_number_choice.call_deferred(number_choice)
	await t.frames(4)
	var key := InputEventKey.new()
	key.keycode = KEY_5
	key.pressed = true
	Input.parse_input_event(key)
	await t.frames(3)
	t.check("FUN_CHOICE", "number five selects the fifth option on a full choice page", number_choice == [4])
	if number_choice.is_empty():
		main.ui.choice_made.emit(6)
		await t.frames(2)
	main.ui.instant = true
	main.ui.dialogue_end()
	G.new_game()
	G.clock_paused = true
	for item_id in ["radish", "komatsuna", "tomato", "cucumber", "potato"]:
		G.add_item(item_id, 1, true)
	main.ui.auto_choices = [4, 0]
	await main.story.farm._sell(1.0, "无人菜摊")
	t.check("FUN_CHOICE", "the fifth sale can be chosen without selling the first four", G.count("potato") == 0 and G.count("radish") == 1 and G.count("komatsuna") == 1)
	G.new_game()
	G.clock_paused = true
	for item_id in ["radish", "komatsuna", "tomato", "cucumber", "potato"]:
		G.add_item(item_id, 1, true)
	var produce: Array = G.produce_owned()
	produce.sort_custom(func(a, b): return main.story.fest.contest_score(a) > main.story.fest.contest_score(b))
	var fifth_entry: String = str(produce[4])
	main.ui.auto_choices = [4, 0]
	await main.story.fest._contest()
	t.check("FUN_CHOICE", "a lower-scoring fifth crop can still enter the contest", G.count(fifth_entry) == 0 and G.flags.get("fest_contest_entry", false))
	G.new_game()
	G.clock_paused = true
	G.inventory = {"tomato": 2, "cucumber": 1}
	G.flags["bakery_order_active"] = true
	main.ui.auto_choices = [0]
	await main.story.fest._contest()
	t.check("FUN_FACT", "the produce contest cannot take vegetables promised to Ren", G.count("tomato") == 2 and G.count("cucumber") == 1 and not G.flags.get("fest_contest_entry", false))
	G.can_level = 1
	G.can_water = 8
	G.add_item("farm_can", 1, true)
	t.check("FUN_FEEDBACK", "the upgraded can prompt uses its real ten-use capacity", str(main.story.farm.prompt("farm_pump")).contains("8/10"))
	G.can_level = 2
	G.can_water = 16
	t.check("FUN_FEEDBACK", "the gold can prompt uses its real twenty-use capacity", str(main.story.farm.prompt("yard_tap")).contains("16/20"))
	G.new_game()
	G.clock_paused = true
	G.quests["Q06"] = {"state": "done", "step": 7}
	var reachable := true
	for date in range(2, 24):
		G.day = date
		G.daily = {}
		G._new_request()
		var request: Dictionary = G.request()
		if request.is_empty() or int(G.crop_def(str(request.item)).get("level", 1)) > G.level():
			reachable = false
	t.check("FUN_LOOP", "requests never require a crop locked above the player's level", reachable)
	G.daily["request"] = {"who": "tanaka", "item": "radish", "n": 2, "done": false, "reward": 110}
	G.day = 6
	G.advance_day()
	t.check("FUN_LOOP", "an unfinished street request survives sleeping without a penalty", str(G.request().get("who", "")) == "tanaka" and str(G.request().get("item", "")) == "radish" and int(G.request().get("n", 0)) == 2 and not G.request().get("done", true))
	G.daily["request"] = {"who": "tanaka", "item": "radish", "n": 2, "done": false, "reward": 110}
	main.ui.open_quests()
	await t.frames(3)
	var quest_text: String = _text(main.ui.modal_layer)
	t.check("FUN_LOOP", "J shows the street request before the player owns its materials", quest_text.contains("田中") and quest_text.contains("萝卜") and quest_text.contains("2"))
	main.ui.close_modal(false)
	if G.has_method("request_lines"):
		var notice: String = "\n".join(G.request_lines())
		t.check("FUN_LOOP", "the notice-board request explains the recipient and recoverable timing", notice.contains("田中") and notice.contains("萝卜") and notice.contains("改天"))
	else:
		t.check("FUN_LOOP", "the notice-board request explains the recipient and recoverable timing", false)
	var hearts_before: Dictionary = G.affinity.duplicate(true)
	var coins_before: int = G.coins
	G.day = 16
	G.quests["Q12"] = {"state": "active", "step": 1}
	G.quests["Q13"] = {"state": "active", "step": 1}
	main.story.lore._on_day(16)
	t.check("FUN_FACT", "town-completed preparations do not pay the player for work they did not do", G.coins == coins_before and G.affinity == hearts_before and G.qstate("Q12") == "done" and G.qstate("Q13") == "done")
	G.new_game()
	G.clock_paused = true
	G.day = 17
	G.minute = 19.0 * 60.0
	G.quests["Q05"] = {"state": "done", "step": 5}
	G.quests["Q14"] = {"state": "active", "step": 0}
	main.player.global_position = Vector3(-43, 0.1, -6)
	main.story.lore.checks()
	t.check("FUN_FACT", "standing at the bus stop does not count as attending the courtyard festival", not G.flags.get("summer_attended", false) and G.at_step("Q14", "go_fest"))
	main.player.global_position = Vector3(4, 0.1, 7)
	main.story.lore.checks()
	t.check("FUN_FACT", "entering the actual courtyard records participation", G.flags.get("summer_attended", false) and G.at_step("Q14", "bon_odori14"))
	G.new_game()
	G.clock_paused = true
	G.quests["Q06"] = {"state": "done", "step": 7}
	G.phase = "market"
	t.check("FUN_FACT", "owning a vegetable plot does not imply supplying Ren", not Dialogue.matches(_entry("ren_market"), {}))
	G.flags["bakery_supplies"] = 1
	t.check("FUN_FACT", "actual produce supply allows Ren to remember it", Dialogue.matches(_entry("ren_market"), {}))
	t.check("FUN_FACT", "a past supply does not imply today's menu uses the player's vegetables", not JSON.stringify(_entry("ren_market").lines).contains("今天"))
	var mio_history: String = JSON.stringify(_entry("mio_a2")) + JSON.stringify(_entry("ev_mio5"))
	t.check("FUN_FACT", "all audited Mio histories agree that she stayed in town", not mio_history.contains("东京上班") and not mio_history.contains("回来以后") and not mio_history.contains("又要离开"))
	t.check("FUN_FACT", "Haru treats a bowl of soup as food rather than a flower", not main.story.farm._loved("haru", "miso_soup").contains("插"))
	t.check("FUN_FACT", "a bread gift is not praised as a crop the player grew", not main.story.farm._loved("tanaka", "melon_pan").contains("种"))
	var invalid_periods: Array = []
	for entry: Dictionary in Dialogue.entries:
		for period in entry.get("when", {}).get("period", []):
			if not ["morning", "day", "evening", "dusk", "night"].has(period):
				invalid_periods.append(str(entry.id))
	t.check("FUN_FACT", "every authored period can actually be reached", invalid_periods.is_empty(), ", ".join(invalid_periods))
	G.new_game()
	G.clock_paused = true
	G.bag_cap = 0
	G.affinity.ren = 4
	G.flags["bakery_first_served"] = true
	await main.story.farm.daily_talk("ren")
	t.check("FUN_RECOVER", "a full bag keeps Ren's one-time sandwich invitation unclaimed", not G.flags.get("dlg_once_ev_ren4", false) and not G.has("veg_sandwich"))
	G.bag_cap = G.INV_SLOTS
	main.ui.auto_choices = [1]
	await main.story.farm.daily_talk("ren")
	t.check("FUN_RECOVER", "returning with bag space receives the promised sandwich once", G.flags.get("dlg_once_ev_ren4", false) and G.count("veg_sandwich") == 1)
	G.from_dict(original)
	main.ui.auto_choices.clear()
	main.ui.close_modal(false)
	main.world.set_region(G.player_region)
	main.update_npcs(true)
	main._sync_props()

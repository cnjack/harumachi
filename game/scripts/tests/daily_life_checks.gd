extends RefCounted
var t: Node
var G: Node
var main: Node


func _init(runner: Node) -> void:
	t = runner
	G = GameState
	main = t.main


func run() -> void:
	var names := [
		"an arrived player can choose a first meal without accepting the market",
		"deferring the meal does not accept a quest or consume the daily scene",
		"the meal invitation remains available on the following day",
		"one pantry parcel is real, protected and never duplicated",
		"the first meal recipe is available after receiving its parcel",
		"a full bag retains the parcel and recipe until food can be made",
		"the real kitchen consumes the parcel and produces exactly two portions",
		"a mini-game rice ball does not count as preparing the first meal",
		"the prepared first meal cannot be sold or given away before choosing its use",
		"eating transfers one real portion and teaches a reusable recipe",
		"the meal result cannot be completed or rewarded twice",
		"packing retains the two portions and releases their reservation",
		"Haru's tea is not offered before its relative introduction day",
		"a completed or major scene suppresses a new life scene that day",
		"deferring tea does not accept Q03 or change affection",
		"tea records the actual temperature and helping intent separately",
		"tea never claims the player planted a crop",
		"the paper-sign scene checks weekday instead of assuming the third day",
		"a bread tasting portion is protected and survives interruption",
		"tasting consumes the actual supplied portion exactly once",
		"helping a sign does not invent produce supply or a completed market",
		"the completed first market can provide the day's major experience",
		"SQLite restores recipe, portion and life-scene state",
		"old saves start their introductions now instead of backfilling three scenes",
		"sleep does not automatically play or complete a life scene",
		"the pantry, meal table and tea props have real interaction points",
		"visible meal feedback follows the actual choice",
		"ordinary eating consumes a real unreserved dish without a scene quota",
	]
	if not FileAccess.file_exists("res://scripts/story/daily_life.gd"):
		for name in names:
			t.check("DAILY_LIFE", name, false, "daily-life implementation not present")
		return
	var rules: Variant = load("res://scripts/story/daily_life.gd")
	var original: Dictionary = G.to_dict().duplicate(true)
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	G.quests["Q01"] = {"state": "available", "step": 0}
	t.check("DAILY_LIFE", names[0], rules.available("meal") and G.qstate("Q01") == "available")
	rules.defer("meal")
	t.check("DAILY_LIFE", names[1], not rules.available("meal") and not rules.quota_used() and G.qstate("Q01") == "available")
	G.day = 2
	t.check("DAILY_LIFE", names[2], rules.available("meal"))
	rules.claim_meal()
	var parcel: int = G.count("home_meal_parcel")
	rules.claim_meal()
	t.check("DAILY_LIFE", names[3], parcel == 1 and G.count("home_meal_parcel") == 1 and G.is_key_item("home_meal_parcel"))
	t.check("DAILY_LIFE", names[4], G.recipe_known("first_home_onigiri"))
	G.bag_cap = 0
	t.check("DAILY_LIFE", names[5], G.craft("first_home_onigiri") != "" and G.count("home_meal_parcel") == 1 and not rules.event("meal").get("cooked", false))
	G.bag_cap = G.INV_SLOTS
	var crafted: String = G.craft("first_home_onigiri")
	t.check("DAILY_LIFE", names[6], crafted == "" and G.count("onigiri") == 2 and G.count("home_meal_parcel") == 0 and rules.event("meal").get("cooked", false))
	var cooked_state: Dictionary = G.to_dict().duplicate(true)
	G.new_game()
	G.quests["Q00"] = {"state": "done", "step": 2}
	G.add_item("onigiri", 3, true)
	t.check("DAILY_LIFE", names[7], rules.finish_meal(0) != "" and not rules.done("meal") and G.count("onigiri") == 3)
	G.from_dict(cooked_state.duplicate(true))
	G.clock_paused = true
	t.check("DAILY_LIFE", names[8], G.sell_produce("onigiri", 2, 1.0) == 0 and G.give_gift("mio", "onigiri") == 0 and G.count("onigiri") == 2)
	var meal_result: String = rules.finish_meal(0)
	t.check("DAILY_LIFE", names[9], meal_result == "" and G.count("onigiri") == 1 and rules.done("meal") and G.recipe_known("plain_onigiri"))
	rules.finish_meal(0)
	t.check("DAILY_LIFE", names[10], G.count("onigiri") == 1)
	G.from_dict(cooked_state.duplicate(true))
	G.clock_paused = true
	rules.finish_meal(1)
	t.check("DAILY_LIFE", names[11], G.count("onigiri") == 2 and G.unreserved_count("onigiri") == 2 and int(rules.event("meal").get("choice", -1)) == 1)
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	t.check("DAILY_LIFE", names[12], not rules.available("tea"))
	G.day = 2
	rules.mark_major("Q05")
	t.check("DAILY_LIFE", names[13], not rules.available("tea"))
	G.day = 3
	var old_hearts: Dictionary = G.affinity.duplicate(true)
	rules.defer("tea")
	t.check("DAILY_LIFE", names[14], G.qstate("Q03") == "locked" and G.affinity == old_hearts and not rules.done("tea"))
	G.day = 4
	rules.begin("tea")
	rules.finish_tea(1, false)
	t.check("DAILY_LIFE", names[15], rules.done("tea") and int(rules.event("tea").get("temperature", -1)) == 1 and not rules.event("tea").get("help_intent", true))
	t.check("DAILY_LIFE", names[16], G.crop_stage == 0 and not G.flags.get("court_plot", false) and G.qstate("Q03") == "locked")
	G.day = 5
	t.check("DAILY_LIFE", names[17], rules.available("card") and not rules.is_weekend_stall())
	rules.begin("card")
	rules.claim_tasting()
	var tasting_state: Dictionary = G.to_dict().duplicate(true)
	rules.claim_tasting()
	t.check("DAILY_LIFE", names[18], G.count("life_bread_sample") == 1 and G.is_key_item("life_bread_sample") and not rules.done("card"))
	rules.finish_card(1)
	rules.finish_card(1)
	t.check("DAILY_LIFE", names[19], G.count("life_bread_sample") == 0 and rules.done("card") and rules.event("card").get("tasted", false))
	G.from_dict(tasting_state.duplicate(true))
	G.clock_paused = true
	rules.finish_card(0)
	t.check("DAILY_LIFE", names[20], rules.event("card").get("helped_sign", false) and not G.flags.get("bakery_first_served", false) and int(G.flags.get("bakery_supplies", 0)) == 0 and G.qstate("Q05") != "done")
	G.new_game()
	G.clock_paused = true
	G.day = 3
	G.quests["Q05"] = {"state": "done", "step": 5}
	G.flags["ended"] = true
	rules.record_market()
	t.check("DAILY_LIFE", names[21], rules.done("card") and rules.quota_used() and rules.event("card").get("main_market", false))
	G.from_dict(cooked_state.duplicate(true))
	G.clock_paused = true
	G.save_game()
	G.flags.clear()
	G.inventory.clear()
	G.load_game()
	t.check("DAILY_LIFE", names[22], rules.event("meal").get("cooked", false) and G.count("onigiri") == 2 and G.recipe_known("first_home_onigiri"))
	var legacy: Dictionary = G.to_dict().duplicate(true)
	legacy.flags.erase("daily_life")
	legacy.day = 25
	G.from_dict(legacy.duplicate(true))
	G.clock_paused = true
	t.check("DAILY_LIFE", names[23], int(rules.state().introduced_day) == 25 and not rules.available("tea") and not rules.available("card"))
	G.advance_day()
	t.check("DAILY_LIFE", names[24], not rules.done("tea") and not rules.done("card"))
	t.check("DAILY_LIFE", names[25], t.point("life_pantry") != null and t.point("life_meal_table") != null and t.point("life_tea") != null)
	G.from_dict(cooked_state.duplicate(true))
	G.clock_paused = true
	rules.finish_meal(0)
	main.story.daily.view.sync_state()
	t.check("DAILY_LIFE", names[26], main.story.daily.view.meal_root.get_meta("meal_choice", -1) == 0 and main.story.daily.view.meal_root.get_meta("meal_cooked", false))
	var quota: int = int(rules.state().last_major_day)
	var ate: String = rules.eat_food("onigiri")
	t.check("DAILY_LIFE", names[27], ate == "" and G.count("onigiri") == 0 and int(rules.state().last_major_day) == quota)
	# Recovery and actual old story entry points must respect the same rules.
	G.from_dict(cooked_state.duplicate(true))
	G.clock_paused = true
	main.ui.auto_choices = [0]
	var offered: bool = await main.story._offer_onigiri("mio")
	t.check("DAILY_LIFE", "the story's original onigiri gift cannot consume the first-meal portions", not offered and G.count("onigiri") == 2)
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	G.day = 2
	rules.begin("tea")
	G.day = 3
	rules.begin("tea")
	rules.finish_tea(0, false)
	t.check("DAILY_LIFE", "resuming tea on a later day occupies that day's story quota", rules.quota_used() and not rules.available("card"))
	G.day = 4
	rules.begin("card")
	rules.claim_tasting()
	G.quests["Q05"] = {"state": "done", "step": 5}
	G.flags["ended"] = true
	rules.record_market()
	t.check("DAILY_LIFE", "a main-market replacement returns an interrupted tasting portion", not G.has("life_bread_sample") and rules.done("card"))
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	G.quests["Q01"] = {"state": "available", "step": 0}
	await main.enter_room()
	await t.frames(8)
	DailyLife.track("meal")
	var prior_position: Vector3 = main.player.global_position
	main.player.global_position = HouseBuilder.ORIGIN + Vector3(-4.6, .05, -.6)
	await t.frames(3)
	var meal_marker: Variant = main.story.marker_target()
	t.check("DAILY_LIFE", "the first meal marker points to the bedroom exit instead of through the south wall", meal_marker != null and Vector2(meal_marker.x - HouseBuilder.ORIGIN.x + 1.5, meal_marker.z - HouseBuilder.ORIGIN.z + 1.2).length() < .05)
	var route_probe := CapsuleShape3D.new()
	route_probe.radius = .4
	route_probe.height = 1.6
	var route_query := PhysicsShapeQueryParameters3D.new()
	route_query.shape = route_probe
	route_query.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED | WorldBuilder.L_BLOCK
	var route_points: Array[Vector3] = [Vector3(-4.6,0,-.6), Vector3(-2.1,0,-1.2), Vector3(-.6,0,-1.2), Vector3(.9,0,-.6), Vector3(1.9,0,.15), Vector3(1.9,0,2.6), Vector3(-.6,0,2.6), Vector3(-1.3,0,1.95), Vector3(-2.3,0,1.95)]
	var blocked_parts: Array[String] = []
	for segment: int in range(route_points.size() - 1):
		for sample: int in range(21):
			route_query.transform = Transform3D(Basis.IDENTITY, HouseBuilder.ORIGIN + route_points[segment].lerp(route_points[segment + 1], sample / 20.0) + Vector3.UP * .82)
			var obstacles: Array[Dictionary] = main.player.get_world_3d().direct_space_state.intersect_shape(route_query, 1)
			if not obstacles.is_empty():
				blocked_parts.append("segment %d: %s" % [segment, obstacles[0].collider.get_path()])
				break
	t.check("DAILY_LIFE", "the wake-to-pantry route has continuous 0.8 metre full-body clearance before tidying", blocked_parts.is_empty(), str(blocked_parts))
	main.player.global_position = HouseBuilder.ORIGIN + Vector3(3.5, .05, -2)
	await t.frames(3)
	var east_marker: Variant = main.story.marker_target()
	t.check("DAILY_LIFE", "an eastern living-room player is guided to the near door rather than across the kotatsu", east_marker != null and absf(east_marker.x - HouseBuilder.ORIGIN.x - 5) < .05)
	main.player.global_position = HouseBuilder.ORIGIN + Vector3(4.9, -.4, -7.55)
	await t.frames(3)
	var yard_marker: Variant = main.story.marker_target()
	t.check("DAILY_LIFE", "returning from the yard first marks the actual railing opening", yard_marker != null and absf(yard_marker.x - HouseBuilder.ORIGIN.x - 1.5) < .05 and yard_marker.z - HouseBuilder.ORIGIN.z < -4.72)
	await main.exit_room()
	var outside_hint: String = main.ui.obj_text.text
	await main.enter_room()
	t.check("DAILY_LIFE", "leaving and re-entering the house refreshes the meal hint immediately", outside_hint == rules.hint("meal") and main.ui.obj_text.text == "沿走廊向左，穿过暖帘就是厨房。")
	main.player.global_position = prior_position
	await t.frames(3)
	await t.use("life_pantry", [1])
	t.check("DAILY_LIFE", "declining through the actual pantry point gives no parcel or scene", not G.has("home_meal_parcel") and not rules.quota_used())
	await t.use("life_pantry", [0, 0])
	t.check("DAILY_LIFE", "the actual pantry point supports explicit same-day reconsideration", G.has("home_meal_parcel") and G.recipe_known("first_home_onigiri"))
	await t.use("house_stove", [{"craft": {"first_home_onigiri": 1}}])
	t.check("DAILY_LIFE", "the actual stove panel crafts two protected portions", G.count("onigiri") == 2 and G.reserved_count("onigiri") == 2)
	await t.use("life_meal_table", [1])
	t.check("DAILY_LIFE", "the actual table packing choice retains food and unlocks the recipe", rules.done("meal") and G.count("onigiri") == 2 and G.recipe_known("plain_onigiri"))
	DailyLife.track("tea")
	main.ui.refresh_hud()
	t.check("DAILY_LIFE", "HUD uses the explicitly tracked life event", main.ui.obj_title.text == rules.title("tea"))
	G.start_quest("Q01")
	t.check("DAILY_LIFE", "accepting a main quest restores its tracking", str(rules.state().tracked) == "")
	await main.exit_room()
	G.day = 2
	G.minute = 12.0 * 60
	main.update_npcs(true)
	await t.frames(8)
	await t.use("life_tea", [2])
	t.check("DAILY_LIFE", "the actual tea refusal does not start Q03 or consume the scene", not rules.done("tea") and G.qstate("Q03") == "locked" and not rules.quota_used())
	await t.use("life_tea", [0, 1, 1])
	t.check("DAILY_LIFE", "the actual tea rest choice records a drink without planting or accepting Q03", rules.done("tea") and G.qstate("Q03") == "locked" and G.crop_stage == 0 and rules.event("tea").get("temperature", -1) == 1)
	G.day = 3
	G.minute = 12.0 * 60
	main.update_npcs(true)
	await t.frames(8)
	await t.use("life_bakery_card", [0])
	t.check("DAILY_LIFE", "the actual sign interaction records helping without fictional market supply", rules.done("card") and rules.event("card").get("helped_sign", false) and G.qstate("Q05") != "done")
	# Eating is independent of rigging; sip keeps the existing rig regression.
	for mode: String in ["eat", "sip"]:
		var action := LivingAction.new()
		main.add_child(action)
		action.surface_at = main.story.daily.view.meal_root.global_position
		action.setup(main.player, mode)
		action.duration = 100.0
		action.clock = 70.0 if mode == "eat" else 50.0
		await t.frames(8)
		if mode == "eat":
			t.check("DAILY_LIFE", "eating leaves an empty plate without a rig, held prop or floating completion text", action.skeleton == null and action.pose == null and action.hand < 0 and not action.meal_food.visible and action.prop.get_node_or_null("Plate") != null and action.prop.find_children("*", "Label3D", true, false).is_empty())
		else:
			t.check("DAILY_LIFE", "the current character rig renders a hand-held sip near the mouth", action.hand >= 0 and action.prop.global_position.distance_to(action.pose.goal_world) < .12)
		action.queue_free()
		await t.frames(3)
	G.new_game()
	G.clock_paused = true
	t.check("DAILY_LIFE", "closed life events expose no invisible tea/sign prompt", main.story.prompt_for("life_tea") == "" and main.story.prompt_for("life_bakery_card") == "")
	G.quests["Q00"] = {"state": "done", "step": 2}
	G.day = 2
	main.npcs.haru.hide()
	var hearts: Dictionary = G.affinity.duplicate(true)
	await t.use("life_tea", [0, 0])
	t.check("DAILY_LIFE", "an absent Haru gives no drink or helping progress", not rules.done("tea") and not rules.quota_used() and G.affinity == hearts)
	main.npcs.haru.show()
	G.day = 3
	main.npcs.ren.hide()
	await t.use("life_bakery_card", [1])
	t.check("DAILY_LIFE", "an absent Ren gives no bread tasting or scene", not G.has("life_bread_sample") and not rules.done("card") and not rules.quota_used())
	main.npcs.ren.show()
	main.ui.auto_choices = [1]
	await main.story.daily.arrival_invitation()
	main.ui.dialogue_end()
	G.flags.clear()
	G.load_game()
	t.check("DAILY_LIFE", "the arrival choice is checkpointed immediately", int(rules.event("meal").deferred_day) == G.day)
	var tray: Node3D = main.story.daily.view.tea_root.get_node("W12_cedar_tray")
	var bench: Node3D = main.world.get_node("P08")
	t.check("DAILY_LIFE", "the tea tray is supported by the actual rendered workbench top", PropAudit.mount_supported(tray, bench))
	tray.position.y += .20
	t.check("DAILY_LIFE", "declaring support does not excuse a floating tray", not PropAudit.mount_supported(tray, bench))
	tray.position.y -= .20
	G.from_dict(original.duplicate(true))
	G.clock_paused = true
	main.ui.auto_choices.clear()
	main.story.daily.view.sync_state()
	main.world.set_region(G.player_region)
	main.update_npcs(true)

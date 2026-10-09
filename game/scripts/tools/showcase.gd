extends "res://scripts/tools/autoplay.gd"
## Festival showcase for the v0.5 video: jumps the calendar to each festival (a fresh game with the
## first market already behind it) and plays it through the same interactions a player uses.
##   godot --path game res://scenes/main.tscn -- --showcase [--no-music] [--shots-dir=<dir>]


func _setup() -> void:
	for q in ["Q00", "Q01", "Q02", "Q03", "Q04", "Q05", "Q06", "Q10", "Q11", "Q12", "Q13"]:
		G.quests[q] = {"state": "done", "step": 99}
	for c in ["col_photo2011", "col_letter", "col_notebook", "col_blueprint"]:
		G.collection[c] = 5
	Progress.quiet = true
	G.flags["met_aoi"] = true
	G.key_items["hoe"] = 1
	G.key_items["farm_can"] = 1
	G.farm_xp = 360
	G.coins = 900
	G.open_plots(["farm0", "farm1", "farm2", "farm3", "yard0", "yard1", "yard2", "yard3"], true)
	for p in ["farm0", "farm1", "farm2", "farm3"]:
		G.plots[p].crop = ["sunflower", "corn", "tomato", "eggplant"][int(p.substr(4))]
		G.plots[p].days = 6
	G.plots_changed.emit()
	for iid in ["salad", "korokke", "focaccia", "corn_soup"]:
		G.add_item(iid, 3, true)
	G.add_item("sunflower", 1, true)
	G.add_item("toro", 1, true)
	G.state_changed.emit()


func jump(d: int, h: float) -> void:
	await main.ui.fade_out(0.6)
	G.day = d
	G.weather = G.weather_for(d)
	G.minute = h * 60.0
	G._last_min = -1
	G.daily = {}
	main.world.sync_festivals()
	main._last_fest = ""
	main.world.update_time(G.minute, G.weather, true)
	main.update_npcs(true)
	await main.ui.fade_in(0.6)
	G._tick_minute()


func to_town(p: Vector2, yaw: float) -> void:
	if main.world.region == "farm":
		await main.leave_farm()
	main.player.global_position = Vector3(p.x, 0.1, p.y)
	main.rig.yaw = yaw
	main.rig.snap()


func to_farm(p: Vector2, yaw: float) -> void:
	if main.world.region != "farm":
		await main.go_farm()
	main.player.global_position = FarmBuilder.ORIGIN + Vector3(p.x, 0.1, p.y)
	main.rig.yaw = yaw
	main.rig.snap()


## Print a mark (and take a shot) once `cond` holds, without blocking the caller. The reel cuts by these.
func mark_when(cond: Callable, delay: float, name: String) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > 60000:
			return
		await get_tree().process_frame
	await wait(delay)
	await shot(name)


func _want(part: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			return a.substr(7).split(",").has(part)
	return true


func play() -> void:
	_setup()
	await get_tree().process_frame
	Progress.check()           # what the setup already earned unlocks silently
	Progress.quiet = false
	if _want("contest"):
		# 品评会 — a Sunday morning in the courtyard
		await jump(11, 10.6)
		await to_town(Vector2(-3.0, 3.0), 200.0)
		await look(200.0, 24.0, 8.0, 0.01)
		await wait(1.5)
		await shot("contest_arrive")
		mark_when(func(): return main.ui.modal == "notice", 0.6, "contest_board")
		await use("contest_table", [0], "contest_stand")
		await shot("contest_result")
		await wait(1.0)
	if _want("natsu"):
		# 夏祭 — the yagura, the stalls and the bon-odori
		await jump(17, 19.2)
		main.story.lore._on_day(17)
		G.phase = "market"
		G.phase_changed.emit("market")
		await to_town(Vector2(-2.0, 9.5), 180.0)
		await look(180.0, 22.0, 11.0, 0.01)
		await wait(2.0)
		await shot("natsu_arrive")
		await look(140.0, 18.0, 9.0, 3.0)
		await shot("natsu_stalls")
		await use("stall", [mini(main.story.farm._market_goods().size(), 4)], "stall")
		await shot("natsu_stall_sell")
		G.skip_to(20.05 * 60.0)
		mark_when(func(): return main.dancing, 1.2, "bon_odori_dance")
		await use("yagura", [], "yagura_stand")
		await shot("bon_odori_done")
		# v0.6: the promise at the goldfish stall (Q14), with the photo the game takes
		main.story.lore.checks()
		G.collection.erase("col_photo_new")
		mark_when(func(): return Progress.found("col_photo_new"), 0.2, "natsu_photo")
		await use("mio", [0])
		await shot("natsu_promise")
		G.phase = "prep"
	if _want("hanabi"):
		# 花火 — the riverbank at the allotment
		await jump(24, 19.55)
		await to_farm(Vector2(6.0, 10.4), 180.0)
		await look(170.0, 6.0, 8.0, 0.01)
		await wait(2.0)
		await shot("hanabi_arrive")
		mark_when(func(): return main.npcs.values().any(func(n): return n.fest_key == "hanabi:watch"), 1.5, "hanabi_watch")
		await use("farm_bench", [0])
		await shot("hanabi_done")
	if _want("obon"):
		# 灯笼流 — Obon's last evening
		await jump(43, 19.1)
		await to_farm(Vector2(0.0, 11.2), 180.0)
		main.world.farm.fx.lanterns_on = true
		for i in 6:
			main.world.farm.fx.float_lantern(false, Vector3(-22.0 + i * 5.0, 0, 15.6 + (i % 3) * 1.1))
		await look(150.0, 14.0, 8.0, 0.01)
		await wait(2.0)
		var bt := point("bridge_toro")
		main.player.global_position = FarmBuilder.ORIGIN + Vector3(0, 0.9, 14.3)
		main.player.face_towards(bt.global_position)
		await wait(0.8)
		main.ui.auto_choices = []
		mark_when(func(): return main.story.fest.done("toro"), 0.3, "obon_float")
		await main.story.interact(bt)
		await look(165.0, 30.0, 9.5, 3.0)
		await wait(3.0)
		await shot("obon_lanterns")
		await wait(1.0)
	if _want("tsukimi"):
		# 月见 — dango on the offering stand under the full moon
		await jump(76, 19.6)
		G.add_item("dango", 1, true)
		await to_town(Vector2(-1.0, 3.0), 193.0)
		await look(193.0, 5.0, 8.0, 0.01)
		await wait(2.0)
		await shot("tsukimi_arrive")
		mark_when(func(): return main.story.fest.done("tsukimi"), 0.2, "tsukimi_offer")
		await use("offer_stand", [])
		await look(188.0, 4.0, 7.5, 3.0)
		await wait(1.5)
		await shot("tsukimi_offering")

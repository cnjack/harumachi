extends "res://scripts/tools/daily_life_demo.gd"
## Real keyboard/mouse rendering checks. Placement and calendar are test fixtures.
func _ready() -> void:
	main = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): folder = arg.substr(11)
	if folder == "": folder = "/tmp/harumachi-summer-demo"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(25)
	GameState.new_game()
	GameState.clock_paused = true
	NPC.roam_enabled = false
	Progress.quiet = true
	Audio.game_on = true
	main.ui.instant = false
	await tap(KEY_K)
	await frames(8)
	await shot("01_default_arrival_journal")
	await tap(KEY_ESCAPE)
	await use_point("mailbox", [])
	await use_point("home_door", [0])
	await use_point("life_pantry", [0])
	await use_point("house_rice", [0])
	await frames(12)
	await tap(KEY_ESCAPE)
	await continue_dialogue([])
	check("cancelled short shape keeps parcel", GameState.count("home_meal_parcel") == 1 and GameState.count("onigiri") == 0)
	await use_point("house_stove", [])
	await frames(10)
	await shot("02_stove_offers_both_methods")
	await press_button("亲手捏形")
	await wait_for_play()
	await shot("02_short_shape_single_start")
	await tap(KEY_A)
	await tap(KEY_D)
	await tap(KEY_A)
	await frames(10)
	await shot("03_shape_result_no_free_reward")
	await press_button("回到厨房")
	await continue_dialogue([])
	var cook_deadline := Time.get_ticks_msec() + 5000
	while GameState.count("onigiri") < 2 and Time.get_ticks_msec() < cook_deadline: await frames(2)
	check("short shape makes exactly two portions", GameState.count("onigiri") == 2 and not GameState.has("home_meal_parcel") and int(GameState.mg_record("onigiri").plays) == 0)
	await use_point("life_meal_table", [1])
	await tap(KEY_K)
	await frames(8)
	await shot("04_meal_in_journal")
	await tap(KEY_ESCAPE)
	await main.exit_room()
	await use_point("zelkova", [])
	check("tree remembers only its fragment", StoryKnowledge.presented("tree") and not StoryKnowledge.presented("promise"))
	await tap(KEY_K)
	await frames(8)
	await press_button("回想 · ")
	await shot("05_tree_memory_replay")
	await tap(KEY_ESCAPE)
	GameState.day = 17
	GameState.minute = 20 * 60
	GameState.quests["Q14"] = {"state": "active", "step": 2}
	main.world.set_region("town")
	main.update_npcs(true)
	await use_neighbour("mio", [3])
	check("declining shared activity leaves quest pending", GameState.at_step("Q14", "goldfish_mio") and not Progress.found("col_photo_new"))
	await use_neighbour("mio", [1, 0, 0])
	await shot("06_after_shared_photo_control")
	check("light participation stores actual photo", GameState.qstate("Q14") == "done" and GameState.flags.get("photo_rendered", false) and FileAccess.file_exists(GameState.photo_path()) and int(GameState.mg_record("goldfish").plays) == 0)
	main.ui.open_book_col()
	await frames(8)
	await shot("07_photo_collection")
	await tap(KEY_ESCAPE)
	main.story._ending.call_deferred()
	var deadline := Time.get_ticks_msec() + 5000
	while main.ui.modal != "chapter_summary" and Time.get_ticks_msec() < deadline: await frames(2)
	await frames(10)
	await shot("08_weekend_is_chapter_summary")
	check("weekend is not summer ending", main.ui.modal == "chapter_summary" and not MainlineProgress.summer_complete())
	await press_button("继续夏季生活")
	await frames(8)
	check("HUD and controls restored", main.ui.modal == "" and not GameState.input_locked() and main.ui.hud.visible and not main.story.busy)
	var file := FileAccess.open(folder.path_join("native-demo.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "passed": failures.is_empty(), "failures": failures, "shots": shots, "photo": GameState.photo_path(), "input": "E / numeric choices / A D A / K / Escape / mouse buttons", "scope": "fixture-positioned source input and rendering; not natural human timing", "facts": GameState.to_dict()}, "  "))
	Audio.silence()
	get_tree().quit(0 if failures.is_empty() else 1)

func wait_for_play() -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while main.ui.active_mg != null and main.ui.active_mg.state != MiniGame.State.PLAY and Time.get_ticks_msec() < deadline: await frames(2)
	check("short shape started once", main.ui.active_mg != null and main.ui.active_mg.state == MiniGame.State.PLAY)

func use_neighbour(id: String, picks: Array) -> void:
	# Stand on the outer side of the festival stage, rather than on its interaction centre.
	var npc: NPC = main.npcs[id]
	npc.place(Vector3(4.8, 0, 15.5), 180)
	npc.home = false
	npc.visible = true
	await frames(3)
	await use_point(id, picks)

func press_button(prefix: String) -> void:
	for node in main.ui.root.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and str(node.text).begins_with(prefix):
			await click(node.get_global_rect().get_center())
			await frames(12)
			return
	failures.append("button missing: " + prefix)

func continue_dialogue(picks: Array) -> void:
	var choices: Array = picks.duplicate()
	var deadline := Time.get_ticks_msec() + 35000
	while main.story.busy and Time.get_ticks_msec() < deadline:
		if main.ui.modal == "minigame":
			await frames(3)
			continue
		if main.ui.modal != "": break
		if main.ui.dlg_choices.visible:
			await frames(5)
			var pick: int = int(choices.pop_front()) if not choices.is_empty() else 0
			await tap(KEY_1 + pick)
		elif main.ui.dlg.visible:
			await frames(14)
			await tap(KEY_E)
		await frames(3)

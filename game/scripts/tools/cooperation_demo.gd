extends "res://scripts/tools/daily_life_demo.gd"
## Real input smoke for one complete cooperation; positioning is a declared fixture.
func _ready() -> void:
	main = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): folder = arg.substr(11)
	if folder == "": folder = "/tmp/harumachi-cooperation-demo"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(25)
	GameState.new_game()
	GameState.clock_paused = true
	NPC.roam_enabled = false
	Progress.quiet = true
	main.ui.instant = false
	main.ui.auto = false
	GameState.quests["Q00"] = {"state": "done", "step": 2}
	GameState.quests["Q01"] = {"state": "done", "step": 2}
	var host_path: bool = OS.get_cmdline_user_args().has("--cooperation-host")
	if main.in_room: await main.exit_room()
	await main.enter_interior("bakery")
	await use_point("opening_paper", [1 if host_path else 0, 1 if host_path else 0, 1, 0])
	check("role starts without farming or a previous market", SummerProjects.phase() == ("feedback" if host_path else "trial") and GameState.qstate("Q03") == "locked" and GameState.qstate("Q05") == "locked")
	await shot("01_recipe_and_source_selected")
	if not host_path:
		await use_point("bakery_oven", [])
		await frames(8)
		await shot("02_trial_recipe_three_small_portions")
		var craft: Button = null
		for button in main.ui.root.find_children("*", "Button", true, false):
			if button.get_meta("recipe_id", "") == SummerProjects.TRIAL_RECIPE and button.is_visible_in_tree() and not button.disabled: craft = button; break
		if craft == null: failures.append("cooperation oven recipe missing")
		else: await click(craft.get_global_rect().get_center())
		await frames(10)
		await tap(KEY_ESCAPE)
		await frames(8)
	check("one real recipe creates one identified batch with truthful maker", SummerProjects.phase() == "feedback" and SummerProjects.current_batch().maker == ("ren" if host_path else "player"))
	await main.exit_interior()
	await main.enter_room()
	await use_point("life_meal_table", [0])
	check("the table really offers the honest remaining small portion", int(SummerProjects.current_batch().self_eaten) == 1)
	await shot("03_small_portion_own_meal")
	await main.exit_room()
	await use_point("haru", [0])
	await use_point("mio", [0])
	check("two real different neighbours consumed the protected portions", SummerProjects.phase() == "decision" and SummerProjects.current_batch().tasters.size() == 2)
	await main.enter_interior("bakery")
	await use_point("opening_paper", [0, 1 if host_path else 0, 1 if host_path else 0])
	check("a good initial menu is retained without a forced second bake", SummerProjects.phase() == "site" and SummerProjects.opening().batches.size() == 1)
	await shot("04_final_small_paper_plan")
	await main.exit_interior()
	# Furniture placement is a fixture here; the subsequent trial follows real collision and walking.
	GameState.add_placement("picnic_table", -3.5, 9.5, 0)
	GameState.add_placement("bench", -3.5, 13.0, 0)
	await frames(8)
	main.npcs.haru.place(Vector3(10.5, 0, 12.5), -90)
	main.npcs.haru.home = false
	main.npcs.haru.visible = true
	await use_point("opening_site", [0, 1])
	check("preparation unlocks the nonfarming mainline before making the final basket", SummerProjects.phase() == "ready" and GameState.qstate("Q05") == "available" and SummerProjects.opening().service.is_empty())
	await use_point("mio", [])
	await use_point("ren", [0])
	main.npcs.haru.place(Vector3(10.5, 0, 12.5), -90)
	await use_point("haru", [0])
	GameState.day = GameState.next_market_day()
	GameState.minute = GameState.MARKET_OPEN + 10
	await use_point("mio", [0])
	await use_point("opening_site", [1])
	check("actual collision-aware trial applies a finite basket", SummerProjects.phase() == "applied" and SummerProjects.opening().layout_trial.get("who", "") == "haru")
	await shot("05_real_route_and_paper_servings")
	await use_point("opening_site", [0])
	check("a guest takes an actual field serving", int(SummerProjects.opening().service.get("remaining", -1)) == 2)
	await use_point("opening_site", ["把实际剩下的份量打包"])
	check("actual leftovers are packed and disappear from the counter", GameState.count("opening_leftover") == 2 and int(SummerProjects.opening().service.get("remaining", -1)) == 0)
	await use_point("opening_site", ["这次先收好合作纸签"])
	for who: String in ["mio", "ren", "haru"]: await use_point(who, [])
	check("nonfarming cooperation completes the first market", GameState.qstate("Q05") == "done" and GameState.qstate("Q03") == "locked")
	var summary_deadline := Time.get_ticks_msec() + 8000
	while main.ui.modal != "chapter_summary" and Time.get_ticks_msec() < summary_deadline: await frames(2)
	if main.ui.modal == "chapter_summary": await press_named_button("继续夏季生活")
	await tap(KEY_K)
	await frames(8)
	await shot("06_saved_cooperation_note")
	await tap(KEY_ESCAPE)
	check("control is restored after trial and service", not main.story.busy and not GameState.input_locked() and main.ui.modal == "")
	GameState.save_game()
	var actual: Dictionary = SummerProjects.state().duplicate(true)
	GameState.flags.clear()
	GameState.load_game()
	if SummerProjects.state() != actual:
		for key: String in actual.opening:
			if SummerProjects.opening().get(key) != actual.opening[key]:
				print("RESTORE_DIFF ", key, " expected=", JSON.stringify(actual.opening[key]), " loaded=", JSON.stringify(SummerProjects.opening().get(key)))
	check("SQLite restores the complete cooperation facts", SummerProjects.state() == actual)
	var file := FileAccess.open(folder.path_join("native-demo.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "failures": failures, "shots": shots,
		"input": "E, numeric choices, mouse oven recipe, K, Escape", "scope": "fixture positioning and furniture; real input, actor walk and collision; not natural human duration", "facts": actual, "restored": SummerProjects.state().duplicate(true)}, "  "))
	Audio.silence()
	get_tree().quit(0 if failures.is_empty() else 1)

func press_named_button(label: String) -> void:
	for button in main.ui.root.find_children("*", "Button", true, false):
		if button.text == label and button.is_visible_in_tree():
			await click(button.get_global_rect().get_center())
			await frames(10)
			return
	failures.append("missing button " + label)

extends "res://scripts/tools/daily_life_demo.gd"
## Food preparation/standing are fixtures; actual E choices, presentation and consumption are tested.
func _ready() -> void:
	main = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): folder = arg.substr(11)
	if folder == "": folder = "/tmp/harumachi-abstract-meal"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(25)
	GameState.new_game()
	GameState.clock_paused = true
	NPC.roam_enabled = false
	Progress.quiet = true
	main.ui.instant = false
	main.ui.auto = false
	GameState.quests.Q00 = {"state": "done", "step": 2}
	await main.enter_room()
	DailyLife.claim_meal()
	GameState.craft("first_home_onigiri")
	check("fixture prepares exactly the existing two-portion meal", GameState.count("onigiri") == 2)
	await use_point("life_meal_table", [0])
	check("first meal consumes one and keeps the other", DailyLife.done("meal") and GameState.count("onigiri") == 1)
	for label: String in ["action_eat", "action_eat_after"]:
		DirAccess.copy_absolute(folder.path_join(label + ".png"), folder.path_join("first_" + label + ".png"))
	GameState.add_item("melon_pan", 1, true)
	seen_actions.clear()
	await use_point("life_meal_table", [1])
	check("ordinary food uses the same cut and consumes only its chosen portion", GameState.count("melon_pan") == 0 and GameState.count("onigiri") == 1)
	check("both eating stages were actually rendered", seen_actions.has("eat") and seen_actions.has("eat_empty"))
	for iid: String in ["veg_sandwich","focaccia","pickles"]:
		GameState.add_item(iid,1,true)
		seen_actions.clear()
		await use_point("life_meal_table",[1])
		check("3D portion %s renders and consumes only its selected food"%iid,GameState.count(iid)==0 and GameState.count("onigiri")==1 and seen_actions.has("eat") and seen_actions.has("eat_empty"))
		for label: String in ["action_eat","action_eat_after"]:
			DirAccess.copy_absolute(folder.path_join(label+".png"),folder.path_join(iid+"_"+label+".png"))
	check("dialogue, camera and control return", not main.story.busy and not GameState.input_locked() and main.ui.modal == "" and get_viewport().get_camera_3d() == main.rig.cam)
	var file := FileAccess.open(folder.path_join("native-demo.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "failures": failures, "shots": shots,
		"scope": "fixture preparation/standing; real E choices, table before/after, inventory and camera restoration",
		"food_left": {"onigiri": GameState.count("onigiri"), "melon_pan": GameState.count("melon_pan")}}, "  "))
	Audio.silence()
	get_tree().quit(0 if failures.is_empty() else 1)

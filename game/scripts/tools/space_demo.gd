extends "res://scripts/tools/daily_life_demo.gd"
## Prior chapters/date and standing are fixtures; all project choices and walks use actual input.
func _ready() -> void:
	main = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): folder = arg.substr(11)
	if folder == "": folder = "/tmp/harumachi-space-demo"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(25)
	GameState.new_game()
	GameState.clock_paused = true
	NPC.roam_enabled = false
	Progress.quiet = true
	main.ui.instant = false
	main.ui.auto = false
	GameState.quests.Q00 = {"state": "done", "step": 2}
	GameState.quests.Q11 = {"state": "done", "step": 3}
	GameState.quests.Q13 = {"state": "active", "step": 1}
	GameState.minute = 10 * 60
	await main.go_farm()
	await use_point("tanaka", [1, 0])
	check("the daytime story entry starts the actual project", GameState.at_step("Q13", "carry_wood") and SummerSpace.state().phase == "arranging")
	await main.leave_farm()
	await use_point("space_plan", [1, 0, 0, 0])
	check("the preview adopts real eastern furniture once", SummerSpace.state().scheme == "east" and GameState.placements.size() == 2)
	await shot("01_eastern_layout_and_occupancy")
	for who: String in ["mio", "haru", "ren"]: await use_point(who, [0])
	check("three actual conversations invite the participants", SummerSpace.state().invited.size() == 3)
	await use_point("space_plan", [4, 1])
	check("three real walks and the viewing check were committed", SummerSpace.state().trials.size() == 3)
	await shot("02_after_three_actual_trials")
	await use_point("space_plan", [5])
	check("a good first plan can be retained", SummerSpace.ready())
	GameState.save_game()
	var retained: Dictionary = SummerSpace.state().duplicate(true)
	GameState.flags.clear()
	GameState.load_game()
	check("SQLite retains the same plan and furniture identities", JSON.stringify(SummerSpace.state()) == JSON.stringify(retained))
	GameState.add_item("flower_pot",1,true);GameState.add_placement("flower_pot",8,4,0)
	await frames(4)
	await use_point("space_plan",[4])
	check("a remote flower leaves the original three walks intact",SummerSpace.ready() and JSON.stringify(SummerSpace.state().trials)==JSON.stringify(retained.trials))
	var before_partial: Dictionary=SummerSpace.state().trials.duplicate(true)
	var chosen_table: Dictionary=SummerSpace.furniture("picnic_table").duplicate(true)
	PlacementSystem.project_context="space"
	GameState.remove_placement(int(chosen_table.uid))
	var moved_table: int=GameState.add_placement("picnic_table",float(chosen_table.x),float(chosen_table.z)+1,int(chosen_table.rot))
	PlacementSystem.project_context=""
	SummerSpace.state().table_uid=moved_table
	await frames(4)
	check("the changed serving table asks only Ren to try again",SummerSpace.trial_current("mio") and SummerSpace.trial_current("haru") and not SummerSpace.trial_current("ren"))
	await use_point("space_plan",[4,1])
	check("the partial actual walk retains Mio and Haru and restores Ren",SummerSpace.trial_current("ren") and JSON.stringify(SummerSpace.state().trials.mio)==JSON.stringify(before_partial.mio) and JSON.stringify(SummerSpace.state().trials.haru)==JSON.stringify(before_partial.haru))
	await use_point("space_plan",[5])
	await shot("02b_partial_serving_change")
	GameState.day = 17
	GameState.minute = 19 * 60
	main.world.sync_festivals()
	main.story.space.view.sync_state()
	await use_point("space_plan", [6, 1])
	check("the same layout has three separate real festival applications", SummerSpace.state().application.get("context", "") == "festival" and SummerSpace.state().application.get("people", {}).size() == 3)
	await shot("03_same_plan_at_actual_festival")
	check("control and camera return", not main.story.busy and not GameState.input_locked() and main.ui.modal == "" and get_viewport().get_camera_3d() == main.rig.cam)
	var file := FileAccess.open(folder.path_join("native-demo.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "failures": failures, "shots": shots,
		"facts": SummerSpace.state().duplicate(true), "scope": "fixture prior chapters/date/standing; actual E choices, furniture, invited cast, collision checked walking, observation and SQLite"}, "  "))
	Audio.silence()
	get_tree().quit(0 if failures.is_empty() else 1)

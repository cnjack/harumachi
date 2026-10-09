extends "res://scripts/tools/daily_life_demo.gd"
## Native keyboard assembly, cancellation and scene reuse; dates and prior chapter are fixtures.
func _ready() -> void:
	main = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): folder = arg.substr(11)
	if folder == "": folder = "/tmp/harumachi-workshop-demo"
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
	GameState.quests.Q12 = {"state": "available", "step": 0}
	await use_point("center_door", [])
	await shot("01_actual_workroom_entry")
	await use_point("workroom_table", [0, 1, 1])
	await frames(10)
	await shot("02_unfinished_lantern_and_controls")
	await tap(KEY_SPACE)
	check("misaligned native fit preserves materials", int(WorkshopProject.state().joints) == 0 and GameState.count("washi") == 1)
	for index in 4: await tap(KEY_A)
	await tap(KEY_SPACE)
	check("native alignment connects one real joint", int(WorkshopProject.state().joints) == 1 and GameState.count("washi") == 0)
	await shot("03_first_joint_before_pause")
	await tap(KEY_ESCAPE)
	await continue_dialogue([])
	check("Escape keeps the half-work and returns control", int(WorkshopProject.state().joints) == 1 and not GameState.input_locked() and not main.story.busy)
	GameState.save_game()
	var half: Dictionary = WorkshopProject.state().duplicate(true)
	GameState.flags.clear()
	GameState.load_game()
	main._restore()
	check("SQLite returns the native half-work to the same room", WorkshopProject.state() == half and main.room_kind == "workroom")
	await use_point("workroom_table", [])
	for index in 5: await tap(KEY_D)
	await tap(KEY_SPACE)
	for index in 6: await tap(KEY_A)
	await tap(KEY_SPACE)
	await continue_dialogue([])
	check("native assembly completes one identity without repeat material costs", int(WorkshopProject.state().joints) == 3 and WorkshopProject.state().maker == "player")
	await use_point("workroom_lantern_test", [1, 0])
	await use_point("workroom_lantern_test", [0, 0])
	check("native low hanging stays adjustable after failed clearance", WorkshopProject.state().phase == "tested" and not WorkshopProject.state().trial.clear)
	await shot("04_low_hang_actual_feedback")
	await use_point("workroom_lantern_test", [1, 1])
	await use_point("workroom_lantern_test", [0, 0])
	check("the corrected actual hanging can be retained", WorkshopProject.state().phase == "retained")
	await shot("05_retained_hanging_lantern")
	var identity: String = WorkshopProject.state().work_id
	await use_point("workroom_exit", [])
	GameState.day = 17
	GameState.minute = 19 * 60
	main.world.sync_festivals()
	await use_point("festival_work", [0])
	check("old orientation needs adapting at the festival entrance", WorkshopProject.state().installed.is_empty())
	await use_point("festival_work", [2, 1])
	await use_point("festival_work", [0])
	check("same native work is installed with the new approach", str(WorkshopProject.state().installed.get("work_id", "")) == identity)
	await shot("06_same_work_at_festival")
	var file := FileAccess.open(folder.path_join("native-demo.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": failures.is_empty(), "failures": failures, "shots": shots, "facts": WorkshopProject.state().duplicate(true),
		"scope": "fixture prior Q11/date and standing; real E, A, D, Space, Escape, choices, collision trial and SQLite; not natural duration"}, "  "))
	Audio.silence()
	get_tree().quit(0 if failures.is_empty() else 1)

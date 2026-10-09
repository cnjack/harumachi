extends "res://scripts/tools/daily_life_demo.gd"
func _ready() -> void:
	main=get_parent()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): folder=arg.substr(11)
	if folder=="": folder="/tmp/harumachi-lantern-choice"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(25)
	GameState.new_game();GameState.clock_paused=true;NPC.roam_enabled=false;Progress.quiet=true
	main.ui.instant=false;main.ui.auto=false
	GameState.quests.Q00={"state":"done","step":2}
	GameState.quests.Q11={"state":"done","step":3}
	GameState.quests.Q12={"state":"available","step":0}
	await use_point("center_door",[])
	await use_point("workroom_table",[1,0,0])
	var identity: String=WorkshopProject.state().work_id
	await use_point("workroom_lantern_test",[1,0])
	await use_point("workroom_lantern_test",[0,0])
	check("a low aisle really fails before deciding a side location",not WorkshopProject.state().trial.clear)
	await use_point("workroom_lantern_test",[4,1])
	await use_point("workroom_lantern_test",[0,0])
	check("native side choice makes low hanging a useful retained plan",WorkshopProject.state().phase=="retained" and WorkshopProject.state().mount=="side" and WorkshopProject.state().trial.near_text_visible and not WorkshopProject.state().trial.far_marker_visible)
	await use_point("workroom_lantern_test",[5,0])
	await use_point("workroom_lantern_test",[6,0])
	await use_point("workroom_lantern_test",[4,0])
	await use_point("workroom_lantern_test",[1,1])
	await use_point("workroom_lantern_test",[0,0])
	check("native high aisle can also be retained without another work or materials",WorkshopProject.state().phase=="retained" and WorkshopProject.state().trial.far_marker_visible and WorkshopProject.state().work_id==identity and GameState.count("washi")==0)
	await use_point("workroom_lantern_test",[5,0])
	await use_point("workroom_lantern_test",[6,0])
	check("all four actual observation views were presented",seen_actions.has("observe_near_side_155") and seen_actions.has("observe_far_side_155") and seen_actions.has("observe_near_path_240") and seen_actions.has("observe_far_path_240"))
	check("the observer camera and controls return",get_viewport().get_camera_3d()==main.rig.cam and not GameState.input_locked() and not main.story.busy)
	var file:=FileAccess.open(folder.path_join("native-demo.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"shots":shots,"work":WorkshopProject.state(),"scope":"fixture Q11/date/standing; actual E choices, material use, hanging settings, collision tests and four near/far observation cameras"},"  "))
	Audio.silence();get_tree().quit(0 if failures.is_empty() else 1)

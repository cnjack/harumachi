extends "res://scripts/tools/daily_life_demo.gd"
func _ready() -> void:
	main=get_parent();var mode: String="rice"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):folder=arg.substr(11)
		if arg=="--meal-role=serve":mode="serve"
	if folder=="":folder="/tmp/harumachi-meal-route-demo"
	DirAccess.make_dir_recursive_absolute(folder);await frames(25)
	GameState.new_game();GameState.clock_paused=true;NPC.roam_enabled=false;Progress.quiet=true;main.ui.instant=false;main.ui.auto=false
	GameState.day=4;GameState.minute=12*60;GameState.quests.Q00={"state":"done","step":2};GameState.recipes_known.plain_onigiri=true
	DailyLife.event("tea").state="done";DailyLife.event("tea").drank=true;DailyLife.event("tea").completed_day=2
	main.npcs.haru.set_home(false);main.npcs.haru.place(Vector3(14.6,0,16.1),0);GameState.state_changed.emit()
	if mode=="rice":
		await use_point("life_tea",[0,4,0])
		var entry: Dictionary=NeighbourMeals.current();var rid: String=NeighbourMeals.rice_id(entry)
		check("rice role leaves Haru's real side waiting without granting rice materials",entry.role=="rice" and entry.stage=="prepared" and GameState.count("rice")==0)
		await shot("01_haru_side_waiting")
		await use_point("home_door",[])
		GameState.add_item("rice",2,true);GameState.add_item("salt",1,true)
		await use_point("house_stove",[]);await frames(5)
		var clicked: bool=false
		for button: Button in main.ui.modal_layer.find_children("*","Button",true,false):
			if button.get_meta("recipe_id","")==rid and not button.disabled and button.is_visible_in_tree():await click(button.get_global_rect().get_center());clicked=true;break
		check("actual kitchen button consumes rice and salt for one finite two-portion batch",clicked and GameState.count(rid)==2 and GameState.count("rice")==0 and GameState.count("salt")==0 and GameState.reserved_count(rid)==1)
		await shot("02_real_kitchen_two_rice_portions")
		await tap(KEY_ESCAPE);await continue_dialogue([]);await use_point("room_door",[])
		main.npcs.haru.set_home(false);main.npcs.haru.place(Vector3(14.6,0,16.1),0)
		await use_point("life_tea",[0,0]);await frames(5)
		check("each person actually eats one rice and one side without extra servings",entry.rice_given==1 and entry.rice_eaten==1 and entry.npc_ate and entry.player_ate and GameState.count(rid)==0)
		await shot("03_shared_rice_and_side_finished")
	else:
		await use_point("life_tea",[0,5,1])
		check("serving choice opens the actual bowl arrangement in the same interaction",main.ui.modal=="meal_arrangement" and NeighbourMeals.current().stage=="portioning")
		if main.ui.modal!="meal_arrangement":get_tree().quit(1);return
		await frames(8);await shot("01_two_bowls_initial_layout")
		await tap(KEY_2)
		for _overlap_step in 3:await tap(KEY_A)
		await frames(6);await shot("02_overlap_feedback")
		check("overlap is reported while the same two portions remain",main.story.neighbours.view.layout_reason()!="" and NeighbourMeals.current().remaining==2)
		for _recovery_step in 3:await tap(KEY_D)
		await frames(6);await shot("03_recovered_layout")
		await tap(KEY_ENTER);await continue_dialogue([1]);await frames(5)
		var served: Dictionary=NeighbourMeals.state().sessions[0]
		check("retained real layout leads to Haru eating her own and packing only the player's",served.arranged and served.npc_ate and served.player_received and served.author=="haru_cooked_player_portioned" and GameState.count(NeighbourMeals.gift_id(served))==1)
		await shot("04_serving_role_finished")
	check("all controls camera and input restore",not main.story.busy and not GameState.input_locked() and main.ui.modal=="" and get_viewport().get_camera_3d()==main.rig.cam)
	var report:=FileAccess.open(folder.path_join("native-demo.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"shots":shots,"mode":mode,"facts":NeighbourMeals.state(),"scope":"fixture earlier tea, learned plain rice/date/standing and rice/salt when specified; real E/choice/kitchen mouse or arrangement keys; not cold-player time"},"  "))
	Audio.silence();get_tree().quit(0 if failures.is_empty() else 1)

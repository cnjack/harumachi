extends "res://scripts/tools/activity_visual_demo.gd"
## Prior tea/date/standing are fixtures; E, preparation keys and ordinary food use are real UI inputs.
func _ready() -> void:
	main=get_parent()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):folder=arg.substr(11)
	if folder=="":folder="/tmp/harumachi-neighbour-meal-demo"
	DirAccess.make_dir_recursive_absolute(folder);await frames(25)
	GameState.new_game();GameState.clock_paused=true;NPC.roam_enabled=false;Progress.quiet=true;main.ui.instant=false;main.ui.auto=false
	GameState.day=4;GameState.minute=12*60;GameState.quests.Q00={"state":"done","step":2}
	# A completed arrival fixture must include the existing key, not only Q00.
	GameState.add_item("house_key",1,true)
	DailyLife.event("tea").state="done";DailyLife.event("tea").drank=true;DailyLife.event("tea").completed_day=2
	main.npcs.haru.set_home(false);main.npcs.haru.place(Vector3(14.6,0,16.1),0);GameState.state_changed.emit()
	await use_point("life_tea",[0,0,0])
	check("the real tea interaction opens a finite preparation with declared Haru materials",main.ui.modal=="pickle_preparation" and NeighbourMeals.current().role=="prepare")
	if main.ui.modal!="pickle_preparation":get_tree().quit(1);return
	await frames(8);await shot("01_thin_before_cutting")
	await tap(KEY_D);await frames(6);await shot("02_chunk_preview_same_batch")
	await tap(KEY_A)
	for step in 3:await tap(KEY_SPACE)
	await tap(KEY_S);await tap(KEY_W);await frames(6);await shot("03_cut_salted_drained")
	await tap(KEY_ENTER);await continue_dialogue([1]);await frames(5)
	var entry: Dictionary=NeighbourMeals.state().sessions[0]
	check("Haru eats her portion and the player packs exactly the other small portion",entry.npc_ate and entry.player_received and not entry.player_ate and entry.remaining==0 and GameState.count(NeighbourMeals.gift_id(entry))==1)
	await shot("04_return_gift_packed")
	GameState.save_game();var id: String=entry.id;GameState.flags.clear();GameState.load_game();main._restore()
	entry=NeighbourMeals.state().sessions[0]
	check("SQLite restores the same return gift and recipe without another batch",entry.id==id and GameState.count(NeighbourMeals.gift_id(entry))==1 and GameState.recipe_known("haru_thin_pickles"))
	await use_point("home_door",[])
	var entered_house: bool = main.in_room and main.room_kind == "house" and GameState.player_in_room
	check("the real E home-door interaction enters the actual house before any table fixture", entered_house)
	if not entered_house:
		var failure_report: FileAccess = FileAccess.open(folder.path_join("native-demo.json"), FileAccess.WRITE)
		failure_report.store_string(JSON.stringify({"passed": false, "failures": failures, "shots": shots, "scope": "Stopped after actual home-door entry failed; no interior table fixture was attempted."}, "  "))
		Audio.silence(); get_tree().quit(1); return
	await shot("home_entry_verified")
	await use_point("life_meal_table",[0]);await frames(5)
	check("private home eating consumes the real return gift without informing Haru",entry.player_ate and not entry.known_by_haru and GameState.count(NeighbourMeals.gift_id(entry))==0)
	await shot("05_home_return_gift_eaten")
	GameState.add_item("cucumber",1,true);GameState.add_item("salt",1,true)
	await use_point("house_stove",[]);await frames(5)
	var cooked: bool=false
	for button: Button in main.ui.modal_layer.find_children("*","Button",true,false):
		if button.get_meta("recipe_id","")=="haru_thin_pickles" and not button.disabled and button.is_visible_in_tree():await click(button.get_global_rect().get_center());cooked=true;break
	check("the ordinary kitchen really consumes personal ingredients and makes two small portions",cooked and GameState.count("cucumber")==0 and GameState.count("salt")==0 and GameState.count("haru_thin_pickles")==2)
	await shot("06_own_kitchen_two_portions");await tap(KEY_ESCAPE);await continue_dialogue([])
	await use_point("room_door",[])
	var left_house: bool = not main.in_room and main.room_kind == "" and not GameState.player_in_room and not main._transition
	check("the actual E room-door exit finishes before the outdoor tea fixture", left_house)
	if not left_house:
		var exit_report: FileAccess = FileAccess.open(folder.path_join("native-demo.json"), FileAccess.WRITE)
		exit_report.store_string(JSON.stringify({"passed": false, "failures": failures, "shots": shots, "scope": "Stopped before outdoor tea because the actual house exit had not finished."}, "  "))
		Audio.silence(); get_tree().quit(1); return
	main.npcs.haru.set_home(false);main.npcs.haru.place(Vector3(14.6,0,16.1),0)
	await use_point("life_tea",[0]);await frames(5)
	check("only the current witnessed personal meal informs Haru",GameState.count("haru_thin_pickles")==1 and NeighbourMeals.state().shared.haru_thin_pickles.eaten==1)
	await shot("07_current_cup_side_meal")
	check("modal input camera and control return",not main.story.busy and not GameState.input_locked() and main.ui.modal=="" and get_viewport().get_camera_3d()==main.rig.cam)
	var report:=FileAccess.open(folder.path_join("native-demo.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"shots":shots,"facts":NeighbourMeals.state(),"scope":"fixture tea/date/standing and personal cucumber/salt; actual E, A/D/Space/S/W/Enter, packing, SQLite, home meal, mouse kitchen craft and later meal; not natural player timing"},"  "))
	Audio.silence();get_tree().quit(0 if failures.is_empty() else 1)

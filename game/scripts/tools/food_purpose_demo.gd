extends "res://scripts/tools/daily_life_demo.gd"
func _ready() -> void:
	main=get_parent()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): folder=arg.substr(11)
	if folder=="": folder="/tmp/harumachi-food-purpose-demo"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(25)
	GameState.new_game();GameState.clock_paused=true;NPC.roam_enabled=false;Progress.quiet=true;main.ui.instant=false;main.ui.auto=false
	GameState.day=17;GameState.minute=19*60
	GameState.quests.Q00={"state":"done","step":2};GameState.quests.Q05={"state":"done","step":5};GameState.quests.Q11={"state":"done","step":3};GameState.quests.Q14={"state":"done","step":3}
	GameState.recipes_known.plain_onigiri=true
	var prior: Dictionary=SummerProjects.opening();prior.phase="applied";prior.followup=false
	prior.final={"menu":"sandwich","portion":"bite","presentation":"paper","trial_batch":1,"recipe":"veg_sandwich","decided_day":3}
	prior.service={"remaining":0,"served":{"mio":3},"packed":2,"self_eaten":0,"day":3,"trial_batch":1,"source":"shop","ingredients":{}}
	main.world.sync_festivals()
	main.npcs.haru.set_home(false);main.npcs.haru.place(Vector3(6,0,13),0)
	main.npcs.ren.set_home(false);main.npcs.ren.place(Vector3(7,0,13),0)
	GameState.state_changed.emit()
	await use_point("gathering_paper",[0,0,0,1])
	check("a real new basket starts with three source-bound serving IDs",FoodPurpose.units(SummerGathering.current()).size()==3 and int(SummerGathering.current().get("remaining",0))==3)
	if SummerGathering.current().is_empty():
		print("FOOD_NATIVE_STOP ", failures)
		get_tree().quit(1)
		return
	await use_point("haru",[0,0,0])
	check("Haru's actual conversation reserves one drain-wrapped serving for tea",FoodPurpose.eligible(SummerGathering.current(),"haru").purpose=="tea" and FoodPurpose.eligible(SummerGathering.current(),"haru").prep=="drain_wrap")
	await table_shot("01_named_split_paper_portion")
	await use_point("gathering_paper",[5,2,1,0])
	check("self choice takes one existing plate portion into the bag",int(SummerGathering.current().remaining)==2 and GameState.count(SummerGathering.leftover_id("festival"))==1)
	await table_shot("02_one_self_kept_two_left")
	await use_point("gathering_paper",[0,"请春"])
	var unit: Dictionary=FoodPurpose.owned(SummerGathering.current(),"haru")
	check("two actual walks put the same received serving on the supported tea corner",unit.state=="placed" and not unit.use.path.is_empty() and not unit.use.eaten and not unit.use.drank and int(SummerGathering.current().remaining)==1)
	if not failures.is_empty():
		var failed:=FileAccess.open(folder.path_join("native-demo.json"),FileAccess.WRITE)
		failed.store_string(JSON.stringify({"passed":false,"failures":failures,"unit":unit,"scope":"fixture-driven real E and collision walks; stopped at first failed transfer"},"  "))
		Audio.silence();get_tree().quit(1);return
	await tea_shot("03_same_portion_next_to_actual_cups")
	GameState.save_game();var identity: String=unit.id
	GameState.flags.clear();GameState.load_game();main._restore()
	check("SQLite restores the same placed identity and visible use",FoodPurpose.owned(SummerGathering.current(),"haru").id==identity and FoodPurpose.owned(SummerGathering.current(),"haru").state=="placed")
	main.npcs.haru.set_home(false);main.npcs.haru.place(Vector3(14.6,0,16.1),0)
	await use_point("life_tea",["继续晚会杯边那一份","下次带自己做的饭团来配茶"])
	check("natural tea revisit presents the true placement and one optional next meal",FoodPurpose.was_presented(SummerGathering.current(),"haru") and FoodPurpose.followup_state().next.choice=="tea")
	await use_point("gathering_paper",[3])
	await use_point("home_door",[])
	GameState.add_item("rice",2,true);GameState.add_item("salt",1,true)
	await use_point("house_stove",[])
	await frames(8)
	var crafted:=false
	for button in main.ui.modal_layer.find_children("*","Button",true,false):
		if button.get_meta("recipe_id","")==FoodPurpose.NEXT_RECIPE and not button.disabled and button.is_visible_in_tree():
			await click(button.get_global_rect().get_center());crafted=true;break
	check("ordinary kitchen offers the already learned next-meal recipe",crafted)
	await tap(KEY_ESCAPE);await continue_dialogue([])
	check("the kitchen consumes real rice and salt and makes a finite batch",GameState.count(FoodPurpose.NEXT_PORTION)==2 and GameState.count("rice")==0 and GameState.count("salt")==0)
	await use_point("room_door",[])
	main.npcs.haru.set_home(false);main.npcs.haru.place(Vector3(14.6,0,16.1),0)
	await use_point("life_tea",["饭团"])
	check("actual next-meal tea eating completes shared use without hand or mouth animation",FoodPurpose.followup_state().next.state=="completed_tea" and FoodPurpose.followup_state().next.known_by=="haru" and GameState.count(FoodPurpose.NEXT_PORTION)==1)
	await tea_shot("04_after_own_next_meal_at_tea")
	check("input and camera return",not main.story.busy and not GameState.input_locked() and get_viewport().get_camera_3d()==main.rig.cam)
	var file:=FileAccess.open(folder.path_join("native-demo.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"shots":shots,"food":SummerGathering.state(),"followup":FoodPurpose.followup_state(),"scope":"fixture prior chapters/menu/known recipe/date/standing and rice/salt; actual E choices, named preparation, two real walks, tea surface, SQLite, followup, kitchen mouse craft and next meal"},"  "))
	Audio.silence();get_tree().quit(0 if failures.is_empty() else 1)

func table_shot(name: String) -> void:
	await surface_shot(main.story.gathering.view.surface(),name)
func tea_shot(name: String) -> void:
	await surface_shot(main.story.gathering.view.tea_surface(),name)
func surface_shot(at: Vector3,name: String) -> void:
	var original: Camera3D=get_viewport().get_camera_3d();var camera:=Camera3D.new();main.add_child(camera)
	camera.global_position=at+Vector3(.12,.72,.36);camera.look_at(at);camera.fov=65;camera.make_current()
	await frames(4)
	await shot(name);original.make_current();camera.queue_free()

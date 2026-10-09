extends "res://scripts/tools/daily_life_demo.gd"
## Prior chapters/work/date are fixtures; new serving, walking, hanging and cleanup use real E choices.
func _ready() -> void:
	main = get_parent()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): folder = arg.substr(11)
	if folder == "": folder = "/tmp/harumachi-gathering-demo"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(25)
	GameState.new_game()
	GameState.clock_paused = true
	NPC.roam_enabled = false
	Progress.quiet = true
	main.ui.instant = false
	main.ui.auto = false
	GameState.day = 17
	GameState.minute = 19 * 60
	GameState.quests.Q00 = {"state":"done","step":2}
	GameState.quests.Q05 = {"state":"done","step":5}
	GameState.quests.Q11 = {"state":"done","step":3}
	GameState.quests.Q12 = {"state":"available","step":0}
	GameState.quests.Q13 = {"state":"done","step":4}
	GameState.quests.Q14 = {"state":"done","step":3}
	var prior: Dictionary = SummerProjects.opening()
	prior.phase = "done"
	prior.final = {"menu":"focaccia","portion":"bite","presentation":"paper","trial_batch":1,"recipe":"focaccia","decided_day":3}
	WorkshopProject.start("plan","meeting","leaf")
	await frames(3)
	var lamp: WorkroomView = main.world.interiors.workroom.get_node("WorkroomProject")
	WorkshopProject.record_trial(lamp.trial())
	WorkshopProject.retain()
	var identity: String = WorkshopProject.state().work_id
	SummerSpace.start("light","loan")
	main.story.space.apply_scheme("east")
	main.world.sync_festivals()
	main.story.space.view.sync_state()
	main.update_npcs(true)
	await frames(8)
	await use_point("gathering_paper",[0,0,1,1])
	check("festival uses the old menu with a distinct finite new basket", SummerGathering.current().get("context","") == "festival" and int(SummerGathering.current().get("remaining",0)) == 3 and SummerGathering.current().get("presentation","") == "plate")
	await table_shot("01_three_servings_on_actual_table")
	await use_point("gathering_paper",[0,0])
	check("a real guest outside the demonstration circle walks to the current table and receives exactly one serving", SummerGathering.current().get("served",{}).has("haru") and int(SummerGathering.current().remaining) == 2)
	await table_shot("02_one_received_two_left")
	await use_point("gathering_paper",[1,0])
	check("the same representative work is actually installed for the festival", WorkshopProject.state().installed.get("context","") == "festival" and WorkshopProject.state().installed.get("work_id","") == identity)
	await lamp_shot("03_same_work_festival")
	await use_point("gathering_paper",[3])
	check("festival cleanup packs exactly two leftovers and stores the original work", GameState.count(SummerGathering.leftover_id("festival")) == 2 and WorkshopProject.state().stored and WorkshopProject.state().work_id == identity)
	GameState.day = 18
	GameState.minute = 18.5 * 60
	main.world.sync_festivals()
	main.story.space.view.sync_state()
	main.update_npcs(true)
	await frames(8)
	await use_point("mio",[0])
	check("an actual conversation agrees a distinct reunion without retroactive attendance", SummerGathering.context() == "reunion" and not GameState.flags.get("summer_attended",false))
	await use_point("gathering_paper",[0,0,0,1])
	check("the reunion prepares its own paper-wrapped basket", SummerGathering.current().get("context","") == "reunion" and int(SummerGathering.current().get("remaining",0)) == 3 and SummerGathering.current().get("presentation","") == "paper")
	await table_shot("04_reunion_new_basket")
	await use_point("gathering_paper",[0,1])
	check("the reunion's actual receiver is recorded separately", SummerGathering.current().get("served",{}).has("haru") and int(SummerGathering.current().remaining) == 2)
	await use_point("gathering_paper",[1,0])
	check("reunion reuse preserves one work identity and both use occasions", WorkshopProject.state().installed.get("context","") == "reunion" and WorkshopProject.state().work_id == identity and WorkshopProject.state().use_history.size() == 2)
	await lamp_shot("05_same_work_reunion")
	await use_point("gathering_paper",[3])
	check("the two finite food ledgers remain separate after cleanup", GameState.count(SummerGathering.leftover_id("reunion")) == 2 and GameState.count(SummerGathering.leftover_id("festival")) == 2 and SummerGathering.state().sessions.reunion.closed)
	await use_point("center_door",[])
	await frames(8)
	var original: Camera3D = get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	main.add_child(camera)
	camera.global_position = InteriorBuilder.SPECS.workroom.origin + Vector3(-3.1,2.2,2.2)
	camera.look_at(InteriorBuilder.SPECS.workroom.origin + Vector3(-1.2,1.01,-.4))
	camera.make_current()
	await shot("06_same_work_stored_on_actual_worktable")
	original.make_current()
	camera.queue_free()
	GameState.save_game()
	var saved: Dictionary = SummerGathering.state().duplicate(true)
	GameState.flags.clear()
	GameState.load_game()
	main._restore()
	check("SQLite restores both finite sessions and the one stored work", JSON.stringify(SummerGathering.state()) == JSON.stringify(saved) and WorkshopProject.state().stored and WorkshopProject.state().work_id == identity)
	check("control and camera return after each actual operation", not main.story.busy and not GameState.input_locked() and get_viewport().get_camera_3d() == main.rig.cam)
	var file := FileAccess.open(folder.path_join("native-demo.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"shots":shots,"food":SummerGathering.state(),"work":WorkshopProject.state(),"scope":"fixture prior chapters/menu/retained work/date/eastern furniture; actual E choices, real guest walks/current tabletop, same work reuse, explicit reunion, cleanup and SQLite"},"  "))
	Audio.silence()
	get_tree().quit(0 if failures.is_empty() else 1)

func table_shot(id: String) -> void:
	var original: Camera3D = get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	main.add_child(camera)
	var at: Vector3 = main.story.gathering.view.surface()
	if not at.is_finite(): failures.append("missing actual food surface " + id); camera.queue_free(); return
	camera.global_position = at + Vector3(.12,.72,.36)
	camera.fov = 65
	camera.look_at(at)
	camera.make_current()
	await shot(id)
	original.make_current()
	camera.queue_free()

func lamp_shot(id: String) -> void:
	var original: Camera3D = get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	main.add_child(camera)
	var at: Vector3 = WorkroomView.festival_position()
	camera.global_position = at + Vector3(1.3,.4,3.2)
	camera.fov = 42
	camera.look_at(at)
	camera.make_current()
	await shot(id)
	original.make_current()
	camera.queue_free()

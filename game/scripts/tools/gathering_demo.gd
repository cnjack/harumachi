extends "res://scripts/tools/activity_visual_demo.gd"
## Prior chapters/work/date are fixtures; new serving, walking, hanging and cleanup use real E choices.
var _gathering_stages: Array[Dictionary] = []

func _qa_focus(label: String) -> Vector3:
	if label in ["01_three_servings_on_actual_table", "02_one_received_two_left", "04_reunion_new_basket"]: return main.story.gathering.view.surface() + Vector3.UP * .04
	if label in ["03_same_work_festival", "05_same_work_reunion"]: return WorkroomView.festival_position()
	if label == "06_same_work_stored_on_actual_worktable":
		var work: WorkroomView = main.world.interiors.workroom.get_node("WorkroomProject")
		if is_instance_valid(work.specimen): return work.specimen.global_position + Vector3.UP * .13
	return Vector3.INF

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
	GameState.quests.Q12 = {"state":"done","step":4}
	GameState.quests.Q13 = {"state":"done","step":4}
	GameState.quests.Q14 = {"state":"done","step":3}
	# Completing the shared summer chapters already requires knowing Mio.
	# Keep that existing history consistent; a personal event is still offered
	# below and the driver explicitly chooses the actual work-topic button.
	GameState.flags["met_mio"] = true
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
	var conversation_context: Dictionary = Story.CONVERSATION.context(main.story, "mio")
	conversation_context.erase("skip_entry")
	var personal_entry: Dictionary = Dialogue.pick("mio", conversation_context)
	var reunion_choices: Array = []
	if personal_entry.get("event", false): reunion_choices.append("继续手头的事")
	reunion_choices.append("另约一晚，在树下坐坐")
	var reunion_before: Dictionary = {"stage":"before_reunion_E", "day":GameState.day, "minute":GameState.minute,
		"met_mio":GameState.flags.get("met_mio",false), "gathering_handles":main.story.gathering.handles("mio"),
		"lore_pending":main.story.lore.pending("mio"), "phase":GameState.phase, "context":SummerGathering.context(),
		"Q12":GameState.quests.Q12.duplicate(true), "Q14":GameState.quests.Q14.duplicate(true),
		"personal_event":str(personal_entry.get("id","")) if personal_entry.get("event",false) else "",
		"actual_choices":reunion_choices.duplicate()}
	_gathering_stages.append(reunion_before)
	print("GATHERING_REUNION ", JSON.stringify(reunion_before))
	var ready_to_ask: bool = bool(reunion_before.met_mio) and bool(reunion_before.gathering_handles) and not bool(reunion_before.lore_pending)
	check("the completed-chapter fixture exposes the actual reunion conversation", ready_to_ask)
	if not ready_to_ask:
		_finish_demo()
		return
	await use_point("mio",reunion_choices)
	var reunion_agreed: bool = SummerGathering.context() == "reunion" and not GameState.flags.get("summer_attended",false)
	_gathering_stages.append({"stage":"after_reunion_E", "context":SummerGathering.context(), "reunion_day":SummerGathering.state().reunion_day,
		"summer_attended":GameState.flags.get("summer_attended",false), "input_locked":GameState.input_locked(), "busy":main.story.busy})
	check("an actual conversation agrees a distinct reunion without retroactive attendance", reunion_agreed)
	if not reunion_agreed or not failures.is_empty():
		_finish_demo()
		return
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
	_finish_demo()

func _finish_demo() -> void:
	var file := FileAccess.open(folder.path_join("native-demo.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"shots":shots,"food":SummerGathering.state(),"work":WorkshopProject.state(),"reunion_input":_gathering_stages,"scope":"fixture prior chapters/known Mio/menu/retained work/date/eastern furniture; actual E and explicit personal-event/work/reunion choices, real guest walks/current tabletop, same work reuse, explicit reunion, cleanup and SQLite"},"  "))
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

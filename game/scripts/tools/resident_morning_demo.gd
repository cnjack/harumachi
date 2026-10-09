extends "res://scripts/tools/daily_life_demo.gd"
## Fixture day/standing; actual E choices and rendered tray movement. No duration claim.
var was_sliding := false
var slide_start := 0
var frame_deltas: Array[float] = []
var slide_metrics: Array = []
func _process(delta: float) -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.story.morning):return
	var sliding: bool=main.story.morning.active
	if sliding and not was_sliding:slide_start=Time.get_ticks_msec();frame_deltas.clear()
	if sliding:frame_deltas.append(delta)
	if was_sliding and not sliding:
		slide_metrics.append({"seconds":float(Time.get_ticks_msec()-slide_start)/1000.0,"frames":frame_deltas.size(),"worst_frame_seconds":frame_deltas.max() if not frame_deltas.is_empty() else 0.0})
	was_sliding=sliding
func _ready() -> void:
	main=get_parent()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):folder=arg.substr(11)
	if folder=="":folder="/tmp/harumachi-resident-morning"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(25)
	NPC.roam_enabled=false;Progress.quiet=true;main.ui.auto=false;main.ui.instant=false
	var camera:=Camera3D.new();main.add_child(camera)
	camera.global_position=Vector3(10.4,4.5,23.8);camera.fov=46
	camera.look_at(Vector3(14.4,1.0,16.8));camera.make_current()
	var observed_facts: Array=[]
	for choice: int in [3,0,1,2]:
		GameState.new_game();GameState.clock_paused=true
		GameState.quests.Q00={"state":"done","step":2};GameState.day=3;GameState.minute=480
		main.update_npcs(true)
		for who: String in ["haru","aoi"]:
			main.npcs[who].set_home(false);main.npcs[who].place(Layout.NPC[who].prep,Layout.NPC[who].prep_yaw)
		main.story.daily.view.sync_state();main.story.morning.sync_tray()
		GameState.time_changed.emit(480)
		GameState.state_changed.emit()
		main.player.global_position=Vector3(15.1,.1,17.75);main.player.velocity=Vector3.ZERO
		main.rig.snap();await frames(15)
		var tray: Node3D=main.story.daily.view.tea_root
		var before: Vector3=tray.global_position
		await shot("%d_before"%choice)
		if choice==3:
			await get_tree().create_timer(2.2).timeout
			check("both residents and their readable exchange are actually in view",main.story.morning.readable() and main.story.morning.facts().observed)
		await use_point("resident_morning",[choice])
		var facts: Dictionary=main.story.morning.facts().duplicate(true)
		if choice==3:check("leave keeps the tray, quests and optional help untouched",not facts.asked and not facts.helped and tray.global_position==before)
		elif choice==0:check("a question records the explanation without moving the tray",facts.asked and not facts.helped and tray.global_position==before)
		else:check("choice %d physically moves the same tray to its distinct valid plan"%choice,facts.helped and int(facts.place)==choice-1 and main.story.morning.placed_now and tray.global_position.distance_to(before)>.25)
		check("choice %d returns camera, dialogue, control and both residents"%choice,get_viewport().get_camera_3d()==camera and not main.story.busy and not main.player.frozen and not GameState.input_locked() and not main.npcs.haru.talking and not main.npcs.aoi.talking)
		check("choice %d neither plants nor begins either crop quest"%choice,GameState.crop_stage==0 and GameState.qstate("Q03")=="locked" and GameState.qstate("Q08")=="locked")
		observed_facts.append({"choice":choice,"facts":facts,"before":str(before),"after":str(tray.global_position)})
		await shot("%d_after"%choice)
	var file:=FileAccess.open(folder.path_join("native-demo.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"facts":observed_facts,"shots":shots,"slide_metrics":slide_metrics,"scope":"fixture day and standing; actual E/choice input, visible tray slide and cleanup; not ordinary duration or human fun"},"  "))
	main.rig.cam.make_current();camera.queue_free();Audio.silence()
	get_tree().quit(0 if failures.is_empty() else 1)

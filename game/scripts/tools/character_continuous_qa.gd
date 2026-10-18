extends RefCounted
## Native Player/NPC movement and final applied skeletons, isolated by the QA runner.
const PROBE = preload("res://scripts/tools/character_continuous_probe.gd")
const IDS: Array[String] = ["sora", "ren", "haru", "mio", "aoi", "tanaka", "kazuko"]
var start := Vector3(-14, .03, -10)
var direction := Vector3.RIGHT
var reports: Array[Dictionary] = []
var failures: Array[String] = []
var views: Array[String] = ["right"]
var clips: Array[String] = ["walk", "run"]

func capture(qa: Node, output: String) -> void:
	var invalid_clips := false
	for clip_argument: String in OS.get_cmdline_user_args():
		if not clip_argument.begins_with("--continuous-clips="): continue
		clips.clear()
		for requested_clip: String in clip_argument.trim_prefix("--continuous-clips=").split(","):
			if requested_clip not in ["walk", "run"] or requested_clip in clips:
				failures.append("invalid or duplicate continuous clip: " + requested_clip)
				invalid_clips = true
				continue
			clips.append(requested_clip)
		if clips.is_empty():
			failures.append("no continuous clips requested")
			invalid_clips = true
	if invalid_clips: clips.clear()
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--continuous-views="): continue
		views.clear()
		for requested_view: String in argument.trim_prefix("--continuous-views=").split(","):
			if requested_view not in ["front", "right", "back", "left", "top"]:
				failures.append("unknown continuous camera view: " + requested_view)
				continue
			if requested_view not in views: views.append(requested_view)
		if views.is_empty(): views.append("right")
	var previous_freeze: bool = NPC.freeze
	NPC.freeze = false
	qa.call("outdoors")
	if "walk" in clips:
		for walk_id: String in IDS:
			if walk_id not in qa.get("ids"): continue
			for walk_view: String in views: await capture_case(qa, walk_id, "walk", -1.0, walk_view)
	if "run" in clips and "sora" in qa.get("ids"):
		for player_run_view: String in views: await capture_case(qa, "sora", "run", -1.0, player_run_view)
	if "run" in clips:
		for run_id: String in ["mio", "haru", "ren", "aoi", "tanaka", "kazuko"]:
			if run_id not in qa.get("ids"): continue
			var speed: float = float({"mio": 3.2, "haru": 4.5, "ren": 3.2, "aoi": 3.1, "tanaka": 3.4, "kazuko": 3.6}[run_id])
			for npc_run_view: String in views: await capture_case(qa, run_id, "run", speed, npc_run_view)
	NPC.freeze = previous_freeze
	var report: Dictionary = {"engine": Engine.get_version_info().string, "scope": "Final SkeletonModifier3D pose during native Player/NPC root movement, two complete clip cycles after warmup.", "sampling": "One final modifier sample per rendered process frame, existing cached shoe envelope <=26 points per foot.", "floor": "Constant measured rendered street height. This fixture does not establish slope/stair contact.", "npc_run_fixture": "NPC runs use explicit speed fixtures. Mio/Ren=3.2 and Haru=4.5 match the courtyard quick option; other NPC run cases test the same controller and clip without claiming normal story use.", "failures": failures, "cases": reports}
	report["requested_clips"] = clips.duplicate()
	var file: FileAccess = FileAccess.open(output.path_join("continuous-gait.json"), FileAccess.WRITE)
	if file == null:
		qa.get("failures").append("could not write continuous-gait.json")
		return
	file.store_string(JSON.stringify(report, "\t"))
	for failure: String in failures: qa.get("failures").append(failure)
	print("RIG_CONTINUOUS_QA ", JSON.stringify({"cases": reports.size(), "failures": failures, "output": output}))

func capture_case(qa: Node, id: String, clip: String, forced_speed: float, view: String) -> void:
	qa.call("choose", id, start)
	var target: Node3D = qa.get("actor") as Node3D
	var source: Node3D = qa.get("model") as Node3D
	var controller: CharAnim = qa.get("anim") as CharAnim
	var game: Node3D = qa.get("main") as Node3D
	var sk: Skeleton3D = source.find_child("Skeleton3D", true, false) as Skeleton3D
	var probe: SkeletonModifier3D = PROBE.new()
	probe.name = "RigAuditFinalContinuousProbe"
	sk.add_child(probe)
	var floor_info: Dictionary = target.get_meta("qa_floor_support", {})
	var ground: float = float(floor_info.get("render_height", target.global_position.y))
	probe.call("prepare", source, target, controller.ap, ground)
	controller._oneshot = ""
	controller.set_idle("idle", true)
	await qa.call("settle", 8)
	var original_speed := -1.0
	if target is Player:
		var start_player: Player = target as Player
		start_player.frozen = false
		start_player.velocity = Vector3.ZERO
		start_player.set_facing(atan2(direction.x, direction.z))
		start_player.auto_move = direction
		start_player.auto_run = clip == "run"
		start_player.set_physics_process(true)
	else:
		var start_npc: NPC = target as NPC
		original_speed = start_npc.speed
		if forced_speed > 0: start_npc.speed = forced_speed
		var hidden_player: Node3D = game.get("player") as Node3D
		hidden_player.global_position = Vector3(-41, .1, -9.5)
		start_npc.hold = false
		start_npc.talking = false
		start_npc.set_yaw(atan2(direction.x, direction.z))
		start_npc.set_process(true)
		start_npc.walk([target.global_position + direction * 22.0])
	var warmup_end: int = Time.get_ticks_msec() + 1250
	while Time.get_ticks_msec() < warmup_end:
		qa.call("look", view)
		await qa.get_tree().process_frame
	for warm_modifier_name: String in ["CharacterFootSupport", "CharacterGarmentSupport", "CharacterApronSupport"]:
		var warm_modifier: Node = source.find_child(warm_modifier_name, true, false)
		if warm_modifier != null and warm_modifier.has_method("reset_performance"):
			warm_modifier.call("reset_performance")
	probe.call("begin")
	var foot_debug: Node = source.find_child("CharacterFootSupport", true, false)
	if foot_debug != null: foot_debug.set("qa_trace_enabled", true)
	var natural_debug: Node = source.find_child("NaturalLocomotionPose", true, false)
	if natural_debug != null: natural_debug.set("qa_trace_enabled", true)
	var capture_start: Vector3 = target.global_position
	var images: Array[Dictionary] = []
	var image_last_usec := 0
	var phase_before: float = controller.ap.current_animation_position / maxf(controller.ap.current_animation_length, .001)
	var progress := 0.0
	var deadline: int = Time.get_ticks_msec() + 7000
	while progress < 2.05 and Time.get_ticks_msec() < deadline:
		qa.call("look", view)
		await qa.get_tree().process_frame
		if controller.ap.current_animation != clip: continue
		var phase: float = controller.ap.current_animation_position / maxf(controller.ap.current_animation_length, .001)
		var advance: float = phase - phase_before
		if advance < -.5: advance += 1.0
		if advance >= 0.0 and advance < .5: progress += advance
		phase_before = phase
		if Time.get_ticks_usec() - image_last_usec >= 50000:
			await RenderingServer.frame_post_draw
			image_last_usec = Time.get_ticks_usec()
			images.append({"image": qa.get_viewport().get_texture().get_image(), "elapsed_s": (Time.get_ticks_usec() - int(probe.get("began_usec"))) / 1000000.0, "phase": controller.ap.current_animation_position / maxf(controller.ap.current_animation_length, .001)})
	probe.set("recording", false)
	var frames: Array = probe.get("rows")
	var distance: float = target.global_position.distance_to(capture_start)
	var fixture: String = "explicit_NPC_run_speed_fixture_not_story_flow" if forced_speed > 0 else "native_runtime_speed"
	var record: Dictionary = {"character": id, "requested_clip": clip, "fixture": fixture, "forced_speed_mps": forced_speed if forced_speed > 0 else null, "ground_height": ground, "captured_clip_cycles": progress, "actual_displacement_m": distance, "frame_count": frames.size(), "frames": frames.duplicate(true)}
	record["view"] = view
	record["bone_layout"] = probe.get("bone_layout")
	if foot_debug != null: foot_debug.set("qa_trace_enabled", false)
	if natural_debug != null: natural_debug.set("qa_trace_enabled", false)
	for modifier_name: String in ["CharacterFootSupport", "CharacterGarmentSupport", "CharacterApronSupport"]:
		var modifier: Node = source.find_child(modifier_name, true, false)
		if modifier != null and modifier.has_method("performance"):
			record[modifier_name + "_performance"] = modifier.call("performance")
	reports.append(record)
	if progress < 2.0: failures.append(id + "/" + clip + ": fewer than two continuous cycles")
	if frames.size() < 20: failures.append(id + "/" + clip + ": fewer than 20 final rendered poses")
	if distance < .5: failures.append(id + "/" + clip + ": native movement did not travel .5m")
	if target is Player:
		var stop_player: Player = target as Player
		stop_player.auto_move = Vector3.ZERO
		stop_player.auto_run = false
		stop_player.set_physics_process(false)
	else:
		var stop_npc: NPC = target as NPC
		stop_npc.place(stop_npc.global_position, 0)
		stop_npc.speed = original_speed
		stop_npc.set_process(false)
	probe.queue_free()
	controller.set_idle("idle", true)
	await qa.call("settle", 2)
	var image_folder: String = str(qa.get("output")).path_join(id + "-" + clip + ("-fast" if forced_speed > 0 else "") + ("-" + view if views != ["right"] else ""))
	DirAccess.make_dir_recursive_absolute(image_folder)
	var image_rows: Array[Dictionary] = []
	for image_index: int in images.size():
		var image_row: Dictionary = images[image_index]
		var image_file: String = "%04d.png" % image_index
		(image_row.image as Image).save_png(image_folder.path_join(image_file))
		image_rows.append({"file": image_file, "elapsed_s": image_row.elapsed_s, "phase": image_row.phase})
	record["images"] = image_rows
	record["image_folder"] = image_folder.get_file()

extends SceneTree
## Native proof of the actual street walkers, with caller-provided isolated saves.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(not OS.get_environment("HARUMACHI_SAVE_DIR").is_empty(), "Cat capture requires an isolated HARUMACHI_SAVE_DIR")
	# Keep 900 native frames at least 15 real seconds on 120Hz displays too.
	Engine.max_fps = 60
	var output: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var state: Node = root.get_node("GameState")
	state.new_game()
	state.clock_paused = true
	state.minute = 600
	var npc_script: GDScript = load("res://scripts/npc/npc.gd") as GDScript
	npc_script.roam_enabled = false
	var main: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	for frame: int in range(35): await process_frame
	main.world.set_region("town")
	main.player.global_position = Vector3(25, .1, 60)
	main.ui.visible = false
	var cats: Array = main.life.roaming_cats
	assert(cats.size() == 2)
	for node: Node in main.find_children("*", "Camera3D", true, false): (node as Camera3D).current = false
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = .70
	main.add_child(camera)
	camera.current = true
	var started: int = Time.get_ticks_msec()
	var samples: Array[Dictionary] = []
	var start_attention: Array[float] = []
	var start_travel: Array[float] = []
	for cat: CharacterBody3D in cats:
		start_attention.append(float(cat.attention.get("attention_time")))
		start_travel.append(cat.travelled)
	for frame: int in range(900):
		var index: int = 0 if frame < 450 else 1
		var cat: CharacterBody3D = cats[index] as CharacterBody3D
		var side_view: bool = frame % 450 < 120
		camera.global_position = cat.global_transform * (Vector3(1.2, .25, 0) if side_view else Vector3(0, .34, 1.15))
		camera.size = .70 if side_view else .46
		camera.look_at(cat.global_position + Vector3(0, .18, 0))
		await process_frame
		if frame % 30 == 0:
			var skel: Skeleton3D = cat.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var tip_index: int = skel.find_bone("Tail_11")
			var tail: Vector3 = skel.get_bone_global_pose(tip_index).origin
			var info: Dictionary = cat.telemetry()
			info["cat"] = "orange" if index == 0 else "calico"
			info["frame"] = frame
			info["joints"] = skel.get_bone_count()
			info["native_walk_speed"] = cat.native_walk_speed
			info["tail_tip_local"] = [tail.x, tail.y, tail.z]
			samples.append(info)
		if frame in [45, 90, 180, 240, 300, 360, 390, 495, 540, 600, 660, 720, 780, 810]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("%s-street-%04d.png" % ["orange" if index == 0 else "calico", frame]))
	var passed: bool = true
	var outcomes: Array[Dictionary] = []
	for index: int in range(2):
		var cat: CharacterBody3D = cats[index] as CharacterBody3D
		var info: Dictionary = cat.telemetry()
		info["cat"] = "orange" if index == 0 else "calico"
		info["native_walk_speed"] = cat.native_walk_speed
		info["attention_delta_seconds"] = float(cat.attention.get("attention_time")) - start_attention[index]
		info["travel_delta_m"] = cat.travelled - start_travel[index]
		info["attention_running"] = cat.attention != null and float(info.attention_delta_seconds) > 10.0
		info["passed"] = bool(info.attention_running) and float(info.travel_delta_m) > .5 and absf(cat.global_position.y) < .04 and cat.speed >= .32 and cat.speed <= .45 and cat.maximum_step < .025 and int(info.foot_locked_samples) > 0 and float(info.foot_lock_error) < .002
		outcomes.append(info)
		passed = passed and bool(info.passed)
	FileAccess.open(output.path_join("runtime.json"), FileAccess.WRITE).store_string(JSON.stringify({"passed": passed, "target_fps": 60, "elapsed_seconds": float(Time.get_ticks_msec() - started) / 1000.0, "walkers": outcomes, "samples": samples}, "\t"))
	print("CAT_LIVELY_WORLD ", outcomes)
	main.queue_free()
	await process_frame
	quit(0 if passed else 1)

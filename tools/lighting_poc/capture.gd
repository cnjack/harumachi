extends "res://scripts/tools/performance_bench.gd"
## Same shipping scene and camera paths for both sides. Movie timings are not benchmarks.
var poc: Node
var clips: Array[Dictionary] = []

func _run() -> void:
	if not _parse_args(): return
	seed(261025)
	_resolve_monitors()
	paused = false
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var warm := 0
	while not bool(main.get("loading_ready")) and warm < 3600:
		await process_frame
		warm += 1
	if not bool(main.get("loading_ready")):
		printerr("BENCH_FAIL loading timeout"); quit(3); return
	root.get_node("GameState").set("clock_paused", true)
	_prepare_scene(main)
	if _user_arg("look", "before") == "poc":
		poc = load("res://scripts/tools/lighting_poc_look.gd").new()
		poc.set("world", main.get("world"))
		main.add_child(poc)
	var views: Dictionary = load("res://scripts/tools/environment_visual_qa.gd").get_views()
	var specs: Dictionary = bench_views()
	specs.street.minute = 1038.0
	specs.street.label = "商店街 · 夕阳"
	for view_id: String in _view_ids:
		if _user_arg("capture", "preview") == "movie":
			await _record_view(main, view_id, specs[view_id] as Dictionary, views)
		else:
			await _run_view(main, view_id, specs[view_id] as Dictionary, views)
			if poc != null: _rows.back()["lighting_poc"] = poc.call("snapshot")
			_verify_balanced(main)
			_write_result("complete")
	var f := FileAccess.open(_out.path_join("clips.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"clips": clips, "physics_frames_total": Engine.get_physics_frames(), "movie_fps": 30, "look": _user_arg("look", "before")}, "\t"))
	quit(0)

func _verify_balanced(main: Node) -> void:
	var mode: Dictionary = root.get_node("PerformanceMode").call("snapshot")
	var world: Node3D = main.get("world") as Node3D
	var env: Environment = world.get("env") as Environment
	assert(mode.profile == "balanced" and mode.fps_cap == 60)
	assert(is_equal_approx(float(mode.scale), .85) and mode.msaa == 2 and mode.shadow_size == 4096)
	assert(env.ssao_enabled and not env.ssil_enabled)
	assert(env.volumetric_fog_enabled == bool(world.get("indoor")))
	assert(is_equal_approx(env.tonemap_exposure, 1.0))
	if poc != null: assert(int(poc.get("changed_materials")) > 0)

func _apply_ablation(main: Node) -> void:
	super._apply_ablation(main)
	if poc != null:
		poc.call("install_materials")
		poc.call("apply")

func _record_view(main: Node, id: String, spec: Dictionary, views: Dictionary) -> void:
	var state: Node = root.get_node("GameState")
	state.set("day", int(spec.get("day", 1)))
	state.set("minute", float(spec.minute))
	state.set("weather", "sunny")
	await _place(main, spec, views)
	var world: Node3D = main.get("world") as Node3D
	world.call("update_time", float(spec.minute), "sunny", true)
	main.call("_sync_weather")
	main.call("update_npcs", true)
	main.call("sync_festival_state")
	_prepare_scene(main)
	_apply_ablation(main)
	for _warm_frame: int in 120: await process_frame
	var cam: Camera3D = root.get_camera_3d()
	var start: Transform3D = cam.global_transform
	var target: Vector3 = start.origin - start.basis.z * (8.0 if id == "store_interior" else 24.0)
	await RenderingServer.frame_post_draw
	var begin: int = Engine.get_frames_drawn()
	var trajectory: Array = []
	for frame: int in 366:
		await process_frame
		var u: float = float(frame) / 365.0
		var angle: float = deg_to_rad(lerpf(-3.0, 3.0, u))
		cam.global_position = target + (start.origin - target).rotated(Vector3.UP, angle)
		cam.look_at(target, Vector3.UP)
		cam.reset_physics_interpolation()
		await RenderingServer.frame_post_draw
		if frame in [2, 182, 362]:
			root.get_texture().get_image().save_png(_out.path_join("%s_%03d.png" % [id, frame]))
			trajectory.append({"frame": frame, "position": str(cam.global_position), "basis": str(cam.global_basis)})
	var end: int = Engine.get_frames_drawn()
	var graphics: Dictionary = root.get_node("PerformanceMode").call("snapshot")
	assert(end - begin >= 366, "Movie renderer stopped advancing")
	_verify_balanced(main)
	clips.append({"view": id, "label": spec.label, "minute": spec.minute, "start_frame": begin,
		"end_frame": end, "trim_start": begin + 3, "frames": 360, "camera": trajectory,
		"graphics": graphics, "lighting": poc.call("snapshot") if poc != null else {}})
	print("POC_CLIP ", JSON.stringify(clips.back()))

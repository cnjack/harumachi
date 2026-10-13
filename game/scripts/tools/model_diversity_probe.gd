extends Node
## Native render-cost comparison. GPU timestamps remain meaningful with a display FPS cap.
func _ready() -> void:
	GameState.new_game()
	GameState.clock_paused = true
	NPC.roam_enabled = false
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for frame in 60:
		await get_tree().process_frame
	var viewport_id: RID = get_viewport().get_viewport_rid()
	var out: String = "/tmp/model-diversity-performance.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	RenderingServer.viewport_set_measure_render_time(viewport_id, true)
	var records: Array[Dictionary] = []
	for region: String in ["town", "farm", "home", "store"]:
		if region == "home":
			await main.enter_room()
			main.player.global_position = Layout.ROOM_ORIGIN + Vector3(-3.2, .1, 3.5)
		elif region == "store":
			await main.exit_room()
			await main.enter_interior("store")
			main.player.global_position = InteriorBuilder.spec_for("store").origin + Vector3(.6, .1, 1.9)
		else:
			main.world.set_region(region)
			main.world.set_indoor_look(false)
			main.rig.fixed = false
			main.player.global_position = FarmBuilder.ORIGIN + Vector3(0, .2, -.4) if region == "farm" else Vector3(19.7, .2, 56)
		main.rig.dist = 8.6
		main.rig.pitch = 46.0 if region in ["home", "store"] else 18.0
		main.rig.yaw = 0.0
		main.rig.snap()
		for frame in 120:
			await get_tree().process_frame
		var intervals: Array[float] = []
		var render_cpu: Array[float] = []
		var render_gpu: Array[float] = []
		var previous: int = Time.get_ticks_usec()
		var draw_calls: int = 0
		var primitives: int = 0
		for frame in 360:
			if region in ["town", "farm"]:
				main.rig.yaw += 1.0
			await get_tree().process_frame
			var now: int = Time.get_ticks_usec()
			intervals.append(float(now - previous) / 1000.0)
			previous = now
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport_id))
			render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport_id))
			draw_calls = maxi(draw_calls, get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
			primitives = maxi(primitives, get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
		await RenderingServer.frame_post_draw
		var rendered: Image = get_viewport().get_texture().get_image()
		rendered.save_png(out.get_basename() + "_" + region + ".png")
		records.append({"region": region, "frames": 360, "frame_ms": _summary(intervals),
			"render_cpu_ms": _summary(render_cpu), "render_gpu_ms": _summary(render_gpu),
			"max_draw_calls": draw_calls, "max_primitives": primitives,
			"rendered_image_size": [rendered.get_width(), rendered.get_height()]})
	var file: FileAccess = FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(),
		"viewport_texture_size": get_viewport().get_texture().get_size(), "logical_canvas_size": get_viewport().get_visible_rect().size,
		"window_size": DisplayServer.window_get_size(),
		"content_scale_factor": get_tree().root.content_scale_factor,
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps, "samples": records}, "  "))
	file.close()
	get_tree().quit()


func _summary(values: Array[float]) -> Dictionary:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return {"median": sorted[180], "p95": sorted[342], "max": sorted.back(), "valid": sorted[180] > 0.0}

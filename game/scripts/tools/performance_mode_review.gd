extends SceneTree
var rows: Array[Dictionary] = []
var out := ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	_run.call_deferred()

func check(label: String, ok: bool, detail: Variant = null) -> void:
	rows.append({"label": label, "ok": ok, "detail": detail})
	print(("PASS " if ok else "FAIL ") + label + " " + str(detail))

func frames(count: int) -> void:
	for index: int in count: await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))

func sample_frames(count: int) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	var previous: int = start
	var rendered: int = Engine.get_frames_drawn()
	var intervals: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	for index: int in count:
		await process_frame
		var now: int = Time.get_ticks_usec()
		intervals.append((now - previous) / 1000.0)
		previous = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	intervals.sort()
	gpu.sort()
	cpu.sort()
	return {"seconds": (Time.get_ticks_usec() - start) / 1000000.0, "rendered": Engine.get_frames_drawn() - rendered, "fps": float(count) * 1000000.0 / (Time.get_ticks_usec() - start), "median_ms": intervals[int(count * .5)], "p95_ms": intervals[int(count * .95)], "max_ms": intervals[-1], "gpu_median_ms": gpu[int(count * .5)], "cpu_median_ms": cpu[int(count * .5)], "focused": root.has_focus(), "refresh_rate": DisplayServer.screen_get_refresh_rate(), "vsync": DisplayServer.window_get_vsync_mode(), "cap": Engine.max_fps, "size": str(root.size), "time_scale": Engine.time_scale}

func _run() -> void:
	if out.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(out)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var mode: Node = root.get_node("PerformanceMode")
	var state: Node = root.get_node("GameState")
	var title: Node = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await frames(45)
	title.call("_settings")
	await frames(15)
	var option: OptionButton = title.find_child("GraphicsProfile", true, false) as OptionButton
	check("title shows graphics settings", option != null)
	if option != null:
		check("title settings remain inside viewport", root.get_visible_rect().encloses(option.get_global_rect()))
		option.select(2)
		option.item_selected.emit(2)
		await frames(10)
		check("title choice applies eco and persists", mode.get("profile") == "eco" and state.get("settings").graphics_profile == "eco" and Engine.max_fps == 30)
	await shot("title_settings")
	state.get("settings")["graphics_profile"] = "balanced"
	state.call("save_settings")
	title.queue_free()
	await frames(2)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	while not main.get("loading_ready"): await process_frame
	state.set("clock_paused", true)
	main.ui.dialogue_end()
	main._restore()
	await frames(90)
	mode.call("configure", "balanced")
	var foreground: Dictionary = await sample_frames(300)
	check("balanced scene renders continuously near60 fps", foreground.fps > 54 and foreground.fps < 64 and foreground.rendered >= 110, foreground)
	main.ui.open_pause()
	await frames(8)
	var pause: Dictionary = await sample_frames(300)
	check("real pause menu drops render rate to30 fps", paused and Engine.max_fps == 30 and pause.fps > 26 and pause.fps < 34, pause)
	main.ui.open_settings()
	await frames(10)
	await shot("game_settings")
	main.ui.close_modal()
	paused = false
	await frames(10)
	check("resuming restores chosen foreground frame cap", Engine.max_fps == 60)
	# Exercise actual notification handler while keeping test focus deterministic.
	mode.set("benchmark", false)
	mode.call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(5)
	check("focus-out notification reduces cap without altering physics", Engine.max_fps == 10 and Engine.physics_ticks_per_second == 60)
	mode.call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await frames(8)
	check("focus-in notification restores the selected cap", Engine.max_fps == 60)
	mode.set("benchmark", true)
	mode.call("configure", "eco")
	await frames(20)
	var eco: Dictionary = await sample_frames(300)
	check("eco scene renders continuously near30 fps", eco.fps > 26 and eco.fps < 34 and eco.rendered >= 55, eco)
	mode.call("configure", "quality")
	await frames(15)
	check("original detail restores full3D resolution and4x MSAA", is_equal_approx(root.scaling_3d_scale, 1.0) and root.msaa_3d == Viewport.MSAA_4X)
	mode.call("configure", "balanced")
	main.rig.process_mode = Node.PROCESS_MODE_DISABLED
	main.player.global_position = Vector3(25, .01, -10)
	var actor: Node3D = main.npcs["mio"] as Node3D
	actor.call("set_home", false)
	actor.set_process(false)
	actor.call("place", Vector3(-5, .01, -9), -90.0)
	actor.set("hold", false)
	actor.get("anim").call("set_idle", "idle", true)
	var animation: AnimationPlayer = actor.get("anim").get("ap") as AnimationPlayer
	var camera: Camera3D = main.rig.cam
	camera.global_position = actor.global_position + Vector3(-28, 2.5, 0)
	camera.look_at(actor.global_position + Vector3.UP)
	camera.reset_physics_interpolation()
	var support: Node = actor.find_child("CharacterGarmentSupport", true, false)
	await frames(45)
	support.call("reset_performance")
	var phase_before: float = animation.current_animation_position
	var phase_changes := 0
	var last_phase: float = phase_before
	for index: int in 90:
		await process_frame
		if absf(animation.current_animation_position - last_phase) > .0001: phase_changes += 1
		last_phase = animation.current_animation_position
	var far_stats: Dictionary = support.call("native_contact_original_performance")
	check("actual distant cloth reuses solves while source animation continues", int(far_stats.budget_skipped) > 20 and int(far_stats.budget_solved) > 15 and animation.is_playing() and phase_changes >= 80, {"skipped": far_stats.budget_skipped, "solved": far_stats.budget_solved, "phase_changes": phase_changes, "phase_before": phase_before, "phase_after": animation.current_animation_position})
	await shot("mio_far_balanced")
	camera.global_position = actor.global_position + Vector3(-4, 1.8, 0)
	camera.look_at(actor.global_position + Vector3.UP)
	camera.reset_physics_interpolation()
	await frames(5)
	support.call("reset_performance")
	await frames(60)
	var near_stats: Dictionary = support.call("native_contact_original_performance")
	check("approaching restores every near-character solve", int(near_stats.budget_skipped) == 0 and int(near_stats.budget_solved) >= 55, {"skipped": near_stats.budget_skipped, "solved": near_stats.budget_solved})
	# Review along the open street; the former south-facing camera sat inside
	# courtyard scenery. Assert unobstructed feet, torso and head before capture.
	var world_layers: Dictionary = main.world.get_script().get_script_constant_map()
	var visual_mask: int = int(world_layers.L_SOLID) | int(world_layers.L_CAMERA) | int(world_layers.L_PLACED)
	var blockers: Array[String] = []
	for height: float in [.2, .85, 1.5]:
		var ray := PhysicsRayQueryParameters3D.create(camera.global_position, actor.global_position + Vector3.UP * height, visual_mask)
		var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty(): blockers.append(str(hit.collider.get_path()))
	check("near character review has clear feet torso and head sightlines", blockers.is_empty(), {"blockers": blockers, "camera": str(camera.global_position), "actor": str(actor.global_position)})
	await shot("mio_near_balanced")
	mode.call("configure", "quality")
	await frames(8)
	await shot("mio_near_quality")
	mode.call("configure", "eco")
	await frames(10)
	support.call("reset_performance")
	await frames(30)
	var eco_near: Dictionary = support.call("native_contact_original_performance")
	check("eco keeps every near-character solve at its30 FPS presentation rate", int(eco_near.budget_skipped) == 0 and int(eco_near.budget_solved) >= 28, {"skipped": eco_near.budget_skipped, "solved": eco_near.budget_solved})
	await shot("mio_near_eco")
	mode.call("configure", "balanced")
	await frames(5)
	camera.look_at(camera.global_position + Vector3(0, 0, 10))
	await frames(5)
	support.call("reset_performance")
	await frames(30)
	var hidden_stats: Dictionary = support.call("native_contact_original_performance")
	check("actual offscreen cloth avoids repeated full work", int(hidden_stats.budget_skipped) >= 20, {"skipped": hidden_stats.budget_skipped, "solved": hidden_stats.budget_solved})
	camera.look_at(actor.global_position + Vector3.UP)
	camera.reset_physics_interpolation()
	await frames(2)
	check("turning back immediately discards the offscreen reuse branch", support.get("last_branch") != "visual_budget")
	# Controlled5 FPS rendering reproduces the minimized-cap clock issue without
	# creating another display or relying on macOS occlusion behavior.
	var original_steps: int = Engine.max_physics_steps_per_frame
	Engine.max_fps = 5
	Engine.max_physics_steps_per_frame = 8
	await frames(10)
	var old_physics_start: int = Engine.get_physics_frames()
	var old_clock_start: int = Time.get_ticks_usec()
	var old_pacing: Dictionary = await sample_frames(30)
	var old_physics_hz: float = (Engine.get_physics_frames() - old_physics_start) * 1000000.0 / (Time.get_ticks_usec() - old_clock_start)
	check("control reproduces lost physics time at5 FPS with old8-step limit", old_physics_hz < 45.0, {"physics_hz": old_physics_hz, "presentation": old_pacing})
	Engine.max_physics_steps_per_frame = int(mode.call("physics_step_budget", 5))
	await frames(10)
	var physics_start: int = Engine.get_physics_frames()
	var clock_start: int = Time.get_ticks_usec()
	var new_pacing: Dictionary = await sample_frames(30)
	var physics_hz: float = (Engine.get_physics_frames() - physics_start) * 1000000.0 / (Time.get_ticks_usec() - clock_start)
	check("5 FPS presentation retains actual60 Hz physics with corrected budget", physics_hz > 55.0 and physics_hz < 65.0, {"physics_hz": physics_hz, "presentation": new_pacing})
	Engine.max_fps = 60
	Engine.max_physics_steps_per_frame = original_steps
	var passed := true
	for row: Dictionary in rows: passed = passed and bool(row.ok)
	var file := FileAccess.open(out.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": rows, "focus_test": "controlled application focus notifications", "physics_hz": Engine.physics_ticks_per_second}, "\t"))
	quit(0 if passed else 1)

extends SceneTree
## Native scene frames for an external neural-rendering experiment. No game integration.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.substr(6)
	if output.is_empty() or OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var warm: int = 0
	while not bool(main.get("loading_ready")) and warm < 1800:
		await process_frame
		warm += 1
	if not bool(main.get("loading_ready")):
		quit(3)
		return
	var state: Node = root.get_node("GameState")
	state.set("clock_paused", true)
	var ui: Node = main.get("ui")
	ui.call("set_hud_visible", false)
	(ui.get("panels") as RefCounted).call("set_cards_visible", false)
	(ui.get("ambient_layer") as CanvasItem).visible = false
	var rig: Node = main.get("rig")
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	var camera: Camera3D = rig.get("cam")
	camera.fov = 50.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var world: Node3D = main.get("world")
	var player: Node3D = main.get("player")
	player.set_physics_process(false)
	player.visible = false
	var catalog: Dictionary = load("res://scripts/tools/shots.gd").VIEWS
	var records: Array[Dictionary] = []
	for scene_id: String in ["bakery_scene_front", "lake_pier"]:
		var view: Dictionary = catalog[scene_id]
		var directory: String = output.path_join(scene_id)
		DirAccess.make_dir_recursive_absolute(directory)
		var is_farm: bool = bool(view.get("farm", false))
		world.call("set_region", "farm" if is_farm else "town")
		var origin: Vector3 = (world.get("farm") as Node3D).global_position if is_farm else Vector3.ZERO
		player.global_position = origin + view.player
		state.set("minute", float(view.time) * 60.0)
		state.set("weather", "sunny")
		world.call("update_time", float(view.time) * 60.0, "sunny", true)
		main.call("_sync_weather")
		main.call("update_npcs", true)
		camera.global_position = origin + view.camera_at
		camera.look_at(origin + view.camera_focus)
		camera.reset_physics_interpolation()
		for settle: int in 60: await process_frame
		var first_render_frame: int = Engine.get_frames_drawn()
		for frame: int in 90:
			# First second is stationary; then a smooth, real 3D camera pan for two seconds.
			var amount: float = smoothstep(0.0, 1.0, maxf(0.0, float(frame - 30) / 59.0))
			camera.global_position = origin + view.camera_at + Vector3(amount * 0.8, 0.0, 0.0)
			camera.look_at(origin + view.camera_focus)
			await process_frame
			await RenderingServer.frame_post_draw
			var status: Error = root.get_texture().get_image().save_png(directory.path_join("%05d.png" % frame))
			if status != OK:
				quit(4)
				return
		var last_render_frame: int = Engine.get_frames_drawn()
		records.append({"scene": scene_id, "frames": 90, "source_fps": 30, "first_render_frame": first_render_frame, "last_render_frame": last_render_frame, "continuous_rendering": last_render_frame - first_render_frame >= 90, "camera_translation_m": 0.8})
		print("CAPTURED ", scene_id, " ", last_render_frame - first_render_frame, " rendered frames")
	var file: FileAccess = FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "scenes": records, "scope": "Native 3D rendering at fixed 30 Hz; PNG capture is not a real-time game benchmark; no virtual display."}, "\t"))
	file.close()
	quit(0)

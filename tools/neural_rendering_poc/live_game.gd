extends SceneTree
## Real-time camera sweep and frame telemetry. Never uses fixed-fps or PNG IO while measuring.
var output: String = ""
var main: Node
var camera: Camera3D
var world: Node3D
var player: Node3D
var state: Node
var marker: Node2D
var view: Dictionary = {}
var origin := Vector3.ZERO
var epoch := 0.0
var stamp := 0
var last_command := ""
var current_phase: Dictionary = {}
var rows: Array[Dictionary] = []
var ready := false
var last_poll := 0.0
var boot := 0.0

class FrameMarker extends Node2D:
	var value: int = 0
	func _draw() -> void:
		var extent: Vector2 = get_viewport_rect().size
		# A5 sync byte plus a 16-bit source frame ID, sampled before neural processing.
		var bits: int = (0xA5 << 16) | (value & 65535)
		for bit: int in 24:
			var lit: bool = ((bits >> (23 - bit)) & 1) == 1
			draw_rect(Rect2(extent.x * (0.05 + bit / 160.0), extent.y * (1.0 - 24.0 / 720.0), extent.x / 160.0, extent.y * 12.0 / 720.0), Color.WHITE if lit else Color.BLACK)

func _initialize() -> void:
	_run.call_deferred()

func _write(name: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(output.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.substr(6)
	if output.is_empty() or OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.title = "Harumachi Neural Live Trial"
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var warm: int = 0
	while not bool(main.get("loading_ready")) and warm < 1800:
		await process_frame
		warm += 1
	if not bool(main.get("loading_ready")):
		quit(3)
		return
	state = root.get_node("GameState")
	state.set("clock_paused", true)
	var ui: Node = main.get("ui")
	ui.call("set_hud_visible", false)
	(ui.get("panels") as RefCounted).call("set_cards_visible", false)
	(ui.get("ambient_layer") as CanvasItem).visible = false
	var rig: Node = main.get("rig")
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	camera = rig.get("cam")
	camera.fov = 50.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world = main.get("world")
	player = main.get("player")
	player.set_physics_process(false)
	player.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)
	marker = FrameMarker.new()
	layer.add_child(marker)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	RenderingServer.frame_post_draw.connect(_drawn)
	_set_scene("bakery_scene_front")
	boot = Time.get_unix_time_from_system()
	ready = true
	_write("game-ready.json", {"engine": Engine.get_version_info().string, "pid": OS.get_process_id(), "size": [root.size.x, root.size.y], "screen": DisplayServer.window_get_current_screen(), "refresh_hz": DisplayServer.screen_get_refresh_rate(), "fps_cap": Engine.max_fps, "vsync": DisplayServer.window_get_vsync_mode(), "fixed_fps": false})
	while ready:
		await process_frame
		var now: float = Time.get_unix_time_from_system()
		if now - boot > 2400:
			quit(5)
			return
		stamp = (stamp + 1) & 65535
		marker.set("value", stamp)
		marker.queue_redraw()
		var movement: float = sin((now - epoch) * TAU / 12.0) * 0.8
		camera.global_position = origin + view.camera_at + Vector3(movement, 0.0, 0.0)
		camera.look_at(origin + view.camera_focus)
		if now - last_poll >= 0.1:
			last_poll = now
			_poll(now)

func _set_scene(scene: String) -> void:
	view = load("res://scripts/tools/shots.gd").VIEWS[scene]
	var is_farm: bool = bool(view.get("farm", false))
	world.call("set_region", "farm" if is_farm else "town")
	origin = (world.get("farm") as Node3D).global_position if is_farm else Vector3.ZERO
	player.global_position = origin + view.player
	state.set("minute", float(view.time) * 60.0)
	state.set("weather", "sunny")
	world.call("update_time", float(view.time) * 60.0, "sunny", true)
	main.call("_sync_weather")
	main.call("update_npcs", true)
	camera.global_position = origin + view.camera_at
	camera.look_at(origin + view.camera_focus)
	camera.reset_physics_interpolation()
	epoch = Time.get_unix_time_from_system()

func _poll(now: float) -> void:
	var path: String = output.path_join("game-command.json")
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and str(parsed.get("id", "")) != last_command:
			var command: Dictionary = parsed
			last_command = str(command.id)
			if command.get("action", "") == "quit":
				ready = false
				quit(0)
				return
			if command.has("scene"): _set_scene(str(command.scene))
			current_phase = command
			rows.clear()
			epoch = float(command.get("start", now))
			_write("game-ack.json", {"id": last_command, "unix": now})
	if not current_phase.is_empty() and now >= float(current_phase.end):
		_write(str(current_phase.id) + "-game.json", {"phase": current_phase, "frames": rows, "fps_cap": Engine.max_fps, "viewport": [root.size.x, root.size.y], "continuous_rendering": rows.size() > 10, "scope": "Real wall-clock render callbacks, no fixed-fps, no PNG IO in sample interval."})
		current_phase = {}
		rows = []

func _drawn() -> void:
	if not ready or current_phase.is_empty(): return
	var now: float = Time.get_unix_time_from_system()
	if now < float(current_phase.start) - 1.0 or now >= float(current_phase.end): return
	rows.append({"stamp": stamp, "unix": now, "tick_usec": Time.get_ticks_usec(), "drawn": Engine.get_frames_drawn(), "gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()), "cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()), "focused": root.has_focus()})

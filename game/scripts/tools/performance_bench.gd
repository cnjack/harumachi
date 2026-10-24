extends SceneTree
## Native runtime frame benchmark for the shipping scene.
##
## One process per variant on purpose: feature toggles, MSAA state and shader
## pipelines never leak between variants. Static views use a fixed camera and
## 300+ rendered frames; walking/running use the real follow rig for six physics
## seconds. The game clock is paused and the HUD hidden; NPCs keep animating.
##
## The cameras come from scripts/tools/environment_visual_qa.gd; the gameplay
## camera (default FOV, spring arm) is reused for the bedroom so the framing is
## one the player actually sees.
##
## User arguments (after `--`):
##   --out=<dir>         required; result.json is written there after every view
##   --views=<a,b,..>    default: street,plaza_day,farm,lake,store_interior,
##                       bedroom,plaza_festival_night
##   --frames=<n>        sampled frames per view (default 300, runner enforces >=300)
##   --settle=<n>        discarded warm frames per view (default 120)
##   --msaa=<1|2|4|8>    MSAA sample count, 1 = off (default 4 = project default)
##   --ablation=<a+b>    no-volumetric-fog, no-ssil, no-ssao, no-glow, msaa0,
##                       no-directional-shadow, hide-props, hide-characters
##   --tag=<name>        label stored in result.json

const DEFAULT_VIEWS: Array[String] = ["street", "plaza_day", "farm", "lake", "store_interior", "bedroom", "plaza_festival_night"]
const DEFAULT_VIEWS_ARG := "street,plaza_day,farm,lake,store_interior,bedroom,plaza_festival_night"
const MONITOR_NAMES: Array[String] = [
	"TIME_FPS", "TIME_PROCESS", "TIME_PHYSICS_PROCESS",
	"RENDER_TOTAL_DRAW_CALLS_IN_FRAME", "RENDER_TOTAL_PRIMITIVES_IN_FRAME",
	"RENDER_TOTAL_OBJECTS_IN_FRAME", "RENDER_VIDEO_MEM_USED",
	"OBJECT_COUNT", "MEMORY_STATIC",
]
const KNOWN_ABLATIONS: Array[String] = ["no-volumetric-fog", "no-ssil", "no-ssao", "no-glow", "msaa0", "no-directional-shadow", "hide-props", "hide-characters"]
## data/festivals.json natsumatsuri: prep_day 16, day 17, 17:00-22:00.
const FESTIVAL_DAY := 17
const FESTIVAL_MINUTE := 1210.0
const NOON := 720.0

var _out := ""
var _tag := "baseline"
var _frames := 300
var _settle := 120
var _msaa_samples := 4
var _ablation: Array[String] = []
var _view_ids: Array[String] = []
var _monitors: Dictionary = {}
var _missing_monitors: Array[String] = []
var _rows: Array[Dictionary] = []
var _constants: Dictionary = {}
var _max_fps_at_start := 0
var _paused_at_start := false


## The scenes the performance review cares about. `source` is a camera id from
## environment_visual_qa.get_views(); `world` is the WorldBuilder region.
static func bench_views() -> Dictionary:
	return {
		"street": {"source": "qa_street_east_lane", "world": "town", "minute": NOON, "label": "商店街东段 · 巷口与路牌"},
		"plaza_day": {"source": "qa_plaza_reverse", "world": "town", "minute": NOON, "label": "广场 · 南侧回望（白天）"},
		"farm": {"source": "qa_farm_entry", "world": "farm", "minute": NOON, "label": "农园 · 入口与全景"},
		"lake": {"source": "qa_lake_pier", "world": "farm", "minute": NOON, "label": "湖边 · 栈桥"},
		"store_interior": {"source": "qa_store_reverse", "world": "town", "minute": 630.0, "label": "商店室内 · 后侧货架与柜台"},
		"bedroom": {"source": "qa_home_bedroom_diorama", "world": "town", "minute": NOON, "label": "卧室 · 游戏机位"},
		"plaza_festival_night": {"source": "qa_plaza_reverse", "world": "town", "minute": FESTIVAL_MINUTE, "day": FESTIVAL_DAY, "label": "广场 · 夏祭夜晚（白天同一机位）"},
		# Moving rows use the real follow camera and the player's own auto_move hook,
		# so the walk loop, NPC roaming and the garment solver run like normal play.
		"street_walk": {"source": "qa_street_east_main", "world": "town", "minute": NOON, "motion": "walk", "physics_seconds": 6.0, "label": "商店街东段 · 玩家步行 6 秒"},
		"street_run": {"source": "qa_street_east_main", "world": "town", "minute": NOON, "motion": "run", "physics_seconds": 6.0, "label": "商店街东段 · 玩家跑步 6 秒"},
	}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _parse_args():
		return
	_resolve_monitors()
	# Measure raw frame cost: never let an engine cap masquerade as a 119-120 FPS plateau.
	_max_fps_at_start = Engine.max_fps
	Engine.max_fps = 0
	# A paused tree would freeze every _process/_physics_process (NPC roaming, cloth,
	# weather), which would make a "static" scene look far cheaper than real play.
	_paused_at_start = paused
	paused = false
	root.msaa_3d = _msaa_enum()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var warm := 0
	while not bool(main.get("loading_ready")) and warm < 3600:
		await process_frame
		warm += 1
	if not bool(main.get("loading_ready")):
		print("BENCH_FAIL loading_ready timeout")
		quit(3)
		return
	var state: Node = root.get_node("GameState")
	state.set("clock_paused", true)
	_prepare_scene(main)
	var views: Dictionary = load("res://scripts/tools/environment_visual_qa.gd").get_views()
	for view_id: String in _view_ids:
		await _run_view(main, view_id, bench_views()[view_id] as Dictionary, views)
		_write_result("complete")
	quit(0)


func _parse_args() -> bool:
	_out = _user_arg("out", "")
	if _out.is_empty():
		printerr("BENCH_FAIL --out= is required")
		quit(2)
		return false
	_tag = _user_arg("tag", "baseline")
	_frames = maxi(10, int(_user_arg("frames", "300")))
	_settle = maxi(10, int(_user_arg("settle", "240")))
	_msaa_samples = int(_user_arg("msaa", "4"))
	if not (_msaa_samples in [1, 2, 4, 8]):
		printerr("BENCH_FAIL --msaa must be 1, 2, 4 or 8 (sample count)")
		quit(2)
		return false
	for view_id: String in _user_arg("views", DEFAULT_VIEWS_ARG).split(","):
		if not view_id.is_empty():
			_view_ids.append(view_id)
	var unknown_views: Array[String] = []
	for view_id: String in _view_ids:
		if not bench_views().has(view_id):
			unknown_views.append(view_id)
	if not unknown_views.is_empty():
		printerr("BENCH_FAIL unknown views: " + ",".join(unknown_views))
		quit(2)
		return false
	for part: String in _user_arg("ablation", "").replace("+", ",").split(","):
		if part.is_empty():
			continue
		if not (part in KNOWN_ABLATIONS):
			printerr("BENCH_FAIL unknown ablation: " + part)
			quit(2)
			return false
		if not _ablation.has(part):
			_ablation.append(part)
	DirAccess.make_dir_recursive_absolute(_out)
	return true


func _user_arg(name: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="):
			return argument.substr(name.length() + 3)
	return fallback


func _msaa_enum() -> int:
	return {1: 0, 2: 1, 4: 2, 8: 3}[_msaa_samples]


## Resolve Performance monitor constants through ClassDB so a monitor that this
## engine snapshot does not expose is reported as missing instead of failing to
## parse the whole script.
func _resolve_monitors() -> void:
	for name: String in MONITOR_NAMES:
		if ClassDB.class_has_integer_constant("Performance", name):
			_monitors[name] = ClassDB.class_get_integer_constant("Performance", name)
		else:
			_missing_monitors.append(name)


func _prepare_scene(main: Node) -> void:
	var ui: Node = main.get("ui") as Node
	ui.call("set_hud_visible", false)
	(ui.get("panels") as RefCounted).call("set_cards_visible", false)
	var ambient: Variant = ui.get("ambient_layer")
	if ambient is CanvasItem:
		(ambient as CanvasItem).visible = false


func _run_view(main: Node, view_id: String, spec: Dictionary, views: Dictionary) -> void:
	var state: Node = root.get_node("GameState")
	var minute: float = float(spec.get("minute", NOON))
	var weather: String = str(spec.get("weather", "sunny"))
	state.set("day", int(spec.get("day", 1)))
	state.set("minute", minute)
	state.set("weather", weather)
	await _place(main, spec, views)
	var world: Node3D = main.get("world") as Node3D
	world.call("update_time", minute, weather, true)
	main.call("_sync_weather")
	main.call("update_npcs", true)
	main.call("sync_festival_state")
	# a festival/date card may have been queued by the clock change
	var ui: Node = main.get("ui") as Node
	ui.call("set_hud_visible", false)
	(ui.get("panels") as RefCounted).call("set_cards_visible", false)
	_apply_ablation(main)
	var settle_frames: int = int(spec.get("settle", _settle))
	for _warm: int in settle_frames:
		await process_frame
	_apply_ablation(main)
	var sample_frames: int = int(spec.get("frames", _frames))
	# Start moving only after warm-up, and measure the same six physics seconds
	# in both builds. A fixed rendered-frame count would cover different streets.
	var start_position: Vector3 = (main.get("player") as Node3D).global_position
	var start_physics_frames: int = Engine.get_physics_frames()
	var physics_ticks: int = roundi(float(spec.get("physics_seconds", 0.0)) * Engine.physics_ticks_per_second)
	if spec.has("motion"): main.get("player").set("auto_move", Vector3(-1.0, 0.0, 0.0))
	var row: Dictionary = await _sample(main, sample_frames, physics_ticks)
	if row.is_empty(): return
	main.get("player").set("auto_move", Vector3.ZERO)
	row["view"] = view_id
	row["label"] = str(spec.get("label", ""))
	row["world"] = str(spec.get("world", "town"))
	row["minute"] = minute
	row["weather"] = weather
	row["day"] = int(spec.get("day", 1))
	row["source_view"] = str(spec.get("source", ""))
	row["motion"] = str(spec.get("motion", ""))
	row["player_travel_m"] = snappedf(start_position.distance_to((main.get("player") as Node3D).global_position), .001)
	row["player_start"] = str(start_position)
	row["player_end"] = str((main.get("player") as Node3D).global_position)
	row["tree_paused"] = paused
	row["player_physics_processing"] = (main.get("player") as Node).is_physics_processing()
	row["player_frozen"] = bool((main.get("player") as Node).get("frozen"))
	row["player_auto_move"] = str((main.get("player") as Node).get("auto_move"))
	row["player_velocity"] = str((main.get("player") as CharacterBody3D).velocity)
	row["slide_collisions"] = (main.get("player") as CharacterBody3D).get_slide_collision_count()
	row["physics_frames"] = Engine.get_physics_frames() - start_physics_frames
	row["settle_frames"] = settle_frames
	_rows.append(row)
	# Readback and PNG compression stay outside the measured interval.
	await RenderingServer.frame_post_draw
	var shot: Image = root.get_texture().get_image()
	shot.save_png(_out.path_join(view_id + ".png"))
	row["rendered_image_size"] = [shot.get_width(), shot.get_height()]
	print("BENCH_VIEW %s median=%.2fms p95=%.2fms max=%.2fms fps=%.1f" % [
		view_id, float(row["median_ms"]), float(row["p95_ms"]), float(row["max_ms"]), float(row["fps_median"])])


func _place(main: Node, spec: Dictionary, views: Dictionary) -> void:
	var state: Node = root.get_node("GameState")
	var world: Node3D = main.get("world") as Node3D
	var player_node: Node3D = main.get("player") as Node3D
	var rig: Node = main.get("rig") as Node
	var view: Dictionary = views[str(spec["source"])]
	var region: String = str(spec.get("world", "town"))
	player_node.set("auto_move", Vector3.ZERO)
	if bool(main.get("in_room")):
		main.set("in_room", false)
		main.set("room_kind", "")
		state.set("player_in_room", false)
		world.call("set_indoor_look", false)
	world.call("set_region", region)
	var origin := Vector3.ZERO
	if bool(view.get("farm", false)):
		origin = _script_constant("res://scripts/world/farm_builder.gd", "ORIGIN") as Vector3
	if view.has("interior"):
		await main.call("enter_interior", str(view["interior"]))
		var interior_spec: Dictionary = (load("res://scripts/world/interior_builder.gd") as GDScript).call("spec_for", str(view["interior"]))
		origin = interior_spec.origin
		player_node.global_position = origin + (view.get("at", Vector3(0, 0.05, 1.8)) as Vector3)
		rig.process_mode = Node.PROCESS_MODE_DISABLED
		_aim(rig, origin + (view["inside_camera"] as Vector3), origin + (view["inside_focus"] as Vector3))
	elif spec.has("motion"):
		player_node.global_position = origin + (view["player"] as Vector3)
		player_node.call("set_facing", -PI / 2.0)
		rig.set("fixed", false)
		rig.set("collide", true)
		rig.set("yaw", 90.0)
		rig.set("pitch", 18.0)
		rig.set("dist", 8.0)
		rig.call("snap")
		rig.process_mode = Node.PROCESS_MODE_INHERIT
		player_node.set("auto_run", str(spec.get("motion", "walk")) == "run")
	elif view.has("house"):
		# the diorama camera the player actually plays with
		main.call("_put_in_room", (_script_constant("res://scripts/world/house_builder.gd", "ORIGIN") as Vector3) + (view["house"] as Vector3) + Vector3(0, 0.05, 0))
		player_node.call("set_facing", deg_to_rad(float(view.get("face", 180.0))))
		rig.set("pitch", float(view.get("pitch", 50.0)))
		rig.set("dist", float(view.get("dist", 9.2)))
		rig.call("snap")
		rig.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		player_node.global_position = origin + (view["player"] as Vector3)
		player_node.call("set_facing", deg_to_rad(float(view.get("face", 180.0))))
		rig.process_mode = Node.PROCESS_MODE_DISABLED
		_aim(rig, origin + (view["camera_at"] as Vector3), origin + (view["camera_focus"] as Vector3))
	await process_frame


## Project scripts are loaded lazily: a `--script` SceneTree entry point compiles
## before the autoloads exist, so referencing a class_name would fail to compile.
func _script_constant(path: String, name: String) -> Variant:
	var key: String = path + "::" + name
	if not _constants.has(key):
		var script: GDScript = load(path) as GDScript
		_constants[key] = script.get_script_constant_map().get(name)
	return _constants[key]


func _aim(rig: Node, at: Vector3, focus: Vector3) -> void:
	var cam: Camera3D = rig.get("cam") as Camera3D
	cam.global_position = at
	cam.look_at(focus, Vector3.UP)
	cam.reset_physics_interpolation()


func _apply_ablation(main: Node) -> void:
	if _ablation.is_empty():
		return
	var world: Node3D = main.get("world") as Node3D
	var env: Environment = world.get("env") as Environment
	var sun: DirectionalLight3D = world.get("sun") as DirectionalLight3D
	for name: String in _ablation:
		match name:
			"no-volumetric-fog":
				if env: env.volumetric_fog_enabled = false
			"no-ssil":
				if env: env.ssil_enabled = false
			"no-ssao":
				if env: env.ssao_enabled = false
			"no-glow":
				if env: env.glow_enabled = false
			"msaa0":
				root.msaa_3d = Viewport.MSAA_DISABLED
			"no-directional-shadow":
				if sun: sun.shadow_enabled = false
			"hide-props":
				_set_models_visible(world, false)
			"hide-characters":
				_set_characters_visible(main, false)


## Every node WorldBuilder.spawn() created carries a model_id meta: trees, stalls,
## houses, props. Hiding them is the "props container" ablation for this project.
func _set_models_visible(world: Node3D, on: bool) -> void:
	for node: Node in world.find_children("*", "", true, false):
		if node.has_meta("model_id"):
			(node as Node3D).visible = on


func _set_characters_visible(main: Node, on: bool) -> void:
	var npcs: Dictionary = main.get("npcs") as Dictionary
	for id: String in npcs:
		var npc: Node3D = npcs[id] as Node3D
		npc.visible = on
	var player_node: Node3D = main.get("player") as Node3D
	player_node.visible = on


func _sample(main: Node, frames: int, physics_ticks: int = 0) -> Dictionary:
	var intervals: Array[float] = []
	var render_cpu: Array[float] = []
	var render_gpu: Array[float] = []
	var first_render_frame: int = Engine.get_frames_drawn()
	var actor_before: Dictionary = _actor_metrics(main)
	var values: Dictionary = {}
	for name: String in MONITOR_NAMES:
		values[name] = [] if _monitors.has(name) else null
	var trace: Array = []
	var last: int = Time.get_ticks_usec()
	var process_index: int = int(_monitors.get("TIME_PROCESS", -1))
	var physics_index: int = int(_monitors.get("TIME_PHYSICS_PROCESS", -1))
	var first_physics_frame: int = Engine.get_physics_frames()
	var started: int = last
	var index := 0
	while (index < frames if physics_ticks == 0 else Engine.get_physics_frames() - first_physics_frame < physics_ticks):
		await process_frame
		if physics_ticks > 0 and Time.get_ticks_usec() - started > 30_000_000:
			printerr("BENCH_FAIL motion did not complete six physics seconds")
			quit(4)
			return {}
		var now: int = Time.get_ticks_usec()
		var interval_ms: float = float(now - last) / 1000.0
		intervals.append(interval_ms)
		last = now
		render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		if process_index >= 0:
			trace.append([snappedf(interval_ms, .001), snappedf(Performance.get_monitor(process_index) * 1000.0, .001),
					snappedf(Performance.get_monitor(physics_index) * 1000.0, .001)])
		for name: String in MONITOR_NAMES:
			if not _monitors.has(name):
				continue
			(values[name] as Array).append(Performance.get_monitor(int(_monitors[name])))
		if _ablation.has("hide-props") or _ablation.has("hide-characters"):
			if (index + 1) % 60 == 0:
				_apply_ablation(main)
		index += 1
	var summary: Dictionary = _summarize(intervals, values)
	summary["trace"] = trace
	summary["render_cpu_ms"] = _time_summary(render_cpu)
	summary["render_gpu_ms"] = _time_summary(render_gpu)
	summary["render_frame_start"] = first_render_frame
	summary["render_frame_end"] = Engine.get_frames_drawn()
	summary["rendered_frames"] = Engine.get_frames_drawn() - first_render_frame
	var actor_after: Dictionary = _actor_metrics(main)
	for key: String in actor_after:
		var cost: Dictionary = actor_after[key]
		var before: Dictionary = actor_before[key]
		cost["measured_updates"] = int(cost.updates) - int(before.updates)
		cost["ms_per_frame"] = float(int(cost.total_usec) - int(before.total_usec)) / (1000.0 * intervals.size())
		var phases: Dictionary = {}
		for counter: String in cost.get("counters", {}):
			phases[counter.trim_suffix("_usec")] = float(int(cost.counters[counter]) - int(before.counters[counter])) / (1000.0 * intervals.size())
		if not phases.is_empty(): cost["phase_ms_per_frame"] = phases
		cost.erase("counters")
	summary["actor_modifiers"] = actor_after
	return summary


func _actor_metrics(main: Node) -> Dictionary:
	var result: Dictionary = {}
	var actors: Dictionary = (main.get("npcs") as Dictionary).duplicate()
	actors["player"] = main.get("player")
	for id: String in actors:
		var actor: Node3D = actors[id] as Node3D
		for modifier_name: String in ["CharacterGarmentSupport", "CharacterFootSupport"]:
			var modifier: Node = actor.find_child(modifier_name, true, false)
			if modifier == null: continue
			result[id + "/" + modifier_name] = {"total_usec": int(modifier.get("total_usec")), "updates": int(modifier.get("updates")), "visible": actor.is_visible_in_tree()}
			if modifier_name == "CharacterGarmentSupport":
				var counters: Dictionary = {}
				for counter: String in ["total_bounds_usec", "total_tree_build_usec", "total_query_usec", "skin_total_usec"]:
					counters[counter] = int(modifier.get(counter))
				result[id + "/" + modifier_name]["counters"] = counters
				result[id + "/" + modifier_name]["native_geometry"] = bool(modifier.get("native_geometry_enabled"))
	return result


func _time_summary(values: Array[float]) -> Dictionary:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return {"median": sorted[sorted.size() / 2], "p95": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], "max": sorted.back(), "valid": sorted[sorted.size() / 2] > 0.0}


func _summarize(intervals: Array[float], values: Dictionary) -> Dictionary:
	var sorted_ms: Array[float] = intervals.duplicate()
	sorted_ms.sort()
	var count: int = sorted_ms.size()
	var total := 0.0
	for value: float in sorted_ms:
		total += value
	var monitors: Dictionary = {}
	for name: String in MONITOR_NAMES:
		var raw: Variant = values.get(name)
		if raw == null or (raw as Array).is_empty():
			continue
		var numbers: Array[float] = []
		for entry: Variant in (raw as Array):
			numbers.append(float(entry))
		numbers.sort()
		monitors[name] = {
			"median": numbers[numbers.size() / 2],
			"p95": numbers[mini(numbers.size() - 1, int(numbers.size() * 0.95))],
			"min": numbers[0],
			"max": numbers[numbers.size() - 1],
		}
	return {
		"frames": count,
		"median_ms": sorted_ms[count / 2],
		"p95_ms": sorted_ms[mini(count - 1, int(count * 0.95))],
		"min_ms": sorted_ms[0],
		"max_ms": sorted_ms[count - 1],
		"mean_ms": total / float(count),
		"fps_median": 1000.0 / sorted_ms[count / 2],
		"fps_mean": 1000.0 * float(count) / total,
		"p95_over_16_67ms": sorted_ms[mini(count - 1, int(count * 0.95))] > 16.67,
		"monitors": monitors,
	}


func _write_result(status: String) -> void:
	var payload := {
		"status": status,
		"engine": Engine.get_version_info().string,
		"tag": _tag,
		"os": OS.get_name(),
		"os_version": OS.get_version(),
		"cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"gpu_api": RenderingServer.get_video_adapter_api_version(),
		"rendering_method": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		# A platform override can select Metal despite a Vulkan project default.
		# The runner captures the actual driver from the engine startup banner.
		"rendering_driver_setting": str(ProjectSettings.get_setting("rendering/rendering_device/driver", "")),
		"viewport_size": get_root().size,
		"viewport_visible_rect": get_root().get_visible_rect().size,
		"window_size": DisplayServer.window_get_size(),
		"screen_scale": DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen()),
		"screen_size": DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()),
		"window_vsync_mode": DisplayServer.window_get_vsync_mode(),
		"screen": DisplayServer.window_get_current_screen(),
		"screen_count": DisplayServer.get_screen_count(),
		"msaa_requested_samples": _msaa_samples,
		"msaa_actual": get_root().msaa_3d,
		"engine_max_fps": Engine.max_fps,
		"engine_max_fps_at_start": _max_fps_at_start,
		"tree_paused_at_start": _paused_at_start,
		"tree_paused": paused,
		"screen_refresh_rate": DisplayServer.screen_get_refresh_rate(),
		"window_mode": DisplayServer.window_get_mode(),
		"ablations": _ablation,
		"frames_requested": _frames,
		"settle_frames": _settle,
		"monitors_missing": _missing_monitors,
		"views": _view_ids,
		"samples": _rows,
	}
	var file: FileAccess = FileAccess.open(_out.path_join("result.json"), FileAccess.WRITE)
	if file == null:
		printerr("BENCH_FAIL cannot write result.json")
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

extends Node
## Real game scenes, reversible material/lighting overrides and a four-way comparison.
const SPOTS: Array[Dictionary] = [
	{"id":"bakery", "label":"面包房门前", "region":"town", "at":Vector3(-24,.1,-12), "camera":Vector3(-28.5,3.1,-8.8), "focus":Vector3(-24,2.85,-19.3)},
	{"id":"lake", "label":"湖畔木栈桥", "region":"farm", "at":Vector3(94,.2,46), "camera":Vector3(89.8,2.1,48.7), "focus":Vector3(96,.9,35)},
	{"id":"bakery_joinery", "label":"二楼窗框与檐口", "region":"town", "at":Vector3(-24,.1,-12), "camera":Vector3(-24.1,4.3,-12.4), "focus":Vector3(-24.1,4.3,-16.4)},
	{"id":"bakery_entry", "label":"布篷与底层橱窗", "region":"town", "at":Vector3(-24,.1,-12), "camera":Vector3(-26.4,2.8,-13.8), "focus":Vector3(-24,1.9,-16.1)},
	{"id":"lake_grass", "label":"湖畔草叶近景", "region":"farm", "at":Vector3(94,.2,46), "camera":Vector3(92,.75,45.4), "focus":Vector3(91,.22,42.5)},
	{"id":"bakery_cedar", "label":"杉树冠层近景", "region":"town", "at":Vector3(-24,.1,-12), "camera":Vector3(-28,4.8,-23), "focus":Vector3(-31.35,6.0,-31)}
]
const CONDITIONS: Array[Dictionary] = [
	{"id":"morning", "label":"晴晨 08:00", "minute":480.0, "weather":"sunny"},
	{"id":"noon", "label":"晴午 12:00", "minute":720.0, "weather":"sunny"},
	{"id":"overcast", "label":"阴天 12:00", "minute":720.0, "weather":"cloudy"},
	{"id":"rain", "label":"雨天 15:00", "minute":900.0, "weather":"rain"},
	{"id":"sunset", "label":"夕照 17:20", "minute":1040.0, "weather":"sunny"},
	{"id":"night", "label":"夜晚 21:00", "minute":1260.0, "weather":"sunny"}
]
const MODES: Array[String] = ["baseline", "material", "lighting", "combined"]
var main: Node3D
var world: WorldBuilder
var cam: Camera3D
var output: String
var rows: Array[Dictionary] = []
var baseline_env: Environment
var scene_index: int = 0
var condition_index: int = 1
var mode_index: int = 0
var caption: Label
var capture_mode: bool = false
var geometry: String
var orbit_degrees: float = 0.0
var materials: RefCounted = preload("res://scripts/tools/material_light_poc_materials.gd").new()
var lighting: RefCounted = preload("res://scripts/tools/material_light_poc_lighting.gd").new()
var landscape: RefCounted = preload("res://scripts/tools/material_light_poc_landscape.gd").new()
var bridge: RefCounted = preload("res://scripts/tools/material_light_poc_geometry.gd").new()
var shapes: RefCounted = preload("res://scripts/tools/material_light_poc_shapes.gd").new()
var bakery_guard: RefCounted = preload("res://scripts/tools/material_light_poc_bakery_guard.gd").new()

func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if OS.get_cmdline_user_args().has("--benchmark-uncapped"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = get_parent() as Node3D
	world = main.get("world") as WorldBuilder
	cam = (main.get("rig") as CameraRig).cam
	output = _arg("poc-out", "")
	orbit_degrees = clampf(float(_arg("poc-orbit", "0")), -35.0, 35.0)
	capture_mode = not output.is_empty()
	main.get("ui").call("set_hud_visible", false)
	(main.get("ui").get("panels") as RefCounted).call("set_cards_visible", false)
	for layer: Node in main.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	(main.get("player") as Node3D).visible = false
	for actor: Node3D in (main.get("npcs") as Dictionary).values(): actor.visible = false
	baseline_env = world.env.duplicate(true) as Environment
	geometry = MaterialChoiceProfile._geometry_signature(world)
	bakery_guard.prepare(world)
	materials.prepare(world)
	lighting.prepare(world)
	landscape.prepare(world, self)
	bridge.prepare(world)
	shapes.prepare(world,self)
	if capture_mode:
		DirAccess.make_dir_recursive_absolute(output)
		_inventory()
		_write("material-bindings.json", materials.report)
		_capture.call_deferred()
	else:
		mode_index = 3
		_build_controls()
		_apply()

func _arg(key: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + key + "="): return argument.get_slice("=", 1)
	return fallback

func release_candidates() -> void:
	# Let rendering dependencies switch back before releasing the shared candidate
	# meshes/materials. Metal otherwise reports stale material RIDs during teardown.
	mode_index = 0
	_apply()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

func _apply() -> void:
	var spot: Dictionary = SPOTS[scene_index]
	var condition: Dictionary = CONDITIONS[condition_index]
	var state: Node = get_tree().root.get_node("GameState")
	state.set("minute", condition.minute)
	state.set("weather", condition.weather)
	state.set("clock_paused", true)
	state.set("player_in_room", false)
	main.set("in_room", false)
	world.set_indoor_look(false)
	world.set_region(spot.region)
	var origin: Vector3 = FarmBuilder.ORIGIN if spot.region == "farm" else Vector3.ZERO
	(main.get("player") as Node3D).global_position = origin + spot.at
	(main.get("rig") as Node3D).global_position = origin + spot.at
	cam.fov = 48.0
	cam.global_position = origin + spot.focus + ((spot.camera as Vector3) - (spot.focus as Vector3)).rotated(Vector3.UP, deg_to_rad(orbit_degrees))
	cam.look_at(origin + spot.focus)
	cam.reset_physics_interpolation()
	world.env = baseline_env.duplicate(true) as Environment
	world.world_env.environment = world.env
	world.sky_mat = world.env.sky.sky_material as ShaderMaterial
	world.update_time(condition.minute, condition.weather, true)
	# Main is frozen: explicitly refresh the same weather uniforms as EnvironmentLife.tick.
	var weather: Dictionary = EnvironmentLife.WEATHER[condition.weather]
	world.sky_mat.set_shader_parameter("cloud_cover", weather.cloud_cover)
	world.sky_mat.set_shader_parameter("sun_visibility", weather.sun_visibility)
	world.sky_mat.set_shader_parameter("sun_direction", world.sun.global_basis.z.normalized())
	world.farm.water_mat.set_shader_parameter("rain_amount", weather.rain)
	world.farm.water_mat.set_shader_parameter("wave_strength", weather.wind)
	RenderingServer.global_shader_parameter_set("wind_strength", float(weather.wind))
	bridge.apply(mode_index == 1 or mode_index == 3)
	materials.apply(mode_index == 1 or mode_index == 3)
	landscape.apply(mode_index == 1 or mode_index == 3, spot.region, condition.id == "night")
	shapes.apply(mode_index == 1 or mode_index == 3, condition,spot.region)
	lighting.apply(world, condition, spot.region, mode_index == 2 or mode_index == 3)
	materials.sync_water_environment(world, mode_index == 2 or mode_index == 3)
	# Their normal per-frame callback is disabled together with Main for repeatable views.
	for mountains: Node in world.find_children("DistantMountains", "", true, false):
		mountains.call("_update_look")
	(main.get("weather_fx") as WeatherFX).set_weather(condition.weather, false)
	(main.get("weather_fx") as WeatherFX).rig = cam
	(main.get("weather_fx") as WeatherFX)._update_origin()
	if bakery_guard.required and spot.region == "town":
		assert(bakery_guard.inspect().passed,"Bakery source geometry, paint or visibility was lost")
	if caption:
		caption.text = "%s    %s    %s\n1/2 全景 · 3 窗框 · 4 布篷 · 5 草叶 · 6 杉树   ←/→ 时段   空格 对照   Q/E 转动   R 复位   Esc 退出" % [spot.label, condition.label, MODES[mode_index]]

func _capture() -> void:
	var sample_frames: int = maxi(60, int(_arg("poc-sample-frames", "60")))
	var chosen_scenes: PackedStringArray = _arg("poc-scenes", "bakery,lake").split(",")
	var chosen_conditions: PackedStringArray = _arg("poc-conditions", "noon,sunset").split(",")
	var chosen_modes: PackedStringArray = _arg("poc-modes", "baseline").split(",")
	for spot_id: int in range(SPOTS.size()):
		if not SPOTS[spot_id].id in chosen_scenes: continue
		scene_index = spot_id
		for condition_id: int in range(CONDITIONS.size()):
			if not CONDITIONS[condition_id].id in chosen_conditions: continue
			condition_index = condition_id
			for look_id: int in range(MODES.size()):
				if not MODES[look_id] in chosen_modes: continue
				mode_index = look_id
				_apply()
				for settle: int in range(45): await RenderingServer.frame_post_draw
				var frame_start: int = Engine.get_frames_drawn()
				var started: int = Time.get_ticks_usec()
				var gpu_ms: Array[float] = []
				for frame: int in range(sample_frames):
					await RenderingServer.frame_post_draw
					gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
				var elapsed: float = float(Time.get_ticks_usec() - started) / 1000000.0
				gpu_ms.sort()
				var name_value: String = "%s_%s_%s.png" % [SPOTS[scene_index].id, CONDITIONS[condition_index].id, MODES[mode_index]]
				var picture: Image = get_viewport().get_texture().get_image()
				var error: Error = picture.save_png(output.path_join(name_value))
				if error != OK:
					get_tree().call_deferred("finish_review",4)
					return
				rows.append({"file":name_value, "scene":SPOTS[scene_index].id, "condition":CONDITIONS[condition_index], "mode":MODES[mode_index], "frames":Engine.get_frames_drawn()-frame_start, "seconds":elapsed, "fps":float(sample_frames)/elapsed, "size":[picture.get_width(),picture.get_height()], "sun_energy":world.sun.light_energy, "ambient":world.env.ambient_light_energy, "fps_limit":Engine.max_fps, "vsync":DisplayServer.window_get_vsync_mode(), "gpu_median_ms":gpu_ms[int(sample_frames * .5)], "gpu_p95_ms":gpu_ms[int(sample_frames * .95)], "sky_dusk":world.sky_mat.get_shader_parameter("dusk_w"), "sky_night":world.sky_mat.get_shader_parameter("night_w")})
				rows.back()["orbit_degrees"] = orbit_degrees
				rows.back()["candidate_bridge"] = bridge.enabled
				rows.back()["bakery_details"] = bakery_guard.inspect() if SPOTS[scene_index].region == "town" else {"evaluated":false}
				var unchanged: bool = geometry == MaterialChoiceProfile._geometry_signature(world)
				var restored: bool = geometry == shapes.source_signature(world, bridge)
				assert(restored, "Documented mesh candidates must restore all source geometry and collisions")
				_write("manifest.json", {"engine":Engine.get_version_info(), "renderer":RenderingServer.get_current_rendering_method(), "geometry_unchanged":unchanged, "source_geometry_and_collisions_preserved":restored, "bridge_candidate":bridge.report, "sky_candidate_sha256":lighting.sky_shader.code.sha256_text(), "water_candidate_sha256":materials.water_candidate.shader.code.sha256_text(), "candidate_grass_clumps":landscape.clumps, "landscape_bindings":landscape.bindings.size(), "bakery_source_required":bakery_guard.required, "screens":DisplayServer.get_screen_count(), "shots":rows})
				print("POC_CAPTURE ", name_value)
				_write("shape-bindings.json",shapes.report)
	get_tree().call_deferred("finish_review",0)

func _inventory() -> void:
	var surfaces: Array[Dictionary] = []
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(world):
		if mesh.mesh == null: continue
		for surface_index: int in range(mesh.mesh.get_surface_count()):
			var mat: Material = mesh.get_active_material(surface_index)
			if mat == null: continue
			var shader: ShaderMaterial = mat as ShaderMaterial
			surfaces.append({"node":str(world.get_path_to(mesh)), "surface":surface_index, "material":mat.resource_name, "shader":shader.shader.resource_path if shader and shader.shader else "StandardMaterial3D", "position":str(mesh.global_position), "visible":mesh.is_visible_in_tree()})
	_write("materials.json", surfaces)

func _write(name_value: String, value: Variant) -> void:
	var file: FileAccess = FileAccess.open(output.path_join(name_value), FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))

func _build_controls() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(20,20)
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_color_override("font_outline_color", Color(.04,.06,.12))
	caption.add_theme_constant_override("outline_size", 6)
	caption.add_theme_font_size_override("font_size", 20)
	layer.add_child(caption)

func _unhandled_key_input(event: InputEvent) -> void:
	if capture_mode or not event.is_pressed() or event.is_echo(): return
	var key: InputEventKey = event as InputEventKey
	if key == null: return
	match key.keycode:
		KEY_1: scene_index = 0
		KEY_2: scene_index = 1
		KEY_3: scene_index = 2
		KEY_4: scene_index = 3
		KEY_5: scene_index = 4
		KEY_6: scene_index = 5
		KEY_RIGHT: condition_index = (condition_index + 1) % CONDITIONS.size()
		KEY_LEFT: condition_index = posmod(condition_index - 1, CONDITIONS.size())
		KEY_SPACE: mode_index = (mode_index + 1) % MODES.size()
		KEY_Q: orbit_degrees = clampf(orbit_degrees - 5.0, -35.0, 35.0)
		KEY_E: orbit_degrees = clampf(orbit_degrees + 5.0, -35.0, 35.0)
		KEY_R: orbit_degrees = 0.0
		KEY_ESCAPE:
			get_tree().call_deferred("finish_review",0)
			return
		_: return
	_apply()

extends RefCounted
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("PERFORMANCE_MODE", label, ok, detail)

func run() -> void:
	var mode: Node = t.get_tree().root.get_node_or_null("PerformanceMode")
	check("shipping runtime offers persistent presentation budgets", mode != null)
	if mode == null: return
	var grass_source: GDScript = load("res://scripts/world/grass_field.gd")
	var original_profile: String = str(mode.get("profile"))
	var viewport: Window = t.get_tree().root
	var original_ui_scale: float = viewport.content_scale_factor
	var original_physics: int = Engine.physics_ticks_per_second
	var original_settings: Dictionary = GameState.settings.duplicate(true)
	var original_indoor: bool = main.world.indoor
	var original_kind: String = main.world.public_interior_kind
	for id: String in ["quality", "balanced", "eco"]:
		mode.call("configure", id)
		var config: Dictionary = mode.get_script().get_script_constant_map().PROFILES[id]
		check(id + " changes only 3D scale and keeps UI and physics intact", is_equal_approx(viewport.scaling_3d_scale, float(config.scale)) and viewport.content_scale_factor == original_ui_scale and Engine.physics_ticks_per_second == original_physics)
		check(id + " sets requested MSAA and shadow atlas", int(viewport.msaa_3d) == int(config.msaa) and int(mode.call("snapshot").shadow_size) == int(config.shadow))
		check(id + " caps foreground pause background and minimized separately", mode.call("target_fps", false, false, false) == config.fps and mode.call("target_fps", false, false, true) == 30 and mode.call("target_fps", true, false, false) == 10 and mode.call("target_fps", true, true, true) == 5)
		main.world.set_indoor_look(true)
		check(id + " survives actual indoor lighting changes", main.world.env.ssil_enabled == (id == "quality" and not OS.has_feature("web")) and main.world.env.volumetric_fog_enabled == (id != "eco" and not OS.has_feature("web")) and is_equal_approx(main.world.sun.directional_shadow_max_distance, float(config.shadow_in)))
		main.world.set_indoor_look(false)
		check(id + " restores outdoor lighting and preserves sky bloom palette", not main.world.env.ssil_enabled and not main.world.env.volumetric_fog_enabled and main.world.env.glow_enabled and is_equal_approx(main.world.sun.directional_shadow_max_distance, float(config.shadow_out)))
	check("minimized cap permits all60 physics ticks and restores normal catchup budget", int(mode.call("physics_step_budget", 5)) >= 12 and int(mode.call("physics_step_budget", 60)) == Engine.max_physics_steps_per_frame)
	mode.call("configure", "broken-value")
	check("unknown saved quality falls back to balanced", mode.get("profile") == "balanced")
	GameState.settings["graphics_profile"] = "eco"
	GameState.save_settings()
	GameState.settings["graphics_profile"] = "quality"
	GameState.load_settings()
	check("graphics preference survives actual settings database reload", GameState.settings.graphics_profile == "eco")
	var box := VBoxContainer.new()
	t.add_child(box)
	GameUI.build_settings_rows(box)
	var choice: OptionButton = box.find_child("GraphicsProfile", true, false) as OptionButton
	check("shared title and pause settings expose all three profiles", choice != null and choice.item_count == 3 and choice.selected == 2)
	if choice != null: choice.item_selected.emit(1)
	check("settings selection writes the requested profile", SaveDB.load_settings().get("graphics_profile", "") == "balanced")
	box.queue_free()
	var geometry_ok := true
	var endpoints_ok := true
	for style: String in GrassField.STYLES:
		for variant: int in 3:
			var meshes: Array = grass_source.budget_meshes(style, variant)
			var count: int = int(GrassField.STYLES[style].n)
			var full: Array = (meshes[0] as ArrayMesh).surface_get_arrays(0)
			for level: int in [1, 2]:
				var arrays: Array = (meshes[level] as ArrayMesh).surface_get_arrays(0)
				geometry_ok = geometry_ok and arrays[Mesh.ARRAY_VERTEX] == full[Mesh.ARRAY_VERTEX] and arrays[Mesh.ARRAY_TEX_UV] == full[Mesh.ARRAY_TEX_UV] and arrays[Mesh.ARRAY_COLOR] == full[Mesh.ARRAY_COLOR]
				# Repacking octahedral normals can round by one16-bit step.
				for vertex: int in arrays[Mesh.ARRAY_NORMAL].size():
					geometry_ok = geometry_ok and arrays[Mesh.ARRAY_NORMAL][vertex].distance_to(full[Mesh.ARRAY_NORMAL][vertex]) <= .0001
				geometry_ok = geometry_ok and arrays[Mesh.ARRAY_INDEX].size() == count * (9 if level == 1 else 3)
			var source: PackedInt32Array = full[Mesh.ARRAY_INDEX]
			var far: PackedInt32Array = (meshes[2] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			for blade: int in count:
				endpoints_ok = endpoints_ok and far[blade * 3] == source[blade * 15] and far[blade * 3 + 1] == source[blade * 15 + 1] and far[blade * 3 + 2] == source[blade * 15 + 14]
	check("all15 distant grass variants preserve vertices UV colours and packed-normal precision", geometry_ok)
	check("simplified grass keeps both roots and every blade tip", endpoints_ok)
	var grass := MultiMeshInstance3D.new()
	grass.multimesh = MultiMesh.new()
	grass.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var demo_meshes: Array = grass_source.budget_meshes("lawn", 0)
	grass.multimesh.mesh = demo_meshes[0]
	grass.multimesh.instance_count = 1
	grass.visibility_range_end = 38.0
	grass.visibility_range_end_margin = 6.0
	grass.set_meta("budget_grass_meshes", demo_meshes)
	grass.set_meta("budget_grass_bounds", grass.multimesh.get_aabb())
	t.add_child(grass)
	mode.call("register_foliage", grass)
	var camera := Camera3D.new()
	t.add_child(camera)
	mode.call("configure", "balanced")
	for distance: float in [2.0, 24.0, 40.0]:
		camera.position = Vector3(0, 0, distance)
		mode.call("_apply_foliage", grass, camera)
		var expected: int = 0 if distance == 2.0 else (1 if distance == 24.0 else 2)
		check("grass switches actual mesh at distance " + str(distance), grass.multimesh.mesh == demo_meshes[expected] and grass.multimesh.instance_count == 1)
	var previous_camera: Camera3D = viewport.get_camera_3d()
	camera.make_current()
	mode.call("refresh_foliage", true)
	camera.fov = 30.0
	mode.call("refresh_foliage", false)
	var zoom_restores: bool = grass.multimesh.mesh == demo_meshes[0]
	camera.fov = 75.0
	mode.call("refresh_foliage", false)
	check("stationary camera zoom refreshes and restores the actual grass mesh", zoom_restores and grass.multimesh.mesh == demo_meshes[2])
	if previous_camera != null: previous_camera.make_current()
	var old_locks: Dictionary = GameState._ui_locks.duplicate()
	GameState._ui_locks.clear()
	grass.global_position = main.rig.cam.global_position + Vector3(0, 0, 60)
	mode.call("_apply_foliage", grass, main.rig.cam)
	var simplified_before_photo: bool = grass.multimesh.mesh == demo_meshes[2]
	main.photo.toggle()
	var immediate_photo_detail: bool = main.photo.active and grass.multimesh.mesh == demo_meshes[0]
	main.photo.finish()
	check("photo entry restores grass detail synchronously and leaving restores its budget", simplified_before_photo and immediate_photo_detail and grass.multimesh.mesh == demo_meshes[2])
	GameState._ui_locks = old_locks
	mode.call("configure", "quality")
	check("returning to quality restores original grass mesh and distance", grass.multimesh.mesh == demo_meshes[0] and grass.visibility_range_end == 38.0)
	var policy: GDScript = load("res://scripts/performance/character_visual_budget.gd")
	check("nearby and interacting actors always use complete current-pose solves", policy.classify("balanced", 3.0, true, false, false) == 0.0 and policy.classify("eco", 50.0, false, true, false) == 0.0)
	check("distant and offscreen cloth has explicit bounded update rates", is_equal_approx(policy.classify("balanced", 24.0, true, false, false), 1.0 / 30.0) and is_equal_approx(policy.classify("eco", 24.0, true, false, false), 1.0 / 15.0) and policy.classify("balanced", 24.0, false, false, false) == 1.0)
	camera.position = Vector3(0, 1, 8)
	camera.look_at(Vector3(0, 1, 0))
	check("frustum policy retains visible body and rejects far behind camera", policy.on_screen(camera, Vector3(0, 1, 0)) and not policy.on_screen(camera, Vector3(0, 1, 25)))
	grass.queue_free()
	camera.queue_free()
	GameState.settings = original_settings
	GameState.save_settings()
	mode.call("configure", original_profile)
	main.world.set_indoor_look(original_indoor, original_kind)

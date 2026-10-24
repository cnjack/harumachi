extends Node
## Presentation budgets only. Gameplay time, physics and save data keep their cadence.
const IDS: Array[String] = ["quality", "balanced", "eco"]
const LABELS: Array[String] = ["原画质 · 60帧", "均衡 · 60帧", "节能 · 30帧"]
const PROFILES := {
	"quality": {"fps": 60, "scale": 1.0, "shadow": 8192, "filter": 3, "msaa": 2, "grass_range": 1.0, "lod": 1.0, "shadow_out": 90.0, "shadow_in": 40.0},
	"balanced": {"fps": 60, "scale": .85, "shadow": 4096, "filter": 2, "msaa": 2, "grass_range": .85, "lod": 1.5, "shadow_out": 65.0, "shadow_in": 35.0},
	"eco": {"fps": 30, "scale": .75, "shadow": 2048, "filter": 1, "msaa": 1, "grass_range": .65, "lod": 2.0, "shadow_out": 45.0, "shadow_in": 28.0},
}
var profile := "balanced"
var background := false
var minimized := false
var benchmark := false
var uncapped := false
var command_profile := ""
var generation := 0
var _last_cap := -1
var _physics_steps_at_start := 8
var _world: WeakRef
var _foliage: Array[WeakRef] = []
var _foliage_time := 0.0
var _shadow_size := -1
var _foliage_position := Vector3(INF, INF, INF)
var _foliage_generation := -1
var _foliage_camera_id := 0
var _foliage_fov := -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_physics_steps_at_start = Engine.max_physics_steps_per_frame
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--graphics-profile="):
			command_profile = valid_profile(argument.trim_prefix("--graphics-profile="))
	benchmark = OS.get_cmdline_user_args().has("--graphics-benchmark")
	uncapped = benchmark and OS.get_cmdline_user_args().has("--benchmark-uncapped")
	if DisplayServer.get_name() != "headless" and not benchmark:
		background = not get_tree().root.has_focus()
	configure(profile)

func valid_profile(value: String) -> String:
	return value if value in IDS else "balanced"

func configure(value: String) -> void:
	profile = valid_profile(value)
	generation += 1
	var config: Dictionary = PROFILES[profile]
	var viewport: Window = get_tree().root
	viewport.scaling_3d_scale = float(config.scale)
	# Spatial scaling keeps temporal trails out of hair, grass and quick camera turns.
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if profile != "quality" and not OS.has_feature("web") else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.msaa_3d = int(config.msaa) as Viewport.MSAA
	viewport.mesh_lod_threshold = float(config.lod)
	var shadow_size: int = int(config.shadow)
	if OS.has_feature("web"):
		shadow_size = mini(shadow_size, int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 2048)))
	if _shadow_size != shadow_size:
		RenderingServer.directional_shadow_atlas_set_size(shadow_size, true)
		_shadow_size = shadow_size
	RenderingServer.directional_soft_shadow_filter_set_quality(int(config.filter))
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM if profile == "quality" else RenderingServer.ENV_SSAO_QUALITY_LOW, true, .5, 2, 50.0, 300.0)
	if _world != null and is_instance_valid(_world.get_ref()): apply_world(_world.get_ref())
	refresh_foliage()
	_update_cap()

func apply_saved(value: String) -> void:
	configure(command_profile if not command_profile.is_empty() else value)

func apply_world(world: Node3D) -> void:
	_world = weakref(world)
	var env: Environment = world.get("env") as Environment
	var sun: DirectionalLight3D = world.get("sun") as DirectionalLight3D
	if env == null or sun == null: return
	var inside: bool = bool(world.get("indoor"))
	var config: Dictionary = PROFILES[profile]
	env.ssao_enabled = profile != "eco" and not OS.has_feature("web")
	env.ssil_enabled = inside and profile == "quality" and not OS.has_feature("web")
	env.volumetric_fog_enabled = inside and profile != "eco" and not OS.has_feature("web")
	# Bloom, painted skies, exposure and the day/night palette are art direction.
	sun.directional_shadow_max_distance = float(config.shadow_in if inside else config.shadow_out)

func target_fps(is_background: bool, is_minimized: bool, is_paused: bool) -> int:
	if is_minimized: return 5
	if is_background: return 10
	if is_paused: return 30
	return int(PROFILES[profile].fps)

func physics_step_budget(cap: int) -> int:
	# At 5 FPS the default 8-step ceiling would silently slow 60 Hz physics to 40 Hz.
	return maxi(_physics_steps_at_start, ceili(float(Engine.physics_ticks_per_second) / cap) + 2) if cap > 0 else _physics_steps_at_start

func _update_cap() -> void:
	if DisplayServer.get_name() == "headless": return
	var cap: int = 0 if uncapped else target_fps(background and not benchmark, minimized and not benchmark, get_tree().paused)
	# Do not repeatedly stomp explicit diagnostic overrides between state changes.
	if cap != _last_cap:
		Engine.max_physics_steps_per_frame = physics_step_budget(cap)
		Engine.max_fps = cap
		_last_cap = cap

func _notification(what: int) -> void:
	if benchmark: return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: background = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: background = false

func _process(delta: float) -> void:
	if DisplayServer.get_name() != "headless":
		minimized = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
	_update_cap()
	_foliage_time += delta
	if _foliage_time >= .2 and not get_tree().paused:
		_foliage_time = 0.0
		refresh_foliage(false)

func register_foliage(node: GeometryInstance3D) -> void:
	if node.has_meta("budget_original_range"): return
	node.set_meta("budget_original_range", node.visibility_range_end)
	node.set_meta("budget_original_margin", node.visibility_range_end_margin)
	_foliage.append(weakref(node))
	_apply_foliage(node, get_viewport().get_camera_3d())

func refresh_foliage(force: bool = true) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var position: Vector3 = camera.global_position if camera != null else Vector3.ZERO
	var camera_id: int = camera.get_instance_id() if camera != null else 0
	var fov: float = camera.fov if camera != null else 0.0
	if not force and _foliage_generation == generation and camera_id == _foliage_camera_id and is_equal_approx(fov, _foliage_fov) and (profile == "quality" or position.distance_squared_to(_foliage_position) < .09): return
	_foliage_camera_id = camera_id
	_foliage_fov = fov
	_foliage_position = position
	_foliage_generation = generation
	var live: Array[WeakRef] = []
	for reference: WeakRef in _foliage:
		var node: GeometryInstance3D = reference.get_ref() as GeometryInstance3D
		if not is_instance_valid(node): continue
		live.append(reference)
		_apply_foliage(node, camera)
	_foliage = live

func _apply_foliage(node: GeometryInstance3D, camera: Camera3D) -> void:
	var factor: float = float(PROFILES[profile].grass_range)
	if not is_equal_approx(float(node.get_meta("budget_range_factor", -1.0)), factor):
		node.visibility_range_end = float(node.get_meta("budget_original_range")) * factor
		node.visibility_range_end_margin = minf(float(node.get_meta("budget_original_margin")), node.visibility_range_end * .2)
		node.set_meta("budget_range_factor", factor)
	if not node is MultiMeshInstance3D or not node.has_meta("budget_grass_meshes"): return
	var grass: MultiMeshInstance3D = node as MultiMeshInstance3D
	var tier := 0
	if profile != "quality" and camera != null and camera.fov >= 40.0 and camera.name != &"PhotoCamera":
		var bounds: AABB = grass.global_transform * (grass.get_meta("budget_grass_bounds") as AABB)
		var point: Vector3 = camera.global_position.clamp(bounds.position, bounds.end)
		var distance: float = camera.global_position.distance_to(point)
		var near_end: float = 18.0 if profile == "balanced" else 14.0
		var far_begin: float = 32.0 if profile == "balanced" else 26.0
		var old_tier: int = int(grass.get_meta("budget_grass_tier", 0))
		tier = 2 if distance > far_begin + (1.5 if old_tier < 2 else -1.5) else (1 if distance > near_end + (1.5 if old_tier == 0 else -1.5) else 0)
	if int(grass.get_meta("budget_grass_tier", -1)) != tier:
		grass.multimesh.mesh = (grass.get_meta("budget_grass_meshes") as Array)[tier]
		grass.set_meta("budget_grass_tier", tier)

func snapshot() -> Dictionary:
	var tiers: Array[int] = [0, 0, 0]
	for reference: WeakRef in _foliage:
		var node: Object = reference.get_ref()
		if is_instance_valid(node) and node.has_meta("budget_grass_tier"): tiers[int(node.get_meta("budget_grass_tier"))] += 1
	return {"profile": profile, "background": background, "minimized": minimized, "fps_cap": Engine.max_fps, "scale": get_tree().root.scaling_3d_scale, "shadow_size": _shadow_size, "msaa": get_tree().root.msaa_3d, "grass_tiers": tiers, "physics_hz": Engine.physics_ticks_per_second}

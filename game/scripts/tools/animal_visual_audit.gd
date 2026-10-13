extends Node
## Native main-scene animal review. Caller must supply HARUMACHI_SAVE_DIR.
## -- --qa-animals=<out> [--qa-animals-mode=live|poses|habitat|home|interactions|cat-smoke]
## --qa-animals-follow=legacy reproduces the old untracked camera for comparison.
## --qa-animals-settle-frames=12 stresses both policies without changing animal time.
## Live samples retain the game's actual decisions. Poses are explicitly labelled
## controlled clip samples and do not pretend to prove navigation or activity.

const DIRECTIONS: Dictionary = {
	"front": Vector3(0, .36, 1.25), "left": Vector3(1.25, .36, 0),
	"back": Vector3(0, .36, -1.25), "right": Vector3(-1.25, .36, 0),
}
const CLIPS: Array[String] = ["Idle", "Walk", "Run", "Sneak", "Sit", "SitDown", "StandUp", "Jump", "Stretch"]
const FRONT_ROUTE: Array[Vector3] = [Vector3(20.65, 0, 14.3), Vector3(21.35, 0, 14.3), Vector3(21.35, 0, 17.3), Vector3(20.65, 0, 17.3)]
var output: String
var mode: String = "all"
var root: Window
var main: Node3D
var life: Node3D
var camera: Camera3D
var records: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var follow_policy: String = "tracked"
var settle_frames: int = 2
var _frame_target: Node3D
var _frame_offset: Vector3
var _frame_focus_offset: Vector3
var _frame_bounds: Dictionary = {}
var _frame_samples: Array[Dictionary] = []
var no_images: bool = false
var paw_samples: Array[Dictionary] = []

func _ready() -> void:
	root = get_tree().root
	_run.call_deferred()

func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for argument: String in arguments:
		if argument.begins_with("--qa-animals="): output = argument.trim_prefix("--qa-animals=")
		if argument.begins_with("--qa-animals-mode="): mode = argument.trim_prefix("--qa-animals-mode=")
		if argument.begins_with("--qa-animals-follow="): follow_policy = argument.trim_prefix("--qa-animals-follow=")
		if argument.begins_with("--qa-animals-settle-frames="): settle_frames = clampi(int(argument.trim_prefix("--qa-animals-settle-frames=")), 2, 12)
	no_images = arguments.has("--qa-animals-no-images=1")
	assert(not OS.get_environment("HARUMACHI_SAVE_DIR").is_empty(), "Animal QA requires an isolated HARUMACHI_SAVE_DIR")
	assert(DisplayServer.get_name() != "headless" or no_images, "Headless audit requires --qa-animals-no-images=1; it cannot prove rendered appearance")
	assert(not output.is_empty(), "Provide --qa-animals=<evidence output directory>")
	assert(follow_policy in ["tracked", "legacy"], "Use --qa-animals-follow=tracked|legacy")
	DirAccess.make_dir_recursive_absolute(output)
	var state: Node = root.get_node("GameState")
	state.new_game()
	state.clock_paused = true
	state.minute = 630
	state.weather = "sunny"
	var npc_script: GDScript = load("res://scripts/npc/npc.gd") as GDScript
	npc_script.roam_enabled = false
	main = get_parent() as Node3D
	await _frames(40)
	life = main.get_node("AmbientLife") as Node3D
	main.ui.visible = false
	main.player.set_physics_process(false)
	main.player.global_position = Vector3(25, .1, 60)
	for node: Node in main.find_children("*", "Camera3D", true, false):
		(node as Camera3D).current = false
	main.rig.set_process(false)
	main.rig.set_physics_process(false)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = .90
	camera.near = .01
	main.add_child(camera)
	camera.current = true
	main.weather_fx.rig = camera
	if not no_images: RenderingServer.frame_pre_draw.connect(_capture_pre_draw)
	_inventory()
	if mode in ["all", "live", "cat-smoke"]: await _live()
	if mode in ["all", "poses", "cat-smoke"]: await _poses()
	if mode in ["all", "habitat"]: await _habitat()
	if mode == "flying": await _flying()
	if mode == "home": await _home()
	if mode == "discovery": await _discovery()
	if mode in ["weather", "cat-smoke"]: await _weather()
	if mode == "fish": await _fish()
	if mode in ["all", "interactions", "cat-smoke"]: await _interactions()
	if mode == "cat-smoke": await _home()
	var passed: bool = true
	for check: Dictionary in checks: passed = passed and bool(check.passed)
	var manifest: Dictionary = {"engine": Engine.get_version_info().string, "mode": mode,
		"camera_follow_policy": follow_policy, "flying_settle_frames": settle_frames,
		"passed": passed, "checks": checks, "screenshots": [] if no_images else records,
		"capture_records": records, "rendered": not no_images, "paw_samples": paw_samples,
		"inventory": {"physical_cats": life.roaming_cats.size(), "roaming_cats": life.roaming_cats.size(), "resting_cat_entities": 0,
			"home_cats": 0,
			"sparrow_flocks": life.flocks.size(), "flyers": life.flyers.size(),
			"other_live_mammals_or_poultry": [], "display_fish": ["G02_goldfish_tank", "G05_goldfish_bowl"]}}
	FileAccess.open(output.path_join("%s.json" % mode), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("ANIMAL_VISUAL_AUDIT ", mode, " passed=", passed, " image_count=", 0 if no_images else records.size(), " capture_records=", records.size(), " checks=", checks.size())
	# Detach this runner before freeing its scene, so renderer references and
	# skeleton modifiers can finish cleanup without cancelling this coroutine.
	var tree: SceneTree = get_tree()
	if RenderingServer.frame_pre_draw.is_connected(_capture_pre_draw): RenderingServer.frame_pre_draw.disconnect(_capture_pre_draw)
	_frame_target = null
	main.remove_child(self)
	tree.root.add_child(self)
	main.queue_free()
	await _frames(5)
	tree.quit(0 if passed else 1)

func _frames(count: int) -> void:
	for frame: int in range(count): await get_tree().process_frame

func _check(label: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"label": label, "passed": passed, "details": details})

func _look(node: Node3D, direction: String, size: float = .90, focus: Vector3 = Vector3(0, .17, 0)) -> void:
	camera.size = size
	camera.global_position = node.global_transform * (DIRECTIONS[direction] as Vector3)
	camera.look_at(node.global_transform * focus)
	camera.current = true

func _shot(id: String, details: Dictionary, target: Node3D = null, focus: Vector3 = Vector3.ZERO) -> void:
	if no_images:
		await _frames(settle_frames)
		var diagnostic: Dictionary = details.duplicate(true)
		diagnostic.merge({"id": id, "file": "", "rendered": false, "weather": GameState.weather, "hour": GameState.hour(), "camera": _vec(camera.global_position)})
		records.append(diagnostic)
		return
	_frame_target = target
	_frame_bounds = {}
	_frame_samples.clear()
	if target != null:
		# Keep this requested world-space angle and size. Only translate with the
		# real target after AmbientLife updates, immediately before each draw.
		_frame_offset = camera.global_position - target.global_position
		_frame_focus_offset = target.global_transform * focus - target.global_position
	for frame: int in range(settle_frames if target != null else 2):
		await RenderingServer.frame_post_draw
	var file: String = id + ".png"
	var bitmap: Image = root.get_texture().get_image()
	var result: Error = bitmap.save_png(output.path_join(file))
	assert(result == OK)
	var record: Dictionary = details.duplicate(true)
	if target != null:
		_add_png_units(_frame_bounds, bitmap.get_size())
		_check("%s drawn target is fully in frame" % id, bool(_frame_bounds.get("complete", false)), _frame_bounds.duplicate(true))
		record["framing"] = _frame_bounds.duplicate(true)
		record["framing"]["settle_samples"] = _frame_samples.duplicate(true)
	_frame_target = null
	record["file"] = file
	record["rendered"] = true
	record["weather"] = GameState.weather
	record["hour"] = GameState.hour()
	record["camera"] = _vec(camera.global_position)
	record["focus_direction"] = _vec(-camera.global_basis.z)
	records.append(record)
	print("ANIMAL_SHOT ", file)

func _capture_pre_draw() -> void:
	if _frame_target == null: return
	if not is_instance_valid(_frame_target):
		_frame_bounds = {"complete": false, "reason": "target was freed"}
		return
	if follow_policy == "tracked":
		camera.global_position = _frame_target.global_position + _frame_offset
		camera.look_at(_frame_target.global_position + _frame_focus_offset)
		camera.force_update_transform()
	_frame_bounds = _project_target(_frame_target)
	_frame_samples.append({"draw_frame": Engine.get_process_frames(),
		"target": _vec(_frame_target.global_position), "target_rotation": _vec(_frame_target.global_rotation),
		"camera": _vec(camera.global_position), "complete": _frame_bounds.complete,
		"bounds_viewport_units": _frame_bounds.get("bounds_viewport_units", [])})

func _add_png_units(framing: Dictionary, png_size: Vector2i) -> void:
	# unproject_position() uses the logical viewport, which can differ from the
	# saved render texture. These are projected geometry bounds, not a pixel mask.
	framing["png_size_px"] = [png_size.x, png_size.y]
	var viewport_units: Array = framing.get("viewport_units", [])
	var bounds: Array = framing.get("bounds_viewport_units", [])
	var valid: bool = viewport_units.size() == 2 and float(viewport_units[0]) > 0 and float(viewport_units[1]) > 0 and png_size.x > 0 and png_size.y > 0
	framing["png_conversion_valid"] = valid
	if not valid:
		return
	var ratio := Vector2(float(png_size.x) / float(viewport_units[0]), float(png_size.y) / float(viewport_units[1]))
	framing["png_px_per_viewport_unit"] = [ratio.x, ratio.y]
	framing["required_margin_png_px_per_axis"] = [4.0 * ratio.x, 4.0 * ratio.y]
	framing["bounds_png_px"] = [float(bounds[0]) * ratio.x, float(bounds[1]) * ratio.y, float(bounds[2]) * ratio.x, float(bounds[3]) * ratio.y] if bounds.size() == 4 else []
	if bounds.size() == 4:
		framing["minimum_projected_margin_png_px"] = minf(minf(float(bounds[0]) * ratio.x, float(bounds[1]) * ratio.y), minf(float(png_size.x) - float(bounds[2]) * ratio.x, float(png_size.y) - float(bounds[3]) * ratio.y))

func _project_target(target: Node3D) -> Dictionary:
	# Scope by ancestry, not pixel colour or scene-wide bounds: foreground leaves
	# cannot masquerade as the animal. Transparent insect wings are included.
	var meshes: Array[MeshInstance3D] = WorldBuilder.find_meshes(target)
	var mesh_paths: Array[String] = []
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var vertex_count: int = 0
	var invalid_vertices: int = 0
	var unsupported_shader: bool = false
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or not mesh.is_visible_in_tree() or (mesh.layers & camera.cull_mask) == 0: continue
		mesh_paths.append(str(target.get_path_to(mesh)))
		for surface: int in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null: continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var skinned: Dictionary = _skin_surface(mesh, surface)
			var material: Material = mesh.get_active_material(surface)
			var deformation: Dictionary = {}
			if material is ShaderMaterial:
				var shader_material := material as ShaderMaterial
				if shader_material.shader == null or shader_material.shader.resource_path != "res://shaders/animal_motion.gdshader" or int(shader_material.get_shader_parameter("animal_kind")) != 0:
					unsupported_shader = true
				else:
					deformation = {"height": shader_material.get_shader_parameter("body_height"),
						"phase": shader_material.get_shader_parameter("phase"), "peck": shader_material.get_shader_parameter("peck")}
			for index: int in vertices.size():
				var vertex: Vector3 = vertices[index]
				var local_vertex: Vector3 = _bird_vertex(vertex, deformation) if not deformation.is_empty() else vertex
				var point: Vector3 = (skinned.points as PackedVector3Array)[index] if bool(skinned.skinned) else mesh.global_transform * local_vertex
				var depth: float = -camera.to_local(point).z
				vertex_count += 1
				if not point.is_finite() or depth <= camera.near or depth >= camera.far:
					invalid_vertices += 1
					continue
				var pixel: Vector2 = camera.unproject_position(point)
				if not pixel.is_finite():
					invalid_vertices += 1
					continue
				low = low.min(pixel)
				high = high.max(pixel)
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var nonempty: bool = vertex_count >= 3 and low.is_finite() and high.is_finite() and (high - low).length() > 1.0
	var margin: float = minf(minf(low.x, low.y), minf(size.x - high.x, size.y - high.y)) if nonempty else -INF
	return {"complete": nonempty and invalid_vertices == 0 and not unsupported_shader and margin >= 4.0,
		"camera_follow_policy": follow_policy, "draw_frame": Engine.get_process_frames(),
		"target": str(target.get_path()), "target_world_position": _vec(target.global_position),
		"mesh_paths": mesh_paths, "vertex_count": vertex_count, "invalid_vertices": invalid_vertices,
		"unsupported_shader": unsupported_shader, "target_visible": target.is_visible_in_tree(),
		"framing_schema_version": 2, "projection_units": "logical_viewport_units",
		"bounds_viewport_units": [low.x, low.y, high.x, high.y] if nonempty else [],
		"viewport_units": [size.x, size.y], "minimum_margin_viewport_units": margin if nonempty else null,
		"required_margin_viewport_units": 4.0, "camera_size": camera.size,
		"geometry_method": "full current skinned cat vertices and post-modifier bone poses; known sparrow peck/breath shader reproduced; animated wing-node transforms; alpha masks conservatively included",
		"scope": "target geometry framing; foreground occlusion still requires visual review"}

func _bird_vertex(vertex: Vector3, deformation: Dictionary) -> Vector3:
	# Match the existing sparrow shader's peck/breath before projection; articulated
	# wing transforms already contain their real current animation pose.
	var height: float = maxf(float(deformation.height), .01)
	var pivot := Vector3(0, height * .64, 0)
	var relative: Vector3 = vertex - pivot
	var angle: float = float(deformation.peck) * smoothstep(height * .62, height * .77, vertex.y) * .65
	var result: Vector3 = vertex
	result.y = pivot.y + cos(angle) * relative.y - sin(angle) * relative.z
	result.z = pivot.z + sin(angle) * relative.y + cos(angle) * relative.z
	var chest: float = smoothstep(height * .16, height * .36, vertex.y) * (1.0 - smoothstep(height * .62, height * .80, vertex.y))
	var breath: float = sin(float(deformation.phase) * 1.5)
	result.y += chest * height * .012 * breath
	result.x += vertex.x * chest * .008 * breath
	return result

func _vec(position: Vector3) -> Array:
	return [position.x, position.y, position.z]

func _live() -> void:
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	life.set_process(true)
	for index: int in range(life.roaming_cats.size()):
		var cat: CharacterBody3D = life.roaming_cats[index]
		var who: String = "orange" if index == 0 else "calico"
		var skeleton: Skeleton3D = cat.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var start_travel: float = cat.travelled
		var start_attention: float = cat.attention.attention_time
		var samples: Array[Dictionary] = []
		var elapsed: float = 0.0
		var next_sample: float = 0.0
		var shot_index: int = 0
		var started: int = Time.get_ticks_msec()
		main.player.global_position = cat.global_position + Vector3(5, .1, 5)
		while elapsed < 15.0:
			elapsed = float(Time.get_ticks_msec() - started) / 1000.0
			var direction: String = ["front", "left", "back", "right"][mini(3, int(elapsed / 3.75))]
			_look(cat, direction)
			await get_tree().process_frame
			if elapsed >= next_sample:
				var sample: Dictionary = cat.telemetry()
				sample["elapsed_seconds"] = elapsed
				sample["visible"] = cat.is_visible_in_tree()
				sample["animation_active"] = cat.player.active
				sample["head_world"] = _vec(skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin)
				samples.append(sample)
				next_sample += .25
			if elapsed > 1.5 + float(shot_index) * 1.5 and shot_index < 9:
				await _shot("%s_live_%02d_%s" % [who, shot_index, direction],
					{"subject": who, "review": "actual_world_decisions", "view": direction, "telemetry": cat.telemetry()})
				shot_index += 1
		var yaws: Array[float] = []
		var clips: Array[String] = []
		for sample: Dictionary in samples:
			yaws.append(float(sample.head_look_degrees))
			if not clips.has(str(sample.animation)): clips.append(str(sample.animation))
		_check("%s lives and looks around in the real street" % who,
			cat.travelled - start_travel > .25 and cat.attention.attention_time - start_attention > 14.0
			and yaws.max() - yaws.min() > 35 and skeleton.get_bone_count() == 59 and cat.player.active,
			{"travelled_m": cat.travelled - start_travel, "attention_delta": cat.attention.attention_time - start_attention,
				"head_yaw_range_degrees": yaws.max() - yaws.min(), "clips_observed": clips,
				"asset_sha256": FileAccess.get_sha256("res://assets/models/AN_cat_%s_walk.glb" % who), "samples": samples})
		_check("%s moves continuously with synchronized planted paws" % who,
			cat.speed >= .32 and cat.speed <= .45 and cat.maximum_step < .025 and int(cat.foot_plant.get("locked_samples")) > 0 and float(cat.foot_plant.get("maximum_lock_error")) < .002,
			{"speed_mps": cat.speed, "maximum_physics_step_m": cat.maximum_step, "locked_paw_samples": int(cat.foot_plant.get("locked_samples")), "maximum_paw_lock_error_m": float(cat.foot_plant.get("maximum_lock_error"))})
	# Test visibility/processing transitions explicitly instead of diagnosing rain/night as a frozen Walk.
	for condition: Dictionary in [{"weather": "cloudy", "hour": 10.5, "active": true},
		{"weather": "rain", "hour": 10.5, "active": false}, {"weather": "sunny", "hour": 21.0, "active": false},
		{"weather": "sunny", "hour": 10.5, "active": true}]:
		GameState.weather = condition.weather
		GameState.minute = float(condition.hour) * 60.0
		await _frames(4)
		var correct: bool = true
		for cat: CharacterBody3D in life.roaming_cats:
			correct = correct and cat.visible and cat.is_physics_processing() == bool(condition.active) and cat.player.active
			if not bool(condition.active): correct = correct and cat.player.current_animation == "Idle"
		_check("weather/time activation %s %.1f" % [condition.weather, condition.hour], correct, condition)

func _poses() -> void:
	main.world.set_region("town")
	GameState.weather = "sunny"
	GameState.minute = 630
	var life_was_processing: bool = life.is_processing()
	var saved: Array[Dictionary] = []
	for cat: CharacterBody3D in life.roaming_cats:
		saved.append({"behaviour": cat.snapshot().duplicate(true), "seed": cat.behaviour_seed,
			"physics": cat.is_physics_processing(), "animation_active": cat.player.active,
			"animation_rate": cat.player.speed_scale, "animation": cat.player.current_animation,
			"animation_position": cat.player.current_animation_position, "attention_active": cat.attention.active,
			"attention_time": cat.attention.attention_time, "attention_yaw": cat.attention.yaw,
			"foot_plant_active": cat.foot_plant.active})
	life.set_process(false)
	for cat: CharacterBody3D in life.roaming_cats: cat.set_physics_process(false)
	for index: int in range(life.roaming_cats.size()):
		var cat: CharacterBody3D = life.roaming_cats[index]
		var who: String = "orange" if index == 0 else "calico"
		cat.show()
		cat.player.active = true
		cat.attention.active = false
		cat.foot_plant.active = false
		cat.rotation.y = 0
		for clip: String in CLIPS:
			_check("%s has %s" % [who, clip], cat.player.has_animation(clip))
			if not cat.player.has_animation(clip): continue
			cat.player.play(clip, 0)
			cat.player.speed_scale = 0
			var duration: float = cat.player.get_animation(clip).length
			for phase: float in [.25, .65]:
				cat.player.seek(duration * phase, true)
				cat.player.advance(0.0)
				await _frames(2)
				var paws: Dictionary = _paw_report(cat)
				paws.merge({"cat": who, "clip": clip, "phase": phase, "controlled": true})
				paw_samples.append(paws)
				_check("%s %s %.2f has four finite skinned paws above the floor" % [who, clip, phase], int(paws.paws) == 4 and bool(paws.finite) and float(paws.minimum_gap_m) > -.015, paws)
				for direction: String in DIRECTIONS:
					_look(cat, direction)
					await _shot("%s_%s_%02d_%s" % [who, clip.to_lower(), int(phase * 100), direction],
						{"subject": who, "review": "controlled_actual_asset_clip", "clip": clip, "phase": phase,
							"view": direction, "world_position": _vec(cat.global_position)}, cat, Vector3(0, .17, 0))
	for index: int in life.roaming_cats.size():
		var cat: CharacterBody3D = life.roaming_cats[index]
		for clip: String in ["Walk", "Run"]:
			cat.player.play(clip, 0)
			for phase_index: int in 17:
				var phase: float = float(phase_index) / 16.0
				cat.player.seek(cat.player.get_animation(clip).length * phase, true)
				cat.player.advance(0.0)
				await _frames(1)
				var paws: Dictionary = _paw_report(cat)
				paws.merge({"cat_index": index, "clip": clip, "phase": phase, "controlled": true})
				paw_samples.append(paws)
				_check("cat %d %s gait phase %02d keeps finite soles above ground" % [index, clip, phase_index], int(paws.paws) == 4 and bool(paws.finite) and float(paws.minimum_gap_m) > -.015 and float(paws.minimum_gap_m) < .025, paws)
	# Controlled asset seeks must not leak into the following real habitat review.
	for index: int in range(life.roaming_cats.size()):
		var cat: CharacterBody3D = life.roaming_cats[index]
		var previous: Dictionary = saved[index]
		cat.reset_behaviour(int(previous.seed), previous.behaviour)
		cat.attention.active = bool(previous.attention_active)
		cat.attention.attention_time = float(previous.attention_time)
		cat.attention.yaw = float(previous.attention_yaw)
		cat.foot_plant.active = bool(previous.foot_plant_active)
		cat.player.active = bool(previous.animation_active)
		cat.player.speed_scale = float(previous.animation_rate)
		cat.player.play(str(previous.animation), 0)
		cat.player.seek(float(previous.animation_position), true)
		cat.set_physics_process(bool(previous.physics))
	life.set_process(life_was_processing)
	await _frames(4)

func _habitat() -> void:
	GameState.weather = "sunny"
	GameState.minute = 630
	main.world.set_indoor_look(false)
	life.set_process(true)
	main.world.set_region("town")
	for index: int in range(life.roaming_cats.size()):
		var cat: CharacterBody3D = life.roaming_cats[index]
		main.player.global_position = cat.global_position + Vector3(3, 0, 3)
		for direction: String in DIRECTIONS:
			_look(cat, direction, .90, Vector3(0, .17, 0))
			await _shot("ground_cat_%d_%s" % [index, direction],
				{"subject": "ground_cat_%d" % index, "review": "actual_rigged_ground_cat", "view": direction}, cat, Vector3(0, .17, 0))
		var paws: Dictionary = _paw_report(cat)
		paws["animation"] = cat.player.current_animation
		_check("ground cat %d has actual paw support or its authored jump" % index, int(paws.paws) == 4 and bool(paws.finite) and float(paws.minimum_gap_m) > -.015 and float(paws.minimum_gap_m) < (.25 if cat.player.current_animation == "Jump" else .025), paws)
	for location: Dictionary in [{"name": "courtyard_wall", "at": Vector3(12.6, .7, -5.42), "region": "town"},
		{"name": "lane_wall", "at": Vector3(22.2, 1.2, 10.6), "region": "town"},
		{"name": "farm_bench", "at": FarmBuilder.ORIGIN + Vector3(-16.4, .46, -1.74), "region": "farm"}]:
		main.world.set_region(str(location.region))
		camera.size = 2.2
		camera.global_position = location.at + Vector3(1.8, 1.2, 2.0)
		camera.look_at(location.at)
		await _shot("former_cat_" + str(location.name), {"review": "former_static_cat_location_now_empty", "subject": location.name})
	await _weather()
	await _flying()
	await _fish()
	await _home()

func _flying() -> void:
	GameState.weather = "sunny"
	GameState.minute = 630
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	life.set_process(true)
	var flock: Dictionary = life.flocks[0]
	main.player.global_position = flock.home + Vector3(8, .1, 8)
	await get_tree().create_timer(.6).timeout
	var bird: Node3D
	for entry: Dictionary in flock.birds:
		if entry.node.is_visible_in_tree(): bird = entry.node; break
	_check("at least one sparrow stands on a rendered surface", bird != null)
	if bird != null:
		for direction: String in ["front", "left", "back"]:
			_look(bird, direction, .32, Vector3(0, .055, 0))
			await _shot("sparrow_ground_%s" % direction, {"subject": "sparrow", "review": "actual_ground_activity", "view": direction}, bird, Vector3(0, .055, 0))
		main.player.global_position = flock.home + Vector3(1.8, .1, 0)
		for phase: int in range(3):
			await get_tree().create_timer(.22).timeout
			_look(bird, "left", .48, Vector3(0, .055, 0))
			await _shot("sparrow_takeoff_%d" % phase, {"subject": "sparrow", "review": "actual_player_triggered_takeoff", "flock_state": flock.state}, bird, Vector3(0, .055, 0))
		_check("player proximity triggers actual sparrow flight", flock.state == "fly")
	for kind: String in ["butterfly", "dragonfly"]:
		var flyer: Dictionary = {}
		for entry: Dictionary in life.flyers:
			if entry.kind == kind and entry.region == "town": flyer = entry; break
		_check("%s capture subject exists" % kind, not flyer.is_empty())
		if flyer.is_empty(): continue
		var insect: Node3D = flyer.node
		main.player.global_position = insect.global_position + Vector3(4, .1, 4)
		await _frames(4)
		var start: Vector3 = insect.global_position
		var first_phase: float = flyer.t
		for direction: String in ["front", "left", "back"]:
			_look(insect, direction, .28, Vector3.ZERO)
			await _shot("%s_%s" % [kind, direction], {"subject": kind, "review": "actual_flight", "view": direction}, insect)
		camera.size = .24
		camera.global_position = insect.global_position + Vector3(.07, .22, .05)
		camera.look_at(insect.global_position)
		await _shot("%s_top" % kind, {"subject": kind, "review": "actual_flight_anatomy", "view": "top"}, insect)
		var toward_sun: Vector3 = main.world.sun.global_basis.z.normalized()
		camera.global_position = insect.global_position - toward_sun * .45 + Vector3(.04, 0, 0)
		camera.look_at(insect.global_position)
		await _shot("%s_sky" % kind, {"subject": kind, "review": "sky_and_backlight_readability", "view": "sky"}, insect)
		await get_tree().create_timer(.75).timeout
		_check("%s flight clock advances" % kind, float(flyer.t) > first_phase + .5,
			{"phase_delta": float(flyer.t) - first_phase, "displacement_m": start.distance_to(insect.global_position)})

func _fish() -> void:
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	GameState.weather = "sunny"
	GameState.minute = 630
	var tank: Node3D = main.world.goldfish_tank
	for direction: String in ["front", "left", "back"]:
		_look(tank, direction, 1.55, Vector3(0, .22, 0))
		camera.global_position += Vector3(0, .8, 0)
		camera.look_at(tank.global_transform * Vector3(0, .22, 0))
		await _shot("goldfish_display_%s" % direction,
			{"subject": "goldfish_tank", "review": "existing_static_display_geometry", "view": direction})
	camera.global_position = tank.global_position + Vector3(0, 2.2, .2)
	camera.look_at(tank.global_position + Vector3(0, .22, 0))
	await _shot("goldfish_display_top", {"subject": "goldfish_tank", "review": "existing_static_display_geometry", "view": "top"})
	main.world.house.show()
	GameState.flags.goldfish_home = true
	main.world.house.sync_state()
	main.world.set_indoor_look(true)
	var bowl: Node3D = main.world.house.goldfish
	var fish_life: Node3D = bowl.get_node_or_null("GoldfishLife") as Node3D
	_check("the caught home goldfish has actual visible geometry", fish_life != null and fish_life.get_node_or_null("CaughtGoldfish/Body") != null)
	for direction: String in ["front", "left", "back"]:
		_look(bowl, direction, .80, Vector3(0, .15, 0))
		camera.global_position += Vector3(0, 1.0, 0)
		camera.look_at(bowl.global_transform * Vector3(0, .15, 0))
		await _shot("goldfish_home_%s" % direction,
			{"subject": "goldfish_bowl", "review": "actual_caught_goldfish_underwater", "view": direction})
	camera.global_position = bowl.global_position + Vector3(0, 1.5, .2)
	camera.look_at(bowl.global_position + Vector3(0, .15, 0))
	await _shot("goldfish_home_top", {"subject": "goldfish_bowl", "review": "actual_caught_goldfish_underwater", "view": "top"})
	await get_tree().create_timer(.9).timeout
	await _shot("goldfish_home_top_later", {"subject": "goldfish_bowl", "review": "caught_goldfish_swimming", "view": "top", "phase": fish_life.get("phase") if fish_life != null else null})

func _weather() -> void:
	life.set_process(true)
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	for condition: Dictionary in [{"weather": "rain", "hour": 10.5}, {"weather": "sunny", "hour": 21.0}]:
		GameState.weather = condition.weather
		GameState.minute = float(condition.hour) * 60.0
		life._process(0.0)
		var places: Array[Vector3] = []
		for cat: CharacterBody3D in life.roaming_cats: places.append(cat.global_position)
		main.world.update_time(GameState.minute, GameState.weather, true)
		await _frames(4)
		for index: int in life.roaming_cats.size():
			var cat: CharacterBody3D = life.roaming_cats[index]
			_look(cat, "front", .90, Vector3(0, .17, 0))
			if GameState.weather == "rain" and not no_images:
				main.weather_fx.rain.global_position = camera.global_position + Vector3(0, 9, 0)
				main.weather_fx.rain.restart()
				await _frames(4)
			await _shot("ground_cat_%d_%s_%02d" % [index, condition.weather, int(condition.hour)],
				{"subject": "ground_cat_%d" % index, "review": "visible_rest_without_relocation", "visible": cat.is_visible_in_tree(), "animation": cat.player.current_animation}, cat, Vector3(0, .17, 0))
			_check("cat %d remains visible and in place during %s %.1f" % [index, condition.weather, condition.hour], cat.visible and cat.player.active and cat.player.current_animation == "Idle" and not cat.is_physics_processing() and cat.global_position.distance_to(places[index]) < .0001)

func _home() -> void:
	main.world.set_region("town")
	main.world.house.show()
	main.world.set_indoor_look(true)
	main.world.house.update_cutaway("engawa", false)
	life._process(0.0)
	var extra: Array[Node] = []
	for node: Node in main.world.house.find_children("*", "Node3D", true, false):
		if node.get_meta("model_id", "") == "G08_cat": extra.append(node)
	var ghost: Node = main.find_child("P_house_cat", true, false)
	_check("home has no third cat and no abandoned pet interaction", extra.is_empty() and ghost == null)
	main.player.visible = false
	for direction: String in ["front", "left"]:
		camera.size = 3.2
		camera.global_position = HouseBuilder.ORIGIN + Vector3(3.3, 2.0, -.4) if direction == "front" else HouseBuilder.ORIGIN + Vector3(.3, 1.6, -2.1)
		camera.look_at(HouseBuilder.ORIGIN + Vector3(3.3, .2, -3.95))
		await _shot("home_engawa_" + direction, {"subject": "empty_engawa", "review": "no_extra_static_cat_or_ghost_prompt", "view": direction})
	GameState.flags.goldfish_home = true
	main.world.house.sync_state()
	var bowl: Node3D = main.world.house.goldfish
	var fish: Node3D = bowl.get_node_or_null("GoldfishLife/CaughtGoldfish") as Node3D
	var controller: Node3D = bowl.get_node_or_null("GoldfishLife") as Node3D
	var first: Vector3 = fish.position if fish != null else Vector3.INF
	await get_tree().create_timer(.7).timeout
	_check("removing the extra cat preserves the caught home goldfish and its swimming", controller != null and fish != null and fish.is_visible_in_tree() and first.distance_to(fish.position) > .005)
	_look(bowl, "front", .90, Vector3(0, .15, 0))
	camera.global_position += Vector3(0, .8, 0)
	camera.look_at(bowl.global_transform * Vector3(0, .15, 0))
	await _shot("home_bowl_after_cat_cleanup", {"subject": "home_goldfish", "review": "fish_remains_after_removing_extra_cat"})
	main.player.visible = true
	await _discovery()

func _discovery() -> void:
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	main.world.house.hide()
	GameState.weather = "sunny"
	GameState.minute = 630
	main.player.global_position = Vector3(19.7, .05, 8)
	var cat: CharacterBody3D = life.roaming_cats[0]
	var candidates: Array[Dictionary] = []
	var safe: bool = true
	for at: Vector3 in FRONT_ROUTE:
		var clear: bool = cat._clear(at)
		var ground: float = WorldBuilder.surface_height(main.world, Vector2(at.x, at.z), .1, true)
		candidates.append({"position": _vec(at), "clear": clear, "rendered_ground_y": ground})
		safe = safe and clear and is_finite(ground)
	_check("front residential lane candidate anchors have safe rendered support", safe, {"anchors": candidates})
	var nearby: bool = true
	for at: Vector3 in cat.route: nearby = nearby and at.distance_to(Vector3(20, 0, 5.5)) < 15
	_check("one animated cat can be discovered near the home and plaza", nearby,
		{"route": Array(cat.route), "home_stand": [20, 0, 5.5], "maximum_discovery_distance_m": 15})
	camera.size = 8
	for sample: int in range(3):
		camera.global_position = Vector3(15, 3.0, 8.0)
		camera.look_at(Vector3(20.8, .8, 15.5))
		await _shot("cat_discovery_%d" % sample,
			{"subject": "orange_cat_discovery", "review": "actual_public_lane", "world_position": _vec(cat.global_position)})
		await get_tree().create_timer(.7).timeout

func _inventory() -> void:
	var physical: Array[Node3D] = []
	_collect_cat_models(main, physical)
	_check("the whole world has exactly two physical cats", physical.size() == 2 and life.roaming_cats.size() == 2, {"models": physical.map(func(node: Node3D) -> String: return str(node.get_meta("model_id")))})
	_check("no cat model remains on a wall bench or in the house", physical.all(func(node: Node3D) -> bool: return str(node.get_meta("model_id")).begins_with("AN_cat_")))

func _collect_cat_models(node: Node, found: Array[Node3D]) -> void:
	if node is Node3D and str(node.get_meta("model_id", "")) in ["G08_cat", "A20_cat_sleep", "A22_cat_sit", "AN_cat_orange_walk", "AN_cat_calico_walk"]: found.append(node as Node3D)
	for child: Node in node.get_children(): _collect_cat_models(child, found)

func _skin_surface(mesh: MeshInstance3D, surface: int) -> Dictionary:
	var arrays: Array = mesh.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var points: PackedVector3Array = []
	var paw_points: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var skeleton: Skeleton3D = mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	if mesh.skin == null or skeleton == null or arrays[Mesh.ARRAY_BONES] == null:
		for vertex: Vector3 in vertices: points.append(mesh.global_transform * vertex)
		return {"points": points, "paws": paw_points, "skinned": false}
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var matrices: Array[Transform3D] = []
	var feet: Array[int] = []
	for bind: int in mesh.skin.get_bind_count():
		var bone: int = mesh.skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
		assert(bone >= 0, "Every skinned vertex bind must resolve to a live bone")
		matrices.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
		feet.append(["Back_Leg_Foot_L", "Front_Leg_Foot_L", "Back_Leg_Foot_R", "Front_Leg_Foot_R"].find(skeleton.get_bone_name(bone)))
	var influences: int = bones.size() / vertices.size()
	for index: int in vertices.size():
		var world_point := Vector3.ZERO
		var foot_weights: Array[float] = [0.0, 0.0, 0.0, 0.0]
		for influence: int in influences:
			var offset: int = index * influences + influence
			var weight: float = weights[offset]
			if weight <= 0.0: continue
			var bind: int = bones[offset]
			world_point += (matrices[bind] * vertices[index]) * weight
			if feet[bind] >= 0: foot_weights[feet[bind]] += weight
		points.append(world_point)
		for foot: int in 4:
			if foot_weights[foot] >= .35:
				var selected: PackedVector3Array = paw_points[foot]
				selected.append(world_point)
				paw_points[foot] = selected
	return {"points": points, "paws": paw_points, "skinned": true}

func _paw_report(cat: CharacterBody3D) -> Dictionary:
	var minima: Array[Vector3] = [Vector3.INF, Vector3.INF, Vector3.INF, Vector3.INF]
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(cat.model):
		for surface: int in mesh.mesh.get_surface_count():
			var geometry: Dictionary = _skin_surface(mesh, surface)
			for foot: int in 4:
				for point: Vector3 in geometry.paws[foot]:
					if point.y < minima[foot].y: minima[foot] = point
	var count: int = 0
	var minimum_gap: float = INF
	var all_finite: bool = true
	var samples: Array[Dictionary] = []
	for foot: int in 4:
		if not minima[foot].is_finite(): all_finite = false; continue
		var point: Vector3 = minima[foot]
		var ground: float = WorldBuilder.surface_height(main.world, Vector2(point.x, point.z), cat.global_position.y + .08, true)
		all_finite = all_finite and is_finite(ground)
		count += 1
		minimum_gap = minf(minimum_gap, point.y - ground)
		samples.append({"paw": foot, "world_minimum": _vec(point), "rendered_ground_y": ground, "gap_m": point.y - ground})
	return {"paws": count, "finite": all_finite, "minimum_gap_m": minimum_gap, "samples": samples}

func _interactions() -> void:
	GameState.weather = "sunny"; GameState.minute = 630
	main.world.set_region("town"); main.world.set_indoor_look(false)
	main.in_room = false; GameState.player_in_room = false
	main.player.visible = true; main.player.frozen = false
	main.player.set_physics_process(true)
	life.set_process(true)
	main.ui.auto = false
	for index: int in life.roaming_cats.size():
		var cat: CharacterBody3D = life.roaming_cats[index]
		var target: Interactable = life.cats[index].interact
		cat.rest_left = maxf(cat.rest_left, 3.0); cat.rest_pose = "Idle"; cat.pose_left = 0.0
		var selected: bool = false
		for direction: Vector3 in [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0)]:
			main.player.global_position = cat.global_position + direction * 1.05 + Vector3.UP * .05
			main.player.velocity = Vector3.ZERO; main.player.face_towards(cat.global_position)
			await _frames(4)
			if main.player.target == target: selected = true; break
		_check("physical E target selects cat %d" % index, selected, {"target": main.player.target.id if main.player.target != null else "none", "cat": _vec(cat.global_position), "player": _vec(main.player.global_position)})
		camera.size = 2.4
		camera.global_position = cat.global_position + Vector3(-1.7, 1.0, 1.9)
		camera.look_at(cat.global_position + Vector3(0, .45, 0))
		await _shot("cat_%d_before_E" % index, {"review": "real_keyboard_pet", "target_selected": selected})
		var pets_before: int = int(GameState.flags.get("ambient_cat_pets", 0))
		var at: Vector3 = cat.global_position
		var event := InputEventKey.new(); event.physical_keycode = KEY_E; event.keycode = KEY_E; event.pressed = true
		Input.parse_input_event(event)
		await _frames(2)
		event = InputEventKey.new(); event.physical_keycode = KEY_E; event.keycode = KEY_E; event.pressed = false
		Input.parse_input_event(event)
		await _frames(3)
		_check("real E pets cat %d audibly without relocating it" % index, selected and int(GameState.flags.get("ambient_cat_pets", 0)) == pets_before + 1 and Audio._last.has("cat_meow") and cat.global_position.distance_to(at) < .002, {"pet_count_before": pets_before, "pet_count_after": int(GameState.flags.get("ambient_cat_pets", 0)), "displacement_m": cat.global_position.distance_to(at)})
		await _shot("cat_%d_after_E" % index, {"review": "real_keyboard_pet_response", "pet_count": int(GameState.flags.get("ambient_cat_pets", 0)), "telemetry": cat.telemetry()})
	main.player.set_physics_process(false)

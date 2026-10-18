extends Node
## Isolated POC: native GLB AnimationPlayer evaluation, no game controllers/modifiers.
## Recording evaluates exact source sample n/30; interactive preview advances normally.
const IDS: Array[String] = ["sora", "ren", "haru", "mio", "aoi", "tanaka", "kazuko"]
const NAMES: Dictionary = {"sora":"空", "ren":"莲", "haru":"春", "mio":"澪", "aoi":"小葵", "tanaka":"田中爷爷", "kazuko":"和子"}
const VIEWS: Array[String] = ["front", "right", "oblique"]
const VIEW_NAMES: Dictionary = {"front":"正面", "right":"右侧", "oblique":"斜侧"}
const WATCH: Array[String] = ["Hips", "Spine2", "Head", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftHand", "RightHand", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]
var config: Dictionary = {}
var take: String = "solo-sora"
var output: String = ""
var recording: bool = false
var stills_only: bool = false
var stills: Array[Dictionary] = []
var panels: Array[Dictionary] = []
var rows: Array[Dictionary] = []
var sections: Array[Dictionary] = []
var failures: Array[String] = []
var font: Font
var title: Label
var subtitle: Label
var clip_index: int = 0
var section_elapsed: float = 0.0
var active: bool = false
var source_data: Dictionary = {}
var paused: bool = false

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--take="): take = argument.trim_prefix("--take=")
		elif argument.begins_with("--out="): output = argument.trim_prefix("--out=")
		elif argument == "--record": recording = true
		elif argument == "--stills":
			recording = true
			stills_only = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://showcase.json"))
	assert(parsed is Dictionary, "Missing prepared showcase.json")
	config = parsed as Dictionary
	assert(not (config["clips"] as Array).is_empty())
	font = load("res://font.ttf") as Font
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var background := ColorRect.new()
	background.color = Color("e9edf1")
	background.position = Vector2.ZERO
	background.size = Vector2(1920, 1080)
	canvas.add_child(background)
	title = _label(canvas, Vector2(30, 15), 30, "MotionBricks · G1 → 人物重定向 POC")
	subtitle = _label(canvas, Vector2(30, 56), 21, "")
	_label(canvas, Vector2(30, 1043), 18, "独立实验 · 原人物材质 · 无游戏动作修饰器 · 各片段独立开始，不代表跨动作生成过渡")
	var selected: Array[String] = []
	if take == "group-three": selected.assign(["sora", "ren", "tanaka"])
	elif take == "group-four": selected.assign(["mio", "haru", "aoi", "kazuko"])
	elif take == "source-motion": selected.assign(["source"])
	else:
		assert(take.begins_with("solo-") and take.trim_prefix("solo-") in IDS, "Unknown take")
		selected.assign([take.trim_prefix("solo-")])
	if take == "source-motion":
		var proxy_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://source-motion.json"))
		assert(proxy_parsed is Dictionary)
		source_data = proxy_parsed as Dictionary
		title.text = "MotionBricks · 生成源 G1 骨架（34关节代理）"
	for index: int in selected.size():
		var columns: int = 2 if selected.size() == 4 else selected.size()
		var panel_rows: int = 2 if selected.size() == 4 else 1
		var column: int = index % columns
		var row_index: int = index / columns
		var panel_size := Vector2((1920.0 - 24.0 * (columns + 1)) / columns, (938.0 - 16.0 * (panel_rows - 1)) / panel_rows)
		var origin := Vector2(24 + column * (panel_size.x + 24), 96 + row_index * (panel_size.y + 16))
		panels.append(_panel(canvas, selected[index], origin, panel_size))
	var display: Dictionary = {"screen":DisplayServer.window_get_current_screen(), "position":[DisplayServer.window_get_position().x, DisplayServer.window_get_position().y], "size":[DisplayServer.window_get_size().x, DisplayServer.window_get_size().y], "no_focus":DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS), "renderer":RenderingServer.get_current_rendering_method()}
	print("MOTIONBRICKS_POC_DISPLAY ", JSON.stringify(display))
	if recording:
		assert(not output.is_empty())
		DirAccess.make_dir_recursive_absolute(output)
		_record.call_deferred()
	else: _start_clip(0)

func _label(parent: Node, at: Vector2, size: int, value: String) -> Label:
	var label := Label.new()
	label.position = at
	label.text = value
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("21364b"))
	parent.add_child(label)
	return label

func _panel(parent: Node, id: String, origin: Vector2, dimensions: Vector2) -> Dictionary:
	var container := SubViewportContainer.new()
	container.position = origin
	container.size = dimensions
	container.stretch = true
	parent.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(dimensions)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8195a5")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d7e3f4")
	environment.environment.ambient_light_energy = 0.7
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	stage.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	floor_mesh.mesh = plane
	var floor_shader := Shader.new()
	floor_shader.code = """shader_type spatial;
render_mode specular_disabled, cull_disabled;
varying vec2 ground_world;
void vertex() { ground_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; }
float aa_grid(vec2 coordinate) {
    vec2 rate = max(fwidth(coordinate), vec2(0.00001));
    vec2 distance_px = abs(fract(coordinate - 0.5) - 0.5) / rate;
    float line = 1.0 - smoothstep(0.45, 1.25, min(distance_px.x, distance_px.y));
    float fade = 1.0 - smoothstep(0.035, 0.12, max(rate.x, rate.y));
    return line * fade;
}
void fragment() {
    float minor_line = aa_grid(ground_world);
    float major_line = aa_grid(ground_world / 5.0);
    float line = max(minor_line * 0.16, major_line * 0.30);
    ALBEDO = mix(vec3(0.28, 0.34, 0.38), vec3(0.16, 0.22, 0.27), line);
    ROUGHNESS = 1.0;
}
"""
	var floor_material := ShaderMaterial.new()
	floor_material.shader = floor_shader
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.35
	camera.near = 0.03
	camera.far = 220
	stage.add_child(camera)
	camera.current = true
	var record: Dictionary = {"id":id, "stage":stage, "camera":camera, "proxy_nodes":[], "proxy_links":[], "last_view":"front"}
	if id == "source":
		_build_proxy(record)
	else:
		var packed: PackedScene = load("res://assets/CH_" + id + ".glb") as PackedScene
		assert(packed != null)
		var model: Node3D = packed.instantiate() as Node3D
		stage.add_child(model)
		var ap: AnimationPlayer = _find_type(model, "AnimationPlayer") as AnimationPlayer
		var skeleton: Skeleton3D = _find_type(model, "Skeleton3D") as Skeleton3D
		assert(ap != null and skeleton != null)
		var root_index: int = -1
		var watched: Array[int] = []
		for bone_index: int in skeleton.get_bone_count():
			var short_name: String = String(skeleton.get_bone_name(bone_index)).replace("mixamorig:", "").replace("mixamorig_", "")
			if short_name == "Hips": root_index = bone_index
			if short_name in WATCH: watched.append(bone_index)
		assert(root_index >= 0 and watched.size() == WATCH.size())
		record.merge({"model":model, "ap":ap, "skeleton":skeleton, "root_index":root_index, "watched":watched})
	var name_label: Label = _label(parent, origin + Vector2(16, 10), 25, "生成源 G1 · 非官方人类模型" if id == "source" else str(NAMES[id]))
	record["label"] = name_label
	return record

func _find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name): return node
	for child: Node in node.get_children():
		var found: Node = _find_type(child, type_name)
		if found != null: return found
	return null

func _build_proxy(panel: Dictionary) -> void:
	var stage: Node3D = panel["stage"] as Node3D
	var names: Array = source_data["joint_names"] as Array
	var parents: Array = source_data["joint_parents"] as Array
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("346b8c")
	material.roughness = 0.9
	for index: int in names.size():
		var joint := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.026
		sphere.height = 0.052
		joint.mesh = sphere
		joint.material_override = material
		stage.add_child(joint)
		(panel["proxy_nodes"] as Array).append(joint)
		if int(parents[index]) >= 0:
			var link := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.014
			cylinder.bottom_radius = 0.014
			cylinder.height = 1.0
			link.mesh = cylinder
			link.material_override = material
			stage.add_child(link)
			(panel["proxy_links"] as Array).append({"node":link, "child":index, "parent":int(parents[index])})

func _clip() -> Dictionary:
	return (config["clips"] as Array)[clip_index] as Dictionary

func _start_clip(index: int) -> void:
	clip_index = index
	section_elapsed = 0.0
	var clip: Dictionary = _clip()
	for panel: Dictionary in panels:
		if panel["id"] == "source": continue
		var ap: AnimationPlayer = panel["ap"] as AnimationPlayer
		var skeleton: Skeleton3D = panel["skeleton"] as Skeleton3D
		ap.stop()
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if recording else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		skeleton.reset_bone_poses()
		var matches: Array[String] = []
		for candidate: String in ap.get_animation_list():
			if candidate == str(clip["clip"]) or candidate.ends_with("/" + str(clip["clip"])): matches.append(candidate)
		assert(matches.size() == 1, "Missing or ambiguous genuine generated clip " + str(clip["clip"]))
		ap.play(matches[0], 0.0)
		ap.speed_scale = 1.0
		ap.seek(0.0, true)
		panel["actual_clip"] = matches[0]
	active = true
	subtitle.text = str(clip["label"]) + "    |    " + ("G1源动作 · 无人体重定向" if take == "source-motion" else "G1生成 → 人物重定向 + 已披露IK/接触校正")
	_update_panels("front")

func _process(delta: float) -> void:
	if not active or paused or recording: return
	section_elapsed += delta
	var view_index: int = mini(2, int(section_elapsed / maxf(0.1, float(_clip()["display_seconds"]) / 3.0)))
	_update_panels(VIEWS[view_index])

func _source_points() -> Array:
	var motion: Dictionary = (source_data["motions"] as Dictionary)[str(_clip()["motion_id"])] as Dictionary
	var frames: Array = motion["global_positions"] as Array
	var frame_value: float = minf(section_elapsed * float(motion["fps"]), float(frames.size() - 1))
	var frame_index: int = int(frame_value)
	var weight: float = frame_value - frame_index
	var points: Array[Vector3] = []
	for index: int in (source_data["joint_names"] as Array).size():
		var a: Array = (frames[frame_index] as Array)[index] as Array
		var b: Array = (frames[mini(frame_index + 1, frames.size() - 1)] as Array)[index] as Array
		points.append(Vector3(float(a[0]), float(a[1]), float(a[2])).lerp(Vector3(float(b[0]), float(b[1]), float(b[2])), weight))
	return points

func _update_proxy(panel: Dictionary) -> void:
	var points: Array = _source_points()
	var nodes: Array = panel["proxy_nodes"] as Array
	for index: int in nodes.size(): (nodes[index] as Node3D).position = points[index] as Vector3
	for link: Dictionary in panel["proxy_links"] as Array:
		var start: Vector3 = points[int(link["parent"])] as Vector3
		var finish: Vector3 = points[int(link["child"])] as Vector3
		var difference: Vector3 = finish - start
		var bone: Node3D = link["node"] as Node3D
		bone.position = (start + finish) * 0.5
		bone.basis = Basis(Quaternion(Vector3.UP, difference.normalized())) if difference.length() > 0.000001 else Basis.IDENTITY
		bone.scale = Vector3(1, maxf(0.000001, difference.length()), 1)

func _root(panel: Dictionary) -> Vector3:
	if panel["id"] == "source":
		return _source_points()[int(source_data["root_index"])] as Vector3
	var skeleton: Skeleton3D = panel["skeleton"] as Skeleton3D
	return skeleton.global_transform * skeleton.get_bone_global_pose(int(panel["root_index"])).origin

func _update_panels(view: String) -> void:
	for panel: Dictionary in panels:
		if panel["id"] == "source": _update_proxy(panel)
		var centre: Vector3 = _root(panel)
		var camera: Camera3D = panel["camera"] as Camera3D
		# Fixed per-action framing: do not pump camera scale with individual poses.
		var wide_action: bool = str(_clip()["official_mode"]) == "hand_crawling"
		if wide_action: centre.z += 0.3
		camera.size = 4.3 if wide_action and panels.size() == 3 else 3.0 if wide_action else 2.6 if str(_clip()["official_mode"]) == "walk_boxing" and panels.size() == 3 else 2.35
		var direction := Vector3(0, 0.95, 6) if view == "front" else Vector3(6, 0.95, 0) if view == "right" else Vector3(4.5, 1.0, 4.5)
		camera.position = centre + direction
		camera.look_at(centre)
		panel["last_view"] = view
		var label: Label = panel["label"] as Label
		label.text = ("G1 34关节源代理" if panel["id"] == "source" else str(NAMES[panel["id"]])) + " · " + str(VIEW_NAMES[view])

func _snapshot(panel: Dictionary) -> Dictionary:
	var root: Vector3 = _root(panel)
	if panel["id"] == "source":
		var points: Array = _source_points()
		var positions: Array = []
		for point: Vector3 in points: positions.append([point.x, point.y, point.z])
		return {"source_time":minf(section_elapsed, float(_clip()["duration_s"])), "root":[root.x, root.y, root.z], "joint_positions":positions, "source_proxy":true}
	var ap: AnimationPlayer = panel["ap"] as AnimationPlayer
	var skeleton: Skeleton3D = panel["skeleton"] as Skeleton3D
	var bones: Dictionary = {}
	for index: int in panel["watched"] as Array:
		var world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(index)
		bones[str(skeleton.get_bone_name(index))] = [world.origin.x, world.origin.y, world.origin.z, world.basis.x.x, world.basis.x.y, world.basis.x.z, world.basis.y.x, world.basis.y.y, world.basis.y.z, world.basis.z.x, world.basis.z.y, world.basis.z.z]
	return {"assigned_clip":ap.assigned_animation, "clip_time":ap.current_animation_position, "playing":ap.is_playing(), "root":[root.x, root.y, root.z], "bones":bones, "original_materials":true, "game_modifiers_attached":false, "animation_callback_mode_process":ap.callback_mode_process, "ap_relative_path":str((panel["model"] as Node).get_path_to(ap)), "ap_import_id":ap.get_meta("import_id") if ap.has_meta("import_id") else ""}

func _record() -> void:
	for warm_frame: int in range(15): await get_tree().process_frame
	for index: int in (config["clips"] as Array).size():
		_start_clip(index)
		var clip: Dictionary = _clip()
		var count: int = int(clip["display_frames"])
		var first: int = Engine.get_frames_drawn()
		for frame: int in count:
			section_elapsed = float(frame) / 30.0
			for panel: Dictionary in panels:
				if panel["id"] != "source":
					var sample_player: AnimationPlayer = panel["ap"] as AnimationPlayer
					sample_player.seek(section_elapsed, true)
			var view: String = VIEWS[mini(2, frame * 3 / count)]
			_update_panels(view)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var state: Dictionary = {}
			for panel: Dictionary in panels: state[str(panel["id"])] = _snapshot(panel)
			rows.append({"drawn_frame":Engine.get_frames_drawn(), "process_frame":Engine.get_process_frames(), "clip":clip["clip"], "motion_id":clip["motion_id"], "view":view, "source_frame_index":frame, "source_time":section_elapsed, "actors":state})
			var capture_frames: Array = [count / 6, count / 2, count * 5 / 6] if stills_only else [0, count / 2, count - 1]
			if frame in capture_frames:
				var filename: String = "%02d-%s-%s.png" % [index + 1, str(clip["motion_id"]), view] if stills_only else "native-%02d-%s-f%04d-%s.png" % [index + 1, str(clip["motion_id"]), frame, view]
				var image_error: Error = get_viewport().get_texture().get_image().save_png(output.path_join(filename))
				assert(image_error == OK)
				stills.append({"file":filename, "drawn_frame":Engine.get_frames_drawn(), "source_frame_index":frame, "source_time":section_elapsed, "clip":clip["clip"], "motion_id":clip["motion_id"], "view":view, "actors":state})

		sections.append({"motion_id":clip["motion_id"], "clip":clip["clip"], "label":clip["label"], "source_duration_s":clip["duration_s"], "display_frames":count, "start_drawn_exclusive":first, "end_drawn_inclusive":Engine.get_frames_drawn(), "tail_policy":clip["tail_policy"], "cross_clip_transition_claimed":false})
		print("MOTIONBRICKS_POC_SECTION ", JSON.stringify(sections.back()))
	active = false
	FileAccess.open(output.path_join("movie-journal.json"), FileAccess.WRITE).store_string(JSON.stringify({"kind":"MotionBricks G1 source/retarget independent POC", "take":take, "fps":30, "engine":Engine.get_version_info().string, "frames":rows, "sections":sections, "failures":failures, "source_config_sha256":config["input_manifest_sha256"], "no_game_controllers":true, "record_evaluation":"Native AnimationPlayer MANUAL exact source n/30, no auto advance, no frame synthesis/loop/hold extension"}))
	FileAccess.open(output.path_join("native-stills.json"), FileAccess.WRITE).store_string(JSON.stringify({"shots":stills, "expected":(config["clips"] as Array).size() * 3, "same_frame_pose_and_png":true, "capture_mode":"exact source sample n/30 via native AnimationPlayer seek/update; original GLB tracks/materials, no source resampling/loop/extra terminal holds", "native_vs_AVI_frame_index":"Must independently compare native PNG against AVI neighboring frames before asserting trim correspondence"}))
	print("MOTIONBRICKS_POC_DONE ", JSON.stringify({"frames":rows.size(), "sections":sections.size(), "take":take}))
	get_tree().quit(0)

func _unhandled_key_input(event: InputEvent) -> void:
	if recording or not event is InputEventKey or not event.is_pressed() or event.is_echo(): return
	match (event as InputEventKey).keycode:
		KEY_RIGHT: _start_clip((clip_index + 1) % (config["clips"] as Array).size())
		KEY_LEFT: _start_clip((clip_index - 1 + (config["clips"] as Array).size()) % (config["clips"] as Array).size())
		KEY_R: _start_clip(clip_index)
		KEY_ESCAPE: get_tree().quit()

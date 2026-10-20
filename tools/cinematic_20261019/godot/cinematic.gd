extends Control
## Film driver for the isolated clone. The game's own main scene builds the world;
## this script owns the clock, camera, actors and props. Every frame is a pure
## function of film time, so PNG capture speed cannot change the edit.

const FILM_FX = preload("res://cinematic/film_fx.gd")

const FPS := 24
const TOTAL_FRAMES := 1344
const IGNITION_T := 11.05
const FADE_OUT_T := 52.0
const TITLE_IN_T := 44.0

const SORA_TREE := Vector3(3.31, 0.02, 5.87)
const MIO_START := Vector3(1.31, 0.02, 14.0)
const MIO_END := Vector3(1.31, 0.02, 8.84)
const SORA_S6 := Vector3(2.90, 0.02, 8.90)
const MIO_S6 := Vector3(4.35, 0.02, 9.30)
const SORA_S7 := Vector3(-6.20, 0.02, 14.20)
const MIO_S7 := Vector3(-6.30, 0.02, 16.00)
const SORA_S8 := Vector3(-3.20, 0.02, 15.00)
const MIO_S8 := Vector3(-1.40, 0.02, 15.30)
const LANTERN_HOOK := Vector3(3.30, 1.88, 6.16)
const YAGURA := Vector3(-2.6, 0.0, 18.8)

const CLIP_SORA_WALK := "motionbricks_poc_sora_walk"
const CLIP_SORA_LOOK := "motionbricks_poc_look_up_wonder"
const CLIP_SORA_STOP_LOOK := "motionbricks_poc_sora_stop_look_up"
const CLIP_SORA_REACH := "motionbricks_poc_sora_reach_lantern"
const CLIP_SORA_TURN := "motionbricks_poc_sora_turn_wave"
const CLIP_MIO_WALK := "motionbricks_poc_mio_walk"
const CLIP_MIO_WAVE := "motionbricks_poc_mio_wave"
const CLIP_MIO_LOOK := "motionbricks_poc_look_up_wonder"

const SHOT_STARTS := [0.0, 5.0, 9.0, 14.0, 19.0, 24.0, 29.0, 34.0, 39.0]
const SHOT_ENDS := [5.0, 9.0, 14.0, 19.0, 24.0, 29.0, 34.0, 39.0, 56.0]
const SHOT_MINUTES := [
	Vector2(17.34, 17.42),
	Vector2(17.62, 17.67),
	Vector2(17.92, 18.00),
	Vector2(18.28, 18.35),
	Vector2(18.58, 18.64),
	Vector2(18.88, 18.94),
	Vector2(19.18, 19.24),
	Vector2(19.90, 19.98),
	Vector2(20.55, 20.85),
]

var sub: SubViewport
var main: Node3D
var world: WorldBuilder
var sora: Player
var mio: NPC
var sora_ap: AnimationPlayer
var mio_ap: AnimationPlayer
var npcs: Dictionary = {}
var cam: Camera3D
var attrs: CameraAttributesPractical
var fx: Node3D

var lantern: Node3D
var lantern_light: OmniLight3D
var lantern_glow: Sprite3D
var lantern_materials: Array[StandardMaterial3D] = []

var overlay: CanvasLayer
var title_label: Label
var subtitle_label: Label
var fade_rect: ColorRect

var dancer_ids: Array[String] = ["ren", "haru", "aoi", "tanaka", "kazuko"]
var dancer_offsets: Array[float] = [0.0, 0.9, 1.8, 2.7, 0.45]
var shot_index := -1
var failures: Array[String] = []


func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_position(Vector2i(80, 80))
	DisplayServer.screen_set_keep_on(true)
	get_window().grab_focus()
	_mute_all()
	sub = $SubViewport as SubViewport
	sub.size = Vector2i(1920, 1080)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var preview := TextureRect.new()
	preview.texture = sub.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview)
	move_child(preview, 0)

	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("cinematic: missing main scene")
		get_tree().quit(2)
		return
	main = packed.instantiate() as Node3D
	sub.add_child(main)
	var waited := 0
	while not bool(main.get("loading_ready")):
		await get_tree().process_frame
		waited += 1
		if waited > 3600:
			push_error("cinematic: world did not become ready")
			get_tree().quit(2)
			return
	await _configure()
	await _render()


func _mute_all() -> void:
	for i in AudioServer.bus_count:
		AudioServer.set_bus_mute(i, true)


func _configure() -> void:
	world = main.get("world") as WorldBuilder
	sora = main.get("player") as Player
	npcs = main.get("npcs") as Dictionary
	mio = npcs.get("mio") as NPC
	if world == null or sora == null or mio == null:
		failures.append("main scene did not expose world/player/npcs")
		return
	sora_ap = sora.anim.ap
	mio_ap = mio.anim.ap
	if sora_ap == null or mio_ap == null:
		failures.append("characters have no AnimationPlayer")

	GameState.new_game()
	GameState.day = 17
	GameState.weather = "sunny"
	GameState.phase = "prep"
	GameState.minute = 17.34 * 60.0
	GameState.clock_paused = true
	GameState.player_in_room = false
	main.set("in_room", false)

	main.set_process(false)
	main.set_physics_process(false)
	main.set_process_unhandled_input(false)
	_stop_node(main.get("rig") as Node)
	_stop_node(main.get("ui") as Node)
	_stop_node(main.get("story") as Node)
	_stop_node(main.get("placement") as Node)
	_stop_node(main.get("calendar") as Node)
	_stop_node(main.get("shop_life") as Node)
	_stop_node(main.get("photo") as Node)
	_stop_node(main.get("life") as Node)
	_stop_node(main.get("weather_fx") as Node)
	_stop_node(main.get_node_or_null("EnvironmentLife"))
	_stop_node(world.bus as Node)
	world.set_process(false)
	for child: Node in main.get_children():
		if child == world or child == sora or npcs.values().has(child):
			continue
		_stop_node(child)

	var rig: CameraRig = main.get("rig") as CameraRig
	if rig != null and rig.get("cam") != null:
		var old_cam: Camera3D = rig.get("cam") as Camera3D
		if old_cam != null:
			old_cam.current = false
	var ui: CanvasLayer = main.get("ui") as CanvasLayer
	if ui != null:
		ui.visible = false
	var marker: Node3D = main.get("marker") as Node3D
	if marker != null:
		marker.visible = false
	var weather_fx: WeatherFX = main.get("weather_fx") as WeatherFX
	if weather_fx != null and weather_fx.has_method("set_weather"):
		weather_fx.call("set_weather", "sunny", false)

	NPC.roam_enabled = false
	NPC.freeze = true
	sora.frozen = true
	sora.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	sora.set_process(false)
	sora.set_physics_process(false)
	sora.set_process_unhandled_input(false)
	sora.visible = true
	_prepare_manual(sora_ap)
	# The follow-camera body fade may have left avatar meshes fully transparent
	# before the rig was stopped; the film camera must see them.
	for mi in WorldBuilder.find_meshes(sora.model):
		mi.transparency = 0.0

	for id: String in npcs:
		var n: NPC = npcs[id] as NPC
		if n == null:
			continue
		n.hold = true
		n.set_process(false)
		n.set_physics_process(false)
		n.set_home(false)
		n.visible = true
		n.tag.visible = false
		n.talk.radius = 0.0
		if n.anim != null and n.anim.ap != null:
			_prepare_manual(n.anim.ap)

	world.set_region("town")
	world.apply_phase("prep", false)
	world.set_crop_stage(0, false)
	world.sync_festivals()
	world.bus.park_at_stop()
	world.update_time(GameState.minute, GameState.weather, true)

	var env: Environment = world.env
	if env != null:
		env.glow_enabled = true
		env.glow_intensity = 0.65
		env.glow_strength = 1.05
		env.glow_bloom = 0.08
		env.glow_hdr_threshold = 0.85
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = 1.03

	cam = Camera3D.new()
	cam.name = "FilmCamera"
	cam.fov = 45.0
	cam.near = 0.03
	cam.far = 600.0
	attrs = CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 6.0
	attrs.dof_blur_far_transition = 4.0
	attrs.dof_blur_amount = 0.05
	attrs.dof_blur_near_enabled = false
	cam.attributes = attrs
	sub.add_child(cam)
	cam.current = true

	_build_overlay()
	_build_lantern()
	_build_fireworks()
	_place_dancers()


func _stop_node(node: Node) -> void:
	if node == null:
		return
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_unhandled_input(false)
	node.process_mode = Node.PROCESS_MODE_DISABLED


func _prepare_manual(ap: AnimationPlayer) -> void:
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 20
	sub.add_child(overlay)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(root)

	var top := ColorRect.new()
	top.color = Color.BLACK
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 139.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var bottom := ColorRect.new()
	bottom.color = Color.BLACK
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -139.0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)

	var font := load("res://assets/fonts/LXGWWenKai-Medium.ttf") as Font
	title_label = Label.new()
	title_label.text = "灯，又亮起来了"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.position = Vector2(0.0, 782.0)
	title_label.size = Vector2(1920.0, 110.0)
	title_label.add_theme_font_override("font", font)
	title_label.add_theme_font_size_override("font_size", 64)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.84, 1.0))
	title_label.add_theme_constant_override("outline_size", 12)
	title_label.add_theme_color_override("font_outline_color", Color(0.07, 0.05, 0.04, 0.72))
	title_label.modulate.a = 0.0
	root.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.text = "H A R U M A C H I   ·   N E X T   S U M M E R"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.position = Vector2(0.0, 884.0)
	subtitle_label.size = Vector2(1920.0, 44.0)
	subtitle_label.add_theme_font_override("font", font)
	subtitle_label.add_theme_font_size_override("font_size", 19)
	subtitle_label.add_theme_color_override("font_color", Color(1.0, 0.89, 0.72, 0.92))
	subtitle_label.add_theme_constant_override("outline_size", 6)
	subtitle_label.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.03, 0.6))
	subtitle_label.modulate.a = 0.0
	root.add_child(subtitle_label)

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade_rect)


func _build_lantern() -> void:
	_add_cylinder(Vector3(4.0, 2.95, 6.92), Vector3(3.30, 2.84, 6.16), 0.055, Color(0.16, 0.11, 0.08))
	_add_cylinder(Vector3(3.30, 2.84, 6.16), Vector3(3.30, 1.90, 6.16), 0.011, Color(0.05, 0.04, 0.035))
	var packed: PackedScene = WorldBuilder.model_scene("P_chochin_red")
	if packed == null:
		failures.append("missing P_chochin_red")
		return
	lantern = packed.instantiate() as Node3D
	world.add_child(lantern)
	lantern.global_position = LANTERN_HOOK
	lantern.scale = Vector3.ONE * 0.82
	lantern.rotation.y = deg_to_rad(-25.0)
	for mesh: MeshInstance3D in lantern.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface: int in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var copy := source.duplicate() as StandardMaterial3D
			copy.emission_enabled = true
			copy.emission = Color(1.0, 0.42, 0.16)
			copy.emission_energy_multiplier = 0.0
			mesh.set_surface_override_material(surface, copy)
			lantern_materials.append(copy)

	lantern_light = OmniLight3D.new()
	lantern_light.light_color = Color(1.0, 0.56, 0.28)
	lantern_light.omni_range = 6.5
	lantern_light.light_energy = 0.0
	lantern_light.shadow_enabled = false
	lantern_light.position = Vector3(0.0, -0.32, 0.0)
	lantern.add_child(lantern_light)

	var glow_gradient := GradientTexture2D.new()
	glow_gradient.width = 128
	glow_gradient.height = 128
	glow_gradient.fill = GradientTexture2D.FILL_RADIAL
	glow_gradient.fill_from = Vector2(0.5, 0.5)
	glow_gradient.fill_to = Vector2(1.0, 0.5)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.14, 0.34, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.80, 0.50, 0.55),
		Color(1.0, 0.52, 0.24, 0.26),
		Color(1.0, 0.26, 0.12, 0.0),
		Color(1.0, 0.26, 0.12, 0.0),
	])
	glow_gradient.gradient = gradient
	lantern_glow = Sprite3D.new()
	lantern_glow.texture = glow_gradient
	lantern_glow.pixel_size = 0.0058
	lantern_glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lantern_glow.no_depth_test = false
	lantern_glow.render_priority = 2
	lantern_glow.position = Vector3(0.0, -0.16, 0.0)
	lantern_glow.modulate = Color(1.0, 0.72, 0.42, 0.0)
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.vertex_color_use_as_albedo = true
	glow_material.albedo_texture = glow_gradient
	glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	lantern_glow.material_override = glow_material
	lantern.add_child(lantern_glow)


func _add_cylinder(a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	cylinder.rings = 1
	var mesh := MeshInstance3D.new()
	mesh.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var direction := (b - a).normalized()
	var reference := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var side := reference.cross(direction).normalized()
	var other := side.cross(direction).normalized()
	var basis := Basis(side, direction, other).scaled(Vector3(1.0, a.distance_to(b), 1.0))
	mesh.transform = Transform3D(basis, (a + b) * 0.5)
	world.add_child(mesh)


func _build_fireworks() -> void:
	fx = FILM_FX.new() as Node3D
	world.add_child(fx)
	var events: Array[Dictionary] = [
		_firework(IGNITION_T, LANTERN_HOOK + Vector3(0.0, -0.28, 0.0), Color(1.0, 0.74, 0.38), 901, 26, 0.7, 1.7, 0.0, 0.5, 0.45, 0.75),
		_firework(34.8, Vector3(-7.0, 9.5, 23.0), Color(1.0, 0.80, 0.35), 101, 82, 7.0, 12.0, 0.9, 2.6),
		_firework(35.9, Vector3(-1.5, 11.5, 25.0), Color(1.0, 0.48, 0.55), 102, 74, 7.0, 11.5, 0.9, 2.4),
		_firework(37.0, Vector3(3.0, 9.0, 22.0), Color(0.52, 0.82, 1.0), 103, 78, 7.5, 12.5, 0.9, 2.5),
		_firework(38.2, Vector3(-4.0, 12.0, 26.0), Color(1.0, 0.92, 0.72), 104, 108, 8.0, 14.0, 1.0, 3.2),
		_firework(39.6, Vector3(-8.5, 10.5, 24.0), Color(0.82, 0.62, 1.0), 105, 86, 7.0, 12.0, 0.9, 2.6),
		_firework(40.8, Vector3(-0.5, 9.5, 22.0), Color(0.65, 1.0, 0.62), 106, 82, 7.5, 12.5, 0.9, 2.5),
		_firework(42.3, Vector3(4.5, 11.0, 25.0), Color(1.0, 0.52, 0.72), 107, 90, 7.0, 12.0, 0.9, 2.7),
		_firework(43.8, Vector3(-6.0, 12.5, 27.0), Color(1.0, 0.86, 0.45), 108, 110, 8.0, 14.5, 1.0, 3.3),
		_firework(45.6, Vector3(-2.0, 10.0, 23.0), Color(0.55, 0.86, 1.0), 109, 84, 7.0, 12.0, 0.9, 2.6),
		_firework(47.4, Vector3(2.0, 11.5, 26.0), Color(1.0, 0.62, 0.75), 110, 92, 7.5, 13.0, 0.9, 2.8),
		_firework(49.3, Vector3(-8.0, 11.0, 25.0), Color(1.0, 0.96, 0.82), 111, 88, 7.5, 13.0, 0.9, 2.8),
		_firework(51.0, Vector3(-3.0, 12.0, 26.0), Color(1.0, 0.82, 0.40), 112, 116, 8.0, 15.0, 1.0, 3.4),
	]
	fx.call("setup", cam, events)


func _firework(time: float, pos: Vector3, color: Color, seed_value: int, count: int,
		speed_min: float, speed_max: float, rise: float, flash_size: float,
		life_min: float = 1.2, life_max: float = 2.3) -> Dictionary:
	return {
		"time": time,
		"pos": pos,
		"color": color,
		"seed": seed_value,
		"count": count,
		"speed_min": speed_min,
		"speed_max": speed_max,
		"rise": rise,
		"flash_size": flash_size,
		"life_min": life_min,
		"life_max": life_max,
	}


func _place_dancers() -> void:
	var angles: Array[float] = [15.0, 65.0, 115.0, 165.0, 205.0]
	for i in dancer_ids.size():
		var n: NPC = npcs.get(dancer_ids[i]) as NPC
		if n == null:
			continue
		var angle := deg_to_rad(angles[i])
		var pos := YAGURA + Vector3(cos(angle), 0.0, sin(angle)) * 3.8
		var to_center := YAGURA - pos
		var yaw := rad_to_deg(atan2(to_center.x, to_center.z))
		n.place(Vector3(pos.x, 0.02, pos.z), yaw)
		n.set_pose("dance")
		n.visible = true
		n.tag.visible = false
		if n.anim != null and n.anim.ap != null:
			_prepare_manual(n.anim.ap)


func _render() -> void:
	var stills_dir := _argument("--film-stills=")
	var capture_dir := _argument("--film-capture=")
	if not failures.is_empty():
		for failure: String in failures:
			push_error("cinematic: " + failure)
		_write_status({}, "failed")
		get_tree().quit(1)
		return
	if not stills_dir.is_empty():
		await _render_stills(stills_dir)
	elif not capture_dir.is_empty():
		await _render_frames(capture_dir)
	else:
		_set_film_time(0.0)
		await get_tree().process_frame
		_write_status({}, "preview-only")
		get_tree().quit(2)


func _render_stills(output: String) -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var targets: Array[Dictionary] = [
		{"name": "S1_walk", "t": 2.5},
		{"name": "S2_lookup", "t": 7.0},
		{"name": "S3_ignite", "t": 11.8},
		{"name": "S4_arrival", "t": 16.5},
		{"name": "S5_greeting", "t": 21.5},
		{"name": "S6_depart", "t": 26.5},
		{"name": "S6_depart_late", "t": 28.2},
		{"name": "S7_festival_walk", "t": 31.5},
		{"name": "S8_fireworks", "t": 37.6},
		{"name": "S9_reveal", "t": 47.0},
		{"name": "S9_wide", "t": 51.0},
	]
	var rows: Array[Dictionary] = []
	for target: Dictionary in targets:
		var t: float = float(target["t"])
		_set_film_time(t)
		for settle: int in 3:
			await get_tree().process_frame
		RenderingServer.force_draw(false)
		var image := sub.get_texture().get_image()
		if image.get_width() != 1920 or image.get_height() != 1080:
			failures.append("wrong still size at %s: %s" % [target["name"], image.get_size()])
			continue
		var name_dbg := str(target["name"])
		var file_name := "%s_%05.2f.png" % [name_dbg, t]
		var error := image.save_png(output.path_join(file_name))
		if error != OK:
			failures.append("failed to save " + file_name)
		rows.append({"name": target["name"], "t": t, "file": file_name, "shot": shot_index})
		print("FILM_STILL ", JSON.stringify(rows.back()))
	_write_status({"mode": "stills", "output": output, "stills": rows, "failures": failures}, "ok" if failures.is_empty() else "failed")
	get_tree().quit(0 if failures.is_empty() else 1)


func _render_frames(output: String) -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var started := Time.get_ticks_usec()
	for frame: int in TOTAL_FRAMES:
		_set_film_time(float(frame) / float(FPS))
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		var image := sub.get_texture().get_image()
		if image.get_width() != 1920 or image.get_height() != 1080:
			failures.append("wrong frame size at %d: %s" % [frame, image.get_size()])
			break
		var path := output.path_join("%05d.png" % frame)
		var error := image.save_png(path)
		if error != OK:
			failures.append("failed to save frame %d" % frame)
			break
		if frame % 96 == 0:
			var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
			print("FILM_FRAME %d/%d elapsed %.1fs" % [frame, TOTAL_FRAMES, elapsed])
	var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
	_write_status({
		"mode": "frames",
		"output": output,
		"fps": FPS,
		"frames": TOTAL_FRAMES,
		"seconds": float(TOTAL_FRAMES) / float(FPS),
		"elapsed_seconds": elapsed,
		"failures": failures,
	}, "ok" if failures.is_empty() else "failed")
	get_tree().quit(0 if failures.is_empty() else 1)


func _write_status(payload: Dictionary, status: String) -> void:
	var data := {
		"status": status,
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"viewport": [sub.size.x, sub.size.y],
		"fps": FPS,
		"total_frames": TOTAL_FRAMES,
		"shot_starts": SHOT_STARTS,
		"shot_ends": SHOT_ENDS,
		"failures": failures,
	}
	for key: String in payload:
		data[key] = payload[key]
	var path := OS.get_environment("HARUMACHI_FILM_STATUS")
	if path.is_empty():
		path = "user://cinematic_status.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	print("FILM_STATUS ", JSON.stringify({"status": status, "failures": failures.size(), "frames": TOTAL_FRAMES}))


func _set_film_time(t: float) -> void:
	var index := _shot_at(t)
	if index != shot_index:
		shot_index = index
		_enter_shot(index)
	var start: float = float(SHOT_STARTS[index])
	var end: float = float(SHOT_ENDS[index])
	var duration: float = end - start
	var local: float = clampf(t - start, 0.0, duration)
	var minutes: Vector2 = SHOT_MINUTES[index]
	var minute: float = lerpf(minutes.x, minutes.y, clampf(local / maxf(duration, 0.001), 0.0, 1.0)) * 60.0
	GameState.minute = minute
	world.update_time(minute, "sunny", false)
	var env: Environment = world.env
	if env != null:
		env.adjustment_contrast = 1.03
		env.adjustment_saturation = float(world.look.get("sat", 1.0)) + 0.02
	_update_shot(index, local, t)
	_update_lantern(t)
	_update_swing(t)
	_update_dancers(t)
	_update_overlay(t)
	if fx != null:
		fx.call("update_time", t)


func _shot_at(t: float) -> int:
	for i in SHOT_STARTS.size():
		if t < float(SHOT_ENDS[i]) or i == SHOT_STARTS.size() - 1:
			return i
	return SHOT_STARTS.size() - 1


func _enter_shot(index: int) -> void:
	_show("sora", true)
	_show("mio", index >= 3)
	match index:
		0:
			_place_sora(SORA_TREE + Vector3(0.59, 0.0, -4.47), 0.0)
			_seek_clip(sora_ap, CLIP_SORA_WALK, 0.0)
		1:
			_place_sora(SORA_TREE, 0.0)
			_seek_clip(sora_ap, CLIP_SORA_LOOK, 0.15)
		2:
			_place_sora(SORA_TREE, 0.0)
			_seek_clip(sora_ap, CLIP_SORA_REACH, 0.0)
		3:
			_place_sora(SORA_TREE, 0.0)
			_seek_loop(sora_ap, "idle", 0.0)
			_place_mio(MIO_START, 180.0)
			_seek_clip(mio_ap, CLIP_MIO_WALK, 0.0)
		4:
			_place_sora(SORA_TREE, 0.0)
			_seek_clip(sora_ap, CLIP_SORA_TURN, 0.0)
			_place_mio(MIO_END, 146.0)
			_seek_clip(mio_ap, CLIP_MIO_WAVE, 0.0)
		5:
			_place_sora(SORA_S6, 0.0)
			_seek_clip(sora_ap, CLIP_SORA_WALK, 0.0)
			_place_mio(MIO_S6, 0.0)
			_seek_clip(mio_ap, CLIP_MIO_WALK, 0.0)
		6:
			_place_sora(SORA_S7, 90.0)
			_seek_clip(sora_ap, CLIP_SORA_WALK, 0.0)
			_place_mio(MIO_S7, 90.0)
			_seek_clip(mio_ap, CLIP_MIO_WALK, 0.0)
		7:
			_place_sora(SORA_S8, 8.0)
			_seek_clip(sora_ap, CLIP_SORA_STOP_LOOK, 0.0)
			_place_mio(MIO_S8, -8.0)
			_seek_clip(mio_ap, CLIP_MIO_LOOK, 0.0)
		8:
			_place_sora(SORA_S8, 8.0)
			_seek_clip(sora_ap, CLIP_SORA_STOP_LOOK, 4.95)
			_place_mio(MIO_S8, -8.0)
			_seek_clip(mio_ap, CLIP_MIO_LOOK, 4.95)


func _update_shot(index: int, local: float, t: float) -> void:
	var duration: float = float(SHOT_ENDS[index]) - float(SHOT_STARTS[index])
	match index:
		0:
			_camera_lerp(local, duration, Vector3(9.8, 2.4, 1.5), Vector3(7.7, 2.1, 3.7),
				Vector3(4.2, 1.0, 2.4), Vector3(3.4, 1.05, 5.2), 44.0, 43.0, 5.6, 0.3, 0.9, t)
			_seek_clip(sora_ap, CLIP_SORA_WALK, local)
		1:
			_camera_lerp(local, duration, Vector3(6.4, 1.15, 4.2), Vector3(6.1, 1.25, 4.5),
				Vector3(3.35, 1.40, 6.0), Vector3(3.35, 2.15, 6.35), 39.0, 37.0, 3.4, -0.2, 0.55, t)
			_seek_clip(sora_ap, CLIP_SORA_LOOK, 0.15 + local)
		2:
			_camera_lerp(local, duration, Vector3(5.35, 1.22, 4.95), Vector3(5.10, 1.27, 5.05),
				Vector3(3.35, 1.50, 6.12), Vector3(3.33, 1.62, 6.14), 37.0, 35.0, 2.5, 0.1, 0.4, t)
			_seek_clip(sora_ap, CLIP_SORA_REACH, local * 0.85)
		3:
			_camera_lerp(local, duration, Vector3(2.3, 1.60, 3.6), Vector3(2.5, 1.58, 4.1),
				Vector3(3.2, 1.30, 6.4), Vector3(3.0, 1.30, 6.8), 42.0, 40.0, 3.5, -0.1, 0.6, t)
			_seek_loop(sora_ap, "idle", local)
			_seek_clip(mio_ap, CLIP_MIO_WALK, local)
		4:
			_camera_lerp(local, duration, Vector3(0.5, 1.62, 11.8), Vector3(0.8, 1.57, 11.1),
				Vector3(2.0, 1.25, 7.9), Vector3(2.3, 1.22, 7.1), 39.0, 38.0, 4.5, 0.15, 0.6, t)
			_seek_clip(sora_ap, CLIP_SORA_TURN, local * 0.8)
			_seek_clip(mio_ap, CLIP_MIO_WAVE, maxf(0.0, local - 0.8) * 0.75)
		5:
			_camera_lerp(local, duration, Vector3(0.6, 2.85, 4.0), Vector3(0.8, 2.95, 5.3),
				Vector3(3.2, 1.05, 8.8), Vector3(3.45, 1.15, 13.2), 46.0, 45.0, 7.0, 0.0, 0.85, t)
			_seek_clip(sora_ap, CLIP_SORA_WALK, local)
			_seek_clip(mio_ap, CLIP_MIO_WALK, local)
		6:
			_camera_lerp(local, duration, Vector3(-4.4, 1.45, 10.3), Vector3(0.4, 1.55, 10.5),
				Vector3(-4.9, 1.20, 13.6), Vector3(-0.2, 1.20, 15.0), 45.0, 47.0, 5.5, -0.15, 0.95, t)
			_seek_clip(sora_ap, CLIP_SORA_WALK, local)
			_seek_clip(mio_ap, CLIP_MIO_WALK, local)
		7:
			_camera_lerp(local, duration, Vector3(-2.50, 1.10, 12.2), Vector3(-2.45, 1.30, 12.6),
				Vector3(-1.5, 2.30, 16.4), Vector3(-1.5, 2.80, 16.8), 56.0, 54.0, 3.6, 0.0, 0.5, t)
			_seek_clip(sora_ap, CLIP_SORA_STOP_LOOK, local)
			_seek_clip(mio_ap, CLIP_MIO_LOOK, local)
		8:
			var u: float = clampf(local / duration, 0.0, 1.0)
			var eased: float = u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
			var position: Vector3 = Vector3(-4.8, 1.8, 11.5).lerp(Vector3(-10.2, 11.5, 0.0), eased)
			var target: Vector3 = Vector3(-2.5, 2.2, 16.6).lerp(Vector3(-1.0, 5.6, 19.0), eased)
			_set_cam(position, target, lerpf(54.0, 64.0, eased), 20.0, lerpf(-0.4, 0.4, eased), 0.35, t)
			_seek_clip(sora_ap, CLIP_SORA_STOP_LOOK, 4.95)
			_seek_clip(mio_ap, CLIP_MIO_LOOK, 4.95)


func _camera_lerp(local: float, duration: float, from_pos: Vector3, to_pos: Vector3,
		from_look: Vector3, to_look: Vector3, from_fov: float, to_fov: float,
		focus: float, roll: float, handheld: float, t: float) -> void:
	var u: float = clampf(local / maxf(duration, 0.001), 0.0, 1.0)
	var eased: float = u * u * (3.0 - 2.0 * u)
	_set_cam(from_pos.lerp(to_pos, eased), from_look.lerp(to_look, eased),
		lerpf(from_fov, to_fov, eased), focus, roll, handheld, t)


func _set_cam(position: Vector3, target: Vector3, fov: float, focus: float,
		roll: float, handheld: float, t: float) -> void:
	var shake := Vector3(
		sin(t * 0.83 + 0.4) + 0.4 * sin(t * 2.11 + 1.7),
		sin(t * 0.71 + 2.2) + 0.4 * sin(t * 1.63 + 0.3),
		sin(t * 0.97 + 1.1) + 0.4 * sin(t * 1.31 + 2.8)) * (0.008 * handheld)
	cam.global_position = position + shake
	var look := target + shake * 0.5
	if cam.global_position.distance_to(look) > 0.01:
		cam.look_at(look, Vector3.UP)
	cam.rotate_object_local(Vector3(0.0, 0.0, 1.0), deg_to_rad(roll + sin(t * 0.37 + 0.6) * 0.15 * handheld))
	cam.fov = fov
	attrs.dof_blur_far_distance = focus
	attrs.dof_blur_far_transition = maxf(1.6, focus * 0.75)
	attrs.dof_blur_amount = 0.045 + 0.015 * clampf((6.0 - focus) / 4.0, 0.0, 1.0)


func _update_lantern(t: float) -> void:
	if lantern == null:
		return
	var ramp := clampf((t - IGNITION_T) / 0.9, 0.0, 1.0)
	var flicker := 1.0 + 0.06 * sin(t * 17.0) + 0.03 * sin(t * 29.0 + 1.7)
	var energy := ramp * flicker
	for material: StandardMaterial3D in lantern_materials:
		material.emission_energy_multiplier = 2.8 * energy
	if lantern_light != null:
		lantern_light.light_energy = 2.4 * energy
	if lantern_glow != null:
		lantern_glow.modulate.a = 0.55 * energy
		lantern_glow.scale = Vector3.ONE * (0.86 + 0.05 * sin(t * 2.4))


func _update_swing(t: float) -> void:
	for entry: Variant in world.swing:
		var parts: Array = entry as Array
		var node: Node3D = parts[0] as Node3D
		if not is_instance_valid(node):
			continue
		var phase: float = float(parts[1])
		var yaw: float = float(parts[2])
		node.rotation = Vector3(
			sin(t * 1.1 + phase) * 0.05,
			yaw + sin(t * 0.37 + phase) * 0.12,
			sin(t * 1.4 + phase * 1.7) * 0.07)
	if lantern != null:
		lantern.rotation = Vector3(
			sin(t * 0.9) * 0.035,
			deg_to_rad(-25.0) + sin(t * 0.41) * 0.08,
			sin(t * 1.25) * 0.05)


func _update_dancers(t: float) -> void:
	for i in dancer_ids.size():
		var n: NPC = npcs.get(dancer_ids[i]) as NPC
		if n == null or n.anim == null or n.anim.ap == null:
			continue
		var ap: AnimationPlayer = n.anim.ap
		var clip_name := _clip_name(ap, "dance")
		if clip_name.is_empty():
			continue
		if ap.current_animation != clip_name:
			ap.play(clip_name, 0.0)
		var length: float = ap.get_animation(clip_name).length
		ap.seek(fmod(t * 0.85 + dancer_offsets[i], maxf(length, 0.01)), true)


func _update_overlay(t: float) -> void:
	if fade_rect != null:
		var alpha := 0.0
		if t < 1.2:
			alpha = 1.0 - smoothstep(0.0, 1.2, t)
		elif t >= FADE_OUT_T:
			alpha = smoothstep(FADE_OUT_T, 55.5, t)
		fade_rect.color = Color(0.0, 0.0, 0.0, alpha)
	var title_alpha := 0.0
	if t >= TITLE_IN_T:
		title_alpha = smoothstep(TITLE_IN_T, TITLE_IN_T + 2.4, t) * (1.0 - smoothstep(50.8, 52.0, t))
	if title_label != null:
		title_label.modulate.a = title_alpha
	if subtitle_label != null:
		subtitle_label.modulate.a = title_alpha * 0.9


func _show(id: String, on: bool) -> void:
	if id == "sora":
		sora.visible = on
		return
	var n: NPC = npcs.get(id) as NPC
	if n != null:
		n.visible = on


func _place_sora(position: Vector3, yaw_degrees: float) -> void:
	sora.global_position = position
	sora.reset_physics_interpolation()
	sora.set_facing(deg_to_rad(yaw_degrees))
	sora.visible = true


func _place_mio(position: Vector3, yaw_degrees: float) -> void:
	mio.place(position, yaw_degrees)
	mio.visible = true


func _seek_clip(ap: AnimationPlayer, wanted: String, time: float) -> void:
	if ap == null:
		return
	var clip_name := _clip_name(ap, wanted)
	if clip_name.is_empty():
		failures.append("missing clip " + wanted)
		return
	if ap.current_animation != clip_name:
		ap.play(clip_name, 0.0)
	var length: float = ap.get_animation(clip_name).length
	ap.seek(clampf(time, 0.0, maxf(0.0, length - 0.0001)), true)


func _seek_loop(ap: AnimationPlayer, wanted: String, time: float) -> void:
	if ap == null:
		return
	var clip_name := _clip_name(ap, wanted)
	if clip_name.is_empty():
		failures.append("missing clip " + wanted)
		return
	if ap.current_animation != clip_name:
		ap.play(clip_name, 0.0)
	var length: float = ap.get_animation(clip_name).length
	ap.seek(fmod(time, maxf(length, 0.01)), true)


func _clip_name(ap: AnimationPlayer, wanted: String) -> String:
	if ap.has_animation(wanted):
		return wanted
	for candidate: String in ap.get_animation_list():
		if candidate.ends_with("/" + wanted):
			return candidate
	return ""


func _argument(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""

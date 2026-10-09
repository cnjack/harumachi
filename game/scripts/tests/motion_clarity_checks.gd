extends RefCounted
## Follow the actual avatar at 120 render frames / 60 physics ticks, including W+D+Shift.
var t: Node

func _init(tester: Node) -> void:
	t = tester

func run() -> void:
	var player: Player = t.main.player
	var rig: CameraRig = t.main.rig
	t.check("MOTION_CLARITY", "4x MSAA keeps character edges without the FXAA blur pass", t.get_viewport().msaa_3d == Viewport.MSAA_4X and t.get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED)
	var unfiltered: Array[String] = []
	var actors: Array[Node3D] = [player.model]
	for npc: NPC in t.main.npcs.values(): actors.append(npc.model)
	for actor: Node3D in actors:
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(actor):
			for surface: int in mesh.mesh.get_surface_count():
				var material: BaseMaterial3D = mesh.get_active_material(surface) as BaseMaterial3D
				if material and material.albedo_texture and material.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC:
					unfiltered.append(str(mesh.get_path()))
	t.check("MOTION_CLARITY", "all seven characters retain mipmaps and anisotropic filtering at oblique angles", unfiltered.is_empty(), str(unfiltered))
	var old_fps: int = Engine.max_fps
	Engine.max_fps = 120
	var old_yaw: float = rig.yaw
	var old_pitch: float = rig.pitch
	var old_dist: float = rig.dist
	var old_collide: bool = rig.collide
	var start: Vector3 = player.global_position
	rig.pitch = 35.0; rig.dist = 6.5
	# Keep focal distance fixed for the alignment comparison. Retraction near
	# roofs changes framing intentionally and is exercised by camera-body checks.
	rig.collide = false
	var speeds: Array[float] = []
	for diagonal: bool in [false, true]:
		Input.action_release("move_back")
		Input.action_release("move_right")
		Input.action_release("sprint")
		player.global_position = Vector3(-38, .05, -10)
		player.velocity = Vector3.ZERO
		rig.yaw = 45.0 if diagonal else 0.0
		rig.snap()
		Input.action_press("move_right")
		if diagonal: Input.action_press("move_back")
		Input.action_press("sprint")
		await t.frames(90)
		var low: Vector2 = Vector2(INF, INF)
		var high: Vector2 = Vector2(-INF, -INF)
		var same_tick: int = 0
		var previous_tick: int = -1
		var previous_screen: Vector2 = Vector2.ZERO
		var previous_render_camera: Vector3 = Vector3.ZERO
		var previous_render_player: Vector3 = Vector3.ZERO
		var interpolated_frames: int = 0
		var interpolated_player_frames: int = 0
		var between_ticks: float = 0.0
		for frame: int in 60:
			await t.get_tree().process_frame
			# SceneTree timers fire after the nodes' process callbacks, including the camera.
			await t.get_tree().create_timer(0.0).timeout
			var rendered_player: Vector3 = player.get_global_transform_interpolated().origin
			var camera_transform: Transform3D = rig.cam.get_global_transform_interpolated()
			var camera_local: Vector3 = camera_transform.affine_inverse() * (rendered_player + Vector3.UP)
			var clip: Vector4 = rig.cam.get_camera_projection() * Vector4(camera_local.x, camera_local.y, camera_local.z, 1.0)
			var viewport_size: Vector2 = t.get_viewport().get_visible_rect().size
			var at: Vector2 = Vector2((clip.x / clip.w + 1.0) * .5 * viewport_size.x, (1.0 - clip.y / clip.w) * .5 * viewport_size.y)
			low = low.min(at); high = high.max(at)
			var tick: int = Engine.get_physics_frames()
			var rendered_camera: Vector3 = camera_transform.origin
			if tick == previous_tick:
				same_tick += 1
				between_ticks = maxf(between_ticks, at.distance_to(previous_screen))
				if rendered_camera.distance_to(previous_render_camera) > .0001: interpolated_frames += 1
				if rendered_player.distance_to(previous_render_player) > .0001: interpolated_player_frames += 1
			previous_tick = tick
			previous_screen = at
			previous_render_camera = rendered_camera
			previous_render_player = rendered_player
			speeds.append(Vector2(player.velocity.x, player.velocity.z).length())
		var spread: Vector2 = high - low
		t.check("MOTION_CLARITY", "%s sprint keeps alignment and advances both actor and camera between physics ticks" % ("diagonal W+D" if diagonal else "sideways D"), same_tick >= 10 and between_ticks < .15 and interpolated_frames >= same_tick * .9 and interpolated_player_frames >= same_tick * .9, "between-tick shift=%.4f px, screen range=%s, camera/actor/repeated ticks=%d/%d/%d" % [between_ticks,spread,interpolated_frames,interpolated_player_frames,same_tick])
	Input.action_release("move_back"); Input.action_release("move_right"); Input.action_release("sprint")
	var steady: bool = true
	for speed: float in speeds:
		if absf(speed - Player.RUN) > .02: steady = false
	t.check("MOTION_CLARITY", "diagonal sprint preserves the normal 3.7 m/s speed and real collision movement", steady)
	player.global_position = start; player.velocity = Vector3.ZERO
	rig.yaw = old_yaw; rig.pitch = old_pitch; rig.dist = old_dist
	rig.snap()
	# Reset notifications are flushed before the next visible frame.
	await t.get_tree().process_frame
	await t.get_tree().create_timer(0.0).timeout
	var camera_trail: float = rig.cam.get_global_transform_interpolated().origin.distance_to(rig.cam.global_position)
	var player_trail: float = player.get_global_transform_interpolated().origin.distance_to(player.global_position)
	t.check("MOTION_CLARITY", "a location change resets both logical and rendered positions without a trail", rig.global_position.distance_to(player.global_position + Vector3(0,1.25,0)) < .001 and camera_trail < .001 and player_trail < .001, "camera trail=%.6f m, player trail=%.6f m" % [camera_trail, player_trail])
	rig.collide = old_collide
	Engine.max_fps = old_fps

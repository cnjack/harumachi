extends RefCounted
## Optional still-image diagnostics of a real demo state. No fixture movement or
## animation seeking: all actors, actions, UI clocks and timers are held together.

static func enabled() -> bool:
	return "--qa-multiangle" in OS.get_cmdline_user_args()


static func capture(main: Node, directory: String, label: String, supplied_focus: Vector3 = Vector3.INF, activity: String = "") -> Dictionary:
	var result: Dictionary = {"shots": [], "failures": [], "hold_ms": 0, "cameras": {}}
	var tree: SceneTree = main.get_tree()
	var viewport: Viewport = main.get_viewport()
	var previous: Camera3D = viewport.get_camera_3d()
	if not is_instance_valid(previous):
		result.failures.append("QA capture has no current camera: " + label)
		return result
	var started_ms: int = Time.get_ticks_msec()
	var was_paused: bool = tree.paused
	var time_scale: float = Engine.time_scale
	var original_ui_visible: bool = main.ui.visible
	var state: Dictionary = _snapshot(main)
	# Pausing the tree deactivates physics, and disabling a parent can remove
	# CollisionObject3D children from its space. Resolve all camera queries now,
	# synchronously before any await/pause: this is the exact same actor state
	# that will be held and photographed below.
	var angles: bool = str(main.ui.modal) in ["", "workshop", "pickle_preparation", "fishing"]
	var focus: Vector3 = supplied_focus
	var angle_placements: Dictionary = {}
	var target_proxies: Dictionary = {"rids": [], "paths": []}
	var detail: bool = false
	if angles:
		if not focus.is_finite(): focus = _focus(main, previous)
		target_proxies = _target_proxies(main, focus)
		var offset: Vector3 = previous.global_position - focus
		var actor_volumes: Array[Dictionary] = _visible_actor_volumes(main)
		if offset.length() > 7.5: offset = offset.normalized() * 7.5
		detail = supplied_focus.is_finite() or main.ui.modal in ["workshop", "pickle_preparation"]
		for action_node: Node in main.get_children():
			if action_node is LivingAction: detail = true
		if not detail and offset.length() < 3.2: offset = offset.normalized() * 3.2
		if Vector2(offset.x, offset.z).length() < .25: offset += Vector3(0, 0, .65)
		for requested: float in [-70.0, 70.0, 150.0]:
			angle_placements[int(requested)] = _placement(main, focus, offset, requested, detail, actor_volumes, target_proxies.rids)
	var modes: Array[Dictionary] = []
	# The UI and autoloads have explicit ALWAYS modes. Pause those too; zero
	# scaled time additionally holds unbound SceneTreeTimers (default: always).
	tree.paused = true
	Engine.time_scale = 0.0
	_freeze_modes(tree.root, modes)
	await tree.process_frame
	await RenderingServer.frame_post_draw
	_save(viewport, directory, label, result)
	var diagnostic_paths: Array[String] = []
	var camera: Camera3D = null
	var fades: Array[Dictionary] = []
	if angles:
		camera = Camera3D.new()
		camera.name = "ActivityDiagnosticCamera"
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.process_mode = Node.PROCESS_MODE_DISABLED
		camera.fov = previous.fov
		camera.near = .03
		camera.far = previous.far
		main.add_child(camera)
		# A close follow camera may have faded the avatar. This is presentation
		# only, and the exact original per-mesh value is restored before resuming.
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(main.player.model):
			fades.append({"mesh": mesh, "transparency": mesh.transparency})
			mesh.transparency = 0.0
		main.ui.visible = false
		for degrees: float in [-70.0, 70.0, 150.0]:
			var placement: Dictionary = angle_placements[int(degrees)]
			if not placement.actor_clear: result.failures.append("no actor-clear diagnostic camera for %s angle %d" % [label, int(degrees)])
			if not placement.static_clear: result.failures.append("no static-clear diagnostic camera for %s angle %d: %s" % [label, int(degrees), JSON.stringify(placement.first_static_blocker)])
			if not placement.actor_clear or not placement.static_clear: break
			camera.global_position = placement.position
			camera.look_at(focus)
			camera.make_current()
			await tree.process_frame
			await tree.process_frame
			await RenderingServer.frame_post_draw
			var path: String = _save(viewport, directory, "%s_diagnostic_angle_%d" % [label, int(degrees)], result)
			if not path.is_empty():
				diagnostic_paths.append(path)
				var structural_back: bool = degrees == 150.0 and not main.in_room and detail and (label in ["prop_tea_tray", "prop_bakery_paper"] or label.begins_with("action_eat") and Vector2(focus.x + 21.4, focus.z + 15.4).length() < 2.0)
				result.cameras[path] = {"position": _xyz(camera.global_position), "focus": _xyz(focus), "requested_angle": degrees,
					"adjustment_degrees": placement.adjustment, "height_lift": placement.lift, "same_room": placement.same_room, "clear_center_ray": placement.clear,
					"actor_clear": placement.actor_clear, "minimum_head_distance": placement.minimum_head_distance, "actor_rejections": placement.actor_rejections,
					"static_clear": placement.static_clear, "static_rejections": placement.static_rejections,
					"target_proxy_exclusions": target_proxies.paths, "first_static_blocker": placement.first_static_blocker,
					"query_phase": "pre_hold_physics",
					"camera_role": "diagnostic_structure_back" if structural_back else "diagnostic_activity_angle",
					"label": "背侧结构；实体篷/背板正常遮挡正面承载物" if structural_back else "活动补充机位"}
	previous.make_current()
	main.ui.visible = original_ui_visible
	for fade: Dictionary in fades:
		if is_instance_valid(fade.mesh): fade.mesh.transparency = float(fade.transparency)
	if is_instance_valid(camera): camera.free()
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var guards: Array[String] = _compare(state, _snapshot(main))
	for message: String in guards: result.failures.append("QA hold changed " + label + ": " + message)
	for saved_mode: Dictionary in modes:
		if is_instance_valid(saved_mode.node): saved_mode.node.process_mode = int(saved_mode.mode)
		else: result.failures.append("QA hold lost processing node: " + label)
	Engine.time_scale = time_scale
	tree.paused = was_paused
	if viewport.get_camera_3d() != previous or main.ui.visible != original_ui_visible:
		result.failures.append("QA camera/UI restoration failed: " + label)
	if tree.paused != was_paused or not is_equal_approx(Engine.time_scale, time_scale):
		result.failures.append("QA pause/time restoration failed: " + label)
	result.hold_ms = Time.get_ticks_msec() - started_ms
	# Report only after all state and restoration guards. Synchronous JSON/SHA
	# writing has no await and therefore cannot advance the held action pose.
	_record(directory, label, result, diagnostic_paths, angles, state, activity)
	return result


static func _freeze_modes(node: Node, saved: Array[Dictionary]) -> void:
	if node.process_mode != Node.PROCESS_MODE_INHERIT:
		saved.append({"node": node, "mode": node.process_mode})
		node.process_mode = Node.PROCESS_MODE_DISABLED
	for child: Node in node.get_children(): _freeze_modes(child, saved)


static func _focus(main: Node, _camera: Camera3D) -> Vector3:
	for child: Node in main.get_children():
		if child is LivingAction:
			var action: LivingAction = child as LivingAction
			if action.surface_at.is_finite(): return action.surface_at + Vector3.UP * .07
			if is_instance_valid(action.actor): return action.actor.global_position + Vector3.UP * 1.25
	if main.ui.modal == "workshop":
		var work: WorkroomView = main.world.interiors.workroom.get_node("WorkroomProject")
		if is_instance_valid(work.specimen): return work.specimen.global_position + Vector3.UP * .13
		return InteriorBuilder.SPECS.workroom.origin + Vector3(-1.2, 1.03, -.4)
	if main.ui.modal == "pickle_preparation": return main.story.neighbours.view.surface() + Vector3.UP * .08
	return main.player.global_position + Vector3.UP


static func _visible_actor_volumes(main: Node) -> Array[Dictionary]:
	var actors: Array[Node3D] = [main.player]
	for neighbour: Node3D in main.npcs.values(): actors.append(neighbour)
	var volumes: Array[Dictionary] = []
	for actor: Node3D in actors:
		var model: Node3D = actor.get("model") as Node3D
		if not is_instance_valid(model) or not actor.is_visible_in_tree() or not model.is_visible_in_tree(): continue
		var first: bool = true
		var bounds := AABB()
		for visible_mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
			if not visible_mesh.is_visible_in_tree() or visible_mesh.mesh == null: continue
			var mesh_bounds: AABB = visible_mesh.global_transform * visible_mesh.get_aabb()
			bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
			first = false
		if first: continue
		var head: Vector3 = actor.global_position + Vector3.UP * 1.6
		var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
			var bone: int = LivingPose.bone(skeleton, "head")
			if bone >= 0: head = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
		volumes.append({"bounds": bounds.grow(.20), "head": head})
	return volumes


static func _actor_clearance(main: Node, position: Vector3, volumes: Array[Dictionary], query: PhysicsShapeQueryParameters3D) -> Dictionary:
	query.transform = Transform3D(Basis.IDENTITY, position)
	var clear: bool = main.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
	var nearest: float = INF
	for actor: Dictionary in volumes:
		nearest = minf(nearest, position.distance_to(actor.head))
		if (actor.bounds as AABB).has_point(position) or position.distance_to(actor.head) < .45: clear = false
	return {"clear": clear, "minimum_head_distance": nearest}


static func _target_proxies(main: Node, focus: Vector3) -> Dictionary:
	# A placed table's walking proxy can be taller than its drawn tabletop, and
	# a lantern's centre is inside its own Box. Exclude only those target Boxes
	# from the sight ray, never the camera-origin sphere or tree/camera geometry.
	var query := PhysicsPointQueryParameters3D.new()
	query.position = focus
	query.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED
	var rids: Array[RID] = []
	var paths: Array[String] = []
	for hit: Dictionary in main.get_world_3d().direct_space_state.intersect_point(query, 32):
		var body: CollisionObject3D = hit.collider as CollisionObject3D
		if body == null or body.collision_layer & WorldBuilder.L_CAMERA: continue
		var owner: Object = body.shape_owner_get_owner(body.shape_find_owner(int(hit.shape)))
		if not owner is CollisionShape3D or not (owner as CollisionShape3D).shape is BoxShape3D: continue
		var ancestor: Node = body.get_parent()
		var belongs_to_model: bool = false
		while ancestor != null and ancestor != main:
			if ancestor is RepresentativeLantern or ancestor.has_meta("model_id") or ancestor.has_meta("wind_model_id"):
				belongs_to_model = true
				break
			ancestor = ancestor.get_parent()
		if belongs_to_model and not rids.has(body.get_rid()):
			rids.append(body.get_rid())
			paths.append(str(body.get_path()))
	return {"rids": rids, "paths": paths}


static func _static_blocker(hit: Dictionary, kind: String, candidate: Vector3, focus: Vector3) -> Dictionary:
	if hit.is_empty(): return {}
	var body: CollisionObject3D = hit.collider as CollisionObject3D
	var at: Vector3 = hit.get("position", candidate)
	return {"kind": kind, "collider": str(body.get_path()) if body != null else "unknown", "layer": body.collision_layer if body != null else 0,
		"position": _xyz(at), "focus_distance": at.distance_to(focus), "origin_distance": at.distance_to(candidate)}


static func _placement(main: Node, focus: Vector3, offset: Vector3, degrees: float, detail: bool, actor_volumes: Array[Dictionary], target_proxy_rids: Array[RID]) -> Dictionary:
	var bounds: Dictionary = {}
	if main.in_room and main.room_kind == "house":
		var room: Dictionary = HouseBuilder.room_at(focus - HouseBuilder.ORIGIN)
		if not room.is_empty() and not bool(room.get("outdoor", false)):
			var rect: Array = room.rect
			bounds = {"x0": HouseBuilder.ORIGIN.x + float(rect[0]) + .24, "z0": HouseBuilder.ORIGIN.z + float(rect[1]) + .24,
				"x1": HouseBuilder.ORIGIN.x + float(rect[2]) - .24, "z1": HouseBuilder.ORIGIN.z + float(rect[3]) - .24}
	elif main.in_room and InteriorBuilder.SPECS.has(main.room_kind):
		var spec: Dictionary = InteriorBuilder.SPECS[main.room_kind]
		var origin: Vector3 = spec.origin
		var size: Vector2 = spec.size
		bounds = {"x0": origin.x - size.x * .5 + .3, "z0": origin.z - size.y * .5 + .3,
			"x1": origin.x + size.x * .5 - .3, "z1": origin.z + size.y * .5 - .3}
	var fallback: Vector3 = focus + offset.rotated(Vector3.UP, deg_to_rad(degrees))
	var camera_volume := SphereShape3D.new()
	camera_volume.radius = .25
	var actor_query := PhysicsShapeQueryParameters3D.new()
	actor_query.shape = camera_volume
	actor_query.collision_mask = WorldBuilder.L_ACTORS
	var static_query := PhysicsShapeQueryParameters3D.new()
	static_query.shape = camera_volume
	static_query.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED | WorldBuilder.L_CAMERA | WorldBuilder.L_GROUND
	var actor_rejections: int = 0
	var static_rejections: int = 0
	var first_static_blocker: Dictionary = {}
	var has_safe_fallback: bool = false
	var fallback_adjustment: float = 0.0
	var fallback_lift: float = 0.0
	# Same-room cameras cannot cross a partition; small angle/height adjustments
	# also avoid real furniture or exterior roofs without changing their visibility.
	for adjustment: float in [0.0, -12.0, 12.0, -28.0, 28.0, -50.0, 50.0, -85.0, 85.0]:
		for lift: float in [0.0, .45, .9, 1.5]:
			var candidate: Vector3 = focus + offset.rotated(Vector3.UP, deg_to_rad(degrees + adjustment))
			if not bounds.is_empty():
				candidate.x = clampf(candidate.x, float(bounds.x0), float(bounds.x1))
				candidate.z = clampf(candidate.z, float(bounds.z0), float(bounds.z1))
				# Stay below hanging lamps for actor views; the same-room rectangle
				# already prevents partition occlusion, so a steep overhead orbit is
				# unnecessary and can put a decorative shade across the face.
				candidate.y = focus.y + clampf(offset.y, -.8 if detail else .8, 1.15)
			candidate.y += lift
			var clearance: Dictionary = _actor_clearance(main, candidate, actor_volumes, actor_query)
			if not clearance.clear:
				actor_rejections += 1
				continue
			static_query.transform = Transform3D(Basis.IDENTITY, candidate)
			var origin_hits: Array[Dictionary] = main.get_world_3d().direct_space_state.intersect_shape(static_query, 1)
			if not origin_hits.is_empty():
				if first_static_blocker.is_empty(): first_static_blocker = _static_blocker(origin_hits[0], "origin", candidate, focus)
				static_rejections += 1
				continue
			if not has_safe_fallback:
				fallback = candidate
				has_safe_fallback = true
				fallback_adjustment = adjustment
				fallback_lift = lift
			var ray := PhysicsRayQueryParameters3D.create(candidate, focus, WorldBuilder.L_SOLID | WorldBuilder.L_PLACED | WorldBuilder.L_CAMERA)
			# A candidate can be deep inside a concave bark mesh without its small
			# camera sphere touching a triangle. The exit face must still be hit.
			ray.hit_back_faces = true
			ray.hit_from_inside = true
			ray.exclude = target_proxy_rids
			var ray_hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(ray)
			var clear: bool = ray_hit.is_empty()
			if not clear and first_static_blocker.is_empty(): first_static_blocker = _static_blocker(ray_hit, "sight", candidate, focus)
			if clear: return {"position": candidate, "adjustment": adjustment, "lift": lift, "same_room": not bounds.is_empty(), "clear": true,
				"actor_clear": true, "minimum_head_distance": clearance.minimum_head_distance, "actor_rejections": actor_rejections,
				"static_clear": true, "static_rejections": static_rejections, "first_static_blocker": first_static_blocker}
			static_rejections += 1
	var fallback_clearance: Dictionary = _actor_clearance(main, fallback, actor_volumes, actor_query)
	return {"position": fallback, "adjustment": fallback_adjustment, "lift": fallback_lift, "same_room": not bounds.is_empty(), "clear": false,
		"actor_clear": fallback_clearance.clear, "minimum_head_distance": fallback_clearance.minimum_head_distance, "actor_rejections": actor_rejections,
		"static_clear": false, "static_rejections": static_rejections, "first_static_blocker": first_static_blocker}


static func _xyz(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


static func _snapshot(main: Node) -> Dictionary:
	var actors: Dictionary = {}
	var actor_nodes: Array[Node3D] = [main.player]
	for neighbor: Node3D in main.npcs.values(): actor_nodes.append(neighbor)
	for actor: Node3D in actor_nodes:
		var values: Dictionary = {"transform": actor.global_transform}
		if actor is Player:
			values.merge({"velocity": actor.velocity, "auto_move": actor.auto_move, "auto_run": actor.auto_run, "frozen": actor.frozen})
		actors[str(actor.get_instance_id())] = values
	var animations: Dictionary = {}
	for animator: AnimationPlayer in main.find_children("*", "AnimationPlayer", true, false):
		animations[str(animator.get_instance_id())] = {"clip": animator.current_animation, "position": animator.current_animation_position if not animator.current_animation.is_empty() else 0.0, "speed": animator.speed_scale, "playing": animator.is_playing()}
	var actions: Dictionary = {}
	for child: Node in main.get_children():
		if child is LivingAction: actions[str(child.get_instance_id())] = {"clock": child.clock, "finished": child.finished, "processing": child.is_processing()}
	var fishing: Dictionary = {}
	if is_instance_valid(main.ui.fishing_panel) and main.ui.fishing_panel.session != null:
		var panel: FishingPanel = main.ui.fishing_panel
		fishing = {"state": panel.session.state, "timer": panel.session.timer, "progress": panel.session.reel_progress, "tension": panel.session.tension, "held": panel._held}
	return {"actors": actors, "animations": animations, "actions": actions, "fishing": fishing, "modal": main.ui.modal,
		"rig": {"transform": main.rig.global_transform, "yaw": main.rig.yaw, "pitch": main.rig.pitch, "dist": main.rig.dist, "fixed": main.rig.fixed},
		"clock": {"day": GameState.day, "minute": GameState.minute, "paused": GameState.clock_paused}}


static func _compare(before: Dictionary, after: Dictionary) -> Array[String]:
	var differences: Array[String] = []
	for key: String in before:
		if before[key] != after.get(key): differences.append(key)
	return differences


static func _save(viewport: Viewport, directory: String, label: String, result: Dictionary) -> String:
	var path: String = directory.path_join(label + ".png")
	var bitmap: Image = viewport.get_texture().get_image()
	if bitmap == null or bitmap.save_png(path) != OK:
		result.failures.append("screenshot failed " + path)
		return ""
	result.shots.append(path)
	return path


static func _record(directory: String, label: String, result: Dictionary, diagnostic: Array[String], angles: bool, snapshot: Dictionary, activity: String) -> void:
	var path: String = directory.path_join("diagnostic-manifest.json")
	var report: Dictionary = {"passed": true, "scope": "Held still images of real native activity state. Supplemental cameras are diagnostic and do not prove movement or natural duration.", "captures": [], "shots": []}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary: report = parsed
	# Native helpers may reuse a dialogue label. Match their replacement PNG
	# semantics so every listed digest describes the file that actually remains.
	var previous_captures: Array = report.get("captures", [])
	var previous_shots: Array = report.get("shots", [])
	report.captures = []
	report.shots = []
	for prior_capture: Dictionary in previous_captures:
		if str(prior_capture.get("label", "")) != label: report.captures.append(prior_capture)
	for prior_shot: Dictionary in previous_shots:
		if str(prior_shot.get("action", "")) != label: report.shots.append(prior_shot)
	var files: Array[Dictionary] = []
	for saved_path: String in result.shots:
		files.append({"file": saved_path, "sha256": FileAccess.get_sha256(saved_path), "camera_role": "diagnostic" if diagnostic.has(saved_path) else "original_native_camera"})
		if diagnostic.has(saved_path):
			var angle: int = int(saved_path.get_file().trim_suffix(".png").get_slice("_diagnostic_angle_", 1))
			var camera: Dictionary = result.cameras.get(saved_path, {})
			report.shots.append({"file": saved_path, "sha256": FileAccess.get_sha256(saved_path), "activity": activity, "action": label,
				"kind": "diagnostic_paused_activity", "angle": angle, "camera_role": camera.get("camera_role", "diagnostic_activity_angle"),
				"configuration": {"label": activity + " / " + label + " / " + str(camera.get("label", "活动补充机位")), "camera_role": camera.get("camera_role", "diagnostic_activity_angle"), "camera": camera}})
	report.captures.append({"label": label, "supplemental_angles": angles, "hold_ms": result.hold_ms,
		"query_phase": "pre_hold_physics" if angles else "no_3d_diagnostic",
		"restoration_passed": result.failures.is_empty(), "failures": result.failures, "files": files,
		"held": {"actors": snapshot.actors.size(), "animation_players": snapshot.animations.size(), "living_actions": snapshot.actions.size(), "fishing": snapshot.fishing}})
	report.passed = bool(report.passed) and result.failures.is_empty()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "  ")); file.close()
	else: result.failures.append("cannot write diagnostic manifest " + path)

class_name Player
extends CharacterBody3D
## Player: camera-relative movement, procedural walk animation, single nearest interaction.

signal interact_requested(target: Interactable)
signal target_changed(target: Interactable)

const WALK := 1.8
const RUN := 3.7
const ACCEL := 14.0
const GRAVITY := 22.0

var rig: CameraRig
var model: Node3D
var model_root := Node3D.new()
var story: Node          # provides prompt_for(id) -> String
var target: Interactable
var seated := false
var seat_target: Interactable
var frozen := false
var auto_move := Vector3.ZERO   # autoplay: world-space direction, overrides keyboard input
var auto_run := false
var _walk_t := 0.0
var _speed_now := 0.0
var _face_yaw := 0.0
var anim: CharAnim
var _in_own_move := false
var _skip_snap_next := false
var _physics_position := Vector3.INF
var ears: AudioListener3D


func _notification(what: int) -> void:
	# A teleport (any external write to our transform, e.g. warping the player into a
	# shop/house/farm) can leave floor-snap's probe brushing a nearby prop's edge and
	# shove the player a meter or more on the very next physics frame. Skip snapping for
	# just that one frame; move_and_slide() itself sets _in_own_move so it isn't caught here.
	if what == NOTIFICATION_TRANSFORM_CHANGED and not _in_own_move:
		# Transform notifications can arrive after move_and_slide has returned.
		# A completed physics move is not a teleport and must keep its snapshots.
		if global_position.is_equal_approx(_physics_position): return
		_skip_snap_next = true
		if is_inside_tree(): reset_physics_interpolation()


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	collision_layer = WorldBuilder.L_ACTORS
	collision_mask = WorldBuilder.L_GROUND | WorldBuilder.L_SOLID | WorldBuilder.L_ACTORS | WorldBuilder.L_PLACED | WorldBuilder.L_BLOCK
	floor_snap_length = 0.3
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	add_child(cs)
	add_child(model_root)
	ears=AudioListener3D.new();ears.name="PlayerEar";ears.position.y=1.5;add_child(ears);ears.make_current()
	set_meta("audit_model", "CH_sora")
	var ps := WorldBuilder.model_scene("CH_sora")
	if ps:
		model = ps.instantiate()
	else:
		model = _capsule_model(Color(0.55, 0.78, 0.66))
	model_root.add_child(model)
	anim = CharAnim.new(model)
	anim.stepped.connect(func():
		if Audio.game_on:
			Audio.footstep(Layout.surface_at(global_position, GameState.player_in_room)))
	for mi in WorldBuilder.find_meshes(model):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_physics_position = global_position


static func _capsule_model(c: Color) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.28
	cm.height = 1.6
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	mi.material_override = m
	mi.position.y = 0.8
	n.add_child(mi)
	return n


func set_facing(yaw_rad: float) -> void:
	_face_yaw = yaw_rad
	model_root.rotation.y = yaw_rad


func face_towards(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		set_facing(atan2(d.x, d.z))


func _physics_process(delta: float) -> void:
	if rig!=null and is_instance_valid(rig.cam):ears.rotation.y=rig.cam.global_rotation.y
	if seated:
		velocity=Vector3.ZERO;_speed_now=0.0;_physics_position=global_position
		_animate(delta);_update_target();return
	if not global_position.is_equal_approx(_physics_position):
		_skip_snap_next = true
		reset_physics_interpolation()
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var input := Vector2.ZERO
	var can_move := not frozen and not GameState.input_locked()
	if can_move:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3(input.x, 0, input.y).rotated(Vector3.UP, rig.forward_yaw() if rig else 0.0)
	var spd := RUN if (can_move and Input.is_action_pressed("sprint")) else WALK
	if auto_move != Vector3.ZERO and not frozen:
		dir = auto_move
		spd = RUN if auto_run else WALK
	var want := dir * spd
	velocity.x = move_toward(velocity.x, want.x, ACCEL * delta * spd)
	velocity.z = move_toward(velocity.z, want.z, ACCEL * delta * spd)
	_in_own_move = true
	if _skip_snap_next:
		floor_snap_length = 0.0
	move_and_slide()
	if _skip_snap_next:
		floor_snap_length = 0.3
		_skip_snap_next = false
	_physics_position = global_position
	_in_own_move = false
	var hv := Vector2(velocity.x, velocity.z)
	_speed_now = hv.length()
	if dir.length() > 0.1:
		var t := atan2(dir.x, dir.z)
		_face_yaw = lerp_angle(_face_yaw, t, 1.0 - exp(-14.0 * delta))
		model_root.rotation.y = _face_yaw
	_animate(delta)
	_update_target()


func _animate(delta: float) -> void:
	if model == null:
		return
	if anim and anim.valid():
		anim.update(_speed_now)
		# the clip carries the gait; add only a slight forward lean when running
		var lean := 0.03 * clampf((_speed_now - WALK) / (RUN - WALK), 0.0, 1.0)
		model.rotation.x = lerpf(model.rotation.x, lean, 1.0 - exp(-8.0 * delta))
		return
	if _speed_now > 0.2:
		_walk_t += delta * (6.0 + _speed_now * 1.4)
		model.position.y = absf(sin(_walk_t)) * 0.045 * clampf(_speed_now / WALK, 0.6, 1.5)
		model.rotation.z = sin(_walk_t) * 0.035
		model.rotation.x = 0.06 * clampf(_speed_now / RUN, 0.0, 1.0)
	else:
		_walk_t += delta * 2.0
		model.position.y = lerpf(model.position.y, 0.0, 1.0 - exp(-12.0 * delta))
		model.rotation.z = lerpf(model.rotation.z, 0.0, 1.0 - exp(-12.0 * delta))
		model.rotation.x = lerpf(model.rotation.x, 0.0, 1.0 - exp(-12.0 * delta))
		model.scale = Vector3(1, 1.0 + sin(_walk_t) * 0.006, 1)


func _update_target() -> void:
	if seated:
		if target!=seat_target:target=seat_target;target_changed.emit(target)
		return
	var best: Interactable = null
	var best_score := INF
	if not frozen and not GameState.input_locked():
		var fwd := Vector3(sin(_face_yaw), 0, cos(_face_yaw))
		var space := get_world_3d().direct_space_state
		for n in get_tree().get_nodes_in_group("interactables"):
			var it := n as Interactable
			if not it.is_visible_in_tree():
				continue
			var d := it.global_position - global_position
			var flat := Vector2(d.x, d.z).length()
			if flat > it.radius or absf(d.y) > 3.0:
				continue
			if story and story.prompt_for(it.id) == "":
				continue
			var ang := 0.0
			if flat > 0.2:
				ang = acos(clampf(fwd.dot(Vector3(d.x, 0, d.z).normalized()), -1.0, 1.0))
			var score := flat + ang * 0.9
			if score >= best_score:
				continue
			# line of sight from chest to the target point (ignore own and target bodies)
			var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.1, 0), it.global_position, WorldBuilder.L_SOLID | WorldBuilder.L_PLACED)
			var ex: Array[RID] = [get_rid()]
			if it.body:
				ex.append(it.body.get_rid())
			q.exclude = ex
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and (hit.position as Vector3).distance_to(it.global_position) > 0.6:
				continue
			best = it
			best_score = score
	if best != target:
		target = best
		target_changed.emit(target)


func _unhandled_input(event: InputEvent) -> void:
	if frozen or GameState.input_locked():
		return
	if event.is_action_pressed("interact") and not event.is_echo() and target:
		get_viewport().set_input_as_handled()
		interact_requested.emit(target)

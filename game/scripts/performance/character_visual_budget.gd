extends RefCounted
## Lower only the residual cloth solve cadence. Source animations and feet keep updating.
var skipped := 0
var solved := 0
var tier := "full"
var _last_usec := -1
var _last_clip := ""
var _last_phase := -1.0
var _last_position := Vector3.ZERO
var _last_generation := -1
var _last_actor_basis := Basis.IDENTITY
var _last_visible := false
var _last_camera := Transform3D.IDENTITY

static func classify(profile: String, distance: float, visible: bool, protected: bool, background: bool) -> float:
	if protected or profile == "quality": return 0.0
	if background or not visible: return 1.0
	if distance < (18.0 if profile == "balanced" else 14.0): return 0.0
	return 1.0 / (30.0 if profile == "balanced" and distance < 32.0 else 15.0)

static func on_screen(camera: Camera3D, center: Vector3) -> bool:
	# Conservative sphere includes hair, raised arms and a little camera-turn margin.
	for plane: Plane in camera.get_frustum():
		if plane.distance_to(center) > 2.0: return false
	return true

func allow(support: Node, mesh: MeshInstance3D, character: String, animation: AnimationPlayer, actor: Node3D) -> bool:
	if DisplayServer.get_name() == "headless" or not is_instance_valid(actor) or not is_instance_valid(animation): return true
	var mode: Node = support.get_node_or_null("/root/PerformanceMode")
	var camera: Camera3D = support.get_viewport().get_camera_3d()
	if mode == null or camera == null: return true
	if mode.get("profile") == "quality":
		solved += 1
		tier = "full"
		return true
	var center: Vector3 = actor.global_position + Vector3.UP
	var visible: bool = on_screen(camera, center)
	var protected: bool = character == "sora" or camera.fov < 40.0 or camera.name == &"PhotoCamera"
	if actor is NPC:
		protected = protected or (actor as NPC).talking or (actor as NPC).hold
		var player: Node3D = (actor as NPC).player
		protected = protected or (is_instance_valid(player) and actor.global_position.distance_to(player.global_position) < 5.0)
	var natural: Node = support.get("steady_natural") as Node
	if is_instance_valid(natural):
		protected = protected or float(natural.get("_transition_elapsed")) < float(natural.get("_transition_duration"))
	var clip: String = animation.current_animation
	# Gestures, interaction and transitions keep full precision even at a distance.
	protected = protected or clip not in ["idle", "walk", "run", "dance"]
	var interval: float = classify(str(mode.get("profile")), camera.global_position.distance_to(center), visible, protected, bool(mode.get("background")) and not bool(mode.get("benchmark")))
	var generation: int = int(mode.get("generation"))
	var now: int = Time.get_ticks_usec()
	var phase: float = animation.current_animation_position
	var force: bool = _last_usec < 0 or generation != _last_generation or clip != _last_clip or phase < _last_phase or actor.global_position.distance_to(_last_position) > .5 or (visible and not _last_visible)
	# A camera cut or rapid turn must use the current pose on its first frame.
	force = force or actor.global_basis.z.dot(_last_actor_basis.z) < .99 or absf(actor.global_position.y - _last_position.y) > .015
	force = force or camera.global_position.distance_to(_last_camera.origin) > .4 or camera.global_basis.z.dot(_last_camera.basis.z) < .995
	_last_visible = visible
	_last_camera = camera.global_transform
	_last_phase = phase
	tier = "full" if interval == 0.0 else ("offscreen" if interval >= 1.0 else "far")
	if not force and interval > 0.0 and now - _last_usec < int(interval * 1000000.0):
		skipped += 1
		return false
	_last_usec = now
	_last_clip = clip
	_last_position = actor.global_position
	_last_actor_basis = actor.global_basis
	_last_generation = generation
	solved += 1
	return true

func reset() -> void:
	_last_usec = -1
	skipped = 0
	solved = 0

class_name NPC
extends Node3D
## Neighbour: follows a daily schedule (Layout.SCHEDULE), turns to talk, walks scripted routes,
## and fills the time in between with small gestures (looking around, stretching, waving hello).

var npc_id := ""
var display_name := ""
var model: Node3D
var body: AnimatableBody3D
var talk: Interactable
var tag: Label3D
var speed := 1.5
var _path: Array[Vector3] = []
var _walk_t := 0.0
var _moving := false
var _safe_walk := false
var _safe_blocked := false
var _walk_probe: CapsuleShape3D
var _route_retry := 0.0
var _blocked_seconds := 0.0
var _frame_delta := 0.0
var walk_succeeded := true
const MOTION_ROUTE = preload("res://scripts/npc/motion_route.gd")
var _yaw := 0.0
var anim: CharAnim
var _steps: AudioStreamPlayer3D
var sched_i := -1            # index of the schedule entry currently applied
var _schedule_context := ""
var _scheduled_walk := false
var _placement_generation := 0
var _departure_tween: Tween
var home := false            # gone home for the night (hidden, cannot be talked to)
var talking := false
var player: Node3D
var _idle_t := 0.0
var _greeted_day := 0
var _end_yaw := INF
var _end_idle := "idle"
var fest_key := ""           # the festival spot currently applied ("" = following the schedule)
signal arrived
signal walk_finished(success: bool)

# v0.6: activity loops at the market and festivals. Each stop is [Vector3 world pos, yaw_deg, clip, dwell_s];
# a clip is either a standing loop (idle, talk, tend, dance) or a one-shot gesture (look, cheer, wave, bow, stretch).
const GESTURES := ["look", "cheer", "wave", "bow", "stretch"]
var roam_key := ""
var _roam: Array = []
var _roam_i := 0
var _roam_wait := 0.0
var _roam_leg := false       # the current walk is a roam leg: it pauses for freeze / hold / talking
var _yield_t := 0.0
var hold := false            # autoplay and scripted beats: finish the current step, then stay put
static var freeze := false   # set by Main every frame: cut-scenes, dialogue, transitions, the bon-odori
static var everyone: Array[NPC] = []
static var roam_enabled := true   # the headless tests switch the loops off so positions stay predictable


func setup(id: String, info: Dictionary) -> void:
	npc_id = id
	display_name = info.name
	set_meta("audit_model", info.model)
	name = "NPC_" + id
	var ps := WorldBuilder.model_scene(info.model)
	model = ps.instantiate() if ps else Player._capsule_model(Color(0.9, 0.7, 0.6))
	add_child(model)
	anim = CharAnim.new(model)
	_steps = AudioStreamPlayer3D.new()
	_steps.bus = "SFX"
	_steps.unit_size = 4.0
	_steps.max_distance = 24.0
	_steps.volume_db = -15.0
	add_child(_steps)
	anim.stepped.connect(func():
		if Audio.game_on:
			_steps.stream = Audio.step_stream(Layout.surface_at(global_position, false))
			_steps.pitch_scale = randf_range(0.94, 1.06)
			_steps.play())
	for mi in WorldBuilder.find_meshes(model):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body = AnimatableBody3D.new()
	body.collision_layer = WorldBuilder.L_ACTORS
	body.collision_mask = 0
	body.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	body.add_child(cs)
	add_child(body)
	talk = Interactable.new()
	talk.id = id
	talk.radius = 2.3
	talk.position.y = 1.1
	talk.body = body
	add_child(talk)
	tag = Label3D.new()
	tag.text = display_name
	tag.font_size = 64
	tag.pixel_size = 0.004
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 14
	tag.modulate = Color(1, 0.98, 0.92)
	tag.outline_modulate = Color(0.3, 0.2, 0.12, 0.85)
	tag.no_depth_test = false
	tag.position.y = 2.05
	add_child(tag)


## Start (or stop, with an empty list) an activity loop. The NPC is assumed to be at stop 0 already.
func set_roam(key: String, stops: Array) -> void:
	if key == roam_key:
		return
	roam_key = key
	_roam = stops
	_roam_i = 0
	_roam_wait = randf_range(2.0, 7.0)      # stagger so the neighbours do not all set off together
	if _roam_leg:
		_roam_leg = false
		_moving = false
		_path.clear()


func roaming() -> bool:
	return not _roam.is_empty()


func _roam_tick(delta: float) -> void:
	if _roam.is_empty() or _moving or talking or home or hold or freeze or not roam_enabled:
		return
	if anim.valid() and anim.busy():
		return
	_roam_wait -= delta
	if _roam_wait > 0.0:
		return
	if player and global_position.distance_to(player.global_position) < 2.4:
		_roam_wait = 1.2          # someone is standing right here (maybe to talk): wait for them
		return
	_roam_i = (_roam_i + 1) % _roam.size()
	var s: Array = _roam[_roam_i]
	var clip := str(s[2])
	_end_yaw = deg_to_rad(float(s[1]))
	_end_idle = "idle" if clip in GESTURES else clip
	if anim.valid():
		anim.set_idle("idle")
	_path.clear()
	_path.append(s[0])
	_moving = true
	_roam_leg = true
	_yield_t = 0.0


func _roam_arrived() -> void:
	_roam_leg = false
	var s: Array = _roam[_roam_i]
	var clip := str(s[2])
	_roam_wait = float(s[3]) * randf_range(0.8, 1.3)
	if clip in GESTURES and anim.valid():
		get_tree().create_timer(0.4).timeout.connect(func(): if not _moving: anim.play_once(clip))


## Steer around the player and the other neighbours while walking. Returns the direction to take,
## or Vector3.ZERO to wait a moment (only on roam legs: scripted walks must always arrive).
func _avoid(dir: Vector3, delta: float, to_goal: float) -> Vector3:
	var push := Vector3.ZERO
	var block := false
	var others: Array[Node3D] = []
	if player:
		others.append(player)
	for n in everyone:
		if n != self and is_instance_valid(n) and n.visible and not n.home:
			others.append(n)
	for o in others:
		var to := o.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 1.7 or dist < 0.001 or dist > to_goal + 0.4:
			continue      # far away, or standing beyond where we are going
		var ahead := dir.dot(to / dist)
		if ahead < 0.1:
			continue
		var side := Vector3(-dir.z, 0, dir.x)
		if side.dot(to) > 0.0:
			side = -side
		push += side * (1.7 - dist) * 1.6 * ahead
		if dist < 0.8 and ahead > 0.6 and o == player:
			block = true
	if block and _roam_leg:
		_yield_t += delta
		if _yield_t < 1.5:
			return Vector3.ZERO
	else:
		_yield_t = maxf(0.0, _yield_t - delta)
	# ease off near the goal so a neighbour waiting next to the stop cannot make us circle it
	return (dir + push * clampf(to_goal / 1.2, 0.0, 1.0)).normalized()


func place(p: Vector3, yaw_deg: float) -> void:
	_placement_generation += 1
	if _departure_tween != null and _departure_tween.is_valid(): _departure_tween.kill()
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(model): mesh.transparency = 0.0
	if _moving: walk_finished.emit(false)
	if _roam_leg:
		_roam_leg = false
		_moving = false
		_path.clear()
	_path.clear()
	_moving = false
	global_position = p
	set_meta("motion_reason", "authored_placement")
	set_yaw(deg_to_rad(yaw_deg))


func set_yaw(y: float) -> void:
	_yaw = y
	model.rotation.y = y


func face(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	var t := atan2(d.x, d.z)
	var tw := create_tween()
	tw.tween_method(func(v): set_yaw(v), _yaw, _yaw + wrapf(t - _yaw, -PI, PI), 0.25)


## Stand still in a loop pose ("idle", "tend", "talk") once any walk has finished.
func set_pose(clip: String) -> void:
	_end_idle = clip
	if not _moving and anim.valid():
		anim.set_idle(clip)


func set_home(on: bool) -> void:
	home = on
	visible = not on
	talk.radius = 0.0 if on else 2.3
	body.collision_layer = 0 if on else WorldBuilder.L_ACTORS
	if on:
		if _moving: walk_finished.emit(false)
		_path.clear()
		_moving = false


func set_talking(on: bool) -> void:
	talking = on
	if anim.valid():
		anim.set_idle("talk" if on else _end_idle)


func gesture(clip: String) -> void:
	if anim.valid() and not _moving:
		anim.play_once(clip)


## Stand at a festival spot: [region, [x, y, z], yaw, pose] (farm spots relative to the farm).
func apply_fest(e: Array, key: String) -> void:
	if fest_key == key:
		return
	fest_key = key
	sched_i = -99
	var off := FarmBuilder.ORIGIN if str(e[0]) == "farm" else Vector3.ZERO
	var p: Array = e[1]
	set_home(false)
	place(Vector3(float(p[0]), float(p[1]), float(p[2])) + off, float(e[2]))
	set_pose(str(e[3]))


## Apply the schedule entry for the current hour. Nearby and on the same side of town the NPC
## walks there along the entry's path; otherwise (far away, other region, coming back from home)
## it simply appears at the spot.
func apply_schedule(h: float, player_pos: Vector3, force: bool = false) -> void:
	var context_key: String = "%d:%d:%s" % [GameState.day,GameState.weekday(),GameState.weather]
	var sch: Array = Layout.daily_schedule(npc_id, GameState.weekday(), GameState.weather)
	if sch.is_empty():
		return
	var i := -1
	for k in sch.size():
		if h >= float(sch[k][0]):
			i = k
	if i == sched_i and _schedule_context == context_key and not force:
		return
	_schedule_context = context_key
	sched_i = i
	if i < 0 or sch[i][1] == "home":
		set_home(true)
		return
	var e: Array = sch[i]
	var off := FarmBuilder.ORIGIN if e[1] == "farm" else Vector3.ZERO
	var goal: Vector3 = e[2] + off
	var yaw: float = e[3]
	var clip: String = e[4] if e.size() > 4 else "idle"
	var path: Array = []
	if e.size() > 5:
		for q in e[5]:
			path.append((q as Vector3) + off)
	path.append(goal)
	var was_home := home
	set_home(false)
	var near: bool = global_position.distance_to(player_pos) < 45.0
	var same_region: bool = (global_position.x > FarmBuilder.ORIGIN.x-200) == (goal.x > FarmBuilder.ORIGIN.x-200)
	if force or was_home or not near:
		place(goal, yaw)
		set_pose(clip)
		return
	if not same_region:
		var departure: Vector3 = FarmBuilder.ORIGIN + Vector3(-26.8,0,.3) if global_position.x > FarmBuilder.ORIGIN.x-200 else Vector3(41.4,0,-10.6)
		var exit_path: Array[Vector3] = MOTION_ROUTE.query(self, global_position, departure)
		if exit_path.is_empty():
			set_meta("motion_reason","region_exit_blocked");sched_i=-1;return
		var generation: int = _placement_generation
		var reached: bool = await walk(exit_path,true)
		if not reached or generation != _placement_generation or sched_i != i or _schedule_context != context_key: return
		set_meta("motion_reason","region_exit")
		_departure_tween = create_tween().set_parallel(true)
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(model): _departure_tween.tween_property(mesh,"transparency",1.0,.35)
		await _departure_tween.finished
		if generation != _placement_generation or sched_i != i or _schedule_context != context_key: return
		place(goal, yaw); set_pose(clip)
		set_meta("motion_reason","region_entry_cut")
		return
	_end_yaw = deg_to_rad(yaw)
	_end_idle = clip
	if anim.valid():
		anim.set_idle("idle")
	walk(path,true)


func walk(points: Array, scheduled: bool=false) -> bool:
	if _moving: walk_finished.emit(false)
	_roam_leg = false
	_scheduled_walk=scheduled
	walk_succeeded = false
	_blocked_seconds = 0.0
	set_meta("motion_reason", "ordinary_walk")
	_path.clear()
	for p in points:
		_path.append(p)
	_moving = not _path.is_empty()
	if _moving:
		return bool(await walk_finished)
	return false

## Project trials use planned paths and still check every actual movement, including avoidance.
func walk_safe(points: Array) -> bool:
	if points.is_empty(): return false
	_safe_blocked = false
	_safe_walk = true
	var reached: bool = await walk(points)
	_safe_walk = false
	return reached and not _safe_blocked

func cancel_safe_walk() -> void:
	if not _safe_walk: return
	_safe_blocked = true
	_moving = false
	_path.clear()
	walk_finished.emit(false)

func _safe_position(at: Vector3) -> bool:
	if _walk_probe == null:
		_walk_probe = MOTION_ROUTE.capsule()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _walk_probe
	query.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED | WorldBuilder.L_ACTORS
	query.exclude = [body.get_rid()]
	var space := get_world_3d().direct_space_state
	if not _safe_walk:
		# A moving neighbour may leave a slight existing actor overlap. Every point
		# must move away; solid/placed props and newly encountered actors still block.
		query.collision_mask=WorldBuilder.L_ACTORS
		query.transform=Transform3D(Basis.IDENTITY,global_position+Vector3(0,.8,0))
		var exclusions: Array[RID]=[body.get_rid()]
		var step_direction:=Vector2(at.x-global_position.x,at.z-global_position.z)
		for hit: Dictionary in space.intersect_shape(query,16):
			var obstacle:=hit.collider as CollisionObject3D
			if obstacle==null:continue
			var away:=Vector2(global_position.x-obstacle.global_position.x,global_position.z-obstacle.global_position.z)
			if step_direction.dot(away)>.000001:exclusions.append(obstacle.get_rid())
		query.exclude=exclusions
		query.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS
	var pieces: int = maxi(1, ceili(global_position.distance_to(at) / .18))
	for index in range(1, pieces + 1):
		var sample: Vector3 = global_position.lerp(at, float(index) / float(pieces))
		sample.y = global_position.y + .8
		query.transform = Transform3D(Basis.IDENTITY, sample)
		if not space.intersect_shape(query, 1).is_empty():
			_blocked_seconds += _frame_delta
			if _safe_walk:
				_path.clear(); _moving = false; _safe_blocked = true; walk_finished.emit(false)
			elif _blocked_seconds > 8.0:
				_path.clear(); _moving = false; _roam_leg = false; _roam_wait = 2.0
				if _scheduled_walk:sched_i=-1
				set_meta("motion_reason", "route_unavailable")
				walk_finished.emit(false)
			elif _route_retry <= 0.0 and not _path.is_empty():
				_route_retry = .8
				var detour: Array[Vector3] = MOTION_ROUTE.query(self, global_position, _path[0])
				if not detour.is_empty():
					_path.pop_front()
					for index_detour: int in range(detour.size()-1, -1, -1): _path.push_front(detour[index_detour])
			set_meta("motion_reason", "waiting_or_detouring")
			if anim.valid(): anim.update(0.0)
			return false
	_blocked_seconds = 0.0
	return true


func is_moving() -> bool:
	return _moving


func face_yaw(t: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v): set_yaw(v), _yaw, _yaw + wrapf(t - _yaw, -PI, PI), 0.35)


## Between errands: glance around or stretch now and then, and wave the first time the player
## comes close each day (the elders bow instead).
func _idle_life(delta: float) -> void:
	if _moving or talking or home or anim.busy():
		return
	if player and _greeted_day != GameState.day and global_position.distance_to(player.global_position) < 4.5:
		_greeted_day = GameState.day
		face(player.global_position)
		anim.play_once("bow" if npc_id in ["haru", "tanaka", "kazuko"] else ("cheer" if npc_id == "aoi" else "wave"))
		_idle_t = randf_range(6.0, 10.0)
		return
	if anim.idle_clip != "idle" or fest_key.ends_with(":dance"):
		return
	_idle_t -= delta
	if _idle_t <= 0.0:
		_idle_t = randf_range(7.0, 16.0)
		var r := randf()
		anim.play_once("look" if r < 0.55 else ("stretch" if r < 0.8 else "bow" if npc_id in ["haru", "kazuko"] else "look"))


func _enter_tree() -> void:
	if not everyone.has(self):
		everyone.append(self)


func _exit_tree() -> void:
	everyone.erase(self)


func _process(delta: float) -> void:
	_frame_delta = delta
	_route_retry = maxf(0.0, _route_retry - delta)
	var stepping := false
	var paused := (_roam_leg or _scheduled_walk) and (freeze or hold or talking)
	if _moving and not _path.is_empty() and not paused:
		var goal: Vector3 = _path[0]
		var d := goal - global_position
		d.y = 0
		var step := speed * delta
		if d.length() <= maxf(step, 0.12 if _roam_leg else 0.0):
			if not _safe_position(Vector3(goal.x, global_position.y, goal.z)): return
			global_position = Vector3(goal.x, global_position.y, goal.z)
			_path.pop_front()
			if _path.is_empty():
				_moving = false
				walk_succeeded = true
				if _end_yaw != INF:
					face_yaw(_end_yaw)
					_end_yaw = INF
				if anim.valid():
					anim.set_idle(_end_idle)
				if _roam_leg:
					_roam_arrived()
				arrived.emit()
				walk_finished.emit(true)
		else:
			var dir := _avoid(d.normalized(), delta, d.length())
			if dir != Vector3.ZERO:
				if not _safe_position(global_position + dir * step): return
				global_position += dir * step
				set_yaw(lerp_angle(_yaw, atan2(dir.x, dir.z), 1.0 - exp(-10.0 * delta)))
				stepping = true
	else:
		stepping = _moving and not paused
	_roam_tick(delta)
	if anim.valid():
		anim.update(speed if stepping else 0.0)
		_idle_life(delta)
		return
	if _moving:
		_walk_t += delta * 8.5
		model.position.y = absf(sin(_walk_t)) * 0.04
		model.rotation.z = sin(_walk_t) * 0.03
	else:
		_walk_t += delta * 1.8
		model.position.y = lerpf(model.position.y, 0.0, 1.0 - exp(-10.0 * delta))
		model.rotation.z = lerpf(model.rotation.z, 0.0, 1.0 - exp(-10.0 * delta))
		model.scale = Vector3(1, 1.0 + sin(_walk_t) * 0.006, 1)

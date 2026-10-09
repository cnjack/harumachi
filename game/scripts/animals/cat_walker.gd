extends CharacterBody3D
## Four-legged locomotion for the game world and standalone roaming preview.

var model: Node3D
var player: AnimationPlayer
var route: PackedVector3Array = PackedVector3Array()
var destination: int = 0
var speed: float = .12
var native_walk_speed: float = .12
var travelled: float = 0.0
var arrivals: int = 0
var headings: Array[float] = []
var rest_left: float = 0.0
var last_position: Vector3
var rng := RandomNumberGenerator.new()
var habitat := Rect2()
var blocked_seconds := 0.0
var behaviour_seed := 0
var waiting_for_spawn := false
const CAT_LOOK = preload("res://scripts/animals/cat_look.gd")
var attention: SkeletonModifier3D
const FOOT_PLANT = preload("res://scripts/animals/cat_foot_plant.gd")
var foot_plant: SkeletonModifier3D
var locomotion: String = "Walk"
var rest_pose: String = "Idle"
var pose_left: float = 0.0
var native_run_speed: float = .42
var native_sneak_speed: float = .07
var animation_history: Array[String] = []
var move_speed: float = 0.0

func setup(visual: Node3D, points: PackedVector3Array, walking_speed: float=.12) -> void:
	model=visual
	route=points
	speed=walking_speed
	player=model.find_child("AnimationPlayer",true,false) as AnimationPlayer
	assert(player != null and player.has_animation("Walk") and player.has_animation("Idle"))
	var skeletons: Array[Node] = model.find_children("*","Skeleton3D",true,false)
	assert(not skeletons.is_empty())
	foot_plant = FOOT_PLANT.new() as SkeletonModifier3D
	foot_plant.name = "CatPawContacts"
	foot_plant.set("animation", player)
	foot_plant.set("actor", self)
	(skeletons[0] as Skeleton3D).add_child(foot_plant)
	attention = CAT_LOOK.new() as SkeletonModifier3D
	(skeletons[0] as Skeleton3D).modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	attention.name = "CatAttention"
	attention.set("target_origin", self)
	(skeletons[0] as Skeleton3D).add_child(attention)
	var metadata_root: Node = skeletons[0]
	while metadata_root != null:
		var extras: Dictionary = metadata_root.get_meta("extras", {})
		if extras.has("walk_speed"):
			native_walk_speed = float(extras["walk_speed"])
			native_run_speed = float(extras.get("run_speed", .42))
			native_sneak_speed = float(extras.get("sneak_speed", .07))
			break
		if metadata_root.has_meta("walk_speed"):
			native_walk_speed = float(metadata_root.get_meta("walk_speed"))
			break
		if metadata_root == model: break
		metadata_root = metadata_root.get_parent()
	for animation_name: String in ["Walk","Idle","Run","Sneak","Sit"]:
		if player.has_animation(animation_name): player.get_animation(animation_name).loop_mode=Animation.LOOP_LINEAR
	if route.size()>1:
		global_position=route[0]
		destination=1
		var initial_direction: Vector3 = route[1]-route[0]
		rotation.y=atan2(initial_direction.x,initial_direction.z)
	last_position=global_position
	var minimum := Vector2(route[0].x, route[0].z)
	var maximum := minimum
	for point: Vector3 in route:
		minimum = minimum.min(Vector2(point.x, point.z)); maximum = maximum.max(Vector2(point.x, point.z))
	habitat = Rect2(minimum, maximum - minimum).grow(.25)
	_play("Walk")

func reset_behaviour(seed_value: int, saved: Dictionary = {}) -> void:
	behaviour_seed = seed_value
	rest_left = 0.0
	rest_pose = "Idle"
	pose_left = 0.0
	locomotion = "Walk"
	blocked_seconds = 0.0
	move_speed = 0.0
	if foot_plant != null: foot_plant.call("reset_contacts")
	if attention != null: attention.set("attention_time", float(seed_value % 1200) / 100.0)
	rng.seed = seed_value
	waiting_for_spawn=false;show();collision_layer=WorldBuilder.L_ACTORS
	if str(saved.get("seed", "")) == str(seed_value) and saved.has("position"):
		var at: Array = saved.position
		var position_saved := Vector3(float(at[0]), float(at[1]), float(at[2]))
		if habitat.has_point(Vector2(position_saved.x, position_saved.z)) and _clear(position_saved):
			global_position = position_saved
			rotation.y = float(saved.get("yaw", rotation.y))
			destination = clampi(int(saved.get("destination", 0)), 0, route.size()-1)
			rest_left = maxf(0.0, float(saved.get("rest", 0)))
			locomotion = str(saved.get("locomotion", "Walk"))
			rest_pose = str(saved.get("rest_pose", "Idle"))
			pose_left = maxf(0.0, float(saved.get("pose_left", 0)))
			blocked_seconds = maxf(0.0, float(saved.get("blocked_seconds", 0)))
			rng.state = str(saved.get("rng_state", str(rng.state))).to_int()
			last_position = global_position
			return
	var first: int=rng.randi_range(0,route.size()-1)
	for index: int in range(route.size()):
		var candidate: Vector3 = route[(first + index) % route.size()]
		if _clear(candidate):
			global_position = candidate
			last_position = global_position
			_choose_destination()
			return
	rest_left = 2.0
	waiting_for_spawn=true;hide();collision_layer=0

func _clear(at: Vector3) -> bool:
	var parameters := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new(); shape.size = Vector3(.16, .24, .24)
	parameters.shape = shape; parameters.exclude = [get_rid()]
	parameters.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED | WorldBuilder.L_ACTORS
	parameters.transform = Transform3D(Basis.IDENTITY, at + Vector3(0, .12, 0))
	return get_world_3d().direct_space_state.intersect_shape(parameters, 1).is_empty()

func _choose_destination() -> void:
	var candidates: Array[int] = []
	for index: int in route.size():
		if global_position.distance_to(route[index]) > .25 and _clear(route[index]): candidates.append(index)
	if candidates.is_empty(): rest_left = 1.0; return
	destination = candidates[rng.randi_range(0, candidates.size()-1)]
	var gait_roll: float = rng.randf()
	locomotion = "Run" if gait_roll < .10 else ("Sneak" if gait_roll < .23 else "Walk")
	if rng.randf() < .65:
		rest_left = rng.randf_range(.6, 3.2)
		rest_pose = "Idle"
		pose_left = 0.0
		if rest_left > 2.0:
			var activity_roll: float = rng.randf()
			if activity_roll < .45 and player.has_animation("SitDown"):
				rest_left = rng.randf_range(4.0, 7.0)
				rest_pose = "SitDown"
				pose_left = player.get_animation("SitDown").length
			elif activity_roll < .75 and player.has_animation("Stretch"):
				rest_left = player.get_animation("Stretch").length
				rest_pose = "Stretch"
				pose_left = rest_left
			elif activity_roll < .84 and player.has_animation("Jump"):
				rest_left = player.get_animation("Jump").length
				rest_pose = "Jump"
				pose_left = rest_left
	blocked_seconds = 0.0

func snapshot() -> Dictionary:
	return {"seed": str(behaviour_seed), "rng_state": str(rng.state), "destination": destination,
		"rest": rest_left, "rest_pose": rest_pose, "pose_left": pose_left, "locomotion": locomotion, "blocked_seconds": blocked_seconds, "yaw": rotation.y, "position": [global_position.x, global_position.y, global_position.z]}

func _play(animation_name: String, rate: float = 1.0) -> void:
	if player.current_animation != animation_name:
		player.play(animation_name, .16)
		if animation_history.is_empty() or animation_history[-1] != animation_name: animation_history.append(animation_name)
	player.speed_scale = rate

func _rest_step(delta: float) -> bool:
	if rest_left <= 0.0 and rest_pose not in ["StandUp", "SitDown"]: return false
	rest_left = maxf(0, rest_left - delta)
	pose_left = maxf(0, pose_left - delta)
	if rest_pose == "SitDown" and pose_left <= 0:
		rest_pose = "Sit"
	if rest_pose == "Sit" and rest_left <= .9:
		rest_pose = "StandUp"
		pose_left = player.get_animation("StandUp").length
		rest_left = maxf(rest_left, pose_left)
	if rest_pose in ["StandUp", "Stretch", "Jump"] and pose_left <= 0:
		rest_pose = "Idle"
		if rest_left <= 0: return false
	_play(rest_pose)
	return true

func _physics_process(delta: float) -> void:
	if model==null or route.size()<2: return
	if waiting_for_spawn:
		move_speed = 0.0
		rest_left=maxf(0,rest_left-delta)
		if rest_left<=0:reset_behaviour(behaviour_seed)
		return
	travelled+=global_position.distance_to(last_position)
	last_position=global_position
	if _rest_step(delta):
		move_speed = 0.0
		if attention != null: attention.set("turn_hint", 0.0)
		velocity=Vector3(0,-.1,0)
		move_and_slide()
		return
	var difference: Vector3 = route[destination]-global_position
	difference.y=0
	if difference.length()<.09:
		arrivals+=1
		_choose_destination()
		difference=route[destination]-global_position
		difference.y=0
	var desired_yaw: float = atan2(difference.x,difference.z)
	if attention != null: attention.set("turn_hint", angle_difference(rotation.y, desired_yaw))
	rotation.y=rotate_toward(rotation.y,desired_yaw,delta*2.1)
	var forward: Vector3 = Vector3(sin(rotation.y),0,cos(rotation.y))
	var travel_speed: float = native_run_speed if locomotion == "Run" else (native_sneak_speed if locomotion == "Sneak" else speed)
	var alignment: float = maxf(.35, cos(angle_difference(rotation.y, desired_yaw)))
	travel_speed *= alignment
	move_speed = move_toward(move_speed, travel_speed, delta * (.28 if travel_speed > move_speed else .48))
	travel_speed = move_speed
	velocity=forward*travel_speed
	velocity.y=-.1
	var predicted: Vector3 = global_position + Vector3(velocity.x, 0, velocity.z) * delta
	if not habitat.has_point(Vector2(predicted.x, predicted.z)):
		rotation.y = desired_yaw
		velocity = Vector3(sin(rotation.y)*travel_speed, -.1, cos(rotation.y)*travel_speed)
		predicted=global_position+Vector3(velocity.x,0,velocity.z)*delta
	if not habitat.has_point(Vector2(predicted.x,predicted.z)) or not _clear(predicted):
		if attention != null: attention.set("turn_hint", 0.0)
		velocity = Vector3(0, -.1, 0)
		move_speed = 0.0
		blocked_seconds += delta
		_play("Idle")
		if blocked_seconds > 1.0: _choose_destination()
		move_and_slide()
		return
	move_and_slide()
	var native_rate: float = native_run_speed if locomotion == "Run" else (native_sneak_speed if locomotion == "Sneak" else native_walk_speed)
	_play(locomotion, Vector2(velocity.x, velocity.z).length() / maxf(.02, native_rate))
	if headings.is_empty() or absf(angle_difference(headings[-1],rotation.y))>.35: headings.append(rotation.y)

func telemetry() -> Dictionary:
	return {"travelled_m":travelled,"arrivals":arrivals,"headings":headings,"animation":player.current_animation if player else "","position":[global_position.x,global_position.y,global_position.z], "behaviour": snapshot(), "blocked_seconds": blocked_seconds,
		"attention_seconds": float(attention.get("attention_time")) if attention != null else 0.0,
		"animation_history": animation_history, "rest_pose": rest_pose, "locomotion": locomotion,
		"foot_locked_samples": int(foot_plant.get("locked_samples")) if foot_plant != null else 0,
		"foot_lock_error": float(foot_plant.get("maximum_lock_error")) if foot_plant != null else 0.0,
		"head_look_degrees": rad_to_deg(float(attention.get("yaw"))) if attention != null else 0.0}

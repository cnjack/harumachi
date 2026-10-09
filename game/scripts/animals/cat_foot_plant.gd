extends SkeletonModifier3D
## Keep stance paws on their real world contacts while the actor turns or changes speed.
var animation: AnimationPlayer
var actor: CharacterBody3D
var previous_clip: String = ""
var planted: Array[bool] = [false, false, false, false]
var anchors: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var locked_samples: int = 0
var replants: int = 0
var maximum_lock_error: float = 0.0
var walk_phases: Array[float] = [0.0, .25, .5, .75]
var walk_duty: float = .76

func _ready() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null: return
	var metadata: Node = skeleton
	while metadata != null:
		var extras: Dictionary = metadata.get_meta("extras", {})
		if extras.has("gait_walk_phases"):
			var values: Array = extras.gait_walk_phases
			if values.size() == 4:
				for index: int in range(4): walk_phases[index] = float(values[index])
			walk_duty = float(extras.get("gait_duty_factor", .70))
			break
		metadata = metadata.get_parent()

const LIMBS: Array[Array] = [["Back", "L", 0.0], ["Front", "L", .25], ["Back", "R", .5], ["Front", "R", .75]]

func reset_contacts() -> void:
	planted = [false, false, false, false]

func aim(transform_pose: Transform3D, old_direction: Vector3, new_direction: Vector3, origin: Vector3) -> Transform3D:
	if old_direction.length_squared() > .000001 and new_direction.length_squared() > .000001:
		transform_pose.basis = Basis(Quaternion(old_direction.normalized(), new_direction.normalized())) * transform_pose.basis
	transform_pose.origin = origin
	return transform_pose

func _process_modification_with_delta(_delta: float) -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null or not is_instance_valid(animation) or not is_instance_valid(actor): return
	var clip: String = animation.current_animation
	if not actor.is_physics_processing() or clip not in ["Walk", "Run", "Sneak"]:
		reset_contacts()
		previous_clip = clip
		return
	if clip != previous_clip:
		reset_contacts()
		previous_clip = clip
	var period: float = .5 if clip == "Run" else (1.2 if clip == "Sneak" else 10.0 / 12.0)
	var duty: float = .62 if clip == "Run" else (.84 if clip == "Sneak" else walk_duty)
	for limb_index: int in range(4):
		var spec: Array = LIMBS[limb_index]
		var kind: String = str(spec[0])
		var side: String = str(spec[1])
		var offset: float = float(spec[2])
		if clip == "Walk": offset = walk_phases[limb_index]
		elif clip == "Run": offset = 0.0 if limb_index in [0, 3] else .5
		var phase: float = fposmod(animation.current_animation_position / period - offset, 1.0)
		if phase >= duty:
			planted[limb_index] = false
			continue
		var prefix: String = kind + "_Leg_"
		var suffix: String = "_" + side
		var upper: int = sk.find_bone(prefix + "Upper" + suffix)
		var lower: int = sk.find_bone(prefix + "Lower" + suffix)
		var ankle: int = sk.find_bone(prefix + "Ankle" + suffix)
		var foot: int = sk.find_bone(prefix + "Foot" + suffix)
		if mini(mini(upper, lower), mini(ankle, foot)) < 0: continue
		var u: Transform3D = sk.get_bone_global_pose(upper)
		var l: Transform3D = sk.get_bone_global_pose(lower)
		var a: Transform3D = sk.get_bone_global_pose(ankle)
		var f: Transform3D = sk.get_bone_global_pose(foot)
		var world_foot: Vector3 = sk.global_transform * f.origin
		if not planted[limb_index]:
			anchors[limb_index] = world_foot
			planted[limb_index] = true
		var target: Vector3 = sk.global_transform.affine_inverse() * anchors[limb_index]
		var ankle_target: Vector3 = target + a.origin - f.origin
		var length_1: float = sk.get_bone_global_rest(upper).origin.distance_to(sk.get_bone_global_rest(lower).origin)
		var length_2: float = sk.get_bone_global_rest(lower).origin.distance_to(sk.get_bone_global_rest(ankle).origin)
		var delta_target: Vector3 = ankle_target - u.origin
		if delta_target.length() > (length_1 + length_2) * 1.03:
			# Replant rather than stretching a planted leg after a sharp avoidance turn.
			anchors[limb_index] = world_foot
			replants += 1
			continue
		var distance: float = minf(delta_target.length(), (length_1 + length_2) * .998)
		if distance < .001: continue
		var direction: Vector3 = delta_target.normalized()
		var pole := Vector3(0, 0, -1 if kind == "Front" else 1)
		pole -= direction * direction.dot(pole)
		if pole.length_squared() < .00001: pole = Vector3.RIGHT
		pole = pole.normalized()
		var along: float = (length_1 * length_1 - length_2 * length_2 + distance * distance) / (2 * distance)
		var bend: float = sqrt(maxf(0, length_1 * length_1 - along * along))
		var joint: Vector3 = u.origin + direction * along + pole * bend
		var old_upper_direction: Vector3 = l.origin - u.origin
		var old_lower_direction: Vector3 = a.origin - l.origin
		var old_ankle_direction: Vector3 = f.origin - a.origin
		u = aim(u, old_upper_direction, joint - u.origin, u.origin)
		l = aim(l, old_lower_direction, ankle_target - joint, joint)
		a = aim(a, old_ankle_direction, target - ankle_target, ankle_target)
		f.origin = target
		sk.set_bone_global_pose(upper, u)
		sk.set_bone_global_pose(lower, l)
		sk.set_bone_global_pose(ankle, a)
		sk.set_bone_global_pose(foot, f)
		locked_samples += 1
		maximum_lock_error = maxf(maximum_lock_error, (sk.global_transform * sk.get_bone_global_pose(foot).origin).distance_to(anchors[limb_index]))

class_name FishingPose
extends SkeletonModifier3D
## Imported arm axes differ from the older procedural rig; solve in skeleton space.
var phase := 0.0
var amount := 0.0
var reel := 0.0
var player: Player
var hook := Vector3.ZERO
var palm_offsets: Dictionary = {}
var palm_world: Dictionary = {}
var updates := 0

func prepare(who: Player, water: Vector3) -> void:
	player = who
	hook = water
	var sk: Skeleton3D = get_skeleton()
	for side: String in ["L", "R"]:
		var hand: int = LivingPose.bone(sk, "hand." + side)
		if hand < 0: continue
		var finger: int = LivingPose.bone(sk, ("Right" if side == "R" else "Left") + "HandMiddle1")
		var rest: Transform3D = sk.get_bone_global_rest(hand)
		# Halfway from wrist to the knuckle row lies inside the actual palm.
		palm_offsets[side] = rest.affine_inverse() * rest.origin.lerp(sk.get_bone_global_rest(finger).origin, .55) if finger >= 0 else Vector3.ZERO

func palm(sk: Skeleton3D, side: String) -> Vector3:
	var hand: int = LivingPose.bone(sk, "hand." + side)
	return sk.get_bone_global_pose(hand) * (palm_offsets.get(side, Vector3.ZERO) as Vector3)

func solve(sk: Skeleton3D, side: String, goal_world: Vector3) -> void:
	var goal: Vector3 = sk.to_local(goal_world)
	var target: Vector3 = palm(sk, side).lerp(goal, amount)
	for iteration: int in range(10):
		for joint_name: String in ["fore." + side, "upper." + side]:
			var joint: int = LivingPose.bone(sk, joint_name)
			if joint < 0: continue
			var pose: Transform3D = sk.get_bone_global_pose(joint)
			var from: Vector3 = palm(sk, side) - pose.origin
			var toward: Vector3 = target - pose.origin
			if from.length_squared() < .000001 or toward.length_squared() < .000001: continue
			pose.basis = Basis(Quaternion(from.normalized(), toward.normalized())) * pose.basis
			sk.set_bone_global_pose(joint, pose)

func _process_modification_with_delta(_delta: float) -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null or not is_instance_valid(player): return
	if amount > 0:
		var forward: Vector3 = hook - player.global_position
		forward.y = 0
		forward = forward.normalized()
		var right: Vector3 = forward.cross(Vector3.UP)
		var grip: Vector3 = player.global_position + Vector3.UP * 1.02 + forward * .37 + right * .16
		var crank: Vector3 = grip - right * .24 + forward * .05 - Vector3.UP * .035
		crank += (forward * cos(phase * 4.6) + Vector3.UP * sin(phase * 4.6)) * .035 * reel
		for side: String in ["R", "L"]:
			if palm_offsets.has(side):solve(sk, side, grip if side == "R" else crank)
	palm_world.clear()
	for side: String in palm_offsets:
		palm_world[side] = sk.to_global(palm(sk, side))
	updates += 1

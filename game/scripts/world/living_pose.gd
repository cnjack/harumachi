class_name LivingPose
extends SkeletonModifier3D
## CCD keeps the real forearm/upper-arm chain attached while bringing the hand to the mouth.
var phase := 0.0
var amount := 0.0
var sip := false
var goal_world := Vector3.ZERO

static func bone(sk: Skeleton3D, name: String) -> int:
	var index: int = sk.find_bone(name)
	if index >= 0: return index
	var imported: String = {"upper.R": "RightArm", "fore.R": "RightForeArm", "hand.R": "RightHand", "head": "Head", "hips":"Hips", "thigh.L":"LeftUpLeg", "thigh.R":"RightUpLeg", "shin.L":"LeftLeg", "shin.R":"RightLeg", "foot.L":"LeftFoot", "foot.R":"RightFoot", "toe.L":"LeftToeBase", "toe.R":"RightToeBase"}.get(name, name)
	index = sk.find_bone("mixamorig:" + imported)
	return index if index >= 0 else sk.find_bone("mixamorig_" + imported)

func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null: return
	var hand: int = bone(skeleton, "hand.R")
	if hand < 0: return
	var lift: float = sin(clampf(phase, 0.0, 1.0) * PI) * amount
	var goal: Vector3 = skeleton.global_transform.affine_inverse() * goal_world
	var initial: Vector3 = skeleton.get_bone_global_pose(hand).origin
	var target: Vector3 = initial.lerp(goal, lift)
	for _iteration in 5:
		for name: String in ["fore.R", "upper.R"]:
			var joint: int = bone(skeleton, name)
			if joint < 0: continue
			var global_pose: Transform3D = skeleton.get_bone_global_pose(joint)
			var inverse: Basis = global_pose.basis.inverse()
			var to_hand: Vector3 = inverse * (skeleton.get_bone_global_pose(hand).origin - global_pose.origin)
			var to_target: Vector3 = inverse * (target - global_pose.origin)
			if to_hand.length() < .001 or to_target.length() < .001: continue
			var delta_rotation := Quaternion(to_hand.normalized(), to_target.normalized())
			skeleton.set_bone_pose_rotation(joint, skeleton.get_bone_pose_rotation(joint) * delta_rotation)

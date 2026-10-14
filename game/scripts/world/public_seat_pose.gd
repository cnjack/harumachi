class_name PublicSeatPose
extends SkeletonModifier3D
## Hips contact the measured seat; feet stay planted and the upper body keeps its idle.
var actor: Node3D
var seat_height := .48
var measured_hip_height := INF
var measured_knee_forward := 0.0
var blend := 1.0

func plant_leg(skeleton: Skeleton3D,side: String,forward_world: Vector3) -> void:
	var thigh: int=LivingPose.bone(skeleton,"thigh."+side)
	var shin: int=LivingPose.bone(skeleton,"shin."+side)
	var foot: int=LivingPose.bone(skeleton,"foot."+side)
	if thigh<0 or shin<0 or foot<0:return
	var hip: Vector3=skeleton.to_global(skeleton.get_bone_global_pose(thigh).origin)
	var knee: Vector3=skeleton.to_global(skeleton.get_bone_global_pose(shin).origin)
	var ankle: Vector3=skeleton.to_global(skeleton.get_bone_global_pose(foot).origin)
	var upper: float=hip.distance_to(knee)
	var lower: float=knee.distance_to(ankle)
	if upper<.001 or lower<.001:return
	# The imported standing foot already has the shoe sole flat on the ground.
	# Keep that orientation/ankle height, and solve the legs without lowering the hips.
	var foot_rest: Transform3D=skeleton.get_bone_global_rest(foot)
	var rest_ankle: Vector3=skeleton.to_global(foot_rest.origin)
	var rest_hip: Vector3=skeleton.to_global(skeleton.get_bone_global_rest(thigh).origin)
	var sideways: Vector3=Vector3.UP.cross(forward_world).normalized()
	var target: Vector3=hip+forward_world*.34+sideways*(rest_ankle-rest_hip).dot(sideways)
	target.y=rest_ankle.y
	var reach: Vector3=target-hip
	var distance: float=clampf(reach.length(),absf(upper-lower)+.001,upper+lower-.001)
	var direction: Vector3=reach.normalized()
	var along: float=(upper*upper-lower*lower+distance*distance)/(2.0*distance)
	var bend: float=sqrt(maxf(0.0,upper*upper-along*along))
	var toward_knee: Vector3=(forward_world-direction*forward_world.dot(direction)).normalized()
	var knee_goal: Vector3=hip+direction*along+toward_knee*bend
	aim(skeleton,"thigh."+side,"shin."+side,skeleton.global_basis.inverse()*(knee_goal-hip))
	var placed_knee: Vector3=skeleton.to_global(skeleton.get_bone_global_pose(shin).origin)
	aim(skeleton,"shin."+side,"foot."+side,skeleton.global_basis.inverse()*(target-placed_knee))
	var foot_pose: Transform3D=skeleton.get_bone_global_pose(foot)
	foot_pose.basis=foot_rest.basis
	skeleton.set_bone_global_pose(foot,foot_pose)

func aim(skeleton: Skeleton3D,joint_name: String,end_name: String,direction: Vector3) -> void:
	var joint: int=LivingPose.bone(skeleton,joint_name);var end: int=LivingPose.bone(skeleton,end_name)
	if joint<0 or end<0:return
	var pose: Transform3D=skeleton.get_bone_global_pose(joint)
	var current: Vector3=skeleton.get_bone_global_pose(end).origin-pose.origin
	if current.length()<.001:return
	pose.basis=Basis(Quaternion(current.normalized(),direction.normalized()))*pose.basis
	skeleton.set_bone_global_pose(joint,pose)

func _process_modification() -> void:
	var skeleton:=get_skeleton()
	if skeleton==null or not is_instance_valid(actor):return
	var before: Dictionary = {}
	if blend < 1.0:
		for index: int in skeleton.get_bone_count():
			before[index] = Transform3D(Basis(skeleton.get_bone_pose_rotation(index)).scaled(skeleton.get_bone_pose_scale(index)), skeleton.get_bone_pose_position(index))
	var hips: int=LivingPose.bone(skeleton,"hips")
	if hips<0:return
	var pose: Transform3D=skeleton.get_bone_global_pose(hips)
	var hip_world: Vector3=skeleton.to_global(pose.origin)
	pose.origin+=skeleton.global_basis.inverse()*Vector3.UP*(actor.global_position.y+seat_height+.09-hip_world.y)
	skeleton.set_bone_global_pose(hips,pose)
	var forward: Vector3=_forward()
	for side: String in ["L","R"]:
		plant_leg(skeleton,side,forward)
		# Relax the forearms toward the lap instead of letting straight fingers
		# hang through a seat. This pose carries no prop and has no grip target.
		aim(skeleton,"fore."+side,"hand."+side,skeleton.global_basis.inverse()*(forward*.70-Vector3.UP*.72))
	measured_hip_height=skeleton.to_global(skeleton.get_bone_global_pose(hips).origin).y-actor.global_position.y
	var knee: int=LivingPose.bone(skeleton,"shin.R")
	if knee>=0:
		measured_knee_forward=(skeleton.to_global(skeleton.get_bone_global_pose(knee).origin)-skeleton.to_global(skeleton.get_bone_global_pose(hips).origin)).dot(_forward())
	if blend < 1.0:
		for index: int in before:
			var previous: Transform3D = before[index]
			var current := Transform3D(Basis(skeleton.get_bone_pose_rotation(index)).scaled(skeleton.get_bone_pose_scale(index)), skeleton.get_bone_pose_position(index))
			var mixed: Transform3D=previous.interpolate_with(current,clampf(blend,0.0,1.0))
			skeleton.set_bone_pose_position(index,mixed.origin)
			skeleton.set_bone_pose_rotation(index,mixed.basis.get_rotation_quaternion())
			skeleton.set_bone_pose_scale(index,mixed.basis.get_scale())

func _exit_tree() -> void:
	if is_instance_valid(actor) and actor.has_meta("seated_mouth"): actor.remove_meta("seated_mouth")

func _forward() -> Vector3:
	if actor is Player:return (actor as Player).model_root.global_basis.z.normalized()
	if actor is NPC:return (actor as NPC).model.global_basis.z.normalized()
	return actor.global_basis.z.normalized()

class_name PublicSeatPose
extends SkeletonModifier3D
## A seated lower-body pose on the existing skeleton; the upper body keeps its idle/sip motion.
var actor: Player
var seat_height := .48
var measured_hip_height := INF
var measured_knee_forward := 0.0

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
	var hips: int=LivingPose.bone(skeleton,"hips")
	if hips<0:return
	var pose: Transform3D=skeleton.get_bone_global_pose(hips)
	var hip_world: Vector3=skeleton.to_global(pose.origin)
	pose.origin+=skeleton.global_basis.inverse()*Vector3.UP*(actor.global_position.y+seat_height+.09-hip_world.y)
	skeleton.set_bone_global_pose(hips,pose)
	var forward: Vector3=skeleton.global_basis.inverse()*actor.model_root.global_basis.z.normalized()
	var down: Vector3=skeleton.global_basis.inverse()*Vector3.DOWN
	for side: String in ["L","R"]:
		aim(skeleton,"thigh."+side,"shin."+side,forward+down*.25)
		aim(skeleton,"shin."+side,"foot."+side,down+forward*.03)
		aim(skeleton,"foot."+side,"toe."+side,forward+down*.10)
	var head: int=LivingPose.bone(skeleton,"head")
	if head>=0:actor.set_meta("seated_mouth",skeleton.to_global(skeleton.get_bone_global_pose(head).origin)-Vector3.UP*.05)
	measured_hip_height=skeleton.to_global(skeleton.get_bone_global_pose(hips).origin).y-actor.global_position.y
	var knee: int=LivingPose.bone(skeleton,"shin.R")
	if knee>=0:
		measured_knee_forward=(skeleton.to_global(skeleton.get_bone_global_pose(knee).origin)-skeleton.to_global(skeleton.get_bone_global_pose(hips).origin)).dot(actor.model_root.global_basis.z.normalized())

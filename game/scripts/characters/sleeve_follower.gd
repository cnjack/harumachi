extends SkeletonModifier3D
## Reset helper bones to their authored rest and place arm collision proxies before springs.
var colliders: Array[Dictionary]=[]

func _process_modification() -> void:
	var sk: Skeleton3D=get_skeleton()
	if sk==null:return
	for bone: int in range(sk.get_bone_count()):
		if String(sk.get_bone_name(bone)).begins_with("Cloth_"):
			sk.set_bone_pose_rotation(bone,sk.get_bone_rest(bone).basis.get_rotation_quaternion())
	for item: Dictionary in colliders:
		var pose: Transform3D=sk.global_transform*sk.get_bone_global_pose(int(item.bone))
		pose.origin+=pose.basis.y.normalized()*float(item.height)*.5
		(item.node as Node3D).global_transform=pose

extends SkeletonModifier3D
# Bound only helper-bone rotations after the native spring solve. The original
# motion bones and corrective shapes are left intact.
var angle_limit: float=deg_to_rad(12.0)
var samples: int=0
var max_input_degrees: float=0
var max_output_degrees: float=0

func _process_modification() -> void:
	var skeleton: Skeleton3D=get_skeleton()
	if skeleton==null:return
	samples+=1
	for index: int in range(skeleton.get_bone_count()):
		if not String(skeleton.get_bone_name(index)).begins_with("Cloth_"):continue
		var rest: Quaternion=skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		var pose: Quaternion=skeleton.get_bone_pose_rotation(index)
		var angle: float=rest.angle_to(pose)
		max_input_degrees=maxf(max_input_degrees,rad_to_deg(angle))
		if angle>angle_limit:
			pose=rest.slerp(pose,angle_limit/angle).normalized()
			skeleton.set_bone_pose_rotation(index,pose)
		max_output_degrees=maxf(max_output_degrees,rad_to_deg(rest.angle_to(pose)))

extends SkeletonModifier3D
## Attention runs across Walk/Idle transitions, after the locomotion pose.
var attention_time: float = 0.0
var yaw: float = 0.0
var turn_hint: float = 0.0
var nearby_target: Node3D
var target_origin: Node3D
var looking_at_neighbour: bool = false
var center_in_head := Vector3.ZERO
var centered_pivot: bool = false

func _ready() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null: return
	var metadata_node: Node = skeleton
	while metadata_node != null:
		var extras: Dictionary = metadata_node.get_meta("extras", {})
		if extras.has("head_center_rest"):
			var coordinates: Array = extras.head_center_rest
			var rest_center := Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
			center_in_head = skeleton.get_bone_global_rest(skeleton.find_bone("Head")).affine_inverse() * rest_center
			centered_pivot = true
			break
		metadata_node = metadata_node.get_parent()

func scan_angle(time: float) -> float:
	# Brief looks with a hold, separated by time looking along the path.
	var keys: Array[Vector2] = [Vector2(0, 0), Vector2(.8, 0), Vector2(1.6, 45), Vector2(2.8, 45), Vector2(3.7, 0), Vector2(5.5, 0), Vector2(6.3, -45), Vector2(7.6, -45), Vector2(8.5, 0), Vector2(12, 0)]
	var at: float = fposmod(time, 12.0)
	for index: int in range(keys.size() - 1):
		if at <= keys[index + 1].x:
			var fraction: float = inverse_lerp(keys[index].x, keys[index + 1].x, at)
			return deg_to_rad(lerpf(keys[index].y, keys[index + 1].y, smoothstep(0, 1, fraction)))
	return 0.0

func _process_modification_with_delta(delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null: return
	attention_time += delta
	var desired: float = scan_angle(attention_time) + clampf(turn_hint * .35, -.18, .18)
	looking_at_neighbour = false
	if is_instance_valid(nearby_target) and is_instance_valid(target_origin) and fposmod(attention_time, 12.0) > 9.0:
		var offset: Vector3 = target_origin.to_local(nearby_target.global_position)
		if offset.length() < 2.5 and offset.z > -.5:
			desired = clampf(atan2(offset.x, offset.z), deg_to_rad(-50), deg_to_rad(50))
			looking_at_neighbour = true
	yaw = move_toward(yaw, clampf(desired, deg_to_rad(-50), deg_to_rad(50)), delta * deg_to_rad(85))
	var head: int = skeleton.find_bone("Head")
	var neck: int = skeleton.find_bone("Spine_4")
	if head < 0 or neck < 0: return
	var head_pose: Transform3D = skeleton.get_bone_global_pose(head)
	var neck_pose: Transform3D = skeleton.get_bone_global_pose(neck)
	var rotation_basis := Basis(Vector3.UP, yaw)
	var neck_rotation := Basis(Vector3.UP, yaw * .3)
	if centered_pivot:
		var cranial_center: Vector3 = head_pose * center_in_head
		head_pose.origin = cranial_center + rotation_basis * (head_pose.origin - cranial_center)
	else:
		head_pose.origin = neck_pose.origin + neck_rotation * (head_pose.origin - neck_pose.origin)
	head_pose.basis = rotation_basis * head_pose.basis
	neck_pose.basis = neck_rotation * neck_pose.basis
	skeleton.set_bone_global_pose(neck, neck_pose)
	skeleton.set_bone_global_pose(head, head_pose)

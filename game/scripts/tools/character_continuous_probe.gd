extends SkeletonModifier3D
## Native QA: append AFTER every existing modifier. Reads final applied pose once per rendered frame.
## Requires CharacterFootSupport's existing <=26 cached shoe points. Does not rescan the mesh.
var model: Node3D
var actor: Node3D
var animation: AnimationPlayer
var floor_height := 0.0
var recording := false
var rows: Array[Dictionary] = []
var indices: Dictionary = {}
var support: Node
var natural: Node
var last_frame := -1
var began_usec := 0
var bone_layout: Array[Dictionary] = []
var shape_meshes: Array[MeshInstance3D] = []
var shape_names: Array[PackedStringArray] = []
const JOINTS: Array[String] = ["hips", "chest", "head", "upper.L", "fore.L", "hand.L", "upper.R", "fore.R", "hand.R", "thigh.L", "shin.L", "foot.L", "toe.L", "thigh.R", "shin.R", "foot.R", "toe.R"]

func prepare(source: Node3D, target: Node3D, player: AnimationPlayer, ground: float) -> void:
	model = source
	actor = target
	animation = player
	floor_height = ground
	var skeleton: Skeleton3D = get_skeleton()
	for bone: int in skeleton.get_bone_count():
		bone_layout.append({"name": skeleton.get_bone_name(bone), "parent": skeleton.get_bone_parent(bone)})
	for candidate: MeshInstance3D in WorldBuilder.find_meshes(source):
		if not candidate.mesh is ArrayMesh: continue
		var geometry: ArrayMesh = candidate.mesh as ArrayMesh
		if geometry.get_blend_shape_count() == 0: continue
		var names := PackedStringArray()
		for shape: int in geometry.get_blend_shape_count(): names.append(str(geometry.get_blend_shape_name(shape)))
		shape_meshes.append(candidate)
		shape_names.append(names)
	for joint: String in JOINTS:
		indices[joint] = LivingPose.bone(skeleton, joint)
	support = skeleton.get_node_or_null("CharacterFootSupport")
	natural = skeleton.get_node_or_null("NaturalLocomotionPose")

func vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func begin() -> void:
	rows.clear()
	last_frame = -1
	began_usec = Time.get_ticks_usec()
	recording = true

func _process_modification() -> void:
	if not recording or model == null or animation == null: return
	var frame: int = Engine.get_process_frames()
	var replaces_same_frame: bool = frame == last_frame
	var skeleton: Skeleton3D = get_skeleton()
	var final_transforms: Array[Array] = []
	for bone: int in skeleton.get_bone_count():
		var applied: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		final_transforms.append([applied.origin.x, applied.origin.y, applied.origin.z, applied.basis.x.x, applied.basis.x.y, applied.basis.x.z, applied.basis.y.x, applied.basis.y.y, applied.basis.y.z, applied.basis.z.x, applied.basis.z.y, applied.basis.z.z])
	var actual_shapes: Dictionary = {}
	for mesh_index: int in shape_meshes.size():
		var current_mesh: MeshInstance3D = shape_meshes[mesh_index]
		var actual: Dictionary = {}
		for shape: int in shape_names[mesh_index].size(): actual[shape_names[mesh_index][shape]] = current_mesh.get_blend_shape_value(shape)
		actual_shapes[str(current_mesh.name)] = actual
	var joints: Dictionary = {}
	for joint: String in JOINTS:
		var index: int = int(indices.get(joint, -1))
		if index >= 0: joints[joint] = vector_array(skeleton.to_global(skeleton.get_bone_global_pose(index).origin))
	var feet: Dictionary = {}
	for side: String in ["L", "R"]:
		var points: Array = support.call("points", skeleton, side) if support != null else []
		var values: Array = []
		var lowest := INF
		var lowest_index := -1
		for index: int in points.size():
			var point: Vector3 = points[index]
			values.append(vector_array(point))
			if point.y < lowest:
				lowest = point.y
				lowest_index = index
		feet[side] = {"cached_points_world": values, "min_y": lowest if is_finite(lowest) else null, "min_index": lowest_index, "ground_gap": lowest - floor_height if is_finite(lowest) else null}
	var length: float = maxf(animation.current_animation_length, .001)
	var trace: Dictionary = (support.get("qa_trace") as Dictionary).duplicate(true) if support != null and support.get("qa_trace") != null else {}
	var natural_trace: Dictionary = (natural.get("qa_trace") as Dictionary).duplicate(true) if natural != null and natural.get("qa_trace") != null else {}
	var row: Dictionary = {"frame": frame, "physics_frame": Engine.get_physics_frames(), "elapsed_s": (Time.get_ticks_usec() - began_usec) / 1000000.0, "actor_position": vector_array(actor.global_position), "model_position": vector_array(model.global_position), "model_basis": [vector_array(model.global_basis.x), vector_array(model.global_basis.y), vector_array(model.global_basis.z)], "clip": animation.current_animation, "clip_time": animation.current_animation_position, "phase": fposmod(animation.current_animation_position / length, 1.0), "playback_scale": animation.speed_scale, "joints": joints, "feet": feet, "bone_transforms": final_transforms, "blend_shape_values": actual_shapes, "foot_support_trace": trace, "natural_pose_trace": natural_trace, "same_frame_callbacks": int(rows.back().get("same_frame_callbacks", 1)) + 1 if replaces_same_frame else 1}
	# play/seek may trigger an immediate modifier update before the ordinary
	# animation tick. Only the last callback is the pose submitted to rendering.
	if replaces_same_frame: rows[rows.size() - 1] = row
	else: rows.append(row)
	last_frame = frame

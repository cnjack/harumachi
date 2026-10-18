extends SkeletonModifier3D
## Read the final modifier pose while it is applied; Skeleton3D restores it afterwards.
var model: Node3D
var measure_feet := false
var joints: Dictionary = {}
var measure_bones := false
var all_bones: Array[Dictionary] = []
var soles: Dictionary = {}
var _vertices: Array[Dictionary] = []
var _shape_meshes: Array[Dictionary] = []
var support_rect_enabled := false
var support_rect := Rect2()
var support_height := 0.0
var base_support_height := 0.0
var request_id := 0
var completed_request := -1
var applied_frame := -1
var clip := ""
var clip_time := 0.0
var result: Dictionary = {}
var _animation: AnimationPlayer
var _request_frame := -1
var _expected_clip := ""
var _expected_time := -1.0
var _pending := false
var _callback_frame := -1
var _callbacks_in_frame := 0

func request(expected_clip: String = "", expected_time: float = -1.0) -> int:
	request_id += 1
	_request_frame = Engine.get_process_frames()
	_expected_clip = expected_clip
	_expected_time = expected_time
	_pending = true
	return request_id

func prepare(source: Node3D) -> void:
	model = source
	_animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sk: Skeleton3D = get_skeleton()
	_shape_meshes.clear()
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
		if mesh.mesh is ArrayMesh and (mesh.mesh as ArrayMesh).get_blend_shape_count() > 0:
			var names: Array[String] = []
			for shape: int in (mesh.mesh as ArrayMesh).get_blend_shape_count():
				names.append(str((mesh.mesh as ArrayMesh).get_blend_shape_name(shape)))
			_shape_meshes.append({"mesh": mesh, "names": names})
		if mesh.skin == null: continue
		var binds: Array[int] = []
		var sides: Array[String] = []
		for index: int in mesh.skin.get_bind_count():
			var bone: int = mesh.skin.get_bind_bone(index)
			if bone < 0: bone = sk.find_bone(mesh.skin.get_bind_name(index))
			binds.append(bone)
			var bone_name: String = sk.get_bone_name(bone) if bone >= 0 else ""
			sides.append("L" if bone_name.contains("LeftFoot") or bone_name.contains("LeftToe") or bone_name in ["foot.L", "toe.L"] else "R" if bone_name.contains("RightFoot") or bone_name.contains("RightToe") or bone_name in ["foot.R", "toe.R"] else "")
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty() or positions.is_empty(): continue
			var influences: int = bones.size() / positions.size()
			for vertex: int in positions.size():
				var foot_weights: Dictionary = {"L": 0.0, "R": 0.0}
				for influence: int in influences:
					var bind: int = bones[vertex * influences + influence]
					if sides[bind] != "": foot_weights[sides[bind]] += weights[vertex * influences + influence]
				var side: String = "L" if float(foot_weights.L) > float(foot_weights.R) else "R"
				if float(foot_weights[side]) < .35: continue
				var chain: Array[Dictionary] = []
				for influence: int in influences:
					var weight: float = weights[vertex * influences + influence]
					if weight <= 0: continue
					var bind: int = bones[vertex * influences + influence]
					chain.append({"bone": binds[bind], "inverse_bind": mesh.skin.get_bind_pose(bind), "weight": weight})
				_vertices.append({"position": positions[vertex], "chain": chain, "side": side})

func _process_modification() -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null: return
	joints.clear()
	if measure_bones:
		all_bones.clear()
		for index: int in sk.get_bone_count():
			var pose: Transform3D = sk.global_transform * sk.get_bone_global_pose(index)
			all_bones.append({"name": sk.get_bone_name(index), "parent": sk.get_bone_parent(index), "position": [pose.origin.x, pose.origin.y, pose.origin.z], "basis": [[pose.basis.x.x, pose.basis.x.y, pose.basis.x.z], [pose.basis.y.x, pose.basis.y.y, pose.basis.y.z], [pose.basis.z.x, pose.basis.z.y, pose.basis.z.z]]})
	for joint: String in ["hips", "head", "hand.R", "hand.L", "thigh.L", "shin.L", "foot.L", "toe.L", "thigh.R", "shin.R", "foot.R", "toe.R"]:
		var index: int = LivingPose.bone(sk, joint)
		if index >= 0:
			var point: Vector3 = sk.to_global(sk.get_bone_global_pose(index).origin)
			joints[joint] = [point.x, point.y, point.z]
	if not measure_feet:
		_complete_sample()
		return
	soles = {"L": INF, "R": INF, "vertices": _vertices.size()}
	if support_rect_enabled:
		soles["ground_gap_L"] = INF
		soles["ground_gap_R"] = INF
	for side: String in ["L", "R"]:
		var foot: int = LivingPose.bone(sk, "foot." + side)
		var toe: int = LivingPose.bone(sk, "toe." + side)
		if foot < 0 or toe < 0: continue
		var actual: Vector3 = sk.global_basis * (sk.get_bone_global_pose(toe).origin - sk.get_bone_global_pose(foot).origin)
		var rest: Vector3 = sk.global_basis * (sk.get_bone_global_rest(toe).origin - sk.get_bone_global_rest(foot).origin)
		var pitch: float = rad_to_deg(asin(clampf(actual.normalized().dot(Vector3.UP), -1.0, 1.0)))
		var rest_pitch: float = rad_to_deg(asin(clampf(rest.normalized().dot(Vector3.UP), -1.0, 1.0)))
		soles["pitch_" + side] = pitch
		soles["pitch_error_" + side] = absf(pitch - rest_pitch)
	for vertex: Dictionary in _vertices:
		var point := Vector3.ZERO
		for influence: Dictionary in vertex.chain:
			var transform: Transform3D = sk.get_bone_global_pose(int(influence.bone)) * (influence.inverse_bind as Transform3D)
			point += (transform * (vertex.position as Vector3)) * float(influence.weight)
		var world: Vector3 = sk.to_global(point)
		if world.y < float(soles[vertex.side]):
			soles[vertex.side] = world.y
			soles["point_" + str(vertex.side)] = [world.x, world.y, world.z]
		if support_rect_enabled:
			var support: float = support_height if support_rect.has_point(Vector2(world.x, world.z)) else base_support_height
			var gap: float = world.y - support
			if gap < float(soles["ground_gap_" + str(vertex.side)]):
				soles["ground_gap_" + str(vertex.side)] = gap
				soles["ground_point_" + str(vertex.side)] = [world.x, world.y, world.z]
	_complete_sample()

func _complete_sample() -> void:
	# This acknowledgement is written only from the final modifier callback,
	# after all requested geometry has been skinned. A process-frame wait alone
	# cannot prove a new pose reached the skeleton in a fast headless test.
	applied_frame = Engine.get_process_frames()
	if _callback_frame != applied_frame:
		_callback_frame = applied_frame
		_callbacks_in_frame = 0
	_callbacks_in_frame += 1
	clip = _animation.current_animation if _animation != null else ""
	clip_time = _animation.current_animation_position if _animation != null else 0.0
	# play/seek can cause an early forced callback and a later normal animation
	# callback in the same rendered frame. Keep this request's last atomic pose,
	# while leaving completed history untouched in all subsequent frames.
	var refresh_same_frame: bool = not _pending and completed_request == request_id and int(result.get("request_id", -1)) == request_id and int(result.get("applied_frame", -1)) == applied_frame
	if (not _pending and not refresh_same_frame) or applied_frame <= _request_frame: return
	if _expected_clip != "" and clip != _expected_clip: return
	if _expected_time >= 0 and absf(clip_time - _expected_time) >= .0001: return
	var blend_shapes: Dictionary = {}
	if measure_bones:
		for cached: Dictionary in _shape_meshes:
			var mesh: MeshInstance3D = cached.mesh as MeshInstance3D
			var values: Dictionary = {}
			var names: Array = cached.names
			for shape: int in names.size(): values[names[shape]] = mesh.get_blend_shape_value(shape)
			blend_shapes[str(mesh.name)] = values
	# Capture actual node values in this same callback. During AnimationPlayer
	# crossfades these differ from sampling the new clip's scalar curve by time.
	result = {"request_id": request_id, "request_frame": _request_frame, "applied_frame": applied_frame, "callbacks_in_frame": _callbacks_in_frame, "clip": clip, "clip_time": clip_time, "measure_feet": measure_feet, "measure_bones": measure_bones, "joints": joints.duplicate(true), "soles": soles.duplicate(true), "bones": all_bones.duplicate(true), "bone_pose_hash": hash(all_bones) if measure_bones else hash(joints), "blend_shape_values": blend_shapes}
	completed_request = request_id
	_pending = false

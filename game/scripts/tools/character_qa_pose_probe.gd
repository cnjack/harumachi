extends SkeletonModifier3D
## Read the final modifier pose while it is applied; Skeleton3D restores it afterwards.
var model: Node3D
var measure_feet := false
var joints: Dictionary = {}
var soles: Dictionary = {}
var _vertices: Array[Dictionary] = []
var support_rect_enabled := false
var support_rect := Rect2()
var support_height := 0.0
var base_support_height := 0.0

func prepare(source: Node3D) -> void:
	model = source
	var sk: Skeleton3D = get_skeleton()
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
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
	for joint: String in ["hips", "head", "hand.R", "thigh.L", "shin.L", "foot.L", "toe.L", "thigh.R", "shin.R", "foot.R", "toe.R"]:
		var index: int = LivingPose.bone(sk, joint)
		if index >= 0:
			var point: Vector3 = sk.to_global(sk.get_bone_global_pose(index).origin)
			joints[joint] = [point.x, point.y, point.z]
	if not measure_feet: return
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

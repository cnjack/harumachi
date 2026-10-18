extends SkeletonModifier3D
## Test-only full skinning and independent front/back original painted-source BVHs.
## Source paint survives hidden rest folds; exterior selection uses final poses.
var pending := false
var request_id := 0
var measured_id := 0
var request_frame := -1
var expected_clip := ""
var expected_time := -1.0
var callback_frame := -1
var callbacks_in_frame := 0
var result: Dictionary = {}
var mesh: MeshInstance3D
var animation: AnimationPlayer
var shape_index := -1
var faces: Dictionary = {"front": [], "back": []}
var pants: PackedInt32Array = []
var records: Dictionary = {}
var support: Node

func request(clip: String = "", time: float = -1.0) -> int:
	request_id += 1
	request_frame = Engine.get_process_frames()
	expected_clip = clip
	expected_time = time
	pending = true
	return request_id

func prepare(model: Node3D) -> void:
	animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	support = model.find_child("CharacterApronSupport", true, false)
	var sk: Skeleton3D = get_skeleton()
	for candidate: MeshInstance3D in WorldBuilder.find_meshes(model):
		var candidate_geometry: ArrayMesh = candidate.mesh as ArrayMesh
		if candidate_geometry == null or candidate.skin == null: continue
		for index: int in candidate_geometry.get_blend_shape_count():
			if candidate_geometry.get_blend_shape_name(index) == "Apron_Clearance":
				mesh = candidate
				shape_index = index
		if mesh != null: break
	if mesh == null:
		result = {"error": "actual Apron_Clearance mesh missing"}
		return
	var geometry: ArrayMesh = mesh.mesh as ArrayMesh
	var arrays: Array = geometry.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var shapes: Array = geometry.surface_get_blend_shape_arrays(0)
	var relative: bool = geometry.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	var material: BaseMaterial3D = mesh.get_active_material(0) as BaseMaterial3D
	if material == null or material.albedo_texture == null:
		result = {"error": "original apron texture missing"}
		return
	var atlas: Image = material.albedo_texture.get_image()
	if atlas.is_compressed(): atlas.decompress()
	var height := 0.0
	for point: Vector3 in positions: height = maxf(height, point.y)
	var hip: int = LivingPose.bone(sk, "hips")
	var hip_z: float = sk.get_bone_global_rest(hip).origin.z
	var yellow: Dictionary = {"front": PackedByteArray(), "back": PackedByteArray()}
	# Packed arrays are values; resize and assign explicitly.
	for layer: String in ["front", "back"]:
		var flags: PackedByteArray = yellow[layer]
		flags.resize(positions.size())
		yellow[layer] = flags
	var local_shape_indices := PackedInt32Array()
	for local_target: int in geometry.get_blend_shape_count():
		if str(geometry.get_blend_shape_name(local_target)).begins_with("Garment_Local_"): local_shape_indices.append(local_target)
	for index: int in positions.size():
		var point: Vector3 = positions[index]
		if absf(point.x) > .20 * height or point.y < .20 * height or point.y > .55 * height: continue
		var texel: Color = atlas.get_pixel(posmod(int(uv[index].x * atlas.get_width()), atlas.get_width()), posmod(int(uv[index].y * atlas.get_height()), atlas.get_height()))
		var cloth: bool = texel.r > texel.g * .95 and texel.r < texel.g * 1.9 and texel.b < texel.g * .65 and texel.g > .18
		if cloth:
			# Keep every original painted source face in this region. A fold
			# hidden at rest can become the exterior after skinning/morphs;
			# select its first exterior only in the final-pose BVH below.
			for layer: String in ["front", "back"]:
				var flags: PackedByteArray = yellow[layer]
				flags[index] = 1
				yellow[layer] = flags
		elif maxf(texel.r, maxf(texel.g, texel.b)) < .36 and point.y > .24 * height and absf(point.x) < .14 * height:
			var neutral: bool = maxf(texel.r, maxf(texel.g, texel.b)) - minf(texel.r, minf(texel.g, texel.b)) < .08
			var clothing_support := 0.0
			if not neutral:
				for local_shape: int in local_shape_indices:
					var local_points: PackedVector3Array = shapes[local_shape][Mesh.ARRAY_VERTEX]
					var local_delta: Vector3 = local_points[index] if relative else local_points[index] - positions[index]
					clothing_support += absf(local_delta.z)
			# Preserve every neutral trouser label and every unknown unsupported
			# boundary point. Only a nonneutral Local-supported cloth point is
			# excluded; source faces and physical acceptance gates stay intact.
			if neutral or clothing_support <= .000001: pants.append(index)
	for offset: int in range(0, indices.size(), 3):
		var triangle := PackedInt32Array([indices[offset], indices[offset + 1], indices[offset + 2]])
		var centre: Vector3 = (positions[triangle[0]] + positions[triangle[1]] + positions[triangle[2]]) / 3.0
		for layer: String in ["front", "back"]:
			var sign: float = 1.0 if layer == "front" else -1.0
			var flags: PackedByteArray = yellow[layer]
			var hits: int = int(flags[triangle[0]]) + int(flags[triangle[1]]) + int(flags[triangle[2]])
			if hits == 3 and sign * (centre.z - hip_z) > .025: (faces[layer] as Array).append(triangle)
	var needed: Dictionary = {}
	for layer: String in ["front", "back"]:
		for triangle: PackedInt32Array in faces[layer]:
			for index: int in triangle: needed[index] = true
	for index: int in pants: needed[index] = true
	if support != null:
		for index: int in (support.get("records") as Dictionary): needed[index] = true
	var influences: int = bones.size() / positions.size()
	for index: int in needed:
		var chain: Array[Dictionary] = []
		for influence: int in influences:
			var weight: float = weights[index * influences + influence]
			if weight <= 0: continue
			var bind: int = bones[index * influences + influence]
			var bone: int = mesh.skin.get_bind_bone(bind)
			if bone < 0: bone = sk.find_bone(mesh.skin.get_bind_name(bind))
			chain.append({"bone": bone, "inverse_bind": mesh.skin.get_bind_pose(bind), "weight": weight})
		var deltas: Array[Vector3] = []
		for shape: Array in shapes:
			var vertices: PackedVector3Array = shape[Mesh.ARRAY_VERTEX]
			deltas.append(vertices[index] if relative else vertices[index] - positions[index])
		records[index] = {"position": positions[index], "deltas": deltas, "chain": chain}
	result = {"prepared": true, "pants_vertices": pants.size(), "skinned_vertices": records.size()}

func _process_modification() -> void:
	if mesh == null: return
	var applied_frame: int = Engine.get_process_frames()
	if callback_frame != applied_frame:
		callback_frame = applied_frame
		callbacks_in_frame = 0
	callbacks_in_frame += 1
	var refresh_same_frame: bool = not pending and measured_id == request_id and int(result.get("request_id", -1)) == request_id and int(result.get("applied_frame", -1)) == applied_frame
	if (not pending and not refresh_same_frame) or applied_frame <= request_frame: return
	if expected_clip != "" and animation.current_animation != expected_clip: return
	if expected_time >= 0 and absf(animation.current_animation_position - expected_time) >= .0001: return
	pending = false
	measured_id = request_id
	var sk: Skeleton3D = get_skeleton()
	var transforms: Dictionary = {}
	var posed: Dictionary = {}
	var morph_weights: Dictionary = {}
	var geometry: ArrayMesh = mesh.mesh as ArrayMesh
	for shape: int in geometry.get_blend_shape_count(): morph_weights[geometry.get_blend_shape_name(shape)] = mesh.get_blend_shape_value(shape)
	for index: int in records:
		var record: Dictionary = records[index]
		var rest: Vector3 = record.position
		for shape: int in (record.deltas as Array).size(): rest += (record.deltas[shape] as Vector3) * mesh.get_blend_shape_value(shape)
		var point := Vector3.ZERO
		for influence: Dictionary in record.chain:
			var bone: int = int(influence.bone)
			if not transforms.has(bone): transforms[bone] = sk.get_bone_global_pose(bone)
			var transform: Transform3D = (transforms[bone] as Transform3D) * (influence.inverse_bind as Transform3D)
			point += (transform * rest) * float(influence.weight)
		posed[index] = point
	var layers: Dictionary = {}
	var deepest := 0.0
	var total_covered := 0
	var total_hits := 0
	for layer: String in ["front", "back"]:
		var sign: float = 1.0 if layer == "front" else -1.0
		var triangle_points: PackedVector3Array = []
		for triangle: PackedInt32Array in faces[layer]:
			for index: int in triangle: triangle_points.append(posed[index])
		var tree := TriangleMesh.new()
		tree.create_from_faces(triangle_points)
		var penetration := 0.0
		var intersections := 0
		var covered := 0
		var side_penetration := 0.0
		var side_hits := 0
		var worst := Vector3.ZERO
		var worst_normal := Vector3.ZERO
		var worst_vertex := -1
		var worst_face := -1
		for index: int in pants:
			var point: Vector3 = posed[index]
			var hit: Dictionary = tree.intersect_ray(point + Vector3(0, 0, sign), Vector3(0, 0, -sign))
			if hit.is_empty(): continue
			var depth: float = sign * (point.z - (hit.position as Vector3).z)
			# A naturally open side panel has |nx|~.99 and |nz|<.2. Keep
			# these overlaps as diagnostics rather than demanding a closed skirt.
			if absf((hit.normal as Vector3).z) < .5:
				if depth > .005: side_hits += 1
				side_penetration = maxf(side_penetration, depth)
				continue
			covered += 1
			if depth > .005: intersections += 1
			if depth > penetration:
				penetration = depth
				worst = point
				worst_normal = hit.normal
				worst_vertex = index
				worst_face = int(hit.face_index)
		var diagnostic: Dictionary = {}
		if support != null and worst_vertex >= 0:
			var sparse: PackedInt32Array = support.get("pants")
			diagnostic["pants_anchor_contains_worst"] = sparse.has(worst_vertex)
			var nearest := INF
			var nearest_vertex := -1
			for index: int in sparse:
				var distance: float = worst.distance_to(posed[index])
				if distance < nearest:
					nearest = distance
					nearest_vertex = index
			diagnostic["nearest_pants_anchor"] = nearest_vertex
			diagnostic["nearest_pants_anchor_distance_m"] = nearest
			var actual_triangle: PackedInt32Array = faces[layer][worst_face]
			diagnostic["actual_cloth_triangle_vertices"] = Array(actual_triangle)
			var target_name: String = "Apron_PostIK_Front" if layer == "front" else "Apron_PostIK_Back"
			var target := -1
			for shape: int in geometry.get_blend_shape_count():
				if geometry.get_blend_shape_name(shape) == target_name: target = shape
			var target_values: Array[float] = []
			for index: int in actual_triangle: target_values.append((records[index].deltas[target] as Vector3).z if target >= 0 else 0.0)
			diagnostic["actual_cloth_postik_delta_z"] = target_values
			var cached_faces: Array = (support.get("faces") as Dictionary)[layer]
			var cached_points: PackedVector3Array = []
			for triangle: PackedInt32Array in cached_faces:
				for index: int in triangle: cached_points.append(posed[index])
			var cached_tree := TriangleMesh.new()
			cached_tree.create_from_faces(cached_points)
			var cached_hit: Dictionary = cached_tree.intersect_ray(worst + Vector3(0, 0, sign), Vector3(0, 0, -sign))
			diagnostic["cached_cloth_hits_worst_ray"] = not cached_hit.is_empty()
			if not cached_hit.is_empty():
				diagnostic["cached_cloth_depth_m"] = sign * (worst.z - (cached_hit.position as Vector3).z)
				diagnostic["cached_cloth_normal_z"] = (cached_hit.normal as Vector3).z
		layers[layer] = {"apron_triangles": (faces[layer] as Array).size(), "covered_vertices": covered, "penetrations_over_5mm": intersections, "max_penetration_m": penetration, "side_overlap_over_5mm": side_hits, "side_overlap_m_max": side_penetration, "worst_point": [worst.x, worst.y, worst.z], "worst_normal": [worst_normal.x, worst_normal.y, worst_normal.z], "worst_pants_vertex": worst_vertex, "diagnostic": diagnostic}
		deepest = maxf(deepest, penetration)
		total_covered += covered
		total_hits += intersections
	result = {"prepared": true, "request_id": measured_id, "request_frame": request_frame, "frame": applied_frame, "applied_frame": applied_frame, "callbacks_in_frame": callbacks_in_frame, "clip": animation.current_animation, "clip_time": animation.current_animation_position, "layers": layers, "apron_triangles": (faces.front as Array).size() + (faces.back as Array).size(), "pants_vertices": pants.size(), "skinned_vertices": records.size(), "covered_vertices": total_covered, "penetrations_over_5mm": total_hits, "max_penetration_m": deepest, "morph_weight": mesh.get_blend_shape_value(shape_index), "morph_weights": morph_weights}

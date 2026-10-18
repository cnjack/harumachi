extends RefCounted
## Map audited source descriptors onto actual imported mesh data at startup.
## Source vertex/face IDs are diagnostics only. Every selected native triangle
## must exist in the actual original LOD0 index buffer; unresolved matches fail.

const WEIGHT_ENCODING := "gltf-f32-normalize-slots/unorm16-f32-floor/decode-f32"
const QUANTIZED_WEIGHT_TOLERANCE := .0000001

static func canonical_bone(name: String) -> String:
	return "mixamorig:" + name.trim_prefix("mixamorig_") if name.begins_with("mixamorig_") else name

static func digest_rows(rows: PackedVector3Array) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK: return ""
	context.update(rows.to_byte_array())
	return context.finish().hex_encode()

static func profile_identity(profile: Dictionary) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK: return ""
	# Explicit ordered fields avoid Dictionary insertion/serialization order.
	context.update(var_to_bytes(int(profile.get("version", 0))))
	for field: String in ["character", "source_glb_sha256", "risk_selection_sha256", "geometry_skin_sha256", "local_fields_sha256", "joint_names_sha256"]:
		context.update(var_to_bytes(String(profile.get(field, ""))))
	var policy: Dictionary = profile.get("mask_policy", {})
	context.update(var_to_bytes(String(policy.get("quantity", ""))))
	context.update(var_to_bytes(float(policy.get("minimum_total_displacement_m", -1.0))))
	context.update(var_to_bytes(String((profile.get("mapping", {}) as Dictionary).get("godot_weight_encoding", ""))))
	if profile.has("body_query_policy"):
		var queries: Dictionary = profile.body_query_policy
		context.update(var_to_bytes(int(queries.get("version", 0))))
		context.update(var_to_bytes(String(queries.get("centroids", ""))))
		context.update(var_to_bytes(float(queries.get("edge_rest_min_length_m", -1))))
		context.update(var_to_bytes(String(queries.get("edge_position", ""))))
	for target_name: String in profile.get("morph_target_names", []): context.update(var_to_bytes(target_name))
	for vertex: Dictionary in profile.get("vertices", []):
		context.update(var_to_bytes(int(vertex.get("source_vertex_for_audit", -1))))
		context.update(PackedFloat32Array(vertex.get("position", [])).to_byte_array())
		context.update(PackedFloat32Array(vertex.get("uv", [])).to_byte_array())
		var influences: Dictionary = {}
		for entry: Array in vertex.get("influences", []): influences[canonical_bone(String(entry[0]))] = float(entry[1])
		var names: Array = influences.keys()
		names.sort()
		for bone_name: String in names:
			context.update(var_to_bytes(bone_name))
			context.update(PackedFloat32Array([float(influences[bone_name])]).to_byte_array())
		for entry: Array in vertex.get("godot_unorm16_influences", []):
			context.update(var_to_bytes(canonical_bone(String(entry[0]))))
			context.update(PackedFloat32Array([float(entry[1])]).to_byte_array())
		context.update(var_to_bytes(String(vertex.get("morph_delta_position_sha256", ""))))
		context.update(var_to_bytes(String(vertex.get("morph_absolute_position_sha256", ""))))
	for side: String in ["front", "back"]:
		context.update(var_to_bytes(side))
		var panel: Dictionary = (profile.get("panels", {}) as Dictionary).get(side, {})
		for triangle: Array in panel.get("indices", []): context.update(PackedInt32Array(triangle).to_byte_array())
		context.update(PackedInt32Array(panel.get("source_face_ids_for_audit", [])).to_byte_array())
	return context.finish().hex_encode()

static func map_proxy(mesh: MeshInstance3D, skeleton: Skeleton3D, profile: Dictionary, arrays: Array, shapes: Array, front_mask: PackedByteArray, back_mask: PackedByteArray) -> Dictionary:
	var report: Dictionary = {"valid": false, "reason": "missing risk profile", "mapped_vertices": 0, "native_alias_vertices": 0, "mapped_faces_front": 0, "mapped_faces_back": 0, "maximum_position_error_m": 0.0, "maximum_uv_error": 0.0, "maximum_skin_weight_error": 0.0, "maximum_quantized_skin_weight_error": 0.0, "skin_weight_encoding": WEIGHT_ENCODING, "quantized_weight_tolerance": QUANTIZED_WEIGHT_TOLERANCE, "morph_position_hashes_verified": 0, "faces": {"front": PackedInt32Array(), "back": PackedInt32Array()}}
	if int(profile.get("version", 0)) != 1 or not profile.has("vertices") or not profile.has("panels"): return report
	var mapping_policy: Dictionary = profile.get("mapping", {})
	var position_tolerance: float = float(mapping_policy.get("position_tolerance_m", .00001))
	var uv_tolerance: float = float(mapping_policy.get("uv_tolerance", .00001))
	var weight_tolerance: float = float(mapping_policy.get("weight_tolerance", .000001))
	if position_tolerance <= 0 or position_tolerance > .00001 or uv_tolerance <= 0 or uv_tolerance > .00001 or weight_tolerance <= 0 or weight_tolerance > .000001:
		report["reason"] = "unsupported mapping tolerances"
		return report
	if String(mapping_policy.get("godot_weight_encoding", "")) != WEIGHT_ENCODING:
		report["reason"] = "missing exact Godot UNORM16 source weight signature"
		return report
	if profile.has("body_query_policy"):
		var queries: Dictionary = profile.body_query_policy
		var edge_minimum: float = float(queries.get("edge_rest_min_length_m", -1))
		if int(queries.get("version", 0)) != 1 or String(queries.get("centroids", "")) != "all_physical_body_faces" or String(queries.get("edge_position", "")) != "midpoint_of_final_skinned_corners" or not is_finite(edge_minimum) or edge_minimum <= 0 or edge_minimum > .030:
			report["reason"] = "unsupported risk body query policy"
			return report
	var geometry: ArrayMesh = mesh.mesh as ArrayMesh
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var binds: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var influences: int = binds.size() / points.size()
	var target_indices := PackedInt32Array()
	var named_targets: Dictionary = {}
	for target: int in geometry.get_blend_shape_count(): named_targets[String(geometry.get_blend_shape_name(target))] = target
	for name: String in profile.get("morph_target_names", []):
		if not named_targets.has(name):
			report["reason"] = "risk target missing from actual mesh: " + name
			return report
		target_indices.append(int(named_targets[name]))
	if target_indices.size() != geometry.get_blend_shape_count():
		report["reason"] = "actual morph target count changed"
		return report
	var spatial: Dictionary = {}
	for vertex: int in points.size():
		var point: Vector3 = points[vertex]
		var key := Vector3i(floori(point.x / position_tolerance), floori(point.y / position_tolerance), floori(point.z / position_tolerance))
		var bucket: PackedInt32Array = spatial.get(key, PackedInt32Array())
		bucket.append(vertex)
		spatial[key] = bucket
	var native_to_descriptor: Dictionary = {}
	var descriptor_index := 0
	for descriptor: Dictionary in profile.vertices:
		var position_values: Array = descriptor.position
		var texture_values: Array = descriptor.uv
		var expected_position := Vector3(float(position_values[0]), float(position_values[1]), float(position_values[2]))
		var expected_uv := Vector2(float(texture_values[0]), float(texture_values[1]))
		var expected_weights: Dictionary = {}
		for influence: Array in descriptor.influences: expected_weights[canonical_bone(String(influence[0]))] = float(influence[1])
		var expected_quantized_weights: Dictionary = {}
		for influence: Array in descriptor.get("godot_unorm16_influences", []): expected_quantized_weights[canonical_bone(String(influence[0]))] = float(influence[1])
		if expected_quantized_weights.is_empty():
			report["reason"] = "risk descriptor missing exact Godot UNORM16 weights"
			return report
		var centre := Vector3i(floori(expected_position.x / position_tolerance), floori(expected_position.y / position_tolerance), floori(expected_position.z / position_tolerance))
		var matched := PackedInt32Array()
		var morph_failure := ""
		var nearest_skin_error := INF
		var nearest_quantized_error := INF
		var closest_actual_weights: Dictionary = {}
		var failed_actual_target_rows := PackedVector3Array()
		var failed_native_vertex := -1
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				for dz: int in range(-1, 2):
					var candidates: PackedInt32Array = spatial.get(centre + Vector3i(dx, dy, dz), PackedInt32Array())
					for candidate: int in candidates:
						var position_error: float = points[candidate].distance_to(expected_position)
						var uv_error: float = uvs[candidate].distance_to(expected_uv)
						if position_error > position_tolerance or uv_error > uv_tolerance: continue
						var actual_weights: Dictionary = {}
						for slot: int in influences:
							var amount: float = weights[candidate * influences + slot]
							if amount == 0: continue
							var bind: int = binds[candidate * influences + slot]
							var bone: int = mesh.skin.get_bind_bone(bind)
							var bone_name: String = skeleton.get_bone_name(bone) if bone >= 0 else String(mesh.skin.get_bind_name(bind))
							bone_name = canonical_bone(bone_name)
							actual_weights[bone_name] = float(actual_weights.get(bone_name, 0.0)) + amount
						var skin_error := 0.0
						for name: String in expected_weights: skin_error = maxf(skin_error, absf(float(expected_weights[name]) - float(actual_weights.get(name, 0.0))))
						for name: String in actual_weights: skin_error = maxf(skin_error, absf(float(actual_weights[name]) - float(expected_weights.get(name, 0.0))))
						var quantized_error := 0.0
						for name: String in expected_quantized_weights: quantized_error = maxf(quantized_error, absf(float(expected_quantized_weights[name]) - float(actual_weights.get(name, 0.0))))
						for name: String in actual_weights: quantized_error = maxf(quantized_error, absf(float(actual_weights[name]) - float(expected_quantized_weights.get(name, 0.0))))
						if quantized_error < nearest_quantized_error:
							nearest_quantized_error = quantized_error
							nearest_skin_error = skin_error
							closest_actual_weights = actual_weights
							failed_native_vertex = candidate
						if quantized_error > QUANTIZED_WEIGHT_TOLERANCE: continue
						var target_rows := PackedVector3Array()
						for target: int in target_indices:
							var target_points: PackedVector3Array = shapes[target][Mesh.ARRAY_VERTEX]
							target_rows.append(target_points[candidate])
						var actual_hash: String = digest_rows(target_rows)
						var expected_hash: String = descriptor.morph_delta_position_sha256 if geometry.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE else descriptor.morph_absolute_position_sha256
						if actual_hash != expected_hash:
							morph_failure = "actual=" + actual_hash + " expected=" + expected_hash
							failed_actual_target_rows = target_rows
							continue
						matched.append(candidate)
						report["maximum_position_error_m"] = maxf(float(report.maximum_position_error_m), position_error)
						report["maximum_uv_error"] = maxf(float(report.maximum_uv_error), uv_error)
						report["maximum_skin_weight_error"] = maxf(float(report.maximum_skin_weight_error), skin_error)
						report["maximum_quantized_skin_weight_error"] = maxf(float(report.maximum_quantized_skin_weight_error), quantized_error)
		if matched.is_empty():
			report["reason"] = "no actual vertex matches risk descriptor %d" % descriptor_index
			report["failed_source_vertex_for_audit"] = descriptor.get("source_vertex_for_audit", -1)
			report["closest_skin_weight_error"] = nearest_skin_error if is_finite(nearest_skin_error) else -1.0
			report["closest_quantized_skin_weight_error"] = nearest_quantized_error if is_finite(nearest_quantized_error) else -1.0
			report["failed_native_vertex"] = failed_native_vertex
			report["failed_expected_weights"] = expected_weights
			report["failed_expected_quantized_weights"] = expected_quantized_weights
			report["failed_actual_weights"] = closest_actual_weights
			var failed_rows: Array = []
			for failed_point: Vector3 in failed_actual_target_rows: failed_rows.append([failed_point.x, failed_point.y, failed_point.z])
			report["failed_actual_target_rows"] = failed_rows
			report["actual_blend_shape_mode"] = geometry.blend_shape_mode
			report["morph_hash_failure"] = morph_failure
			return report
		for candidate: int in matched:
			if native_to_descriptor.has(candidate) and int(native_to_descriptor[candidate]) != descriptor_index:
				report["reason"] = "ambiguous non-equivalent source vertex descriptors"
				return report
			native_to_descriptor[candidate] = descriptor_index
		report["mapped_vertices"] = int(report.mapped_vertices) + 1
		report["native_alias_vertices"] = int(report.native_alias_vertices) + matched.size() - 1
		report["morph_position_hashes_verified"] = int(report.morph_position_hashes_verified) + matched.size()
		descriptor_index += 1
	var original_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var original_faces: Dictionary = {}
	for offset: int in range(0, original_indices.size(), 3):
		var triangle := PackedInt32Array([original_indices[offset], original_indices[offset + 1], original_indices[offset + 2]])
		if not native_to_descriptor.has(triangle[0]) or not native_to_descriptor.has(triangle[1]) or not native_to_descriptor.has(triangle[2]): continue
		var key := PackedInt32Array([native_to_descriptor[triangle[0]], native_to_descriptor[triangle[1]], native_to_descriptor[triangle[2]]])
		key.sort()
		if not original_faces.has(key): original_faces[key] = triangle
	for side: String in ["front", "back"]:
		var panel: Dictionary = (profile.panels as Dictionary).get(side, {})
		var mask: PackedByteArray = front_mask if side == "front" else back_mask
		var selected := PackedInt32Array()
		for source_triangle: Array in panel.get("indices", []):
			if source_triangle.size() != 3:
				report["reason"] = "risk face does not have three source vertices"
				return report
			var key := PackedInt32Array(source_triangle)
			key.sort()
			if not original_faces.has(key):
				report["reason"] = "risk source triangle is absent from actual original LOD0"
				return report
			var triangle: PackedInt32Array = original_faces[key]
			for vertex: int in triangle:
				if mask[vertex] == 0:
					report["reason"] = "risk source triangle is outside stable per-side Local support"
					return report
			selected.append_array(triangle)
		(report.faces as Dictionary)[side] = selected
		report["mapped_faces_" + side] = selected.size() / 3
	report["valid"] = true
	report["reason"] = "actual position, UV, exact UNORM16 named skin, all target positions and original LOD0 topology verified"
	return report

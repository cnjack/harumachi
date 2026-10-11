extends RefCounted
## Preserve imported streams exactly; only append two independently encoded targets.
const FRONT := "Apron_PostIK_Front"
const BACK := "Apron_PostIK_Back"
static var cache: Dictionary = {}


static func clear_cache() -> void:
	cache.clear()


static func duplicate_with_targets(original: ArrayMesh, front_delta: PackedVector3Array, back_delta: PackedVector3Array) -> ArrayMesh:
	var surfaces: Array = (original.get("_surfaces") as Array).duplicate(true)
	var copy := ArrayMesh.new()
	copy.blend_shape_mode = original.blend_shape_mode
	for index: int in original.get_blend_shape_count(): copy.add_blend_shape(original.get_blend_shape_name(index))
	copy.add_blend_shape(FRONT)
	copy.add_blend_shape(BACK)
	for surface: int in surfaces.size():
		var arrays: Array = original.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if surface == 0 and (positions.size() != front_delta.size() or positions.size() != back_delta.size()): return null
		var targets: Array[Array] = []
		for side: int in 2:
			var target: Array = []
			target.resize(Mesh.ARRAY_MAX)
			var target_vertices := PackedVector3Array()
			target_vertices.resize(positions.size())
			for vertex: int in positions.size():
				var delta: Vector3 = Vector3.ZERO if surface != 0 else front_delta[vertex] if side == 0 else back_delta[vertex]
				target_vertices[vertex] = delta if original.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE else positions[vertex] + delta
			target[Mesh.ARRAY_VERTEX] = target_vertices
			# Normalized targets keep the source directions. Relative targets must
			# supply zero increments, rather than adding those directions again.
			if original.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE:
				if arrays[Mesh.ARRAY_NORMAL] != null:
					var normal_delta := PackedVector3Array()
					normal_delta.resize(positions.size())
					target[Mesh.ARRAY_NORMAL] = normal_delta
				if arrays[Mesh.ARRAY_TANGENT] != null:
					var tangent_delta := PackedFloat32Array()
					tangent_delta.resize(positions.size() * 4)
					target[Mesh.ARRAY_TANGENT] = tangent_delta
			else:
				target[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
				target[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
			targets.append(target)
		var encoder := ArrayMesh.new()
		encoder.blend_shape_mode = original.blend_shape_mode
		encoder.add_blend_shape(FRONT)
		encoder.add_blend_shape(BACK)
		encoder.add_surface_from_arrays(original.surface_get_primitive_type(surface), arrays, targets, {}, original.surface_get_format(surface))
		if encoder.get_surface_count() != 1: return null
		var encoded: Dictionary = (encoder.get("_surfaces") as Array)[0]
		if int(encoded.format) != int(surfaces[surface].format): return null
		var extra: PackedByteArray = encoded.get("blend_shapes", PackedByteArray())
		var prefix: PackedByteArray = surfaces[surface].get("blend_shapes", PackedByteArray())
		if extra.is_empty() or extra.size() % 2 != 0: return null
		if original.get_blend_shape_count() > 0 and extra.size() / 2 != prefix.size() / original.get_blend_shape_count(): return null
		prefix.append_array(extra)
		surfaces[surface]["blend_shapes"] = prefix
	# ArrayMesh's serialized wrapper uses blend_shapes, while RenderingServer's
	# public SurfaceData dictionary calls the same byte stream blend_shape_data.
	copy.set("_surfaces", surfaces)
	if copy.get_surface_count() != original.get_surface_count(): return null
	copy.custom_aabb = original.get_aabb().grow(.2)
	copy.lightmap_size_hint = original.lightmap_size_hint
	return copy


static func build(original: ArrayMesh) -> Dictionary:
	if original == null or original.get_surface_count() == 0: return {}
	var key: int = original.get_instance_id()
	if cache.has(key): return cache[key]
	var arrays: Array = original.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var material: BaseMaterial3D = original.surface_get_material(0) as BaseMaterial3D
	if material == null or material.albedo_texture == null or normals.size() != positions.size() or uv.size() != positions.size(): return {}
	var atlas: Image = material.albedo_texture.get_image()
	if atlas == null: return {}
	if atlas.is_compressed() and atlas.decompress() != OK: return {}
	var height := 0.0
	for point: Vector3 in positions: height = maxf(height, point.y)
	var triangle_points := PackedVector3Array()
	for index: int in indices: triangle_points.append(positions[index])
	var tree := TriangleMesh.new()
	tree.create_from_faces(triangle_points)
	var adjacency: Array[PackedInt32Array] = []
	adjacency.resize(positions.size())
	for offset: int in range(0, indices.size(), 3):
		for corner: int in 3:
			var index: int = indices[offset + corner]
			adjacency[index].append(indices[offset + (corner + 1) % 3])
			adjacency[index].append(indices[offset + (corner + 2) % 3])
	var colours: Array[Color] = []
	for vertex: int in positions.size():
		colours.append(atlas.get_pixel(posmod(int(uv[vertex].x * atlas.get_width()), atlas.get_width()), posmod(int(uv[vertex].y * atlas.get_height()), atlas.get_height())))
	var split_z: float = panel_split(positions, normals, colours, tree, height, original.get_aabb().get_center().z)
	var front: Dictionary = select_layer(positions, normals, indices, colours, adjacency, tree, height, 1.0, split_z)
	var back: Dictionary = select_layer(positions, normals, indices, colours, adjacency, tree, height, -1.0, split_z)
	if (front.faces as Array).is_empty() or (back.faces as Array).is_empty(): return {}
	var front_delta: PackedVector3Array = front.delta
	var back_delta: PackedVector3Array = back.delta
	var clone: ArrayMesh = duplicate_with_targets(original, front_delta, back_delta)
	if clone == null: return {}
	var proxies: Dictionary = runtime_proxies(original, positions, normals, front_delta, back_delta, height, split_z)
	var metadata: Dictionary = {"selection_surface": 0, "source_mesh": original.resource_path,
		"front_vertices": front.vertices, "back_vertices": back.vertices, "front_triangles": (front.faces as Array).size(), "back_triangles": (back.faces as Array).size(),
		"front_seeds": front.seeds, "back_seeds": back.seeds, "original_shape_count": original.get_blend_shape_count(),
		"blend_shape_mode": original.blend_shape_mode, "target_amplitude_m": .12, "transition_m": .016,
		"normal_encoding": "zero_increment" if original.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE else "original_direction",
		"source_streams_repacked": false, "raw_surface_aabb_changed": false, "natural_side_openings_retained": true,
		"lower_fold_vertices_front": front.fold_vertices, "lower_fold_vertices_back": back.fold_vertices,
		"source_panel_split_z": split_z,
		"runtime_lod_candidates": proxies.candidates, "runtime_lod_selected": proxies.selected}
	var data: Dictionary = {"mesh": clone, "original_mesh": original, "original_shape_count": original.get_blend_shape_count(),
		"original_shapes": original.surface_get_blend_shape_arrays(0), "front_delta": front_delta, "back_delta": back_delta,
		"front_faces": front.faces, "back_faces": back.faces,
		"runtime_front_faces": proxies.front_faces, "runtime_back_faces": proxies.back_faces, "metadata": metadata}
	cache[key] = data
	return data


static func select_layer(positions: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, colours: Array[Color], adjacency: Array[PackedInt32Array], tree: TriangleMesh, height: float, sign_z: float, split_z: float) -> Dictionary:
	var eligible := PackedByteArray()
	eligible.resize(positions.size())
	var mask := PackedFloat32Array()
	mask.resize(positions.size())
	var seeds := 0
	for vertex: int in positions.size():
		var point: Vector3 = positions[vertex]
		var normal_z: float = normals[vertex].z * sign_z
		var colour: Color = colours[vertex]
		var fold: bool = lower_fold(point, normals[vertex], height, sign_z, split_z)
		if absf(point.x) > .23 * height or point.y < .20 * height or point.y > .57 * height or (normal_z < .25 and not fold): continue
		# Dark trousers cannot enter the transition band, even where they are
		# connected to the apron in the source's single welded body mesh.
		if maxf(colour.r, maxf(colour.g, colour.b)) < .36: continue
		var first: Dictionary = tree.intersect_ray(Vector3(point.x, point.y, 2 * sign_z), Vector3(0, 0, -sign_z))
		# A missed outward face can yield a later hit behind this vertex. Only a
		# genuinely closer layer occludes it; a rear hit is not an occluder.
		if first.is_empty() or sign_z * ((first.position as Vector3).z - point.z) > .012: continue
		eligible[vertex] = 1
		var yellow: bool = colour.r > colour.g * .95 and colour.r < colour.g * 1.9 and colour.b < colour.g * .65 and colour.g > .18
		if yellow and (normal_z >= .5 or fold):
			mask[vertex] = 1.0
			seeds += 1
	# At most16mm of connected pale hem/waist texels fade from the yellow seeds.
	# Source side normals near +/-X remain zero, preserving the natural slit.
	for iteration: int in 6:
		var next: PackedFloat32Array = mask.duplicate()
		for vertex: int in positions.size():
			if eligible[vertex] == 0 or mask[vertex] >= 1.0: continue
			for neighbour: int in adjacency[vertex]:
				var weight: float = mask[neighbour] - positions[vertex].distance_to(positions[neighbour]) / .016
				next[vertex] = maxf(next[vertex], weight)
		mask = next
	var delta := PackedVector3Array()
	delta.resize(positions.size())
	var vertices := 0
	var fold_vertices := 0
	for vertex: int in positions.size():
		if eligible[vertex] == 0 or mask[vertex] <= 0: continue
		var waist_fade: float = 1.0 - smoothstep(.40 * height, .57 * height, positions[vertex].y)
		var side_fade: float = smoothstep(.25, .75, normals[vertex].z * sign_z)
		if lower_fold(positions[vertex], normals[vertex], height, sign_z, split_z):
			# Underturned hems face down in rest, but turn toward the viewer after
			# leg IK. Their small +/-Z normal must not be mistaken for a side slit.
			side_fade = maxf(side_fade, smoothstep(.60, .85, -normals[vertex].y))
		var weight: float = smoothstep(0.0, 1.0, mask[vertex]) * waist_fade * side_fade
		if weight <= .00001: continue
		delta[vertex] = Vector3(0, 0, sign_z * .12 * weight)
		vertices += 1
		if lower_fold(positions[vertex], normals[vertex], height, sign_z, split_z): fold_vertices += 1
	var faces: Array[PackedInt32Array] = target_faces(positions, normals, indices, delta, height, sign_z, split_z)
	return {"delta": delta, "faces": faces, "vertices": vertices, "seeds": seeds, "fold_vertices": fold_vertices}


static func lower_fold(point: Vector3, normal: Vector3, height: float, sign_z: float, split_z: float) -> bool:
	# The folded underside can reverse its Z normal. Actual front/back position
	# separates the two panels, while +/-X openings and dark pants stay excluded.
	return point.y < .36 * height and normal.y < -.60 and absf(normal.x) < .50 and (point.z - split_z) * sign_z > .01


static func target_faces(positions: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, delta: PackedVector3Array, height: float, sign_z: float, split_z: float) -> Array[PackedInt32Array]:
	var faces: Array[PackedInt32Array] = []
	for offset: int in range(0, indices.size(), 3):
		var triangle := PackedInt32Array([indices[offset], indices[offset + 1], indices[offset + 2]])
		if delta[triangle[0]].length_squared() == 0 or delta[triangle[1]].length_squared() == 0 or delta[triangle[2]].length_squared() == 0: continue
		var average_normal_z: float = (normals[triangle[0]].z + normals[triangle[1]].z + normals[triangle[2]].z) * sign_z / 3.0
		var folded: bool = lower_fold(positions[triangle[0]], normals[triangle[0]], height, sign_z, split_z) or lower_fold(positions[triangle[1]], normals[triangle[1]], height, sign_z, split_z) or lower_fold(positions[triangle[2]], normals[triangle[2]], height, sign_z, split_z)
		if average_normal_z >= .5 or folded: faces.append(triangle)
	return faces


static func runtime_proxies(original: ArrayMesh, positions: PackedVector3Array, normals: PackedVector3Array, front_delta: PackedVector3Array, back_delta: PackedVector3Array, height: float, split_z: float) -> Dictionary:
	var raw: Dictionary = (original.get("_surfaces") as Array)[0]
	var levels: Array[Dictionary] = [{"level": -1, "edge_length": 0.0, "indices": original.surface_get_arrays(0)[Mesh.ARRAY_INDEX]}]
	var lods: Array = raw.get("lods", [])
	var index_bytes: int = 2 if positions.size() <= 65536 else 4
	for offset: int in range(0, lods.size(), 2):
		var blob: PackedByteArray = lods[offset + 1]
		var decoded := PackedInt32Array()
		decoded.resize(blob.size() / index_bytes)
		for index: int in decoded.size(): decoded[index] = blob.decode_u16(index * index_bytes) if index_bytes == 2 else blob.decode_u32(index * index_bytes)
		levels.append({"level": offset / 2, "edge_length": float(lods[offset]), "indices": decoded})
	var candidates: Array[Dictionary] = []
	var selected: Dictionary = {}
	var selected_front: Array[PackedInt32Array] = []
	var selected_back: Array[PackedInt32Array] = []
	var best := INF
	for level: Dictionary in levels:
		var front_faces: Array[PackedInt32Array] = target_faces(positions, normals, level.indices, front_delta, height, 1.0, split_z)
		var back_faces: Array[PackedInt32Array] = target_faces(positions, normals, level.indices, back_delta, height, -1.0, split_z)
		var anchors: Dictionary = {}
		for triangle: PackedInt32Array in front_faces:
			for vertex: int in triangle: anchors[vertex] = true
		for triangle: PackedInt32Array in back_faces:
			for vertex: int in triangle: anchors[vertex] = true
		var total: int = front_faces.size() + back_faces.size()
		var counts: Dictionary = {"level": level.level, "edge_length": level.edge_length, "front_triangles": front_faces.size(), "back_triangles": back_faces.size(), "cloth_anchors": anchors.size(), "total_triangles": total}
		candidates.append(counts)
		# Keep meaningful detail rather than blindly choosing the coarsest LOD.
		# Accuracy remains subject to the independent full-mesh 5mm regression.
		var score: float = absf(float(total) - 1600.0) if total >= 1200 and front_faces.size() >= 250 and back_faces.size() >= 250 else INF
		if selected.is_empty() or score < best:
			best = score
			selected = counts
			selected_front = front_faces
			selected_back = back_faces
	return {"front_faces": selected_front, "back_faces": selected_back, "selected": selected, "candidates": candidates}


static func panel_split(positions: PackedVector3Array, normals: PackedVector3Array, colours: Array[Color], tree: TriangleMesh, height: float, fallback: float) -> float:
	var front: Array[float] = []
	var back: Array[float] = []
	for vertex: int in positions.size():
		var point: Vector3 = positions[vertex]
		var colour: Color = colours[vertex]
		if absf(point.x) > .14 * height or point.y < .20 * height or point.y > .40 * height or absf(normals[vertex].z) < .5: continue
		if not (colour.r > colour.g * .95 and colour.r < colour.g * 1.9 and colour.b < colour.g * .65 and colour.g > .18): continue
		var sign_z: float = 1.0 if normals[vertex].z > 0 else -1.0
		var first: Dictionary = tree.intersect_ray(Vector3(point.x, point.y, sign_z * 2), Vector3(0, 0, -sign_z))
		if first.is_empty() or absf((first.position as Vector3).z - point.z) > .012: continue
		if sign_z > 0: front.append(point.z)
		else: back.append(point.z)
	if front.is_empty() or back.is_empty(): return fallback
	front.sort()
	back.sort()
	return (front[front.size() / 2] + back[back.size() / 2]) * .5

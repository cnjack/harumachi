extends SkeletonModifier3D
## Cached front/back cloth anchors resolve only real panel penetration after leg IK.
var mesh: MeshInstance3D
var original_shape_count := 0
var front_index := -1
var back_index := -1
var applied := Vector2.ZERO
var enabled := true
var faces: Dictionary = {"front": [], "back": []}
var pants: PackedInt32Array = []
var records: Dictionary = {}
var updates := 0
var total_usec := 0
var max_usec := 0
var source_pants_anchors := 0
var total_skin_usec := 0
var total_build_usec := 0
var total_ray_usec := 0
var max_skin_usec := 0
var max_build_usec := 0
var max_ray_usec := 0
var total_ray_queries := 0
var total_broadphase_skips := 0
var dense_positions: PackedVector3Array = []
var dense_original_deltas: Array[PackedVector3Array] = []
var dense_front_delta: PackedVector3Array = []
var dense_back_delta: PackedVector3Array = []
var dense_flags: PackedByteArray = []
var dense_offsets: PackedInt32Array = []
var dense_slots: PackedInt32Array = []
var dense_weights: PackedFloat32Array = []
var dense_bones: PackedInt32Array = []
var dense_inverse_bind: Array[Transform3D] = []
var dense_moving: PackedInt32Array = []
var dense_pants: PackedInt32Array = []
var dense_faces: Dictionary = {"front": PackedInt32Array(), "back": PackedInt32Array()}
var dense_layer_vertices: Dictionary = {"front": PackedInt32Array(), "back": PackedInt32Array()}

static func attach(model: Node3D, _player: AnimationPlayer) -> SkeletonModifier3D:
	var sk: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
	var rig: Node = model.find_child("Rig", true, false)
	if sk == null or rig == null or not rig.has_meta("extras"): return null
	var extras: Dictionary = rig.get_meta("extras")
	if extras.get("character_id", "") != "kazuko": return null
	var support: SkeletonModifier3D = load("res://scripts/characters/character_apron_support.gd").new()
	support.name = "CharacterApronSupport"
	sk.add_child(support)
	support.call("prepare", model)
	return support

func performance() -> Dictionary:
	return {"updates": updates, "mean_usec": float(total_usec) / maxi(updates, 1), "max_usec": max_usec,
		"skin_mean_usec": float(total_skin_usec) / maxi(updates, 1), "build_mean_usec": float(total_build_usec) / maxi(updates, 1), "ray_mean_usec": float(total_ray_usec) / maxi(updates, 1),
		"skin_max_usec": max_skin_usec, "build_max_usec": max_build_usec, "ray_max_usec": max_ray_usec,
		"ray_queries_mean": float(total_ray_queries) / maxi(updates, 1), "broadphase_skips_mean": float(total_broadphase_skips) / maxi(updates, 1),
		"source_pants_anchors": source_pants_anchors, "pants_anchors": pants.size(), "garment_triangles_front": (faces.front as Array).size(), "garment_triangles_back": (faces.back as Array).size(), "skinned_anchors": records.size(), "applied_front": applied.x, "applied_back": applied.y}

func reset_performance() -> void:
	updates = 0
	total_usec = 0
	max_usec = 0
	total_skin_usec = 0
	total_build_usec = 0
	total_ray_usec = 0
	max_skin_usec = 0
	max_build_usec = 0
	max_ray_usec = 0
	total_ray_queries = 0
	total_broadphase_skips = 0

func prepare(model: Node3D) -> void:
	var sk: Skeleton3D = get_skeleton()
	for candidate: MeshInstance3D in WorldBuilder.find_meshes(model):
		var candidate_geometry: ArrayMesh = candidate.mesh as ArrayMesh
		if candidate_geometry == null or candidate.skin == null: continue
		for index: int in candidate_geometry.get_blend_shape_count():
			if candidate_geometry.get_blend_shape_name(index) == "Apron_Clearance": mesh = candidate
		if mesh != null: break
	if mesh == null: return
	var original: ArrayMesh = mesh.mesh as ArrayMesh
	original_shape_count = original.get_blend_shape_count()
	var original_values: PackedFloat32Array = []
	for index: int in original_shape_count: original_values.append(mesh.get_blend_shape_value(index))
	var built: Dictionary = load("res://scripts/characters/character_apron_mesh.gd").build(original)
	if built.is_empty(): return
	mesh.set_meta("apron_original_mesh", original)
	mesh.mesh = built.mesh
	for index: int in original_shape_count: mesh.set_blend_shape_value(index, original_values[index])
	front_index = original_shape_count
	back_index = original_shape_count + 1
	var arrays: Array = original.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var source_shapes: Array = original.surface_get_blend_shape_arrays(0)
	var front_delta: PackedVector3Array = built.front_delta
	var back_delta: PackedVector3Array = built.back_delta
	var relative: bool = original.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	var material: BaseMaterial3D = mesh.get_active_material(0) as BaseMaterial3D
	var atlas: Image = material.albedo_texture.get_image()
	if atlas.is_compressed(): atlas.decompress()
	var height := 0.0
	for point: Vector3 in positions: height = maxf(height, point.y)
	var influences: int = bones.size() / positions.size()
	var chosen: Dictionary = {}
	var signatures: Dictionary = {}
	for index: int in positions.size():
		var point: Vector3 = positions[index]
		if absf(point.x) > .14 * height or point.y < .24 * height or point.y > .55 * height: continue
		var colour: Color = atlas.get_pixel(posmod(int(uv[index].x * atlas.get_width()), atlas.get_width()), posmod(int(uv[index].y * atlas.get_height()), atlas.get_height()))
		if maxf(colour.r, maxf(colour.g, colour.b)) >= .36: continue
		source_pants_anchors += 1
		# Split UV/normal vertices can share the exact same animated point.
		# Equality includes every bind, weight and original morph increment;
		# no spatial quantization or approximate extrema remove coverage.
		var signature: PackedByteArray = PackedVector3Array([point]).to_byte_array()
		signature.append_array(bones.slice(index * influences, (index + 1) * influences).to_byte_array())
		signature.append_array(weights.slice(index * influences, (index + 1) * influences).to_byte_array())
		for shape: Array in source_shapes:
			var shape_vertices: PackedVector3Array = shape[Mesh.ARRAY_VERTEX]
			var delta: Vector3 = shape_vertices[index] if relative else shape_vertices[index] - point
			signature.append_array(PackedVector3Array([delta]).to_byte_array())
		signature.append_array(PackedVector3Array([front_delta[index], back_delta[index]]).to_byte_array())
		if signatures.has(signature): continue
		signatures[signature] = index
		chosen[index] = true
	for index: int in chosen: pants.append(index)
	for layer: String in ["front", "back"]:
		# Existing imported LOD triangles form continuous panels; isolated
		# rest-space ray hits left holes when a bent leg moved across the panel.
		faces[layer] = built.get("runtime_" + layer + "_faces", built[layer + "_faces"])
	var needed: Dictionary = chosen.duplicate()
	for layer: String in ["front", "back"]:
		for triangle: PackedInt32Array in faces[layer]:
			for index: int in triangle: needed[index] = true
	for index: int in needed:
		var chain: Array[Dictionary] = []
		for influence: int in influences:
			var weight: float = weights[index * influences + influence]
			if weight <= 0: continue
			var bind: int = bones[index * influences + influence]
			var bone: int = mesh.skin.get_bind_bone(bind)
			if bone < 0: bone = sk.find_bone(mesh.skin.get_bind_name(bind))
			chain.append({"bind": bind, "bone": bone, "inverse_bind": mesh.skin.get_bind_pose(bind), "weight": weight})
		var deltas: Array[Vector3] = []
		for shape: Array in source_shapes:
			var vertices: PackedVector3Array = shape[Mesh.ARRAY_VERTEX]
			deltas.append(vertices[index] if relative else vertices[index] - positions[index])
		records[index] = {"position": positions[index], "original_deltas": deltas, "front_delta": front_delta[index], "back_delta": back_delta[index], "front_moves": front_delta[index].length_squared() > 0, "back_moves": back_delta[index].length_squared() > 0, "chain": chain}
	prepare_dense()

func prepare_dense() -> void:
	# Keep source IDs/records for diagnostics, but never hash them in the frame loop.
	var lookup: Dictionary = {}
	var bind_slots: Dictionary = {}
	var source_ids: Array = records.keys()
	for source: int in source_ids:
		var index: int = dense_positions.size()
		lookup[source] = index
		var record: Dictionary = records[source]
		dense_positions.append(record.position)
		dense_front_delta.append(record.front_delta)
		dense_back_delta.append(record.back_delta)
		var flags: int = (1 if record.front_moves else 0) | (2 if record.back_moves else 0)
		dense_flags.append(flags)
		if flags != 0: dense_moving.append(index)
		dense_offsets.append(dense_weights.size())
		for influence: Dictionary in record.chain:
			var bind: int = int(influence.bind)
			if not bind_slots.has(bind):
				bind_slots[bind] = dense_bones.size()
				dense_bones.append(influence.bone)
				dense_inverse_bind.append(influence.inverse_bind)
			dense_slots.append(bind_slots[bind])
			dense_weights.append(influence.weight)
	dense_offsets.append(dense_weights.size())
	for shape: int in original_shape_count:
		var deltas: PackedVector3Array = []
		for source: int in source_ids: deltas.append(records[source].original_deltas[shape])
		dense_original_deltas.append(deltas)
	for source: int in pants: dense_pants.append(lookup[source])
	for layer: String in ["front", "back"]:
		var triangles: PackedInt32Array = []
		var vertices: PackedInt32Array = []
		var visited: Dictionary = {}
		for triangle: PackedInt32Array in faces[layer]:
			for source: int in triangle:
				var index: int = lookup[source]
				triangles.append(index)
				if not visited.has(index):
					visited[index] = true
					vertices.append(index)
		dense_faces[layer] = triangles
		dense_layer_vertices[layer] = vertices

func _process_modification() -> void:
	if mesh == null or front_index < 0 or not mesh.is_visible_in_tree(): return
	var began: int = Time.get_ticks_usec()
	var skin_usec := 0
	var build_usec := 0
	var ray_usec := 0
	var ray_queries := 0
	var broadphase_skips := 0
	applied = Vector2.ZERO
	if enabled:
		var skin_began: int = Time.get_ticks_usec()
		var sk: Skeleton3D = get_skeleton()
		var matrices: Array[Transform3D] = []
		for slot: int in dense_bones.size(): matrices.append(sk.get_bone_global_pose(dense_bones[slot]) * dense_inverse_bind[slot])
		var base := PackedVector3Array()
		var front := PackedVector3Array()
		var back := PackedVector3Array()
		base.resize(dense_positions.size())
		front.resize(dense_positions.size())
		back.resize(dense_positions.size())
		var original_values: PackedFloat32Array = []
		for shape: int in original_shape_count: original_values.append(mesh.get_blend_shape_value(shape))
		for index: int in dense_positions.size():
			var rest: Vector3 = dense_positions[index]
			for shape: int in original_shape_count:
				if original_values[shape] != 0: rest += dense_original_deltas[shape][index] * original_values[shape]
			var point := Vector3.ZERO
			var front_displacement := Vector3.ZERO
			var back_displacement := Vector3.ZERO
			var front_rest: Vector3 = dense_front_delta[index]
			var back_rest: Vector3 = dense_back_delta[index]
			var flags: int = dense_flags[index]
			for influence: int in range(dense_offsets[index], dense_offsets[index + 1]):
				var transform: Transform3D = matrices[dense_slots[influence]]
				var weight: float = dense_weights[influence]
				point += (transform * rest) * weight
				if flags & 1: front_displacement += (transform.basis * front_rest) * weight
				if flags & 2: back_displacement += (transform.basis * back_rest) * weight
			base[index] = point
			front[index] = front_displacement
			back[index] = back_displacement
		skin_usec += Time.get_ticks_usec() - skin_began
		var posed: PackedVector3Array = base.duplicate()
		for iteration: int in range(3):
			var pose_began: int = Time.get_ticks_usec()
			# The full trousers region has zero post-IK increments; only cloth moves.
			for index: int in dense_moving: posed[index] = base[index] + front[index] * applied.x + back[index] * applied.y
			skin_usec += Time.get_ticks_usec() - pose_began
			var increase := Vector2.ZERO
			for layer: String in ["front", "back"]:
				var triangles: PackedInt32Array = dense_faces[layer]
				if triangles.is_empty(): continue
				var sign: float = 1.0 if layer == "front" else -1.0
				var deltas: PackedVector3Array = front if layer == "front" else back
				var build_began: int = Time.get_ticks_usec()
				var lower := Vector3(INF, INF, INF)
				var upper := Vector3(-INF, -INF, -INF)
				var vertices: PackedInt32Array = dense_layer_vertices[layer]
				for index: int in vertices:
					var cloth_point: Vector3 = posed[index]
					lower = lower.min(cloth_point)
					upper = upper.max(cloth_point)
				# Within each 4cm XY cell, every triangle hit has signed Z at
				# least its lowest signed vertex Z. Bounds cover whole triangle
				# rectangles and retain a micrometre at cell boundaries.
				var columns: int = maxi(1, ceili((upper.x - lower.x) * 25.0) + 1)
				var rows: int = maxi(1, ceili((upper.y - lower.y) * 25.0) + 1)
				var depth_bounds := PackedFloat32Array()
				depth_bounds.resize(columns * rows)
				depth_bounds.fill(INF)
				for offset: int in range(0, triangles.size(), 3):
					var a: Vector3 = posed[triangles[offset]]
					var b: Vector3 = posed[triangles[offset + 1]]
					var c: Vector3 = posed[triangles[offset + 2]]
					var triangle_lower: Vector3 = a.min(b).min(c)
					var triangle_upper: Vector3 = a.max(b).max(c)
					var signed_lower: float = minf(a.z * sign, minf(b.z * sign, c.z * sign))
					var first_x: int = clampi(floori((triangle_lower.x - lower.x - .000001) * 25.0), 0, columns - 1)
					var last_x: int = clampi(floori((triangle_upper.x - lower.x + .000001) * 25.0), 0, columns - 1)
					var first_y: int = clampi(floori((triangle_lower.y - lower.y - .000001) * 25.0), 0, rows - 1)
					var last_y: int = clampi(floori((triangle_upper.y - lower.y + .000001) * 25.0), 0, rows - 1)
					for cell_y: int in range(first_y, last_y + 1):
						for cell_x: int in range(first_x, last_x + 1):
							var cell: int = cell_y * columns + cell_x
							depth_bounds[cell] = minf(depth_bounds[cell], signed_lower)
				build_usec += Time.get_ticks_usec() - build_began
				var tree: TriangleMesh
				var ray_began: int = Time.get_ticks_usec()
				for index: int in dense_pants:
					var point: Vector3 = posed[index]
					# Every cloth hit lies inside these bounds. A micrometre guard
					# retains boundary hits; skipped Z ranges cannot exceed the
					# existing 1mm activation depth for either panel.
					if point.x < lower.x - .000001 or point.x > upper.x + .000001 or point.y < lower.y - .000001 or point.y > upper.y + .000001 or (sign > 0 and point.z <= lower.z + .000999) or (sign < 0 and point.z >= upper.z - .000999):
						broadphase_skips += 1
						continue
					var cell_x: int = clampi(floori((point.x - lower.x) * 25.0), 0, columns - 1)
					var cell_y: int = clampi(floori((point.y - lower.y) * 25.0), 0, rows - 1)
					if point.z * sign <= depth_bounds[cell_y * columns + cell_x] + .000999:
						broadphase_skips += 1
						continue
					if tree == null:
						var tree_began: int = Time.get_ticks_usec()
						var points: PackedVector3Array = []
						for vertex: int in triangles: points.append(posed[vertex])
						tree = TriangleMesh.new()
						tree.create_from_faces(points)
						var construction_usec: int = Time.get_ticks_usec() - tree_began
						build_usec += construction_usec
						ray_began += construction_usec
					ray_queries += 1
					var hit: Dictionary = tree.intersect_ray(point + Vector3(0, 0, sign), Vector3(0, 0, -sign))
					if hit.is_empty() or absf((hit.normal as Vector3).z) < .5: continue
					var depth: float = sign * (point.z - (hit.position as Vector3).z)
					if depth <= .001: continue
					var triangle: int = int(hit.face_index) * 3
					var ai: int = triangles[triangle]
					var bi: int = triangles[triangle + 1]
					var ci: int = triangles[triangle + 2]
					var a: Vector3 = posed[ai]
					var b: Vector3 = posed[bi]
					var c: Vector3 = posed[ci]
					var first := Vector2(b.x - a.x, b.y - a.y)
					var second := Vector2(c.x - a.x, c.y - a.y)
					var at := Vector2(point.x - a.x, point.y - a.y)
					var determinant: float = first.cross(second)
					if absf(determinant) < .00000001: continue
					var u: float = at.cross(second) / determinant
					var v: float = first.cross(at) / determinant
					var cloth_delta: Vector3 = deltas[ai] * (1 - u - v) + deltas[bi] * u + deltas[ci] * v
					var slope: float = sign * (cloth_delta.z - deltas[index].z)
					if slope <= .003: continue
					var required: float = (depth + .010) / slope
					if layer == "front": increase.x = maxf(increase.x, required)
					else: increase.y = maxf(increase.y, required)
				ray_usec += Time.get_ticks_usec() - ray_began
			if maxf(increase.x, increase.y) < .0001: break
			applied = Vector2(minf(1.5, applied.x + increase.x), minf(1.5, applied.y + increase.y))
	mesh.set_blend_shape_value(front_index, applied.x)
	mesh.set_blend_shape_value(back_index, applied.y)
	var elapsed: int = Time.get_ticks_usec() - began
	updates += 1
	total_usec += elapsed
	max_usec = maxi(max_usec, elapsed)
	total_skin_usec += skin_usec
	total_build_usec += build_usec
	total_ray_usec += ray_usec
	max_skin_usec = maxi(max_skin_usec, skin_usec)
	max_build_usec = maxi(max_build_usec, build_usec)
	max_ray_usec = maxi(max_ray_usec, ray_usec)
	total_ray_queries += ray_queries
	total_broadphase_skips += broadphase_skips

func _exit_tree() -> void:
	load("res://scripts/characters/character_apron_mesh.gd").clear_cache()

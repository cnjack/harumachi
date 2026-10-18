extends RefCounted
## Startup-only semantic correction for isolated warm atlas texels on Ren's
## white apron ties. The independent painted panel, complete physical UV fan,
## source topology and Local support must all agree; true body faces stay intact.
## Shared by production contact anchors and independent QA body witnesses.

static func ren_pigment_flags(points: PackedVector3Array, colours: Array[Color], height: float, hip_z: float) -> Dictionary:
	var flags: Dictionary = {"front": PackedByteArray(), "back": PackedByteArray()}
	for layer: String in ["front", "back"]:
		var mask := PackedByteArray()
		mask.resize(points.size())
		var sign_z: float = 1.0 if layer == "front" else -1.0
		for index: int in points.size():
			var point: Vector3 = points[index]
			if absf(point.x) >= .24 * height or point.y <= .20 * height or point.y >= .59 * height or (point.z - hip_z) * sign_z <= .025: continue
			var colour: Color = colours[index]
			var low: float = minf(colour.r, minf(colour.g, colour.b))
			var high: float = maxf(colour.r, maxf(colour.g, colour.b))
			if low > .50 and high - low < .10 and not (colour.r > colour.g * 1.04 and colour.g > colour.b * 1.08): mask[index] = 1
		flags[layer] = mask
	return flags

static func physical_uv_copies(index: int, points: PackedVector3Array, binds: PackedInt32Array, weights: PackedFloat32Array, influences: int, buckets: Dictionary) -> PackedInt32Array:
	var origin: Vector3 = points[index]
	var cell := Vector3i(floori(origin.x * 1000000.0), floori(origin.y * 1000000.0), floori(origin.z * 1000000.0))
	var copies := PackedInt32Array()
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			for dz: int in range(-1, 2):
				var key: Vector3i = cell + Vector3i(dx, dy, dz)
				if not buckets.has(key): continue
				for candidate: int in buckets[key]:
					if origin.distance_to(points[candidate]) > .000001: continue
					var same_skin := true
					for slot: int in influences:
						if binds[index * influences + slot] != binds[candidate * influences + slot] or absf(weights[index * influences + slot] - weights[candidate * influences + slot]) >= .0000001:
							same_skin = false
							break
					if same_skin: copies.append(candidate)
	return copies

static func classify(body: PackedInt32Array, body_local_support: Dictionary, points: PackedVector3Array, indices: PackedInt32Array, uv: PackedVector2Array, binds: PackedInt32Array, weights: PackedFloat32Array, influences: int, colours: Array[Color], independent_flags: Dictionary) -> Dictionary:
	# Independent paint means membership in an actual all-painted source face,
	# not merely a qualifying texel at one disconnected UV boundary vertex.
	var paint_face_membership: Dictionary = {}
	for paint_layer: String in ["front", "back"]:
		var eligible_mask: PackedByteArray = independent_flags[paint_layer]
		var painted_vertices := PackedByteArray()
		painted_vertices.resize(points.size())
		for paint_offset: int in range(0, indices.size(), 3):
			var paint_a: int = indices[paint_offset]
			var paint_b: int = indices[paint_offset + 1]
			var paint_c: int = indices[paint_offset + 2]
			if eligible_mask[paint_a] and eligible_mask[paint_b] and eligible_mask[paint_c]:
				painted_vertices[paint_a] = 1
				painted_vertices[paint_b] = 1
				painted_vertices[paint_c] = 1
		paint_face_membership[paint_layer] = painted_vertices
	var original_labels: Dictionary = {}
	for vertex: int in body: original_labels[vertex] = true
	var pure_vertices: Dictionary = {}
	var pure_faces := 0
	for face_offset: int in range(0, indices.size(), 3):
		if original_labels.has(indices[face_offset]) and original_labels.has(indices[face_offset + 1]) and original_labels.has(indices[face_offset + 2]):
			pure_faces += 1
			for corner: int in 3: pure_vertices[indices[face_offset + corner]] = true
	var isolated := PackedInt32Array()
	for vertex: int in body:
		if not pure_vertices.has(vertex): isolated.append(vertex)
	var buckets: Dictionary = {}
	for source_vertex: int in points.size():
		var source: Vector3 = points[source_vertex]
		var source_cell := Vector3i(floori(source.x * 1000000.0), floori(source.y * 1000000.0), floori(source.z * 1000000.0))
		var members: PackedInt32Array = buckets.get(source_cell, PackedInt32Array())
		members.append(source_vertex)
		buckets[source_cell] = members
	var candidates: Dictionary = {}
	var candidate_copies: Dictionary = {}
	var protected_by_pure_uv_copy := 0
	for isolated_vertex: int in isolated:
		var copies: PackedInt32Array = physical_uv_copies(isolated_vertex, points, binds, weights, influences, buckets)
		var protected := false
		for copy: int in copies:
			if pure_vertices.has(copy): protected = true
		if protected:
			protected_by_pure_uv_copy += 1
			continue
		candidates[isolated_vertex] = copies
		for copy: int in copies: candidate_copies[copy] = true
	var neighbours: Dictionary = {}
	for candidate_copy: int in candidate_copies: neighbours[candidate_copy] = {}
	for source_offset: int in range(0, indices.size(), 3):
		for local_corner: int in 3:
			var copy_vertex: int = indices[source_offset + local_corner]
			if not candidate_copies.has(copy_vertex): continue
			var adjacent: Dictionary = neighbours[copy_vertex]
			for neighbour_corner: int in 3:
				if neighbour_corner != local_corner: adjacent[indices[source_offset + neighbour_corner]] = true
	var removed: Array[Dictionary] = []
	var remove_ids: Dictionary = {}
	for isolated_vertex: int in candidates:
		var copies: PackedInt32Array = candidates[isolated_vertex]
		var surrounding: Dictionary = {}
		for copy: int in copies:
			for neighbour: int in neighbours[copy]:
				if not copies.has(neighbour): surrounding[neighbour] = true
		if surrounding.is_empty(): continue
		for layer: String in ["front", "back"]:
			var paint_mask: PackedByteArray = paint_face_membership[layer]
			var local_support: PackedFloat32Array = body_local_support[layer]
			var all_white_cloth := true
			for neighbour: int in surrounding:
				var pigment: Color = colours[neighbour]
				var low: float = minf(pigment.r, minf(pigment.g, pigment.b))
				var high: float = maxf(pigment.r, maxf(pigment.g, pigment.b))
				var khaki: bool = pigment.r > pigment.g * 1.04 and pigment.g > pigment.b * 1.08
				if paint_mask[neighbour] == 0 or low <= .50 or high - low >= .10 or khaki or local_support[neighbour] <= .000001:
					all_white_cloth = false
					break
			if not all_white_cloth: continue
			remove_ids[isolated_vertex] = true
			var texture_uv: Vector2 = uv[isolated_vertex]
			removed.append({"imported_surface_vertex_index": isolated_vertex, "rest_position": [points[isolated_vertex].x, points[isolated_vertex].y, points[isolated_vertex].z], "uv": [texture_uv.x, texture_uv.y], "physical_uv_copies": copies, "neighbour_count": surrounding.size(), "independent_white_clothing_side": layer})
			break
	var retained := PackedInt32Array()
	for original_vertex: int in body:
		if not remove_ids.has(original_vertex): retained.append(original_vertex)
	var original_count: int = body.size()
	return {"retained_indices": retained, "original_rgb_body_anchors": original_count, "retained_body_anchors": retained.size(), "original_pure_body_source_triangles_preserved": pure_faces, "isolated_rgb_body_anchors": isolated.size(), "isolated_anchors_protected_by_physical_uv_copy_on_pure_body_face": protected_by_pure_uv_copy, "isolated_anchors_reclassified_as_clothing": removed, "physical_uv_copy_policy": "rest distance<=1micrometre; identical bind slots; maximum weight difference<1e-7; protect if any physical copy belongs to a pure body triangle", "classification_rule": "Only an isolated RGB anchor absent from every physical-copy pure body face can become clothing: every incident neighbour across all copies must be same-side vertices of complete original independent pigment clothing triangles, neutral white(minRGB>.5/spread<.10), not warm khaki, and that side Local z-envelope>1micrometre. Original pure body faces and their corners are never removed."}


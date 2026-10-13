extends RefCounted

# P10 is joined by material, so its flag posts share a mesh with the deck frame
# and its cord shares a mesh with the feet. Split only while building the scene.
const PARTS_META: StringName = &"scene_lifecycle_stage_parts"
const WELD_EPSILON: float = 0.000001


static func prepare_stage(stage: Node3D) -> Array[Node3D]:
	var activity_parts: Array[Node3D] = []
	if stage == null:
		return activity_parts
	if stage.has_meta(PARTS_META):
		var cached_parts: Variant = stage.get_meta(PARTS_META)
		if cached_parts is Array:
			for cached_part: Variant in cached_parts:
				if cached_part is Node3D and is_instance_valid(cached_part):
					activity_parts.append(cached_part as Node3D)
		return activity_parts
	var stage_meshes: Array[MeshInstance3D] = []
	_collect_meshes(stage, stage_meshes)
	for stage_mesh: MeshInstance3D in stage_meshes:
		var mesh_name: String = str(stage_mesh.name)
		if mesh_name.begins_with("Pennant_") or mesh_name in ["SpeakerCharcoal", "SpeakerCone"]:
			activity_parts.append(stage_mesh)
		elif mesh_name == "CedarAge_2":
			var posts: MeshInstance3D = _split_activity(stage_mesh, stage, true, "StageBuntingPosts")
			if posts != null:
				activity_parts.append(posts)
		elif mesh_name == "CedarAge_3":
			var cord: MeshInstance3D = _split_activity(stage_mesh, stage, false, "StageBuntingCord")
			if cord != null:
				activity_parts.append(cord)
	stage.set_meta(PARTS_META, activity_parts)
	return activity_parts


static func visible_bounds(root: Node3D) -> AABB:
	var result: AABB = AABB()
	var has_vertex: bool = false
	if root == null:
		return result
	var bound_meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, bound_meshes)
	for bound_mesh: MeshInstance3D in bound_meshes:
		if bound_mesh.mesh == null or not _visible_in_hierarchy(bound_mesh):
			continue
		var to_root: Transform3D = _relative_transform(root, bound_mesh)
		for bound_surface: int in range(bound_mesh.mesh.get_surface_count()):
			var bound_arrays: Array = bound_mesh.mesh.surface_get_arrays(bound_surface)
			var bound_vertices: PackedVector3Array = bound_arrays[Mesh.ARRAY_VERTEX]
			var bound_indices: PackedInt32Array = _indices(bound_arrays, bound_vertices.size())
			for bound_index: int in bound_indices:
				var root_vertex: Vector3 = to_root * bound_vertices[bound_index]
				if has_vertex:
					result = result.expand(root_vertex)
				else:
					result = AABB(root_vertex, Vector3.ZERO)
					has_vertex = true
	return result


static func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for mesh_child: Node in node.get_children():
		_collect_meshes(mesh_child, result)


static func _visible_in_hierarchy(node: Node3D) -> bool:
	var visibility_cursor: Node = node
	while visibility_cursor != null:
		if visibility_cursor is Node3D and not (visibility_cursor as Node3D).visible:
			return false
		visibility_cursor = visibility_cursor.get_parent()
	return true


static func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	# Local transforms also work before the model is attached to the SceneTree.
	var relative: Transform3D = Transform3D.IDENTITY
	var transform_cursor: Node = node
	while transform_cursor != null and transform_cursor != root:
		if transform_cursor is Node3D:
			relative = (transform_cursor as Node3D).transform * relative
		transform_cursor = transform_cursor.get_parent()
	return relative


static func _split_activity(source: MeshInstance3D, stage: Node3D, split_components: bool, part_name: String) -> MeshInstance3D:
	var original_mesh: ArrayMesh = source.mesh as ArrayMesh
	if original_mesh == null or source.get_parent() == null:
		return null
	var retained_mesh: ArrayMesh = ArrayMesh.new()
	var activity_mesh: ArrayMesh = ArrayMesh.new()
	var retained_surfaces: Array[int] = []
	var activity_surfaces: Array[int] = []
	var original_overrides: Array[Material] = []
	var source_to_root: Transform3D = _relative_transform(stage, source)
	for source_surface: int in range(original_mesh.get_surface_count()):
		original_overrides.append(source.get_surface_override_material(source_surface))
		var source_arrays: Array = original_mesh.surface_get_arrays(source_surface)
		var source_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
		var source_indices: PackedInt32Array = _indices(source_arrays, source_vertices.size())
		var primitive_type: Mesh.PrimitiveType = original_mesh.surface_get_primitive_type(source_surface)
		if primitive_type != Mesh.PRIMITIVE_TRIANGLES:
			retained_mesh.add_surface_from_arrays(primitive_type, source_arrays)
			retained_mesh.surface_set_material(retained_mesh.get_surface_count() - 1, original_mesh.surface_get_material(source_surface))
			retained_surfaces.append(source_surface)
			continue
		var root_vertices: PackedVector3Array = source_to_root * source_vertices
		var activity_flags: PackedByteArray = _activity_triangles(root_vertices, source_indices, split_components)
		var retained_indices: PackedInt32Array = PackedInt32Array()
		var activity_indices: PackedInt32Array = PackedInt32Array()
		for triangle_offset: int in range(0, source_indices.size(), 3):
			var is_activity: bool = activity_flags[int(triangle_offset / 3.0)] != 0
			for triangle_corner: int in range(3):
				if is_activity:
					activity_indices.append(source_indices[triangle_offset + triangle_corner])
				else:
					retained_indices.append(source_indices[triangle_offset + triangle_corner])
		if not retained_indices.is_empty():
			retained_mesh.add_surface_from_arrays(primitive_type, _compact_arrays(source_arrays, retained_indices))
			retained_mesh.surface_set_material(retained_mesh.get_surface_count() - 1, original_mesh.surface_get_material(source_surface))
			retained_surfaces.append(source_surface)
		if not activity_indices.is_empty():
			activity_mesh.add_surface_from_arrays(primitive_type, _compact_arrays(source_arrays, activity_indices))
			activity_mesh.surface_set_material(activity_mesh.get_surface_count() - 1, original_mesh.surface_get_material(source_surface))
			activity_surfaces.append(source_surface)
	if activity_mesh.get_surface_count() == 0 or retained_mesh.get_surface_count() == 0:
		return null
	# Replace the instance's mesh; never edit the imported, shared ArrayMesh.
	source.mesh = retained_mesh
	for retained_surface: int in range(retained_surfaces.size()):
		source.set_surface_override_material(retained_surface, original_overrides[retained_surfaces[retained_surface]])
	var activity_part: MeshInstance3D = MeshInstance3D.new()
	activity_part.name = part_name
	activity_part.mesh = activity_mesh
	activity_part.transform = source.transform
	activity_part.material_override = source.material_override
	activity_part.material_overlay = source.material_overlay
	activity_part.cast_shadow = source.cast_shadow
	activity_part.layers = source.layers
	activity_part.extra_cull_margin = source.extra_cull_margin
	activity_part.visible = source.visible
	for activity_surface: int in range(activity_surfaces.size()):
		activity_part.set_surface_override_material(activity_surface, original_overrides[activity_surfaces[activity_surface]])
	source.get_parent().add_child(activity_part)
	return activity_part


static func _indices(arrays: Array, vertex_count: int) -> PackedInt32Array:
	var result_indices: PackedInt32Array = PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		result_indices = arrays[Mesh.ARRAY_INDEX]
	if result_indices.is_empty():
		result_indices.resize(vertex_count)
		for generated_index: int in range(vertex_count):
			result_indices[generated_index] = generated_index
	return result_indices


static func _activity_triangles(vertices: PackedVector3Array, indices: PackedInt32Array, split_components: bool) -> PackedByteArray:
	var triangle_flags: PackedByteArray = PackedByteArray()
	triangle_flags.resize(int(indices.size() / 3.0))
	var parents: Array[int] = []
	var component_max_y: Dictionary = {}
	if split_components:
		parents.resize(vertices.size())
		var welded_positions: Dictionary = {}
		for weld_index: int in range(vertices.size()):
			parents[weld_index] = weld_index
			var weld_vertex: Vector3 = vertices[weld_index]
			var weld_key: Vector3i = Vector3i(roundi(weld_vertex.x / WELD_EPSILON), roundi(weld_vertex.y / WELD_EPSILON), roundi(weld_vertex.z / WELD_EPSILON))
			if welded_positions.has(weld_key):
				_join(parents, weld_index, int(welded_positions[weld_key]))
			else:
				welded_positions[weld_key] = weld_index
		for component_triangle: int in range(0, indices.size(), 3):
			_join(parents, indices[component_triangle], indices[component_triangle + 1])
			_join(parents, indices[component_triangle], indices[component_triangle + 2])
		for component_vertex: int in range(vertices.size()):
			var component_id: int = _find(parents, component_vertex)
			component_max_y[component_id] = maxf(float(component_max_y.get(component_id, -INF)), vertices[component_vertex].y)
	for flag_offset: int in range(0, indices.size(), 3):
		var selected: bool = false
		if split_components:
			# Measured P10: posts reach 2.15 m; complete side frames end at .38 m.
			selected = float(component_max_y[_find(parents, indices[flag_offset])]) > 1.0
		else:
			# Measured P10: the complete cord is above 1.982 m; all feet end at .3 m.
			selected = vertices[indices[flag_offset]].y > 1.9 and vertices[indices[flag_offset + 1]].y > 1.9 and vertices[indices[flag_offset + 2]].y > 1.9
		triangle_flags[int(flag_offset / 3.0)] = 1 if selected else 0
	return triangle_flags


static func _find(parents: Array[int], index: int) -> int:
	var root_index: int = index
	while parents[root_index] != root_index:
		parents[root_index] = parents[parents[root_index]]
		root_index = parents[root_index]
	return root_index


static func _join(parents: Array[int], left: int, right: int) -> void:
	var left_root: int = _find(parents, left)
	var right_root: int = _find(parents, right)
	if left_root != right_root:
		parents[right_root] = left_root


static func _compact_arrays(source_arrays: Array, selected_indices: PackedInt32Array) -> Array:
	var result_arrays: Array = []
	result_arrays.resize(Mesh.ARRAY_MAX)
	var index_map: Dictionary = {}
	var selected_vertices: PackedInt32Array = PackedInt32Array()
	var compact_indices: PackedInt32Array = PackedInt32Array()
	for original_index: int in selected_indices:
		if not index_map.has(original_index):
			index_map[original_index] = selected_vertices.size()
			selected_vertices.append(original_index)
		compact_indices.append(int(index_map[original_index]))
	var original_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
	for array_slot: int in range(Mesh.ARRAY_INDEX):
		if source_arrays[array_slot] != null:
			result_arrays[array_slot] = _select_stream(source_arrays[array_slot], selected_vertices, original_vertices.size())
	result_arrays[Mesh.ARRAY_INDEX] = compact_indices
	return result_arrays


static func _select_stream(stream: Variant, selected_vertices: PackedInt32Array, vertex_count: int) -> Variant:
	match typeof(stream):
		TYPE_PACKED_VECTOR3_ARRAY:
			var vector_source: PackedVector3Array = stream
			var vector_result: PackedVector3Array = PackedVector3Array()
			for vector_index: int in selected_vertices:
				vector_result.append(vector_source[vector_index])
			return vector_result
		TYPE_PACKED_VECTOR2_ARRAY:
			var uv_source: PackedVector2Array = stream
			var uv_result: PackedVector2Array = PackedVector2Array()
			for uv_index: int in selected_vertices:
				uv_result.append(uv_source[uv_index])
			return uv_result
		TYPE_PACKED_COLOR_ARRAY:
			var colour_source: PackedColorArray = stream
			var colour_result: PackedColorArray = PackedColorArray()
			for colour_index: int in selected_vertices:
				colour_result.append(colour_source[colour_index])
			return colour_result
		TYPE_PACKED_FLOAT32_ARRAY:
			var float_source: PackedFloat32Array = stream
			var float_result: PackedFloat32Array = PackedFloat32Array()
			var float_stride: int = int(float_source.size() / float(vertex_count))
			for float_vertex: int in selected_vertices:
				for float_channel: int in range(float_stride):
					float_result.append(float_source[float_vertex * float_stride + float_channel])
			return float_result
		TYPE_PACKED_INT32_ARRAY:
			var integer_source: PackedInt32Array = stream
			var integer_result: PackedInt32Array = PackedInt32Array()
			var integer_stride: int = int(integer_source.size() / float(vertex_count))
			for integer_vertex: int in selected_vertices:
				for integer_channel: int in range(integer_stride):
					integer_result.append(integer_source[integer_vertex * integer_stride + integer_channel])
			return integer_result
		TYPE_PACKED_BYTE_ARRAY:
			var byte_source: PackedByteArray = stream
			var byte_result: PackedByteArray = PackedByteArray()
			var byte_stride: int = int(byte_source.size() / float(vertex_count))
			for byte_vertex: int in selected_vertices:
				for byte_channel: int in range(byte_stride):
					byte_result.append(byte_source[byte_vertex * byte_stride + byte_channel])
			return byte_result
	push_error("Unsupported P10 vertex stream while separating activity parts")
	return null

class_name FurnitureForms
extends RefCounted
## Cached rounded timber meshes with the same central deck and outer dimensions.
static var _meshes: Dictionary = {}

static func rounded_box(size: Vector3, corner: float = .035, edge: float = .009, steps: int = 4) -> ArrayMesh:
	var key: String = "%s/%s/%s/%d" % [size, corner, edge, steps]
	if _meshes.has(key): return _meshes[key] as ArrayMesh
	var radii := Vector3(minf(corner, size.x * .45), minf(edge, size.y * .45), minf(corner, size.z * .45))
	var half: Vector3 = size * .5
	var core: Vector3 = half - radii
	var coordinates: Array[PackedFloat32Array] = []
	for dimension: int in 3:
		var samples := PackedFloat32Array()
		for index: int in range(steps, -1, -1): samples.append(-core[dimension] - radii[dimension] * tan(float(index) / float(steps) * PI * .25))
		for index: int in range(steps + 1): samples.append(core[dimension] + radii[dimension] * tan(float(index) / float(steps) * PI * .25))
		coordinates.append(samples)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for axis: int in 3:
		var axis_u: int = (axis + 1) % 3
		var axis_v: int = (axis + 2) % 3
		for side: float in [-1., 1.]:
			var start: int = vertices.size()
			var columns: int = coordinates[axis_u].size()
			var rows: int = coordinates[axis_v].size()
			for row: int in rows:
				for column: int in columns:
					var point := Vector3.ZERO
					point[axis] = half[axis] * side
					point[axis_u] = coordinates[axis_u][column]
					point[axis_v] = coordinates[axis_v][row]
					var nearest: Vector3 = point.clamp(-core, core)
					var direction: Vector3 = ((point - nearest) / radii).normalized()
					var rounded: Vector3 = nearest + direction * radii
					vertices.append(rounded)
					normals.append((direction / radii).normalized())
					uvs.append(Vector2(rounded[axis_u] / size[axis_u] + .5, rounded[axis_v] / size[axis_v] + .5))
			for row: int in rows - 1:
				for column: int in columns - 1:
					var a: int = start + row * columns + column
					var b: int = a + 1
					var c: int = a + columns
					var d: int = c + 1
					# Godot front faces are clockwise; the normal points outward.
					indices.append_array(PackedInt32Array([a, c, b, b, c, d]) if side > 0. else PackedInt32Array([a, b, c, b, d, c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.set_meta("furniture_corner_radius", radii.x)
	mesh.set_meta("furniture_edge_radius", radii.y)
	mesh.set_meta("furniture_round_steps", steps)
	_meshes[key] = mesh
	return mesh

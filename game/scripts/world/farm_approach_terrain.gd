extends RefCounted
## One open road bed: the old 3.4 m cut now bends and rejoins the meadow.
## UV V is measured along each cross-section so steep banks keep real texture area.
const SIDE_STEPS := 8


static func centre_z(x: float) -> float:
	return -11.0 + 3.8 * smoothstep(60.0, 112.0, x)


static func half_width(x: float) -> float:
	return lerpf(1.3, .40, smoothstep(101.0, 132.0, x))


static func height_at(x: float) -> float:
	var descent: float = lerpf(0.0, -3.4, smoothstep(45.6, 63.0, x))
	return lerpf(descent, -.03, smoothstep(72.0, 126.0, x))


static func _section(x: float, cut: Rect2) -> Dictionary:
	var centre: float = centre_z(x)
	var width: float = half_width(x)
	var height: float = height_at(x)
	var vertices: Array[Vector3] = []
	for index: int in SIDE_STEPS + 1:
		var fraction: float = index / float(SIDE_STEPS)
		vertices.append(Vector3(x, lerpf(-.03, height, smoothstep(0, 1, fraction)), lerpf(cut.position.y, centre - width, fraction)))
	vertices.append(Vector3(x, height, centre + width))
	for index: int in range(1, SIDE_STEPS + 1):
		var fraction: float = index / float(SIDE_STEPS)
		vertices.append(Vector3(x, lerpf(height, -.03, smoothstep(0, 1, fraction)), lerpf(centre + width, cut.end.y, fraction)))
	var distances: Array[float] = [0.0]
	for index: int in range(1, vertices.size()):
		distances.append(distances[index - 1] + vertices[index].distance_to(vertices[index - 1]))
	var to_centre: float = distances[SIDE_STEPS] + width
	var v_coords: Array[float] = []
	for distance: float in distances:
		v_coords.append(centre + distance - to_centre)
	return {"vertices": vertices, "v_coords": v_coords}


static func _triangle(surface: SurfaceTool, vertices: Array[Vector3], uvs: Array[Vector2]) -> void:
	for index: int in 3:
		surface.set_uv(uvs[index])
		var at: Vector3 = vertices[index]
		surface.set_uv2(Vector2(half_width(at.x), at.z - centre_z(at.x)))
		surface.add_vertex(vertices[index])


static func surface_height(at: Vector2, cut: Rect2) -> float:
	# Interpolate the actual two triangles of the sampled strip, including bends.
	var steps: int = maxi(2, ceili(cut.size.x / .6))
	var column: int = clampi(floori((at.x - cut.position.x) / cut.size.x * steps), 0, steps - 1)
	var left: Dictionary = _section(lerpf(cut.position.x, cut.end.x, column / float(steps)), cut)
	var right: Dictionary = _section(lerpf(cut.position.x, cut.end.x, (column + 1) / float(steps)), cut)
	for row: int in SIDE_STEPS * 2 + 1:
		var triangles: Array[Array] = [[left.vertices[row], right.vertices[row], left.vertices[row + 1]], [right.vertices[row], right.vertices[row + 1], left.vertices[row + 1]]]
		for triangle: Array in triangles:
			var a: Vector3 = triangle[0]
			var b: Vector3 = triangle[1]
			var c: Vector3 = triangle[2]
			var ab := Vector2(b.x - a.x, b.z - a.z)
			var ac := Vector2(c.x - a.x, c.z - a.z)
			var relative: Vector2 = at - Vector2(a.x, a.z)
			var determinant: float = ab.cross(ac)
			var u: float = relative.cross(ac) / determinant
			var v: float = ab.cross(relative) / determinant
			if u >= -.00001 and v >= -.00001 and u + v <= 1.00001:
				return a.y + (b.y - a.y) * u + (c.y - a.y) * v
	return -.03


static func build(parent: Node3D, cut: Rect2, path_material: Material, bank_material: Material) -> MeshInstance3D:
	var steps: int = maxi(2, ceili(cut.size.x / .6))
	var sections: Array[Dictionary] = []
	var route_lengths: Array[float] = [cut.position.x]
	for index: int in steps + 1:
		var x: float = lerpf(cut.position.x, cut.end.x, index / float(steps))
		sections.append(_section(x, cut))
		if index > 0:
			var before_x: float = lerpf(cut.position.x, cut.end.x, (index - 1) / float(steps))
			var before: Vector3 = Vector3(before_x, height_at(before_x), centre_z(before_x))
			var current: Vector3 = Vector3(x, height_at(x), centre_z(x))
			route_lengths.append(route_lengths[index - 1] + before.distance_to(current))
	var surfaces: Array[SurfaceTool] = [SurfaceTool.new(), SurfaceTool.new()]
	for surface: SurfaceTool in surfaces:
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for column: int in steps:
		var left: Dictionary = sections[column]
		var right: Dictionary = sections[column + 1]
		var u_left: float = route_lengths[column]
		var u_right: float = route_lengths[column + 1]
		for row: int in SIDE_STEPS * 2 + 1:
			var surface: SurfaceTool = surfaces[0] if row == SIDE_STEPS else surfaces[1]
			var a: Vector3 = left.vertices[row]
			var b: Vector3 = right.vertices[row]
			var c: Vector3 = left.vertices[row + 1]
			var d: Vector3 = right.vertices[row + 1]
			var uv_a := Vector2(u_left, left.v_coords[row])
			var uv_b := Vector2(u_right, right.v_coords[row])
			var uv_c := Vector2(u_left, left.v_coords[row + 1])
			var uv_d := Vector2(u_right, right.v_coords[row + 1])
			_triangle(surface, [a, b, c], [uv_a, uv_b, uv_c])
			_triangle(surface, [b, d, c], [uv_b, uv_d, uv_c])
	for surface: SurfaceTool in surfaces:
		surface.generate_normals()
		surface.index()
	var mesh: ArrayMesh = surfaces[0].commit()
	surfaces[1].commit(mesh)
	var lane := MeshInstance3D.new()
	lane.name = "Lane"
	lane.mesh = mesh
	var bounds := Vector4(cut.position.x, cut.position.y, cut.end.x, cut.end.y)
	var road_material := ShaderMaterial.new()
	road_material.shader = load("res://shaders/lane_path.gdshader")
	var source_path: ShaderMaterial = path_material as ShaderMaterial
	if source_path != null:
		for parameter: String in ["albedo_tex", "wear_tex", "tint", "tile", "macro_strength", "surface_wear"]:
			road_material.set_shader_parameter(parameter, source_path.get_shader_parameter(parameter))
	road_material.set_shader_parameter("lane_bounds", bounds)
	var grass_material: ShaderMaterial = bank_material as ShaderMaterial
	if grass_material != null:
		grass_material.set_shader_parameter("lane_bounds", bounds)
	lane.set_surface_override_material(0, road_material)
	lane.set_surface_override_material(1, bank_material)
	lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(lane)
	var body := StaticBody3D.new()
	body.collision_layer = WorldBuilder.L_GROUND
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	lane.add_child(body)
	return lane

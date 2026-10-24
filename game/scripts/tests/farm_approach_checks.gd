extends RefCounted
## The reported green wall was real closing geometry with collapsed XZ UVs.
## Inspect rendered triangles, their UV area and physics instead of marker metadata.
var t: Node
var main: Node


func _init(runner: Node) -> void:
	t = runner
	main = runner.main


func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("FARM_APPROACH", label, ok, detail)


func _surface_height(lane: MeshInstance3D, surface: int, at: Vector2) -> float:
	var arrays: Array = lane.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count: int = indices.size() if not indices.is_empty() else vertices.size()
	var highest: float = -INF
	for offset: int in range(0, count - 2, 3):
		var points: Array[Vector3] = []
		for corner: int in 3:
			points.append(lane.to_global(vertices[indices[offset + corner] if not indices.is_empty() else offset + corner]))
		var crossing: Variant = Geometry3D.segment_intersects_triangle(Vector3(at.x, 12, at.y), Vector3(at.x, -12, at.y), points[0], points[1], points[2])
		if crossing != null:
			highest = maxf(highest, (crossing as Vector3).y)
	return highest


func _path_section(lane: MeshInstance3D, x: float) -> Dictionary:
	var arrays: Array = lane.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count: int = indices.size() if not indices.is_empty() else vertices.size()
	var low: float = INF
	var high: float = -INF
	for offset: int in range(0, count - 2, 3):
		for edge: int in 3:
			var a: Vector3 = lane.to_global(vertices[indices[offset + edge] if not indices.is_empty() else offset + edge])
			var next: int = (edge + 1) % 3
			var b: Vector3 = lane.to_global(vertices[indices[offset + next] if not indices.is_empty() else offset + next])
			if absf(a.x - b.x) < .00001 or x < minf(a.x, b.x) - .00001 or x > maxf(a.x, b.x) + .00001:
				continue
			var z: float = lerpf(a.z, b.z, clampf((x - a.x) / (b.x - a.x), 0, 1))
			low = minf(low, z)
			high = maxf(high, z)
	var centre: float = (low + high) * .5
	return {"valid": is_finite(centre), "low": low, "high": high, "centre": centre, "height": _surface_height(lane, 0, Vector2(x, centre)) if is_finite(centre) else -INF}


func run() -> void:
	var lane: MeshInstance3D = main.world.get_node_or_null("Lane") as MeshInstance3D
	check("the town exit contains a physical rendered path and banks", lane != null and lane.mesh.get_surface_count() == 2)
	if lane == null:
		return
	var faces: PackedVector3Array = lane.mesh.get_faces()
	var min_up: float = 1.0
	var triangle_count: int = 0
	for offset: int in range(0, faces.size(), 3):
		var cross: Vector3 = (faces[offset + 2] - faces[offset]).cross(faces[offset + 1] - faces[offset])
		if cross.length() < .000001:
			continue
		min_up = minf(min_up, cross.normalized().y)
		triangle_count += 1
	check("every visible exit face is a walkable-looking slope rather than a vertical cap", min_up > .60, "min upward normal %.4f; triangles %d" % [min_up, triangle_count])
	var bank_arrays: Array = lane.mesh.surface_get_arrays(1)
	var bank_vertices: PackedVector3Array = bank_arrays[Mesh.ARRAY_VERTEX]
	var bank_uv: PackedVector2Array = bank_arrays[Mesh.ARRAY_TEX_UV]
	var bank_indices: PackedInt32Array = bank_arrays[Mesh.ARRAY_INDEX] if bank_arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var bank_count: int = bank_indices.size() if not bank_indices.is_empty() else bank_vertices.size()
	var min_uv_density: float = INF
	var max_uv_density: float = 0.0
	for offset: int in range(0, bank_count - 2, 3):
		var a: int = bank_indices[offset] if not bank_indices.is_empty() else offset
		var b: int = bank_indices[offset + 1] if not bank_indices.is_empty() else offset + 1
		var c: int = bank_indices[offset + 2] if not bank_indices.is_empty() else offset + 2
		var area: float = (bank_vertices[b] - bank_vertices[a]).cross(bank_vertices[c] - bank_vertices[a]).length()
		if area < .000001:
			continue
		var uv_area: float = absf((bank_uv[b] - bank_uv[a]).cross(bank_uv[c] - bank_uv[a]))
		min_uv_density = minf(min_uv_density, uv_area / area)
		max_uv_density = maxf(max_uv_density, uv_area / area)
	check("actual bank triangles preserve two-dimensional metre-scale UV area", min_uv_density > .65 and max_uv_density < 1.45, "UV/world area %.4f..%.4f" % [min_uv_density, max_uv_density])
	var bank_material: ShaderMaterial = lane.get_active_material(1) as ShaderMaterial
	check("the bank texture reads its slope UVs with the existing painted grass", bank_material != null and bank_material.shader.resource_path == "res://shaders/lane_bank.gdshader" and bank_material.get_shader_parameter("albedo_tex") is Texture2D)
	var sections: Array[Dictionary] = []
	var extends_beyond: bool = true
	for x: float in [63.8, 64.2, 72.0, 86.0, 102.0, 120.0, 131.8]:
		var section: Dictionary = _path_section(lane, x)
		sections.append(section)
		extends_beyond = extends_beyond and section.valid and is_finite(section.height) and float(section.high) - float(section.low) > .50
	check("the same gravel surface continues past the former wall into the distance", extends_beyond, str(sections))
	var before_cap: Dictionary = sections[0]
	var after_cap: Dictionary = sections[1]
	check("the former x64 cap is replaced by a continuous road", before_cap.valid and after_cap.valid and absf(float(before_cap.height) - float(after_cap.height)) < .05)
	var start_section: Dictionary = _path_section(lane, 55.0)
	var last_section: Dictionary = _path_section(lane, 131.8)
	check("the distant road bends gently and joins the surrounding meadow level", start_section.valid and last_section.valid and absf(float(last_section.height) + .03) < .04 and absf(float(last_section.centre) - float(start_section.centre)) > 2.5)
	var grounded: bool = true
	var samples: Array[Dictionary] = []
	var space: PhysicsDirectSpaceState3D = main.world.get_world_3d().direct_space_state
	for x: float in [43.3, 46.0, 55.0, 63.8, 64.2, 72.0, 86.0, 102.0, 120.0, 131.8]:
		var section: Dictionary = _path_section(lane, x)
		if not section.valid:
			grounded = false
			continue
		var at: Vector2 = Vector2(x, float(section.centre))
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(at.x, 8, at.y), Vector3(at.x, -8, at.y), WorldBuilder.L_GROUND)
		var hit: Dictionary = space.intersect_ray(ray)
		var physical: float = (hit.get("position", Vector3(0, -INF, 0)) as Vector3).y
		grounded = grounded and is_finite(physical) and absf(physical - float(section.height)) < .012
		samples.append({"x": x, "rendered": section.height, "collision": physical})
	check("the extended visible road has matching ground collision throughout", grounded, JSON.stringify(samples))
	var rooted_on_path: Array[String] = []
	for tree_node: Node in main.world.get_children():
		if not tree_node is Node3D or not bool(tree_node.get_meta("near_background_tree", false)):
			continue
		var tree: Node3D = tree_node as Node3D
		for trunk: MeshInstance3D in WorldBuilder.find_meshes(tree):
			if not str(trunk.name).begins_with("Trunk"):
				continue
			var bounds: AABB = trunk.global_transform * trunk.get_aabb()
			var section: Dictionary = _path_section(lane, bounds.get_center().x)
			if section.valid and bounds.position.z < float(section.high) + .35 and bounds.end.z > float(section.low) - .35:
				rooted_on_path.append(str(tree.name))
	check("no existing bank-tree trunk grows through the gravel corridor", rooted_on_path.is_empty(), str(rooted_on_path))
	var gate_clear: bool = true
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = .28
	query.shape = sphere
	query.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_BLOCK
	for step: int in 21:
		query.transform = Transform3D(Basis(), Vector3(40.6 + step * .24, .9, Layout.STREET_Z))
		gate_clear = gate_clear and space.intersect_shape(query, 1).is_empty()
	check("the player's real approach and gate opening remain unobstructed", gate_clear)
	await t.use("east_end")
	await t.frames(40)
	check("the original gate interaction still enters the farm", main.world.region == "farm" and main.player.global_position.distance_to(FarmBuilder.ORIGIN + FarmBuilder.ENTRY) < .4)
	await t.use("farm_exit")
	await t.frames(40)
	check("the original farm interaction returns just inside the town gate", main.world.region == "town" and main.player.global_position.distance_to(WorldBuilder.EXIT_GATE + Vector3(-2.4, .1, 0)) < .4)

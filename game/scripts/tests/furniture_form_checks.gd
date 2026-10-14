extends RefCounted
## Geometry contracts measured from the 9b7aaa9 shipped GLBs. These checks use
## triangles, ray intersections and authored UV area, never a refinement marker.
## The predecessor must run these normally and fail the rounded-form checks.
## A headless material-path check cannot replace native reflection screenshots.
const BOUNDS := {
	"P_cafe_table": [Vector3(-.9475, 0, -.36), Vector3(.9475, .89, .36)],
	"P_community_table": [Vector3(-1.025, 0, -1.1175), Vector3(1.025, .89, 1.1175)],
	"P_reading_chair": [Vector3(-.3025, 0, -.255), Vector3(.3025, .89, .255)],
	"I04_shop_counter": [Vector3(-1.055, 0, -.575), Vector3(1.055, 1.22, .6225)],
	"P_gondola": [Vector3(-.92, 0, -.31), Vector3(.92, 1.6, .31)],
	"W17_display_shelf": [Vector3(-.545, 0, -.25), Vector3(.545, 1.25, .25)],
	"I05_bread_shelf": [Vector3(-.535, 0, -.31), Vector3(.535, 1.51, .31)],
	"W13_cedar_worktable": [Vector3(-.9, 0, -.46125), Vector3(.9, .78, .46125)],
	"I02_cake_showcase": [Vector3(-.67, 0, -.3745), Vector3(.67, 1.149, .3805)],
	"P_deck_oven": [Vector3(-.73, 0, -.445), Vector3(.73, 2.08, .5098)],
	"P_coffee_station": [Vector3(-.5, 0, -.33), Vector3(.5, 1.326, .355)]
}
const ROUNDED := {
	"P_cafe_table": ["RoundTop", "ChairRightSeat"],
	"P_community_table": ["SharedTop", "ChairFrontSeat"],
	"P_reading_chair": ["ReadingChairArm", "ReadingChairSeat"],
	"I04_shop_counter": ["CounterTop"],
	"P_gondola": ["*"],
	"W17_display_shelf": ["TrayBoard_0"],
	"I05_bread_shelf": ["TrayBoard_0"],
	"W13_cedar_worktable": ["Solid rectangular tabletop*"],
	"I02_cake_showcase": ["CabinetBase", "TopRail"]
}
var t: Object
var main: Node
var fixture: Node3D
var imported: Dictionary = {}

func _init(runner: Object) -> void:
	t = runner
	main = runner.main

func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("FURNITURE_FORM", label, ok, detail)

func _meshes(root: Node3D, pattern: String = "*") -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root == null: return result
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		var label: String = str(mesh.name).to_lower().replace(" ", "_").replace(".", "_")
		if label.match(pattern.to_lower().replace(" ", "_").replace(".", "_")): result.append(mesh)
	return result

func _live(id: String) -> Node3D:
	for candidate: Node in main.world.find_children("*", "Node3D", true, false):
		if str(candidate.get_meta("model_id", "")) == id: return candidate as Node3D
	return null

func _triangles(root: Node3D, pattern: String = "*") -> PackedVector3Array:
	var result := PackedVector3Array()
	for mesh: MeshInstance3D in _meshes(root, pattern):
		var transform: Transform3D = root.global_transform.affine_inverse() * mesh.global_transform
		for vertex: Vector3 in mesh.mesh.get_faces(): result.append(transform * vertex)
	return result

func _edge_slopes(root: Node3D, pattern: String) -> Dictionary:
	# A bevel must contain several actual planes between vertical and horizontal.
	# Smooth vertex normals on a 12-triangle box or a single 45-degree chamfer fail.
	var faces: PackedVector3Array = _triangles(root, pattern)
	var slopes: Dictionary = {}
	var transition_area: float = 0.0
	for offset: int in range(0, faces.size() - 2, 3):
		var cross: Vector3 = (faces[offset + 1] - faces[offset]).cross(faces[offset + 2] - faces[offset])
		var area: float = cross.length() * .5
		if area < .0000001: continue
		var normal: Vector3 = cross.normalized().abs()
		if normal.y <= .055 or normal.y >= .995: continue
		if minf(normal.x, normal.z) > .025: continue
		var degrees: float = rad_to_deg(acos(clampf(normal.y, 0, 1)))
		slopes[int(round(degrees / 3.0))] = true
		transition_area += area
	return {"ok": slopes.size() >= 3 and transition_area > .001, "slope_bins": slopes.keys(), "transition_area": transition_area}

func _hit(faces: PackedVector3Array, origin: Vector3, direction: Vector3) -> Vector3:
	var nearest: Vector3 = Vector3.INF
	var distance: float = INF
	for offset: int in range(0, faces.size() - 2, 3):
		var result: Variant = Geometry3D.ray_intersects_triangle(origin, direction, faces[offset], faces[offset + 1], faces[offset + 2])
		if result is Vector3:
			var point: Vector3 = result
			var next_distance: float = origin.distance_squared_to(point)
			if next_distance < distance:
				nearest = point
				distance = next_distance
	return nearest

func _height(root: Node3D, at: Vector3, ceiling: float) -> float:
	if root == null: return -INF
	return WorldBuilder.rendered_support_height(root, root.to_global(at), ceiling, true)

func _seat_curves(id: String, pattern: String, center: Vector3, across: Vector3) -> void:
	var model: Node3D = imported.get(id) as Node3D
	var faces: PackedVector3Array = _triangles(model, pattern)
	var middle: Vector3 = _hit(faces, center + Vector3.UP, Vector3.DOWN)
	# The central 23 cm remains a stable hip-support patch. Probe inside the
	# surrounding shallow seat dish, still well clear of its 14 mm edge roundover.
	var left: Vector3 = _hit(faces, center + Vector3.UP - across * .17, Vector3.DOWN)
	var right: Vector3 = _hit(faces, center + Vector3.UP + across * .17, Vector3.DOWN)
	var depth: float = absf(middle.y - (left.y + right.y) * .5)
	check(id + " seat has a shallow real central curve rather than a flat box", middle.is_finite() and left.is_finite() and right.is_finite() and depth >= .002 and depth <= .018, "center=%s left=%s right=%s curve=%.5f" % [middle, left, right, depth])
	var support_ok: bool = true
	var samples: Array[float] = []
	for offset: float in [-.10, 0., .10]:
		var height: float = _height(model, center + across * offset, .56)
		samples.append(height)
		support_ok = support_ok and is_finite(height) and absf(height - .48) <= .012
	check(id + " keeps the existing seated hip support within twelve millimetres", support_ok, str(samples))

func _back_curve(id: String, pattern: String, center: Vector3, across: Vector3, toward: Vector3) -> void:
	var faces: PackedVector3Array = _triangles(imported.get(id) as Node3D, pattern)
	var middle: Vector3 = _hit(faces, center - toward * .35, toward)
	var left: Vector3 = _hit(faces, center - toward * .35 - across * .15, toward)
	var right: Vector3 = _hit(faces, center - toward * .35 + across * .15, toward)
	var sag: float = absf((middle - (left + right) * .5).dot(toward))
	check(id + " backrest bends across the sitter instead of only tilting a flat slab", middle.is_finite() and left.is_finite() and right.is_finite() and sag >= .004 and sag < .065, "center=%s left=%s right=%s sag=%.5f" % [middle, left, right, sag])

func _support_plane(id: String, heights: Array, width: float, depths: Array, ceiling_offset: float = .009) -> Dictionary:
	var errors: Array[String] = []
	var samples: int = 0
	var model: Node3D = imported.get(id) as Node3D
	for height_value: float in heights:
		for x_value: float in [-width * .5, 0.0, width * .5]:
			for z_value: float in depths:
				var found: float = _height(model, Vector3(x_value, 0, z_value), height_value + ceiling_offset)
				samples += 1
				if not is_finite(found) or absf(found - height_value) > .004:
					errors.append("at=(%.3f,%.3f) expected=%.4f actual=%.4f" % [x_value, z_value, height_value, found])
	return {"ok": samples > 0 and errors.is_empty(), "samples": samples, "errors": errors}

func _bounds_contract(ids: Array[String], label: String) -> void:
	var errors: Array[String] = []
	for id: String in ids:
		var root: Node3D = imported.get(id) as Node3D
		if root == null:
			errors.append(id + " missing")
			continue
		var box: AABB = WorldBuilder.local_aabb(root)
		var expected_min: Vector3 = BOUNDS[id][0]
		var expected_max: Vector3 = BOUNDS[id][1]
		var lower_error: Vector3 = (box.position - expected_min).abs()
		var upper_error: Vector3 = (box.end - expected_max).abs()
		if maxf(lower_error[lower_error.max_axis_index()], upper_error[upper_error.max_axis_index()]) > .02 or absf(box.position.y) > .003:
			errors.append("%s bounds=%s -> %s" % [id, box.position, box.end])
	check(label, errors.is_empty(), str(errors))

func _uv_report(root: Node3D, role: String) -> Dictionary:
	var visible_area: float = 0.
	var mapped_area: float = 0.
	var texture_area: float = 0.
	var textured_surfaces: int = 0
	for mesh: MeshInstance3D in _meshes(root):
		for surface: int in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or source.resource_name != role: continue
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array else PackedVector2Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var count: int = indices.size() if not indices.is_empty() else vertices.size()
			if source.albedo_texture != null: textured_surfaces += 1
			for offset: int in range(0, count - 2, 3):
				var a: int = indices[offset] if not indices.is_empty() else offset
				var b: int = indices[offset + 1] if not indices.is_empty() else offset + 1
				var c: int = indices[offset + 2] if not indices.is_empty() else offset + 2
				var area: float = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length() * .5
				visible_area += area
				if uv.size() != vertices.size(): continue
				var uv_area: float = absf((uv[b] - uv[a]).cross(uv[c] - uv[a])) * .5
				if uv_area > .00000001 and source.albedo_texture != null: mapped_area += area
				texture_area += uv_area
	return {"ok": visible_area > .02 and mapped_area / maxf(visible_area, .000001) > .95 and textured_surfaces > 0 and texture_area > .05, "mapped_fraction": mapped_area / maxf(visible_area, .000001), "uv_area": texture_area, "surfaces": textured_surfaces}

func _active_texture_kept(root: Node3D, role: String) -> bool:
	var found: bool = false
	for mesh: MeshInstance3D in _meshes(root):
		for surface: int in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or source.resource_name != role: continue
			var finish: ShaderMaterial = mesh.get_active_material(surface) as ShaderMaterial
			if source.albedo_texture == null or finish == null: return false
			found = true
			if finish.get_shader_parameter("albedo_tex") != source.albedo_texture: return false
			if finish.get_shader_parameter("uv_scale") != Vector2(source.uv1_scale.x, source.uv1_scale.y) or finish.get_shader_parameter("uv_offset") != Vector2(source.uv1_offset.x, source.uv1_offset.y): return false
	return found

func _zeroes_dielectric_ibl(code: String) -> bool:
	# Godot's diffuse_toon render mode multiplies indirect specular by metallic.
	# Comments mentioning the restriction are not render-mode declarations.
	var declarations := RegEx.new()
	declarations.compile("(?m)^\\s*render_mode\\s+([^;]+);")
	for declaration: RegExMatch in declarations.search_all(code):
		for token: String in declaration.get_string(1).split(","):
			if token.strip_edges() == "diffuse_toon": return true
	return false

func run() -> void:
	fixture = Node3D.new()
	fixture.name = "FurnitureFormProbe"
	fixture.visible = false
	main.add_child(fixture)
	for id: String in BOUNDS:
		var scene: PackedScene = WorldBuilder.model_scene(id)
		if scene == null: continue
		var model: Node3D = scene.instantiate() as Node3D
		fixture.add_child(model)
		imported[id] = model
	var timber_ids: Array[String] = []
	for id: String in ROUNDED: timber_ids.append(id)
	_bounds_contract(timber_ids, "all nine rebuilt furnishings retain their original footprint height and floor contact")
	_bounds_contract(["P_deck_oven", "P_coffee_station"], "appliances retain their placed footprint and original working heights")
	for id: String in ROUNDED:
		var details: Dictionary = {}
		var rounded: bool = true
		for pattern: String in ROUNDED[id]:
			var report: Dictionary = _edge_slopes(imported.get(id) as Node3D, pattern)
			details[pattern] = report
			rounded = rounded and bool(report.ok)
		check(id + " has multiple real roundover planes on the exposed furniture edges", rounded, str(details))
	_seat_curves("P_cafe_table", "ChairRightSeat", Vector3(.70, 0, 0), Vector3.FORWARD)
	_seat_curves("P_community_table", "ChairFrontSeat*", Vector3(0, 0, .87), Vector3.RIGHT)
	_seat_curves("P_reading_chair", "ReadingChairSeat", Vector3.ZERO, Vector3.RIGHT)
	_back_curve("P_cafe_table", "ChairRightBack", Vector3(.92, .69, 0), Vector3.FORWARD, Vector3.RIGHT)
	_back_curve("P_community_table", "ChairFrontBack*", Vector3(0, .69, 1.09), Vector3.RIGHT, Vector3.BACK)
	_back_curve("P_reading_chair", "ReadingChairBack", Vector3(0, .69, -.22), Vector3.RIGHT, Vector3.FORWARD)
	var tabletop_errors: Dictionary = {}
	for row: Array in [["P_cafe_table", .76, .32, [-.12, .12]], ["P_community_table", .75, 1.5, [-.30, .30]], ["I04_shop_counter", .87, 1.6, [-.10, .25]], ["W13_cedar_worktable", .78, 1.4, [-.28, .28]]]:
		var report: Dictionary = _support_plane(str(row[0]), [row[1]], float(row[2]), row[3])
		if not report.ok: tabletop_errors[str(row[0])] = report
	check("table and serving centers retain the original flat support patches beneath books dishes and food", tabletop_errors.is_empty(), str(tabletop_errors))
	for row: Array in [["W17_display_shelf", [.354, .654, 1.004], .88, [-.11, .11]], ["I05_bread_shelf", [.274, .614, .944, 1.264], .82, [-.12, .15]], ["P_gondola", [.14, .48, .82, 1.16], 1.5, [-.17, -.065, .065, .17]], ["I02_cake_showcase", [.5735, .8135], .90, [-.11, .12]]]:
		var report: Dictionary = _support_plane(str(row[0]), row[1], float(row[2]), row[3], .025)
		check(str(row[0]) + " keeps every stocked shelf level and both product rows supported", bool(report.ok), str(report))
	var procedural_errors: Dictionary = {}
	for row: Array in [["toolshed", "DirtyWorkBench"], ["zakka", "RepairWorkbench"], ["post", "PostalCounter"], ["home_haru", "FamilyLowTable"], ["photo_room", "PhotoComparisonDesk"], ["library", "MapReadingDesk"]]:
		var room: Node3D = main.world.interiors.get(str(row[0])) as Node3D
		var board: Node3D = room.find_child(str(row[1]), true, false) as Node3D if room != null else null
		var report: Dictionary = _edge_slopes(board, "*")
		if not report.ok: procedural_errors[str(row[1])] = report
	check("actual resident work family photo and postal table edges are rounded in the rendered mesh", procedural_errors.is_empty(), str(procedural_errors))
	var oven: Node3D = imported.get("P_deck_oven") as Node3D
	for row: Array in [["P_deck_oven", "Oven_MaintainedEnamel*"], ["P_coffee_station", "BrushedSteel_Geometry"]]:
		var appliance_curves: Dictionary = _edge_slopes(imported.get(str(row[0])) as Node3D, str(row[1]))
		check(str(row[0]) + " casing has real multisegment curved highlight edges", bool(appliance_curves.ok), str(appliance_curves))
	var uv: Dictionary = _uv_report(oven, "Oven_MaintainedEnamel")
	check("the oven enamel image maps over real surface area instead of collapsed or missing UVs", bool(uv.ok), str(uv))
	check("the live oven finish keeps the imported enamel image and its authored UV transform", _active_texture_kept(_live("P_deck_oven"), "Oven_MaintainedEnamel"))
	var reflection_errors: Array[String] = []
	for id: String in ["P_deck_oven", "P_coffee_station", "P_cafe_table", "I04_shop_counter", "I02_cake_showcase"]:
		var reflected: bool = false
		for mesh: MeshInstance3D in _meshes(_live(id)):
			for surface: int in mesh.mesh.get_surface_count():
				var finish: ShaderMaterial = mesh.get_active_material(surface) as ShaderMaterial
				if finish == null or finish.shader == null: continue
				var code: String = finish.shader.code
				if code.contains("specular_disabled") or _zeroes_dielectric_ibl(code) or not code.contains("SPECULAR ="): continue
				for uniform: Dictionary in finish.shader.get_shader_uniform_list():
					if str(uniform.name) not in ["sheen_strength", "gloss_strength"]: continue
					var value: Variant = finish.get_shader_parameter(str(uniform.name))
					if value is float and float(value) > .05: reflected = true
		if not reflected: reflection_errors.append(id)
	check("actual cafe enamel and steel retain an enabled reflection path with nonzero bound strength", reflection_errors.is_empty(), str(reflection_errors))
	var stock_errors: Array[String] = []
	var stock_count: int = 0
	var stock_models: Dictionary = {}
	for row: Dictionary in main.shop_life.content.products:
		var support: Node3D = row.support as Node3D
		var id: String = str(support.get_meta("model_id", ""))
		if id not in ["P_gondola", "W17_display_shelf", "I05_bread_shelf", "I02_cake_showcase"]: continue
		var product: Node3D = row.node as Node3D
		var box: AABB = product.global_transform * WorldBuilder.local_aabb(product)
		var surface_y: float = WorldBuilder.rendered_support_height(support, Vector3(box.get_center().x, 0, box.get_center().z), box.position.y + .025, true)
		stock_count += 1
		stock_models[id] = true
		if not is_finite(surface_y) or absf(surface_y - box.position.y) > .012: stock_errors.append(str(product.get_path()))
	check("live rebuilt racks keep every generated grocery pastry and cake on its real shelf", stock_count > 100 and stock_models.size() == 4 and stock_errors.is_empty(), str({"products": stock_count, "models": stock_models.keys(), "errors": stock_errors}))
	fixture.free()
	imported.clear()

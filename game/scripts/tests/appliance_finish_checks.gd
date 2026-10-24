extends RefCounted
## Check the actual imported surfaces and their live finish, not an appliance marker.
var t: Object
var main: Node
const METAL_PATH := "res://shaders/appliance_metal.gdshader"
const GLASS_PATH := "res://shaders/appliance_glass.gdshader"
const HOPPER_PATH := "res://shaders/appliance_hopper_glass.gdshader"
const IDS := ["P_deck_oven", "P_coffee_station", "I03_drink_fridge", "I07_ice_freezer"]

func _init(runner: Object) -> void:
	t = runner
	main = runner.main

func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("APPLIANCE_FINISH", label, ok, detail)

func _piece(id: String) -> Node3D:
	for candidate: Node in main.find_children("*", "Node3D", true, false):
		if str(candidate.get_meta("model_id", "")) == id:
			return candidate as Node3D
	return null

func _surfaces(root: Node3D, role: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if root == null:
		return found
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		for surface: int in mesh.mesh.get_surface_count():
			var original: Material = mesh.mesh.surface_get_material(surface)
			if original != null and original.resource_name == role:
				found.append({"mesh": mesh, "index": surface, "original": original, "active": mesh.get_active_material(surface)})
	return found

func _uses(material: Material, path: String) -> bool:
	return material is ShaderMaterial and material.shader != null and material.shader.resource_path == path

func _number(material: ShaderMaterial, parameter: String, fallback: float = -1.0) -> float:
	var value: Variant = material.get_shader_parameter(parameter)
	return float(value) if value is float or value is int else fallback

func _same_texture(value: Variant, expected: Texture2D) -> bool:
	if expected == null:
		return value == null
	if not value is Texture2D:
		return false
	return value == expected or (expected.resource_path != "" and value.resource_path == expected.resource_path)

func _same_color(value: Variant, expected: Color) -> bool:
	if value is Color:
		return (value as Color).is_equal_approx(expected)
	if value is Vector4:
		var vector: Vector4 = value
		return Color(vector.x, vector.y, vector.z, vector.w).is_equal_approx(expected)
	return false

func _metal(rows: Array[Dictionary], kind: int, count: int, wear: bool = true) -> bool:
	if rows.size() != count:
		return false
	for row: Dictionary in rows:
		var active: Material = row.active
		if not _uses(active, METAL_PATH):
			return false
		var finish: ShaderMaterial = active as ShaderMaterial
		var source: StandardMaterial3D = row.original as StandardMaterial3D
		if source == null or str(finish.get_meta("source_material", "")) != source.resource_name:
			return false
		if int(_number(finish, "finish_kind")) != kind or _number(finish, "gloss_strength") <= 0.0:
			return false
		if wear and _number(finish, "wear_strength") <= 0.0:
			return false
		var roughness: float = _number(finish, "roughness_value")
		if roughness <= 0.0 or roughness >= 1.0:
			return false
		if bool(finish.get_shader_parameter("has_albedo")) != (source.albedo_texture != null):
			return false
		if not _same_texture(finish.get_shader_parameter("albedo_tex"), source.albedo_texture) or not _same_color(finish.get_shader_parameter("base_color"), source.albedo_color):
			return false
	return true

func _glass(rows: Array[Dictionary], count: int, opacity: float) -> bool:
	if rows.size() != count:
		return false
	for row: Dictionary in rows:
		var active: Material = row.active
		if not (_uses(active, GLASS_PATH) or (_uses(active, HOPPER_PATH) and row.original.resource_name == "Coffee_HopperGlass")):
			return false
		var finish: ShaderMaterial = active as ShaderMaterial
		var source: StandardMaterial3D = row.original as StandardMaterial3D
		if source == null or str(finish.get_meta("source_material", "")) != source.resource_name:
			return false
		if absf(_number(finish, "opacity") - opacity) > .001 or _number(finish, "gloss_strength") <= 0.0:
			return false
		if not _same_color(finish.get_shader_parameter("base_color"), source.albedo_color):
			return false
	return true

func _kept(root: Node3D, roles: Array[String], count: int) -> bool:
	var total := 0
	for role: String in roles:
		var rows: Array[Dictionary] = _surfaces(root, role)
		if rows.is_empty():
			return false
		for row: Dictionary in rows:
			var active: Material = row.active
			if active == null or _uses(active, METAL_PATH) or _uses(active, GLASS_PATH):
				return false
			total += 1
	return total == count

func _area(rows: Array[Dictionary]) -> float:
	# Opaque parts may be batched by material. Measure the actual triangles rather
	# than requiring one draw surface per knob, pipe or cabinet door.
	var total: float = 0.0
	for row: Dictionary in rows:
		var mesh: MeshInstance3D = row.mesh as MeshInstance3D
		var arrays: Array = mesh.mesh.surface_get_arrays(int(row.index))
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for offset: int in range(0, count - 2, 3):
			var a: Vector3 = vertices[indices[offset] if not indices.is_empty() else offset]
			var b: Vector3 = vertices[indices[offset + 1] if not indices.is_empty() else offset + 1]
			var c: Vector3 = vertices[indices[offset + 2] if not indices.is_empty() else offset + 2]
			total += (b - a).cross(c - a).length() * .5
	return total

func _metal_area(rows: Array[Dictionary], kind: int, minimum: float) -> bool:
	return not rows.is_empty() and _area(rows) >= minimum and _metal(rows, kind, rows.size())

func _contains_geometry(root: Node3D, role: String, at: Vector3, radius: float) -> bool:
	for row: Dictionary in _surfaces(root, role):
		var mesh: MeshInstance3D = row.mesh as MeshInstance3D
		var transform: Transform3D = root.global_transform.affine_inverse() * mesh.global_transform
		var arrays: Array = mesh.mesh.surface_get_arrays(int(row.index))
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for offset: int in range(0, count - 2, 3):
			var a: Vector3 = transform * vertices[indices[offset] if not indices.is_empty() else offset]
			var b: Vector3 = transform * vertices[indices[offset + 1] if not indices.is_empty() else offset + 1]
			var c: Vector3 = transform * vertices[indices[offset + 2] if not indices.is_empty() else offset + 2]
			if _triangle_distance(at, a, b, c) < radius: return true
	return false

func _triangle_distance(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab: Vector3 = b - a
	var ac: Vector3 = c - a
	var normal: Vector3 = ab.cross(ac)
	if normal.length_squared() > .000000000001:
		normal = normal.normalized()
		var projected: Vector3 = point - normal * normal.dot(point - a)
		var ap: Vector3 = projected - a
		var denominator: float = ab.dot(ab) * ac.dot(ac) - ab.dot(ac) * ab.dot(ac)
		if absf(denominator) > .000000000001:
			var u: float = (ac.dot(ac) * ap.dot(ab) - ab.dot(ac) * ap.dot(ac)) / denominator
			var v: float = (ab.dot(ab) * ap.dot(ac) - ab.dot(ac) * ap.dot(ab)) / denominator
			if u >= 0 and v >= 0 and u + v <= 1: return point.distance_to(projected)
	return minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, a, b)), minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point, b, c)), point.distance_to(Geometry3D.get_closest_point_to_segment(point, c, a))))

func _kept_roles(root: Node3D, roles: Array[String]) -> bool:
	for role: String in roles:
		var rows: Array[Dictionary] = _surfaces(root, role)
		if rows.is_empty() or _area(rows) < .001: return false
		for row: Dictionary in rows:
			var active: Material = row.active
			if active == null or _uses(active, METAL_PATH) or _uses(active, GLASS_PATH): return false
	return true

func _unchanged_geometry() -> Array[String]:
	var changed: Array[String] = []
	for id: String in IDS:
		var live: Node3D = _piece(id)
		var scene: PackedScene = WorldBuilder.model_scene(id)
		if live == null or scene == null:
			changed.append(id + ": missing model")
			continue
		var imported: Node3D = scene.instantiate() as Node3D
		var original_meshes: Dictionary = {}
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(imported):
			original_meshes[str(imported.get_path_to(mesh))] = mesh
		# Existing runtime labels and shop stock are not part of the imported GLB.
		# Compare every original mesh, allowing those independent attached displays.
		for path: String in original_meshes:
			var original: MeshInstance3D = original_meshes[path] as MeshInstance3D
			var mesh: MeshInstance3D = live.get_node_or_null(path) as MeshInstance3D
			if mesh == null or original.mesh.get_surface_count() != mesh.mesh.get_surface_count() or original.transform != mesh.transform:
				changed.append(id + "/" + path + ": structure")
				continue
			for surface: int in mesh.mesh.get_surface_count():
				var before: Array = original.mesh.surface_get_arrays(surface)
				var after: Array = mesh.mesh.surface_get_arrays(surface)
				for stream: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
					if before[stream] != after[stream]:
						changed.append("%s/%s surface %d stream %d" % [id, path, surface, stream])
		imported.free()
	return changed

func run() -> void:
	var oven: Node3D = _piece("P_deck_oven")
	var coffee: Node3D = _piece("P_coffee_station")
	var fridge: Node3D = _piece("I03_drink_fridge")
	var freezer: Node3D = _piece("I07_ice_freezer")
	check("oven enamel keeps its authored atlas under the local reflective finish", _metal(_surfaces(oven, "Oven_MaintainedEnamel"), 0, 1))
	# The broad control/rack assembly and four bright handle end caps have
	# different finishes. The cap/mount role measures .03042 m² in the GLB.
	var oven_hardware: bool = _metal_area(_surfaces(oven, "Oven_ControlPanel"), 1, .15) and _metal_area(_surfaces(oven, "Oven_BrushedSteel"), 1, .020)
	for level: float in [1.075, 1.635]:
		for side: float in [-.520, .290]:
			oven_hardware = oven_hardware and _contains_geometry(oven, "Oven_BrushedSteel", Vector3(side, level, .4918), .025)
	check("oven controls racks and all four real handle caps keep their distinct steel finishes", oven_hardware)
	check("both real oven panes remain transparent with a restrained reflection", _glass(_surfaces(oven, "Oven_HeatGlass"), 2, .16))
	check("oven heat seals heatproof handles and stone decks retain their separate nonmetal materials", _kept(oven, ["Oven_HeatSeal", "Oven_HeatproofHandle", "Oven_StoneDeck"], 3))
	var steel_rows: Array[Dictionary] = _surfaces(coffee, "BrushedSteel")
	var steel_present: bool = _metal_area(steel_rows, 1, .60)
	for at: Vector3 in [Vector3(-.14, 1.195, .116), Vector3(-.29, 1.09, .135), Vector3(-.05, 1.09, .135), Vector3(.13, .96, .23)]:
		steel_present = steel_present and _contains_geometry(coffee, "BrushedSteel", at, .06)
	check("espresso control body both group heads and steam wand retain real finished steel after batching", steel_present, "steel area=%.4f" % _area(steel_rows))
	check("both actual espresso cabinet pulls receive brass rather than steel", _metal_area(_surfaces(coffee, "Brass"), 2, .006) and _contains_geometry(coffee, "Brass", Vector3(-.24, .65, .345), .07) and _contains_geometry(coffee, "Brass", Vector3(.24, .65, .345), .07))
	var painted_parts: Array[Dictionary] = _surfaces(coffee, "Cream")
	painted_parts.append_array(_surfaces(coffee, "Sage"))
	check("espresso timber coffee rubber paint and transparent hopper keep distinct materials after batching", _kept_roles(coffee, ["Hyper3D_TimberAtlas", "Coffee", "Charcoal"]) and _metal_area(painted_parts, 0, 1.5) and _glass(_surfaces(coffee, "Coffee_HopperGlass"), 1, .12))
	check("cold cabinet shelves and pulls retain different steel and brass roles", _metal(_surfaces(fridge, "BrushedSteel"), 1, 4) and _metal(_surfaces(fridge, "Brass"), 2, 2))
	check("both cold cabinet glass doors preserve their clear twelve percent tint", _glass(_surfaces(fridge, "Glass"), 2, .12))
	var freezer_paint: Array[Dictionary] = _surfaces(freezer, "freezer_white")
	freezer_paint.append_array(_surfaces(freezer, "freezer_band"))
	check("freezer lid frames baskets and ventilation keep steel while shell keeps enamel and casters stay rubber", _metal_area(_surfaces(freezer, "freezer_trim"), 1, .35) and _metal_area(freezer_paint, 0, 2.0) and _kept_roles(freezer, ["castor", "freezer_liner", "freezer_seal"]))
	var recessed_stock: bool = freezer != null and _glass(_surfaces(freezer, "freezer_glass"), 2, .08) and _surfaces(freezer, "icecream").is_empty()
	if recessed_stock:
		recessed_stock = _contains_geometry(freezer, "freezer_liner", Vector3(0, .44, 0), .025)
		var stock_count: int = 0
		for stock_mesh: MeshInstance3D in WorldBuilder.find_meshes(freezer):
			if not str(stock_mesh.name).begins_with("Stock_"):
				continue
			var stock_transform: Transform3D = freezer.global_transform.affine_inverse() * stock_mesh.global_transform
			var stock_bounds: AABB = stock_transform * stock_mesh.get_aabb()
			recessed_stock = recessed_stock and stock_bounds.size.y >= .045 and stock_bounds.end.y <= .733 and stock_bounds.position.y >= .49
			stock_count += 1
		recessed_stock = recessed_stock and stock_count >= 12
	check("freezer has two clear sliding panes above a 39cm cavity and fourteen solid recessed packages", recessed_stock)
	var changed: Array[String] = _unchanged_geometry()
	check("finishing preserves every imported node transform vertex normal UV and index stream", changed.is_empty(), str(changed))

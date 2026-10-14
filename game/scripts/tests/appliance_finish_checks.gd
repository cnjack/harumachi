extends RefCounted
## Check the actual imported surfaces and their live finish, not an appliance marker.
var t: Object
var main: Node
const METAL_PATH := "res://shaders/appliance_metal.gdshader"
const GLASS_PATH := "res://shaders/appliance_glass.gdshader"
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
		if not _uses(active, GLASS_PATH):
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
	check("oven control and rack steel have a distinct highlight and subtle wear", _metal(_surfaces(oven, "Oven_ControlPanel"), 1, 1))
	check("both real oven panes remain transparent with a restrained reflection", _glass(_surfaces(oven, "Oven_HeatGlass"), 2, .16))
	check("oven heat seals heatproof handles and stone decks retain their separate nonmetal materials", _kept(oven, ["Oven_HeatSeal", "Oven_HeatproofHandle", "Oven_StoneDeck"], 3))
	check("all six espresso steel parts receive the steel finish", _metal(_surfaces(coffee, "BrushedSteel"), 1, 6))
	check("both espresso cabinet pulls receive brass rather than steel", _metal(_surfaces(coffee, "Brass"), 2, 2))
	var painted_parts: Array[Dictionary] = _surfaces(coffee, "Cream")
	painted_parts.append_array(_surfaces(coffee, "Sage"))
	check("espresso wood grounds and rubber stay distinct while cups and paint keep a nonmetal enamel finish", _kept(coffee, ["Cedar", "CedarDark", "Coffee", "Charcoal"], 11) and _metal(painted_parts, 0, 12))
	check("cold cabinet shelves and pulls retain different steel and brass roles", _metal(_surfaces(fridge, "BrushedSteel"), 1, 4) and _metal(_surfaces(fridge, "Brass"), 2, 2))
	check("both cold cabinet glass doors preserve their clear twelve percent tint", _glass(_surfaces(fridge, "Glass"), 2, .12))
	var freezer_paint: Array[Dictionary] = _surfaces(freezer, "freezer_white")
	freezer_paint.append_array(_surfaces(freezer, "freezer_band"))
	check("freezer lid trim gains metal while white blue paint keeps its enamel role and castors remain unchanged", _metal(_surfaces(freezer, "freezer_trim"), 1, 1) and _metal(freezer_paint, 0, 2) and _kept(freezer, ["castor"], 1))
	var picture_rows: Array[Dictionary] = _surfaces(freezer, "icecream")
	var picture_ok: bool = _metal(picture_rows, 3, 1, false)
	if picture_ok:
		var finish: ShaderMaterial = picture_rows[0].active as ShaderMaterial
		var source: StandardMaterial3D = picture_rows[0].original as StandardMaterial3D
		picture_ok = is_equal_approx(_number(finish, "opacity"), 1.0) and source.emission_texture != null and bool(finish.get_shader_parameter("has_emission")) and _same_texture(finish.get_shader_parameter("emission_tex"), source.emission_texture) and _same_color(finish.get_shader_parameter("emission_color"), source.emission * source.emission_energy_multiplier)
	check("freezer contents remain an opaque authored picture with their original emissive texture", picture_ok)
	var changed: Array[String] = _unchanged_geometry()
	check("finishing preserves every imported node transform vertex normal UV and index stream", changed.is_empty(), str(changed))

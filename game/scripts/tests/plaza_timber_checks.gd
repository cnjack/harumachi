extends RefCounted
## Sample actual imported UVs and active materials. Equal-light native images
## remain the visual acceptance; this catches the reported pale/dark mismatch.
const IDS: Array[String] = ["A12_bench", "P01", "P03", "P05", "P09", "P10", "MS14_event_board"]
const COURTYARD := Rect2(-13.0, -5.5, 30.0, 29.5)
var t: Node
var main: Node
var images: Dictionary = {}

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("PLAZA_TIMBER", label, ok, detail)

func _value(material: Material, name: String, fallback: Variant) -> Variant:
	if not material is ShaderMaterial: return fallback
	var declared: bool = false
	for uniform: Dictionary in (material as ShaderMaterial).shader.get_shader_uniform_list():
		if str(uniform.name) == name: declared = true; break
	if not declared: return fallback
	var value: Variant = (material as ShaderMaterial).get_shader_parameter(name)
	return value if value != null else fallback

func _luminance(colour: Color) -> float:
	return colour.r * .2126 + colour.g * .7152 + colour.b * .0722

func _pixel(texture: Texture2D, uv: Vector2) -> Color:
	if texture == null: return Color.WHITE
	var key: int = texture.get_instance_id()
	if not images.has(key):
		var image: Image = texture.get_image()
		if image.is_compressed(): image.decompress()
		images[key] = image
	var pixels: Image = images[key]
	var x: int = clampi(floori(fposmod(uv.x, 1.0) * pixels.get_width()), 0, pixels.get_width() - 1)
	var y: int = clampi(floori(fposmod(uv.y, 1.0) * pixels.get_height()), 0, pixels.get_height() - 1)
	return pixels.get_pixel(x, y).srgb_to_linear()

func _is_timber(id: String, role: String) -> bool:
	return role.begins_with("CedarAge_") or role == "P09_Cedar_Maintained" or id in ["A12_bench", "P03", "MS14_event_board"]

func _surface_sample(mesh: MeshInstance3D, surface: int, source: StandardMaterial3D) -> Vector4:
	var arrays: Array = mesh.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var material: Material = mesh.get_active_material(surface)
	var has_tint: bool = bool(_value(material, "has_finish_tint", false))
	var tone: Color = _value(material, "finish_tint", Color.WHITE)
	var reference: float = float(_value(material, "authored_fibre_reference", .65))
	var detail: float = float(_value(material, "authored_detail_strength", 0.0))
	var atlas: bool = int(_value(material, "atlas_mode", 0)) > 0
	var colour_sum := Vector3.ZERO
	var area_sum: float = 0.0
	var count: int = indices.size() if not indices.is_empty() else vertices.size()
	var step_size: int = maxi(1, floori(float(count) / 9000.0)) * 3
	for offset: int in range(0, count - 2, step_size):
		var a: int = indices[offset] if not indices.is_empty() else offset
		var b: int = indices[offset + 1] if not indices.is_empty() else offset + 1
		var c: int = indices[offset + 2] if not indices.is_empty() else offset + 2
		var weight: float = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length() * .5
		if weight < .00000001: continue
		var coords: Vector2 = (uv[a] + uv[b] + uv[c]) / 3.0 if not uv.is_empty() else Vector2.ZERO
		coords = coords * Vector2(source.uv1_scale.x, source.uv1_scale.y) + Vector2(source.uv1_offset.x, source.uv1_offset.y)
		var fibre: Color = _pixel(source.albedo_texture, coords)
		var original: Color = fibre * source.albedo_color.srgb_to_linear()
		if original.r <= original.g * 1.08 or original.g <= original.b * 1.04 or minf(original.r, minf(original.g, original.b)) >= .82: continue
		var result: Color = original
		if has_tint:
			var contrast: float = clampf(1.0 + (_luminance(fibre) - reference) * detail, .72, 1.15) if source.albedo_texture != null else 1.0
			var timber: float = 1.0
			if atlas:
				timber = smoothstep(1.08, 1.24, original.r / maxf(original.g, .005)) * smoothstep(1.04, 1.22, original.g / maxf(original.b, .005))
				timber *= 1.0 - smoothstep(.66, .82, minf(original.r, minf(original.g, original.b)))
			result = original.lerp(tone.srgb_to_linear() * contrast, timber)
		colour_sum += Vector3(result.r, result.g, result.b) * weight
		area_sum += weight
	return Vector4(colour_sum.x, colour_sum.y, colour_sum.z, area_sum)

func _roots() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node: Node in main.find_children("*", "Node3D", true, false):
		var model: Node3D = node as Node3D
		var id: String = str(model.get_meta("model_id", model.get_meta("wind_model_id", "")))
		if id not in IDS or not COURTYARD.has_point(Vector2(model.global_position.x, model.global_position.z)) or absf(model.global_position.y) > .5: continue
		result.append(model)
	return result

func run() -> void:
	var saved: Array = GameState.placements.duplicate(true)
	# Exercise the player's actual placement path, including a rotated reload.
	GameState.placements.append({"uid": -424, "item": "picnic_table", "x": -2.0, "z": 5.5, "rot": 1})
	GameState.placements_changed.emit()
	await t.frames(2)
	var totals: Dictionary = {}
	var coverage_errors: Array[String] = []
	var preserved_errors: Array[String] = []
	var nonwood_errors: Array[String] = []
	var pale_surface_errors: Array[String] = []
	var wood_count: int = 0
	var nonwood_count: int = 0
	for model: Node3D in _roots():
		var id: String = str(model.get_meta("model_id", model.get_meta("wind_model_id", "")))
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
			for surface: int in mesh.mesh.get_surface_count():
				var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if source == null: continue
				var active: Material = mesh.get_active_material(surface)
				if not _is_timber(id, source.resource_name):
					nonwood_count += 1
					if bool(_value(active, "has_finish_tint", false)): nonwood_errors.append(id + "/" + source.resource_name)
					continue
				wood_count += 1
				var key: String = id + "/" + source.resource_name
				if not active is ShaderMaterial or active.shader != FurnitureWoodFinish.SHADER or not bool(_value(active, "has_finish_tint", false)):
					coverage_errors.append(key)
				if _value(active, "albedo_tex", null) != source.albedo_texture or _value(active, "base_color", Color.TRANSPARENT) != source.albedo_color:
					preserved_errors.append(key)
				var sample: Vector4 = _surface_sample(mesh, surface, source)
				totals[id] = (totals.get(id, Vector4.ZERO) as Vector4) + sample
				if sample.w > .000001:
					var surface_mean: float = _luminance(Color(sample.x, sample.y, sample.z) / sample.w)
					if surface_mean < .045 or surface_mean > .155:
						pale_surface_errors.append("%s/%s %.4f" % [key, str(mesh.name), surface_mean])
	var minimum: float = INF
	var maximum: float = -INF
	var means: Dictionary = {}
	for id: String in totals:
		var total: Vector4 = totals[id]
		var mean := Color(total.x, total.y, total.z) / maxf(total.w, .000001)
		var luminance: float = _luminance(mean)
		means[id] = snappedf(luminance, .0001)
		minimum = minf(minimum, luminance)
		maximum = maxf(maximum, luminance)
	check("the seven courtyard wood assets stay within one cedar albedo range", totals.size() == 7 and maximum - minimum <= .10 and maximum <= .35 and minimum >= .045, str({"linear_luminance": means, "spread": maximum - minimum}))
	check("all seven courtyard assets use dark brown timber rather than the rejected pale honey finish", totals.size() == 7 and minimum >= .06 and maximum <= .14 and maximum - minimum <= .045, str({"linear_luminance": means, "spread": maximum - minimum}))
	check("every sampled wooden surface stays dark without hiding pale boards inside an averaged asset", wood_count > 15 and pale_surface_errors.is_empty(), str(pale_surface_errors))
	check("all courtyard timber including the player's placed picnic table receives the cedar finish", wood_count > 15 and coverage_errors.is_empty(), str({"surfaces": wood_count, "errors": coverage_errors}))
	check("cedar calibration retains original images and source material tints", wood_count > 15 and preserved_errors.is_empty(), str(preserved_errors))
	check("canvas foliage steel enamel and stage pennants are not recoloured as wood", nonwood_count >= 8 and nonwood_errors.is_empty(), str({"surfaces": nonwood_count, "errors": nonwood_errors}))
	var ignored: Node3D = main.world.spawn("A12_bench", Vector3(60, 0, 50), 90, 0)
	var excluded: bool = not ignored.has_meta("plaza_cedar_surfaces")
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(ignored):
		for surface: int in mesh.mesh.get_surface_count(): excluded = excluded and not bool(_value(mesh.get_active_material(surface), "has_finish_tint", false))
	ignored.queue_free()
	check("outdoor benches outside the courtyard keep their original timber palette", excluded)
	var table: Node3D = main.placement.placed_nodes.get(-424) as Node3D
	var first: Vector4 = Vector4.ZERO
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(table):
		for surface: int in mesh.mesh.get_surface_count(): first += _surface_sample(mesh, surface, mesh.mesh.surface_get_material(surface) as StandardMaterial3D)
	GameState.placements.back().rot = 3
	GameState.placements_changed.emit()
	await t.frames(2)
	table = main.placement.placed_nodes.get(-424) as Node3D
	var second: Vector4 = Vector4.ZERO
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(table):
		for surface: int in mesh.mesh.get_surface_count(): second += _surface_sample(mesh, surface, mesh.mesh.surface_get_material(surface) as StandardMaterial3D)
	check("rotating and rebuilding a placed table retains its UV fibre colour", first.w > 1.0 and first.distance_to(second) < .00001 and table.has_meta("plaza_cedar_surfaces"), str({"before": first, "reloaded": second}))
	GameState.placements = saved
	GameState.placements_changed.emit()
	await t.frames(2)

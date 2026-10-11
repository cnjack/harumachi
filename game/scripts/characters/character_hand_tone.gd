extends RefCounted
## Correct Aoi's orange palm paint using the original skin's hand weights.
## Mesh, UV, LOD, skin, animation and embedded images remain untouched.
const TONE = preload("res://shaders/character_hand_tone.gdshader")
static var cache: Dictionary = {}

static func clear_cache() -> void:
	cache.clear()

static func apply(model: Node) -> void:
	if OS.get_cmdline_user_args().has("--hand-tone-before") or model.has_meta("hand_tone_stats"): return
	var rig: Node = model.find_child("Rig", true, false)
	if rig == null or not rig.has_meta("extras"): return
	if str((rig.get_meta("extras") as Dictionary).get("character_id", "")) != "aoi": return
	if not model.tree_exiting.is_connected(clear_cache): model.tree_exiting.connect(clear_cache)
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty(): return
	var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
	for source: MeshInstance3D in WorldBuilder.find_meshes(model):
		if source.skin == null: continue
		var key: int = source.mesh.get_instance_id()
		if not cache.has(key): cache[key] = build(source, skeleton)
		var data: Dictionary = cache[key]
		if data.is_empty(): continue
		source.set_meta("hand_tone_original_mesh", source.mesh)
		source.set_meta("hand_tone_original_materials", data.original_materials)
		for surface: int in source.mesh.get_surface_count(): source.set_surface_override_material(surface, data.materials[surface])
		source.set_meta("hand_tone_material", true)
		model.set_meta("hand_tone_stats", data.stats)

static func build(source: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	if source.skin.get_bind_count() > 128: return {}
	var hand_bind := PackedFloat32Array()
	hand_bind.resize(128)
	var side_bind: Array[String] = []
	var forearm_bind: Array[bool] = []
	for index: int in source.skin.get_bind_count():
		var joint: int = source.skin.get_bind_bone(index)
		if joint < 0: joint = skeleton.find_bone(source.skin.get_bind_name(index))
		var bone_name: String = skeleton.get_bone_name(joint) if joint >= 0 else ""
		var side: String = "L" if bone_name.contains("LeftHand") else "R" if bone_name.contains("RightHand") else ""
		side_bind.append(side)
		hand_bind[index] = 0.0 if side.is_empty() else 1.0
		forearm_bind.append(bone_name.contains("ForeArm"))
	var stats: Dictionary = {"left_vertices": 0, "right_vertices": 0, "triangles": 0, "source_mesh": source.mesh.resource_path, "source_unchanged": true, "rendering": "opaque_source_mesh", "original_streams_preserved": true}
	var original_materials: Array[Material] = []
	var materials: Array[Material] = []
	for surface: int in source.mesh.get_surface_count():
		var material: BaseMaterial3D = source.get_active_material(surface) as BaseMaterial3D
		if material == null or material.albedo_texture == null: return {}
		original_materials.append(material)
		var arrays: Array = source.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var per: int = bones.size() / positions.size()
		# Aoi currently imports with four weights; re-review a future replacement.
		if per != 4: return {}
		var mask := PackedFloat32Array()
		mask.resize(positions.size())
		var image: Image = material.albedo_texture.get_image()
		if image.is_compressed(): image.decompress()
		var samples: Array[Color] = []
		for vertex: int in positions.size():
			var left := 0.0
			var right := 0.0
			var forearm := 0.0
			for influence: int in per:
				var bind: int = bones[vertex * per + influence]
				var weight: float = weights[vertex * per + influence]
				if side_bind[bind] == "L": left += weight
				if side_bind[bind] == "R": right += weight
				if forearm_bind[bind]: forearm += weight
			mask[vertex] = left + right
			if left > .8: stats.left_vertices += 1
			if right > .8: stats.right_vertices += 1
			if forearm > .55 and mask[vertex] < .1:
				var painted: Color = image.get_pixel(clampi(int(uv[vertex].x * image.get_width()), 0, image.get_width() - 1), clampi(int(uv[vertex].y * image.get_height()), 0, image.get_height() - 1))
				if painted.v > .5 and painted.s > .12 and painted.s < .42 and painted.r - painted.g > .03 and painted.g - painted.b > .03: samples.append(painted)
		for triangle: int in range(0, indices.size(), 3):
			if maxf(mask[indices[triangle]], maxf(mask[indices[triangle + 1]], mask[indices[triangle + 2]])) >= .05: stats.triangles += 1
		var palette := Color(.90, .79, .66)
		if not samples.is_empty():
			var reds: Array[float] = []
			var greens: Array[float] = []
			var blues: Array[float] = []
			for sample: Color in samples:
				reds.append(sample.r); greens.append(sample.g); blues.append(sample.b)
			reds.sort(); greens.sort(); blues.sort()
			var middle: int = samples.size() / 2
			palette = Color(reds[middle], greens[middle], blues[middle])
		var tone := ShaderMaterial.new()
		tone.shader = TONE
		tone.set_shader_parameter("diffuse", material.albedo_texture)
		tone.set_shader_parameter("skin_color", palette)
		tone.set_shader_parameter("hand_bind_mask", hand_bind)
		tone.set_shader_parameter("roughness_value", material.roughness)
		tone.set_shader_parameter("specular_value", material.metallic_specular)
		tone.set_shader_parameter("metallic_value", material.metallic)
		tone.set_shader_parameter("albedo_factor", material.albedo_color)
		tone.render_priority = material.render_priority
		materials.append(tone)
		stats["palette"] = [palette.r, palette.g, palette.b]
		stats["palette_samples"] = samples.size()
		stats["influences"] = per
		stats["lod_levels"] = (RenderingServer.mesh_get_surface(source.mesh.get_rid(), surface).get("lods", []) as Array).size()
		var properties: Dictionary = {}
		for property: String in ["albedo_color", "metallic", "metallic_specular", "roughness", "diffuse_mode", "specular_mode", "shading_mode", "cull_mode", "normal_enabled", "ao_enabled", "rim_enabled", "emission_enabled", "backlight_enabled", "disable_receive_shadows", "disable_ambient_light", "disable_fog", "vertex_color_use_as_albedo", "vertex_color_is_srgb", "uv1_scale", "uv1_offset", "texture_filter"]: properties[property] = str(material.get(property))
		stats["original_material"] = properties
	return {"materials": materials, "stats": stats, "original_materials": original_materials}

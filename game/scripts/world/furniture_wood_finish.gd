class_name FurnitureWoodFinish
extends RefCounted
## Small, local signs of use on furniture. Original textures, UVs and geometry stay intact.
const SHADER: Shader = preload("res://shaders/furniture_wood.gdshader")
const PROFILES := {
	"I04_shop_counter": 0, "I02_cake_showcase": 0, "P_coffee_station": 0,
	"P_offer_stand": 0, "P09": 0, "J01_kitchen_counter": 0,
	"P_cafe_table": 1, "P_community_table": 1, "P_long_table": 1,
	"P_reading_chair": 1, "J03_dining_set": 1, "J07_kotatsu": 1,
	"W13_cedar_worktable": 2, "P08": 2,
	"A12_bench": 3,
	"I05_bread_shelf": 4, "W17_display_shelf": 4, "P_low_bookcase": 4,
	"I03_bookshelf": 4, "J05_dish_cabinet": 4, "G07_hall_cabinet": 4,
	"G01_getabako": 4, "J09_tansu": 4, "P_gondola": 4,
}
# These older assets use a single mixed atlas. Keep the image and restrict wear
# to warm timber pixels; dining/low tables additionally use their actual top bounds.
const ATLAS_IDS: Array[String] = ["J01_kitchen_counter", "J03_dining_set", "J07_kotatsu", "I03_bookshelf", "J05_dish_cabinet", "G07_hall_cabinet", "G01_getabako", "J09_tansu", "P_gondola"]
static var _parts: Dictionary = {}

static func apply(root: Node3D, id: String) -> void:
	if root == null or not PROFILES.has(id):
		return
	var count: int = 0
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		if mesh.mesh == null:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var active: Material = mesh.get_active_material(surface)
			if active is ShaderMaterial and (active as ShaderMaterial).shader == SHADER:
				count += 1
				continue
			var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var role: String = source.resource_name.to_lower()
			var atlas: bool = id in ATLAS_IDS
			if not atlas and not (role.contains("wood") or role.contains("cedar") or role.contains("oak")):
				continue
			if atlas and source.albedo_texture == null:
				continue
			var material: ShaderMaterial = _material(mesh, surface, source, root, int(PROFILES[id]), active)
			material.set_shader_parameter("structural", role.contains("dark") or role.contains("plug"))
			material.set_shader_parameter("atlas_mode", 1 if atlas else 0)
			if id == "J03_dining_set": material.set_shader_parameter("atlas_mode", 2)
			if id == "J07_kotatsu": material.set_shader_parameter("atlas_mode", 3)
			mesh.set_surface_override_material(surface, material)
			# A whole-mesh override would silently hide the new surface material.
			mesh.material_override = null
			count += 1
	if count > 0:
		root.set_meta("furniture_wood_surfaces", count)

static func profile_for(label: String) -> int:
	var name: String = label.to_lower()
	if "workbench" in name or "worktable" in name or "repair" in name or "cleaning" in name or "seed" in name or "flower" in name:
		return 2
	if "counter" in name or "returnstation" in name or "teastation" in name or "parcel" in name:
		return 0
	if "seat" in name or "bench" in name:
		return 3 if "outdoor" in name else 1
	return 1

static func board(mesh: MeshInstance3D, label: String, structural: bool = false) -> void:
	if mesh == null or mesh.mesh == null:
		return
	var source: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if source == null:
		return
	var material: ShaderMaterial = _material(mesh, 0, source, mesh, profile_for(label))
	material.set_shader_parameter("structural", structural)
	mesh.material_override = material
	mesh.set_meta("furniture_wood_profile", profile_for(label))
	mesh.set_meta("furniture_wood_board", true)

static func _components(mesh: Mesh, surface: int) -> Array[AABB]:
	var key: String = "%d/%d" % [mesh.get_instance_id(), surface]
	if _parts.has(key):
		var cached: Array[AABB] = _parts[key]
		return cached
	var parts: Array[AABB] = SurfaceFinish.timber_components(mesh, surface)
	if parts.is_empty() or parts.size() > 64:
		parts = [SurfaceFinish.surface_bounds(mesh, surface)]
	_parts[key] = parts
	return parts

static func _material(mesh: MeshInstance3D, surface: int, source: StandardMaterial3D, root: Node3D, profile: int, prior: Material = null) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var transform: Transform3D = root.global_transform.affine_inverse() * mesh.global_transform
	material.set_shader_parameter("wood_transform", Projection(transform))
	var box: AABB = SurfaceFinish.surface_bounds(mesh.mesh, surface)
	var root_size: Vector3 = (transform * box).size
	material.set_shader_parameter("grain_axis", 1 if root_size.y > maxf(root_size.x, root_size.z) else (2 if root_size.z > root_size.x else 0))
	material.set_shader_parameter("base_color", source.albedo_color)
	var grain_texture: Texture2D = SurfaceFinish.refined_grain()
	var grain_strength: float = .62
	# The prior treatment establishes warm cedar tops and darker structural wood.
	# Retain that art direction separately from the untouched GLB image/tint/UV.
	if prior is ShaderMaterial and (prior as ShaderMaterial).shader == SurfaceFinish.SHADER:
		var previous: ShaderMaterial = prior as ShaderMaterial
		var kind_value: Variant = previous.get_shader_parameter("finish_kind")
		var kind: int = int(kind_value) if kind_value != null else 0
		var tone: Variant = previous.get_shader_parameter("base_color")
		if tone is Color and kind in [0, 2]:
			material.set_shader_parameter("finish_tint", tone)
			material.set_shader_parameter("has_finish_tint", true)
		var old_grain: Variant = previous.get_shader_parameter("wood_tex")
		var old_strength: Variant = previous.get_shader_parameter("grain_strength")
		if old_grain is Texture2D: grain_texture = old_grain as Texture2D
		grain_strength = float(old_strength) if old_strength != null else 1.0
	material.set_shader_parameter("has_original", source.albedo_texture != null)
	if source.albedo_texture != null: material.set_shader_parameter("albedo_tex", source.albedo_texture)
	material.set_shader_parameter("uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
	material.set_shader_parameter("uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
	material.set_shader_parameter("grain_tex", grain_texture)
	material.set_shader_parameter("grain_strength", grain_strength)
	material.set_shader_parameter("use_profile", profile)
	material.set_shader_parameter("wear_strength", .65 if profile == 2 else (.48 if profile == 3 else .46))
	material.set_shader_parameter("sheen_strength", .42 if profile == 0 else (.30 if profile == 3 else .35))
	material.set_shader_parameter("environment_sheen", .18)
	material.set_shader_parameter("part_min", box.position)
	material.set_shader_parameter("part_size", box.size)
	var minima := PackedVector4Array()
	var maxima := PackedVector4Array()
	var parts: Array[AABB] = _components(mesh.mesh, surface)
	for part: AABB in parts:
		minima.append(Vector4(part.position.x, part.position.y, part.position.z, 0.))
		var horizontal: bool = part.size.y < maxf(part.size.x, part.size.z) * .60
		maxima.append(Vector4(part.end.x, part.end.y, part.end.z, 1.0 if horizontal else 0.0))
	material.set_shader_parameter("component_count", parts.size())
	material.set_shader_parameter("component_min", minima)
	material.set_shader_parameter("component_max", maxima)
	material.set_meta("furniture_source_material", source)
	material.set_meta("furniture_model_root", root.get_instance_id())
	return material

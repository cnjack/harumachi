extends RefCounted
## Inspect the displayed source, before any reversible mesh restoration.
var required: bool = false
var body: MeshInstance3D
var source_mesh: Mesh
var source_arrays: Array[int] = []
var source_paint: Array[Array] = []
var source_colour: Array[PackedStringArray] = []
var colour_writes: RegEx = RegEx.new()
var whitespace: RegEx = RegEx.new()

func prepare(world: WorldBuilder) -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/material_light_poc/shape/config.json"))
	required = bool(config.get("bakery_source_required",false))
	body = world.get_node("S02").find_child("Rodin_S02_body",true,false) as MeshInstance3D
	assert(body != null)
	source_mesh = body.mesh
	colour_writes.compile("(?:vec4\\s+c\\s*=|c\\.rgb\\s*[*/+\\-]?=|ALBEDO\\s*=)[^;]+;")
	whitespace.compile("\\s+")
	for surface: int in source_mesh.get_surface_count():
		source_arrays.append(hash(source_mesh.surface_get_arrays(surface)))
		source_paint.append(_paint(body.get_active_material(surface)))
		source_colour.append(_colour(body.get_active_material(surface)))

func _paint(material: Material) -> Array:
	if material is ShaderMaterial:
		var shader_material: ShaderMaterial = material as ShaderMaterial
		return [shader_material.get_shader_parameter("albedo_tex"),shader_material.get_shader_parameter("albedo_color")]
	if material is StandardMaterial3D:
		var standard: StandardMaterial3D = material as StandardMaterial3D
		return [standard.albedo_texture,standard.albedo_color]
	return []

func _colour(material: Material) -> PackedStringArray:
	var result: PackedStringArray = []
	if material is ShaderMaterial:
		for operation: RegExMatch in colour_writes.search_all((material as ShaderMaterial).shader.code):
			result.append(whitespace.sub(operation.get_string(),"",true))
	return result

func inspect() -> Dictionary:
	var arrays_retained: bool = body.mesh.get_surface_count() == source_arrays.size()
	var paint_retained: bool = arrays_retained
	var colour_retained: bool = arrays_retained
	if arrays_retained:
		for surface: int in source_arrays.size():
			arrays_retained = arrays_retained and hash(body.mesh.surface_get_arrays(surface)) == source_arrays[surface]
			paint_retained = paint_retained and _paint(body.get_active_material(surface)) == source_paint[surface]
			colour_retained = colour_retained and _colour(body.get_active_material(surface)) == source_colour[surface]
	var checks: Dictionary = {
		"original_body_rendered":body.is_visible_in_tree(),
		"original_mesh_bound":body.mesh == source_mesh,
		"original_geometry_normals_and_uv":arrays_retained,
		"original_albedo_texture_and_tint":paint_retained,
		"original_paint_colour_operations":colour_retained
	}
	return {"evaluated":true,"passed":not checks.values().has(false),"checks":checks,"surfaces":source_arrays.size()}

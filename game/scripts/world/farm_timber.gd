extends RefCounted
## Farm-only aged timber. Shared town/indoor instances and source atlases stay intact.
const ROAD := Color("a18d74")
const BED := Color(.70, .63, .54)
const FENCE := Color("694c36")
const IDS: Array[String] = ["F01_tool_shed", "F03_compost_bin", "F06_veggie_stand", "A12_bench", "A16_planter_box", "D01_wheelbarrow", "D02_rain_barrel", "D03_veg_crates", "D08_tool_rack", "D09_log_pile", "D12_flower_planter", "P_farm_gate", "P_signpost", "P_bridge", "MS03_garden_board", "N12_carrot_crate", "N13_empty_crate", "P_library_stool", "F08_soil_plot"]
# The mixed vegetable atlas is already separated from real cedar crate boards.
static func timber_surface(id: String, role: String) -> bool:
	if id == "D03_veg_crates": return role == "Diversity_clean_cedar"
	if id == "P_bridge": return role.to_lower().contains("wood") or role.begins_with("CedarAge_")
	return id in IDS

static func apply(root: Node3D, id: String) -> void:
	if id not in IDS or not root.is_inside_tree(): return
	var at: Vector3 = root.global_position
	if at.x < 640.0 or at.x > 860.0 or absf(at.y) > 10.0: return
	# Neighbour beds do not use PlotView; keep their timber/soil base consistent.
	# PlotView applies the same base before registering its wet-soil colours.
	if id == "F08_soil_plot":
		for bed_mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
			for bed_surface: int in bed_mesh.mesh.get_surface_count():
				var bed_source := bed_mesh.mesh.surface_get_material(bed_surface) as StandardMaterial3D
				if bed_source == null: continue
				var bed_material := bed_source.duplicate() as StandardMaterial3D
				bed_material.albedo_color *= BED
				bed_mesh.set_surface_override_material(bed_surface, bed_material)
		return
	var count := 0
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		if id == "P_library_stool" and str(mesh.name).begins_with("Bolt"): continue
		for surface: int in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or not timber_surface(id, source.resource_name): continue
			var active: Material = mesh.get_active_material(surface)
			if active is ShaderMaterial and active.get_meta("farm_timber", false):
				count += 1
				continue
			var material: ShaderMaterial = active.duplicate() as ShaderMaterial if active is ShaderMaterial and active.shader == FurnitureWoodFinish.SHADER else FurnitureWoodFinish._material(mesh, surface, source, root, 3, active)
			var pure: bool = id in ["P_bridge", "D03_veg_crates", "P_library_stool"]
			material.set_shader_parameter("atlas_mode", 0 if pure else 1)
			material.set_shader_parameter("has_finish_tint", true)
			material.set_shader_parameter("finish_tint", Color("755039") if id == "A12_bench" else Color("694a35"))
			material.set_shader_parameter("farm_timber_mask", not pure)
			material.set_shader_parameter("farm_finish", true)
			_piece_axes(material)
			material.set_shader_parameter("farm_preserve_hat", id == "D08_tool_rack")
			material.set_shader_parameter("farm_preserve_compost", id == "F03_compost_bin")
			# Flowers and harvested carrots sit above their wooden container.
			var wood_top: float = {"D12_flower_planter": .38, "A16_planter_box": .28, "N12_carrot_crate": .28}.get(id, 100.0)
			material.set_shader_parameter("farm_wood_top", wood_top)
			material.set_shader_parameter("authored_fibre_reference", .40)
			material.set_shader_parameter("authored_detail_strength", 2.8)
			material.set_shader_parameter("grain_strength", .2)
			material.set_shader_parameter("use_profile", 3)
			material.set_shader_parameter("wear_strength", .42)
			material.set_shader_parameter("sheen_strength", .13)
			material.set_shader_parameter("roughness_base", .93)
			material.set_shader_parameter("roughness_polished", .82)
			material.set_shader_parameter("reflectance", .20)
			# The gate's deeply shaded engraved face must remain readable.
			if id == "P_farm_gate":
				material.set_shader_parameter("finish_tint", Color("876347"))
				material.set_shader_parameter("authored_detail_strength", 1.8)
			material.set_meta("farm_timber", true)
			mesh.material_override = null
			mesh.set_surface_override_material(surface, material)
			count += 1
	if count: root.set_meta("farm_timber_surfaces", count)

static func _piece_axes(material: ShaderMaterial) -> void:
	# Preserve each joined timber's measured long axis in its own mesh space.
	var minima: PackedVector4Array = material.get_shader_parameter("component_min")
	var maxima: PackedVector4Array = material.get_shader_parameter("component_max")
	for index: int in mini(minima.size(), maxima.size()):
		var low: Vector4 = minima[index]
		var high: Vector4 = maxima[index]
		var size := Vector3(high.x - low.x, high.y - low.y, high.z - low.z)
		low.w = 1 if size.y > maxf(size.x, size.z) else (2 if size.z > size.x else 0)
		minima[index] = low
	material.set_shader_parameter("component_min", minima)

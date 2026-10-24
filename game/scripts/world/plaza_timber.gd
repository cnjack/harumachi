extends RefCounted
## One maintained cedar palette for the furniture in this courtyard. Imported
## images, UVs, small age differences and non-timber parts remain independent.
const IDS: Array[String] = ["A12_bench", "P01", "P03", "P05", "P09", "P10", "MS14_event_board"]
const COURTYARD := Rect2(-13.0, -5.5, 30.0, 29.5)
const CEDAR: Array[Color] = [Color("be8b55"), Color("ba8752"), Color("b78350"), Color("ac794a")]
# Area-weighted linear fibre means measured from each asset's actual UVs.
# art/tools/audit_plaza_timber.py records/rechecks these without changing images.
const FIBRE_MEAN := {
	"A12_bench": {"Hyper3D_OriginalAtlas_HFF14_outdoor_bench": .410687},
	"P01": {"CedarAge_0": .432991, "CedarAge_1": .509070, "CedarAge_2": .121833, "CedarAge_3": .160676},
	"P03": {"M_P03": .245652},
	"P09": {"P09_Cedar_Maintained": .409987},
	"P10": {"CedarAge_0": .440871, "CedarAge_1": .514373, "CedarAge_2": .121614, "CedarAge_3": .160684},
	"MS14_event_board": {"Hyper3D_OriginalAtlas_MS04_wall_plaque": .357791, "Hyper3D_OriginalAtlas_MS01_signpost.001": .275068, "Hyper3D_OriginalAtlas_MS01_signpost": .275068},
}

static func _timber(id: String, role: String) -> bool:
	if id in ["P01", "P05", "P10"]: return role.begins_with("CedarAge_")
	if id == "P09": return role == "P09_Cedar_Maintained"
	if id == "P03": return role == "M_P03"
	if id == "A12_bench": return role == "Hyper3D_OriginalAtlas_HFF14_outdoor_bench"
	if id == "MS14_event_board": return role.begins_with("Hyper3D_OriginalAtlas_MS0")
	return false

static func _age(id: String, role: String, part: String) -> int:
	if role.begins_with("CedarAge_"): return clampi(int(role.trim_prefix("CedarAge_")), 0, 3)
	if id == "MS14_event_board": return 0 if role.contains("wall_plaque") else 2
	if id == "A12_bench": return 2 if part.to_lower().ends_with("frame") else 0
	return 1

static func apply(root: Node3D, id: String) -> void:
	if root == null or id not in IDS or not root.is_inside_tree(): return
	var at: Vector3 = root.global_position
	# Farm/lake seats and room furniture retain their own finishes. Room models
	# use separate world-space origins; no whole-world name-based recolouring.
	if absf(at.y) > .5 or not COURTYARD.has_point(Vector2(at.x, at.z)): return
	var count: int = 0
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		if mesh.mesh == null: continue
		for surface: int in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or not _timber(id, source.resource_name): continue
			var active: Material = mesh.get_active_material(surface)
			if active is ShaderMaterial and active.get_meta("plaza_cedar", false):
				count += 1
				continue
			var material: ShaderMaterial
			if active is ShaderMaterial and (active as ShaderMaterial).shader == FurnitureWoodFinish.SHADER:
				material = active.duplicate() as ShaderMaterial
			else:
				material = FurnitureWoodFinish._material(mesh, surface, source, root, 3, active)
			var age: int = _age(id, source.resource_name, str(mesh.name))
			var generated: bool = source.resource_name.begins_with("Hyper3D_")
			material.set_shader_parameter("finish_tint", CEDAR[age])
			material.set_shader_parameter("has_finish_tint", true)
			material.set_shader_parameter("atlas_mode", 1 if generated or id == "P03" else 0)
			material.set_shader_parameter("generated_atlas", generated)
			material.set_shader_parameter("authored_fibre_reference", float(FIBRE_MEAN.get(id, {}).get(source.resource_name, .4)))
			material.set_shader_parameter("authored_detail_strength", .85 if id == "P03" else 1.65)
			material.set_shader_parameter("grain_strength", .35)
			material.set_shader_parameter("use_profile", 3)
			material.set_shader_parameter("wear_strength", .32)
			material.set_shader_parameter("sheen_strength", .24)
			material.set_shader_parameter("roughness_base", .88)
			material.set_shader_parameter("roughness_polished", .76)
			material.set_shader_parameter("reflectance", .22)
			material.set_meta("plaza_cedar", true)
			mesh.material_override = null
			mesh.set_surface_override_material(surface, material)
			count += 1
	if count > 0: root.set_meta("plaza_cedar_surfaces", count)

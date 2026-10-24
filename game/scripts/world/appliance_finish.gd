class_name ApplianceFinish
extends RefCounted
## Local enamel/steel/glass treatment. The source geometry and authored UVs stay intact.
const SHADER: Shader = preload("res://shaders/appliance_metal.gdshader")
const GLASS: Shader = preload("res://shaders/appliance_glass.gdshader")
const HOPPER_GLASS: Shader = preload("res://shaders/appliance_hopper_glass.gdshader")
const MODELS := ["P_deck_oven", "P_coffee_station", "I03_drink_fridge", "I07_ice_freezer", "I04_shop_counter"]

static func apply(root: Node3D, id: String) -> void:
	if id not in MODELS:
		return
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		for surface: int in mesh.mesh.get_surface_count():
			var original: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
			if original == null:
				continue
			var role: String = original.resource_name
			var profile: Dictionary = _profile(id, role)
			if profile.is_empty():
				continue
			var finish := ShaderMaterial.new()
			finish.shader = HOPPER_GLASS if bool(profile.get("hopper", false)) else (GLASS if bool(profile.get("glass", false)) else SHADER)
			finish.resource_name = role
			finish.set_meta("source_material", role)
			finish.set_meta("source_base", original.albedo_color)
			finish.set_shader_parameter("base_color", original.albedo_color)
			finish.set_shader_parameter("has_albedo", original.albedo_texture != null)
			finish.set_shader_parameter("albedo_tex", original.albedo_texture)
			finish.set_shader_parameter("has_emission", original.emission_enabled and original.emission_texture != null)
			finish.set_shader_parameter("emission_tex", original.emission_texture)
			finish.set_shader_parameter("emission_color", original.emission * original.emission_energy_multiplier if original.emission_enabled else Color.BLACK)
			finish.set_shader_parameter("opacity", original.albedo_color.a)
			finish.set_shader_parameter("gloss_strength", float(profile.gloss))
			finish.set_shader_parameter("uv_scale", Vector2(original.uv1_scale.x, original.uv1_scale.y))
			finish.set_shader_parameter("uv_offset", Vector2(original.uv1_offset.x, original.uv1_offset.y))
			if finish.shader == SHADER:
				finish.set_shader_parameter("finish_kind", int(profile.kind))
				finish.set_shader_parameter("roughness_value", float(profile.roughness))
				finish.set_shader_parameter("wear_strength", float(profile.wear))
				finish.set_shader_parameter("oven_surface", id == "P_deck_oven")
				finish.set_shader_parameter("part_transform", Projection(root.global_transform.affine_inverse() * mesh.global_transform))
			mesh.set_surface_override_material(surface, finish)
	root.set_meta("appliance_finish", true)

static func _profile(id: String, role: String) -> Dictionary:
	if id == "P_deck_oven":
		if role == "Oven_MaintainedEnamel":
			return {"kind": 0, "roughness": .48, "gloss": .18, "wear": .45}
		if role == "Oven_ControlPanel":
			return {"kind": 1, "roughness": .38, "gloss": .23, "wear": .26}
		if role == "Oven_BrushedSteel":
			return {"kind": 1, "roughness": .32, "gloss": .24, "wear": .16}
		if role == "Oven_HeatGlass":
			return {"glass": true, "gloss": .20}
	elif id in ["P_coffee_station", "I03_drink_fridge", "I04_shop_counter"]:
		if role == "BrushedSteel":
			return {"kind": 1, "roughness": .32, "gloss": .24, "wear": .16}
		if role == "Brass":
			return {"kind": 2, "roughness": .40, "gloss": .20, "wear": .18}
		if role in ["Sage", "Cream"]:
			# Painted cabinet/appliance casings and ceramic cups get a quiet broad finish.
			return {"kind": 0, "roughness": .55, "gloss": .10, "wear": .07}
		if role == "Glass" and id == "I03_drink_fridge":
			return {"glass": true, "gloss": .16}
		if role == "Coffee_HopperGlass" and id == "P_coffee_station":
			return {"glass": true, "hopper": true, "gloss": .18}
	elif id == "I07_ice_freezer":
		if role == "freezer_trim":
			return {"kind": 1, "roughness": .38, "gloss": .23, "wear": .18}
		if role in ["freezer_white", "freezer_band"]:
			return {"kind": 0, "roughness": .52, "gloss": .12, "wear": .07}
		if role == "freezer_glass":
			# Actual sliding panes reveal the recessed baskets and sealed stock in the source mesh.
			return {"glass": true, "gloss": .12}
	return {}

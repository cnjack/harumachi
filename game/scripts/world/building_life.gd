class_name BuildingLife
extends RefCounted
## Small summer movements and opening-hour displays on the individually designed houses.

const SHOP_IDS := {"S01": "store", "S02": "bakery", "S03": "florist", "S08": "zakka"}

static func add(building: Node3D, id: String) -> Dictionary:
	var lamps: Array[StandardMaterial3D] = []
	var displays: Array[Node3D] = []
	var cloth_count := 0
	for mesh_instance in WorldBuilder.find_meshes(building):
		if "__display" in mesh_instance.name:
			displays.append(mesh_instance)
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var material_name: String = source.resource_name
			if material_name.begins_with("cloth_noren") or material_name.begins_with("cloth_laundry") or material_name.begins_with("cloth_towel"):
				var cloth := ShaderMaterial.new()
				cloth.shader = load("res://shaders/house_cloth.gdshader")
				cloth.set_shader_parameter("albedo_tex", source.albedo_texture)
				cloth.set_shader_parameter("albedo_color", source.albedo_color)
				cloth.set_shader_parameter("textured", source.albedo_texture != null)
				# Provider atlas UVs are unrelated to the physical sewn edge.
				if id == "H02" or id == "S08":
					cloth.set_shader_parameter("physical_anchor", true)
					cloth.set_shader_parameter("cloth_top", 4.03 if id == "H02" else 2.20)
					cloth.set_shader_parameter("cloth_height", (0.68 if material_name.begins_with("cloth_towel") else 0.93) if id == "H02" else 1.01)
				mesh_instance.set_surface_override_material(surface, cloth)
				cloth_count += 1
			elif material_name == "lamp" or (id.begins_with("H") and (material_name == "glass" or material_name.begins_with("Tenant_curtain"))):
				source.emission_enabled = true
				source.emission = Color(1.0, 0.73, 0.39)
				lamps.append(source)
	building.set_meta("summer_cloth_surfaces", cloth_count)
	return {"id": id, "lamps": lamps, "displays": displays}

static func update(items: Array[Dictionary], minute: float, lamp_level: float) -> void:
	var hour: float = minute / 60.0
	for item in items:
		for material: StandardMaterial3D in item.lamps:
			material.emission_energy_multiplier = 0.32 * clampf(lamp_level, 0.0, 1.6)
		if not SHOP_IDS.has(item.id):
			continue
		var shop: Dictionary = GameState.shop(SHOP_IDS[item.id])
		var opened: bool = hour >= float(shop.open) and hour < float(shop.close) and int(shop.get("closed_weekday", -1)) != GameState.weekday()
		for display_node: Node3D in item.displays:
			display_node.visible = opened

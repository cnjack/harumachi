class_name TruckGlazing
extends RefCounted
## Retain source vehicle finishes and one thin layer for each real cab window.
const GLASS: Shader = preload("res://shaders/truck_glass.gdshader")

static func apply(root: Node3D) -> void:
	VehicleFinish.apply(root)
	var glazing := ShaderMaterial.new()
	glazing.shader = GLASS
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		if not mesh.name.begins_with("Glass_"):
			continue
		for surface: int in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, null)
		mesh.material_override = glazing
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

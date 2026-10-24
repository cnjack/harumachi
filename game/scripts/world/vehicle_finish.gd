class_name VehicleFinish
extends RefCounted
## Keep the authored paint, rubber and metal response through the toon pipeline.
## Materials are shared between repeated instances; no work runs per frame.
static var _materials: Dictionary = {}

static func apply(root: Node3D) -> void:
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		if mesh.mesh == null or str(mesh.name).begins_with("Glass_"):
			continue
		mesh.material_override = null
		for surface: int in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var key: int = source.get_instance_id()
			if not _materials.has(key):
				var finish: StandardMaterial3D = source.duplicate() as StandardMaterial3D
				finish.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				finish.specular_mode = BaseMaterial3D.SPECULAR_DISABLED if source.roughness >= .78 else BaseMaterial3D.SPECULAR_TOON
				finish.metallic_specular = minf(source.metallic_specular, .35)
				finish.set_meta("vehicle_finish", true)
				_materials[key] = finish
			mesh.set_surface_override_material(surface, _materials[key] as StandardMaterial3D)
	root.set_meta("vehicle_source_materials", true)

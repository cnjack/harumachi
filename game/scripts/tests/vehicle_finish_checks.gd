extends RefCounted
## Verify the actual imported materials survive both export and world assembly.
var t: Object
var main: Node

func _init(runner: Object) -> void:
	t = runner
	main = runner.main

func run() -> void:
	var vehicles: Array[Node3D] = []
	for node: Node in main.world.find_children("*", "Node3D", true, false):
		if node.get_meta("model_id", "") in ["B01_bus", "D07_kei_truck"]:
			vehicles.append(node as Node3D)
	t.check("VEHICLE_FINISH", "the bus and both loaded trucks use authored surface finishes", vehicles.size() == 3 and vehicles.all(func(vehicle: Node3D) -> bool: return vehicle.get_meta("vehicle_source_materials", false)))
	var trucks: Array[Node3D] = []
	for vehicle: Node3D in vehicles:
		var failures: Array[String] = []
		var lowest_roughness: float = 1.0
		var highest_roughness: float = 0.0
		var highest_metallic: float = 0.0
		var surfaces: int = 0
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(vehicle):
			if str(mesh.name).begins_with("Glass_") or str(mesh.get_path()).contains("SeatedDriver"):
				continue
			for surface: int in mesh.mesh.get_surface_count():
				var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				var active: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
				if source == null:
					continue
				surfaces += 1
				lowest_roughness = minf(lowest_roughness, source.roughness)
				highest_roughness = maxf(highest_roughness, source.roughness)
				highest_metallic = maxf(highest_metallic, source.metallic)
				if active == null or not active.get_meta("vehicle_finish", false):
					failures.append(str(mesh.name) + ": missing finish")
				elif not is_equal_approx(active.roughness, source.roughness) or not is_equal_approx(active.metallic, source.metallic) or active.albedo_texture != source.albedo_texture or not active.albedo_color.is_equal_approx(source.albedo_color):
					failures.append(str(mesh.name) + ": changed source response or texture")
		var identity: String = str(vehicle.get_meta("model_id")) + (" farm" if vehicle.global_position.x > 600 else " town")
		t.check("VEHICLE_FINISH", identity + " retains paint metal and rubber contrast from source", surfaces > 15 and lowest_roughness <= .45 and highest_roughness >= .85 and highest_metallic >= .45 and failures.is_empty(), JSON.stringify({"roughness": [lowest_roughness, highest_roughness], "metallic_max": highest_metallic, "errors": failures}))
		if vehicle.get_meta("model_id") == "D07_kei_truck":
			trucks.append(vehicle)
	var shared: bool = trucks.size() == 2
	var compared: int = 0
	if shared:
		for first_mesh: MeshInstance3D in WorldBuilder.find_meshes(trucks[0]):
			if str(first_mesh.name).begins_with("Glass_"):
				continue
			var second_mesh: MeshInstance3D = trucks[1].get_node_or_null(trucks[0].get_path_to(first_mesh)) as MeshInstance3D
			if second_mesh == null:
				shared = false
				continue
			for surface: int in first_mesh.mesh.get_surface_count():
				compared += 1
				shared = shared and first_mesh.get_active_material(surface) == second_mesh.get_active_material(surface)
	t.check("VEHICLE_FINISH", "repeated trucks share finishes instead of duplicating every material", shared and compared > 15, str(compared))

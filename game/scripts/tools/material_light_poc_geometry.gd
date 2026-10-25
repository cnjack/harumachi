extends RefCounted
## A separately exported bevel candidate; original meshes and all collisions survive.
var bindings: Array[Dictionary] = []
var report: Array[Dictionary] = []
var enabled: bool = false

func prepare(world: WorldBuilder) -> void:
	var packed: PackedScene = load("res://assets/material_light_poc/P_bridge_beveled.glb") as PackedScene
	var candidate_root: Node3D = packed.instantiate() as Node3D
	var candidates: Dictionary = {}
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(candidate_root):
		assert(mesh.transform.is_equal_approx(Transform3D.IDENTITY), "Candidate must retain the source coordinate system")
		candidates[str(mesh.name)] = mesh.mesh
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(world):
		if not str(world.get_path_to(mesh)).begins_with("Farm/Lakeside/P_bridge/"): continue
		assert(candidates.has(str(mesh.name)))
		var candidate: Mesh = candidates[str(mesh.name)] as Mesh
		var source: Mesh = mesh.mesh
		assert(candidate.get_surface_count() == source.get_surface_count())
		var error: float = maxf(source.get_aabb().position.distance_to(candidate.get_aabb().position),source.get_aabb().end.distance_to(candidate.get_aabb().end))
		assert(error < .03, "Bevel must not change bridge placement or dimensions")
		var vertices_before: int = 0
		var vertices_after: int = 0
		for index: int in range(source.get_surface_count()):
			assert(source.surface_get_material(index).resource_name == candidate.surface_get_material(index).resource_name, "Material slots must retain their meaning")
			vertices_before += source.surface_get_array_len(index)
			vertices_after += candidate.surface_get_array_len(index)
		bindings.append({"node":mesh,"original":source,"candidate":candidate})
		report.append({"part":mesh.name,"vertices_before":vertices_before,"vertices_after":vertices_after,"bounds_error_m":error,"material_slots":source.get_surface_count()})
	assert(bindings.size() == 5, "Expected all five original bridge parts")
	candidate_root.free()

func apply(value: bool) -> void:
	enabled = value
	for binding: Dictionary in bindings:
		(binding.node as MeshInstance3D).mesh = binding.candidate if value else binding.original

func source_signature(world: WorldBuilder) -> String:
	# Capture-only audit, between saved frames. No collision or placement is reset.
	var active: bool = enabled
	apply(false)
	var result: String = MaterialChoiceProfile._geometry_signature(world)
	apply(active)
	return result

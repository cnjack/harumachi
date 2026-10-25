extends RefCounted
## Regressions for pale farm timber and uniformly sliding fish, measured in the real scene.
var t: Node
var main: Node
func _init(runner: Node) -> void:
	t = runner
	main = runner.main
func check(label: String, ok: bool, detail: Variant = "") -> void:
	t.check("FARM_FISH_FEEDBACK", label, ok, str(detail))
func run() -> void:
	var sampler: RefCounted = load("res://scripts/tests/plaza_timber_checks.gd").new(t)
	for id: String in ["F01_tool_shed", "F03_compost_bin", "F06_veggie_stand", "A12_bench", "D08_tool_rack", "P_farm_gate", "MS03_garden_board", "P_library_stool", "P_bridge"]:
		var roots := 0
		var samples := Vector4.ZERO
		var original_texture := true
		var finished := 0
		for node: Node in main.find_children("*", "Node3D", true, false):
			if str(node.get_meta("model_id", "")) != id or node.global_position.x < 640.0 or node.global_position.x > 860.0 or absf(node.global_position.y) > 10.0: continue
			roots += 1
			for mesh: MeshInstance3D in WorldBuilder.find_meshes(node):
				for surface: int in mesh.mesh.get_surface_count():
					var source: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
					var active: Material = mesh.get_active_material(surface)
					if source == null: continue
					samples += sampler.call("_surface_sample", mesh, surface, source)
					if active is ShaderMaterial and bool(sampler.call("_value", active, "has_finish_tint", false)):
						finished += 1
						original_texture = original_texture and active.get_shader_parameter("albedo_tex") == source.albedo_texture
		var value: float = Vector3(samples.x, samples.y, samples.z).dot(Vector3(.2126, .7152, .0722)) / maxf(samples.w, .00001)
		check(id + " farm timber is dark with its original texture", roots > 0 and finished > 0 and samples.w > 0.0 and value < .23 and original_texture, {"instances": roots, "finished_surfaces": finished, "wood_linear_luminance": value, "original_texture": original_texture})
	var outside: Node3D = main.world.spawn("A12_bench", Vector3(40, 0, 42), 0, 0, main.world)
	check("town bench is not recoloured by farm weathering", outside != null and not outside.has_meta("farm_timber_surfaces"))
	outside.queue_free()
	var road_count := 0
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(main.world.farm):
		if not mesh.mesh is PlaneMesh: continue
		var material: Material = mesh.get_active_material(0)
		var tint: Color = sampler.call("_value", material, "tint", Color.WHITE)
		if tint.r > .5 and tint.r < .7 and tint.g > .45 and tint.g < .6 and tint.b < .5: road_count += 1
	check("farm gravel paths use a muted earth colour", road_count >= 7, road_count)
	var mg: MiniGame = load("res://scripts/minigames/mg_goldfish.gd").new()
	t.add_child(mg)
	await t.frames(2)
	mg.set_process(false)
	mg.rng.seed = 261025
	mg.mg_reset()
	var fishes: Array = mg.get("fish")
	var unique_materials: Dictionary = {}
	for item: Dictionary in fishes:
		if item.sprite.material is ShaderMaterial: unique_materials[item.sprite.material.get_instance_id()] = true
	check("each fish bends its own tail independently", unique_materials.size() == 13, unique_materials.size())
	mg.set("poi_dipped", false)
	var minima: Array[float] = []
	var maxima: Array[float] = []
	var bounded := true
	for item: Dictionary in fishes: minima.append(INF); maxima.append(0.)
	for frame: int in 720:
		for index: int in fishes.size():
			mg.call("_move_fish", index, 1.0 / 60.0)
			var item: Dictionary = fishes[index]
			minima[index] = minf(minima[index], item.vel.length())
			maxima[index] = maxf(maxima[index], item.vel.length())
			bounded = bounded and (mg.WATER as Rect2).has_point(item.pos)
	# Remove neighbours and boundaries: speed variation must come from propulsion,
	# not just slowing down when the steering vector turns near another fish.
	var isolated: Array[Dictionary] = [fishes[0]]
	mg.set("fish", isolated)
	var glide_min := INF
	var glide_max := 0.0
	for frame: int in 480:
		isolated[0].pos = mg.WATER.get_center()
		isolated[0].turn = 0.0
		isolated[0].turn_wait = 100.0
		mg.call("_move_fish", 0, 1.0 / 60.0)
		glide_min = minf(glide_min, isolated[0].vel.length())
		glide_max = maxf(glide_max, isolated[0].vel.length())
	check("unobstructed fish alternates propulsion and gliding", glide_max > glide_min * 1.5 and glide_min > 50.0 and glide_max < 175.0, {"min_speed": glide_min, "max_speed": glide_max})
	check("burst swimming remains inside the water", bounded)
	check("tail motion does not squash the entire fish", (fishes[0].sprite.scale as Vector2).is_equal_approx(Vector2.ONE * float(fishes[0].depth)))
	check("catch size score paper cost and round duration retain their rules", mg.PAPER_RADIUS == 53.0 and mg.FISH_POINTS == [10, 20, 30, 60] and mg.FISH_WEIGHT == [8.0, 13.0, 17.0, 29.0] and mg.mg_info().duration == 60.0 and mg.get("poi_left") == 3)
	mg.queue_free()
	await t.frames(2)

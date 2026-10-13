extends RefCounted
## Physical checks for the reviewed singles; visual quality remains a separate native review.
var t: Node
var main: Node


func _init(runner: Node) -> void:
	t = runner
	main = runner.main


func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("MODEL_DIVERSITY", label, ok, detail)


func _contexts() -> Dictionary:
	return {"town": main.world, "farm": main.world.farm, "home": main.world.house,
		"store": main.world.interiors.store, "festival": main.world.fest_nodes.natsumatsuri}


func ground_clearance() -> void:
	var contexts: Dictionary = _contexts()
	var tested: int = 0
	for entry: Array in ModelDiversity.USES:
		var id: String = entry[1]
		var context: String = entry[0]
		if context not in ["farm", "town"] or str(entry[4]) != "" or id.begins_with("T") or not ModelDiversity.contains(id):
			continue
		var item: Node3D = contexts[context].get_node_or_null("ModelDiversity/" + id)
		if item == null:
			check(id + " has a real ground use", false)
			continue
		var bounds: AABB = item.global_transform * WorldBuilder.local_aabb(item)
		var footprint := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(-.025)
		var grass_root: Node3D = main.world.farm.get_node("Meadow") if context == "farm" else main.world.get_node("TownGrass")
		var intrusions: int = 0
		var submitted: int = 0
		var readable: bool = true
		for child: Node in grass_root.get_children():
			var batch := child as MultiMeshInstance3D
			if batch == null:
				continue
			var points: PackedVector3Array = batch.get_meta("submitted_grass_positions", PackedVector3Array())
			readable = readable and points.size() == batch.multimesh.instance_count
			for index: int in batch.multimesh.instance_count:
				if DisplayServer.get_name() == "headless" and points.size() <= index:
					continue
				var local_point: Vector3 = points[index] if DisplayServer.get_name() == "headless" else batch.multimesh.get_instance_transform(index).origin
				var point: Vector3 = batch.global_transform * local_point
				submitted += 1
				if footprint.has_point(Vector2(point.x, point.z)):
					intrusions += 1
		check(id + " has no grass growing through its body or floor", readable and submitted > 0 and intrusions == 0,
			"intrusions=%d inspected=%d renderer=%s" % [intrusions, submitted, DisplayServer.get_name()])
		tested += 1
	check("new floor uses were physically checked", tested >= 2)


func run() -> void:
	var catalog: Dictionary = ModelDiversity.CATALOG.data.assets
	check("the agreed sixty reviewed singles are present", catalog.size() == 60, str(catalog.size()))
	var bark_path: String = "res://assets/models/_stats/_diversity_bark.json"
	var bark_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bark_path)) if FileAccess.file_exists(bark_path) else {}
	for id: String in ["T07_summer_maple", "T08_green_cherry", "T10_weeping_willow", "T11_young_zelkova"]:
		var measured: Dictionary = bark_report.get("models", {}).get(id, {})
		check(id + " has measured closed connected bark after reduction", bool(measured.get("passed", false))
			and measured.get("source_sha256", "") == FileAccess.get_sha256("res://assets/models/" + id + ".glb"),
			"boundary=%.6f connected=%.6f" % [float(measured.get("boundary_edge_fraction", 1)), float(measured.get("largest_component_area_fraction", 0))])
	var contexts: Dictionary = _contexts()
	var unique_uses: Dictionary = {}
	for entry: Array in ModelDiversity.USES:
		var id: String = entry[1]
		unique_uses[id] = true
		var item: Node3D = contexts[entry[0]].get_node_or_null("ModelDiversity/" + id)
		check(id + " is instantiated in its actual intended context", item != null and item.get_meta("model_id", "") == id)
		if item == null:
			continue
		var triangles: int = 0
		var clean_materials: bool = true
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(item):
			for surface: int in mesh.mesh.get_surface_count():
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
				var original := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if original:
					clean_materials = clean_materials and original.metallic <= .001 and original.roughness >= .95 and not original.normal_enabled
		check(id + " respects its real triangle and matte material budget", triangles > 0 and triangles <= int(catalog.get(id, {}).get("triangle_budget", 0)) and clean_materials,
			"triangles=%d" % triangles)
		var bounds: AABB = item.global_transform * WorldBuilder.local_aabb(item)
		if str(entry[4]) != "":
			var support: Node3D = item.get_node_or_null(item.get_meta("diversity_support", NodePath()))
			var at: Vector3 = item.global_position
			var actual: float = WorldBuilder.rendered_support_height(support, at, at.y + .08, true) if support else -INF
			check(id + " rests on an actual rendered tabletop", is_finite(actual) and absf(bounds.position.y - actual) <= .012)
			var sampled: int = 0
			var all_feet_supported: bool = support != null
			for mesh: MeshInstance3D in WorldBuilder.find_meshes(item):
				for surface: int in mesh.mesh.get_surface_count():
					var data: Array = mesh.mesh.surface_get_arrays(surface)
					var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
					for vertex: Vector3 in vertices:
						var foot: Vector3 = mesh.global_transform * vertex
						if foot.y > bounds.position.y + .006:
							continue
						var surface_y: float = WorldBuilder.rendered_support_height(support, foot, foot.y + .025, true)
						all_feet_supported = all_feet_supported and is_finite(surface_y) and absf(surface_y - foot.y) < .014
						sampled += 1
			check(id + " has its full actual foot supported without an edge overhang", all_feet_supported and sampled > 0)
			if id == "N17_seedling_tray":
				var intrusions: int = 0
				var interior: AABB = bounds.grow(-.005)
				for mesh: MeshInstance3D in WorldBuilder.find_meshes(support):
					for surface: int in mesh.mesh.get_surface_count():
						var data: Array = mesh.mesh.surface_get_arrays(surface)
						var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
						for vertex: Vector3 in vertices:
							var point: Vector3 = mesh.global_transform * vertex
							if point.y > bounds.position.y + .008 and interior.has_point(point):
								intrusions += 1
				check("seedling tray does not intersect the pot joined into P08", intrusions == 0, str(intrusions))
			if str(entry[0]) == "home":
				var relative_height: float = bounds.position.y - contexts.home.global_position.y
				check(id + " uses the worktop rather than a hidden cabinet or blanket surface",
					relative_height > (1.0 if id == "N01_enamel_kettle" else .40),
					"base above house floor=%.3f" % relative_height)
		else:
			var query := PhysicsRayQueryParameters3D.create(item.global_position + Vector3(0, .35, 0), item.global_position - Vector3(0, .35, 0), WorldBuilder.L_GROUND)
			var hit: Dictionary = main.world.get_world_3d().direct_space_state.intersect_ray(query)
			check(id + " rests on a real floor collider", not hit.is_empty() and absf(bounds.position.y - (hit.position as Vector3).y) <= .025)
		if id.begins_with("T"):
			var body: StaticBody3D = item.get_node_or_null("RootAndTrunkCollision")
			var simple: bool = body != null
			if body:
				for shape: Node in body.get_children():
					simple = simple and shape is CollisionShape3D and shape.shape is CylinderShape3D
			check(id + " uses a simple measured lower-trunk collider", simple and body.has_meta("model_part") and float(item.get_meta("diversity_root_radius", 0)) > .08)
			var contact_query := PhysicsShapeQueryParameters3D.new()
			if body:
				var trunk_shape: CollisionShape3D = body.get_child(0) as CollisionShape3D
				contact_query.shape = trunk_shape.shape
				contact_query.transform = trunk_shape.global_transform
				contact_query.collision_mask = WorldBuilder.L_SOLID
				contact_query.exclude = [body.get_rid()]
			var trunk_hits: Array[Dictionary] = main.world.get_world_3d().direct_space_state.intersect_shape(contact_query, 8) if body else []
			check(id + " trunk stays clear of existing walls and solid models", body != null and trunk_hits.is_empty(), str(trunk_hits))
			var capsule := CapsuleShape3D.new()
			capsule.radius = .23
			capsule.height = 1.2
			var clear_sides: int = 0
			var root_radius: float = float(item.get_meta("diversity_root_radius", 0))
			var centre: Vector3 = body.get_child(0).global_position if body else item.global_position
			for side: int in 8:
				var angle: float = float(side) * TAU / 8.0
				var at: Vector3 = Vector3(centre.x + cos(angle) * (root_radius + .58),
					bounds.position.y + .88, centre.z + sin(angle) * (root_radius + .58))
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.transform = Transform3D(Basis.IDENTITY, at)
				query.collision_mask = WorldBuilder.L_SOLID
				if main.world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
					clear_sides += 1
			check(id + " leaves real capsule clearance around at least half the trunk", clear_sides >= 4,
				"clear approaches=%d/8 radius=%.3f" % [clear_sides, root_radius])
	check("all thirty-six additions have actual unique uses", unique_uses.size() == 36)
	ground_clearance()
	await crop_lifecycle()
	festival_lifecycle()


func crop_lifecycle() -> void:
	var saved: Dictionary = GameState.to_dict().duplicate(true)
	var ids: Array[String] = ["carrot", "potato", "eggplant", "corn", "pumpkin", "watermelon", "wheat", "onion"]
	GameState.inventory.clear()
	GameState.bag_cap = 80
	GameState.farm_xp = 0
	for index: int in ids.size():
		var cid: String = ids[index]
		var pid: String = "farm%d" % index
		var definition: Dictionary = GameState.crop_def(cid)
		var model: String = definition.model
		var plot: PlotView = main.world.farm.plot_views[pid]
		GameState.plots[pid] = {"open": true, "tilled": true, "crop": cid, "days": 0,
			"water": true, "fert": false, "boost": false, "regrown": false}
		plot.refresh(true)
		await t.frames(2)
		var seed_soil: float = WorldBuilder.surface_height(plot.bed,
			Vector2(plot.global_position.x, plot.global_position.z), plot.global_position.y + 1.0)
		var mound: Node3D = plot.crops.get_child(0) as Node3D
		check(cid + " seed mound touches actual ridged soil", GameState.plot_state(pid) == "seeded"
			and absf(mound.global_position.y - seed_soil - .005) < .008)
		GameState.plots[pid].days = 1
		plot.refresh(true)
		await t.frames(2)
		var sprout: Node3D = plot.crops.get_child(0) as Node3D
		var sprout_box: AABB = sprout.global_transform * WorldBuilder.local_aabb(sprout)
		check(cid + " still uses the common seedling at sprout stage",
			GameState.plot_state(pid) == "sprout" and plot.crops.get_child_count() > 0
			and sprout.get_meta("model_id", "") == "C01_seedling" and absf(sprout_box.position.y - seed_soil) < .012)
		var growing_height: float = 0.0
		var mature_height: float = 0.0
		for stage: String in ["growing", "ripe"]:
			GameState.plots[pid].days = int(ceil(float(definition.days) / 2.0)) if stage == "growing" else int(definition.days)
			plot.refresh(true)
			await t.frames(2)
			var plant: Node3D = plot.crops.get_child(0) as Node3D
			var box: AABB = plant.global_transform * WorldBuilder.local_aabb(plant)
			var soil_y: float = WorldBuilder.surface_height(plot.bed,
				Vector2(plant.global_position.x, plant.global_position.z), plot.global_position.y + 1.0)
			if stage == "growing":
				growing_height = box.size.y
			else:
				mature_height = box.size.y
			var contact: bool = absf(box.position.y - soil_y) < .012
			if cid == "carrot":
				# Carrot body measured 0..0.054m. Its shoulder remains above soil.
				contact = box.position.y < soil_y - .015 and box.position.y + .054 * plant.scale.y > soil_y
			elif cid == "onion":
				# Root and lower bulb are below soil; the upper bulb stays visible.
				contact = box.position.y < soil_y - .025 and box.position.y + .15 * plant.scale.y > soil_y
			check(cid + " has its actual replacement rooted at " + stage,
				plant.get_meta("model_id", "") == model and contact
				and (stage == "growing" or box.size.y > growing_height * 1.45),
				"base=%.4f soil=%.4f height=%.3f" % [box.position.y, soil_y, box.size.y])
		var before: int = GameState.count(cid)
		var picked: Dictionary = GameState.harvest(pid)
		plot.refresh(true)
		await t.frames(2)
		var regrows: bool = int(definition.get("regrow", 0)) > 0
		var next_state_ok: bool = GameState.plot_state(pid) == "tilled" and plot.crops.get_child_count() == 0
		if regrows:
			next_state_ok = GameState.plot_state(pid) == "growing" and plot.crops.get_child_count() > 0
			if next_state_ok:
				var regrown: Node3D = plot.crops.get_child(0) as Node3D
				next_state_ok = regrown.get_meta("model_id", "") == model and WorldBuilder.local_aabb(regrown).size.y * regrown.scale.y < mature_height * .75
		check(cid + " harvest gives the real item and restores the proper post-harvest mesh",
			picked.get("item", "") == cid and GameState.count(cid) > before and next_state_ok)
	GameState.from_dict(saved)
	main.world.farm.refresh_plots()
	await t.frames(2)


func festival_lifecycle() -> void:
	var old_day: int = GameState.day
	var old_region: String = main.world.region
	for day: int in [17, 19]:
		GameState.day = day
		main.world.set_region("town")
		var enabled: bool = day == 17
		var root: Node3D = main.world.fest_nodes.natsumatsuri.get_node("ModelDiversity")
		for id: String in ["N22_festival_masks", "N23_goldfish_scoops", "N24_bamboo_lantern"]:
			var item: Node3D = root.get_node(id)
			var collision_ok: bool = true
			for body: Node in item.find_children("*", "StaticBody3D", true, false):
				collision_ok = collision_ok and ((body as StaticBody3D).collision_layer > 0) == enabled
			check(id + (" appears with its festival" if enabled else " hides and releases collision after the festival"),
				item.is_visible_in_tree() == enabled and collision_ok)
	GameState.day = old_day
	main.world.set_region(old_region)

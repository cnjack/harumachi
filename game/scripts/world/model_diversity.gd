class_name ModelDiversity
extends RefCounted
## Shared anime treatment for reviewed model replacements and reusable singles.
const CATALOG: JSON = preload("res://data/model_diversity.json")


static func contains(id: String) -> bool:
	var assets: Dictionary = CATALOG.data.get("assets", {})
	return assets.has(id)


static func soil_sink_m(id: String) -> float:
	# Measured body extents in soil-body-measurements.json. Only growing plants
	# are buried; displays, harvested inventory and reference models stay intact.
	if not contains(id):
		return 0.0
	return float({"C09_carrot": .044, "C16_onion": .075}.get(id, 0.0))


static func apply(root: Node3D, id: String) -> void:
	if not contains(id):
		return
	HouseBuilder.toonify(root)
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		for surface: int in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
			if material:
				material.roughness = 1.0
	SurfaceFinish.decorate_timber(root)
	if id == "N24_bamboo_lantern":
		var lamp := OmniLight3D.new()
		lamp.name = "PaperLanternLight"
		lamp.position.y = WorldBuilder.local_aabb(root).size.y * .5
		lamp.light_color = Color(1.0, .71, .39)
		lamp.light_energy = .65
		lamp.omni_range = 2.2
		lamp.shadow_enabled = false
		root.add_child(lamp)
	root.set_meta("model_diversity_revision", "20261013")


## context, model, position in that context, yaw, support model (empty means floor).
## Tabletops are measured once at construction, never during the game clock.
const USES: Array = [
	["farm", "T06_camphor", Vector3(20, 0, -17), 24, ""],
	["town", "T07_summer_maple", Vector3(29.5, 0, 11.5), 15, ""],
	["town", "T08_green_cherry", Vector3(-44, 0, 3), -25, ""],
	["farm", "T09_bamboo_grove", Vector3(18, 0, 24), 20, ""],
	["farm", "T10_weeping_willow", Vector3(-19, 0, 24), -40, ""],
	["town", "T11_young_zelkova", Vector3(36, 0, 12), 60, ""],
	["town", "V20_morning_glory", Vector3(-15.3, 0, -14.8), 0, ""],
	["town", "V21_white_hydrangea", Vector3(21.8, 0, 6.7), -90, ""],
	["farm", "V22_shiso_planter", Vector3(-16.3, 0, -6), 15, ""],
	["town", "V23_cosmos_pot", Vector3(-8.65, 0, -14.8), 0, ""],
	["home", "V24_fern_pot", Vector3(6.1, 0, -3.95), 0, ""],
	["home", "V25_dwarf_lemon", Vector3(6.0, -.45, -8), -20, ""],
	["home", "N01_enamel_kettle", Vector3(-6.10, 0, 2.90), 90, "J01_kitchen_counter"],
	["home", "N02_kyusu", Vector3(2.59, 0, -1.45), -30, "J07_kotatsu"],
	["home", "N03_tea_pair", Vector3(2.30, 0, -1.50), 5, "J07_kotatsu"],
	["home", "N04_fruit_bowl", Vector3(2.5, 0, -1.0), 10, "J07_kotatsu"],
	["home", "N05_sewing_basket", Vector3(-4.2, 0, -1.45), 25, ""],
	["home", "N06_house_slippers", Vector3(3.95, -.12, 3.45), -10, ""],
	["farm", "N07_watering_can", Vector3(-17.45, 0, -6.15), -30, ""],
	["home", "N08_broom_dustpan", Vector3(3.85, 0, 1.65), 5, ""],
	["store", "N09_shopping_basket", Vector3(-2.8, 0, 2.75), 15, ""],
	["store", "N10_apple_crate", Vector3(4.8, 0, 2.4), 0, ""],
	["store", "N11_daikon_crate", Vector3(4.8, 0, 3.3), 0, ""],
	["farm", "N12_carrot_crate", Vector3(7.4, 0, 4.25), -10, ""],
	["farm", "N13_empty_crate", Vector3(6.25, 0, 4.15), 10, ""],
	["store", "N14_paper_parcels", Vector3(-3.90, 0, .05), 10, "I04_shop_counter"],
	["home", "N15_umbrella_stand", Vector3(6.0, 0, 1.7), 0, ""],
	["town", "N16_wooden_crate_seat", Vector3(13.6, 0, 14.0), -10, ""],
	["town", "N17_seedling_tray", Vector3(16.075, 0, 16.075), 90, "P08"],
	["farm", "N18_harvest_basket", Vector3(8.45, 0, 4.5), 10, ""],
	["farm", "N19_burlap_sacks", Vector3(-15.5, 0, -5.0), 10, ""],
	["farm", "N20_coiled_hose", Vector3(-7.1, 0, -4.6), 0, ""],
	["farm", "N21_tool_basket", Vector3(-11.15, 0, -9.7), -10, ""],
	["festival", "N22_festival_masks", Vector3(7.6, 0, 18.6), 180, ""],
	["festival", "N23_goldfish_scoops", Vector3(-6.4, 0, 17.8), 0, "N16_wooden_crate_seat"],
	["festival", "N24_bamboo_lantern", Vector3(5.0, 0, 19.8), 0, ""],
]


static func build(world: WorldBuilder) -> void:
	var contexts: Dictionary = {"town": world, "farm": world.farm, "home": world.house,
		"store": world.interiors.store, "festival": world.fest_nodes.natsumatsuri}
	var groups: Dictionary = {}
	for context: String in contexts:
		var group := Node3D.new()
		group.name = "ModelDiversity"
		contexts[context].add_child(group)
		groups[context] = group
	if contains("N23_goldfish_scoops") and contains("N16_wooden_crate_seat"):
		# Reuse the reviewed stool as a real dry tray support beside the fish
		# pool, instead of placing paper scoops on a food-stall serving surface.
		var tray_stand: Node3D = world.spawn("N16_wooden_crate_seat", Vector3(-6.4, 0, 17.8),
			0, 1, groups.festival)
		WorldBuilder.rest_on_terrain(tray_stand, 0.0, .002)
	for entry: Array in USES:
		var id: String = entry[1]
		if not contains(id):
			continue
		var parent: Node3D = groups[entry[0]]
		var item: Node3D = world.spawn(id, entry[2], float(entry[3]), 0, parent)
		if item == null:
			continue
		item.set_meta("diversity_context", entry[0])
		if str(entry[4]) != "":
			var support: Node3D = null
			var support_y: float = -INF
			for candidate: Node in contexts[entry[0]].find_children("*", "Node3D", true, false):
				if candidate.get_meta("model_id", "") != str(entry[4]):
					continue
				var measured: float = WorldBuilder.rendered_support_height(candidate, item.global_position,
					(candidate as Node3D).global_position.y + 1.25, true)
				if is_finite(measured) and measured > support_y:
					support = candidate
					support_y = measured
			if support:
				if is_finite(support_y):
					WorldBuilder.rest_on(item, support_y, .001)
					item.set_meta("diversity_support", support.get_path())
					item.set_meta("diversity_support_y", support_y)
					item.set_meta("support_surface", support.get_path())
					item.set_meta("support_ceiling", support_y + .05)
				else:
					push_error("No rendered support beneath " + id)
			else:
				push_error("Missing support for " + id)
		else:
			WorldBuilder.rest_on_terrain(item, item.global_position.y, .002)
		if id.begins_with("T"):
			# Only a measured lower trunk/root cylinder blocks walking. The leaf
			# crown never becomes a concave sphere-sweep collider.
			_attach_tree_support(item)
		elif str(entry[4]) == "" and not id in ["N06_house_slippers", "N20_coiled_hose"]:
			WorldBuilder.add_box_collider(item, .88, WorldBuilder.L_SOLID)


static func ground_exclusions(context: String) -> Array:
	var rectangles: Array = []
	for entry: Array in USES:
		var id: String = entry[1]
		if str(entry[0]) != context or str(entry[4]) != "" or id.begins_with("T") or not contains(id):
			continue
		var path: String = "res://assets/models/_stats/" + id + ".json"
		if not FileAccess.file_exists(path):
			continue
		var stats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var dimensions: Array = stats.get("godot_size_m_xyz", [])
		if dimensions.size() != 3:
			continue
		var angle: float = deg_to_rad(float(entry[3]))
		var width: float = absf(cos(angle)) * float(dimensions[0]) + absf(sin(angle)) * float(dimensions[2])
		var depth: float = absf(sin(angle)) * float(dimensions[0]) + absf(cos(angle)) * float(dimensions[2])
		var point: Vector3 = entry[2]
		rectangles.append([point.x - width * .5 - .12, point.z - depth * .5 - .12,
			point.x + width * .5 + .12, point.z + depth * .5 + .12])
	return rectangles


static func _attach_tree_support(tree: Node3D) -> void:
	var bounds: AABB = WorldBuilder.local_aabb(tree)
	var lower_points: Array[Vector3] = []
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(tree):
		var mesh_to_tree: Transform3D = tree.global_transform.affine_inverse() * mesh.global_transform
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point: Vector3 = mesh_to_tree * vertex
				if point.y <= bounds.position.y + minf(.65, bounds.size.y * .12):
					lower_points.append(point)
	if lower_points.is_empty():
		push_error("No lower trunk geometry: " + tree.name)
		return
	var low: Vector3 = lower_points[0]
	var high: Vector3 = low
	for point: Vector3 in lower_points:
		low = low.min(point)
		high = high.max(point)
	var centre: Vector3 = (low + high) * .5
	var radius: float = .08
	for point: Vector3 in lower_points:
		radius = maxf(radius, Vector2(point.x - centre.x, point.z - centre.z).length() + .08)
	var body := StaticBody3D.new()
	body.name = "RootAndTrunkCollision"
	body.collision_layer = WorldBuilder.L_SOLID | WorldBuilder.L_CAMERA
	body.set_meta("model_part", tree.get_meta("model_id"))
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 2.3
	shape.shape = cylinder
	shape.position = Vector3(centre.x, bounds.position.y + 1.15, centre.z)
	body.add_child(shape)
	tree.add_child(body)
	tree.set_meta("diversity_root_radius", radius)


static func seed_review_crops() -> void:
	var crop_ids: Array[String] = ["carrot", "potato", "eggplant", "corn", "pumpkin", "watermelon", "wheat", "onion"]
	var stage: String = "ripe"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--diversity-crop-stage="):
			stage = argument.trim_prefix("--diversity-crop-stage=")
	for index: int in crop_ids.size():
		var cid: String = crop_ids[index]
		var pid: String = "farm%d" % index
		var grow_days: int = int(GameState.crop_def(cid).days)
		var days: int = grow_days
		if stage == "seeded":
			days = 0
		elif stage == "sprout":
			days = 1
		elif stage == "growing":
			days = int(ceil(float(grow_days) / 2.0))
		GameState.plots[pid] = {"open": true, "tilled": true, "crop": cid,
			"days": days, "water": true,
			"fert": false, "boost": false, "regrown": false}
	GameState.plots_changed.emit()


static func capture_views(world: WorldBuilder) -> Dictionary:
	var views: Dictionary = {}
	var fixtures: Array = [
		["D01_wheelbarrow", Vector3(-6.3, 0, -9.2), Vector3(-5.7, 1.45, -10.7), .40],
		["D02_rain_barrel", Vector3(-8.8, 0, -9.3), Vector3(-7.0, 1.3, -8.5), .50],
		["D03_veg_crates", Vector3(8.3, 0, 3.3), Vector3(9.7, 1.25, 4.8), .45],
		["D04_stone_lantern", Vector3(-4.6, 0, 25.9), Vector3(-3.0, 1.3, 24.7), .65],
		["D05_hokora", Vector3(-6.6, 0, 26.2), Vector3(-5.0, 1.4, 24.6), .70],
		["D08_tool_rack", Vector3(-12.9, 0, -9.6), Vector3(-14.8, 1.6, -8.0), .80],
		["D09_log_pile", Vector3(-15.2, 0, -9.8), Vector3(-15.2, 1.5, -11.4), .45],
		["D12_flower_planter", Vector3(4.3, 0, 3.3), Vector3(5.9, 1.2, 5.0), .40],
		["F04_scarecrow", Vector3(6.3, 0, -5.3), Vector3(8.5, 1.8, -3.0), .95],
		["F06_veggie_stand", Vector3(6.5, 0, 1.9), Vector3(4.7, 1.7, -.3), .95],
	]
	for fixture: Array in fixtures:
		_add_views(views, fixture[0], "farm", fixture[1], fixture[2], fixture[1] + Vector3(0, fixture[3], 0))
	var town_fixtures: Array = [
		["A14_hydrangea_pot", Vector3(21.8, 0, 8.6), Vector3(20.3, 1.1, 7.1), .4],
		["A15_potted_plant", Vector3(4.1, 0, -15.0), Vector3(5.5, 1.2, -13.6), .4],
		["A16_planter_box", Vector3(-9.7, 0, -14.95), Vector3(-8.2, 1.1, -13.4), .3],
		["P07", Vector3(14.4, 0, 21.4), Vector3(11.5, 2.1, 18.7), .7],
		["P08", Vector3(16.0, 0, 15.2), Vector3(13.5, 1.8, 13.4), .85],
		["H06", Vector3(15.4, 0, 1.0), Vector3(12.0, 2.2, -2.0), 1.05],
	]
	for fixture: Array in town_fixtures:
		_add_views(views, fixture[0], "town", fixture[1], fixture[2], fixture[1] + Vector3(0, fixture[3], 0))
	var crop_models: Array[String] = ["C09_carrot", "C10_potato", "C11_eggplant", "C12_corn", "C13_pumpkin", "C14_watermelon", "C15_wheat", "C16_onion"]
	var crop_heights: Array[float] = [.35, .5, .8, 1.8, .5, .5, .9, .45]
	for index: int in crop_models.size():
		var point: Vector3 = FarmBuilder.plot_pos("farm%d" % index) + Vector3(0, .25, 0)
		var distance: float = maxf(1.2, crop_heights[index] * 1.6)
		_add_views(views, crop_models[index], "farm", point, point + Vector3(distance, distance * .65, distance), point + Vector3(0, crop_heights[index] * .45, 0))
	var contexts: Dictionary = {"town": world, "farm": world.farm, "home": world.house,
		"store": world.interiors.store, "festival": world.fest_nodes.natsumatsuri}
	for entry: Array in USES:
		var context: String = entry[0]
		var group: Node3D = contexts[context].get_node_or_null("ModelDiversity")
		var item: Node3D = group.get_node_or_null(entry[1]) if group else null
		if item == null:
			continue
		var point: Vector3 = item.position
		var bounds: AABB = WorldBuilder.local_aabb(item)
		var height: float = bounds.size.y
		var extent: float = maxf(height, maxf(bounds.size.x, bounds.size.z))
		var distance: float = maxf(.55, extent * 1.4)
		var direction := Vector3(distance, distance * .75, distance)
		if context == "home" and point.x > 4.0:
			direction.x = -distance
		if entry[1] == "V24_fern_pot":
			direction = Vector3(-distance * .5, distance * .75, -distance)
		if context == "festival":
			direction.z = -distance
		if context == "store":
			if point.x > 3.0:
				direction.x = -distance
			if point.z > 2.5:
				direction.z = -distance
		_add_views(views, entry[1], context, point, point + direction, point + Vector3(0, height * .45, 0))
		if str(entry[1]).begins_with("T"):
			var root_distance: float = maxf(1.6, float(item.get_meta("diversity_root_radius", .3)) + .7)
			_add_views(views, str(entry[1]) + "_root", context, point,
				point + Vector3(-root_distance, 1.2, -root_distance), point + Vector3(0, .3, 0))
	return views


static func _add_views(views: Dictionary, id: String, context: String, point: Vector3, camera: Vector3, focus: Vector3) -> void:
	var conditions: String = "noon,sunset,night,rain"
	var subset: String = "all"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--diversity-conditions="):
			conditions = argument.trim_prefix("--diversity-conditions=")
		if argument.begins_with("--diversity-assets="):
			subset = argument.trim_prefix("--diversity-assets=")
	var is_new: bool = id.begins_with("N") or id.begins_with("V2") or id.begins_with("T")
	if (subset == "replace" and is_new) or (subset == "new" and not is_new):
		return
	for condition: String in conditions.split(","):
		var view: Dictionary = {"time": 21.0 if condition == "night" else (17.6 if condition == "sunset" else 12.0),
			"weather": "rain" if condition == "rain" else "sunny", "settle_seconds": .8}
		if context == "home":
			view.merge({"house": point + Vector3(.5, .05, .5), "house_camera": camera,
				"house_focus": focus, "face": 0, "pitch": 25, "dist": 6})
		elif context == "store":
			view.merge({"interior": "store", "at": point + Vector3(.8, .05, .8),
				"inside_camera": camera, "inside_focus": focus})
		else:
			view.merge({"farm": context == "farm", "player": point + Vector3(3, .1, 2),
				"camera_at": camera, "camera_focus": focus})
			if context == "festival":
				view["day"] = 17
		views["diversity_" + id + "_" + condition] = view

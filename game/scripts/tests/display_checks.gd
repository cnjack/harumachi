extends RefCounted
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(name: String, passed: bool, detail: String = "") -> void:
	t.check("DISPLAY", name, passed, detail)

func _volume(node: Node3D) -> float:
	var total := 0.0
	var inverse: Transform3D = node.global_transform.affine_inverse()
	for mesh_instance: MeshInstance3D in WorldBuilder.find_meshes(node):
		var transform: Transform3D = inverse * mesh_instance.global_transform
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				for i in vertices.size():
					indices.append(i)
			for i in range(0, indices.size(), 3):
				var a: Vector3 = transform * vertices[indices[i]]
				var b: Vector3 = transform * vertices[indices[i+1]]
				var c: Vector3 = transform * vertices[indices[i+2]]
				total += a.dot(b.cross(c)) / 6.0
	return absf(total)

func run() -> void:
	var baseline_path := "res://assets/models/_stats/_window_apertures.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--aperture-report="):
			baseline_path = argument.substr(18)
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
	var fresh := true
	for id: String in ["S01", "S02", "S03", "S05", "S08"]:
		var metric: Dictionary = report.get("models", {}).get(id, {})
		fresh = fresh and float(FileAccess.get_modified_time("res://assets/models/%s.glb" % id)) <= float(metric.get("source_mtime", 0)) + 5.0
	check("eight exported facade openings have a fresh physical aperture survey", fresh and report.get("windows", {}).size() == 8 and bool(report.get("passed", false)), str(report.get("windows", {})))
	var buildings: Dictionary = {}
	for child: Node in main.world.get_children():
		var id := str(child.get_meta("model_id", ""))
		if ShopWindows.WINDOWS.has(id):
			buildings[id] = child
	for id: String in ShopWindows.WINDOWS:
		var building: Node3D = buildings.get(id)
		var room: Node3D = building.get_node_or_null("ActualShopDisplay_" + id) as Node3D if building else null
		var products: Array[Node3D] = []
		if room:
			for child: Node in room.get_children():
				if child is Node3D and child.get_meta("shop_display", false):
					products.append(child as Node3D)
		check("real product models behind " + id, room != null and products.size() >= 2 and products.all(func(prop: Node3D): return _volume(prop) > .000005), "products %d" % products.size())
		var floor_mesh: MeshInstance3D = room.get_node_or_null("RoomFloor") as MeshInstance3D if room else null
		check("display room has floor depth behind " + id, floor_mesh != null and (floor_mesh.mesh as BoxMesh).size.z > 1.8)
	var windows: Array[Node] = main.world.find_children("ShopWindow_*", "MeshInstance3D", true, false)
	check("glass no longer renders a picture of shelves or goods", windows.size() == 8 and windows.all(func(node: Node): return ((node as MeshInstance3D).material_override as ShaderMaterial).shader.resource_path.ends_with("shop_glass.gdshader")))
	var lights: Array[Node] = main.world.find_children("ActualDisplayLight_*", "OmniLight3D", true, false)
	main.world.update_time(10.0*60, "sunny", true)
	var day_energy: float = (lights[0] as OmniLight3D).light_energy if not lights.is_empty() else 0.0
	main.world.update_time(21.0*60, "sunny", true)
	check("actual room lights increase after dusk", lights.size() == 5 and (lights[0] as OmniLight3D).light_energy > day_energy+.3)
	main.world.update_time(GameState.minute, GameState.weather, true)
	var trees: Array[Node3D] = []
	for child: Node in main.world.get_children():
		if child is Node3D and child.get_meta("near_background_tree", false):
			trees.append(child as Node3D)
	check("near forest uses many volumetric model trees", trees.size() >= 25 and trees.all(func(tree: Node3D): return tree.has_meta("model_id") and _volume(tree) > .10), "trees %d" % trees.size())
	# Farm scenery is a child of world at x=700; its far treeline is outside town.
	var cards: Array = main.world.find_children("*", "MeshInstance3D", true, false).filter(func(node: Node): return absf((node as MeshInstance3D).global_position.x) < 200.0 and str(node.get_meta("backdrop_tex", "")).begins_with("bg_tree_"))
	check("no near tree image cards remain in town", cards.is_empty(), "cards %d" % cards.size())
	var tree_types := ["T02_summer_tree", "T03_round_ginkgo", "T04_slender_cedar"]
	check("near forest has three different generated tree shapes", tree_types.all(func(id: String): return trees.filter(func(tree: Node3D): return tree.get_meta("model_id", "") == id).size() >= 6))
	var cucumber_models: Array[Node] = (buildings["S01"] as Node3D).find_children("Pixal_whole_cucumbers_*", "MeshInstance3D", true, false)
	check("store's cucumber bins contain two actual generated whole-cucumber crates", cucumber_models.size() == 2 and cucumber_models.all(func(node: Node): return _volume(node as Node3D) > .0001))
	var stock := {"S01":["W02_grocer_shelf","W09_rice_sacks","W10_bottle_crate"],"S02":["W07_pastry_tray","W08_baguette_basket","W12_cedar_tray"],"S03":["W01_flower_buckets","W04_sunflower_pot","W05_hydrangea_pot","W06_lily_vase"],"S05":["I03_bookshelf","I08_boxes"],"S08":["W11_ceramic_set","J05_dish_cabinet"]}
	var complete_stock := true
	for shop_id: String in stock:
		var display_room: Node = (buildings[shop_id] as Node3D).get_node_or_null("ActualShopDisplay_" + shop_id)
		for product_id: String in stock[shop_id]:
			complete_stock = complete_stock and display_room != null and display_room.get_children().any(func(child: Node): return child.get_meta("model_id", "") == product_id)
	check("all independent generated stock modules are present in their shops", complete_stock)
	var contents_inside := true
	for shop_id: String in ShopWindows.WINDOWS:
		var display_room: Node3D = (buildings[shop_id] as Node3D).get_node_or_null("ActualShopDisplay_"+shop_id) as Node3D
		if display_room == null:
			contents_inside = false
			continue
		for child: Node in display_room.get_children():
			if not (child is Node3D) or not (child.get_meta("shop_display",false) or "Counter" in str(child.name) or "Table" in str(child.name)):
				continue
			var item := child as Node3D
			var box: AABB = item.transform * WorldBuilder.local_aabb(item)
			for pane: Array in ShopWindows.WINDOWS[shop_id]:
				if box.end.x > float(pane[0]) and box.position.x < float(pane[1]):
					contents_inside = contents_inside and box.end.z <= float(pane[4])-.025
	check("stock and counters stay behind the glazing with a 2.5 cm margin", contents_inside)

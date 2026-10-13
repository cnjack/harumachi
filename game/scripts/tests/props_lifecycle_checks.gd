extends RefCounted
## Exercise real models, colliders and existing story facts rather than invented inventory.
var t: Object
var main: Node

func _init(runner: Object) -> void:
	t = runner; main = runner.main

func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("PROPS_LIFECYCLE", label, ok, detail)

func _life() -> Node:
	return main.world.get_node_or_null("SceneLifecycle")

func _sync() -> void:
	main.world.sync_festivals(); main._sync_props()
	if _life(): _life().sync_state()
	main.story.daily.view.sync_state()

func _moment(day: int, hour: float, phase: String = "prep") -> void:
	GameState.day = day; GameState.minute = hour * 60.0; GameState.phase = phase
	main.world.set_region("town"); _sync()

func _solid(root: Node) -> int:
	var count: int = 0
	for body: StaticBody3D in root.find_children("*", "StaticBody3D", true, false):
		if body.collision_layer & (WorldBuilder.L_SOLID | WorldBuilder.L_PLACED): count += 1
	return count

func _model(parent: Node, id: String) -> Node3D:
	for child: Node in parent.find_children("*", "Node3D", true, false):
		if str(child.get_meta("model_id", "")) == id: return child as Node3D
	return null

func _cover_end(mesh: MeshInstance3D, at: Vector2, front: bool) -> float:
	var extreme: float = -INF if front else INF
	for surface: int in mesh.mesh.get_surface_count():
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var count: int = vertices.size() if indices.is_empty() else indices.size()
		for index: int in range(0, count, 3):
			var a: Vector3 = vertices[index if indices.is_empty() else indices[index]]
			var b: Vector3 = vertices[index + 1 if indices.is_empty() else indices[index + 1]]
			var c: Vector3 = vertices[index + 2 if indices.is_empty() else indices[index + 2]]
			var ab := Vector2(b.x-a.x, b.y-a.y); var ac := Vector2(c.x-a.x, c.y-a.y); var ap := at-Vector2(a.x,a.y)
			var determinant: float = ab.cross(ac)
			if absf(determinant) < .000001: continue
			var u: float = ap.cross(ac)/determinant; var v: float = ab.cross(ap)/determinant
			if u < -.001 or v < -.001 or u+v > 1.001: continue
			var z: float = a.z+(b.z-a.z)*u+(c.z-a.z)*v
			extreme = maxf(extreme,z) if front else minf(extreme,z)
	return extreme

func run() -> void:
	var saved: Dictionary = GameState.to_dict().duplicate(true)
	GameState.weather = "sunny"
	_moment(1, 11.0)
	var stage: Node3D = main.world.get_node("P10")
	var ordinary: bool = true
	var found: int = 0
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(stage):
		if str(mesh.name).begins_with("Pennant_") or str(mesh.name).begins_with("Speaker"):
			ordinary = ordinary and not mesh.is_visible_in_tree(); found += 1
	check("ordinary public platform keeps its timber but puts away all six flags and speakers", stage.visible and found == 6 and ordinary)
	check("daily fish practice and taiko remain visible at the existing physical anchors", main.world.goldfish_tank.is_visible_in_tree() and main.world.taiko_drum.is_visible_in_tree() and main.world.goldfish_tank.position.distance_to(Layout.GOLDFISH_POS) < .001 and main.world.taiko_drum.position.distance_to(Layout.TAIKO_POS) < .001)
	if _life():
		var cover: MeshInstance3D = main.world.taiko_drum.get_node("PracticeClothCover")
		check("the everyday taiko wears a fitted reusable cloth rather than appearing mid-performance", cover.visible)
		var cloth_material: ShaderMaterial = cover.material_override
		check("thin cloth renders both sides instead of culling the entire front drape", cloth_material.shader.code.contains("cull_disabled"))
		var covered_faces: bool = true
		for probe: Vector2 in [Vector2(0,.76),Vector2(.25,.76),Vector2(-.25,.76),Vector2(0,1.04),Vector2(0,.50)]:
			covered_faces = covered_faces and _cover_end(cover,probe,true) > .255 and _cover_end(cover,probe,false) < -.255
		check("the actual draped geometry covers both drum heads from crown to lower rim", covered_faces)
		_life().begin_practice("taiko")
		check("practice immediately uncovers the same drum without deploying stage speakers", not cover.visible and not main.world.get_node("P10").find_child("SpeakerCharcoal", true, false).visible)
		_life().end_practice("taiko")
		check("finishing practice puts the same cloth back without moving the drum", cover.visible and main.world.taiko_drum.position.distance_to(Layout.TAIKO_POS) < .001)
	var cloth: Node3D = main.world.farm.get_node_or_null("ReviewedLibrary/PicnicCloth")
	check("an uninvited picnic is not already laid out on the lakeside", cloth == null or not cloth.visible)
	check("the town no longer duplicates the farm's carton and filled bucket", main.world.get_node_or_null("ReviewedLibrary/P_library_carton") == null and main.world.get_node_or_null("ReviewedLibrary/P_library_bucket") == null)
	check("bridge lanterns remain independent of festival setup", main.world.farm.get_node("BridgeDressing").find_children("BridgeLantern_*", "Node3D", true, false).size() == 4)
	var resident: Dictionary = GameState.flags.get("resident_visits", {})
	var was_setup: bool = bool(resident.get("resident_setup", false))
	var prior_trial: Dictionary = resident.get("trial", {}).duplicate(true)
	resident.resident_setup = true; resident.trial = {}
	main.story.visits.view.sync_state()
	await main.get_tree().physics_frame; await main.get_tree().physics_frame
	var fallback: Node3D = main.story.visits.view.fallback
	var shape: CollisionShape3D = fallback.find_children("*", "CollisionShape3D", true, false)[0]
	var exclusions: Array[RID] = []
	for body: CollisionObject3D in fallback.find_children("*", "CollisionObject3D", true, false): exclusions.append(body.get_rid())
	var seat_query := PhysicsShapeQueryParameters3D.new(); seat_query.shape = shape.shape; seat_query.transform = shape.global_transform
	seat_query.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED; seat_query.exclude = exclusions
	var seat_hits: Array[Dictionary] = main.world.get_world_3d().direct_space_state.intersect_shape(seat_query, 12)
	var capsule := CapsuleShape3D.new(); capsule.radius = .28; capsule.height = 1.5
	var feet_query := PhysicsShapeQueryParameters3D.new(); feet_query.shape = capsule
	feet_query.transform = Transform3D(Basis.IDENTITY, fallback.global_position + fallback.global_basis * Vector3(0, 0, .85) + Vector3.UP * .77)
	feet_query.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED; feet_query.exclude = exclusions
	var feet_hits: Array[Dictionary] = main.world.get_world_3d().direct_space_state.intersect_shape(feet_query, 12)
	check("the residents' late-or-cancelled fallback bench and its full standing capsule clear existing furniture", fallback.visible and seat_hits.is_empty() and feet_hits.is_empty(), "bench_hits=%s standing_hits=%s" % [str(seat_hits.map(func(hit: Dictionary) -> String: return str(hit.collider.get_parent().name))), str(feet_hits.map(func(hit: Dictionary) -> String: return str(hit.collider.get_parent().name)))])
	resident.resident_setup = was_setup; resident.trial = prior_trial; main.story.visits.view.sync_state()
	var tray: Node3D = _model(main.world.get_node("ModelDiversity"), "N17_seedling_tray")
	check("the nursery tray has no plants before the planter project is accepted", tray != null and not tray.visible)
	# Other full-suite groups exercise the legacy route. This fixture describes
	# a cooperative delivery, so select its real source of construction progress.
	SummerProjects.state().mainline_mode = "cooperation"
	GameState.quests.Q13 = {"state": "active", "step": 1}
	GameState.flags.erase("town_finished_Q13")
	GameState.flags["summer_space"] = {"version": 1, "phase": "arranging", "optional_wood": 0}
	_moment(16, 9.0)
	var tower: Node3D = _model(main.world.fest_nodes.natsumatsuri, "P_yagura")
	check("a preparation morning does not silently finish the complete tower", tower != null and not tower.visible and _solid(tower) == 0)
	check("partial construction reserves its actual future footprint", main.story.space.view.preview.visible and _solid(main.story.space.view.preview) == 3)
	GameState.flags.summer_space.optional_wood = 4; _sync()
	var logs: Node3D = main.world.farm.get_node("D09_log_pile")
	check("moving four logs leaves exactly two visible transportable beams at the shed", int(logs.get_meta("remaining_logs", -1)) == 2)
	var work: Node3D = main.world.get_node_or_null("SceneLifecycle/ConstructionWood")
	check("moved beams appear at the real construction site before being consumed", work != null and int(work.get_meta("delivered_logs", -1)) == 4 and work.visible)
	if _life():
		var stock: Node3D = logs.get_node("RemainingBeams")
		check("the shed renders exactly two remaining beams after four were carried", stock.get_children().filter(func(beam: Node3D) -> bool: return beam.visible).size() == 2)
		check("only four delivered beam bodies remain solid at the construction site", work.get_children().filter(func(beam: Node3D) -> bool: return beam.visible).size() == 4 and _solid(work) == 4)
		var structure: Node3D = _life().get_node("StageFramework")
		check("unfinished framework has six real beams with matching simple collision", structure.visible and _solid(structure) == 6)
	_moment(17, 18.0)
	check("residents' festival fallback produces the complete real tower in time", tower.visible and _solid(tower) > 0 and not main.story.space.view.preview.visible)
	if _life(): check("formal festival opening uncovers the playable drum", not main.world.taiko_drum.get_node("PracticeClothCover").visible)
	main.world.set_region("farm"); _sync()
	check("leaving town disables every collision in the hidden festival subtree", not main.world.fest_nodes.natsumatsuri.visible and _solid(main.world.fest_nodes.natsumatsuri) == 0)
	main.world.set_region("town"); _sync()
	check("returning restores the same tower and real festive collision", tower.is_visible_in_tree() and _solid(tower) > 0)
	_moment(17, 22.1)
	var festival_items: Node3D = main.world.fest_nodes.natsumatsuri.get_node("ModelDiversity")
	check("cleanup briefly retains substantial frames but packs away mask and scoop displays", tower.is_visible_in_tree() and not festival_items.visible and _solid(festival_items) == 0)
	_moment(17, 22.7)
	check("cleanup ends with no solid festival object left behind", not tower.is_visible_in_tree() and _solid(main.world.fest_nodes.natsumatsuri) == 0)
	_moment(18, 10.0)
	check("the completed festival removes the tower and its collision together", not tower.is_visible_in_tree() and _solid(tower) == 0)
	var planning_rings: bool = false
	for child: Node in main.story.space.view.get_children():
		if child.has_meta("space_circle"): planning_rings = planning_rings or child.visible
	check("after the festival no occupancy preview or dance-planning disk reappears", not main.story.space.view.preview.visible and _solid(main.story.space.view.preview) == 0 and not planning_rings)
	GameState.quests["Q02"] = {"state": "done", "step": 0}
	GameState.quests["Q04"] = {"state": "done", "step": 0}
	_moment(20, 23.0)
	check("an old delivered basket does not leave fresh bread outside overnight", not main.world.stall_bread.visible)
	var poster_label: Label3D
	for child: Node in main.world.poster.get_children():
		if child is Label3D: poster_label = child
	check("a completed poster reflects the next real activity rather than a perpetual opening", main.world.poster.visible and poster_label != null and poster_label.text != "周末小集市\n庭院 · 周六傍晚")
	var sign: Node3D = main.world.get_node("BuildSign")
	check("the first completed festival retires the temporary construction sign and collider", not sign.visible and _solid(sign) == 0)
	DailyLife.initialize()
	DailyLife.event("tea").state = "done"; DailyLife.event("tea").completed_day = 19
	_moment(20, 22.0)
	check("returned tea cups from a previous day are actually put away", not main.story.daily.view.tea_root.visible)
	GameState.quests.Q00 = {"state": "done", "step": GameState.quests_db.Q00.steps.size()}
	_moment(20, 7.5)
	check("after yesterday's completed tea the same tray is available for the next nursery morning", main.story.daily.view.tea_root.visible and main.story.daily.view.tea_root.get_meta("lifecycle_state", "") == "preparing")
	_moment(20, 10.0)
	check("the nursery tray is stored when that next morning ends instead of replaying completed tea", not main.story.daily.view.tea_root.visible and main.story.daily.view.tea_root.get_meta("lifecycle_state", "") == "stored")
	var harvest: Node3D = _model(main.world.farm.get_node("ModelDiversity"), "N18_harvest_basket")
	check("the player's harvest basket is absent before an actual stand sale", harvest != null and not harvest.visible and _solid(harvest) == 0)
	check("Tanaka's own vegetable crates and working stand remain present", main.world.farm.get_node("D03_veg_crates").visible and main.world.farm.get_node("F06_veggie_stand").visible)
	if _life():
		_moment(20, 12.0); _life().record_delivery("bread")
		check("a real current-day delivery appears on the supported counter", main.world.stall_bread.visible)
		_moment(20, 11.0)
		check("the delivered basket cannot appear before its recorded delivery time", not main.world.stall_bread.visible)
		_moment(20, 12.0)
		var before: Dictionary = _life().snapshot()
		var serial: Dictionary = GameState.to_dict().duplicate(true)
		GameState.from_dict(serial); _sync()
		check("load reconstructs the same lifecycle without changing its recorded deliveries", _life().snapshot() == before)
		var wrote: bool = GameState.save_game()
		GameState.flags.erase("scene_lifecycle")
		var loaded: bool = GameState.load_game(); _sync()
		check("actual isolated SQLite save and reload preserve the same delivered basket", wrote and loaded and _life().snapshot() == before and main.world.stall_bread.visible)
		_life().record_delivery("harvest", 2)
		check("a real stand sale produces the player's harvest basket with collision", harvest.visible and _solid(harvest) > 0)
		_moment(21, 12.0)
		check("next-day cleanup removes only that delivery basket and its collision", not harvest.visible and _solid(harvest) == 0 and main.world.farm.get_node("D03_veg_crates").visible)
		DailyLife.event("tea").state = "in_progress"; _moment(21, 23.0)
		check("an interrupted tea scene remains visible even when resumed at night", main.story.daily.view.tea_root.visible)
		GameState.quests.Q03 = {"state": "active", "step": 0}; GameState.plots.court.crop = ""; _sync()
		check("accepted planter work brings the real nursery tray onto the bench", tray.visible)
		GameState.plots.court.crop = "radish"; _sync()
		check("transplanting the crop puts away the emptied nursery tray", not tray.visible)
		GameState.flags.summer_projects.mainline_mode = "legacy"
		var step_index: int = 0
		for quest_step: Dictionary in GameState.quests_db.Q13.steps:
			if str(quest_step.id) == "give_wood": break
			step_index += 1
		GameState.quests.Q13 = {"state": "active", "step": step_index}; _moment(16, 10.0)
		check("legacy carry-to-deliver advancement never resurrects six already carried logs", int(logs.get_meta("remaining_logs", -1)) == 0 and not logs.get_node("RemainingBeams").get_children().any(func(beam: Node3D) -> bool: return beam.visible))
		GameState.flags.summer_projects.mainline_mode = "cooperation"
		GameState.flags.summer_space = {"version": 1, "phase": "invitation", "optional_wood": 0}
		GameState.flags.town_finished_Q13 = true
		GameState.quests.Q13 = {"state": "done", "step": GameState.quests_db.Q13.steps.size()}; _moment(16, 10.0)
		check("legacy resident completion does not silently display a finished festival on prep morning", not tower.visible and _solid(tower) == 0)
		_moment(17, 18.0)
		check("a resident fallback is visibly credited to residents rather than invented player work", tower.is_visible_in_tree() and str(main.world.fest_nodes.natsumatsuri.get_meta("assembled_by", "")) == "residents")
		_moment(17, 16.25)
		var fitted_captions: bool = true
		var caption_width: float = 0.0
		for label: Label3D in sign.find_children("*", "Label3D", true, false):
			for line: String in label.text.split("\n"):
				var physical_width: float = label.font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size
				caption_width = maxf(caption_width, physical_width)
				fitted_captions = fitted_captions and physical_width <= .981
		check("dynamic resident construction captions fit the actual board with six-centimetre margins", fitted_captions, "max_ink_width=%.4f board_available=.98" % caption_width)
	else:
		check("a real current-day delivery appears on the supported counter", false)
		check("load reconstructs the same lifecycle without changing its recorded deliveries", false)
	GameState.from_dict(saved); _sync()

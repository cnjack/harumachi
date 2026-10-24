extends RefCounted
## Exercise real models, colliders and existing story facts rather than invented inventory.
var t: Object
var main: Node
var _flow_finished := false

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
	check("ordinary days store the entire portable stage including its deck and collision", not stage.is_visible_in_tree() and _solid(stage) == 0 and found == 6 and ordinary)
	check("ordinary days store both the drum and filled fish tank with their collision", not main.world.goldfish_tank.is_visible_in_tree() and not main.world.taiko_drum.is_visible_in_tree() and _solid(main.world.goldfish_tank) == 0 and _solid(main.world.taiko_drum) == 0)
	check("stored festival equipment leaves no floating outdoor interaction", main.story.prompt_for("goldfish_pool").is_empty() and main.story.prompt_for("taiko_drum").is_empty())
	main.world.set_region("farm"); main.world.set_region("town")
	check("a region round trip cannot restore the stored top-level models or bodies", not stage.is_visible_in_tree() and not main.world.goldfish_tank.is_visible_in_tree() and not main.world.taiko_drum.is_visible_in_tree() and _solid(stage) + _solid(main.world.goldfish_tank) + _solid(main.world.taiko_drum) == 0)
	if _life():
		var cover: MeshInstance3D = main.world.taiko_drum.get_node("PracticeClothCover")
		check("the reusable cover is stored with the drum instead of displaying a covered drum every day", not cover.is_visible_in_tree())
		var cloth_material: ShaderMaterial = cover.material_override
		check("thin cloth renders both sides instead of culling the entire front drape", cloth_material.shader.code.contains("cull_disabled"))
		var covered_faces: bool = true
		for probe: Vector2 in [Vector2(0,.76),Vector2(.25,.76),Vector2(-.25,.76),Vector2(0,1.04),Vector2(0,.50)]:
			covered_faces = covered_faces and _cover_end(cover,probe,true) > .255 and _cover_end(cover,probe,false) < -.255
		check("the actual draped geometry covers both drum heads from crown to lower rim", covered_faces)
		_life().begin_practice("taiko")
		check("practice deploys the same drum and plain platform with collision but no speakers or fish tank", main.world.taiko_drum.is_visible_in_tree() and stage.is_visible_in_tree() and _solid(stage) > 0 and _solid(main.world.taiko_drum) > 0 and not cover.visible and not stage.find_child("SpeakerCharcoal", true, false).visible and not main.world.goldfish_tank.is_visible_in_tree())
		_life().end_practice("taiko")
		check("finishing practice stores both drum and platform and removes their outdoor prompts", not main.world.taiko_drum.is_visible_in_tree() and not stage.is_visible_in_tree() and _solid(main.world.taiko_drum) + _solid(stage) == 0 and main.story.prompt_for("taiko_drum").is_empty())
		await _festival_loan_checks()
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
	check("the actual festival opens the stage drum and tank together with their interaction and collision", stage.is_visible_in_tree() and main.world.taiko_drum.is_visible_in_tree() and main.world.goldfish_tank.is_visible_in_tree() and _solid(stage) > 0 and _solid(main.world.taiko_drum) > 0 and _solid(main.world.goldfish_tank) > 0 and not main.story.prompt_for("taiko_drum").is_empty() and not main.story.prompt_for("goldfish_pool").is_empty())
	if _life(): check("formal festival opening uncovers the playable drum", not main.world.taiko_drum.get_node("PracticeClothCover").visible)
	main.world.set_region("farm"); _sync()
	check("leaving town disables every collision in the hidden festival subtree", not main.world.fest_nodes.natsumatsuri.visible and _solid(main.world.fest_nodes.natsumatsuri) == 0)
	check("leaving town also disables the separate stage drum and pool bodies and interaction", _solid(stage) + _solid(main.world.taiko_drum) + _solid(main.world.goldfish_tank) == 0 and main.story.prompt_for("goldfish_pool").is_empty() and main.story.prompt_for("taiko_drum").is_empty())
	main.world.set_region("town"); _sync()
	check("returning restores the same tower and real festive collision", tower.is_visible_in_tree() and _solid(tower) > 0)
	_moment(17, 22.1)
	var festival_items: Node3D = main.world.fest_nodes.natsumatsuri.get_node("ModelDiversity")
	check("cleanup briefly retains substantial frames but packs away mask and scoop displays", tower.is_visible_in_tree() and not festival_items.visible and _solid(festival_items) == 0)
	check("cleanup drains and stores the games immediately while the platform awaits dismantling", stage.is_visible_in_tree() and not main.world.taiko_drum.is_visible_in_tree() and not main.world.goldfish_tank.is_visible_in_tree() and _solid(main.world.taiko_drum) + _solid(main.world.goldfish_tank) == 0 and main.story.prompt_for("goldfish_pool").is_empty())
	_moment(17, 22.7)
	check("cleanup ends with no solid festival object left behind", not tower.is_visible_in_tree() and _solid(main.world.fest_nodes.natsumatsuri) == 0)
	check("the portable platform also leaves the lawn when cleanup ends", not stage.is_visible_in_tree() and _solid(stage) == 0)
	_moment(18, 10.0)
	check("the completed festival removes the tower and its collision together", not tower.is_visible_in_tree() and _solid(tower) == 0)
	check("the next ordinary day does not resurrect the festival games or their E points", not stage.is_visible_in_tree() and not main.world.taiko_drum.is_visible_in_tree() and not main.world.goldfish_tank.is_visible_in_tree() and main.story.prompt_for("goldfish_pool").is_empty() and main.story.prompt_for("taiko_drum").is_empty())
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
		check("the real scheduled preparation hour deploys covered equipment before opening", stage.is_visible_in_tree() and main.world.goldfish_tank.is_visible_in_tree() and main.world.taiko_drum.is_visible_in_tree() and main.world.taiko_drum.get_node("PracticeClothCover").is_visible_in_tree() and str(stage.get_meta("lifecycle_state", "")) == "ready")
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


func _games_stored() -> bool:
	var stage: Node3D = main.world.get_node("P10")
	return not stage.is_visible_in_tree() and not main.world.taiko_drum.is_visible_in_tree() and not main.world.goldfish_tank.is_visible_in_tree() and _solid(stage) + _solid(main.world.taiko_drum) + _solid(main.world.goldfish_tank) == 0 and main.story.prompt_for("goldfish_pool").is_empty() and main.story.prompt_for("taiko_drum").is_empty()

func _finish_flow(flow: String) -> void:
	_flow_finished = false
	if flow == "promise": await main.story.lore._goldfish_promise()
	else: await main.story.call("_i_" + flow)
	_flow_finished = true

func _cancel_live_game(flow: String) -> Dictionary:
	main.ui.instant = false
	main.ui.auto = false
	main.story.busy = true
	_finish_flow(flow)
	var deadline: int = Time.get_ticks_msec() + 5000
	while not is_instance_valid(main.ui.active_mg) and not _flow_finished and Time.get_ticks_msec() < deadline:
		await main.get_tree().process_frame
		if main.ui.dlg_choices.visible: main.ui.choice_made.emit(1 if flow == "festival_storage" else 0)
		elif main.ui.dlg.visible: main.ui.dialogue_advance.emit()
	var had_game: bool = is_instance_valid(main.ui.active_mg)
	var deployed: bool = main.world.goldfish_tank.is_visible_in_tree() if flow == "promise" else main.world.taiko_drum.is_visible_in_tree()
	if had_game:
		main.ui.active_mg._leave()
	while not _flow_finished and Time.get_ticks_msec() < deadline:
		await main.get_tree().process_frame
		if main.ui.dlg_choices.visible: main.ui.choice_made.emit(3)
		elif main.ui.dlg.visible: main.ui.dialogue_advance.emit()
	main.ui.instant = true
	main.ui.dialogue_end()
	main.story.busy = false
	return {"finished": _flow_finished, "game": had_game, "deployed": deployed}

func _festival_loan_checks() -> void:
	var saved: Dictionary = GameState.to_dict().duplicate(true)
	var player_at: Vector3 = main.player.global_position
	var player_facing: float = main.player.model_root.rotation.y
	var mio: NPC = main.npcs.mio
	var mio_at: Vector3 = mio.global_position
	var mio_facing: float = mio.rotation.y
	var mio_home: bool = mio.home
	var mio_visible: bool = mio.visible
	GameState.new_game(); GameState.clock_paused = true
	_moment(1, 11.0)
	var outer: int = _life().begin_practice("goldfish")
	var nested: int = _life().begin_practice("goldfish")
	check("borrowing the fish tank deploys only the real tank and enables its existing anchor", main.world.goldfish_tank.is_visible_in_tree() and _solid(main.world.goldfish_tank) > 0 and not main.world.get_node("P10").is_visible_in_tree() and not main.world.taiko_drum.is_visible_in_tree() and not main.story.prompt_for("goldfish_pool").is_empty())
	_life().end_practice("goldfish", nested)
	check("a nested photo return cannot pack away an outer shared fish scene", main.world.goldfish_tank.is_visible_in_tree() and _solid(main.world.goldfish_tank) > 0)
	_life().end_practice("goldfish", outer)
	check("returning the final fish loan removes the tank collision and prompt", _games_stored())
	var interrupted: int = _life().begin_practice("taiko")
	var wrote: bool = GameState.save_game()
	var loaded: bool = GameState.load_game(); _sync()
	_life().end_practice("taiko", interrupted)
	check("an actual SQLite reload restores ordinary storage rather than an interrupted practice loan", wrote and loaded and _games_stored())
	var overnight: int = _life().begin_practice("goldfish")
	_moment(2, 8.0)
	_life().end_practice("goldfish", overnight)
	check("an interrupted loan cannot survive into the next game day", _games_stored())
	main.ui.auto_choices = [3]
	await main.story._i_festival_storage()
	check("declining the real community storage menu leaves every item stored", _games_stored())
	var taiko_plays: int = int(GameState.mg_record("taiko").plays)
	main.ui.auto_choices = [1]
	await main.story._i_festival_storage()
	check("the existing community doorway reaches a real taiko round and returns its borrowed setup", int(GameState.mg_record("taiko").plays) == taiko_plays + 1 and _games_stored())
	var goldfish_plays: int = int(GameState.mg_record("goldfish").plays)
	main.ui.auto_choices = [2]
	await main.story._i_festival_storage()
	check("the same storage doorway reaches a rewarded fish round without leaving a filled pool outside", int(GameState.mg_record("goldfish").plays) == goldfish_plays + 1 and _games_stored())
	var coins: int = GameState.coins
	var cancelled: Dictionary = await _cancel_live_game("festival_storage")
	check("leaving the actual taiko intro releases the visible drum and stage without awarding a round", cancelled.finished and cancelled.game and cancelled.deployed and _games_stored() and GameState.coins == coins, str(cancelled))
	GameState.quests.Q14 = {"state": "active", "step": 2}
	_moment(18, 19.0)
	var warmth: int = int(GameState.warmth.get("mio", 0))
	main.ui.auto_choices = [3]
	await main.story.lore._goldfish_promise()
	check("postponing the late shared scene returns its tank without advancing Q14 or warmth", _games_stored() and GameState.at_step("Q14", "goldfish_mio") and int(GameState.warmth.get("mio", 0)) == warmth and not GameState.flags.has("summer_shared"))
	var shared_cancel: Dictionary = await _cancel_live_game("promise")
	check("cancelling the actual shared goldfish countdown returns the tank and preserves the pending promise", shared_cancel.finished and shared_cancel.game and shared_cancel.deployed and _games_stored() and GameState.at_step("Q14", "goldfish_mio") and not GameState.flags.has("summer_shared"), str(shared_cancel))
	main.story.npcs.erase("mio")
	var photo_without_mio: bool = await main.story.lore._photo()
	main.story.npcs.mio = mio
	check("a photo that cannot find its companion safely returns the borrowed tank", not photo_without_mio and _games_stored() and not Progress.found("col_photo_new"))
	GameState.quests.Q14 = {"state": "available", "step": 0}
	main.ui.auto_choices = [0, 1, 1, 2]
	await main.story.lore._reunion()
	check("a real reunion still completes Q14 by watching fish then packs away the tank", GameState.qstate("Q14") == "done" and str(GameState.flags.get("summer_shared", {}).get("participation", "")) == "watched" and int(GameState.flags.get("summer_gathering", {}).get("reunion_day", -1)) == GameState.day and _games_stored())
	var photo: bool = await main.story.lore._photo()
	check("optional later photography borrows a real tank and returns it while preserving the saved photo", photo and Progress.found("col_photo_new") and FileAccess.file_exists(GameState.photo_path()) and _games_stored())
	GameState.from_dict(saved); _sync()
	main.player.global_position = player_at
	main.player.set_facing(player_facing)
	mio.place(mio_at, rad_to_deg(mio_facing)); mio.home = mio_home; mio.visible = mio_visible
	main.ui.auto_choices = []
	main.ui.dialogue_end()

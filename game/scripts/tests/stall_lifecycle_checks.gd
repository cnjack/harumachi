extends RefCounted
## The portable stall must have a real use, real stock and a reachable interaction.
var t: Object
var main: Node

func _init(runner: Object) -> void:
	t = runner; main = runner.main

func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("STALL_LIFECYCLE", label, ok, detail)

func _sync() -> void:
	main.world.lifecycle.sync_state()

func _solid(root: Node) -> int:
	var count := 0
	for body: StaticBody3D in root.find_children("*", "StaticBody3D", true, false):
		if body.collision_layer & (WorldBuilder.L_SOLID | WorldBuilder.L_PLACED): count += 1
	return count

func _fresh(day: int = 2, hour: float = 11.0) -> void:
	GameState.new_game(); GameState.clock_paused = true
	GameState.day = day; GameState.minute = hour * 60.0
	GameState.flags.arrival_home.phase = "done"
	main.in_room = false; main.room_kind = ""
	main.world.set_indoor_look(false); main.world.set_region("town")
	_sync()

func run() -> void:
	var saved: Dictionary = GameState.to_dict().duplicate(true)
	var stall: Node3D = main.world.get_node("P09")
	_fresh()
	check("ordinary courtyard stores the portable P09 frame and its collision", not stall.is_visible_in_tree() and _solid(stall) == 0)
	check("a stored stall leaves neither displayed food nor either outdoor E prompt", not main.world.stall_bread.is_visible_in_tree() and main.story.prompt_for("stall").is_empty() and main.story.prompt_for("opening_site").is_empty())
	main.world.set_region("farm"); main.world.set_region("town")
	check("returning to town cannot resurrect the stored frame or its collision", not stall.is_visible_in_tree() and _solid(stall) == 0)
	GameState.quests.Q02 = {"state": "active", "step": 0}; _sync()
	check("accepting bread work without receiving the basket does not set out an empty stall", not stall.is_visible_in_tree() and not main.world.stall_bread.is_visible_in_tree())
	GameState.quests.Q02.step = 1
	GameState.add_item("bread_basket", 1, true); GameState.tracked_quest = "Q02"; _sync()
	check("a basket ready for delivery deploys a prepared counter without inventing displayed bread", stall.is_visible_in_tree() and _solid(stall) > 0 and not main.world.stall_bread.is_visible_in_tree() and str(stall.get_meta("lifecycle_state", "")) == "preparing")
	var point: Variant = main.story.physical_point("stall")
	var marker: Variant = main.story.marker_target()
	check("Q02 keeps its real outdoor delivery target and E action", point is Vector3 and marker is Vector3 and (point as Vector3).distance_to(Vector3(2, 1, 13.9)) < .01 and (marker as Vector3).distance_to((point as Vector3) + Vector3.UP * 1.6) < .01 and main.story.prompt_for("stall") == "放下面包篮")
	await t.frames(2)
	var approach := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new(); capsule.radius = .3; capsule.height = 1.5
	approach.shape = capsule; approach.transform = Transform3D(Basis.IDENTITY, Vector3(2, .8, 13.9))
	approach.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED
	check("the delivery target leaves a full standing capsule clear of the deployed counter", main.world.get_world_3d().direct_space_state.intersect_shape(approach, 1).is_empty())
	await main.story._i_stall(); _sync()
	check("actual delivery consumes the basket and exposes bread on the same supported counter", GameState.qstate("Q02") == "done" and GameState.count("bread_basket") == 0 and stall.is_visible_in_tree() and main.world.stall_bread.is_visible_in_tree())
	check("the delivered basket remains on the measured P09 counter", main.world.stall_bread_surface.is_finite() and absf(main.world.stall_bread.global_position.y - .06 - main.world.stall_bread_surface.y) < .002)
	GameState.save_game(); GameState.load_game(); GameState.clock_paused = true; _sync()
	check("SQLite reload restores the actual same-day delivery together with its frame", stall.is_visible_in_tree() and main.world.stall_bread.is_visible_in_tree() and _solid(stall) > 0)
	main.world.set_region("farm")
	check("leaving town stores the counter, food, collision and E action together", not stall.is_visible_in_tree() and not main.world.stall_bread.is_visible_in_tree() and _solid(stall) == 0 and main.story.prompt_for("stall").is_empty())
	main.world.set_region("town")
	check("returning during a delivery day restores stock with its real support", stall.is_visible_in_tree() and main.world.stall_bread.is_visible_in_tree() and _solid(stall) > 0)
	main.world.set_indoor_look(true, "bakery"); _sync()
	check("entering an interior removes outdoor stall food collision and prompts together", not stall.is_visible_in_tree() and not main.world.stall_bread.is_visible_in_tree() and _solid(stall) == 0 and main.story.prompt_for("stall").is_empty())
	main.world.set_indoor_look(false); _sync()
	GameState.day += 1; _sync()
	check("the next ordinary day stores both yesterday's bread and the frame", not stall.is_visible_in_tree() and not main.world.stall_bread.is_visible_in_tree() and _solid(stall) == 0 and main.story.prompt_for("stall").is_empty())
	_fresh(6, 18.0); GameState.phase = "market"; GameState.quests.Q05 = {"state": "done", "step": 5}; _sync()
	check("an open weekend market deploys a stocked solid stall", stall.is_visible_in_tree() and main.world.stall_bread.is_visible_in_tree() and _solid(stall) > 0)
	GameState.add_item("tomato", 3, true)
	check("market vegetable and dish sales retain their existing interaction", main.story.farm.handles("stall") and main.story.prompt_for("stall").contains("卖"))
	GameState.phase = "prep"; GameState.minute = 23 * 60.0; _sync()
	check("market closure removes the frame, stock and collision without waiting for another day", not stall.is_visible_in_tree() and not main.world.stall_bread.is_visible_in_tree() and _solid(stall) == 0)
	_fresh()
	check("permanent pergola bicycle shelter and recycling shelter remain in place", main.world.get_node("P01").is_visible_in_tree() and main.world.get_node("H05").is_visible_in_tree() and main.world.get_node("R10").is_visible_in_tree())
	var helper: Node = main.world.lifecycle.get("stalls") as Node
	if helper != null:
		await _use_checks(helper, stall)
	GameState.from_dict(saved); GameState.clock_paused = true; _sync()

func _use_checks(helper: Node, stall: Node3D) -> void:
	check("preparation reuses a measured empty tray rather than inventing a food delivery", helper.preparation_supported and helper.preparation.get_node_or_null("PreparationTray") != null and helper.preparation.get_node("PreparationTray").get_meta("model_id", "") == "W12_cedar_tray")
	var owner_scene := Node3D.new(); main.add_child(owner_scene)
	var loan: int = helper.begin_tasting(owner_scene)
	check("a real tasting borrows the same solid counter and clean preparation tray", loan >= 0 and stall.is_visible_in_tree() and _solid(stall) > 0 and helper.preparation.is_visible_in_tree() and not main.world.stall_bread.is_visible_in_tree())
	helper.end_tasting(loan)
	check("cancelled tasting returns the frame and tray without recording delivered bread", not stall.is_visible_in_tree() and _solid(stall) == 0 and not helper.preparation.is_visible_in_tree() and GameState.flags.get("scene_lifecycle", {}).get("deliveries", {}).is_empty())
	loan = helper.begin_tasting(owner_scene)
	GameState.save_game(); GameState.load_game(); GameState.clock_paused = true; _sync()
	check("a real SQLite reload cannot restore a session-only tasting loan", not stall.is_visible_in_tree() and _solid(stall) == 0 and main.story.prompt_for("stall").is_empty())
	helper.end_tasting(loan)
	loan = helper.begin_tasting(owner_scene); GameState.day += 1; _sync()
	check("a new day returns an interrupted temporary counter even while its owner node survives", not stall.is_visible_in_tree() and _solid(stall) == 0)
	helper.end_tasting(loan); owner_scene.queue_free()
	GameState.quests.Q05 = {"state": "active", "step": 1}; _sync()
	check("Q05 seating preparation has a clean physical counter without pretending food was delivered", stall.is_visible_in_tree() and helper.preparation.is_visible_in_tree() and not main.world.stall_bread.is_visible_in_tree())
	GameState.quests.Q05.state = "done"; _sync()
	check("finishing an old preparation task alone cannot keep an empty stall outside", not stall.is_visible_in_tree() and _solid(stall) == 0)
	_fresh()
	GameState.quests.Q01 = {"state": "done", "step": 2}
	SummerProjects.accept("host"); SummerProjects.choose_plan("sandwich", "shop"); SummerProjects.claim_kit(); SummerProjects.shop_prepares()
	_sync()
	var batch: Dictionary = SummerProjects.current_batch()
	check("an unfinished sample in inventory does not leave a permanent empty stall", not stall.is_visible_in_tree() and GameState.count(str(batch.iid)) == 3)
	var actor: NPC = main.npcs.mio
	actor.home = false; actor.visible = true; actor.place(Vector3(1.1, 0, 14.1), 0)
	main.player.global_position = Vector3(2.7, .05, 14.1)
	var was_instant: bool = main.ui.instant
	main.ui.instant = false; main.story.busy = true; main.player.frozen = true
	var tasting := ProjectTasting.new(); main.add_child(tasting)
	tasting.run(main.story, "mio", "paper")
	await t.frames(3)
	var started: bool = tasting.active
	tasting.aborted = true; actor.cancel_safe_walk()
	var deadline: int = Time.get_ticks_msec() + 5000
	while tasting.active and Time.get_ticks_msec() < deadline: await t.frames(1)
	check("cancelling the actual tasting action returns its borrowed counter and preserves all samples", started and not tasting.active and not stall.is_visible_in_tree() and _solid(stall) == 0 and GameState.count(str(batch.iid)) == 3 and batch.tasters.is_empty())
	tasting.queue_free(); main.ui.instant = was_instant; main.story.busy = false; main.player.frozen = false; main.ui.dialogue_end()
	var opening: Dictionary = SummerProjects.opening()
	opening.final = {"menu": "sandwich", "portion": "bite", "presentation": "paper", "trial_batch": int(batch.id)}
	opening.service = {"source": "shop", "maker": "ren", "remaining": 2, "servings": 3, "served": {"mio": GameState.day}, "day": GameState.day, "trial_batch": int(batch.id)}
	opening.phase = "applied"; GameState.phase = "market"
	var view: ProjectView
	for child: Node in main.get_children():
		if child is ProjectView: view = child; break
	if view == null:
		check("the cooperative food display is registered with the stall lifecycle", false); return
	view.sync_state()
	var portions: Array[Node] = view.food.find_children("Serving_*", "Node3D", false, false)
	check("cooperative service displays its two recorded remaining portions without a duplicate bread basket", stall.is_visible_in_tree() and view.food.is_visible_in_tree() and portions.size() == 2 and not main.world.stall_bread.is_visible_in_tree())
	var instance_ids: Array = portions.map(func(node: Node) -> int: return node.get_instance_id())
	main.world.set_region("farm")
	var hidden_stock: bool = not view.food.is_visible_in_tree() and not stall.is_visible_in_tree() and _solid(stall) == 0
	main.world.set_region("town")
	portions = view.food.find_children("Serving_*", "Node3D", false, false)
	check("region changes hide and restore the same portions without rebuilding the food meshes", hidden_stock and view.food.is_visible_in_tree() and portions.map(func(node: Node) -> int: return node.get_instance_id()) == instance_ids)
	opening.service.remaining = 0; view.sync_state()
	check("an exhausted service keeps its empty tray for closing and never refills itself with resident bread", stall.is_visible_in_tree() and helper.preparation.is_visible_in_tree() and not view.food.is_visible_in_tree() and not main.world.stall_bread.is_visible_in_tree())
	GameState.phase = "prep"; SummerProjects.finish(); _sync()
	check("closing an exhausted service stores its tray frame collision and both outdoor interactions", not stall.is_visible_in_tree() and not helper.preparation.is_visible_in_tree() and _solid(stall) == 0 and main.story.prompt_for("stall").is_empty() and main.story.prompt_for("opening_site").is_empty())

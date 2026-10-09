extends Node
## Rendered acceptance path, including the exported app (no dependency on excluded tests).
## Launch with --newgame --bakery-demo and an isolated HARUMACHI_SAVE_DIR.
var main: Node
var G: Node
var results: Array = []

func _ready() -> void:
	main = get_parent()
	G = GameState
	await _frames(15)
	main.ui.instant = true
	G.clock_paused = true
	NPC.roam_enabled = false
	Progress.quiet = true
	G.new_game()
	G.day = 4
	G.minute = 10.0 * 60.0
	G.quests["Q05"] = {"state": "done", "step": 5}
	G.quests["Q06"] = {"state": "done", "step": 5}
	for qid in ["Q00", "Q01", "Q02", "Q03", "Q04"]:
		G.quests[qid] = {"state": "done", "step": G.quests_db[qid].steps.size()}
	for who in ["mio", "ren", "haru", "tanaka"]:
		G.flags["met_" + who] = true
	main.story.bakery.checks()
	main.update_npcs(true)
	_check("invitation", G.qstate("Q16") == "available")
	await _visit("bakery", "bakery_orders", [0])
	_check("trial kit and recipe", G.recipe_known("veg_sandwich") and G.count("tomato") == 2)
	await _visit("bakery", "bakery_oven", [{"craft": {"veg_sandwich": 1}}])
	_check("real oven", G.at_step("Q16", "bakery_trial") and G.has("veg_sandwich"))
	await _visit("bakery", "bakery_orders")
	await _use("mio")
	await _visit("shop_store", "store_counter")
	_check("two residents", G.at_step("Q16", "bakery_menu") and G.flags.get("bakery_tasters", {}).size() == 2)
	await _visit("bakery", "bakery_orders", [1])
	_check("choice and reservation", int(G.flags.get("bakery_menu", -1)) == 1 and G.reserved_count("tomato") == 2)
	G.add_item("tomato", 4, true)
	G.add_item("cucumber", 2, true)
	await _visit("shop_store", "store_counter", [{"sell": {"tomato": -1, "cucumber": -1}}])
	_check("sell-all preserves order", G.count("tomato") == 2 and G.count("cucumber") == 1)
	main.ui.instant = false
	main.ui.panels.open_bakery_order()
	await _frames(8)
	await _capture("order")
	main.ui.close_modal()
	main.ui.instant = true
	G.day = int(G.flags.get("bakery_due_day", 10))
	G.minute = 17.0 * 60.0
	G.phase = "market"
	main.update_npcs(true)
	var before: int = G.coins
	await _use("stall", [0])
	_check("stall delivery", G.at_step("Q16", "bakery_followup") and G.coins > before and not G.has("tomato"))
	G.day += 1
	G.minute = 10.0 * 60.0
	G.phase = "prep"
	main.update_npcs(true)
	await _visit("bakery", "bakery_orders", [1])
	_check("rest week", G.qstate("Q16") == "done" and not G.flags.get("bakery_order_active", false))
	G.save_game()
	G.flags.clear()
	G.load_game()
	_check("SQLite persistence", G.flags.get("bakery_first_served", false) and int(G.flags.get("bakery_menu", -1)) == 1)
	await _use("bakery")
	main.update_npcs(true)
	G.skip_to(G.minute + 1.0)
	var keeper_spec: Dictionary = InteriorBuilder.spec_for("bakery")
	_check("festival-day keeper stays indoors", main.npcs.ren.global_position.distance_to(keeper_spec.origin + keeper_spec.keeper) < 0.1)
	main.player.global_position = InteriorBuilder.SPECS.bakery.origin + Vector3(-2.35, 0.05, 2.7)
	main.rig.pitch = 22.0
	main.rig.dist = 4.3
	main.rig.snap()
	await _frames(20)
	await _capture("bakery")
	await _use("bakery_exit")
	G.day = 25
	G.minute = 10.0 * 60.0
	G.quests["Q14"] = {"state": "available", "step": 0}
	main.story.lore.checks()
	main.update_npcs(true)
	await _use("mio", [0, 1])
	_check("missed festival reunion", G.qstate("Q14") == "done" and G.flags.get("summer_reunion", false) and int(G.flags.get("summer_promise", -1)) == 1 and not G.flags.get("fest_bon_odori", false))
	_check("isolated rendered photo", FileAccess.file_exists(G.photo_path()))
	G.quests["Q15"] = {"state": "active", "step": 1}
	G.flags["met_tanaka"] = true
	main.world.set_region("farm")
	main.update_npcs(true)
	await _use("farm_bench")
	_check("missed fireworks continuation", G.qstate("Q15") == "done" and G.flags.get("hanabi_revisit", false) and not G.flags.get("fest_hanabi", false))
	var failed: int = results.filter(func(row): return not row.ok).size()
	var out := _arg("demo-out", "")
	if out != "":
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "checks": results.size(), "failed": failed, "renderer": DisplayServer.get_name(), "fixture": "Q05 and Q06 completed; all new actions use the real interactables", "results": results}, "  "))
		file.close()
	print("BAKERY DEMO: %d checks, %d failed" % [results.size(), failed])
	Audio.silence()
	await _frames(3)
	get_tree().quit(1 if failed > 0 else 0)

func _frames(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame

func _arg(key: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + key + "="):
			return arg.split("=", true, 1)[1]
	return fallback

func _capture(name: String) -> void:
	var directory := _arg("demo-shots", "")
	if directory == "" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(directory)
	main.ui.toast_box.visible = false
	main.ui.panels.set_cards_visible(false)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(name + ".png"))

func _check(name: String, ok: bool) -> void:
	results.append({"name": name, "ok": ok})
	print(("PASS " if ok else "FAIL ") + name)

func _use(id: String, choices: Array = []) -> bool:
	var point: Interactable
	for node in get_tree().get_nodes_in_group("interactables"):
		if (node as Interactable).id == id:
			point = node
	if point == null:
		_check("point exists: " + id, false)
		return false
	var distance := 0.55 if id == "shop_store" else 1.2
	var from: Vector3 = main.player.global_position
	var at: Vector3 = point.global_position
	var direction := Vector3(from.x - at.x, 0, from.z - at.z)
	if direction.length() < 0.1 or direction.length() > 30.0:
		var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
		for candidate in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + candidate * 1.4, WorldBuilder.L_SOLID)).is_empty():
				direction = candidate
				break
	direction = direction.normalized()
	main.player.global_position = Vector3(at.x, 0.1, at.z) + direction * distance
	main.player.velocity = Vector3.ZERO
	main.player.face_towards(point.global_position)
	await _frames(3)
	main.ui.auto_choices = choices.duplicate()
	if main.player.target != point:
		_check("targetable: " + id, false)
		return false
	await main.story.interact(point)
	await _frames(3)
	return true

func _visit(door: String, point: String, choices: Array = []) -> void:
	await _use(door)
	await _frames(8)
	if not main.in_room:
		_check("entered " + door, false)
		return
	await _use(point, choices)
	await _use("bakery_exit" if door == "bakery" else "store_exit")
	await _frames(8)

extends Node
## Headless acceptance tests. Runs the real main scene in "instant" UI mode and drives the
## story through the same interactables the player uses.
##   godot --headless --path game res://scenes/tests.tscn -- --out=<json>
## Exit code 0 = all checks passed.

var results: Array = []
var main: Node
var G: Node


func check(case_id: String, name: String, ok: bool, detail: String = "") -> void:
	results.append({"case": case_id, "name": name, "ok": ok, "detail": detail})
	print(("PASS " if ok else "FAIL ") + "[" + case_id + "] " + name + ("" if detail == "" else "  — " + detail))


func _ready() -> void:
	G = GameState
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-db="):
			G.SAVE_PATH = arg.trim_prefix("--test-db=")
			G.SAVE_BAK = G.SAVE_PATH.get_basename() + ".backup.db"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(G.SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(G.SAVE_BAK))
	G.new_game()
	G.clock_paused = true
	NPC.roam_enabled = false      # activity loops are checked on their own in crowd_checks()
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.ui.instant = true
	main.ui.auto_work_priority = true # this suite follows its declared work route; the topic-choice suite overrides it
	await frames(10)
	if OS.get_cmdline_user_args().has("--only=inhabited"):
		await load("res://scripts/tests/inhabited_places_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=public-art"):
		await load("res://scripts/tests/public_place_art_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=foliage-depth"):
		await load("res://scripts/tests/foliage_depth_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=plaza-quality"):
		await load("res://scripts/tests/plaza_quality_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=scene-quality"):
		await load("res://scripts/tests/scene_quality_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=motion-clarity"):
		await load("res://scripts/tests/motion_clarity_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=camera-body"):
		await load("res://scripts/tests/camera_body_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=resident-morning"):
		await load("res://scripts/tests/resident_morning_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=layout-validity"):
		await load("res://scripts/tests/layout_validity_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=project-tasting"):
		await load("res://scripts/tests/project_tasting_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=shop-life"):
		await load("res://scripts/tests/shop_life_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=bunting"):
		await load("res://scripts/tests/bunting_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=npc-overlap"):
		await load("res://scripts/tests/npc_overlap_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=environment-life"):
		await load("res://scripts/tests/environment_life_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=core"):
		await run_all()
	elif OS.get_cmdline_user_args().has("--only=meal-plate"):
		await load("res://scripts/tests/meal_plate_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=world-behaviour"):
		await load("res://scripts/tests/world_behaviour_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=arrival-home"):
		await load("res://scripts/tests/arrival_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=meal-routes"):
		await load("res://scripts/tests/meal_route_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=neighbour-meal"):
		await load("res://scripts/tests/neighbour_meal_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=food-purpose"):
		await load("res://scripts/tests/food_purpose_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=summer-flow"):
		await load("res://scripts/tests/summer_flow_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=summer-gathering"):
		await load("res://scripts/tests/gathering_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=calendar-advance"):
		await load("res://scripts/tests/calendar_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=summer-space"):
		await load("res://scripts/tests/space_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=space-entry"):
		await load("res://scripts/tests/space_entry_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=project-entry"):
		await load("res://scripts/tests/summer_project_checks.gd").new(self).mainline_checks()
	elif OS.get_cmdline_user_args().has("--only=summer-workshop"):
		await load("res://scripts/tests/workshop_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=summer-projects"):
		await load("res://scripts/tests/summer_project_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=summer-foundation"):
		await load("res://scripts/tests/summer_foundation_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=daily-life"):
		await load("res://scripts/tests/daily_life_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=fun-contracts"):
		await load("res://scripts/tests/fun_contract_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=crowd"):
		await crowd_checks()
		prologue_checks()
	elif OS.get_cmdline_user_args().has("--only=props"):
		await props_checks()
	elif OS.get_cmdline_user_args().has("--only=walls"):
		wall_material_checks()
	elif OS.get_cmdline_user_args().has("--only=shop-build"):
		shop_build_checks()
	elif OS.get_cmdline_user_args().has("--only=materials"):
		material_checks()
	elif OS.get_cmdline_user_args().has("--only=model-audit"):
		model_inventory_checks()
	elif OS.get_cmdline_user_args().has("--only=architecture"):
		architecture_checks()
	elif OS.get_cmdline_user_args().has("--only=storage"):
		storage_checks()
		loading_checks()
	elif OS.get_cmdline_user_args().has("--only=narrative"):
		narrative_regressions()
		await load("res://scripts/tests/narrative_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=keepers"):
		await keeper_continuity_checks()
	elif OS.get_cmdline_user_args().has("--only=bakery-display"):
		bakery_display_check()
	elif OS.get_cmdline_user_args().has("--only=lakeside-polish"):
		await load("res://scripts/tests/lakeside_polish_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=lakeside"):
		await load("res://scripts/tests/lakeside_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=homage"):
		await load("res://scripts/tests/homage_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=display"):
		await load("res://scripts/tests/display_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=ui-map"):
		await load("res://scripts/tests/ui_map_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=ui-kit"):
		await load("res://scripts/tests/ui_kit_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=dialogue-ui"):
		await load("res://scripts/tests/dialogue_ui_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=placement"):
		await load("res://scripts/tests/placement_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=save-slots"):
		await load("res://scripts/tests/save_slot_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=hero-tree"):
		await load("res://scripts/tests/hero_tree_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=foliage-library"):
		await load("res://scripts/tests/foliage_library_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=scene-polish"):
		await load("res://scripts/tests/scene_polish_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=town-detail"):
		await load("res://scripts/tests/town_detail_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=living"):
		await load("res://scripts/tests/living_town_checks.gd").new(self).run()
	elif OS.get_cmdline_user_args().has("--only=daily-save"):
		await load("res://scripts/tests/daily_save_checks.gd").new(self).run()
	else:
		await run_all()
		await load("res://scripts/tests/lakeside_checks.gd").new(self).run()
		await load("res://scripts/tests/homage_checks.gd").new(self).run()
		await load("res://scripts/tests/display_checks.gd").new(self).run()
		await load("res://scripts/tests/ui_map_checks.gd").new(self).run()
		await load("res://scripts/tests/ui_kit_checks.gd").new(self).run()
		await load("res://scripts/tests/dialogue_ui_checks.gd").new(self).run()
		await load("res://scripts/tests/placement_checks.gd").new(self).run()
		await load("res://scripts/tests/daily_save_checks.gd").new(self).run()
		await load("res://scripts/tests/living_town_checks.gd").new(self).run()
		await load("res://scripts/tests/town_detail_checks.gd").new(self).run()
		await load("res://scripts/tests/scene_polish_checks.gd").new(self).run()
		await load("res://scripts/tests/save_slot_checks.gd").new(self).run()
		await load("res://scripts/tests/foliage_library_checks.gd").new(self).run()
		await load("res://scripts/tests/hero_tree_checks.gd").new(self).run()
		await load("res://scripts/tests/fun_contract_checks.gd").new(self).run()
		await load("res://scripts/tests/daily_life_checks.gd").new(self).run()
		await load("res://scripts/tests/summer_foundation_checks.gd").new(self).run()
		await load("res://scripts/tests/resident_morning_checks.gd").new(self).run()
		await load("res://scripts/tests/summer_project_checks.gd").new(self).run()
		await load("res://scripts/tests/camera_body_checks.gd").new(self).run()
		await load("res://scripts/tests/workshop_checks.gd").new(self).run()
		await load("res://scripts/tests/space_checks.gd").new(self).run()
		await load("res://scripts/tests/calendar_checks.gd").new(self).run()
		await load("res://scripts/tests/gathering_checks.gd").new(self).run()
		await load("res://scripts/tests/summer_flow_checks.gd").new(self).run()
		await load("res://scripts/tests/food_purpose_checks.gd").new(self).run()
		await load("res://scripts/tests/neighbour_meal_checks.gd").new(self).run()
		await load("res://scripts/tests/meal_route_checks.gd").new(self).run()
		await load("res://scripts/tests/arrival_checks.gd").new(self).run()
		await load("res://scripts/tests/world_behaviour_checks.gd").new(self).run()
		await load("res://scripts/tests/meal_plate_checks.gd").new(self).run()
		await load("res://scripts/tests/layout_validity_checks.gd").new(self).run()
		await load("res://scripts/tests/project_tasting_checks.gd").new(self).run()
		await load("res://scripts/tests/npc_overlap_checks.gd").new(self).run()
		await load("res://scripts/tests/environment_life_checks.gd").new(self).run()
		await load("res://scripts/tests/lakeside_polish_checks.gd").new(self).run()
		await load("res://scripts/tests/bunting_checks.gd").new(self).run()
		await load("res://scripts/tests/shop_life_checks.gd").new(self).run()
		await load("res://scripts/tests/motion_clarity_checks.gd").new(self).run()
		await load("res://scripts/tests/scene_quality_checks.gd").new(self).run()
		await load("res://scripts/tests/plaza_quality_checks.gd").new(self).run()
		await load("res://scripts/tests/foliage_depth_checks.gd").new(self).run()
		await load("res://scripts/tests/public_place_art_checks.gd").new(self).run()
		await load("res://scripts/tests/inhabited_places_checks.gd").new(self).run()
	var fails := results.filter(func(r): return not r.ok).size()
	print("\n==== %d checks, %d failed ====" % [results.size(), fails])
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "checks": results.size(), "failed": fails, "results": results}, "  "))
		f.close()
	Audio.silence()
	await frames(3)
	get_tree().quit(1 if fails > 0 else 0)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## JSON round-trips float values with tiny decimal rounding; discrete/RNG state remains exact.
func state_equal(a: Variant,b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key: Variant in a:
			if not b.has(key) or not state_equal(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for index: int in a.size():
			if not state_equal(a[index],b[index]):return false
		return true
	if (a is float or a is int) and (b is float or b is int):return absf(float(a)-float(b))<.000000001
	return a==b


func narrative_regressions() -> void:
	var entry: Dictionary = {}
	var reward: Dictionary = {}
	for e in Dialogue.entries:
		if str(e.id) == "ev_mio4":
			entry = e
		if str(e.id) == "ev_ren4":
			reward = e.get("give", {})
	check("NARR", "Mio's history agrees with the resident who stayed", not JSON.stringify(entry).contains("我回晴町"))
	check("NARR", "Ren gives the sandwich described in his heart event", int(reward.get("veg_sandwich", 0)) == 1 and not reward.has("melon_pan"))
	var festival_source := FileAccess.get_file_as_string("res://scripts/story/story_fest.gd")
	check("NARR", "the first fireworks do not refer to a festival last year", not festival_source.contains("每年都在这里看烟花") and not festival_source.contains("比去年的大"))
	var snapshot: Dictionary = G.to_dict().duplicate(true)
	G.quests["Q05"] = {"state": "done", "step": 3}
	G.quests["Q14"] = {"state": "available", "step": 0}
	G.day = 18
	main.story.lore.checks()
	check("NARR", "a missed summer festival has a Mio continuation", main.story.lore.pending("mio"))
	G.quests["Q14"] = {"state": "done", "step": 3}
	G.quests["Q15"] = {"state": "active", "step": 1}
	G.day = 25
	check("NARR", "a missed fireworks night has a riverside continuation", main.story.lore.pending("farm_bench"))
	G.from_dict(snapshot)


func keeper_continuity_checks() -> void:
	var snapshot: Dictionary = G.to_dict().duplicate(true)
	main.world.set_region("town")
	G.day = 11
	G.minute = 11.0 * 60.0
	G.phase = "prep"
	G.clock_paused = true
	main.update_npcs(true)

	for shop in ["bakery", "store"]:
		await main.enter_interior(shop)
		var spec: Dictionary = InteriorBuilder.spec_for(shop)
		var who := "ren" if shop == "bakery" else "kazuko"
		main.update_npcs(true)
		G.skip_to(G.minute + 1.0)
		await frames(4)
		var keeper: NPC = main.npcs[who]
		check("KEEPER", "%s stays behind the counter during festival and minute updates" % shop, keeper.global_position.distance_to(spec.origin + spec.keeper) < 0.1 and keeper.fest_key == shop + ":counter")
		await main.exit_interior()
		await frames(4)
	check("KEEPER", "leaving the bakery restores Ren's festival assignment", main.npcs.ren.fest_key == "contest" and main.npcs.ren.global_position.x < 50.0)
	G.from_dict(snapshot)
	main.world.set_region(G.player_region)
	main.update_npcs(true)


func bakery_display_check() -> void:
	# Follow the actual CLI counter. A finite centre alone cannot support the basket rim.
	var bowl: MeshInstance3D = main.world.stall_bread.get_child(0) as MeshInstance3D
	var base: AABB = bowl.global_transform * bowl.get_aabb()
	var at: Vector3=main.world.stall_bread_surface
	var counter: Node3D=main.world.get_node_or_null("P09")
	var supported: bool=at.is_finite() and absf(base.position.y-at.y)<=.015
	if supported and counter!=null:
		for index: int in 8:
			var offset:=Vector3(cos(TAU*index/8.0)*.26,0,sin(TAU*index/8.0)*.26)
			var height: float=WorldBuilder.rendered_support_height(counter,at+offset,1.35,true)
			if not is_finite(height) or absf(height-base.position.y)>.02:supported=false
	else:supported=false
	check("BAKERY_DISPLAY", "the tasting basket perimeter rests on P09's actual counter", supported,"basket base %.3f, measured surface %s"%[base.position.y,at])

func point(id: String) -> Interactable:
	for n in get_tree().get_nodes_in_group("interactables"):
		if (n as Interactable).id == id:
			return n
	return null


## Walk-free teleport next to an interactable, facing it, then let the player pick targets.
func stand_at(id: String, dist: float = 1.2) -> Interactable:
	var it := point(id)
	var p: Vector3 = it.global_position
	var from: Vector3 = main.player.global_position
	var dir := Vector3(from.x - p.x, 0, from.z - p.z)
	if dir.length() < 0.1 or dir.length() > 30.0:
		dir = _free_side(it)
	dir = dir.normalized()
	var spot := Vector3(p.x, 0.1, p.z) + dir * dist
	main.player.global_position = spot
	main.player.velocity = Vector3.ZERO
	main.player.face_towards(p)
	return it


func _free_side(it: Interactable) -> Vector3:
	# pick the side of the target that has no solid body in the way
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	for d in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
		var q := PhysicsRayQueryParameters3D.create(it.global_position, it.global_position + d * 1.4, WorldBuilder.L_SOLID)
		if space.intersect_ray(q).is_empty():
			return d
	return Vector3(0, 0, -1)


func use(id: String, choices: Array = [], distance: float = 1.2) -> bool:
	var it := stand_at(id, distance)
	await frames(3)
	main.ui.auto_choices = choices.duplicate()
	if main.player.target != it:
		check("infra", "player can target " + id, false, "target=%s" % (main.player.target.id if main.player.target else "none"))
		return false
	await main.story.interact(it)
	await frames(2)
	return true


## v0.6: shops are rooms: go in through the street door, use a point inside, walk back out.
func shop_in(door: String, pt: String, choices: Array = [], door_distance: float = 1.2) -> bool:
	await use(door, [], door_distance)
	await frames(8)
	if not main.in_room:
		check("infra", "entered the shop through " + door, false, "closed? %s" % G.shop_closed_reason("store" if door == "shop_store" else "bakery"))
		return false
	var ok := await use(pt, choices)
	await use("bakery_exit" if door == "bakery" else "store_exit")
	await frames(8)
	return ok


func minigame_sfx() -> Array:
	var names := {}
	var re := RegEx.create_from_string("sfx\\(\"([a-z_]+)\"")
	for id in G.MINIGAMES:
		var src := FileAccess.get_file_as_string("res://scripts/minigames/mg_%s.gd" % id)
		for m in re.search_all(src):
			names[m.get_string(1)] = true
	for k in ["count", "go", "result", "don", "ka", "place"]:
		names[k] = true
	return names.keys()


## Inside the house: rooms, cut-away, surfaces, interaction points and the three home mini-games.
func house_checks() -> void:
	var house: HouseBuilder = main.world.house
	var O := HouseBuilder.ORIGIN
	check("HOUSE", "the player starts in the genkan", house.room_name(main.player.global_position) == "玄关" and house.current_room == "genkan")
	var ids: Array = []
	for n in get_tree().get_nodes_in_group("interactables"):
		ids.append((n as Interactable).id)
	var missing: Array = []
	for pt in HouseBuilder.POINTS:
		if not ids.has(pt[0]):
			missing.append(pt[0])
	check("HOUSE", "all %d house interaction points exist" % HouseBuilder.POINTS.size(), missing.is_empty(), ", ".join(missing))
	main.player.global_position = O + Vector3(2.2, 0.05, -0.9)
	await frames(4)
	check("HOUSE", "walking into the living room tracks the room", house.current_room == "living" and main.area_name() == "客厅")
	check("HOUSE", "cut-away drops the walls south of the living room and keeps the north glass wall",
		house.cut_groups["m_liv"].cut and house.cut_groups["s_ext"].cut and not house.cut_groups["n_liv"].cut)
	main.player.global_position = O + Vector3(-3.0, 0.05, 3.3)
	await frames(4)
	check("HOUSE", "in the kitchen the middle walls stand again", house.current_room == "kitchen" and not house.cut_groups["m_liv"].cut)
	check("HOUSE", "footsteps: tatami in the living room, stone in the genkan, wood in the kitchen",
		HouseBuilder.surface_at(O + Vector3(2.0, 0, -1.0)) == "tatami" and HouseBuilder.surface_at(O + Vector3(5.0, 0, 4.0)) == "stone"
		and HouseBuilder.surface_at(O + Vector3(-3.0, 0, 3.0)) == "wood")
	check("HOUSE", "daytime light shafts through the north openings", house.beams != null and house.beams.visible and house.beams.get_child_count() >= 5)
	check("HOUSE", "the move-in boxes are there and the map frame is empty", house.boxes.visible and not house.map_frame.visible)

	# mini-game framework: every game passes its own self-test and scoring sanity checks
	for id in G.MINIGAMES:
		var mg: MiniGame = load("res://scripts/minigames/mg_%s.gd" % id).new()
		mg.id = id
		main.ui.root.add_child(mg)
		await frames(1)
		var bad: Array = []
		for c in mg.mg_self_test():
			if not bool(c[1]):
				bad.append(str(c[0]))
		var th: Array = mg.info.get("stars", [])
		var sane: bool = th.size() == 3 and int(th[0]) < int(th[1]) and int(th[1]) < int(th[2]) \
			and mg.stars_for(mg.mg_simulate(1.0, 3)) == 3 and mg.stars_for(mg.mg_simulate(0.0, 3)) == 0
		mg.queue_free()
		check("MGF", "%s: self-test and star thresholds" % id, bad.is_empty() and sane, ", ".join(bad))
	await frames(2)

	# the three home mini-games through their interactions (instant mode plays at skill 0.85)
	var c0: int = G.coins
	main.player.global_position = O + Vector3(2.0, 0.05, 2.0)   # hall, in front of the living-room door
	await frames(3)
	check("MG", "unpacking is absent from the playable catalogue", not G.MINIGAMES.has("unpack"))
	check("MG", "decorative boxes have no minigame interaction", point("house_boxes")==null)
	await use("house_rice")
	check("MG", "onigiri at the rice cooker puts rice balls in the bag", int(G.mg_record("onigiri").stars) >= 1 and G.count("onigiri") >= 1)
	await use("room_desk")
	check("MG", "the map puzzle on the desk ends up framed on the wall", G.flags.get("map_framed", false) and house.map_frame.visible)
	check("MG", "each new star pays %d coins" % G.MG_COINS_PER_STAR, G.coins == c0 + G.MG_COINS_PER_STAR * G.mg_total_stars(),
		"coins %d -> %d, stars %d" % [c0, G.coins, G.mg_total_stars()])
	var stars0: int = G.mg_total_stars()
	var coins1: int = G.coins
	await use("room_desk")
	check("MG", "replaying without a new star pays nothing", G.coins == coins1 and G.mg_total_stars() == stars0 and int(G.mg_record("puzzle").plays) == 2)
	check("MG", "input unlocked after the mini-games", not G.input_locked() and main.ui.modal == "")
	for sz in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		get_window().size = sz
		main.ui.open_minigame_records()
		await frames(4)
		var panel: Control = main.ui.modal_layer.get_child(0)
		var screen := Rect2(Vector2.ZERO, main.ui.root.size).grow(1.0)
		check("MG", "records panel fits the screen at %dx%d" % [sz.x, sz.y], main.ui.modal == "records" and screen.encloses(panel.get_global_rect()),
			"%s" % panel.get_global_rect())
		main.ui.close_modal()
	get_window().size = Vector2i(1920, 1080)
	main.player.global_position = HouseBuilder.spawn_point()
	await frames(3)


## The two courtyard stations: goldfish scooping and the festival drum.
func courtyard_minigames() -> void:
	await use("goldfish_pool")
	check("MG", "goldfish at the courtyard tank brings a fish home", int(G.mg_record("goldfish").stars) >= 1 and G.flags.get("goldfish_home", false))
	await use("taiko_drum")
	check("MG", "the taiko drum records a clear", int(G.mg_record("taiko").plays) == 1 and G.flags.get("taiko_cleared", false) == (int(G.mg_record("taiko").stars) >= 1))
	check("MG", "the goldfish bowl appears on the engawa", main.world.house.goldfish.visible)


func run_all() -> void:
	# Keep the original errands branch covered as the legacy save compatibility scenario.
	SummerProjects.state().mainline_mode = "legacy"
	storage_checks()
	loading_checks()
	await props_checks()      # first, while the world is exactly as built
	# ---------- case 1: distance / line of sight
	var board := point("board")
	main.player.global_position = board.global_position + Vector3(0, -1.1, -4.0)
	main.player.face_towards(board.global_position)
	await frames(3)
	check("AC1", "no interaction from 4 m away", main.player.target != board)
	main.player.global_position = board.global_position + Vector3(0, -1.1, -1.4)
	main.player.face_towards(board.global_position)
	await frames(3)
	check("AC1", "board targetable at 1.4 m", main.player.target == board)
	main.player.global_position = Vector3(board.global_position.x, 0.1, -5.0)     # just behind the low wall
	main.player.face_towards(board.global_position)
	await frames(4)
	var dist_ok: bool = Vector2(main.player.global_position.x - board.global_position.x, main.player.global_position.z - board.global_position.z).length() < board.radius
	check("AC1", "within range but blocked by the board/wall -> no target", dist_ok and main.player.target != board, "dist_ok=%s" % dist_ok)

	# ---------- Q00
	await use("mailbox")
	check("Q00", "mailbox gives key + note", G.count("house_key") == 1 and G.count("welcome_note") == 1)
	await use("mailbox")
	check("AC2", "re-using mailbox does not duplicate items", G.count("house_key") == 1)
	await use("home_door")
	check("Q00", "entering home completes Q00", G.qstate("Q00") == "done" and main.in_room)
	check("Q00", "Q01 becomes available", G.qstate("Q01") == "available")
	await house_checks()
	await use("room_door")
	await frames(5)
	check("Q00", "leaving the room returns to the lane", not main.in_room and main.player.global_position.x > 15.0)
	await courtyard_minigames()

	# ---------- Q01
	await use("mio", [0])
	check("Q01", "talking to Mio starts Q01", G.at_step("Q01", "read_board"))
	await use("mio")
	check("AC2", "repeat talk does not re-add or skip", G.at_step("Q01", "read_board"))
	await use("board")
	check("Q01", "reading the board completes Q01", G.qstate("Q01") == "done")
	check("Q01", "three errands active", G.qstate("Q02") == "active" and G.qstate("Q03") == "active" and G.qstate("Q04") == "active")
	check("Q01", "checklist key item granted once", G.count("checklist") == 1)

	# ---------- Q02 + AC2/AC3
	await use("stall")
	check("AC2", "stall without basket changes nothing", G.at_step("Q02", "talk_ren") and G.count("support_token") == 0)
	await use("ren", [0])
	check("Q02", "Ren gives one basket and a melon pan", G.count("bread_basket") == 1 and G.count("melon_pan") == 1 and G.at_step("Q02", "deliver_basket"))
	await use("ren")
	check("AC2", "talking to Ren again does not add a second basket", G.count("bread_basket") == 1)
	await use("stall")
	check("AC3", "delivery consumes the basket once", G.count("bread_basket") == 0 and G.qstate("Q02") == "done")
	check("AC3", "reward granted once (token + flower pot)", G.count("support_token") == 1 and G.count("flower_pot") == 1)
	check("Q02", "bread shows on the stall", main.world.stall_bread.visible)
	await use("stall")
	check("AC3", "second stall use grants nothing more", G.count("support_token") == 1 and G.count("flower_pot") == 1)

	# ---------- AC4: key items safe, inventory full
	var backup_db: Dictionary = G.items_db.duplicate(true)
	var cap: int = G.INV_SLOTS
	var had_kinds: int = G.slots_used()
	for i in cap:
		G.items_db["t%d" % i] = {"name": "测试%d" % i, "key": false}
	var filled := 0
	for i in cap - had_kinds:
		if G.add_item("t%d" % i, 1, true):
			filled += 1
	check("AC4", "normal inventory caps at %d kinds" % cap, G.slots_used() == cap and not G.add_item("t%d" % (cap - 1), 1, true))
	G.items_db["t_new"] = {"name": "新", "key": false}
	check("AC8", "adding one more kind fails cleanly when full", not G.add_item("t_new", 1, true) and G.slots_used() == cap)
	check("AC4", "key items still accepted when the bag is full", G.add_item("seeds", 1, true) and G.remove_item("seeds", 1))
	var before_buy: int = G.coins
	check("AC8", "buying with a full bag is refused without charging", G.buy("lantern") != "" and G.coins == before_buy)
	for i in cap:
		G.inventory.erase("t%d" % i)
	G.items_db = backup_db
	G.inventory_changed.emit()
	check("AC4", "no drop / sell path for key items (UI exposes none; remove only via quest steps)", not main.ui.has_method("drop_item") and not G.has_method("sell")
		and G.sell_produce("seeds", 1, 1.0) == 0 and G.count("seeds") == 0)

	# ---------- Q03
	await use("haru", [0])
	check("Q03", "Haru hands over seeds and can", G.count("seeds") == 1 and G.count("watering_can") == 1)
	await use("planter")
	check("Q03", "planting uses the seeds; crop stage 1", G.count("seeds") == 0 and G.crop_stage == 1 and G.at_step("Q03", "fill_can"))
	await use("planter")
	check("Q03", "watering blocked until the can is filled", G.at_step("Q03", "fill_can"))
	await use("tap")
	check("Q03", "tap fills the can", G.flags.get("can_filled", false) and G.at_step("Q03", "water"))
	await use("planter")
	check("Q03", "watering sprouts the crop (stage 2)", G.crop_stage == 2 and G.at_step("Q03", "report"))
	var coins_before: int = G.coins
	await use("haru")
	check("Q03", "report completes Q03, +20 coins, can returned", G.qstate("Q03") == "done" and G.coins == coins_before + 20 and G.count("watering_can") == 0)

	# ---------- Q04
	await use("board")
	check("Q04", "board does nothing without the sign", G.at_step("Q04", "get_sign"))
	await use("center_door")
	check("Q04", "community centre gives the sign", G.count("event_sign") == 1)
	await use("board")
	check("Q04", "posting the sign completes Q04 and shows the poster", G.qstate("Q04") == "done" and main.world.poster.visible and G.count("event_sign") == 0)
	check("Q04", "crop grew to stage 3 after the next completed errand", G.crop_stage == 3)
	check("Q05", "three tokens unlock Q05", G.count("support_token") == 3 and G.qstate("Q05") == "available")

	# ---------- Q05 prep + AC7
	await use("mio")
	check("Q05", "Mio lends 1 table + 2 benches", G.count("picnic_table") == 1 and G.count("bench") == 2 and G.at_step("Q05", "place_seats"))
	check("AC7", "market cannot start before seats + invites", not G.start_market() and G.phase == "prep")

	# ---------- shop + decor limit
	var c_shop: int = G.coins
	await use("shop_zakka", [["bunting"]])
	check("SHOP", "bought bunting (30)", G.count("bunting") == 1 and G.coins == c_shop - 30)
	await use("shop_zakka", [["lantern"]])
	check("SHOP", "third decor kind refused (max two kinds)", G.count("lantern") == 0 and G.coins == c_shop - 30)
	var c0: int = G.coins
	G.coins = 10
	check("SHOP", "not enough coins is refused", G.buy("flower_pot") != "" and G.count("flower_pot") == 1)
	G.coins = c0

	# ---------- AC5 placement rules
	var P := PlacementSystem
	check("AC5", "outside the zone is rejected", P.check_rect(Vector2(20, 5), Vector2(2, 2)) != "")
	check("AC5", "walkway is kept free", P.check_rect(Vector2(0.0, 6.0), Vector2(2, 2)) != "")
	check("AC5", "tree circle is kept free", P.check_rect(Vector2(4.0, 7.0), Vector2(1, 1)) != "")
	check("AC5", "valid spot accepted", P.check_rect(Vector2(7.0, 4.0), Vector2(2, 2)) == "")
	var pl: PlacementSystem = main.placement
	check("AC5", "place picnic table", pl.place_at("picnic_table", 7.0, 4.0, 0))
	check("AC5", "overlap rejected", not pl.place_at("bench", 7.0, 4.5, 0) and G.count("bench") == 2)
	check("AC5", "place bench", pl.place_at("bench", 2.5, 10.5, 0))
	var uid: int = pl.session_uids.back()
	check("AC5", "undo returns the bench", G.remove_placement(uid) and G.count("bench") == 2)
	check("AC5", "bench placed again", pl.place_at("bench", 2.5, 10.5, 0))
	check("AC5", "rotated bench fits", pl.place_at("bench", 8.5, 9.5, 1))
	check("AC5", "decor placed", pl.place_at("flower_pot", 5.5, 4.0, 0) and pl.place_at("bunting", 5.5, 11.2, 0))
	main.story.post_checks()
	await frames(2)
	check("Q05", "seating advances Q05 to invites", G.at_step("Q05", "invite"))
	check("AC5", "placed nodes exist in the world", main.placement.placed_root.get_child_count() == G.placements.size())

	# ---------- AC6 save / load
	await use("ren", [0])
	check("Q05", "Ren invited", G.invited("ren"))
	check("AC6", "save succeeds", G.save_game())
	var snap: Dictionary = G.to_dict()
	G.new_game()
	check("AC6", "state cleared before load", G.placements.is_empty() and G.qstate("Q05") == "locked")
	check("AC6", "load succeeds", G.load_game())
	var after: Dictionary = G.to_dict()
	var same := true
	for k in ["coins", "inventory", "key_items", "quests", "flags", "affinity", "placements", "crop_stage", "phase", "next_uid", "minigames",
			"day", "minute", "weather", "plots", "can_water", "compost"]:
		if not state_equal(snap[k],after[k]):
			same = false
			print("  diff in ", k, ": ", snap[k], " vs ", after[k])
	check("AC6", "quests, bag, placements, crop and flags survive save/load", same)
	# corrupted main save falls back to .bak
	G.save_game()
	var f := FileAccess.open(G.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{ broken json")
	f.close()
	check("AC6", "corrupt save falls back to backup", G.load_game() and G.qstate("Q05") == "active")
	G.save_game()
	# AC8: re-delivery after load grants nothing
	var tokens: int = G.count("support_token")
	await use("stall")
	check("AC8", "re-delivering after load grants nothing", G.count("support_token") == tokens)

	# ---------- AC8: double interact guard
	var it := stand_at("haru")
	await frames(3)
	main.ui.auto_choices = [0]
	main.story.interact(it)
	main.story.interact(it)
	await frames(10)
	check("AC8", "rapid double interaction is ignored while busy", G.invited("haru") and G.affinity.haru <= 3)
	await frames(10)
	main.story.post_checks()
	check("Q05", "both invited -> ready to start", G.at_step("Q05", "start"))

	# ---------- AC9: input lock while menus are open
	main.ui.open_inventory()
	var p0: Vector3 = main.player.global_position
	Input.action_press("move_forward")
	await frames(20)
	Input.action_release("move_forward")
	check("AC9", "player does not move while the bag is open", main.player.global_position.distance_to(p0) < 0.05 and G.input_locked())
	main.ui.close_modal()
	check("AC9", "closing the bag unlocks input", not G.input_locked())
	Input.action_press("move_forward")
	await frames(20)
	Input.action_release("move_forward")
	check("AC9", "player moves again after closing", main.player.global_position.distance_to(p0) > 0.3)
	# panels anchored to the screen edges must stay fully on screen at any window size
	var ui: GameUI = main.ui
	for sz in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1600, 1000)]:
		get_window().size = sz
		ui.dlg.visible = true
		ui.dlg_choices.visible = true
		ui.prompt_panel.visible = true
		ui.place_bar.visible = true
		await frames(3)
		var screen := Rect2(Vector2.ZERO, ui.root.size).grow(1.0)
		var off: Array = []
		for c in [ui.dlg.get_child(1), ui.dlg_name_panel, ui.dlg_choices, ui.prompt_panel, ui.place_bar]:
			if not screen.encloses((c as Control).get_global_rect()):
				off.append("%s %s" % [c.get_class(), (c as Control).get_global_rect()])
		check("AC9", "dialogue / prompt / layout panels on screen at %dx%d" % [sz.x, sz.y], off.is_empty(), ", ".join(off))
		ui.dlg.visible = false
		ui.dlg_choices.visible = false
		ui.prompt_panel.visible = false
		ui.place_bar.visible = false
	get_window().size = Vector2i(1920, 1080)

	# ---------- AUD: music, ambience, buses, footsteps
	for b in ["Music", "Ambience", "SFX", "UI"]:
		check("AUD", "audio bus %s exists" % b, AudioServer.get_bus_index(b) >= 0)
	var cues: Array = ["music/title.ogg", "music/day.ogg", "music/market.ogg", "music/ending.ogg", "amb/day.ogg", "amb/evening.ogg", "amb/room.ogg"]
	for sfc in Audio.SURFACES:
		for i in 4:
			cues.append("sfx/step_%s_%d.wav" % [sfc, i])
	for k in Audio.STING_RANK:
		cues.append("sfx/sting_%s.wav" % k)
	for k in ["hover", "click", "open", "close", "next", "select", "invalid", "rotate"]:
		cues.append("sfx/ui_%s.wav" % k)
	for k in ["door", "mailbox", "water_tap", "water_pour", "soil", "paper", "place", "pickup", "basket", "purr"]:
		cues.append("sfx/fx_%s.wav" % k)
	for k in minigame_sfx():
		cues.append("sfx/mg_%s.wav" % k)
	var missing := cues.filter(func(c): return Audio.stream(c) == null)
	check("AUD", "all %d audio cues load" % cues.size(), missing.is_empty(), ", ".join(missing))
	check("AUD", "ambience loops seamlessly; music tracks play through (they restart under a crossfade)",
		(Audio.stream("amb/evening.ogg") as AudioStreamOggVorbis).loop and not (Audio.stream("music/day.ogg") as AudioStreamOggVorbis).loop
		and not (Audio.stream("music/ending.ogg") as AudioStreamOggVorbis).loop)
	var mi0: int = Audio._mi
	var mlen: float = Audio.stream("music/%s.ogg" % Audio.music_name).get_length()
	var early: bool = Audio._maybe_loop(mlen * 0.5)
	var looped: bool = Audio._maybe_loop(mlen - 1.0)
	check("AUD", "music restarts with a crossfade near its end", not early and looped and Audio._mi != mi0 and Audio.music_name == "day",
		"len %.1f s" % mlen)
	check("AUD", "town music and daytime ambience outdoors while preparing", Audio.music_name == "day" and Audio.amb_name == "day" and not Audio.indoor)
	var vm0: float = float(G.settings.vol_music)
	G.settings.vol_music = 0.5
	G.apply_settings()
	var mdb := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	check("AUD", "music volume setting drives the Music bus", absf(mdb - linear_to_db(0.5 * Audio._duck)) < 0.3, "%.2f dB" % mdb)
	G.settings.vol_music = 0.0
	G.apply_settings()
	check("AUD", "music volume 0 mutes the bus", AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	G.settings.vol_music = vm0
	G.apply_settings()
	check("AUD", "footstep surface lookup (street / courtyard / lawn / room)",
		Layout.surface_at(Vector3(-20, 0, -10.6), false) == "stone" and Layout.surface_at(Vector3(4, 0, 4), false) == "gravel"
		and Layout.surface_at(Vector3(-9, 0, 15), false) == "grass" and Layout.surface_at(Vector3.ZERO, true) == "wood")
	var ca: CharAnim = main.player.anim
	var n_steps := [0]
	var on_step := func(): n_steps[0] += 1
	ca.stepped.connect(on_step)
	for i in 120:
		ca.update(1.8)
		ca.ap.advance(1.0 / 60.0)
	ca.stepped.disconnect(on_step)
	ca.update(0.0)
	check("AUD", "walk clip gives a footstep at each heel strike", n_steps[0] >= 4 and n_steps[0] <= 7, "%d steps in 2 s" % n_steps[0])

	# ---------- market (only on Saturday evening; Mio offers to wait on the bench)
	await use("mio")
	check("TIME", "on a Thursday Mio schedules the market for Saturday", G.phase == "prep" and G.at_step("Q05", "start") and G.weekday() == 3)
	G.day = 3
	G.minute = 14.0 * 60.0
	G.weather = G.weather_for(3)
	await use("mio", [0, 0])
	check("TIME", "Saturday afternoon: waiting on the bench jumps to 16:30", G.minute >= G.MARKET_OPEN and G.weekday() == G.SATURDAY)
	check("AC7", "market starts when ready", G.phase == "market" and G.at_step("Q05", "chat"))
	check("AUD", "market music and evening ambience after the market opens", Audio.music_name == "market" and Audio.amb_name == "evening")
	check("MKT", "evening light applied", main.world.sun.light_color.r > 0.9 and main.world.sun.light_color.b < 0.7)
	check("MKT", "NPCs gathered at the courtyard", (main.npcs["ren"] as Node3D).global_position.distance_to(Layout.NPC.ren.market) < 0.5)
	check("MKT", "placement locked during the market", not main.placement.can_enter() and not G.remove_placement(int(G.placements[0].uid)))
	await use("mio")
	await use("ren")
	await use("haru")
	await frames(30)
	check("END", "chatting with all three completes Q05", G.qstate("Q05") == "done" and G.flags.get("ended", false))
	check("END", "liked decor raised affinity", int(G.affinity.mio) >= 2 and int(G.affinity.haru) >= 2)
	check("AC6", "final save/load keeps the ending", G.load_game() and G.flags.get("ended", false) and G.phase == "market")
	check("HOUSE", "evening: light shafts off, lamps on", not main.world.house.beams.visible and main.world.house.lamps[0].light_energy > 0.5)

	# ---------- MG: home-made onigiri as a gift (once per neighbour)
	var had: int = G.count("onigiri")
	var aff_r: int = int(G.affinity.ren)
	await use("ren", [0])
	check("MG", "giving Ren an onigiri: -1 rice ball, +1 familiarity", had > 0 and G.count("onigiri") == had - 1 and int(G.affinity.ren) == aff_r + 1 and G.flags.get("gift_ren", false),
		"had %d now %d" % [had, G.count("onigiri")])
	await use("ren", [0])
	check("MG", "the gift is offered only once per neighbour", G.count("onigiri") == had - 1 and int(G.affinity.ren) == aff_r + 1)

	await time_checks()
	await farm_checks()
	await v05_checks()
	await v06_checks()
	await crowd_checks()
	prologue_checks()
	narrative_regressions()
	await load("res://scripts/tests/narrative_checks.gd").new(self).run()
	await keeper_continuity_checks()
	bakery_display_check()




# ================================================================== v0.4: clock, weather, farming
func time_checks() -> void:
	# the clock runs only while nothing is open
	G.clock_paused = false
	var m0: float = G.minute
	await frames(40)
	check("TIME", "the clock advances while walking around", G.minute > m0, "%.2f -> %.2f" % [m0, G.minute])
	main.ui.open_inventory()
	var m1: float = G.minute
	await frames(40)
	check("TIME", "the clock stops while a menu is open", absf(G.minute - m1) < 0.001)
	main.ui.close_modal()
	G.clock_paused = true
	check("TIME", "day 1 is a Thursday and day 3 a Saturday", G.weekday_name(1) == "周四" and G.weekday(3) == G.SATURDAY)
	var sat_sunny := true
	var rainy := 0
	for d in range(1, 90):
		var w: String = G.weather_for(d)
		if G.weekday(d) == G.SATURDAY and w != "sunny":
			sat_sunny = false
		if w == "rain":
			rainy += 1
		if w != G.weather_for(d):
			sat_sunny = false
	check("TIME", "weather is deterministic, Saturdays and the first three days are sunny, some days rain",
		sat_sunny and G.weather_for(1) == "sunny" and G.weather_for(2) == "sunny" and rainy >= 5, "%d rainy days" % rainy)
	var W: WorldBuilder = main.world
	var noon: Dictionary = WorldBuilder.look_at_hour(12.0)
	var morning: Dictionary = WorldBuilder.look_at_hour(7.0)
	var night: Dictionary = WorldBuilder.look_at_hour(22.0)
	check("TIME", "sun is brightest at noon, lamps and the night sky take over after dark",
		noon.sun > morning.sun and night.sun < 0.5 and night.lamp > 1.0 and night.night > 0.9 and noon.lamp == 0.0)
	# the first market ended the evening; sleeping brings a new ordinary day
	var d0: int = G.day
	if main.in_room:
		await use("room_door")
	main.enter_room()
	await frames(30)
	G.minute = 22.0 * 60.0
	await use("room_bed", [0])
	await frames(40)
	check("TIME", "sleeping in the bed starts the next morning in the bedroom", G.day == d0 + 1 and G.minute == float(G.WAKE_MIN) and main.in_room and G.phase == "prep")
	var saved_days := SaveDB.load_candidates()
	check("TIME", "sleeping saves the game in SQLite", not saved_days.is_empty() and int(saved_days[0].data.get("day", 0)) == G.day)
	# late night: at midnight the player nods off and wakes up at home
	var d1: int = G.day
	await use("room_door")
	await frames(10)
	G.minute = float(G.DAY_END) - 0.3
	G.clock_paused = false
	for i in 240:
		await frames(1)
		if G.day != d1:
			break
	await frames(60)
	G.clock_paused = true
	check("TIME", "midnight sends the player to bed: next day, at home", G.day == d1 + 1 and main.in_room)
	await use("room_door")
	await frames(10)


func _plot(id: String) -> Dictionary:
	return G.plots[id]


func farm_checks() -> void:
	var W: WorldBuilder = main.world
	var ids: Array = []
	for n in get_tree().get_nodes_in_group("interactables"):
		ids.append((n as Interactable).id)
	var miss: Array = G.plot_ids().filter(func(p): return p != "court" and not ids.has("plot_" + p))
	check("FARM", "every farm, greenhouse and yard plot can be used", miss.is_empty(), ", ".join(miss))
	var tree: Node = W.find_child("T01_courtyard_tree", true, false)
	var sway := false
	if tree:
		for mi in WorldBuilder.find_meshes(tree):
			var m := mi.get_surface_override_material(0)
			sway = sway or (m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path.ends_with("foliage_sway.gdshader"))
	check("LIFE", "trees move in the wind (foliage shader)", sway)
	# Q06: Haru's letter to the allotment
	G.minute = 9.0 * 60.0
	main.update_npcs(true)
	check("FARM", "Q06 unlocks after Q03", G.qstate("Q06") == "available")
	await use("haru")
	check("FARM", "Haru gives the letter and starts Q06", G.at_step("Q06", "go_farm") and G.has("letter_haru"))
	await use("east_end")
	await frames(20)
	check("FARM", "the east end leads down to the allotment (town hidden, farm shown)",
		W.region == "farm" and W.farm.visible and main.player.global_position.x > 600.0 and G.at_step("Q06", "talk_tanaka"))
	var mk = main.story.marker_target()
	check("FARM", "the marker points at Tanaka on the farm", mk != null and (mk as Vector3).distance_to(main.npcs.tanaka.global_position) < 3.0)
	await use("tanaka")
	check("FARM", "Tanaka lends a hoe and a can, gives seeds and four plots",
		G.has("hoe") and G.has("farm_can") and G.has("seed_radish") and G.plot_state("farm0") == "wild" and G.plot_state("farm4") == "locked" and G.can_water == G.CAN_CAP)
	await use("plot_farm0")
	check("FARM", "tilling a wild plot gives weeds", G.plot_state("farm0") == "tilled" and G.count("weeds") == 2 and G.at_step("Q06", "sow"))
	await use("plot_farm0", [0])
	check("FARM", "sowing uses one seed", _plot("farm0").crop != "" and G.plot_state("farm0") == "seeded" and G.at_step("Q06", "water6"))
	var sown: String = _plot("farm0").crop
	await use("plot_farm0")
	check("FARM", "watering wets the soil and uses the can", _plot("farm0").water and G.can_water == G.CAN_CAP - 1 and G.at_step("Q06", "report6"))
	var c0: int = G.coins
	await use("tanaka")
	check("FARM", "reporting completes Q06 (+30) and starts Q07", G.qstate("Q06") == "done" and G.coins == c0 + 30 and G.qstate("Q07") == "active")
	# a second plot left dry does not grow
	await use("plot_farm1")
	G.add_item("seed_tomato", 2, true)
	await use("plot_farm1", [0])
	var dry_crop: String = _plot("farm1").crop
	G.compost_add("weeds")
	G.add_item("weeds", 3, true)
	G.compost_add("weeds")
	G.advance_day()
	check("FARM", "watered crops grow overnight, dry ones wait", int(_plot("farm0").days) == 1 and int(_plot("farm1").days) == 0 and dry_crop != "")
	check("FARM", "the compost bin turns 3 weeds into a bag of fertilizer by morning", G.compost_ready >= 1)
	await use("farm_compost")
	check("FARM", "fertilizer comes out of the bin", G.count("fertilizer") >= 1 and G.compost_ready == 0)
	await use("farm_pump")
	check("FARM", "the hand pump refills the can", G.can_water == G.CAN_CAP)
	await use("plot_farm1")
	await use("plot_farm1", [0])
	check("FARM", "fertilizer on a watered plot is recorded", _plot("farm1").fert and _plot("farm1").water)
	G.weather = "sunny"
	G.advance_day()
	check("FARM", "fertilized crops grow two days in one night", int(_plot("farm1").days) == 2)
	# ripen and harvest
	_plot("farm0").days = int(G.crop_def(sown).days)
	_plot("farm1").days = int(G.crop_def(dry_crop).days)
	G.plots_changed.emit()
	var n0: int = G.count(sown)
	await use("plot_farm0")
	check("FARM", "a ripe plot is harvested into the bag", G.count(sown) > n0 and G.at_step("Q07", "sell"))
	var tom0: int = G.count("tomato")
	await use("plot_farm1")
	var regrow: int = int(G.crop_def("tomato").regrow)
	check("FARM", "tomatoes (+1 from fertilizer) and the plant keeps growing", dry_crop != "tomato" or (G.count("tomato") == tom0 + 4 and _plot("farm1").crop == "tomato" and int(_plot("farm1").days) == int(G.crop_def("tomato").days) - regrow))
	var coins_s: int = G.coins
	await use("veggie_stand", [G.produce_owned().size()])
	check("FARM", "the honor stand buys produce at the base price", G.coins > coins_s and G.produce_owned().is_empty() and G.at_step("Q07", "report7"))
	check("FARM", "key items are never sold", G.has("hoe") and G.has("farm_can"))
	await use("tanaka")
	check("FARM", "Q07 opens the greenhouse and gives strawberry plants + fertilizer", G.qstate("Q07") == "done" and G.plot_state("gh0") == "tilled" and G.has("seed_strawberry"))
	check("FARM", "strawberries only go in the greenhouse", G.sow("farm2", "seed_strawberry") != "" and G.sow("gh0", "seed_strawberry") == "" and G.sow("gh1", "seed_radish") != "")
	# rain waters everything outdoors, not the greenhouse
	var rain_day := -1
	for d in range(G.day + 1, G.day + 60):
		if G.weather_for(d) == "rain":
			rain_day = d
			break
	G.day = rain_day - 1
	G.advance_day()
	check("FARM", "a rainy morning waters the outdoor plots but not the greenhouse",
		G.weather == "rain" and _plot("farm0").water and not _plot("gh0").water, "day %d" % G.day)
	check("FARM", "rain sets the rain ambience and streaks", main.outdoor_amb() == "rain")
	G.weather = "sunny"
	# yard plots at home
	check("FARM", "the four yard plots opened with Q06", G.plot_state("yard0") == "wild")
	# expand the allotment
	G.flags["harvests"] = 5
	G.coins = 400
	G.farm_xp = maxi(G.farm_xp, int(G.LEVELS[1]))
	await use("tanaka", [1])
	check("FARM", "renting four more plots from Tanaka costs 200 (needs Lv2)", G.farm_expansions == 1 and G.coins == 200 and G.plot_state("farm4") == "wild")
	# gifts, warmth and hearts
	G.add_item("radish", 3, true)
	var aff_t: int = int(G.affinity.tanaka)
	var w0: int = int(G.warmth.get("tanaka", 0))
	var pts: int = G.give_gift("tanaka", "radish")
	check("HEART", "a liked gift counts double, once per day", pts == 2 and G.give_gift("tanaka", "radish") == 0)
	G.warmth["tanaka"] = 3
	G.add_warmth("tanaka", 1)
	check("HEART", "four warmth points become a heart", int(G.affinity.tanaka) == mini(aff_t + 1, G.MAX_AFF) and int(G.warmth.tanaka) == 0)
	# daily request from the board
	G.daily["request"] = {"who": "tanaka", "item": "radish", "n": 2, "done": false, "reward": 110}
	var cr: int = G.coins
	await use("tanaka", [0])
	check("HEART", "fulfilling a board request pays and warms", G.request().done and G.coins == cr + 110 and G.count("radish") == 0)
	# dialogue pool
	G.weather = "rain"
	var e: Dictionary = Dialogue.pick("mio", {"region": "town"})
	check("TALK", "rainy days pick rain lines", not e.is_empty() and (e.when.get("weather", []) as Array).has("rain"), str(e.get("id", "")))
	G.weather = "sunny"
	G.affinity["aoi"] = 4
	G.minute = 13.0 * 60.0
	var ev: Dictionary = Dialogue.pick("aoi", {"region": "farm"})
	check("TALK", "a heart event outranks everyday lines once earned", ev.get("id", "") == "ev_aoi4")
	Dialogue.mark(ev)
	check("TALK", "heart events play only once", Dialogue.pick("aoi", {"region": "farm"}).get("id", "") != "ev_aoi4" and G.flags.get("ev_aoi4", false))
	var total := 0
	for who in ["mio", "ren", "haru", "tanaka", "aoi"]:
		total += Dialogue.entries.filter(func(x): return x.who == who).size()
	check("TALK", "every neighbour has at least 15 lines in the pool", total >= 75, "%d lines" % total)
	# routines
	var mio: NPC = main.npcs.mio
	mio.apply_schedule(12.5, main.player.global_position, true)
	check("NPC", "Mio spends lunchtime at the florist", mio.global_position.distance_to(Vector3(-12.2, 0, -13.2)) < 0.5 and not mio.home)
	mio.apply_schedule(22.0, main.player.global_position, true)
	check("NPC", "at night neighbours go home (hidden, no talking)", mio.home and not mio.visible and mio.talk.radius == 0.0)
	check("NPC", "the marker ignores neighbours who are at home", main.story._npc_head("mio") == null)
	mio.apply_schedule(9.0, main.player.global_position, true)
	var aoi: NPC = main.npcs.aoi
	check("NPC", "the new neighbours have rigged gestures", aoi.anim.valid() and aoi.anim.has("wave") and aoi.anim.has("tend") and main.npcs.tanaka.anim.has("bow"))
	# Q08: Aoi's sunflower
	G.minute = 13.0 * 60.0
	main.update_npcs(true)
	await use("aoi")
	check("Q08", "Aoi asks for a sunflower and hands over the seeds", G.at_step("Q08", "sow_sun") and G.has("seed_sunflower"), "day %d Q08 %s/%s lore %s" % [G.day, G.qstate("Q08"), G.qstep_id("Q08"), main.story.lore.pending("aoi")])
	G.plots.farm2.tilled = true
	G.plots.farm2.crop = ""
	var other_seeds := {}
	for sid in G.seeds_owned():
		if sid != "seed_sunflower":
			other_seeds[sid] = G.count(sid)
			G.remove_item(sid, G.count(sid))
	await use("plot_farm2", [0])
	for sid in other_seeds:
		G.add_item(sid, other_seeds[sid], true)
	check("Q08", "sowing the sunflower advances Q08", _plot("farm2").crop == "sunflower" and G.at_step("Q08", "bloom"))
	_plot("farm2").days = int(G.crop_def("sunflower").days)
	await use("plot_farm2")
	await use("aoi")
	check("Q08", "the sunflower goes to Aoi: Q08 done, hair clip", G.qstate("Q08") == "done" and G.has("hairclip"))
	# save v2 round trip + v1 migration
	check("SAVE", "save succeeds on the farm", G.save_game())
	var snap: Dictionary = G.to_dict()
	G.new_game()
	G.clock_paused = true
	check("SAVE", "load restores day, weather, plots and the farm region",
		G.load_game() and G.day == int(snap.day) and JSON.stringify(G.plots) == JSON.stringify(snap.plots) and G.player_region == "farm")
	var v1: Dictionary = snap.duplicate(true)
	v1.version = 1
	for k in ["day", "minute", "weather", "plots", "can_water", "compost", "compost_ready", "farm_expansions", "warmth", "daily", "region"]:
		v1.erase(k)
	v1.affinity = {"mio": 2, "ren": 1, "haru": 3}
	check("SAVE", "a v1 save still loads (moving day, closed plots)", G.from_dict(v1) and G.day == 1 and G.plot_state("farm0") == "locked" and int(G.affinity.tanaka) == 0 and int(G.affinity.haru) == 3)
	G.load_game()
	# weekly market: after the first one, Saturdays open the stall again at 16:30
	G.phase = "prep"
	var sat: int = G.day
	while G.weekday(sat) != G.SATURDAY:
		sat += 1
	G.day = sat
	G.minute = 16.0 * 60.0
	G._last_min = -1
	G.skip_to(float(G.MARKET_OPEN))
	await frames(5)
	check("MKT", "every Saturday at 16:30 the market opens by itself", G.phase == "market")
	if main.in_room:
		await use("room_door")
	if W.region == "farm":
		await use("farm_exit")
		await frames(20)
	await use("mio")
	check("Q09", "Mio suggests a vegetable stall at the weekly market", G.qstate("Q09") == "active" or G.qstate("Q09") == "available")
	if G.qstate("Q09") == "available":
		G.start_quest("Q09")
	G.add_item("komatsuna", 5, true)
	var cm: int = G.coins
	var expect := 0
	for iid in G.produce_owned():
		expect += int(round(float(G.item(iid).sell) * G.MARKET_RATE)) * G.count(iid)
	await use("stall", [mini(G.produce_owned().size(), 4)])
	check("Q09", "the market stall pays the market rate (1.3x)", G.coins == cm + expect and G.at_step("Q09", "report9"), "+%d expected %d" % [G.coins - cm, expect])
	await use("mio")
	check("Q09", "reporting to Mio completes Q09", G.qstate("Q09") == "done")
	G.skip_to(float(G.MARKET_CLOSE))
	await frames(5)
	check("MKT", "the market closes at 21:00", G.phase == "prep")



# ================================================================== v0.5: experience, shops, cooking, bag, festivals
func v05_checks() -> void:
	var W: WorldBuilder = main.world
	if main.in_room:
		await use("room_door")
	if W.region == "farm":
		await use("farm_exit")
		await frames(20)
	G.phase = "prep"
	G.day = 5          # a Monday
	G.minute = 10.0 * 60.0
	G.weather = "sunny"
	# ---- experience
	var xp0: int = G.farm_xp
	var levels_seen: Array = []
	var cb := func(lv, _p): levels_seen.append(lv)
	G.level_up.connect(cb)
	G.farm_xp = 0
	G.add_xp(int(G.LEVELS[1]))
	check("XP", "reaching the level-2 threshold levels up (signal + perks)", G.level() == 2 and levels_seen == [2] and not (G.LEVEL_PERKS[2] as Array).is_empty())
	G.level_up.disconnect(cb)
	G.plots.farm8.open = true
	G.plots.farm8.tilled = false
	G.plots.farm8.crop = ""
	var x1: int = G.farm_xp
	G.add_item("hoe", 0)
	G.till("farm8")
	G.add_item("seed_komatsuna", 1, true)
	G.sow("farm8", "seed_komatsuna")
	G.can_water = 3
	G.water_plot("farm8")
	check("XP", "tilling, sowing and watering give experience", G.farm_xp == x1 + G.XP_TILL + G.XP_SOW + G.XP_WATER)
	G.plots.farm8.days = int(G.crop_def("komatsuna").days)
	var x2: int = G.farm_xp
	G.harvest("farm8")
	check("XP", "harvesting gives the crop's experience", G.farm_xp == x2 + int(G.crop_def("komatsuna").xp))
	# ---- shops, levels, hours
	G.coins = 5000
	check("SHOP5", "high-level seeds are locked by farming level", G.buy_block("seed_pumpkin").begins_with("种植等级") and G.buy_block("seed_tomato") == "")
	check("SHOP5", "the general store keeps hours and closes on Wednesdays",
		G.shop_closed_reason("store") == "" and (func(): G.minute = 20.0 * 60.0; return G.shop_closed_reason("store") != "").call())
	G.minute = 10.0 * 60.0
	G.day = 7
	check("SHOP5", "Wednesday: the store is closed", G.shop_closed_reason("store").contains("定休"))
	G.day = 5
	var c0: int = G.coins
	var out0: int = int(G.ledger.out)
	await shop_in("shop_store", "store_counter", [{"buy": {"seed_carrot": 2, "flour": 1}}])
	check("SHOP5", "buying seeds and flour at the store", G.count("seed_carrot") >= 2 and G.count("flour") >= 1 and G.coins == c0 - 2 * 18 - 20 and int(G.ledger.out) == out0 + 56)
	check("SHOP5", "the copper can needs level 3", G.buy_block("can_copper") != "")
	G.farm_xp = int(G.LEVELS[2])
	G.buy_item("can_copper")
	check("SHOP5", "the copper can holds 10", G.can_cap() == 10 and G.can_level == 1 and not G.shop_stock("store").has("can_copper"))
	G.buy_item("up_bag30")
	check("BAG", "the big backpack gives 30 slots", G.bag_cap == 30)
	# ---- selling and the daily glut
	G.add_item("carrot", 15, true)
	var v: int = G.sale_value("carrot", 15, 1.0)
	var unit: int = int(G.item("carrot").sell)
	check("SHOP5", "a buyer pays full price for 12, then 70%", v == unit * 12 + int(round(unit * 0.7)) * 3, "%d" % v)
	await shop_in("shop_store", "store_counter", [{"sell": {"carrot": -1}}])
	check("SHOP5", "selling carrots at the store", G.count("carrot") == 0 and int(G.daily.sold_n.carrot) >= 15)
	check("SHOP5", "the store does not buy key items", not G.buys_item("store", "hoe") and not G.buys_item("store", "farm_can"))
	# ---- cooking at home
	main.enter_room()
	await frames(30)
	G.add_item("tomato", 3, true)
	G.add_item("cucumber", 1, true)
	var m0: float = G.minute
	check("COOK", "the salad needs nothing more than what is in the bag", G.craft_block("salad") == "")
	await use("house_stove", [{"craft": {"salad": 1}}])
	check("COOK", "cooking a salad uses 3 tomatoes + 1 cucumber and takes 30 minutes",
		G.count("salad") == 1 and G.count("tomato") == 0 and absf(G.minute - m0 - 30.0) < 0.5)
	check("COOK", "missing ingredients are listed", G.craft_block("salad").begins_with("还差"))
	check("COOK", "locked recipes say how to learn them", G.craft_block("pumpkin_nimono").contains("种植等级 6") and not G.recipe_known("pumpkin_bread"))
	G.minute = 23.6 * 60.0
	G.add_item("komatsuna", 2, true)
	G.add_item("miso", 1, true)
	check("COOK", "too late at night to cook", G.craft_block("miso_soup").contains("太晚"))
	G.minute = 11.0 * 60.0
	# ---- the home chest
	G.add_item("potato", 150, true)
	main.player.global_position = HouseBuilder.ORIGIN + Vector3(2.0, 0.05, 3.0)
	check("BAG", "a stack holds 99, 150 potatoes take two slots", G.count("potato") == 150 and G._slots_for(150) == 2)
	await use("house_chest", [{"store": {"potato": -1}}])
	check("BAG", "the chest takes the potatoes out of the bag", G.count("potato") == 0 and int(G.storage.get("potato", 0)) == 150)
	check("BAG", "key items stay in the bag", not G.store_in("hoe", 1))
	main.player.global_position = HouseBuilder.ORIGIN + Vector3(2.0, 0.05, 3.0)
	await use("house_chest", [{"take": {"potato": 10}}])
	check("BAG", "taking 10 back out", G.count("potato") == 10 and int(G.storage.potato) == 140)
	await use("room_door")
	await frames(10)
	# ---- the bakery: recipe cards, the oven, the mill
	G.minute = 10.0 * 60.0
	await shop_in("bakery", "bakery_counter", [{"buy": {"card_focaccia": 1}}])
	check("BAKE", "buying a recipe card teaches the recipe", G.recipe_known("focaccia") and not G.has("card_focaccia"))
	G.add_item("tomato", 3, true)
	G.add_item("wheat", 3, true)
	var fl: int = G.count("flour")
	await shop_in("bakery", "bakery_oven", [{"craft": {"mill_flour": 1, "focaccia": 1}}])
	check("BAKE", "the mill turns 3 wheat into 2 flour, the oven bakes focaccia", G.count("wheat") == 0 and G.count("focaccia") == 1 and G.count("flour") == fl + 2 - 1)
	check("BAKE", "the bakery pays 1.2x for bread", G.buys_item("bakery", "focaccia") and not G.buys_item("bakery", "tomato"))
	# ---- gifts: home-made food counts more
	check("HEART", "a liked home-made dish is worth 3 warmth, produce 1–2", G.gift_points("mio", "salad") == 3 and G.gift_points("mio", "focaccia") == 3 and G.gift_points("ren", "salad") == 2 and G.gift_points("tanaka", "radish") == 2)
	# ---- festivals
	var days: Array = []
	for fid in G.festivals_db:
		days.append(int(G.festivals_db[fid].day))
	days.sort()
	var fd: Array = G.FESTIVAL_DAYS.duplicate()
	fd.sort()
	check("FEST", "festival days in the data match the weather table", days == fd)
	var sunny := true
	for d in days:
		sunny = sunny and G.weather_for(d) == "sunny"
	check("FEST", "festival days are always sunny", sunny)
	check("FEST", "calendar: day 1 is 7月4日, day 29 is 8月1日", G.date_text(1) == "7月4日" and G.date_text(29) == "8月1日" and G.festival_on(4) == "tanabata")
	G.day = 3
	G.minute = 9.0 * 60.0
	W.sync_festivals()
	check("FEST", "Tanabata bamboo goes up the day before", W.fest_nodes.tanabata.visible and not W.fest_nodes.natsumatsuri.visible)
	G.day = 4
	G.minute = 18.0 * 60.0
	main.sync_festival_state()
	main.update_npcs(true)
	check("FEST", "Tanabata is running at 18:00", G.festival_now() == "tanabata" and main.story.prompt_for("tanabata_bamboo") != "")
	var fmio: Array = G.festival("tanabata").npc.mio[1]
	check("FEST", "neighbours gather at the festival", (main.npcs.mio as Node3D).global_position.distance_to(Vector3(fmio[0], fmio[1], fmio[2])) < 0.5)
	var wa: int = int(G.warmth.get("ren", 0)) + int(G.affinity.ren) * G.WARMTH_PER_HEART
	await use("tanabata_bamboo", [1])
	check("FEST", "writing a wish hangs a tanzaku and warms the person it is for",
		G.flags.get("fest_tanabata_wish", false) and W.tanzaku_root.get_child_count() == 1 and int(G.warmth.get("ren", 0)) + int(G.affinity.ren) * G.WARMTH_PER_HEART >= wa + 2)
	G.day = 11
	G.minute = 11.0 * 60.0
	W.sync_festivals()
	main.update_npcs(true)
	G.farm_xp = int(G.LEVELS[2])
	G.add_item("sunflower", 1, true)
	var ci: int = G.coins
	await use("contest_table", [0])
	check("FEST", "a sunflower at level 3 wins the vegetable contest (+300, gold ribbon)", G.has("ribbon_gold") and G.coins == ci + 300)
	G.day = 17
	G.minute = 17.5 * 60.0
	G.phase = "market"
	W.sync_festivals()
	main.update_npcs(true)
	check("FEST", "summer festival: the yagura is up and solid", W.fest_nodes.natsumatsuri.visible and W.fest_nodes.natsumatsuri.find_children("*", "StaticBody3D", true, false).any(func(b): return b.collision_layer != 0))
	for iid in G.inventory.keys():
		if G.item(iid).has("crop") or G.item(iid).has("dish"):
			G.store_in(iid, G.count(iid)) if G.storage_used() < G.STORAGE_SLOTS else G.remove_item(iid, G.count(iid))
	G.add_item("salad", 2, true)
	var cs: int = G.coins
	var pay: int = G.sale_value("salad", 1, G.FESTIVAL_STALL_RATE)
	await use("stall", [0])
	check("FEST", "dishes sell at double price at the summer festival stall", G.coins == cs + pay * 2 or G.coins == cs + G.sale_value("salad", 2, G.FESTIVAL_STALL_RATE), "+%d" % (G.coins - cs))
	G.minute = 20.2 * 60.0
	# v0.7.3: seven dancers now (Kazuko joined); every spot on the ring is clear of the stalls and lanterns
	var ring_bad := []
	for i in 7:
		var a := TAU * i / 7.0
		var sp := WorldBuilder.YAGURA_POS + Vector3(cos(a), 0, sin(a)) * 3.6
		var hit := _solid_at(sp, 0.3)
		if not hit.is_empty():
			ring_bad.append("%d %s" % [i, hit])
	check("FEST", "the bon-odori ring has a clear spot for all seven dancers", ring_bad.is_empty(), str(ring_bad))
	await use("yagura")
	check("FEST", "joining the bon-odori after 20:00", G.flags.get("fest_bon_odori", false) and not main.dancing)
	G.phase = "prep"
	G.day = 24
	G.minute = 19.8 * 60.0
	await use("east_end")
	await frames(20)
	main.sync_festival_state()
	main.update_npcs(true)
	check("FEST", "hanabi: fireworks over the river when you are at the farm", W.farm.fx.fireworks_on)
	await use("farm_bench", [0])
	check("FEST", "watching the fireworks with someone", G.flags.get("fest_hanabi", false))
	G.day = 43
	G.minute = 19.0 * 60.0
	main.sync_festival_state()
	main.update_npcs(true)
	var nl: int = W.farm.fx.lanterns.size()
	var bt := point("bridge_toro")
	main.player.global_position = FarmBuilder.ORIGIN + Vector3(0, 0.9, 14.3)
	main.player.face_towards(bt.global_position)
	await frames(8)
	check("FEST", "the lantern spot on the bridge can be reached", main.player.target == bt, "target=%s y=%.2f" % [main.player.target.id if main.player.target else "none", main.player.global_position.y])
	await main.story.interact(bt)
	await frames(2)
	check("FEST", "floating a lantern at Obon", G.flags.get("fest_toro", false) and W.farm.fx.lanterns.size() > nl)
	# ---- the bridge reaches both banks
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var mid := FarmBuilder.ORIGIN + Vector3(0, 5, 17.0)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(mid, mid + Vector3(0, -10, 0), WorldBuilder.L_GROUND))
	var far := FarmBuilder.ORIGIN + Vector3(0, 5, 23.0)
	var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(far, far + Vector3(0, -10, 0), WorldBuilder.L_GROUND))
	check("WORLD", "the bridge deck is walkable over the river and lands on the far bank",
		not hit.is_empty() and (hit.position as Vector3).y > 0.6 and not hit2.is_empty() and absf((hit2.position as Vector3).y) < 0.2)
	var tufts := 0
	for mm in W.find_children("*", "MultiMeshInstance3D", true, false):
		tufts += (mm as MultiMeshInstance3D).multimesh.instance_count
	check("WORLD", "grass and flower tufts cover the lawns and the allotment", tufts > 4000, "%d tufts" % tufts)
	# ---- cards fade by themselves
	var pn: GamePanels = main.ui.panels
	pn.card("测试", ["一行"], "calendar", "ban_tanabata", 0.2)
	pn.card("测试2", ["一行"], "", "", 0.2)
	pn.card("测试3", ["一行"], "", "", 0.2)
	check("UI5", "at most two cards at a time", pn._cards.size() <= 2)
	await get_tree().create_timer(1.6).timeout
	check("UI5", "cards fade out on their own", pn._cards.is_empty(), "%d left" % pn._cards.size())
	# ---- save v3
	check("SAVE", "save v3 keeps experience, bag size, chest, recipes and the can", G.save_game())
	var snap: Dictionary = G.to_dict()
	G.new_game()
	G.clock_paused = true
	G.load_game()
	check("SAVE", "…and loads them back", G.farm_xp == int(snap.farm_xp) and G.bag_cap == 30 and int(G.storage.get("potato", 0)) == int(snap.storage.get("potato", -1))
		and G.recipe_known("focaccia") and G.can_level == 1,
		"xp %d/%d cap %d potato %d focaccia %s can %d" % [G.farm_xp, int(snap.farm_xp), G.bag_cap, int(G.storage.get("potato", 0)), G.recipe_known("focaccia"), G.can_level])


## v0.6: achievements, 晴町旧物, the picture book, chapter 3 (Q10–Q15), the town finishing what was
## left before the festival, and save v4.
func v06_checks() -> void:
	var W: WorldBuilder = main.world
	Progress.quiet = true
	# ---- data and assets
	check("ACH", "32 achievements with a badge each, 13 keepsakes with a picture each",
		Progress.ach_db.size() == 32 and Progress.col_db.size() == 13
		and Progress.ach_db.all(func(a): return ResourceLoader.exists("res://assets/ui/badges/%s.png" % a.id))
		and Progress.col_db.all(func(c): return ResourceLoader.exists("res://assets/ui/collection/%s.jpg" % c.id)))
	Progress.check()
	check("ACH", "achievements already earned are unlocked (moving in, the first market, the first harvest)",
		Progress.has("move_in") and Progress.has("first_market") and Progress.has("first_harvest"), str(G.achievements.keys()))
	check("ACH", "condition parser: counters, quests, items, >=", Progress.holds("q:Q00") and not Progress.holds("coins>=999999")
		and Progress.holds("stat:harvests>=1") and Progress.holds("level>=1") and not Progress.holds("memories>=13"))
	var keep_coins: int = G.coins
	G.achievements.erase("coins_1000")
	G.coins = 10
	Progress.check()
	var n0: int = G.achievements.size()
	G.coins = maxi(keep_coins, 1000)
	G.state_changed.emit()
	# Progress checks once per process frame; headless physics catch-up may emit
	# three physics frames before another process callback gets a turn.
	for _frame: int in 3:await get_tree().process_frame
	check("ACH", "reaching 1000 coins unlocks 小小积蓄 by itself (checked when the state changes)", Progress.has("coins_1000") and G.achievements.size() > n0)
	check("ACH", "progress bars: harvest_100 shows a partial value", Progress.progress("harvest_100") > 0.0 and Progress.progress("harvest_100") < 1.0 or Progress.has("harvest_100"))
	# ---- the book panel
	main.ui.book.open("ach")
	await frames(3)
	var bp: Control = main.ui.modal_layer.get_child(main.ui.modal_layer.get_child_count() - 1) if main.ui.modal_layer.get_child_count() > 0 else null
	var vp := main.get_viewport().get_visible_rect()
	check("BOOK", "the picture book opens (K) and fits on screen", main.ui.modal == "book" and bp != null and vp.encloses(bp.get_global_rect()), str(bp.get_global_rect() if bp else "none"))
	for t in ["col", "crops", "dishes", "ach"]:
		main.ui.book._set_tab(t)
		await frames(1)
	main.ui.close_modal()
	await frames(2)
	# ---- chapter 3 from the start
	for q in ["Q10", "Q11", "Q12", "Q13", "Q14", "Q15"]:
		G.quests[q] = {"state": "locked", "step": 0}
	G.collection = {}
	G.flags.erase("summer_shared")
	G.day = 5
	G.minute = 9.0 * 60.0
	G.flags.erase("fest_bon_odori")
	G.flags.erase("fest_hanabi")
	main.story.lore._on_day(5)
	check("LORE", "the morning after the first market, grandma's box is an available invitation", G.qstate("Q10") == "available")
	main.enter_room()
	await frames(30)
	main.player.global_position = HouseBuilder.ORIGIN + Vector3(-4.6, 0.05, 0.3)
	await use("room_closet")
	check("LORE", "the closet holds the 2011 photo and grandma's letter", Progress.found("col_photo2011") and Progress.found("col_letter") and G.at_step("Q10", "show_mio"))
	main.exit_room()
	await frames(30)
	G.minute = 10.0 * 60.0
	main.update_npcs(true)
	await use("mio", [0])
	check("LORE", "Mio recognises herself in the photo; the notebook quest starts", G.qstate("Q10") == "done" and G.at_step("Q11", "find_notebook"))
	await use("center_door")
	check("LORE", "健一's notebook is in the community centre storeroom", Progress.found("col_notebook") and G.at_step("Q11", "show_haru"))
	await use("haru")
	check("LORE", "Haru reads 健一's handwriting", G.at_step("Q11", "report_mio11"))
	await use("mio")
	check("LORE", "Mio sets the festival for 7月20日; lanterns and the yagura open up", G.qstate("Q11") == "done" and G.qstate("Q12") == "available" and G.qstate("Q13") == "available")
	await use("haru")
	check("LORE", "Haru starts both jobs and hands over the yagura blueprint", G.at_step("Q12", "buy_washi") and G.at_step("Q13", "ask_tanaka") and Progress.found("col_blueprint"))
	G.coins += 200
	await use("shop_zakka", [{"buy": {"washi": 5}}])
	main.story.lore.checks()
	check("LORE", "five sheets of washi from the zakka shop", G.count("washi") >= 5 and G.at_step("Q12", "get_bamboo"), "washi %d %s" % [G.count("washi"), G.qstep_id("Q12")])
	check("LORE", "after the notebook, 阿健 found the old market poster", Progress.found("col_poster"))
	await use("east_end")
	await frames(20)
	G.minute = 15.0 * 60.0
	main.update_npcs(true)
	await use("tanaka")
	check("LORE", "Tanaka gives bamboo strips", G.has("bamboo_strip", 5) and G.at_step("Q12", "make_lanterns"))
	await use("tanaka")
	check("LORE", "about the yagura, Tanaka only talks in the evening", G.at_step("Q13", "ask_tanaka"))
	G.minute = 17.5 * 60.0
	main.update_npcs(true)
	await use("tanaka")
	check("LORE", "in the evening he tells of 健一 and the last fireworks", G.at_step("Q13", "carry_wood"))
	for i in 3:
		await use("farm_logs")
	check("LORE", "six logs from the farm's woodpile", G.has("wood", 6) and G.at_step("Q13", "give_wood"))
	await use("tanaka")
	check("LORE", "the wood goes to Tanaka: the yagura will stand", G.qstate("Q13") == "done" and not G.has("wood"))
	await use("farm_exit")
	await frames(20)
	G.minute = 10.0 * 60.0
	main.update_npcs(true)
	await use("haru")
	check("LORE", "five hand-made lanterns with Haru", G.count("chochin_hand") == 5 and G.at_step("Q12", "give_lanterns"))
	await use("mio")
	check("LORE", "the lanterns go to Mio", G.qstate("Q12") == "done" and G.count("chochin_hand") == 0)
	await use("board")
	await use("library")
	check("LORE", "keepsakes around town: the 1968 courtyard photo, the old map", Progress.found("col_zelkova1968") and Progress.found("col_oldmap"))
	# ---- the summer festival night
	G.day = 16
	G.minute = 9.0 * 60.0
	main.story.lore._on_day(16)
	main.update_npcs(true)
	await use("aoi")
	check("LORE", "the day before the festival, Aoi hands over a teru-teru-bozu", Progress.found("col_teruteru"))
	G.day = 17
	main.story.lore._on_day(17)
	G.minute = 19.2 * 60.0
	G.phase = "market"
	main.sync_festival_state()
	main.update_npcs(true)
	main.story.lore.checks()
	main.story.lore.checks()
	check("LORE", "on 7月20日 the festival quest starts and the player is already in the courtyard", G.at_step("Q14", "bon_odori14"), "%s %s" % [G.qstate("Q14"), G.qstep_id("Q14")])
	G.minute = 20.2 * 60.0
	await use("yagura")
	main.story.lore.checks()
	check("LORE", "after the bon-odori, the next step is Mio and the goldfish", G.at_step("Q14", "goldfish_mio"))
	await use("mio", [0])
	check("LORE", "the promise at the goldfish stall: a new photo is taken and kept", G.qstate("Q14") == "done" and Progress.found("col_photo_new")
		and FileAccess.file_exists(G.photo_path()) and G.qstate("Q15") == "available", "Q14=%s/%s shared=%s photo=%s" % [G.qstate("Q14"), G.qstep_id("Q14"), str(G.flags.get("summer_shared", {})), str(Progress.found("col_photo_new"))])
	G.phase = "prep"
	# ---- the fireworks again
	G.day = 18
	G.minute = 10.0 * 60.0
	await use("east_end")
	await frames(20)
	main.update_npcs(true)
	await use("tanaka")
	await use("farm_shed")
	check("LORE", "the old fireworks tube from the top shelf of the shed", Progress.found("col_fire_tube") and G.at_step("Q15", "watch_hanabi"))
	G.flags["fest_hanabi"] = true
	main.story.lore.checks()
	await frames(4)
	await get_tree().create_timer(0.5).timeout
	check("LORE", "watching the fireworks ends chapter 3", G.qstate("Q15") == "done", G.qstep_id("Q15"))
	await use("farm_hokora")
	check("LORE", "the ema at the little shrine across the river", Progress.found("col_ema"))
	await use("farm_exit")
	await frames(20)
	# ---- nothing can be missed
	G.quests["Q12"] = {"state": "active", "step": 1}
	G.quests["Q13"] = {"state": "available", "step": 0}
	main.story.lore._on_day(16)
	check("LORE", "the day before the festival, the town finishes lanterns and yagura that were left", G.qstate("Q12") == "done" and G.qstate("Q13") == "done")
	# ---- picture book counters
	var nc: int = G.zukan.crops.size()
	var nd: int = G.zukan.dishes.size()
	check("BOOK", "harvested crops and cooked dishes are in the picture book", nc >= 2 and nd >= 1, "crops %d dishes %d" % [nc, nd])
	# ---- lore lines join the everyday dialogue
	var e := Dialogue.pick("kazuko")
	check("TALK", "the new store keeper has lines of her own", not e.is_empty() and str(e.id).begins_with("v06_kazuko"))
	check("TALK", "chapter-3 lines are in the pool for every neighbour", ["mio", "ren", "haru", "tanaka", "aoi"].all(func(w): return Dialogue.entries.filter(func(x): return x.who == w and str(x.id).begins_with("v06_")).size() >= 8))
	# ---- the shops have insides
	G.day = 20
	G.minute = 11.0 * 60.0
	main.update_npcs(true)
	await use("shop_store")
	await frames(8)
	var ks: NPC = main.npcs.kazuko
	var store_sp := InteriorBuilder.spec_for("store")
	check("SHOPIN", "the general store is a room: the door leads inside, Kazuko stands behind the counter",
		main.in_room and main.room_kind == "store" and main.area_name() == "晴町商店" and not ks.home
		and ks.global_position.distance_to(store_sp.origin + store_sp.keeper) < 0.6,
		"kazuko at %s" % ks.global_position)
	check("SHOPIN", "the store is furnished and stocked", W.interiors.store.find_children("*", "MeshInstance3D", true, false).size() > 60)
	var c0: int = G.count("seed_radish")
	await use("store_counter", [{"buy": {"seed_radish": 2}}])
	check("SHOPIN", "Kazuko sells from her counter", G.count("seed_radish") == c0 + 2 and G.flags.get("met_kazuko", false))
	await use("store_exit")
	await frames(8)
	check("SHOPIN", "walking out puts you back on the street at the shop door", not main.in_room and main.player.global_position.distance_to(Vector3(-36.0, 0.1, -13.2)) < 1.5)
	await use("bakery")
	await frames(8)
	var bakery_sp := InteriorBuilder.spec_for("bakery")
	check("SHOPIN", "the bakery is a room with Ren behind the counter",
		main.room_kind == "bakery" and (main.npcs.ren as NPC).global_position.distance_to(bakery_sp.origin + bakery_sp.keeper) < 0.6,
		"ren at %s" % (main.npcs.ren as NPC).global_position)
	await use("bakery_exit")
	await frames(8)
	check("SHOPIN", "Ren goes back to his routine when you leave", not main.in_room and (main.npcs.ren as NPC).fest_key == "")
	G.day = 21     # a Wednesday: the store is closed
	await use("shop_store")
	await frames(4)
	check("SHOPIN", "on Wednesdays the store stays shut", not main.in_room and G.weekday() == 2, "weekday %d" % G.weekday())
	# ---- voices (Qwen3-TTS): every line in the dialogue pool has a clip for its speaker
	var total_l := 0
	var voiced := 0
	for de in Dialogue.entries:
		for ln in de.lines:
			if str(ln[0]) in ["mio", "ren", "aoi", "kazuko", "sora"] and not str(ln[2]).contains("%"):
				total_l += 1
				if ResourceLoader.exists("res://assets/audio/voice/%s/%s.ogg" % [ln[0], str(ln[2]).md5_text()]):
					voiced += 1
	check("VOICE", "the dialogue pool is voiced (clips looked up by the md5 of the line)", total_l > 150 and voiced >= total_l * 0.97, "%d / %d" % [voiced, total_l])
	check("VOICE", "a voice bus and a voice volume setting exist", AudioServer.get_bus_index("Voice") >= 0 and G.settings.has("vol_voice"))
	check("VOICE", "the narrator, Haru and Tanaka stay text only", Audio.voice("narrator", "你把活动标牌端端正正地贴在公告栏中央。路过的人放慢了脚步。") == 0.0
		and not DirAccess.dir_exists_absolute("res://assets/audio/voice/narrator") and not DirAccess.dir_exists_absolute("res://assets/audio/voice/haru")
		and not DirAccess.dir_exists_absolute("res://assets/audio/voice/tanaka"))
	# ---- music for every festival
	for f in ["tanabata", "contest", "natsumatsuri", "bon_odori", "hanabi", "obon", "tsukimi", "farm", "night", "rain", "shop"]:
		if not ResourceLoader.exists("res://assets/audio/music/%s.ogg" % f):
			check("MUS", "music track %s exists" % f, false)
	var want := {}
	var saved_day: int = G.day
	for f in [["tanabata", 4, 19.0, "town", "tanabata"], ["contest", 11, 11.0, "town", "contest"], ["natsumatsuri", 17, 18.0, "town", "natsumatsuri"],
			["bon_odori", 17, 20.5, "town", "bon_odori"], ["obon", 43, 19.0, "farm", "obon"], ["tsukimi", 76, 19.5, "town", "tsukimi"]]:
		G.day = f[1]
		G.minute = f[2] * 60.0
		var was: String = W.region
		W.region = f[3]
		want[f[0]] = main._music_pick() == f[4]
		W.region = was
	G.day = saved_day
	G.minute = 11.0 * 60.0
	check("MUS", "each festival picks its own music", want.values().all(func(x): return x), str(want))
	# ---- save v4
	Progress.check()
	var ach_n: int = G.achievements.size()
	var col_n: int = G.collection.size()
	check("SAVE", "save v4 keeps achievements, keepsakes and the picture book", G.save_game())
	G.new_game()
	G.clock_paused = true
	G.load_game()
	check("SAVE", "…and loads them back", G.achievements.size() == ach_n and G.collection.size() == col_n and G.zukan.crops.size() == nc and G.qstate("Q15") == "done",
		"ach %d/%d col %d/%d" % [G.achievements.size(), ach_n, G.collection.size(), col_n])
	Progress.quiet = false



# ------------------------------------------------------------------ v0.6: crowds, clearance, the farm lane
const WALKWAY := [Vector2(-3.0, -6.4), Vector2(-3.0, -2.6), Vector2(-3.0, 0.2), Vector2(-4.4, 1.7), Vector2(-3.4, 12.6),
	Vector2(1.0, 12.6), Vector2(10.4, 12.6)]

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _solid_at(p: Vector3, r: float = 0.3) -> Array:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = r
	sh.height = 1.4
	q.shape = sh
	q.transform = Transform3D(Basis(), p + Vector3(0, 0.95, 0))
	q.collision_mask = WorldBuilder.L_SOLID
	var hits := []
	for h in space.intersect_shape(q, 4):
		var c: Node3D = h.collider
		hits.append("%s@%.1f,%.1f" % [c.get_parent().name if c.get_parent() else c.name, c.global_position.x, c.global_position.z])
	return hits


func _leg_blocked(a: Vector3, b: Vector3) -> String:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.26
	q.shape = sh
	q.collision_mask = WorldBuilder.L_SOLID
	var n := maxi(2, int(a.distance_to(b) / 0.25))
	for i in n + 1:
		q.transform = Transform3D(Basis(), a.lerp(b, i / float(n)) + Vector3(0, 0.9, 0))
		var h := space.intersect_shape(q, 1)
		if not h.is_empty():
			var c: Node3D = h[0].collider
			return "%s@%.1f,%.1f" % [c.get_parent().name, c.global_position.x, c.global_position.z]
	return ""


## Every activity loop: [context, id, stops (world space, stop 0 = the anchor)].
func _all_loops() -> Array:
	var out := []
	for id in Layout.MARKET_ROAM:
		var info: Dictionary = Layout.NPC[id]
		var st := [[info.market, info.market_yaw, "idle", 8.0]]
		st.append_array(Layout.MARKET_ROAM[id])
		out.append(["market", id, st])
	for fid in G.festivals_db:
		var f: Dictionary = G.festivals_db[fid]
		for id in (f.get("npc", {}) as Dictionary):
			var e: Array = f.npc[id]
			var off := FarmBuilder.ORIGIN if str(e[0]) == "farm" else Vector3.ZERO
			var st := [[Vector3(float(e[1][0]), 0, float(e[1][2])) + off, float(e[2]), str(e[3]), 6.0]]
			for r in (f.get("roam", {}) as Dictionary).get(id, []):
				st.append([Vector3(float(r[0][0]), 0, float(r[0][2])) + off, float(r[1]), str(r[2]), float(r[3])])
			out.append([fid, id, st])
	return out


func crowd_checks() -> void:
	var W: WorldBuilder = main.world
	# ---- the road to the allotment: the same lantern gate at both ends, the lane drops out of town and climbs out of the farm
	var gates := 0
	for n in W.find_children("P_farm_gate", "", true, false):
		gates += 1
	check("LANE", "the lantern gate stands at the east end of the street and at the farm entrance", gates >= 2, "gates %d" % gates)
	check("LANE", "the street's east wall is open under the gate",
		Layout.WALLS.all(func(w): return not (absf(float(w[0]) - 42.7) < 0.1 and absf(float(w[2]) - 42.7) < 0.1
			and minf(float(w[1]), float(w[3])) < Layout.STREET_Z and maxf(float(w[1]), float(w[3])) > Layout.STREET_Z)))
	check("LANE", "the lane runs downhill out of town and uphill out of the farm",
		WorldBuilder.lane_depth(60.0) < -2.5 and FarmBuilder.lane_height(-50.0) > 2.5 and WorldBuilder.lane_depth(43.0) == 0.0)
	await use("east_end")
	await frames(40)
	var fe: Vector3 = main.player.global_position - FarmBuilder.ORIGIN
	check("LANE", "going down the lane arrives just inside the farm gate, walking east", main.world.region == "farm" and absf(fe.x - FarmBuilder.ENTRY.x) < 0.3
		and fe.x > FarmBuilder.GATE_POS.x and absf(wrapf(main.player._face_yaw - PI / 2.0, -PI, PI)) < 0.2)
	await use("farm_exit")
	await frames(40)
	var te: Vector3 = main.player.global_position
	check("LANE", "coming back arrives just inside the town gate, walking west", main.world.region == "town" and te.x < WorldBuilder.EXIT_GATE.x
		and te.x > 40.0 and absf(te.z - Layout.STREET_Z) < 0.5 and absf(wrapf(main.player._face_yaw + PI / 2.0, -PI, PI)) < 0.2, str(te))
	# ---- clearance: nobody stands in a prop, on the walkway or on someone else
	var bad := []
	var crowd := {}
	for L in _all_loops():
		var st: Array = L[2]
		for i in st.size():
			var p: Vector3 = st[i][0]
			var hit := _solid_at(p)
			if not hit.is_empty():
				bad.append("%s %s stop %d in %s" % [L[0], L[1], i, hit])
			var leg := _leg_blocked(p, st[(i + 1) % st.size()][0])
			if st.size() > 1 and leg != "":
				bad.append("%s %s leg %d crosses %s" % [L[0], L[1], i, leg])
			if p.x < 300.0 and str(L[0]) != "contest":
				var w := 99.0
				for k in WALKWAY.size() - 1:
					w = minf(w, _seg_dist(Vector2(p.x, p.z), WALKWAY[k], WALKWAY[k + 1]))
				if w < 0.8:
					bad.append("%s %s stop %d on the walkway (%.2f m)" % [L[0], L[1], i, w])
			for o in crowd.get(L[0], []):
				if o[0] != L[1] and Vector2(p.x, p.z).distance_to(Vector2(o[1].x, o[1].z)) < 0.9:
					bad.append("%s %s stop %d on %s" % [L[0], L[1], i, o[0]])
		for i in st.size():
			crowd[L[0]] = crowd.get(L[0], []) + [[L[1], st[i][0]]]
	var np := 0
	for pr in Layout.POINTS:
		for id in Layout.NPC:
			var info: Dictionary = Layout.NPC[id]
			if Vector2(pr[1], pr[2]).distance_to(Vector2(info.market.x, info.market.z)) < 0.9:
				bad.append("market spot of %s on the point %s" % [id, pr[0]])
				np += 1
	check("CLEAR", "activity stops and legs stay clear of props, the walkway and each other", bad.is_empty(), "; ".join(bad.slice(0, 14)))
	var board := W.find_child("P02", true, false) as Node3D
	check("CLEAR", "the notice board stands on the pavement in front of the low wall, not in it",
		board != null and board.global_position.z < -5.4 - 0.09 - 0.45 and _solid_at(Vector3(-8.5, 0, -7.2), 0.25).is_empty())
	# ---- the market walk-in: nobody's route passes through where the player stands
	var ppos := Vector2(-5.8, 9.2)
	var close := []
	for id in Layout.NPC:
		var info: Dictionary = Layout.NPC[id]
		var pts: Array = [info.get("route_start", info.prep)]
		pts.append_array(info.route)
		for k in pts.size() - 1:
			var a: Vector3 = pts[k]
			var b: Vector3 = pts[k + 1]
			var dd := _seg_dist(ppos, Vector2(a.x, a.z), Vector2(b.x, b.z))
			if dd < 1.4:
				close.append("%s %.2f" % [id, dd])
	check("CLEAR", "the market walk-in routes keep clear of the player", close.is_empty(), str(close))
	# ---- the market loops run, walk round the player rather than through them, and wait when held
	NPC.roam_enabled = true
	var was_phase: String = G.phase
	G.phase = "market"
	main.to_market_positions(false)
	main._sync_roams()
	var n: NPC = main.npcs["aoi"]
	var p1: Vector3 = Layout.MARKET_ROAM.aoi[0][0]
	var p2: Vector3 = Layout.MARKET_ROAM.aoi[1][0]
	main.player.global_position = Vector3(12.0, 0.1, 4.0)
	n._roam_wait = 0.0
	for i in 480:
		await get_tree().physics_frame
		if not n.is_moving() and n.global_position.distance_to(p1) < 0.2:
			break
	check("CROWD", "at the market a neighbour walks her loop to the next stop", n.roam_key == "market" and n.global_position.distance_to(p1) < 0.2,
		"%s key=%s freeze=%s hold=%s talking=%s moving=%s leg=%s locks=%s busy=%s" % [n.global_position, n.roam_key, NPC.freeze, n.hold, n.talking,
		n._moving, n._roam_leg, G._ui_locks.keys(), main.story.busy])
	if n.global_position.distance_to(p1)>=.2:
		var probe:=PhysicsShapeQueryParameters3D.new()
		probe.shape=n.MOTION_ROUTE.capsule();probe.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS
		probe.exclude=[n.body.get_rid()];probe.transform=Transform3D(Basis.IDENTITY,n.global_position+Vector3(0,.8,0))
		for overlap: Dictionary in n.get_world_3d().direct_space_state.intersect_shape(probe,16):
			var collider:=overlap.collider as CollisionObject3D
			print("CROWD_BLOCKER ",collider.get_path()," layer=",collider.collision_layer," at=",collider.global_position)
	var mid := p1.lerp(p2, 0.5)
	main.player.global_position = Vector3(mid.x + 0.05, 0.1, mid.z)
	main.player.velocity = Vector3.ZERO
	n._roam_wait = 0.0
	var nearest := 99.0
	for i in 900:      # a gesture at the first stop, the detour and a short wait can take ~10 s
		await get_tree().physics_frame
		var pp: Vector3 = main.player.global_position
		nearest = minf(nearest, Vector2(pp.x, pp.z).distance_to(Vector2(n.global_position.x, n.global_position.z)))
		if not n.is_moving() and n.global_position.distance_to(p2) < 0.2:
			break
	check("CROWD", "…and steps round the player standing in the way instead of walking through", nearest > 0.6 and n.global_position.distance_to(p2) < 0.2,
		"nearest %.2f at %s moving=%s leg=%s yield=%.2f others=%s" % [nearest, n.global_position, n._moving, n._roam_leg, n._yield_t,
		str(main.npcs.values().filter(func(x): return x != n and (x as Node3D).global_position.distance_to(n.global_position) < 2.0).map(func(x): return "%s@%s" % [x.npc_id, x.global_position]))])
	n.hold = true
	n._roam_wait = 0.0
	var at := n.global_position
	await frames(40)
	check("CROWD", "a held neighbour stays put (autoplay walks over to talk)", n.global_position.distance_to(at) < 0.05)
	n.hold = false
	var moved := 0
	for id in main.npcs:
		if (main.npcs[id] as NPC).roam_key == "market":
			moved += 1
	check("CROWD", "everyone at the market is on a loop", moved == Layout.MARKET_ROAM.size(), "%d" % moved)
	G.phase = was_phase
	main._sync_roams()
	check("CROWD", "loops stop when the market is over", main.npcs.values().all(func(x): return (x as NPC).roam_key == ""))
	NPC.roam_enabled = false
	main._to_prep_positions()
	# ---- shops: walking out through the door lands on the street; no holes; falling is caught everywhere
	for k in ["store", "bakery"]:
		var sp := InteriorBuilder.spec_for(k)
		main.enter_interior(k)
		await frames(40)
		var o: Vector3 = sp.origin
		var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
		var holes := 0
		for dz in [3.4, 4.5, 6.0, 8.5]:
			for dx in [-4.0, 0.0, 4.0]:
				var q := PhysicsRayQueryParameters3D.create(o + Vector3(dx, 1.0, dz), o + Vector3(dx, -1.0, dz), WorldBuilder.L_GROUND)
				if space.intersect_ray(q).is_empty():
					holes += 1
		check("SHOP6", "%s: the painted street outside the door has ground under it" % k, holes == 0, "holes %d" % holes)
		main.player.global_position = o + Vector3(float(sp.door_x), 0.1, (sp.size as Vector2).y / 2.0 + 0.5)
		main.player.velocity = Vector3.ZERO
		await frames(50)
		var pp: Vector3 = main.player.global_position
		check("SHOP6", "%s: walking out through the door goes back to the street" % k, not main.in_room and pp.distance_to(sp.exit) < 0.6 and pp.y > -0.3,
			"in_room=%s at %s" % [main.in_room, pp])
		check("CLEAR", "%s: the street spot you come out at is clear" % k, _solid_at(sp.exit).is_empty(), str(_solid_at(sp.exit)))
	main.player.global_position = Vector3(-10.0, 0.1, -11.0)
	await frames(40)
	main.player.global_position = Vector3(-10.0, -4.0, -11.0)
	main.player.velocity = Vector3.ZERO
	await frames(10)
	var rp: Vector3 = main.player.global_position
	check("SHOP6", "falling below the ground puts you back where you last stood", rp.y > -0.5 and Vector2(rp.x, rp.z).distance_to(Vector2(-10.0, -11.0)) < 1.0, str(rp))
	main.enter_interior("store")
	await frames(40)
	main.player.global_position = InteriorBuilder.spec_for("store").origin + Vector3(0, -4.0, 0)
	await frames(10)
	check("SHOP6", "…inside a shop too", main.player.global_position.y > -0.5 and main.in_room)
	main.exit_interior()
	await frames(40)
	# ---- shop furniture: inside the walls, not overlapping, keeper spot free
	for fk in ["store", "bakery"]:
		var f_ib: InteriorBuilder = main.world.interiors[fk]
		var f_sp := InteriorBuilder.spec_for(fk)
		var f_hw: float = (f_sp.size as Vector2).x / 2.0
		var f_hd: float = (f_sp.size as Vector2).y / 2.0
		var f_boxes := []
		for f_piece in f_ib.pieces:
			var f_bb := AABB()
			var f_first := true
			for mi in WorldBuilder.find_meshes(f_piece):
				var f_g: AABB = mi.global_transform * mi.get_aabb()
				f_bb = f_g if f_first else f_bb.merge(f_g)
				f_first = false
			f_bb.position -= f_ib.global_position
			f_boxes.append([str(f_piece.name), f_bb])
		var f_bad := []
		for f_b0 in f_boxes:
			var f_bb: AABB = f_b0[1]
			if f_bb.position.x < -f_hw - 0.05 or f_bb.end.x > f_hw + 0.05 or f_bb.position.z < -f_hd - 0.05 or f_bb.end.z > f_hd + 0.05:
				f_bad.append("%s through the wall %s" % [f_b0[0], f_bb])
		for i in f_boxes.size():
			for j in range(i + 1, f_boxes.size()):
				var f_o: AABB = (f_boxes[i][1] as AABB).intersection(f_boxes[j][1])
				if f_o.size.x > 0.08 and f_o.size.z > 0.08:
					f_bad.append("%s overlaps %s by %.2f x %.2f" % [f_boxes[i][0], f_boxes[j][0], f_o.size.x, f_o.size.z])
		var f_keeper: Vector3 = f_sp.keeper
		for f_b0 in f_boxes:
			var f_bb: AABB = f_b0[1]
			if f_bb.grow(0.2).has_point(Vector3(f_keeper.x, 0.5, f_keeper.z)):
				f_bad.append("the keeper stands in %s" % f_b0[0])
		check("CLEAR", "%s: the furniture stays inside the walls and apart, the keeper stands free" % fk, f_bad.is_empty(), "; ".join(f_bad))
	# the loops are wired to the festivals and the market
	check("CROWD", "each festival and the market have activity loops", G.festivals_db.values().all(func(f): return not (f.get("roam", {}) as Dictionary).is_empty())
		and Layout.MARKET_ROAM.size() >= 6)


## v0.6 feedback: the prologue is a slideshow of codex anime panels with 空's voice; the old movie is gone.
func prologue_checks() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prologue.json"))
	var ps: Array = d.panels
	var missing := []
	for p in ps:
		if not ResourceLoader.exists("res://assets/ui/prologue/%s.jpg" % p.img):
			missing.append(str(p.img))
		if not ResourceLoader.exists("res://assets/audio/voice/%s/%s.ogg" % [d.voice, str(p.text).md5_text()]):
			missing.append("voice " + str(p.img))
	check("PRO", "the arrival has 4 anime panels, each with 空's line voiced", ps.size() == 4 and missing.is_empty(), str(missing))
	var tex: Texture2D = load("res://assets/ui/prologue/%s.jpg" % ps[0].img)
	check("PRO", "panels are 1920×1080", tex != null and tex.get_width() == 1920 and tex.get_height() == 1080)
	check("PRO", "the old prologue movie is gone", not ResourceLoader.exists("res://assets/video/prologue.ogv") and not DirAccess.dir_exists_absolute("res://assets/video"))
	var total := 0.0
	for p in ps:
		total += maxf(4.5, Audio.voice_length(str(d.voice), str(p.text)) + 2.2) + float(p.get("hold", 0.0))
	check("PRO", "arrival panels stay readable without showing the later promise", total > 20.0 and total < 60.0, "%.1f s" % total)
	check("PRO", "the prologue script loads", load("res://scripts/ui/prologue.gd") != null)
	# v0.7.3: every dialogue portrait is codex's own transparent PNG (no keying): real alpha
	# around the bust, and no see-through holes in the clothes
	var cream_bad := []
	for f in DirAccess.get_files_at("res://assets/ui/portraits"):
		if not f.ends_with(".png"):
			continue
		var img: Image = (load("res://assets/ui/portraits/" + f) as Texture2D).get_image()
		img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		var clear := 0
		for y in range(0, h, 8):
			for x in range(0, w, 8):
				if img.get_pixel(x, y).a < 0.05:
					clear += 1
		if clear < (w / 8) * (h / 8) / 4:
			cream_bad.append("%s only %d%% transparent" % [f, clear * 100 / ((w / 8) * (h / 8))])
		if img.get_pixel(0, 0).a > 0.01 or img.get_pixel(w - 1, 0).a > 0.01:
			cream_bad.append(f + " corner not transparent")
		var holes := _portrait_holes(img)
		if holes > 20:
			cream_bad.append("%s %d hole cells in the clothes" % [f, holes])
	check("UI6", "dialogue portraits have a real transparent background and no holes in the clothes", cream_bad.is_empty(), str(cream_bad))


## v0.7.3: generated models stand upright, on the ground and apart. The lean comes from
## art/tools/level_check.py (Blender); the placement from PropAudit on the built world.
func props_checks() -> void:
	wall_material_checks()
	shop_build_checks()
	material_checks()
	landmark_quality_checks()
	model_inventory_checks()
	architecture_checks()
	building_life_checks()
	var path := "res://assets/models/_stats/_level.json"
	var rep: Dictionary = {}
	if FileAccess.file_exists(path):
		rep = JSON.parse_string(FileAccess.get_file_as_string(path))
	var rep_time := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	var stale: Array = []
	var leaning: Array = []
	var turned: Array = []
	for f in DirAccess.get_files_at("res://assets/models"):
		if not f.ends_with(".glb"):
			continue
		var id := f.get_basename()
		if not rep.has(id) or FileAccess.get_modified_time("res://assets/models/" + f) > rep_time + 5:
			stale.append(id)
			continue
		var r: Dictionary = rep[id]
		if float(r.base_frac) >= 0.45 and float(r.tilt) > 2.0:
			leaning.append("%s %.1f°" % [id, float(r.tilt)])
		if float(r.base_frac) >= 0.45 and float(r.get("rect_fill", 0.0)) >= 0.9 and absf(float(r.get("square_deg", 0.0))) > 2.0:
			turned.append("%s %.1f°" % [id, float(r.square_deg)])
	check("PROPS", "every model has a fresh lean measurement (rerun art/tools/level_check.py after exporting)", stale.is_empty(), str(stale))
	check("PROPS", "models that stand on a real base stand level (within 2°)", rep.size() > 100 and leaning.is_empty(), str(leaning))
	check("PROPS", "boxy models are squared to their front (within 2°)", turned.is_empty(), str(turned))
	await frames(2)
	var audit_region: String=main.world.region
	main.world.set_region("town")
	await frames(2)
	var found := PropAudit.run(main.world, Layout.WALLS)
	main.world.set_region("farm")
	await frames(2)
	found.append_array(PropAudit.run(main.world))
	main.world.set_region(audit_region)
	var by_kind := {"overlap": [], "in_building": [], "in_wall": [], "floating": [], "sunk": []}
	for f: Dictionary in found:
		(by_kind[f.kind] as Array).append(PropAudit.describe(f))
	for k in by_kind:
		for line in by_kind[k]:
			print("  AUDIT ", line)
	var n_inst := PropAudit.instances(main.world).size()
	check("PROPS", "the audit sees the town, farm, house and shops (%d models)" % n_inst, n_inst > 300)
	check("PROPS", "no two props share floor space", (by_kind.overlap as Array).is_empty(), "%d" % (by_kind.overlap as Array).size())
	check("PROPS", "no prop pushes into a building", (by_kind.in_building as Array).is_empty(), "%d" % (by_kind.in_building as Array).size())
	check("PROPS", "no prop crosses a block wall", (by_kind.in_wall as Array).is_empty(), "%d" % (by_kind.in_wall as Array).size())
	check("PROPS", "nothing floats above the ground", (by_kind.floating as Array).is_empty(), "%d" % (by_kind.floating as Array).size())
	check("PROPS", "nothing is sunk into the ground", (by_kind.sunk as Array).is_empty(), "%d" % (by_kind.sunk as Array).size())
	await _arm_cloth_checks()
	# Thin glazing remains in front of actual rooms; DISPLAY checks their geometry.
	var wins: Array = main.world.find_children("ShopWindow_*", "MeshInstance3D", true, false)
	var fronts := 0
	for w in ShopWindows.WINDOWS.values():
		fronts += (w as Array).size()
	check("PROPS", "every shop opening has a glass pane (%d windows)" % wins.size(), wins.size() == fronts and fronts >= 6)
	var lamp_day: float = (main.world.window_mats[0] as ShaderMaterial).get_shader_parameter("lamp")
	main.world.update_time(21.0 * 60.0, "sunny", true)
	var lamp_night: float = (main.world.window_mats[0] as ShaderMaterial).get_shader_parameter("lamp")
	main.world.update_time(GameState.minute, GameState.weather, true)
	check("PROPS", "the shops light up inside at night", lamp_night > lamp_day + 0.2, "day %.2f night %.2f" % [lamp_day, lamp_night])


## All boundary walls used to share the last wall's cap height (1.6 m), including 0.7 m walls.
func wall_material_checks() -> void:
	var bad: Array[String] = []
	var count := 0
	for node in main.world.get_children():
		if not (node is MeshInstance3D):
			continue
		var mesh := node as MeshInstance3D
		var mat := mesh.material_override as ShaderMaterial
		if mat == null or mat.shader.resource_path != "res://shaders/blockwall.gdshader":
			continue
		count += 1
		var height: float = (mesh.mesh as BoxMesh).size.y
		var cap: float = mat.get_shader_parameter("wall_top")
		if absf(cap - height) > 0.01:
			bad.append("wall %.2f / cap %.2f" % [height, cap])
	check("PROPS", "boundary cap height follows each wall, including low gate walls", count == Layout.WALLS.size()+ResidentialLife.GARDEN_WALL_COUNT and bad.is_empty(), str(bad))


func shop_build_checks() -> void:
	var bad: Array[String] = []
	for kind: String in InteriorBuilder.SPECS:
		var room := main.world.interiors[kind] as InteriorBuilder
		var expected: int = (InteriorBuilder.SPECS[kind].furniture as Array).size()
		if room.pieces.size() != expected:
			bad.append("%s: %d/%d furniture" % [kind, room.pieces.size(), expected])
	check("PROPS", "both shop interiors complete construction with all furniture", bad.is_empty(), str(bad))


func landmark_quality_checks() -> void:
	var report_path := "res://assets/models/_stats/_quality.json"
	var report: Dictionary = {}
	if FileAccess.file_exists(report_path):
		report = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	var quality: Dictionary = report.get("checks", {})
	var metrics: Dictionary = report.get("models", {})
	var stale: Array[String] = []
	for asset_id: String in ["P_farm_gate", "P_yagura", "P_deck_oven"]:
		var measurement: Dictionary = metrics.get(asset_id, {})
		var model_time := FileAccess.get_modified_time("res://assets/models/%s.glb" % asset_id)
		if measurement.is_empty() or float(model_time) > float(measurement.get("source_mtime", 0.0)) + 5.0:
			stale.append(asset_id)
	check("PROPS", "landmark quality measurements match the current models", not report.is_empty() and stale.is_empty(), str(stale))
	check("PROPS", "gate roof tiles have geometric relief", bool(quality.get("gate_roof_relief", false)), str(metrics.get("P_farm_gate", {})))
	check("PROPS", "bon-odori tower has a pitched roof instead of stacked boxes", bool(quality.get("yagura_pitched_roof", false)), str(metrics.get("P_yagura", {})))
	check("PROPS", "bakery oven has a detailed albedo atlas", bool(quality.get("oven_textured", false)), str(metrics.get("P_deck_oven", {})))
	check("PROPS", "replacement landmarks preserve their physical bounds", bool(quality.get("physical_bounds", false)), str(metrics))


func model_inventory_checks() -> void:
	var report_path := "res://assets/models/_stats/_audit.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model-audit-report="):
			report_path = arg.substr(21)
	var report: Dictionary = {}
	if FileAccess.file_exists(report_path):
		report = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	var models: Dictionary = report.get("models", {})
	var stale: Array[String] = []
	for file in DirAccess.get_files_at("res://assets/models"):
		if not file.ends_with(".glb"):
			continue
		var asset_id: String = file.get_basename()
		var measurement: Dictionary = models.get(asset_id, {})
		var stamp := FileAccess.get_modified_time("res://assets/models/" + file)
		if measurement.is_empty() or float(stamp) > float(measurement.get("source_mtime", 0.0)) + 5.0:
			stale.append(asset_id)
	var quality: Dictionary = report.get("checks", {})
	var detail: Dictionary = report.get("details", {})
	check("PROPS", "all game models have a fresh size, UV and topology inventory", models.size() >= 153 and stale.is_empty(), str(stale))
	check("PROPS", "anime assets do not inherit metallic or normal maps", bool(quality.get("matte_materials", false)), str(detail.get("matte", [])))
	check("PROPS", "solid regenerated props retain continuous surfaces after reduction", bool(quality.get("continuous_surfaces", false)), str(detail.get("fragmented", [])))
	check("PROPS", "large rebuilt houses retain sufficient albedo pixels per metre", bool(quality.get("building_density", false)), str(detail.get("density", [])))
	check("PROPS", "apartment retains six independently textured facades above 280 pixels per metre", bool(quality.get("apartment_modular_detail", false)), str(detail.get("apartment_modules", {})))
	check("PROPS", "rebuilt houses and shed preserve their measured footprint", bool(quality.get("physical_bounds", false)), str(detail.get("bounds", [])))
	var material_path := "res://assets/models/_stats/_material_detail.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--material-detail-report="):
			material_path = argument.substr(25)
	var material_report: Dictionary = {}
	if FileAccess.file_exists(material_path):
		material_report = JSON.parse_string(FileAccess.get_file_as_string(material_path))
	var material_models: Dictionary = material_report.get("models", {})
	var material_stale: Array[String] = []
	for building_id: String in ["H01", "H02", "H03", "S06", "S01", "S02", "S03", "S05", "S08", "M01_timber_machiya", "M03_gable_house", "M05_residential"]:
		var detail_metric: Dictionary = material_models.get(building_id, {})
		if detail_metric.is_empty() or float(FileAccess.get_modified_time("res://assets/models/%s.glb" % building_id)) > float(detail_metric.get("source_mtime", 0)) + 5.0:
			material_stale.append(building_id)
	check("PROPS", "twelve building texture-detail measurements match current assets", material_models.size() == 12 and material_stale.is_empty(), str(material_stale))
	var material_checks: Dictionary = material_report.get("checks", {})
	check("PROPS", "building atlases contain painted detail beyond interpolation and JPEG noise", bool(material_checks.get("authored_raster_detail", false)))


func architecture_checks() -> void:
	var path := "res://assets/models/_stats/_architecture.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--architecture-report="):
			path = arg.substr(22)
	var report: Dictionary = {}
	if FileAccess.file_exists(path):
		report = JSON.parse_string(FileAccess.get_file_as_string(path))
	var models: Dictionary = report.get("models", {})
	var stale: Array[String] = []
	for id: String in ["H01", "H02", "H03", "S06", "S01", "S02", "S03", "S05", "S08", "M01_timber_machiya", "M03_gable_house", "M05_residential"]:
		var metric: Dictionary = models.get(id, {})
		if metric.is_empty() or float(FileAccess.get_modified_time("res://assets/models/%s.glb" % id)) > float(metric.get("source_mtime", 0)) + 5.0:
			stale.append(id)
	var quality: Dictionary = report.get("checks", {})
	check("PROPS", "twelve buildings have fresh close-up geometry measurements", stale.is_empty() and models.size() == 12, str(stale))
	check("PROPS", "structural jambs and balcony rails deviate less than 6 mm", bool(quality.get("straight_joinery", false)), str(report.get("failed_profiles", [])))
	check("PROPS", "store produce has a dedicated atlas above 300 pixels per metre", bool(quality.get("produce_detail", false)), str(report.get("produce_density_px_m", 0)))
	var bakery_clear_path := "res://assets/models/_stats/_bakery_clear.json"
	for bakery_arg in OS.get_cmdline_user_args():
		if bakery_arg.begins_with("--bakery-clear-report="):
			bakery_clear_path = bakery_arg.substr(22)
	var bakery_clear: Dictionary = {}
	if FileAccess.file_exists(bakery_clear_path):
		bakery_clear = JSON.parse_string(FileAccess.get_file_as_string(bakery_clear_path))
	var bakery_clear_fresh: bool = float(FileAccess.get_modified_time("res://assets/models/S02.glb")) <= float(bakery_clear.get("source_mtime", 0)) + 5.0
	check("PROPS", "bakery display sill has no provider fragments in front of the opening", bakery_clear_fresh and bool(bakery_clear.get("passed", false)), str(bakery_clear.get("intrusions", [])))
	var identity_path := "res://assets/models/_stats/_identity.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--identity-report="):
			identity_path = argument.substr(18)
	var identity: Dictionary = {}
	if FileAccess.file_exists(identity_path):
		identity = JSON.parse_string(FileAccess.get_file_as_string(identity_path))
	var identity_models: Dictionary = identity.get("models", {})
	var identity_stale: Array[String] = []
	for asset_id: String in models:
		var measurement: Dictionary = identity_models.get(asset_id, {})
		if measurement.is_empty() or float(FileAccess.get_modified_time("res://assets/models/%s.glb" % asset_id)) > float(measurement.get("source_mtime", 0)) + 5.0:
			identity_stale.append(asset_id)
	check("PROPS", "individual building identity measurements match current models", identity_models.size() == 12 and identity_stale.is_empty(), str(identity_stale))
	var identity_checks: Dictionary = identity.get("checks", {})
	for feature: String in ["distinct_shop_heights", "home_separate_low_wing", "florist_real_glass_annex", "produce_has_real_volume", "different_tenant_cloth", "modern_four_hip_slopes"]:
		check("PROPS", "architectural identity: " + feature, bool(identity_checks.get(feature, false)), str(identity.get("metrics", {})))


func building_life_checks() -> void:
	var bakery_door := Vector3.INF
	for candidate in main.world.get_children():
		if candidate is Node3D and str(candidate.get_meta("model_id", "")) == "S02":
			var door_pane: Array = ShopWindows.WINDOWS["S02"][1]
			bakery_door = candidate.global_transform * Vector3((float(door_pane[0]) + float(door_pane[1])) * 0.5, 1.0, float(door_pane[4]))
	var bakery_point := point("bakery")
	check("PROPS", "bakery interaction aligns with the measured door pane", bakery_point != null and is_finite(bakery_door.x) and absf(bakery_point.global_position.x - bakery_door.x) < 0.12, "door %s / interaction %s" % [bakery_door, bakery_point.global_position if bakery_point != null else Vector3.INF])
	var cloth_ids: Array[String] = []
	var store_displays: Array[Node3D] = []
	var home_lamps: Array[StandardMaterial3D] = []
	for item: Dictionary in main.world.building_life:
		if item.id == "S01":
			store_displays.assign(item.displays)
		if item.id == "H01":
			home_lamps.assign(item.lamps)
	for building in main.world.get_children():
		if building is Node3D and int(building.get_meta("summer_cloth_surfaces", 0)) > 0:
			cloth_ids.append(str(building.get_meta("model_id", "")))
	check("PROPS", "summer cloth is active on the house, apartment and zakka", cloth_ids.has("H01") and cloth_ids.has("H02") and cloth_ids.has("S08"), str(cloth_ids))
	var old_day: int = GameState.day
	GameState.day = 4
	main.world.update_time(10.5 * 60.0, "sunny", true)
	var day_energy: float = home_lamps[0].emission_energy_multiplier if not home_lamps.is_empty() else -1.0
	var visible_day := 0
	for display_node in store_displays:
		if display_node.visible:
			visible_day += 1
	main.world.update_time(21.0 * 60.0, "sunny", true)
	var night_energy: float = home_lamps[0].emission_energy_multiplier if not home_lamps.is_empty() else -1.0
	var visible_night := 0
	for display_node in store_displays:
		if display_node.visible:
			visible_night += 1
	check("PROPS", "home porch and windows glow more at night", not home_lamps.is_empty() and night_energy > day_energy + 0.15, "%.3f -> %.3f" % [day_energy, night_energy])
	check("PROPS", "grocery brings exterior displays in after closing", store_displays.size() > 5 and visible_day == store_displays.size() and visible_night == 0, "%d nodes: %d -> %d" % [store_displays.size(), visible_day, visible_night])
	GameState.day = old_day
	main.world.update_time(GameState.minute, GameState.weather, true)


func material_checks() -> void:
	var missing: Array[String] = []
	for id: String in ["P_farm_gate", "P_signpost", "P_bridge", "P_yagura"]:
		var model := WorldBuilder.model_scene(id).instantiate()
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
			for surface in mesh.mesh.get_surface_count():
				var mat := mesh.get_active_material(surface) as StandardMaterial3D
				if mat == null:
					continue
				var label := mat.resource_name.to_lower()
				if label.begins_with("wood") or label.begins_with("roof"):
					var arrays: Array = mesh.mesh.surface_get_arrays(surface)
					var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
					if mat.albedo_texture == null or uv.is_empty():
						missing.append(id + ": " + label)
		model.free()
	check("TEXTURE", "procedural landmark wood and roofs have painted textures and UVs", missing.is_empty(), str(missing))
	var small: Array[String] = []
	for id: String in ["a", "b", "c"]:
		var tex := load("res://assets/textures/bg/bg_tree_%s.png" % id) as Texture2D
		if tex.get_width() < 1024 or tex.get_height() < 512:
			small.append("%s: %dx%d" % [id, tex.get_width(), tex.get_height()])
	check("TEXTURE", "forest sprites have enough pixels for wide scenery cards", small.is_empty(), str(small))
	var near: Array[String] = []
	var trees := 0
	for node in main.world.farm.get_children():
		if not node.has_meta("backdrop_tex") or not str(node.get_meta("backdrop_tex")).begins_with("bg_tree_"):
			continue
		trees += 1
		var position: Vector3 = node.position
		var dx := maxf(maxf(-30.0 - position.x, position.x - 28.0), 0.0)
		var dz := maxf(maxf(-16.0 - position.z, position.z - 31.0), 0.0)
		if Vector2(dx, dz).length() < 20.0:
			near.append("%.1f, %.1f" % [position.x, position.z])
	check("TEXTURE", "flat forest cards stay beyond close viewing range", trees >= 10 and near.is_empty(), str(near))
	var buried: Array[String] = []
	var titles := 0
	for title: Label3D in main.world.find_children("GateTitle_*", "Label3D", true, false):
		for gate: Node3D in PropAudit.instances(main.world):
			if str(gate.get_meta("model_id")) != "P_farm_gate":
				continue
			var local := gate.to_local(title.global_position)
			if Vector2(local.x, local.z).length() < 0.2:
				titles += 1
				if gate_letter_clearance(gate, title) < 0.01:
					buried.append(title.name)
	check("TEXTURE", "gate lettering sits outside the thick wooden name board", titles == 4 and buried.is_empty(), str(buried))


## Check the actual imported surface; a fixed offset cannot catch a changed roof/plaque.
func gate_letter_clearance(gate: Node3D, title: Label3D) -> float:
	var normal: Vector3 = title.global_basis.z.normalized()
	var origin: Vector3 = title.global_position + normal * 0.8
	var nearest := INF
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(gate):
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		for face_index in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(origin, -normal,
				mesh.global_transform * faces[face_index], mesh.global_transform * faces[face_index + 1], mesh.global_transform * faces[face_index + 2])
			if hit is Vector3:
				nearest = minf(nearest, origin.distance_to(hit as Vector3))
	return -1.0 if is_inf(nearest) else nearest - 0.8


## v0.7.3: raising an arm used to pull a sheet of shirt / apron / cardigan up with it, because the
## generated meshes weld the inner arm to the body. rig_char.py now cuts that seam. Pose every
## character at the wave's peak, skin the mesh on the CPU and measure how much edge length got
## stretched to over three times its rest length.
func _arm_cloth_checks() -> void:
	var bad: Array = []
	var worst := ""
	for f in DirAccess.get_files_at("res://assets/models"):
		if not (f.begins_with("CH_") and f.ends_with(".glb")):
			continue
		var n: Node3D = (load("res://assets/models/" + f) as PackedScene).instantiate()
		add_child(n)
		var ap := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var sk := n.find_child("Skeleton3D", true, false) as Skeleton3D
		var mi: MeshInstance3D = WorldBuilder.find_meshes(n)[0]
		ap.play("idle")
		ap.seek(0.0, true)
		var rest := _skinned(mi, sk)
		ap.play("wave")
		ap.seek(ap.current_animation_length * 0.35, true)
		var pose := _skinned(mi, sk)
		var h := 0.0
		for p in rest[0]:
			h = maxf(h, p.y)
		var stretched := 0.0
		var idx: PackedInt32Array = rest[1]
		var i := 0
		while i + 2 < idx.size():
			for k in 3:
				var a := idx[i + k]
				var b := idx[i + (k + 1) % 3]
				var l0: float = (rest[0][a] as Vector3).distance_to(rest[0][b])
				var l1: float = (pose[0][a] as Vector3).distance_to(pose[0][b])
				if l1 > 3.0 * l0 + 0.01 * h and l1 > 0.04 * h:
					stretched += (l1 - l0) * 0.5      # each edge is seen from both of its faces
			i += 3
		worst += "%s %.1f m  " % [f.get_basename(), stretched]
		if stretched > 12.0:
			bad.append(f.get_basename())
		n.queue_free()
	check("PROPS", "a raised arm does not drag the clothes up with it (wave, all characters)", bad.is_empty(), worst)


## [vertices, indices] of a skinned mesh in model space (Skeleton3D pose applied on the CPU).
func _skinned(mi: MeshInstance3D, sk: Skeleton3D) -> Array:
	var a: Array = mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / v.size()
	var skin := mi.skin
	var xf: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bi := skin.get_bind_bone(b)
		if bi < 0:
			bi = sk.find_bone(skin.get_bind_name(b))
		xf.append(sk.get_bone_global_pose(bi) * skin.get_bind_pose(b))
	var out := PackedVector3Array()
	out.resize(v.size())
	for i in v.size():
		var p := Vector3.ZERO
		for k in per:
			var w := weights[i * per + k]
			if w > 0.0:
				p += (xf[bones[i * per + k]] * v[i]) * w
		out[i] = p
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	return [out, idx]


func _portrait_holes(img: Image) -> int:
	var g := 128
	var step := img.get_width() / g
	var col: Array[Color] = []
	col.resize(g * g)
	for y in g:
		for x in g:
			col[y * g + x] = img.get_pixel(x * step + step / 2, y * step + step / 2)
	var lab := PackedInt32Array()
	lab.resize(g * g)
	var total := 0
	var next := 0
	for start in g * g:
		if col[start].a >= 0.5 or lab[start] != 0:
			continue
		next += 1
		var comp: Array[int] = [start]
		lab[start] = next
		var i := 0
		var touches := false
		var top := g
		while i < comp.size():
			var c := comp[i]
			i += 1
			var cx := c % g
			var cy := c / g
			top = mini(top, cy)
			if cx == 0 or cy == 0 or cx == g - 1 or cy == g - 1:
				touches = true
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = cx + d[0]
				var ny: int = cy + d[1]
				if nx < 0 or ny < 0 or nx >= g or ny >= g:
					continue
				var j := ny * g + nx
				if lab[j] == 0 and col[j].a < 0.5:
					lab[j] = next
					comp.append(j)
		if touches or top < int(g * 0.6):
			continue
		var lums: Array[float] = []
		for c in comp:
			for d in [[2, 0], [-2, 0], [0, 2], [0, -2]]:
				var nx: int = c % g + d[0]
				var ny: int = c / g + d[1]
				if nx < 0 or ny < 0 or nx >= g or ny >= g:
					continue
				var k: Color = col[ny * g + nx]
				if k.a >= 0.5:
					lums.append(k.r * 0.3 + k.g * 0.59 + k.b * 0.11)
		if lums.is_empty():
			continue
		lums.sort()
		if lums[lums.size() / 2] > 0.55:
			total += comp.size()
	return total


func storage_checks() -> void:
	var root := SaveDB.directory.path_join("checks_%d" % Time.get_ticks_usec())
	var store := GameSaveStore.new()
	store.set_directory(root)
	var current: Dictionary = G.to_dict().duplicate(true)
	current.coins = 11
	var old: Dictionary = current.duplicate(true)
	old.coins = 7
	var file := FileAccess.open(root.path_join("save.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(current))
	file.close()
	file = FileAccess.open(root.path_join("save.bak"), FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	file = FileAccess.open(root.path_join("settings.json"), FileAccess.WRITE)
	file.store_string('{"vol_music":0.31,"fullscreen":false}')
	file.close()
	var migrated := store.load_candidates()
	check("SQLITE", "legacy JSON progress migrates into SQLite", migrated.size() == 2 and int(migrated[0].data.coins) == 11)
	check("SQLITE", "legacy backup is retained as previous snapshot", migrated.size() == 2 and int(migrated[1].data.coins) == 7)
	check("SQLITE", "legacy settings migrate", is_equal_approx(float(store.load_settings().get("vol_music", 0)), 0.31))
	check("SQLITE", "legacy files remain untouched", FileAccess.get_file_as_string(root.path_join("save.json")) == JSON.stringify(current))
	file = FileAccess.open(store.database_path, FileAccess.READ)
	check("SQLITE", "save file has the real SQLite format header", file.get_buffer(15).get_string_from_ascii() == "SQLite format 3")
	file.close()
	file = FileAccess.open(root.path_join("save.json"), FileAccess.WRITE)
	var stale: Dictionary = current.duplicate(true)
	stale.coins = 999
	file.store_string(JSON.stringify(stale))
	file.close()
	check("SQLITE", "migration runs once and cannot overwrite newer progress", int(store.load_candidates()[0].data.coins) == 11)
	current.coins = 12
	var first_write := store.save_snapshot(current)
	current.coins = 13
	var second_write := store.save_snapshot(current)
	var reopened := GameSaveStore.new()
	reopened.set_directory(root)
	var readback := reopened.load_candidates()
	check("SQLITE", "committed progress survives a new connection", first_write and second_write and int(readback[0].data.coins) == 13)
	check("SQLITE", "snapshot transaction preserves the immediately previous save", readback.size() == 2 and int(readback[1].data.coins) == 12)
	var quote := "晴町'; DROP TABLE snapshots; --"
	check("SQLITE", "settings bindings preserve quotes and Unicode", store.save_settings({"name": quote, "vol_music": 0.47}) and str(store.load_settings().get("name", "")) == quote)
	check("SQLITE", "settings writes preserve game progress", int(store.load_candidates()[0].data.coins) == 13)
	var sql := SQLite.new()
	sql.path = store.database_path
	sql.verbosity_level = 0
	sql.open_db()
	sql.query("UPDATE snapshots SET payload='{}' WHERE slot='current'")
	sql.close_db()
	var checked := store.load_candidates()
	check("SQLITE", "checksum damage falls back to previous snapshot", checked.size() == 1 and int(checked[0].data.coins) == 12)
	file = FileAccess.open(store.database_path, FileAccess.WRITE)
	file.store_string("broken database")
	file.close()
	checked = store.load_candidates()
	check("SQLITE", "physical database corruption recovers the consistent backup", not checked.is_empty() and int(checked[0].data.coins) == 12 and store.recovered_database)
	check("SQLITE", "invalid state cannot replace a valid save", not store.save_snapshot({}) and int(store.load_candidates()[0].data.coins) == 12)
	var future := GameSaveStore.new()
	future.set_directory(root.path_join("future"))
	future.save_snapshot(current)
	sql.path = future.database_path
	sql.open_db()
	sql.query("UPDATE metadata SET value='2' WHERE key='schema_version'")
	sql.close_db()
	check("SQLITE", "future database schemas are rejected without restoring over them", future.load_candidates().is_empty() and future.error_message == "存档数据库版本不兼容")
	store.free()
	reopened.free()
	future.free()


func loading_checks() -> void:
	var prior: bool = G.clock_paused
	Loading.begin("准备晴町")
	check("LOADING", "loading overlay is visible and prevents accidental input", Loading.root.visible and G.input_locked())
	var viewport_size: Vector2 = Loading.get_viewport().get_visible_rect().size
	check("LOADING", "loading covers the viewport and centres its feedback", Loading.root.size.is_equal_approx(viewport_size) and Loading.box.get_rect().get_center().distance_to(viewport_size / 2.0) < 1.0)
	Loading.progress("准备街景", 0.42)
	check("LOADING", "loading progress reflects completed work", Loading.bar.visible and is_equal_approx(Loading.bar.value, 42.0))
	Loading.finish()
	check("LOADING", "loading ends without leaving input or clock stuck", not Loading.root.visible and not G.input_locked() and G.clock_paused == prior)
	check("LOADING", "main scene becomes playable only after construction", main.loading_ready and not main.world.build_steps().is_empty())

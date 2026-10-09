extends RefCounted
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(name: String, passed: bool, detail: String = "") -> void:
	t.check("HOMAGE", name, passed, detail)

func run() -> void:
	var snapshot: Dictionary = GameState.to_dict().duplicate(true)
	var position_before: Vector3 = main.player.global_position
	var region_before: String = main.world.region
	GameState.new_game()
	GameState.clock_paused = true
	check("four optional discoveries have usable images and the retired box is absent", Homage.entries().size() == 4 and Homage.definition("egg_star_box").is_empty() and t.point("egg_star_box")==null and Homage.entries().all(func(entry: Dictionary): return t.point(str(entry.id)) != null and ResourceLoader.exists(Homage.image_path(entry))))
	check("legacy town history and achievements retain their original counts", Progress.col_db.size() == 13 and Progress.ach_db.size() == 32 and Homage.count() == 0)
	var initial_coins: int = GameState.coins
	check("unknown discovery and invalid offerings cannot mutate progress", not Homage.discover("egg_missing") and not Homage.donate("egg_missing", "radish") and not Homage.donate("egg_star_box", "fish_carp") and Homage.state().is_empty())
	# Keep the generic multi-slot donation rules covered using a test-only definition.
	var live_entries: Array=Homage.entries().duplicate(true)
	Homage._entries.append({"id":"test_bundle","requires":["radish","tomato","cucumber"]})
	check("required offerings cannot be bypassed by reading the box", not Homage.discover("test_bundle") and not Homage.found("test_bundle"))
	check("missing crop is not consumed and leaves the slot empty", not Homage.donate("test_bundle", "radish") and Homage.paid("test_bundle").is_empty())
	GameState.inventory = {"radish": 2, "tomato": 1, "cucumber": 1}
	var repeated: Array = []
	var callback := func(): repeated.append(Homage.donate("test_bundle", "radish"))
	GameState.inventory_changed.connect(callback)
	var accepted := Homage.donate("test_bundle", "radish")
	GameState.inventory_changed.disconnect(callback)
	check("one donation consumes one crop and rejects reentrant callbacks", accepted and GameState.count("radish") == 1 and not repeated.has(true))
	check("the same slot never consumes a second copy", not Homage.donate("test_bundle", "radish") and GameState.count("radish") == 1)
	check("partial contributions survive a save-data round trip", Homage.paid("test_bundle") == ["radish"] and not Homage.found("test_bundle"))
	var partial: Dictionary = GameState.to_dict().duplicate(true)
	GameState.new_game(); GameState.from_dict(partial)
	check("restored box still only asks for the two missing crops", Homage.remaining("test_bundle") == ["tomato", "cucumber"])
	check("second crop does not prematurely complete the bundle", Homage.donate("test_bundle", "tomato") and not Homage.found("test_bundle"))
	check("third crop completes the entry exactly once", Homage.donate("test_bundle", "cucumber") and Homage.found("test_bundle") and not Homage.donate("test_bundle", "cucumber"))
	GameState.inventory = {"radish": 1}
	check("tree hollow accepts one radish and records its letter", Homage.donate("egg_sprite_caps", "radish") and Homage.found("egg_sprite_caps") and GameState.count("radish") == 0)
	Homage._entries=live_entries
	GameState.inventory = {"washi": GameState.STACK_MAX * GameState.bag_cap}
	check("free discoveries work with a full bag and do not add inventory slots", Homage.discover("egg_blue_feather") and Homage.discover("egg_cow_bell") and Homage.discover("egg_purple_shorts") and Homage.count() == 4 and GameState.slots_used() == GameState.bag_cap)
	check("repeat reading awards neither currency nor duplicate entries", not Homage.discover("egg_blue_feather") and Homage.count() == 4 and GameState.coins == initial_coins)
	check("optional discoveries do not unlock town-history achievements", GameState.collection.is_empty() and not Progress.holds("memories>=6") and not Progress.holds("memories>=13"))
	GameState.save_game()
	GameState.flags.erase(Homage.STATE_KEY)
	GameState.load_game()
	check("actual SQLite save keeps four discoveries and paid slots", Homage.count() == 4 and Homage.paid("egg_sprite_caps")==["radish"])
	var legacy: Dictionary = GameState.to_dict().duplicate(true)
	legacy.flags.erase(Homage.STATE_KEY)
	GameState.from_dict(legacy)
	check("an old v4 save without homage flags loads as zero discoveries", Homage.count() == 0 and Homage.state().is_empty())
	GameState.flags[Homage.STATE_KEY] = {"egg_star_box":{"paid":["radish"],"found_day":1},"egg_sprite_caps": {"paid": ["invalid", "radish", "radish"]}, "egg_blue_feather": 9}
	check("malformed and retired optional records are ignored safely", not Homage.found("egg_blue_feather") and not Homage.found("egg_star_box") and Homage.paid("egg_sprite_caps") == ["radish"])
	GameState.flags.erase(Homage.STATE_KEY)
	var sprites: Array[Node] = []
	for root: Node in [main.world.get_node("Homage_town"), main.world.farm.get_node("Homage_farm")]:
		for child: Node in root.get_children():
			if child is HomageDisplay:
				sprites.append(child)
	check("four world illustrations have genuine transparent backgrounds", sprites.size() == 4 and sprites.all(func(node: Node): return node is HomageDisplay and (node as HomageDisplay).texture.get_image().get_pixel(0, 0).a == 0))
	var box_display: HomageDisplay = main.world.farm.get_node("Homage_farm/Keepsake_egg_sprite_caps")
	GameState.state_changed.emit()
	check("tree hollow uses its actual empty artwork before the offering", box_display.texture.resource_path.ends_with("sprite_caps_empty.png"))
	GameState.inventory = {"radish": 1, "tomato": 1, "cucumber": 1}
	Homage.donate("egg_sprite_caps","radish")
	check("completed offering changes the tree hollow illustration", box_display.texture.resource_path.ends_with("sprite_caps.png"))
	GameState.flags.erase(Homage.STATE_KEY)
	GameState.state_changed.emit()
	for entry: Dictionary in Homage.entries():
		main.world.set_region(str(entry.region))
		var at: Vector3 = Homage.world_position(entry, true)
		main.player.global_position = at + Vector3(0, .15, 0)
		main.player.velocity = Vector3.ZERO
		var target: Interactable = t.point(str(entry.id))
		main.player.face_towards(target.global_position)
		await t.frames(12)
		check("reachable world interaction: " + str(entry.id), main.player.target != null and main.player.target.id == str(entry.id), str(main.player.target.id) if main.player.target != null else "no target")
	main.ui.instant = true
	GameState.inventory = {"radish": 1}
	main.ui.auto_choices = [1]
	await main.story.interact(t.point("egg_sprite_caps"))
	check("cancel through the actual dialogue leaves crops and slots untouched", GameState.count("radish") == 1 and Homage.paid("egg_sprite_caps").is_empty() and not main.story.busy and not main.player.frozen)
	main.ui.auto_choices = [0]
	await main.story.interact(t.point("egg_sprite_caps"))
	check("actual dialogue dispatch records the tree hollow offering", GameState.count("radish") == 0 and Homage.paid("egg_sprite_caps") == ["radish"])
	await main.story.interact(t.point("egg_blue_feather"))
	main.ui.book.open("homage")
	await t.frames(4)
	check("K book opens the separate discoveries tab and shows current count", main.ui.modal == "book" and main.ui.book._count.text == "小记 2 / 4" and main.ui.book._body.get_child_count() > 0)
	main.ui.close_modal()
	GameState.from_dict(snapshot)
	main.player.global_position = position_before
	main.world.set_region(region_before)

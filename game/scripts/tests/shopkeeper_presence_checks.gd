extends RefCounted
## A shopkeeper has one workplace even while the player is on the street.
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("SHOPKEEPER_PRESENCE", label, ok, detail)

func _at_counter(kind: String) -> bool:
	var who: String = "ren" if kind == "bakery" else "kazuko"
	var spec: Dictionary = InteriorBuilder.spec_for(kind)
	return main.npcs[who].global_position.distance_to(spec.origin + spec.keeper) < .08

func _ordinary_morning() -> void:
	GameState.day = 1
	GameState.minute = 10.0 * 60.0
	GameState.phase = "prep"
	GameState.weather = "sunny"
	GameState.clock_paused = true
	main.world.set_region("town")
	main.update_npcs(true)

func run() -> void:
	var snapshot: Dictionary = GameState.to_dict().duplicate(true)
	var roam_was: bool = NPC.roam_enabled
	NPC.roam_enabled = false
	if main.in_room: await main.exit_room()
	_ordinary_morning()
	for kind: String in ["store", "bakery"]:
		var who: String = "ren" if kind == "bakery" else "kazuko"
		var actor: NPC = main.npcs[who]
		var instance_id: int = actor.get_instance_id()
		var initial_at: Vector3 = actor.global_position
		var spec: Dictionary = InteriorBuilder.spec_for(kind)
		check("%s works inside before the player enters" % who, _at_counter(kind), str(initial_at))
		check("%s has no street body or name tag beside the shop" % who, actor.global_position.distance_to(spec.exit) > 100.0 and not actor.visible and actor.talk.radius == 0.0 and actor.body.collision_layer == 0)
		var door_id: String = "bakery" if kind == "bakery" else "shop_store"
		var door_at: Vector3 = main.story.physical_point(door_id)
		var marker: Variant = main.story._npc_head(who)
		check("%s quest marker leads to the real shop entrance" % who, marker is Vector3 and Vector2(marker.x, marker.z).distance_to(Vector2(door_at.x, door_at.z)) < .05, str(marker))
		await main.enter_interior(kind)
		await t.frames(3)
		check("entering %s does not move its keeper between two locations" % kind, actor.global_position.distance_to(initial_at) < .08 and actor.get_instance_id() == instance_id)
		check("%s remains visible and reachable inside" % who, _at_counter(kind) and actor.visible and actor.talk.radius > 2.0 and actor.body.collision_layer == WorldBuilder.L_ACTORS)
		var inside_at: Vector3 = actor.global_position
		await main.exit_interior()
		await t.frames(3)
		check("leaving %s does not put its keeper back on the street" % kind, actor.global_position.distance_to(inside_at) < .08 and actor.get_instance_id() == instance_id, str(actor.global_position))
		var matching: int = 0
		for candidate: Node in main.get_children():
			if candidate is NPC and candidate.npc_id == who: matching += 1
		check("%s still has exactly one actor instance" % who, matching == 1)
	# The same position must be reconstructed when loading outdoors or indoors.
	GameState.has_player_pos = true
	GameState.player_pos = Vector3(-34.0, .1, -11.0)
	GameState.player_in_room = false
	GameState.player_region = "town"
	main._restore()
	check("outdoor load restores both keepers to their workplaces", _at_counter("store") and _at_counter("bakery"))
	GameState.player_in_room = true
	GameState.player_pos = InteriorBuilder.door_point("store")
	main._restore()
	check("indoor load does not create a second workplace", _at_counter("store") and _at_counter("bakery"))
	await main.exit_interior()
	# A festival assignment belongs to the NPC, not to whichever room is being viewed.
	GameState.day = 11
	GameState.minute = 11.0 * 60.0
	main.update_npcs(true)
	var festival_at: Vector3 = main.npcs.ren.global_position
	check("Ren attends the cooking contest", main.npcs.ren.fest_key == "contest" and not _at_counter("bakery"))
	await main.enter_interior("bakery")
	check("entering the bakery does not summon Ren out of the contest", main.npcs.ren.fest_key == "contest" and main.npcs.ren.global_position.distance_to(festival_at) < .08)
	var greeting_before: int = main.shop_life.greeting_count
	main.shop_life.last_greeting.bakery = -999.0
	Audio.stop_voice()
	var welcomed: bool = main.shop_life.greet("bakery", true)
	check("an absent keeper cannot greet from the empty bakery", not welcomed and main.shop_life.greeting_count == greeting_before)
	check("the empty bakery counter does not advertise a present keeper", main.story.prompt_for("bakery_counter") == "看看空着的柜台")
	var introduced_before: bool = GameState.flags.get("bakery_inside", false)
	var empty_counter: Interactable
	for candidate: Node in main.get_tree().get_nodes_in_group("interactables"):
		if candidate.id == "bakery_counter": empty_counter = candidate
	await main.story.interact(empty_counter)
	check("an empty counter cannot trigger Ren's introduction or shop", GameState.flags.get("bakery_inside", false) == introduced_before and main.ui.modal == "" and not main.story.busy)
	await main.exit_interior()
	GameState.day = 4
	GameState.minute = 12.5 * 60.0
	main.update_npcs(true)
	check("Ren's Sunday errand remains outside during shop hours", not _at_counter("bakery") and main.npcs.ren.global_position.distance_to(Vector3(-3.8,0,21.2)) < .08)
	await main.enter_interior("bakery")
	check("visiting during an errand does not summon the keeper", not _at_counter("bakery"))
	await main.exit_interior()
	GameState.day = 7
	GameState.minute = 10.0 * 60.0
	main.update_npcs(true)
	check("Kazuko's weekly closed day does not place her at the counter", not _at_counter("store") and main.npcs.kazuko.global_position.z < 100.0)
	_ordinary_morning()
	GameState.minute = 18.5 * 60.0
	main.update_npcs(true)
	check("closing the bakery returns Ren to his evening routine", not _at_counter("bakery") and main.npcs.ren.fest_key == "" and main.npcs.ren.global_position.z < 100.0)
	GameState.minute = 20.0 * 60.0
	main.update_npcs(true)
	check("Kazuko goes home after closing", main.npcs.kazuko.home and not main.npcs.kazuko.visible and main.npcs.kazuko.talk.radius == 0.0)
	_ordinary_morning()
	GameState.phase = "market"
	main.to_market_positions(false)
	main._sync_roams()
	check("the market releases both workplace roles and restores their visible actors", main.npcs.ren.fest_key == "" and main.npcs.kazuko.fest_key == "" and main.npcs.ren.visible and main.npcs.kazuko.visible and not _at_counter("store") and not _at_counter("bakery"))
	await main.enter_interior("store")
	check("entering the store does not call Kazuko back from the market", main.npcs.kazuko.global_position.distance_to(Layout.NPC.kazuko.market) < .08 and not main.shopkeeper_present("store"))
	await main.exit_interior()
	# Existing invited private visits retain their explicit owner placement.
	_ordinary_morning()
	GameState.minute = 16.5 * 60.0
	await main.enter_interior("home_ren")
	check("the invited back-room visit still uses the single Ren actor", InteriorBuilder.at(main.npcs.ren.global_position) == "home_ren")
	await main.exit_interior()
	check("returning from the back room restores the working counter", main.room_kind == "bakery" and _at_counter("bakery"))
	await main.exit_interior()
	# Run the real collision path planner from the street into each workplace,
	# then through the normal dialogue/shop interactions.
	_ordinary_morning()
	main.player.global_position = Vector3(-28.0,.1,-11.0)
	main.player.velocity = Vector3.ZERO
	var driver: RefCounted = SummerAutoplay.new(t)
	var reached_ren: bool = await driver.use("ren",[1])
	check("Ren's actual dialogue is reachable through the real shop door", reached_ren and main.in_room and main.room_kind == "bakery" and GameState.flags.get("met_ren",false))
	GameState.coins = 1000
	var seeds_before: int = GameState.count("seed_radish")
	var coin_before: int = GameState.coins
	var reached_kazuko: bool = await driver.use("store_counter",[{"buy":{"seed_radish":1}}])
	check("the other shop stays reachable and its counter still sells", reached_kazuko and main.in_room and main.room_kind == "store" and GameState.flags.get("met_kazuko",false) and GameState.count("seed_radish") == seeds_before + 1 and GameState.coins < coin_before)
	await main.exit_interior()
	GameState.from_dict(snapshot)
	main._restore()
	NPC.roam_enabled = roam_was

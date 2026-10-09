extends RefCounted
## Exercises the same doors, oven, paper sign, neighbours and stall as normal play.
var t: Node
var G: Node
var main: Node


func _init(runner: Node) -> void:
	t = runner
	G = GameState
	main = t.main


func run() -> void:
	var original: Dictionary = G.to_dict().duplicate(true)
	if main.in_room:
		main.exit_interior() if main.room_kind != "house" else main.exit_room()
		await t.frames(20)
	main.world.set_region("town")
	G.new_game()
	G.clock_paused = true
	G.day = 4
	G.minute = 10.0 * 60.0
	G.quests["Q05"] = {"state": "done", "step": 5}
	G.quests["Q06"] = {"state": "done", "step": 5}
	main.story.bakery.checks()
	main.update_npcs(true)
	t.check("BAKERY", "the partnership opens after the market and allotment", G.qstate("Q16") == "available" and t.point("bakery_orders") != null)
	await t.shop_in("bakery", "bakery_orders", [1])
	t.check("BAKERY", "declining leaves the invitation and money intact", G.qstate("Q16") == "available" and G.coins == G.START_COINS and G.inventory.is_empty())
	G.bag_cap = 0
	await t.shop_in("bakery", "bakery_orders", [0])
	t.check("BAKERY", "a full bag does not lose any of the one-time kit", G.at_step("Q16", "bakery_bake") and not G.flags.get("bakery_kit_claimed", false) and G.inventory.is_empty())
	t.check("BAKERY", "trial recipe is available without buying the card", G.recipe_known("veg_sandwich") and G.coins == G.START_COINS)
	G.bag_cap = G.INV_SLOTS
	await t.shop_in("bakery", "bakery_orders")
	t.check("BAKERY", "collecting later gives exactly one complete kit", G.count("tomato") == 2 and G.count("cucumber") == 1 and G.count("flour") == 1 and G.count("butter") == 1 and not G.bakery_claim_kit())
	t.check("BAKERY", "trial materials cannot be accidentally sold or gifted", G.sell_produce("tomato", 2, 1.0) == 0 and G.give_gift("mio", "tomato") == 0 and G.count("tomato") == 2)
	await t.shop_in("bakery", "bakery_oven", [{"craft": {"veg_sandwich": 1}}])
	t.check("BAKERY", "the real oven advances only after baking the trial", G.at_step("Q16", "bakery_trial") and G.has("veg_sandwich") and not G.has("tomato"))
	t.check("BAKERY", "the baked trial is protected until it reaches Ren", G.sell_produce("veg_sandwich", 1, 1.0) == 0)
	await t.shop_in("bakery", "bakery_orders")
	t.check("BAKERY", "Ren cuts the trial into unsellable tasting portions", G.at_step("Q16", "bakery_taste") and G.count("bakery_sample") == 3 and not G.has("veg_sandwich") and G.is_key_item("bakery_sample"))
	await t.use("mio")
	var samples: int = G.count("bakery_sample")
	t.check("BAKERY", "a repeated taster cannot consume a second portion", not G.bakery_taste("mio") and G.count("bakery_sample") == samples)
	await t.shop_in("shop_store", "store_counter", [], 0.55)
	t.check("BAKERY", "two different residents suffice, including Kazuko's counter", G.at_step("Q16", "bakery_menu") and G.flags.bakery_tasters.size() == 2 and G.flags.bakery_tasters.has("kazuko"))
	await t.shop_in("bakery", "bakery_orders", [1])
	t.check("BAKERY", "menu choice opens a small Saturday order", G.at_step("Q16", "bakery_supply") and int(G.flags.bakery_menu) == 1 and int(G.flags.bakery_due_day) == 10 and G.flags.bakery_order_active)
	G.add_item("tomato", 4, true)
	G.add_item("cucumber", 2, true)
	var before: int = G.coins
	await t.shop_in("shop_store", "store_counter", [{"sell": {"tomato": -1, "cucumber": -1}}], 0.55)
	t.check("BAKERY", "shop sell-all keeps the promised quantities", G.count("tomato") == 2 and G.count("cucumber") == 1 and G.coins > before)
	t.check("BAKERY", "other recipes respect the same reservation", G.craft_block("pickles").contains("预留") and G.craft_max("pickles") == 0)
	var saved: Dictionary = G.to_dict().duplicate(true)
	G.save_game()
	G.flags.clear()
	G.load_game()
	t.check("BAKERY", "SQLite restores menu, tasters, due day and reservations", int(G.flags.bakery_menu) == 1 and G.flags.bakery_tasters.size() == 2 and int(G.flags.bakery_due_day) == 10 and G.unreserved_count("tomato") == 0)
	G.clock_paused = false
	main.ui.instant = false
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		t.get_window().size = size
		main.ui.panels.open_bakery_order()
		await t.frames(8)
		var panel: Control = main.ui.modal_layer.get_child(0)
		t.check("BAKERY_UI", "order fits %dx%d and freezes the clock" % [size.x, size.y], Rect2(Vector2.ZERO, main.ui.root.size).grow(2).encloses(panel.get_global_rect()) and not G.time_running())
		main.ui.close_modal()
		await t.frames(2)
	main.ui.instant = true
	G.clock_paused = true
	G.from_dict(saved)
	G.minute = 18.0 * 60.0
	G.phase = "market"
	before = G.coins
	t.check("BAKERY", "delivery outside the booked Saturday pays nothing", G.bakery_deliver() != "" and G.coins == before and G.count("tomato") == 2)
	G.day = 10
	G.inventory.erase("cucumber")
	t.check("BAKERY", "missing produce cannot partially debit the delivery", G.bakery_deliver() != "" and G.count("tomato") == 2 and G.coins == before)
	G.add_item("cucumber", 1, true)
	main.update_npcs(true)
	var expected: int = G.sale_value("tomato", 2, G.MARKET_RATE) + G.sale_value("cucumber", 1, G.MARKET_RATE)
	await t.use("stall", [0])
	t.check("BAKERY", "actual stall delivery consumes and pays once", G.at_step("Q16", "bakery_followup") and not G.has("tomato") and not G.has("cucumber") and G.coins == before + expected and int(G.flags.bakery_supplies) == 1)
	before = G.coins
	t.check("BAKERY", "repeated delivery cannot pay twice", G.bakery_deliver() != "" and G.coins == before)
	await t.use("ren")
	t.check("BAKERY", "follow-up waits until the next day", G.at_step("Q16", "bakery_followup"))
	G.day = 11
	G.minute = 10.0 * 60.0
	G.phase = "prep"
	main.update_npcs(true)
	await t.shop_in("bakery", "bakery_orders", [1])
	t.check("BAKERY", "a rest week completes the story without compulsory work", G.qstate("Q16") == "done" and not G.flags.bakery_order_active and G.flags.bakery_supplied_first)
	G.flags["bakery_menu"] = 0
	G.state_changed.emit()
	t.check("BAKERY", "old-menu choice changes both persistent signs", main.world.interiors.bakery.bakery_sign.text.begins_with("菠萝包") and main.world.bakery_market_sign.text.begins_with("菠萝包"))
	G.flags["bakery_menu"] = 1
	G.state_changed.emit()
	t.check("BAKERY", "new-menu choice changes both persistent signs", main.world.interiors.bakery.bakery_sign.text.begins_with("街坊三明治") and main.world.bakery_market_sign.text.begins_with("街坊三明治"))
	G.bakery_accept_order()
	await t.shop_in("bakery", "bakery_orders", [1])
	t.check("BAKERY", "rescheduling moves the due date without deducting coins", int(G.flags.bakery_due_day) == 24 and G.coins == before)
	await t.shop_in("bakery", "bakery_orders", [2])
	t.check("BAKERY", "cancelling releases the reservation", not G.flags.bakery_order_active and G.reserved_count("tomato") == 0)
	# An existing active first order can also finish with Ren's ingredients.
	G.quests["Q16"] = {"state": "active", "step": 4}
	G.flags["bakery_due_day"] = 17
	G.day = 17
	G.minute = 18.0 * 60.0
	G.phase = "market"
	main.update_npcs(true)
	await t.use("stall", [1])
	t.check("BAKERY", "shop-stock alternative advances honestly and pays no produce reward", G.at_step("Q16", "bakery_followup") and not G.flags.bakery_supplied_first and G.coins == before)
	for day in [18, 25, 76]:
		G.new_game()
		G.clock_paused = true
		G.day = day
		G.minute = 10.0 * 60.0
		G.quests["Q05"] = {"state": "done", "step": 5}
		main.world.set_region("town")
		main.story.lore.checks()
		main.update_npcs(true)
		await t.use("mio", [0, 0, 0, 1])
		t.check("NARR_LATE", "missed summer at day %d can reach a new photo" % day, G.qstate("Q14") == "done" and G.flags.get("summer_reunion", false) and not G.flags.get("fest_bon_odori", false) and not G.flags.get("summer_attended", false) and FileAccess.file_exists(G.photo_path()))
		t.check("NARR_CHOICE", "returning later is accepted and remembered at day %d" % day, int(G.flags.get("summer_promise", -1)) == 1 and Dialogue.matches(_entry("promise_return"), {}) and not Dialogue.matches(_entry("promise_next"), {}))
	G.day = 77
	G.quests["Q15"] = {"state": "active", "step": 1}
	G.quests["Q06"] = {"state": "done", "step": 5}
	G.flags["met_tanaka"] = true
	main.world.set_region("farm")
	main.update_npcs(true)
	await t.use("farm_bench")
	t.check("NARR_LATE", "late riverside scene completes without pretending the player watched fireworks", G.qstate("Q15") == "done" and G.flags.get("hanabi_revisit", false) and not G.flags.get("fest_hanabi", false))
	var legacy: Dictionary = saved.duplicate(true)
	legacy.quests.erase("Q16")
	for key in legacy.flags.keys():
		if str(key).begins_with("bakery_"):
			legacy.flags.erase(key)
	G.from_dict(legacy)
	main.story.bakery.checks()
	t.check("BAKERY_SAVE", "old v4 saves get an available invitation without inventing participation", G.qstate("Q16") == "available" and not G.flags.get("bakery_first_served", false))
	G.recipes_known.erase("veg_sandwich")
	G.start_quest("Q16")
	t.check("BAKERY_SAVE", "accepting from the quest journal also teaches the trial recipe", G.recipe_known("veg_sandwich") and not G.flags.get("bakery_kit_claimed", false))
	t.check("NARR_SAVE", "review photos share the isolated database directory", G.photo_path().get_base_dir() == SaveDB.database_path.get_base_dir())
	G.from_dict(original)
	main.world.set_region(G.player_region)
	main.update_npcs(true)
	main._sync_props()


func _entry(id: String) -> Dictionary:
	for entry in Dialogue.entries:
		if str(entry.id) == id:
			return entry
	return {}

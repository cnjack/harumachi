extends RefCounted
var t: Node
var G: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	G = GameState
	main = t.main

func _text(node: Node) -> String:
	var result := str(node.text) + "\n" if node is Label or node is Button else ""
	for child in node.get_children(): result += _text(child)
	return result

func run() -> void:
	var original: Dictionary = G.to_dict().duplicate(true)
	G.new_game()
	G.clock_paused = true
	G.record_minigame("puzzle", 300, 1)
	t.check("SUM_A06", "a partial map with one star cannot hang a completed map", not G.flags.get("map_framed", false))
	G.record_minigame("goldfish", 200, 1)
	t.check("SUM_A06", "points without a captured fish cannot bring a fish home", not G.flags.get("goldfish_home", false))
	G.record_minigame("taiko", 900, 3)
	var story_source := FileAccess.get_file_as_string("res://scripts/story/story.gd")
	t.check("SUM_A06", "a past taiko score never invents a current audience", not story_source.contains("刚才在小舞台打太鼓的是你"))
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prologue.json"))
	t.check("SUM_A08", "arrival starts with four present-day panels", opening.panels.size() == 4)
	t.check("SUM_A04", "home rice prompt is an object before an activity", not main.story.prompt_for("house_rice").contains("小游戏"))
	t.check("SUM_A04", "map prompt begins with the map on the desk", not main.story.prompt_for("room_desk").contains("小游戏"))
	main.ui.open_book_col()
	await t.frames(2)
	# Visit an unknown tile; its hint must not expose the future quest name.
	for button in main.ui.modal_layer.find_children("*", "Button", true, false):
		if button.text == "？": button.mouse_entered.emit()
	var unknown := _text(main.ui.modal_layer)
	t.check("SUM_A08", "unknown keepsakes do not publish future where clues", not unknown.contains("线索："))
	main.ui.close_modal(false)
	main.ui.open_minigame_records()
	await t.frames(2)
	var records := _text(main.ui.modal_layer)
	t.check("SUM_A10", "records omit games not encountered or played", not records.contains("捏饭团"))
	main.ui.close_modal(false)
	G.quests["Q00"] = {"state": "done", "step": 2}
	G.day = 25
	main.ui.open_book("notes")
	await t.frames(2)
	t.check("SUM_E03", "an old settled save is not described as just arriving", not _text(main.ui.modal_layer).contains("刚到晴町"))
	main.ui.close_modal(false)
	var lore_source := FileAccess.get_file_as_string("res://scripts/story/story_lore.gd")
	t.check("SUM_A08", "printed photo names agree with Sora's knowledge", not lore_source.contains("女孩是谁来着"))
	var summer_rules: Script = load("res://scripts/story/mainline_progress.gd") if ResourceLoader.exists("res://scripts/story/mainline_progress.gd") else null
	t.check("SUM_A01", "chapter and summer completion have separate persisted identities", summer_rules != null)
	if summer_rules != null:
		G.flags["ended"] = true
		G.quests["Q15"] = {"state": "locked", "step": 0}
		t.check("SUM_A01", "legacy ended does not migrate to completed summer", not summer_rules.summer_complete())
		G.quests["Q15"] = {"state": "done", "step": 2}
		t.check("SUM_E03", "a legacy completed Q15 remains completed", summer_rules.summer_complete())
	G.flags.erase("map_framed")
	G.record_minigame("puzzle", 0, 0, {"started": true, "solved": true})
	t.check("SUM_A06", "a solved low-score map is still a real completed work", G.flags.get("map_framed", false))
	G.record_minigame("goldfish", 0, 0, {"started": true, "caught": 1})
	t.check("SUM_A06", "a real low-score catch is independent of stars", G.flags.get("goldfish_home", false))
	G.save_game()
	G.minigames.clear()
	G.load_game()
	t.check("SUM_E03", "SQLite retains actual outcomes and the recorded day", G.mg_record("puzzle").get("outcome", {}).get("solved", false) and int(G.mg_record("goldfish").get("outcome", {}).get("caught", 0)) == 1 and int(G.mg_record("goldfish").get("last_day", -1)) == G.day)
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	if not main.in_room: await main.enter_room()
	DailyLife.claim_meal()
	main.ui.instant = false
	main.ui.panels.open_craft("kitchen")
	await t.frames(3)
	var kitchen_text := _text(main.ui.modal_layer)
	t.check("SUM_A11", "the guided stove entrance offers shaping and accurately labelled two portions", kitchen_text.contains("亲手捏形") and kitchen_text.contains("做 1 批 · 2 份"))
	main.ui.close_modal(false)
	main.ui.instant = true
	var before_coins: int = G.coins
	await t.use("house_rice", [0])
	t.check("SUM_A02", "guided shaping consumes one parcel and produces two real portions", G.count("onigiri") == 2 and G.count("home_meal_parcel") == 0 and DailyLife.event("meal").get("method", "") == "shaped")
	t.check("SUM_A03", "guided shaping never pays practice coins or free-game food", G.coins == before_coins and int(G.mg_record("onigiri").plays) == 0)
	await t.use("house_rice")
	t.check("SUM_A02", "reentering the prepared batch does not make extra portions", G.count("onigiri") == 2)
	G.save_game()
	G.flags.clear()
	G.load_game()
	await t.use("house_rice")
	t.check("SUM_A02", "loading after commit does not duplicate or debit the meal", G.count("onigiri") == 2 and G.count("home_meal_parcel") == 0)
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	DailyLife.claim_meal()
	await t.use("house_rice", [2])
	t.check("SUM_A02", "deferring the shape choice leaves the actual parcel untouched", G.count("home_meal_parcel") == 1 and G.count("onigiri") == 0)
	await t.use("house_rice", [1])
	t.check("SUM_A02", "the simple route makes the identical meal through the same craft authority", G.count("onigiri") == 2 and DailyLife.event("meal").get("method", "") == "simple")
	DailyLife.finish_meal(1)
	var before_food: int = G.count("onigiri")
	await t.use("house_rice")
	t.check("SUM_A03", "later free practice is a separate recorded round", int(G.mg_record("onigiri").plays) == 1 and G.count("onigiri") > before_food and DailyLife.done("meal"))
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	DailyLife.claim_meal()
	G.bag_cap = 0
	await t.use("house_rice", [0])
	t.check("SUM_A02", "a completed short shape with a full bag cannot consume the parcel", G.count("home_meal_parcel") == 1 and not DailyLife.event("meal").get("cooked", false))
	G.bag_cap = G.INV_SLOTS
	await t.use("house_rice", [1])
	t.check("SUM_A02", "retry after a full bag makes exactly the original batch", G.count("home_meal_parcel") == 0 and G.count("onigiri") == 2)
	var game: MiniGame = load("res://scripts/minigames/mg_goldfish.gd").new()
	game.id = "goldfish"
	main.ui.root.add_child(game)
	await t.frames(1)
	game._leave()
	t.check("SUM_A07", "leaving the rules page records no participation", not game.last_result.outcome.started and not game.last_result.completed)
	game.queue_free()
	game = load("res://scripts/minigames/mg_goldfish.gd").new()
	main.ui.root.add_child(game)
	await t.frames(1)
	game.state = MiniGame.State.PLAY
	game.round_started = true
	game.set("caught", 2)
	game._leave()
	t.check("SUM_A06", "quitting mid-round retains actual catches without inventing a finished round", not game.last_result.completed and game.last_result.outcome.started and int(game.last_result.outcome.caught) == 2)
	game.queue_free()
	await t.frames(2)
	if main.in_room: await main.exit_room()
	G.new_game()
	G.clock_paused = true
	G.day = 17
	G.minute = 20 * 60
	G.quests["Q14"] = {"state": "active", "step": 2}
	main.update_npcs(true)
	var warmth_before: int = G.warmth.get("mio", 0)
	await t.use("mio", [3])
	t.check("SUM_A07", "declining the joint invitation leaves promise, photo and warmth unchanged", G.at_step("Q14", "goldfish_mio") and not Progress.found("col_photo_new") and int(G.warmth.get("mio", 0)) == warmth_before and not G.flags.has("summer_shared"))
	await t.use("mio", [1, 1, 0])
	t.check("SUM_A07", "light shared participation can finish without a fake game or photo", G.qstate("Q14") == "done" and G.flags.summer_shared.participation == "watched" and not Progress.found("col_photo_new") and int(G.mg_record("goldfish").plays) == 0)
	G.flags["summer_promise"] = 2
	var photo_reply: Dictionary = {}
	var no_photo_reply: Dictionary = {}
	for entry: Dictionary in Dialogue.entries:
		if str(entry.id) == "promise_photo": photo_reply = entry
		if str(entry.id) == "promise_without_photo": no_photo_reply = entry
	t.check("SUM_A07", "no-photo choice selects honest later conversation", not Dialogue.matches(photo_reply, {}) and Dialogue.matches(no_photo_reply, {}))
	t.check("SUM_A07", "completed no-photo participation has an optional later photo entrance", main.story.lore.photo_optional() and main.story.lore.pending("mio"))
	var warmth_after: int = G.warmth.get("mio", 0)
	await main.go_farm()
	await main.story.lore._stand_by_pool()
	var true_pool: Vector3 = main.story.physical_point("goldfish_pool")
	t.check("SUM_A07", "rejoining from the farm uses the real town pool, not a routing marker", main.world.region == "town" and not main.in_room and main.player.global_position.distance_to(true_pool) < 3.0 and main.npcs.mio.global_position.distance_to(true_pool) < 3.0)
	var photo_folder: String = SaveDB.directory
	SaveDB.directory = "/dev/null/harumachi-no-photo"
	var failed_photo: bool = await main.story.lore._photo()
	SaveDB.directory = photo_folder
	t.check("SUM_A07", "photo write failure awards no photo and preserves the completed shared scene", not failed_photo and not Progress.found("col_photo_new") and G.qstate("Q14") == "done" and int(G.warmth.get("mio", 0)) == warmth_after)
	var success_photo: bool = await main.story.lore._photo()
	t.check("SUM_A07", "a later retry captures once without replaying the game or rewarding again", success_photo and Progress.found("col_photo_new") and int(G.mg_record("goldfish").plays) == 0 and int(G.warmth.get("mio", 0)) == warmth_after)
	main.ui.dialogue_end()
	G.new_game()
	G.clock_paused = true
	G.day = 17
	G.minute = 20 * 60
	G.quests["Q14"] = {"state": "active", "step": 2}
	main.update_npcs(true)
	await t.use("mio", [0, 0, 0])
	t.check("SUM_A07", "actual shared game result continues into the selected photo and promise", G.qstate("Q14") == "done" and Progress.found("col_photo_new"), "Q14=%s/%s shared=%s" % [G.qstate("Q14"), G.qstep_id("Q14"), str(G.flags.get("summer_shared", {}))])
	G.new_game()
	G.clock_paused = true
	var no_fragments: bool = not StoryKnowledge.presented("promise")
	await main.story.lore._fragment("tree")
	t.check("SUM_A08", "a tree cue presents just its own fragment", no_fragments and StoryKnowledge.presented("tree") and not StoryKnowledge.presented("promise"))
	main.ui.dialogue_end()
	main.ui.open_book("notes")
	await t.frames(3)
	var saved_facts: Dictionary = G.to_dict().duplicate(true)
	for button in main.ui.modal_layer.find_children("*", "Button", true, false):
		if str(button.text).begins_with("回想 · "): button.pressed.emit()
	var after_replay: Dictionary = G.to_dict().duplicate(true)
	saved_facts.erase("saved_at")
	after_replay.erase("saved_at")
	t.check("SUM_A09", "memory replay changes no world facts or rewards", saved_facts == after_replay)
	t.check("SUM_A09", "unpresented promise is absent from the journal", not _text(main.ui.modal_layer).contains("纸网破掉的那年"))
	main.ui.close_modal(false)
	DailyLife.event("card").state = "done"
	DailyLife.event("card").choice = 3
	main.ui.open_book("notes")
	await t.frames(2)
	t.check("SUM_A10", "a first-market substitute in old or new saves has a truthful journal entry", _text(main.ui.modal_layer).contains("首次集市已经一起开过"))
	main.ui.close_modal(false)
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	G.quests["Q05"] = {"state": "done", "step": 5}
	DailyLife.track("meal")
	main.story.lore._on_day(2)
	t.check("SUM_A08", "the old-box invitation leaves personal tracking and acceptance with the player", G.qstate("Q10") == "available" and str(DailyLife.state().tracked) == "meal")
	DailyLife.clear_tracking()
	for qid: String in G.quest_order: G.quests[qid] = {"state": "done", "step": G.quests_db[qid].steps.size()}
	G.quests["Q10"] = {"state": "available", "step": 0}
	G.tracked_quest = "Q10"
	t.check("SUM_A11", "the available box points to the home door from town", main.story.marker_target() == main.story._point("home_door"))
	await main.enter_room()
	t.check("SUM_A11", "the available box points to the real closet once indoors", main.story.marker_target() == main.story._point("room_closet"))
	await main.exit_room()
	t.check("SUM_A11", "every tested activity returns HUD, dialogue and input control", main.ui.modal == "" and not G.input_locked() and main.ui.hud.visible)
	G.from_dict(original.duplicate(true))
	G.clock_paused = true

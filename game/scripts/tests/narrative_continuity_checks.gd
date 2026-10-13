extends RefCounted
## Regression checks for the playable bridge between arrival, market and revival.
var t: Node
var G: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	G = GameState
	main = t.main

func check(label: String, passed: bool) -> void:
	t.check("NARRATIVE_CONTINUITY", label, passed)

func run() -> void:
	var original: Dictionary = G.to_dict().duplicate(true)
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	main.story.lore._unlock_box()
	check("settling in opens the actual closet before the first market", G.qstate("Q10") == "available" and G.qstate("Q05") == "locked")
	check("availability alone does not invent seeing the photo", not Progress.found("col_photo2011") and not StoryKnowledge.presented("promise"))
	G.quests["Q10"] = {"state": "active", "step": 1}
	G.advance("Q10", "show_mio")
	check("recognition alone never offers the whole revival project", G.qstate("Q11") == "locked")
	# The shared entry point must also reject a stale available flag in an old save.
	G.quests["Q11"] = {"state": "available", "step": 0}
	check("the quest API cannot bypass the missing first market", not G.start_quest("Q11"))
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	G.quests["Q01"] = {"state": "done", "step": 2}
	await main.story._i_mio()
	check("cooperation Mio does not ask for obsolete support tokens", not main.ui.dlg_text.text.contains("支持标记"))
	var story_source := FileAccess.get_file_as_string("res://scripts/story/story.gd")
	var ending_source: String = story_source.get_slice("func _ending()", 1)
	check("the first market stays in the scene and has no title-screen ending", not ending_source.contains("show_ending(") and not ending_source.contains("go_title("))
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	main.story.lore._unlock_box()
	main.ui.auto_choices = [1]
	await main.story.lore._closet()
	check("declining the box keeps its contents undiscovered", G.qstate("Q10") == "available" and not Progress.found("col_photo2011"))
	main.ui.auto_choices = [0]
	await main.story.lore._closet()
	check("opening the actual box finds both illustrations without implying recognition", G.at_step("Q10", "show_mio") and Progress.found("col_photo2011") and Progress.found("col_letter") and not StoryKnowledge.presented("promise"))
	main.ui.auto_choices = [0]
	await main.story.lore._mio()
	check("the photo conversation records the promise and known closure facts", G.qstate("Q10") == "done" and StoryKnowledge.presented("promise") and StoryKnowledge.presented("stopped"))
	check("early recognition ends before offering a festival project", G.qstate("Q11") == "locked" and not G.flags.get("revival_accepted", false))
	var collection_before: Dictionary = G.collection.duplicate(true)
	var warmth_before: int = int(G.warmth.get("mio", 0))
	await main.story.lore._closet()
	check("revisiting the box neither gives another photo nor another relationship reward", G.collection == collection_before and int(G.warmth.get("mio", 0)) == warmth_before)
	G.quests["Q05"] = {"state": "done", "step": 5}
	main.story.lore._unlock_box()
	check("both real milestones offer but do not accept the revival", G.qstate("Q11") == "available" and not G.flags.get("revival_accepted", false))
	main.ui.auto_choices = [1]
	await main.story.lore._mio()
	check("Mio respects postponing the revival and keeps a specific return reason", G.qstate("Q11") == "available" and not G.flags.get("revival_accepted", false) and main.ui.dlg_text.text.contains("春"))
	main.ui.auto_choices = [0]
	await main.story.lore._mio()
	check("accepting the offered plan starts the notebook once", G.at_step("Q11", "find_notebook") and G.flags.get("revival_accepted", false) and not MainlineProgress.accept_revival())
	var coins_before: int = G.coins
	G.save_game()
	G.flags.clear()
	G.load_game()
	check("SQLite preserves recognition, explicit agreement and old photo identity", G.at_step("Q11", "find_notebook") and G.flags.get("revival_accepted", false) and G.collection == collection_before and G.coins == coins_before)
	G.quests["Q10"] = {"state": "locked", "step": 0}
	G.quests["Q05"] = {"state": "locked", "step": 0}
	MainlineProgress.initialize()
	check("an already started old notebook is not re-locked by the new preconditions", G.at_step("Q11", "find_notebook") and MainlineProgress.can_offer_revival())
	G.quests["Q11"] = {"state": "done", "step": 3}
	MainlineProgress.initialize()
	check("an old completed notebook never replays or pays its reward twice", G.qstate("Q11") == "done" and G.coins == coins_before and not MainlineProgress.accept_revival())
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	G.quests["Q05"] = {"state": "done", "step": 5}
	ResidentVisits.invite_after_market()
	var initial: Dictionary = MainlineProgress.objective()
	check("the market's next objective names the invited house and its actual action", initial.source == "visits" and str(initial.text).contains("春家"))
	DailyLife.track("meal")
	check("choosing a life action explicitly replaces rather than silently competing with a visit", not ResidentVisits.tracked() and MainlineProgress.objective().source == "life")
	ResidentVisits.track()
	check("choosing the invitation explicitly clears the previous life action", str(DailyLife.state().tracked) == "" and MainlineProgress.objective().source == "visits")
	SummerProjects.track()
	check("choosing cooperation explicitly clears the visit marker", not ResidentVisits.tracked() and MainlineProgress.objective().source == "cooperation")
	ResidentVisits.state().blueprint_seen = true
	ResidentVisits.state().measured = true
	ResidentVisits.arrange(1)
	DailyLife.track("meal")
	var promise_goal: Dictionary = MainlineProgress.objective()
	check("a dated promise stays visible while the player chooses another action", promise_goal.source == "life" and str(promise_goal.text).contains(ResidentVisits.promise_text()) and str(promise_goal.title) == MainlineProgress.season_goal())
	main.ui.instant = false
	main.ui.show_keepsake("col_photo2011")
	await t.frames(3)
	var picture: TextureRect = main.ui.modal_layer.find_child("StoryPicture", true, false)
	var caption: Label = main.ui.modal_layer.find_child("StoryPictureDescription", true, false)
	check("picture clues show actual existing art and a readable text alternative", picture != null and picture.texture != null and caption != null and caption.text.contains("空 和 澪") and G.input_locked())
	main.ui.close_modal()
	main.ui.instant = true
	G.new_game()
	G.clock_paused = true
	G.quests["Q15"] = {"state": "done", "step": 2}
	MainlineProgress.choose_direction(0, "home")
	check("a future planting note points to playable work without inventing completion", not MainlineProgress.direction_action().is_empty() and not MainlineProgress.direction().action_done)
	G.open_plots(["court"], true)
	G.add_item("seed_radish", 1, true)
	check("actually sowing the new seed fulfills the planting intention", G.sow("court", "seed_radish") == "" and MainlineProgress.direction().action_done and G.count("seed_radish") == 0)
	MainlineProgress.choose_direction(1, "home")
	G.add_item("radish", 3, true)
	G.sell_produce("radish", 1, 1.0)
	check("an ordinary shop sale cannot stand in for the promised market", not MainlineProgress.direction().action_done)
	G.sell_produce("radish", 1, float(G.shop("bakery").rate))
	check("a shop's higher purchase rate is still not the promised courtyard market", not MainlineProgress.direction().action_done)
	G.sell_produce("radish", 1, G.MARKET_RATE)
	check("an actual market sale fulfills the second playable intention once", MainlineProgress.direction().action_done and not MainlineProgress.record_direction_action("market"))
	MainlineProgress.choose_direction(2, "home")
	check("a new return-home letter is pending even after older correspondence", not MainlineProgress.direction().action_done and str(MainlineProgress.direction_action().target) == "visit_post_door")
	MainlineProgress.choose_direction(3, "home")
	check("leaving the long-term decision open still offers an actual visit", str(MainlineProgress.direction_action().target) == "visit_home_haru_door" and not MainlineProgress.direction().action_done)
	G.minute=11*60
	ResidentVisits.visit("florist")
	check("entering a public shop cannot stand in for visiting an invited household", not MainlineProgress.direction().action_done)
	ResidentVisits.invite("home_haru", "future household visit")
	ResidentVisits.visit("home_haru")
	check("actually visiting the invited home fulfills that final intention once", MainlineProgress.direction().action_done and not MainlineProgress.record_direction_action("visit"))
	var was_inside: bool = main.in_room
	var was_kind: String = main.room_kind
	var was_region: String = main.world.region
	var photo_target: Vector3 = main.story.physical_point("visit_photo_room_memory") + Vector3(0, 1.6, 0)
	main.in_room = false
	main.world.region = "town"
	check("from the street a photo-side-room clue first leads to the community entrance", main.story.route_marker(photo_target) == main.story._raw_marker("center_door"))
	main.in_room = true
	main.room_kind = "workroom"
	check("inside the parent room the photo clue leads to the actual side door", main.story.route_marker(photo_target) == main.story._raw_marker("visit_photo_room_door"))
	main.room_kind = "store"
	check("a clue in another house first leads out of the current room", main.story.route_marker(photo_target) == main.story._raw_marker("store_exit"))
	main.room_kind = "photo_room"
	check("inside the destination room the marker reaches the actual object", main.story.route_marker(photo_target) == photo_target)
	main.in_room = false
	main.world.region = "farm"
	check("from the farm a town interior clue first leads to the real town path", main.story.route_marker(photo_target) == main.story._raw_marker("farm_exit"))
	var mio: NPC = main.npcs.mio
	var mio_position: Vector3 = mio.global_position
	var mio_home: bool = mio.home
	mio.home = true
	mio.global_position = ResidentPlaces.SPECS.home_mio.origin + Vector3(1.25, 0, .35)
	ResidentVisits.invite("home_mio", "navigation regression")
	main.world.region = "town"
	check("an invited resident really at home is reached through her own door", main.story._npc_head("mio") == main.story._raw_marker("visit_home_mio_door"))
	main.in_room = true
	main.room_kind = "bakery"
	var ren_target: Vector3 = main.story.physical_point("visit_home_ren_memory") + Vector3(0, 1.6, 0)
	check("a shop's private back room is reached through its real internal door", main.story.route_marker(ren_target) == main.story._raw_marker("visit_home_ren_door"))
	main.room_kind = "home_ren"
	check("a different household requires first leaving the current private room", main.story._npc_head("mio") == main.story._raw_marker("visit_home_ren_exit"))
	var projected: Vector3 = main.story.outdoor_marker(ren_target)
	check("the map projects nested rooms onto actual street doors rather than hidden room origins", projected == main.story._raw_marker("bakery") and absf(projected.z) < 100)
	mio.home = mio_home
	mio.global_position = mio_position
	main.in_room = was_inside
	main.room_kind = was_kind
	main.world.region = was_region
	G.from_dict(original)
	G.clock_paused = true
	main.ui.dialogue_end()
	main.story.busy = false
	main.player.frozen = false
	await t.frames(2)

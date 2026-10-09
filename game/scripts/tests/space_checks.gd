extends RefCounted
var t: Node
var G: Node
var main: Node
func _init(runner: Node) -> void:
	t = runner
	G = GameState
	main = runner.main

func fresh() -> void:
	G.new_game()
	G.clock_paused = true
	G.quests.Q00 = {"state": "done", "step": 2}
	G.quests.Q11 = {"state": "done", "step": 3}
	G.quests.Q13 = {"state": "active", "step": 1}
	main.placement.rebuild()
	main.world.set_region("town")
	main.story.space.view.sync_state()

func run() -> void:
	var original: Dictionary = G.to_dict().duplicate(true)
	if main.in_room:
		if main.room_kind == "house": await main.exit_room()
		else: await main.exit_interior()
	fresh()
	t.check("SPACE_DISCOVERY", "the diagram only opens after the actual notebook discussion", main.story.space.handles("space_plan") and SummerSpace.state().phase == "invitation")
	G.quests.Q11 = {"state": "locked", "step": 0}
	t.check("SPACE_DISCOVERY", "an early visitor gets no future diagram or accepted space project", main.story.space.prompt("space_plan") == null and SummerSpace.start("manual", "loan") != "")
	fresh()
	G.bag_cap = 0
	t.check("SPACE_KIT", "a full bag keeps the invitation without imaginary received furniture", SummerSpace.start("manual", "loan") != "" and SummerSpace.state().phase == "invitation" and not G.has("bench"))
	G.bag_cap = G.INV_SLOTS
	SummerSpace.start("light", "loan")
	SummerSpace.start("light", "loan")
	t.check("SPACE_KIT", "finite project furniture is issued once without mandatory wood", G.count("bench") == 1 and G.count("picnic_table") == 1 and not G.has("wood") and G.at_step("Q13", "carry_wood"))
	await t.frames(3)
	PlacementSystem.project_context = "space"
	t.check("SPACE_REGION", "project editing reaches actual southern decisions outside the old zone", PlacementSystem.zone()[3] == 24.0 and PlacementSystem.check_rect(Vector2(2.5, 19), Vector2(2, 2)) == "")
	t.check("SPACE_OCCUPANCY", "an actual future dance footprint rejects furniture", PlacementSystem.check_rect(SummerSpace.DANCE_CENTER, Vector2(2, 2)) != "")
	t.check("SPACE_OCCUPANCY", "fixed stage and pergola collision cannot be disguised as usable ground", PlacementSystem.check_rect(Vector2(-9.8, 20.4), Vector2(2, 2)) != "" and PlacementSystem.check_rect(Vector2(-9.8, 13.2), Vector2(2, 2)) != "")
	PlacementSystem.project_context = ""
	t.check("SPACE_REGION", "ordinary placement still uses its original bounds", PlacementSystem.check_rect(Vector2(2.5, 19), Vector2(2, 2)) != "")
	for key: String in ["east", "west"]:
		var why: String = main.story.space.apply_scheme(key)
		await t.frames(3)
		t.check("SPACE_SCHEMES", key + " is a physically placeable distinct scheme", why == "" and G.placements.size() == 2 and SummerSpace.state().scheme == key, why)
		t.check("SPACE_SCHEMES", key + " uses a distinct valid serving choice", SummerSpace.state().style == "paper" or SummerSpace.stop_for("bench").distance_to(SummerSpace.stop_for("picnic_table")) < 5.0)
	t.check("SPACE_KIT", "switching schemes recycles the same furniture rather than issuing rewards", G.count("bench") == 0 and G.count("picnic_table") == 0 and SummerSpace.state().owned_uids.size() == 2)
	t.check("SPACE_INVITE", "absent residents cannot become invited or actual trial witnesses", SummerSpace.invite("haru", false) != "" and SummerSpace.state().invited.is_empty())
	for who: String in ["mio", "haru", "ren"]: SummerSpace.invite(who, true)
	main.npcs.mio.home = false
	main.npcs.haru.home = false
	main.npcs.ren.home = false
	main.npcs.mio.visible = true
	main.npcs.haru.visible = true
	main.npcs.ren.visible = true
	main.npcs.mio.place(SummerSpace.DEMO, 0)
	main.npcs.haru.place(SummerSpace.stop_for("bench"), 0)
	await t.frames(3)
	var visible: bool = main.story.space.view.see_demo(main.npcs.haru, main.npcs.mio)
	t.check("SPACE_VIEW", "the actual selected western viewpoint can see the live demonstrator", visible)
	var stamp: String = SummerSpace.revision()
	var records: Dictionary = {}
	for role: String in ["mio", "haru", "ren"]:
		var at: Vector3 = SummerSpace.DEMO if role == "mio" else SummerSpace.stop_for("bench" if role == "haru" else "picnic_table")
		var result := {"present": true, "arrived": true, "revision": stamp, "position": {"x": at.x, "y": at.y, "z": at.z}, "visible_demo": visible, "crossed_dance": false, "length": 1.0,"path":[LayoutValidity.position(at)]}
		if role=="haru":result["sight"]={"from":LayoutValidity.position(main.story.space.view.eye(main.npcs.haru)),"to":LayoutValidity.position(main.story.space.view.eye(main.npcs.mio))}
		records[role] = result
		t.check("SPACE_RESULT", role + " commits only the actual selected target", SummerSpace.record(role, result) == "")
	var wrong: Dictionary = records.haru.duplicate(true)
	wrong.position.x = 0
	t.check("SPACE_RESULT", "a reported arrival at another place cannot approve the viewing plan", SummerSpace.record("haru", wrong) != "")
	var no_view: Dictionary = records.haru.duplicate(true)
	no_view.visible_demo = false
	t.check("SPACE_RESULT", "arrival alone never replaces an actual viewing check", SummerSpace.record("haru", no_view) != "")
	t.check("SPACE_RETAIN", "a good first scheme is retained without compulsory failures or remakes", SummerSpace.retain() == "" and SummerSpace.ready() and G.at_step("Q13", "give_wood"))
	G.save_game()
	var stored: Dictionary = SummerSpace.state().duplicate(true)
	G.flags.clear()
	G.load_game()
	t.check("SPACE_SAVE", "SQLite preserves the same scheme, furniture identities and actual witnesses", JSON.stringify(SummerSpace.state()) == JSON.stringify(stored))
	main.story.lore._on_day(16)
	t.check("SPACE_CALENDAR", "a half or retained player scheme is not autocompleted by the town", G.at_step("Q13", "give_wood") and not G.flags.get("town_finished_Q13", false))
	var crossed: Dictionary = records.ren.duplicate(true)
	crossed.crossed_dance = true
	t.check("SPACE_REUSE", "shared use rejects a food route through the active dance circle", SummerSpace.record("ren", crossed, true) != "" and SummerSpace.state().application.is_empty())
	SummerSpace.record("ren", records.ren, true)
	t.check("SPACE_REUSE", "off-date shared use is explicitly rehearsal rather than a fabricated festival", SummerSpace.state().application.context == "shared_rehearsal")
	# A legal intermediate plan can borrow the circle before it is in shared use.
	var current_table: Dictionary = SummerSpace.furniture("picnic_table")
	PlacementSystem.project_context = "space"
	G.remove_placement(int(current_table.uid))
	G.add_placement("picnic_table", -7.5, 22.5, 1)
	PlacementSystem.project_context = ""
	await t.frames(3)
	var plain: Dictionary = ProjectRoute.query(main.world, SummerSpace.FOOD_START, SummerSpace.stop_for("picnic_table"), [], SummerSpace.revision())
	var shared: Dictionary = ProjectRoute.query(main.world, SummerSpace.FOOD_START, SummerSpace.stop_for("picnic_table"), [], SummerSpace.revision(), [[SummerSpace.DANCE_CENTER, SummerSpace.DANCE_RADIUS]])
	var shared_tradeoff: bool=not shared.ok or (not SummerSpace.crosses_dance(shared.path) and float(shared.length)>float(plain.get("length",INF))+.5)
	t.check("SPACE_ROUTING", "an occupied dance circle forces a real detour or an unavailable food route", plain.ok and SummerSpace.crosses_dance(plain.path) and shared_tradeoff, JSON.stringify({"plain":plain.get("length"), "shared":shared.get("length",shared.get("reason"))}))
	G.add_item("flower_pot", 1, true)
	G.add_placement("flower_pot", 9.5, 12.5, 0)
	t.check("SPACE_REVISION", "a layout change invalidates old retention and completed shared use", not SummerSpace.ready())
	var before_failure: Dictionary = G.to_dict().duplicate(true)
	G.bag_cap = 0
	var failed: String = main.story.space.apply_scheme("east")
	t.check("SPACE_ROLLBACK", "a failed scheme change preserves existing furniture without duplication", failed != "" and G.placements.size() == before_failure.placements.size())
	# Real legacy entry and invitation, rather than directly setting invited flags.
	fresh()
	SummerProjects.state().mainline_mode = "legacy"
	G.quests.Q13 = {"state":"done","step":4}
	await t.use("space_plan", [0])
	for resident: String in ["mio", "haru", "ren"]: await t.use(resident, [0])
	t.check("SPACE_LEGACY", "a legacy completed story can open the new practice and actually invite its cast", SummerSpace.state().invited.size() == 3 and G.qstate("Q13") == "done" and not SummerProjects.uses_cooperation_mainline())
	main.story.space.apply_scheme("east")
	var old_bench: int = int(SummerSpace.furniture("bench").uid)
	PlacementSystem.project_context = "space"
	G.remove_placement(old_bench)
	var replaced: bool = main.placement.place_at("bench", 6.5, 23.5, 2)
	PlacementSystem.project_context = ""
	await t.frames(3)
	var switched: String = main.story.space.apply_scheme("west")
	t.check("SPACE_OWNERSHIP", "manual pickup and replacement permits another scheme without duplicating furniture", replaced and switched == "" and G.placements.size() == 2 and G.count("bench") == 0 and G.count("picnic_table") == 0 and not SummerSpace.state().owned_uids.has(old_bench))
	var food: Vector3 = SummerSpace.stop_for("picnic_table")
	var event_result := {"present":true,"arrived":true,"revision":SummerSpace.revision(),"position":{"x":food.x,"y":food.y,"z":food.z},"crossed_dance":false,"path":[LayoutValidity.position(food)]}
	G.day = 16
	SummerSpace.record("ren", event_result, true)
	G.day = 17
	G.minute = 19 * 60
	SummerSpace.record("ren", event_result, true)
	t.check("SPACE_CONTEXT", "unchanged furniture still separates rehearsal and actual festival identities", SummerSpace.state().application.context == "festival" and SummerSpace.state().application_history.back().context == "shared_rehearsal")
	G.day = 18
	SummerSpace.record("ren", event_result, true)
	t.check("SPACE_CONTEXT", "a later shared trial cannot complete yesterday's festival session", SummerSpace.state().application.context == "shared_rehearsal" and int(SummerSpace.state().application.day) == 18 and SummerSpace.state().application_history.back().context == "festival")
	var probe_actor: NPC = main.npcs.ren
	main.story.space.view.begin_walk(probe_actor)
	await t.frames(3)
	var panel: PanelContainer = main.story.space.view.walk_panel
	# The native demo checks actual mouse; this checks the panel follows its parent instead of fixed pixels.
	t.check("SPACE_CANCEL", "the mouse cancel panel is anchored to the available viewport", main.ui.instant or (panel.anchor_left == 1.0 and panel.anchor_right == 1.0 and panel.offset_right < 0))
	main.story.space.view.end_walk()
	G.from_dict(original.duplicate(true))
	G.clock_paused = true
	PlacementSystem.project_context = ""
	main.placement.rebuild()
	main.story.space.view.sync_state()

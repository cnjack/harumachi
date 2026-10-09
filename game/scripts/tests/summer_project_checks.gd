extends RefCounted
var t: Node
var G: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	G = GameState
	main = runner.main

func fresh(role: String = "food") -> void:
	G.new_game()
	G.clock_paused = true
	G.quests["Q00"] = {"state": "done", "step": 2}
	G.quests["Q01"] = {"state": "done", "step": 2}
	SummerProjects.accept(role)

func run() -> void:
	var original: Dictionary = G.to_dict().duplicate(true)
	G.new_game()
	t.check("PROJECT_INVITE", "no project is accepted automatically on arrival", SummerProjects.phase() == "invitation" and not SummerProjects.state().tracked)
	t.check("PROJECT_INVITE", "the cooperation waits for the actual neighbourhood invitation", SummerProjects.accept("food") != "" and not G.has("picnic_table"))
	G.quests["Q01"] = {"state": "done", "step": 2}
	G.bag_cap = 0
	t.check("PROJECT_INVITE", "a full bag cannot accept missing borrowed furniture as received", SummerProjects.accept("food") != "" and SummerProjects.phase() == "invitation" and not G.has("bench"))
	fresh()
	t.check("PROJECT_INVITE", "acceptance lends one real table and bench without accepting farming", G.count("picnic_table") == 1 and G.count("bench") == 1 and G.qstate("Q03") == "locked" and G.qstate("Q16") == "locked")
	SummerProjects.accept("food")
	t.check("PROJECT_INVITE", "repeating acceptance does not duplicate furniture", G.count("picnic_table") == 1 and G.count("bench") == 1)
	SummerProjects.choose_plan("sandwich", "own")
	var sandwich_inputs: Dictionary = G.recipe(SummerProjects.TRIAL_RECIPE).inputs.duplicate(true)
	SummerProjects.opening().phase = "plan"
	SummerProjects.choose_plan("focaccia", "own")
	var focaccia_inputs: Dictionary = G.recipe(SummerProjects.TRIAL_RECIPE).inputs.duplicate(true)
	t.check("PROJECT_MENU", "different menus actually consume different ingredient bundles", sandwich_inputs.get("cucumber", 0) == 1 and sandwich_inputs.get("butter", 0) == 1 and focaccia_inputs.get("tomato", 0) == 3 and not focaccia_inputs.has("cucumber"))
	t.check("PROJECT_MENU", "missing own ingredients never lock the player out of changing source", SummerProjects.choose_plan("sandwich", "shop") == "" and SummerProjects.opening().source == "shop")
	fresh()
	SummerProjects.choose_plan("sandwich", "shop")
	SummerProjects.claim_kit()
	SummerProjects.claim_kit()
	t.check("PROJECT_MATERIAL", "borrowed trial kit is one real protected parcel", G.count(SummerProjects.KIT) == 1 and G.is_key_item(SummerProjects.KIT) and int(SummerProjects.opening().borrowed_trials) == 1)
	t.check("PROJECT_MATERIAL", "unconsumed materials cannot silently become a different menu", SummerProjects.choose_plan("focaccia", "shop") != "" and SummerProjects.opening().menu == "sandwich")
	SummerProjects.return_kit()
	t.check("PROJECT_MATERIAL", "returning an unused parcel really removes it and permits replanning", not G.has(SummerProjects.KIT) and SummerProjects.phase() == "plan")
	SummerProjects.choose_plan("sandwich", "shop")
	SummerProjects.claim_kit()
	var why: String = G.craft(SummerProjects.TRIAL_RECIPE)
	var batch: Dictionary = SummerProjects.current_batch()
	var iid: String = str(batch.get("iid", ""))
	t.check("PROJECT_MATERIAL", "actual oven crafting consumes kit and creates precisely three small portions", why == "" and not G.has(SummerProjects.KIT) and G.count(iid) == 3 and int(batch.total) == 3 and batch.maker == "player")
	t.check("PROJECT_MATERIAL", "a completed trial cannot be cooked or committed a second time", G.craft(SummerProjects.TRIAL_RECIPE) != "" and SummerProjects.opening().batches.size() == 1)
	t.check("PROJECT_FOOD", "two portions are protected but the honest remaining one is edible", G.reserved_count(iid) == 2 and G.unreserved_count(iid) == 1 and DailyLife.edible(iid))
	if not main.in_room: await main.enter_room()
	await t.use("life_meal_table", [0])
	t.check("PROJECT_FOOD", "the real table offers and consumes the key-item small portion", G.count(iid) == 2 and int(batch.self_eaten) == 1)
	t.check("PROJECT_FOOD", "self eating cannot consume the two promised tasting portions", DailyLife.eat_food(iid) != "" and G.count(iid) == 2)
	t.check("PROJECT_FEEDBACK", "absent neighbours cannot taste or consume food", SummerProjects.taste("mio", false) != "" and G.count(iid) == 2 and batch.tasters.is_empty())
	SummerProjects.taste("mio", true)
	SummerProjects.taste("mio", true)
	t.check("PROJECT_FEEDBACK", "one taster cannot be counted twice", G.count(iid) == 1 and batch.tasters.size() == 1)
	SummerProjects.taste("haru", true)
	t.check("PROJECT_FEEDBACK", "two actual different tasters unlock an independent decision", G.count(iid) == 0 and SummerProjects.phase() == "decision" and batch.tasters.size() == 2)
	G.save_game()
	var expected: Dictionary = SummerProjects.state().duplicate(true)
	G.flags.clear()
	G.load_game()
	t.check("PROJECT_SAVE", "SQLite restores batch identity, source, maker, tasters and own meal", SummerProjects.state() == expected and G.is_key_item(iid) and DailyLife.edible(iid))
	t.check("PROJECT_CHOICE", "a good first menu can be retained without compulsory remaking", SummerProjects.confirm_plan("bite", "paper") == "" and SummerProjects.phase() == "site" and SummerProjects.opening().batches.size() == 1)
	var result: Dictionary = {"ok": true, "revision": SummerProjects.layout_fingerprint(), "path": [Vector3(2,0,13)]}
	t.check("PROJECT_ROUTE", "a paper assertion cannot replace actual arranged furniture", SummerProjects.record_layout(result, "mio", true) != "")
	G.add_placement("picnic_table", -3, 10, 0)
	G.add_placement("bench", -3, 14, 0)
	result.revision = SummerProjects.layout_fingerprint()
	t.check("PROJECT_ROUTE", "absent actor cannot approve a valid layout", SummerProjects.record_layout(result, "mio", false) != "")
	SummerProjects.record_layout(result, "mio", true)
	t.check("PROJECT_ROUTE", "layout review is bound to the current placement revision", SummerProjects.ready())
	G.add_item("flower_pot", 1, true)
	var extra: int = G.add_placement("flower_pot", 8, 4, 0)
	t.check("PROJECT_ROUTE", "remote flowers preserve the retained cooperation trial", SummerProjects.ready())
	G.remove_placement(extra)
	result.revision = SummerProjects.layout_fingerprint()
	SummerProjects.record_layout(result, "mio", true)
	G.phase = "market"
	SummerProjects.apply("shop")
	var small: Dictionary = SummerProjects.opening().service.ingredients.duplicate(true)
	t.check("PROJECT_USE", "small servings allocate one real recipe rather than three full dishes", int(small.tomato) == 2 and int(SummerProjects.opening().service.servings) == 3 and SummerProjects.opening().service.maker == "ren")
	var view: ProjectView=null
	for child: Node in main.get_children():
		if child is ProjectView:view=child;break
	var supported_servings:=view!=null
	if view!=null:
		view.sync_state()
		var bases: Array[Node]=view.food.find_children("Presentation_*","MeshInstance3D",true,false)
		supported_servings=bases.size()==3
		var counter: Node3D=main.world.get_node_or_null("P09")
		for base_node: MeshInstance3D in bases:
			var bounds: AABB=base_node.global_transform*base_node.get_aabb()
			for x: float in [bounds.position.x,bounds.end.x]:
				for z: float in [bounds.position.z,bounds.end.z]:
					var height: float=WorldBuilder.rendered_support_height(counter,Vector3(x,0,z),1.5,true)
					if not is_finite(height) or absf(height-bounds.position.y)>.02:supported_servings=false
	t.check("PROJECT_USE","the real three first-market servings have complete support on the current counter",supported_servings)
	G.phase = "market"
	SummerProjects.apply("shop")
	t.check("PROJECT_USE", "repeating field use neither resets portions nor allocates another basket", int(SummerProjects.opening().service.remaining) == 3)
	t.check("PROJECT_USE", "unused food cannot be packed as a finished cooperation before greeting a guest", SummerProjects.pack_leftovers() != "")
	t.check("PROJECT_USE", "an absent diner cannot be counted as real use", SummerProjects.serve("mio", false) != "" and int(SummerProjects.opening().service.remaining) == 3)
	var before_delivery: Dictionary = G.to_dict().duplicate(true)
	G.add_item("flower_pot", 1, true)
	G.add_placement("flower_pot", 8, 4, 0)
	t.check("PROJECT_USE", "remote flowers preserve the basket and its existing route", SummerProjects.current_layout_valid() and int(SummerProjects.opening().service.remaining)==3)
	G.from_dict(before_delivery.duplicate(true))
	t.check("PROJECT_USE", "nearby alone cannot be recorded as an actual handoff", SummerProjects.serve("mio", true) != "" and int(SummerProjects.opening().service.remaining) == 3)
	SummerProjects.begin_handoff("mio", true, Vector3(2, 0, 13), Vector3(2.95, .05, 13))
	t.check("PROJECT_HANDOFF", "a portion in the giver's hand is removed from displayed stock", int(SummerProjects.opening().service.remaining) == 2 and SummerProjects.opening().service.has("pending") and SummerProjects.opening().service.served.is_empty())
	G.save_game()
	G.load_game()
	t.check("PROJECT_HANDOFF", "loading an interrupted handoff returns exactly the undecided portion", int(SummerProjects.opening().service.remaining) == 3 and not SummerProjects.opening().service.has("pending") and SummerProjects.opening().service.served.is_empty())
	SummerProjects.serve("mio", true, Vector3(2, 0, 13), Vector3(2.95, .05, 13))
	SummerProjects.serve("mio", true, Vector3(2, 0, 13), Vector3(2.95, .05, 13))
	t.check("PROJECT_USE", "handing one portion to one guest debits only once", int(SummerProjects.opening().service.remaining) == 2)
	SummerProjects.finish()
	SummerProjects.pack_leftovers()
	t.check("PROJECT_LEFTOVER", "actual leftover portions can be packed without duplicating the basket", G.count("opening_leftover") == 2 and int(SummerProjects.opening().service.remaining) == 0)
	SummerProjects.pack_leftovers()
	t.check("PROJECT_LEFTOVER", "packing twice cannot create food", G.count("opening_leftover") == 2)
	DailyLife.eat_food("opening_leftover")
	t.check("PROJECT_LEFTOVER", "leftover own meal is edible and keeps its actual source", G.count("opening_leftover") == 1 and int(SummerProjects.opening().service.self_eaten) == 1)
	G.save_game()
	var after_service: Dictionary = SummerProjects.state().duplicate(true)
	G.flags.clear()
	G.load_game()
	t.check("PROJECT_SAVE", "SQLite preserves complete field use, ingredients, leftovers and portions", SummerProjects.state() == after_service)
	fresh("host")
	SummerProjects.choose_plan("focaccia", "shop")
	SummerProjects.claim_kit()
	SummerProjects.shop_prepares()
	t.check("PROJECT_HOST", "the host path names Ren as maker and never claims player cooking", SummerProjects.phase() == "feedback" and SummerProjects.current_batch().maker == "ren" and not G.flags.get("cooked", false))
	t.check("PROJECT_HOST", "Ren's preparation is finite and cannot be requested twice", SummerProjects.shop_prepares() != "" and G.count(str(SummerProjects.current_batch().iid)) == 3)
	SummerProjects.taste("mio", true)
	SummerProjects.taste("kazuko", true)
	SummerProjects.confirm_plan("whole", "plate")
	G.add_placement("picnic_table", -3, 10, 0)
	G.add_placement("bench", -3, 14, 0)
	await t.frames(3)
	SummerProjects.record_layout({"ok": true, "revision": SummerProjects.layout_fingerprint(),"path":[Vector3(2,0,13)]}, "mio", true)
	G.phase = "market"
	SummerProjects.apply("shop")
	t.check("PROJECT_HOST", "whole servings change actual material allocation and presentation", int(SummerProjects.opening().service.ingredients.tomato) == 9 and SummerProjects.opening().final.presentation == "plate")
	fresh("food")
	SummerProjects.choose_plan("sandwich", "own")
	for material: String in SummerProjects.ingredients("sandwich"):
		G.add_item(material, int(SummerProjects.ingredients("sandwich")[material]) * 3, true)
	var raw_before: int = G.count("tomato")
	t.check("PROJECT_BATCH", "one identified trial cannot consume and emit multiple batches at once", G.craft(SummerProjects.TRIAL_RECIPE, 2) != "" and G.count("tomato") == raw_before)
	fresh("food")
	SummerProjects.choose_plan("sandwich", "own")
	for material: String in SummerProjects.ingredients("sandwich"):
		G.add_item(material, int(SummerProjects.ingredients("sandwich")[material]) * 3, true)
	G.craft(SummerProjects.TRIAL_RECIPE, 1)
	var committed: Dictionary = SummerProjects.state().duplicate(true)
	var tomatoes_after: int = G.count("tomato")
	t.check("PROJECT_BATCH", "spare owned ingredients cannot create unregistered portions after commit", G.craft(SummerProjects.TRIAL_RECIPE, 1) != "" and G.count("tomato") == tomatoes_after and SummerProjects.state() == committed)
	t.check("PROJECT_BATCH", "a committed project recipe is neither known nor batchable", not G.recipe_known(SummerProjects.TRIAL_RECIPE) and G.craft_max(SummerProjects.TRIAL_RECIPE) == 0)
	# Collision queries are separate evidence from rule acceptance; they use the real current scene.
	if main.in_room:
		if main.room_kind == "house": await main.exit_room()
		else: await main.exit_interior()
	G.placements.clear()
	main.placement.rebuild()
	await t.frames(3)
	var path: Dictionary = ProjectRoute.query(main.world, Vector3(-3, 0, 12.5), Vector3(2, 0, 13.0))
	t.check("PROJECT_COLLISION", "clear actual courtyard collision produces a usable route", path.ok and not path.get("path", []).is_empty(), str(path.get("reason", "")))
	G.add_item("picnic_table", 1, true)
	G.add_placement("picnic_table", 2, 13, 0)
	await t.frames(3)
	var blocked: Dictionary = ProjectRoute.query(main.world, Vector3(-3, 0, 12.5), Vector3(2, 0, 13.0))
	t.check("PROJECT_COLLISION", "an actual table over the stop fails the route instead of phasing through", not blocked.ok, str(blocked.get("reason", "")))
	var trial_actor: NPC = main.npcs.haru
	trial_actor.home = false
	trial_actor.visible = true
	trial_actor.place(Vector3(-3, 0, 13), 90)
	trial_actor.set_talking(true)
	main.story.busy = true
	var stopped_by_table: bool = false
	var direct_path: Array = [Vector3(4, 0, 13)]
	if trial_actor.has_method("walk_safe"):
		stopped_by_table = not await trial_actor.call("walk_safe", direct_path)
	else:
		trial_actor.walk(direct_path)
		await trial_actor.arrived
	t.check("PROJECT_COLLISION", "a live trial actor stops at a real table instead of reporting arrival", stopped_by_table and trial_actor.global_position.distance_to(Vector3(4, 0, 13)) > .8)
	main.story.busy = false
	trial_actor.set_talking(false)
	await mainline_checks()
	G.from_dict(original.duplicate(true))
	G.clock_paused = true
	main.placement.rebuild()

func mainline_checks() -> void:
	fresh("host")
	t.check("PROJECT_MAINLINE", "a new game explicitly uses the cooperation mainline", str(SummerProjects.state().get("mainline_mode", "")) == "cooperation")
	SummerProjects.choose_plan("focaccia", "shop")
	SummerProjects.claim_kit()
	SummerProjects.shop_prepares()
	SummerProjects.taste("mio", true)
	SummerProjects.taste("haru", true)
	SummerProjects.confirm_plan("bite", "paper")
	G.add_placement("picnic_table", -3, 10, 0)
	G.add_placement("bench", -3, 14, 0)
	await t.frames(3)
	SummerProjects.record_layout({"ok": true, "revision": SummerProjects.layout_fingerprint(),"path":[Vector3(2,0,13)]}, "mio", true)
	t.check("PROJECT_MAINLINE", "actual hosting preparation unlocks Q05 without farming or old errands", G.qstate("Q05") == "available" and G.qstate("Q03") == "locked" and G.qstate("Q02") == "locked")
	t.check("PROJECT_MAINLINE", "the final service basket waits for the actual market", SummerProjects.apply("shop") != "" and SummerProjects.opening().service.is_empty())
	main.placement.rebuild()
	await t.frames(3)
	var marker: Variant = main.story.marker_target()
	t.check("PROJECT_TRACK", "a prepared cooperation pin points at Mio for the actual report", marker is Vector3 and marker.distance_to(main.npcs.mio.global_position + Vector3(0, 2.55, 0)) < .5)
	main.ui.open_quests()
	await t.frames(3)
	var entry: Button = journal_button(G.quest_title("Q05"))
	if entry: entry.pressed.emit()
	await t.frames(2)
	var old_text := false
	for label in main.ui.modal_layer.find_children("*", "Label", true, false):
		if "支持标记" in label.text: old_text = true
	t.check("PROJECT_JOURNAL", "all new Q05 steps describe the actual cooperation branch", not old_text)
	var accept: Button = journal_button("接受委托")
	if accept: accept.pressed.emit()
	main.ui.close_modal(false)
	var furniture_before: int = G.count("picnic_table") + G.count("bench")
	await t.use("mio")
	t.check("PROJECT_MAINLINE", "J acceptance still lets Mio report the actual project without duplicate furniture", G.at_step("Q05", "invite") and G.count("picnic_table") + G.count("bench") == furniture_before)
	if not G.at_step("Q05", "invite"): return
	await t.use("ren", [0])
	await t.use("haru", [0])
	t.check("PROJECT_MAINLINE", "nonfarming neighbours are invited through their real story entries", G.at_step("Q05", "start") and G.invited("ren") and G.invited("haru") and G.qstate("Q03") == "locked")
	G.day = G.next_market_day()
	G.minute = G.MARKET_OPEN + 10
	await t.use("mio", [0])
	t.check("PROJECT_MAINLINE", "actual Saturday opening preserves an empty planter", G.phase == "market" and G.at_step("Q05", "chat") and G.crop_stage == 0)
	for who: String in ["mio", "ren", "haru"]: await t.use(who)
	t.check("PROJECT_MAINLINE", "three conversations cannot finish a new market before real service", G.at_step("Q05", "chat") and not G.flags.get("ended", false))
	await t.use("opening_site", [1])
	await t.use("opening_site", [0])
	t.check("PROJECT_MAINLINE", "a real market handoff permits the first chapter summary", G.qstate("Q05") == "done" and SummerProjects.market_used() and G.qstate("Q03") == "locked")
	await t.frames(12)
	# Instant summary returns control automatically; verify journal buttons use the same tracking APIs.
	DailyLife.track("tea")
	t.check("PROJECT_TRACK", "tracking a life event removes the project pin", not bool(SummerProjects.state().tracked))
	SummerProjects.state().tracked = true
	G.quests["Q04"] = {"state": "available", "step": 0}
	G.start_quest("Q04")
	t.check("PROJECT_TRACK", "accepting a quest replaces the project pin", not bool(SummerProjects.state().tracked) and str(DailyLife.state().tracked) == "")
	var saved: Dictionary = G.to_dict().duplicate(true)
	saved.flags.summer_projects.erase("mainline_mode")
	saved.quests.Q05 = {"state": "done", "step": 5}
	G.from_dict(saved)
	t.check("PROJECT_LEGACY", "pre-integration saves retain their completed market without fabricated service", str(SummerProjects.state().mainline_mode) == "legacy" and G.qstate("Q05") == "done")
	await board_checks()
	G.new_game()

func board_text() -> String:
	var was_instant: bool=main.ui.instant
	main.ui.instant=false
	main.story.call_deferred("_i_board")
	await t.frames(4)
	var text: String=""
	for label: Label in main.ui.modal_layer.find_children("*","Label",true,false):text+=label.text+"\n"
	main.ui.close_modal()
	await t.frames(2)
	main.ui.instant=was_instant
	return text

func board_checks() -> void:
	G.new_game();G.clock_paused=true;G.quests.Q01={"state":"done","step":2}
	var invitation_text: String=await board_text()
	t.check("PROJECT_BOARD","a revisited cooperation board names the current paper and marks old community jobs optional",invitation_text.contains(SummerProjects.hint()) and invitation_text.contains("可选") and invitation_text.contains("面包送到摊位") and G.qstate("Q03")=="locked")
	SummerProjects.accept("host");SummerProjects.choose_plan("focaccia","shop")
	var trial_text: String=await board_text()
	t.check("PROJECT_BOARD","the same board follows the actual hosting phase without pretending the food is finished",trial_text.contains(SummerProjects.hint()) and not trial_text.contains("方案试好后") and SummerProjects.phase()=="trial")
	SummerProjects.state().mainline_mode="legacy"
	var legacy_text: String=await board_text()
	t.check("PROJECT_BOARD","legacy saves retain their original preparation list without a fabricated cooperation",legacy_text.contains("种植箱重新种上") and not legacy_text.contains("本次合作") and not legacy_text.contains("可选"))

func journal_button(prefix: String) -> Button:
	for node in main.ui.modal_layer.find_children("*", "Button", true, false):
		if node.text.begins_with(prefix): return node
	return null

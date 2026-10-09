extends RefCounted
var t: Node
var main: Node
var G: Node
func _init(runner: Node) -> void: t = runner; main = runner.main; G = GameState
func check(name: String, ok: bool) -> void: t.check("GATHERING", name, ok)
func fixture() -> void:
	G.new_game()
	G.clock_paused = true
	G.day = 17
	G.minute = 19 * 60
	G.quests.Q05 = {"state":"done","step":5}
	G.quests.Q11 = {"state":"done","step":3}
	G.quests.Q14 = {"state":"done","step":3}
	var prior: Dictionary = SummerProjects.opening()
	prior.phase = "done"
	prior.final = {"menu":"sandwich","portion":"bite","presentation":"paper","trial_batch":1,"recipe":"veg_sandwich","decided_day":3}
	prior.service = {"remaining":2,"served":{"mio":3},"self_eaten":0,"packed":0,"day":3,"trial_batch":1,"ingredients":{},"source":"shop","revision":"old"}
	main.world.set_region("town")
	main.world.sync_festivals()
	main.in_room = false
	G.player_in_room = false
	G.add_item("bench",1,true)
	G.add_placement("bench",2.5,10.5,0)
	main.placement.rebuild()
	G.state_changed.emit()
func proof(target: Vector3) -> Dictionary:
	return {"present":true,"arrived":true,"revision":SummerSpace.revision(),"position":{"x":target.x,"y":target.y,"z":target.z},"crossed_dance":false,"path":[LayoutValidity.position(target)]}
func run() -> void:
	var original: Dictionary = G.to_dict().duplicate(true)
	var instant: bool = main.ui.instant
	main.ui.instant = true
	G.new_game()
	G.clock_paused = true
	check("arrival does not invent a summer basket or an agreed reunion", SummerGathering.state().sessions.is_empty() and SummerGathering.context() == "")
	var empty_started: int = Time.get_ticks_usec()
	for refresh: int in 10: main.story.gathering.view.sync_state()
	var empty_ms: float = float(Time.get_ticks_usec() - empty_started) / 1000.0
	t.check("GATHERING", "ten first-morning clock refreshes avoid unused tabletop geometry", empty_ms < 50.0, "10 refreshes=%.3f ms" % empty_ms)
	check("food cannot be prepared before the real event or explicit agreement", SummerGathering.prepare("bite","paper","shop",true) != "")
	fixture()
	var old: Dictionary = SummerProjects.opening().service.duplicate(true)
	check("two menus and whole portions use the original finite ingredient algorithm", SummerGathering.service_cost("sandwich","whole").tomato == 6 and SummerGathering.service_cost("focaccia","bite").tomato == 3 and not SummerGathering.service_cost("focaccia","bite").has("butter"))
	check("an absent maker and insufficient own materials never create a basket", SummerGathering.prepare("whole","plate","own",true) != "" and SummerGathering.prepare("bite","paper","shop",false) != "" and SummerGathering.current().is_empty())
	for iid: String in SummerGathering.service_cost("sandwich","whole"): G.add_item(iid, SummerGathering.service_cost("sandwich","whole")[iid], true)
	check("preparing three whole servings consumes new actual materials once", SummerGathering.prepare("whole","plate","own",true) == "" and G.count("tomato") == 0 and G.count("butter") == 0 and int(SummerGathering.current().remaining) == 3 and SummerGathering.current().maker == "ren")
	check("reentering never repeats the free basket or edits the first market ledger", SummerGathering.prepare("bite","paper","shop",true) != "" and SummerProjects.opening().service == old and int(SummerGathering.current().remaining) == 3)
	var surface: Vector3 = main.story.gathering.view.surface()
	check("the food is supported by a real rendered table surface", surface.is_finite() and surface.y > .5 and surface.y < 1.5)
	var repeated_started: int = Time.get_ticks_usec()
	for repeat: int in 5: main.story.gathering.view.surface()
	var repeated_ms: float = float(Time.get_ticks_usec() - repeated_started) / 1000.0
	t.check("GATHERING", "an unchanged active table reuses its real measured support", repeated_ms < 20.0, "5 surface queries=%.3f ms" % repeated_ms)
	var measured_table: Node3D = main.story.gathering.view.table()
	var table_before: Vector3 = measured_table.global_position
	measured_table.global_position += Vector3.RIGHT
	var moved_surface: Vector3 = main.story.gathering.view.surface()
	check("moving a measured table updates the real serving surface", moved_surface.is_finite() and moved_surface.distance_to(surface + Vector3.RIGHT) < .001)
	measured_table.global_position = table_before
	var target: Vector3 = main.story.gathering.view.stop()
	var absent: Dictionary = proof(target)
	absent.present = false
	check("absent or unarrived actors cannot consume a serving", SummerGathering.take("mio", absent, target) != "" and SummerGathering.take("mio", proof(target + Vector3(3,0,0)), target) != "" and int(SummerGathering.current().remaining) == 3)
	var crossing: Dictionary = proof(target)
	crossing.crossed_dance = true
	check("festival service leaves the actual dance circle clear", SummerGathering.take("mio", crossing, target) != "" and int(SummerGathering.current().remaining) == 3)
	G.placements[0].x = 10
	check("moving the resting place too far away makes the current plate plan unusable without remaking food", SummerGathering.take("mio",proof(target),target) != "" and int(SummerGathering.current().remaining) == 3)
	G.placements[0].x = 2.5
	main.npcs.mio.home = false
	main.npcs.mio.show()
	main.npcs.mio.place(Vector3(0,0,13), 0)
	await main.story.gathering.take("mio")
	check("the controller uses a real collision route and records receiving rather than eating", SummerGathering.current().served.has("mio") and int(SummerGathering.current().remaining) == 2 and not SummerGathering.current().served.mio.path.is_empty() and int(SummerGathering.current().self_eaten) == 0)
	check("duplicate receiving leaves the finite serving count unchanged", SummerGathering.take("mio",proof(target),target) != "" and int(SummerGathering.current().remaining) == 2)
	G.day = 18
	check("a previous night's basket cannot be received as today's event", SummerGathering.take("haru",proof(target),target) != "" and int(SummerGathering.state().sessions.festival.remaining) == 2)
	check("actual old-night leftovers can be packed without a forced extra recipient", SummerGathering.cleanup("festival") == "" and G.count(SummerGathering.leftover_id("festival")) == 2 and SummerGathering.state().sessions.festival.closed)
	check("packing again cannot duplicate food", SummerGathering.cleanup("festival") != "" and G.count(SummerGathering.leftover_id("festival")) == 2)
	check("summer leftovers are normal storable food with their own provenance", G.store_in(SummerGathering.leftover_id("festival"),1) and G.count(SummerGathering.leftover_id("festival")) == 1)
	DailyLife.eat_food(SummerGathering.leftover_id("festival"))
	check("eating summer leftovers never increments the first market's eaten count", int(SummerGathering.state().sessions.festival.self_eaten) == 1 and int(SummerProjects.opening().service.self_eaten) == 0)
	fixture()
	SummerGathering.prepare("bite","paper","shop",true)
	G.bag_cap = 1
	G.add_item("onigiri",1,true)
	check("a full bag leaves all unpacked food on the table", SummerGathering.cleanup("festival") != "" and int(SummerGathering.current().remaining) == 3 and not SummerGathering.current().closed)
	G.remove_item("onigiri",1)
	check("after making space, exactly the real three remaining servings can be packed", SummerGathering.cleanup("festival") == "" and G.count(SummerGathering.leftover_id("festival")) == 3)
	fixture()
	G.day = 18
	G.minute = 18 * 60
	check("reunion requires the real partner's agreement", SummerGathering.agree_reunion(false) != "" and SummerGathering.context() == "")
	check("an explicit new evening has its own identity without original festival attendance", SummerGathering.agree_reunion(true) == "" and SummerGathering.context() == "reunion" and not G.flags.get("summer_attended",false) and not G.flags.get("fest_bon_odori",false))
	WorkshopProject.start("plan","meeting","leaf")
	var lamp_view: WorkroomView = main.world.interiors.workroom.get_node("WorkroomProject")
	await t.frames(3)
	WorkshopProject.record_trial(lamp_view.trial())
	WorkshopProject.retain()
	var identity: String = WorkshopProject.state().work_id
	var began: String = WorkshopProject.begin_site()
	await t.frames(3)
	var measured: Dictionary = lamp_view.trial(true)
	check("a late work is physically installed during the explicit reunion", began == "" and WorkshopProject.install(measured) == "" and WorkshopProject.state().installed.context == "reunion" and WorkshopProject.state().installed.work_id == identity and is_instance_valid(lamp_view.festival_lantern))
	SummerGathering.prepare("bite","paper","shop",true)
	SummerGathering.cleanup("reunion")
	await t.frames(3)
	check("cleanup stores exactly the same work and retains its real use history", WorkshopProject.state().stored and WorkshopProject.state().work_id == identity and WorkshopProject.state().installed.is_empty() and WorkshopProject.state().use_history.size() == 1 and is_instance_valid(lamp_view.specimen) and not is_instance_valid(lamp_view.festival_lantern) and not is_instance_valid(lamp_view.trial_lantern))
	var recovered: Dictionary = SummerGathering.state().duplicate(true)
	G.save_game()
	G.flags.clear()
	G.load_game()
	main._restore()
	await t.frames(3)
	check("SQLite restores the distinct sessions, counts and one stored work", SummerGathering.state() == recovered and WorkshopProject.state().work_id == identity and WorkshopProject.state().stored and is_instance_valid(lamp_view.specimen))
	var legacy: Dictionary = WorkshopProject.state().duplicate(true)
	legacy.erase("use_history")
	legacy.installed = {"work_id":identity,"day":17,"place":"festival","revision":"legacy-confirmed","lit":true,"clear":true,"readable":true}
	legacy.site_preview = true
	legacy.stored = false
	G.flags.summer_workshop = legacy
	WorkshopProject.stow()
	check("storing an old installed work archives its existing fact without inventing missing context", WorkshopProject.state().use_history.size() == 1 and WorkshopProject.state().use_history[0].place == "festival" and int(WorkshopProject.state().use_history[0].day) == 17 and not WorkshopProject.state().use_history[0].has("context") and WorkshopProject.state().work_id == identity)
	fixture()
	SummerSpace.state().phase = "arranging"
	PlacementSystem.project_context = "space"
	G.add_item("picnic_table",1,true)
	var table_uid: int = G.add_placement("picnic_table",2.5,19,0)
	PlacementSystem.project_context = ""
	SummerSpace.state().table_uid = -1
	main.placement.rebuild()
	await t.frames(3)
	if OS.get_cmdline_user_args().has("--gathering-debug"):
		var model: Node3D=main.story.gathering.view.table()
		var sample: Array=[]
		for ix: int in range(-3,4):
			for iz: int in range(-3,4):
				var at: Vector3=model.global_position+Vector3(ix*.15,0,iz*.15)
				sample.append([ix*.15,iz*.15,WorldBuilder.rendered_support_height(model,at,1.5,true)])
		print("GATHERING_TABLE_DEBUG ",JSON.stringify({"origin":str(model.global_position),"bounds":str(model.global_transform*WorldBuilder.local_aabb(model)),"sample":sample}))
	check("a unique self-owned project table is shared without requiring a redundant manual target selection", int(SummerSpace.furniture("picnic_table").uid) == table_uid and main.story.gathering.view.table() == main.placement.placed_nodes[table_uid] and main.story.gathering.view.surface().is_finite())
	SummerGathering.prepare("bite","paper","shop",true)
	main.story.gathering.view.sync_state()
	check("all three rendered servings fit the actual narrow tabletop rather than the surrounding benches",servings_supported(main.placement.placed_nodes[table_uid]))
	for placement: Dictionary in G.placements:
		if int(placement.uid)==table_uid:placement.rot=1
	main.placement.rebuild();await t.frames(3);main.story.gathering.view.sync_state()
	check("quarter-turning the same table still supports every serving perimeter",servings_supported(main.placement.placed_nodes[table_uid]))
	PlacementSystem.project_context = "space"
	G.add_item("bench",2,true)
	var chosen_bench: int = G.add_placement("bench",-9.5,23.5,2)
	G.add_placement("bench",6.5,23.5,2)
	PlacementSystem.project_context = ""
	SummerSpace.state().bench_uid = chosen_bench
	check("an unrelated nearby bench cannot replace the selected watching place in a plate plan", not SummerGathering.plate_ready())
	G.day = 18
	SummerGathering.agree_reunion(true)
	SummerSpace.state().invited["mio"] = G.day
	SummerSpace.record("mio",proof(SummerSpace.DEMO),true)
	check("space reuse shares the explicit reunion activity identity without original attendance", SummerSpace.state().application.context == "reunion" and SummerSpace.state().application.activity_id == "reunion:18" and not G.flags.get("summer_attended",false))
	G.from_dict(original.duplicate(true))
	G.clock_paused = true
	main.ui.instant = instant
	main.placement.rebuild()
	main._restore()

func servings_supported(model: Node3D) -> bool:
	var roots: Array=main.story.gathering.view.food.get_children()
	if roots.size()!=3:return false
	var centres: Array[Vector3]=[]
	for root: Node3D in roots:
		var container: MeshInstance3D=root.get_node_or_null("Container")
		if container==null:return false
		var bounds: AABB=container.global_transform*container.get_aabb()
		centres.append(bounds.get_center())
		for x: float in [bounds.position.x,bounds.end.x]:
			for z: float in [bounds.position.z,bounds.end.z]:
				var at:=Vector3(x,0,z)
				var height: float=WorldBuilder.rendered_support_height(model,at,1.5,true)
				if not is_finite(height) or absf(height-bounds.position.y)>.025:return false
	for i: int in centres.size():
		for j: int in range(i+1,centres.size()):
			if centres[i].distance_to(centres[j])<.28:return false
	return true

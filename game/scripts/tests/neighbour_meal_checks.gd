extends RefCounted
var t: Node
var main: Node
var G: Node
func _init(runner: Node) -> void:t=runner;main=runner.main;G=GameState
func check(label: String,ok: bool,detail: String="") -> void:t.check("NEIGHBOUR_MEAL",label,ok,detail)
func fixture() -> void:
	G.new_game();G.clock_paused=true;G.day=4;G.minute=12*60;G.quests.Q00={"state":"done","step":2}
	DailyLife.event("tea").state="done";DailyLife.event("tea").drank=true;DailyLife.event("tea").completed_day=2
	main.world.set_region("town");main.in_room=false;G.player_in_room=false
	main.npcs.haru.set_home(false);main.npcs.haru.place(Vector3(14.6,0,16.1),0);main.player.global_position=Vector3(15.1,.05,16.65)
	G.state_changed.emit()
func run() -> void:
	var original: Dictionary=G.to_dict().duplicate(true);var instant: bool=main.ui.instant;main.ui.instant=true
	fixture()
	if OS.get_cmdline_user_args().has("--survey-neighbour"):
		var grid: Array=[]
		var model: Node3D=main.world.get_node("P08")
		for xx: float in [15.2,15.4,15.6,15.8,16.0,16.2,16.4,16.6]:
			for zz: float in [14.6,14.8,15.0,15.2,15.4,15.6,15.8]:
				var at_grid:=Vector3(xx,0,zz)
				var hh: float=WorldBuilder.rendered_support_height(model,at_grid)
				var bounds: Array=[]
				for offset: Vector3 in [Vector3(-.10,0,-.10),Vector3(.10,0,-.10),Vector3(-.10,0,.10),Vector3(.10,0,.10)]:bounds.append(WorldBuilder.rendered_support_height(model,at_grid+offset))
				grid.append({"x":xx,"z":zz,"h":hh,"corners":bounds})
		var survey:=FileAccess.open("/Users/jack/workpath/research/3D model/anime/evidence/summer_reciprocal_20261006/surface-survey.json",FileAccess.WRITE);survey.store_string(JSON.stringify(grid,"  "));return
	check("the invitation comes from real tea without farming hearts or a random request",NeighbourMeals.can_offer() and G.qstate("Q06")!="done" and G.request().is_empty())
	check("unknown preparation variants are absent from the kitchen while the ordinary pickle recipe stays known",not G.recipes_db.has("haru_thin_pickles") and G.recipe_known("pickles"))
	var at: Vector3=main.story.neighbours.view.surface()
	check("the new bowl uses another real surface without covering the earlier tea-side food",at.is_finite() and at.distance_to(main.story.gathering.view.tea_surface())>=.39,str(at))
	NeighbourMeals.defer()
	check("deferring neither accepts a hidden project nor awards food",not NeighbourMeals.can_offer() and NeighbourMeals.current().is_empty() and NeighbourMeals.state().learned.is_empty())
	G.day+=1;NeighbourMeals.invite(true)
	var entry: Dictionary=NeighbourMeals.current();var id: String=entry.id
	check("Haru contributes an explicit finite batch while the player's inventory stays empty",entry.haru_materials.cucumber==2 and entry.haru_materials.salt==1 and entry.player_materials.is_empty() and G.count("cucumber")==0)
	check("the same starter invitation cannot generate another free batch",NeighbourMeals.invite(true)!="" and NeighbourMeals.state().sessions.size()==1)
	NeighbourMeals.start("prepare","thin",true);NeighbourMeals.cut(1)
	check("unfinished preparation cannot become two ready portions or a learned recipe",NeighbourMeals.finish(true)!="" and entry.remaining==0 and not G.recipe_known("haru_thin_pickles"))
	var before_restore: Dictionary=NeighbourMeals.state().duplicate(true)
	G.save_game();G.flags.clear();G.load_game();entry=NeighbourMeals.current()
	check("the complete finite-source state survives a SQLite round trip without numeric changes",JSON.stringify(before_restore)==JSON.stringify(NeighbourMeals.state()))
	check("SQLite restores the same half-prepared batch and real cutting progress",entry.id==id and entry.cuts==1 and not entry.salted and entry.remaining==0)
	var prep:=PicklePreparation.new();main.add_child(prep);await prep.run(main.story);prep.queue_free()
	check("the preparation controller finishes the same batch and records player plus Haru authorship",entry.stage=="prepared" and entry.remaining==2 and entry.author=="player_and_haru" and entry.drained and G.recipe_known("haru_thin_pickles"))
	main.story.neighbours.view.sync_state()
	var supported_slices: bool=true
	for portion_index: int in 2:
		var bowl: MeshInstance3D=main.story.neighbours.view.dish.get_node("Bowl_%d"%portion_index)
		var bowl_top: float=(bowl.global_transform*bowl.get_aabb()).end.y
		for slice_index: int in 3:
			var slice: MeshInstance3D=main.story.neighbours.view.dish.get_node("Cucumber_%d_%d"%[portion_index,slice_index])
			var base: float=(slice.global_transform*slice.get_aabb()).position.y
			if base<bowl_top-.001 or base>bowl_top+.003:supported_slices=false
	check("all thin cucumber pieces rest on their own bowls instead of floating above them",supported_slices)
	main.ui.dialogue_end()
	check("completion cannot be pressed again to create another two portions",NeighbourMeals.finish(true)!="" and entry.remaining==2)
	check("player cannot receive before Haru is actually at the shared meal",NeighbourMeals.take("pack",true)!="" and not entry.player_received)
	await t.use("life_tea",[0])
	await t.frames(3)
	check("two abstract table meals consume exactly the same two portions",entry.npc_ate and entry.player_ate and entry.remaining==0 and entry.known_by_haru and G.count(NeighbourMeals.gift_id(entry))==0)
	check("the story meal restores input camera and modal state",not G.input_locked() and main.ui.modal=="" and main.get_viewport().get_camera_3d()==main.rig.cam)
	G.add_item("cucumber",2,true);G.add_item("salt",1,true)
	check("the learned thin preparation really uses one cucumber and salt for two small portions",G.craft("haru_thin_pickles")=="" and G.count("cucumber")==1 and G.count("salt")==0 and G.count("haru_thin_pickles")==2)
	DailyLife.eat_food("haru_thin_pickles")
	check("private use of the learned preparation does not tell Haru",NeighbourMeals.state().own.haru_thin_pickles.eaten==1 and NeighbourMeals.state().shared.is_empty())
	await main.story.neighbours.own_meal()
	check("an actual cup-side use of one's own food gives Haru only that current knowledge",G.count("haru_thin_pickles")==0 and NeighbourMeals.state().shared.haru_thin_pickles.eaten==1)
	G.add_item("cucumber",1,true);G.add_item("salt",1,true);G.craft("haru_thin_pickles")
	check("cooking another normal batch preserves the earlier actual meal history",NeighbourMeals.state().own.haru_thin_pickles.made==4 and NeighbourMeals.state().own.haru_thin_pickles.eaten==2)
	var meal_history: Dictionary=NeighbourMeals.state().duplicate(true)
	G.save_game();G.flags.clear();G.load_game()
	check("learned methods material sources and private versus witnessed history all round-trip unchanged",JSON.stringify(meal_history)==JSON.stringify(NeighbourMeals.state()))
	main.npcs.haru.set_home(true)
	check("a partner leaving cannot finish a shared meal or produce a success fact",main.story.neighbours.finish_own("haru_thin_pickles")!="" and G.count("haru_thin_pickles")==2 and NeighbourMeals.state().shared.haru_thin_pickles.eaten==1)
	fixture()
	G.daily.request={"who":"haru","item":"cucumber","n":3,"reward":50,"done":false,"issued_day":4};G.add_item("cucumber",3,true)
	G.fulfil_request("haru")
	entry=NeighbourMeals.current()
	check("the paid request records actual delivered cucumber sources rather than copying them",entry.source=="player_request" and entry.player_materials.cucumber==2 and entry.haru_kept_raw==1 and entry.haru_materials.cucumber==0 and G.count("cucumber")==0)
	NeighbourMeals.record_request(G.request())
	check("one request receipt cannot create duplicate return gifts",NeighbourMeals.state().sessions.size()==1)
	NeighbourMeals.start("watch","chunk",true)
	check("watching cannot credit unseen cooking before Haru processes the real tabletop batch",NeighbourMeals.finish(true)!="" and entry.remaining==0)
	await main.story.neighbours.view.watch_prepare();NeighbourMeals.finish(true)
	check("watching teaches the selected preparation while preserving Haru authorship",entry.author=="haru" and G.recipe_known("haru_chunk_pickles") and not G.recipe_known("haru_thin_pickles"))
	check("a missing resident cannot be recorded as having eaten",NeighbourMeals.eat_haru(false)!="" and not entry.npc_ate)
	NeighbourMeals.eat_haru(true)
	G.bag_cap=1;G.add_item("rice",1,true)
	check("full inventory leaves the same player portion at the table",NeighbourMeals.take("pack",true)!="" and entry.remaining==1 and not entry.player_received)
	G.remove_item("rice",1);NeighbourMeals.take("pack",true)
	check("packing transfers one finite small side dish and cannot be repeated",G.count(NeighbourMeals.gift_id(entry))==1 and entry.remaining==0 and NeighbourMeals.take("pack",true)!="")
	DailyLife.eat_food(NeighbourMeals.gift_id(entry))
	check("taking a return gift home does not give Haru private eating knowledge",entry.player_ate and not entry.known_by_haru and G.count(NeighbourMeals.gift_id(entry))==0)
	fixture();G.daily.request={"who":"haru","item":"komatsuna","n":1,"reward":50,"done":false,"issued_day":4};G.add_item("komatsuna",1,true);G.fulfil_request("haru")
	check("other vegetables do not silently turn into cucumber pickles",NeighbourMeals.state().sessions.is_empty() and not main.story.farm._thanks("haru","komatsuna").contains("腌"))
	var old: Dictionary=G.to_dict().duplicate(true);old.flags.erase("neighbour_meals");old.flags.requests_done=99
	G.from_dict(old)
	check("old request totals cannot invent a promised meal or returned dish",NeighbourMeals.state().sessions.is_empty() and NeighbourMeals.state().learned.is_empty())
	fixture();NeighbourMeals.defer()
	await t.use("life_tea",[0,0,1,0,1])
	check("actively returning to the tray can resume a deferred invitation on the same day",G.day==4 and NeighbourMeals.state().starter_offered and NeighbourMeals.state().sessions[0].player_received)
	fixture();G.recipes_known.plain_onigiri=true;FoodPurpose.next_meal("parallel","tea");G.add_item("rice",2,true);G.add_item("salt",1,true);G.craft(FoodPurpose.NEXT_RECIPE)
	await t.use("life_tea",[0,0,1,0,1])
	check("an existing rice plan is a parallel choice rather than a prerequisite for Haru's invitation",NeighbourMeals.state().starter_offered and NeighbourMeals.state().sessions[0].player_received and G.count(FoodPurpose.NEXT_PORTION)==2)
	var returned: Dictionary=NeighbourMeals.state().sessions[0]
	await t.use("life_tea",[0,0])
	check("the packed return gift remains selectable beside the untouched rice plan",returned.player_ate and returned.known_by_haru and G.count(FoodPurpose.NEXT_PORTION)==2)
	fixture();NeighbourMeals.invite(true);NeighbourMeals.start("watch","thin",true)
	for step: int in [1,2,3]:NeighbourMeals.observe_step(step,true)
	NeighbourMeals.finish(true);NeighbourMeals.eat_haru(true);NeighbourMeals.take("eat",true)
	G.add_item("onigiri",1,true)
	await t.use("life_tea",[0])
	var ordinary_shared: bool=G.count("onigiri")==0 and NeighbourMeals.state().shared.has("onigiri")
	check("an ordinary carried rice ball can actually be eaten at the reused table without another story batch",ordinary_shared and NeighbourMeals.state().sessions.size()==1)
	if not ordinary_shared:
		G.from_dict(original.duplicate(true));G.clock_paused=true;main.ui.instant=instant;main._restore();return
	G.add_item("melon_pan",2,true)
	var normal_chat: bool=await main.story.neighbours.visit()
	check("ordinary carried food does not turn every Haru chat into another meal menu",not normal_chat and G.count("melon_pan")==2)
	main.npcs.haru.set_home(true)
	var history: Dictionary=NeighbourMeals.state().shared.duplicate(true)
	await t.use("shared_meal_table",[0])
	check("the table also supports a real ordinary meal alone without Haru or extra free food",G.count("melon_pan")==1 and NeighbourMeals.state().shared==history and NeighbourMeals.state().sessions.size()==1 and int(G.daily.meals)==3)
	check("an ordinary meal uses a spare place and returns camera input and dialogue",main.story.neighbours.view.last_meal_surface.distance_to(main.story.neighbours.view.surface())>.35 and not main.story.busy and not G.input_locked() and main.get_viewport().get_camera_3d()==main.rig.cam)
	var solo_count: int=G.count("melon_pan")
	main.player.global_position=Vector3.ZERO
	check("leaving the table before commit preserves the selected ordinary food",str(main.story.neighbours.call("finish_table","melon_pan"))!="" and G.count("melon_pan")==solo_count)
	main.player.global_position=Vector3(15.1,.05,16.65)
	G.store_in("melon_pan",1)
	check("stored food is not a ghost meal on the table",main.story.neighbours.own_foods().is_empty())
	DailyLife.event("meal").cooked=true;G.add_item("onigiri",2,true)
	check("the ordinary table never consumes the protected first-meal portions",not main.story.neighbours.own_foods().has("onigiri") and str(main.story.neighbours.call("finish_table","onigiri"))!="" and G.count("onigiri")==2)
	G.save_game();var shared_snapshot: Dictionary=NeighbourMeals.state().shared.duplicate(true)
	G.flags.clear();G.load_game()
	check("ordinary public eating knowledge persists without inventing recipe or cooking authorship",NeighbourMeals.state().shared==shared_snapshot and not NeighbourMeals.state().own.has("onigiri"))
	fixture();NeighbourMeals.state().declined=true;NeighbourMeals.commit();G.add_item("onigiri",1,true)
	await t.use("life_tea",[0])
	check("declining the return meal still permits an ordinary meal on a real visible table without a free batch",main.story.neighbours.view.table_model.visible and G.count("onigiri")==0 and NeighbourMeals.state().sessions.is_empty())
	fixture();var old_tea: Dictionary=G.to_dict().duplicate(true);old_tea.flags.erase("neighbour_meals");G.from_dict(old_tea);G.add_item("onigiri",1,true)
	await t.use("life_tea",[1,0])
	check("a tea-complete old save can use the actual table without inventing a past return meal",main.story.neighbours.view.table_model.visible and G.count("onigiri")==0 and NeighbourMeals.state().sessions.is_empty() and not NeighbourMeals.state().starter_offered)
	G.add_item("melon_pan",1,true);main.story.neighbours.view.table_model.hide()
	check("cached support on a hidden table cannot commit a shared meal",main.story.neighbours.finish_own("melon_pan")!="" and G.count("melon_pan")==1)
	G.from_dict(original.duplicate(true));G.clock_paused=true;main.ui.instant=instant;main._restore()

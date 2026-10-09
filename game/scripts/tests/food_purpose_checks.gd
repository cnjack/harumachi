extends RefCounted
var t: Node
var main: Node
var G: Node
func _init(runner: Node) -> void: t=runner;main=runner.main;G=GameState
func check(name: String,ok: bool,detail: String="") -> void: t.check("FOOD_PURPOSE",name,ok,detail)
func fixture() -> Dictionary:
	G.new_game();G.clock_paused=true;G.day=17;G.minute=19*60
	G.quests.Q00={"state":"done","step":2};G.quests.Q05={"state":"done","step":5};G.quests.Q11={"state":"done","step":3};G.quests.Q14={"state":"done","step":3}
	var prior: Dictionary=SummerProjects.opening();prior.phase="applied";prior.followup=false
	prior.final={"menu":"sandwich","portion":"bite","presentation":"paper","trial_batch":1,"recipe":"veg_sandwich","decided_day":3}
	prior.service={"remaining":0,"served":{"mio":3},"packed":2,"self_eaten":0,"day":3,"trial_batch":1,"source":"shop","ingredients":{}}
	main.world.set_region("town");main.world.sync_festivals();main.in_room=false;G.player_in_room=false;main.placement.rebuild()
	main.player.global_position=Vector3(8.5,.05,11.55)
	main.npcs.haru.set_home(false);main.npcs.haru.place(Vector3(6,0,13),0)
	main.npcs.ren.set_home(false);main.npcs.ren.place(Vector3(7,0,13),0)
	SummerGathering.prepare("bite","paper","shop",true)
	return SummerGathering.current()
func proof(target: Vector3) -> Dictionary:
	return {"present":true,"arrived":true,"revision":SummerSpace.revision(),"position":{"x":target.x,"y":target.y,"z":target.z},"crossed_dance":false}
func run() -> void:
	var original: Dictionary=G.to_dict().duplicate(true)
	var instant: bool=main.ui.instant;main.ui.instant=true
	var entry: Dictionary=fixture()
	check("new basket contains exactly three unique serving identities",FoodPurpose.units(entry).size()==3 and FoodPurpose.units(entry).map(func(u:Dictionary):return u.id).duplicate().size()==3 and entry.units[0].id!=entry.units[1].id)
	check("a real first-market receipt creates a Ren followup even when the old finish boolean is false",not SummerProjects.opening().followup and main.story.food_use.handles("opening_paper"))
	check("an absent person cannot agree to a named destination",FoodPurpose.plan(entry,"haru","tea","drain_wrap",false)!="" and entry.units.all(func(u:Dictionary):return u.target==""))
	check("a destination cannot silently substitute another person's stated purpose",FoodPurpose.plan(entry,"haru","home","tray",true)!="" and entry.units.all(func(u:Dictionary):return u.target==""))
	FoodPurpose.plan(entry,"haru","tea","drain_wrap",true)
	FoodPurpose.plan(entry,"ren","later","tray",true)
	FoodPurpose.plan(entry,"self","home","drain_wrap",true)
	check("three uses reserve the same three servings without consuming or creating materials",int(entry.remaining)==3 and entry.units.size()==3 and entry.units.all(func(u:Dictionary):return u.state=="reserved"))
	var surface: Vector3=main.story.gathering.view.surface()
	var tea: Vector3=main.story.gathering.view.tea_surface()
	check("the tea destination uses a separate real supported space beside the cup tray",tea.is_finite() and tea.y>.35 and tea.distance_to(main.story.daily.view.tea_root.global_position)>.35,str(tea))
	check("a public guest cannot take portions promised to other uses",SummerGathering.take("mio",proof(main.story.gathering.view.stop()),main.story.gathering.view.stop())!="" and int(entry.remaining)==3)
	var nodes: Array=main.story.gathering.view.food.get_children()
	check("two preparations render visibly different split wrapping and plate juice",nodes.any(func(n:Node):return n.get_node_or_null("FoldedPaperBand")!=null) and nodes.any(func(n:Node):return n.get_node_or_null("JuiceOnPlate")!=null))
	check("the explicitly self-kept portion becomes one real bag portion",FoodPurpose.claim_self(entry)=="" and int(entry.remaining)==2 and G.count(SummerGathering.leftover_id("festival"))==1)
	check("self collection cannot be repeated or reassigned as a fresh fourth serving",FoodPurpose.claim_self(entry)!="" and FoodPurpose.plan(entry,"self","home","tray",true)!="" and G.count(SummerGathering.leftover_id("festival"))==1)
	var target: Vector3=main.story.gathering.view.stop()
	SummerGathering.take("haru",proof(target),target)
	var unit: Dictionary=FoodPurpose.owned(entry,"haru");var identity: String=unit.id
	check("receipt binds the reserved identity and only subtracts one table serving",unit.state=="held" and int(entry.remaining)==1 and entry.served.haru.unit_id==identity)
	var interrupted: String=FoodPurpose.place(entry,"haru",{"arrived":false,"supported":true,"present":true})
	check("interrupted destination walk preserves held food rather than returning it to the public table",interrupted!="" and unit.state=="held" and int(entry.remaining)==1)
	check("an arrival boolean without a real cup-side standing and route cannot place food",FoodPurpose.place(entry,"haru",{"arrived":true,"supported":true,"present":true})!="" and unit.state=="held")
	await main.story.food_use.haru_followup(entry)
	check("an interrupted held portion cannot be described as already placed or unlock the next meal",not FoodPurpose.was_presented(entry,"haru") and FoodPurpose.followup_state().next.is_empty())
	G.save_game();G.flags.clear();G.load_game();entry=SummerGathering.current()
	check("SQLite restores the same held serving without a duplicate or fictional placement",FoodPurpose.owned(entry,"haru").id==identity and FoodPurpose.owned(entry,"haru").state=="held" and int(entry.remaining)==1)
	main.npcs.haru.place(target,0)
	await main.story.food_use.tea_use(entry)
	unit=FoodPurpose.owned(entry,"haru")
	check("the second real collision route places the same serving on the tea surface",unit.state=="placed" and unit.use.place=="tea" and not unit.use.path.is_empty() and not unit.use.eaten and not unit.use.drank,JSON.stringify(unit.use))
	main.story.gathering.view.sync_state()
	var old_meal: Vector3=main.story.gathering.view.tea_surface()
	var spare_meal: Vector3=main.story.gathering.view.spare_tea_surface()
	check("a new rice plate has a supported clear patch beside today's retained serving",spare_meal.is_finite() and Vector2(spare_meal.x-old_meal.x,spare_meal.z-old_meal.z).length()>=.24,"old=%s new=%s"%[old_meal,spare_meal])
	check("placing again cannot make another portion or fake eating",FoodPurpose.place(entry,"haru",{"arrived":true,"supported":true,"present":true})!="" and int(entry.remaining)==1)
	check("Ren is still only promised food until actual receipt",not entry.served.has("ren") and FoodPurpose.eligible(entry,"ren").state=="reserved")
	SummerGathering.cleanup("festival")
	check("closing the basket preserves one placed serving and exactly two packed portions",int(entry.packed)==2 and G.count(SummerGathering.leftover_id("festival"))==2 and FoodPurpose.owned(entry,"haru").state=="placed")
	DailyLife.eat_food(SummerGathering.leftover_id("festival"))
	check("private leftover eating does not disclose facts to Ren or Kazuko",FoodPurpose.followup_state().disclosed.is_empty() and not FoodPurpose.owned(entry,"haru").use.eaten)
	G.recipes_known.plain_onigiri=true
	FoodPurpose.next_meal(identity,"home")
	check("one optional next-meal intent uses a learned ordinary recipe without free ingredients",G.recipe_known(FoodPurpose.NEXT_RECIPE) and G.count("rice")==0 and G.craft(FoodPurpose.NEXT_RECIPE)!="")
	G.add_item("rice",2,true);G.add_item("salt",1,true)
	check("cooking the planned next meal consumes real materials and produces one batch of two",G.craft(FoodPurpose.NEXT_RECIPE)=="" and G.count("rice")==0 and G.count("salt")==0 and G.count(FoodPurpose.NEXT_PORTION)==2)
	check("the story meal cannot be crafted a second time or as multiple free batches",G.craft(FoodPurpose.NEXT_RECIPE)!="" and G.craft(FoodPurpose.NEXT_RECIPE,2)!="" and G.count(FoodPurpose.NEXT_PORTION)==2)
	DailyLife.eat_food(FoodPurpose.NEXT_PORTION)
	check("eating one's next meal completes the private choice without giving a resident knowledge",FoodPurpose.followup_state().next.state=="completed_home" and not FoodPurpose.followup_state().next.has("known_by"))
	FoodPurpose.mark_followup(entry,"haru")
	check("a later conversation does not convert an earlier private meal into shared tea",FoodPurpose.followup_state().next.state=="completed_home" and not FoodPurpose.followup_state().next.has("known_by"))
	G.day=18
	check("a previous night's self reservation cannot be collected as today's fresh food",FoodPurpose.claim_self(entry)!="")
	main.story.gathering.view.sync_state()
	check("old placement facts do not leave yesterday's food rendering on today's tea surface",main.story.gathering.view.used_food.get_child_count()==0 and unit.use.placed_day==17)
	entry=fixture()
	check("a future story meal is absent from the stove before anyone has discussed it",not G.recipes_db.has(FoodPurpose.NEXT_RECIPE) and not G.recipe_known(FoodPurpose.NEXT_RECIPE))
	SummerGathering.take("haru",proof(main.story.gathering.view.stop()),main.story.gathering.view.stop())
	check("a default public receipt cannot reserve a second unclaimable serving for the same guest",FoodPurpose.plan(entry,"haru","tea","drain_wrap",true)!="" and int(entry.remaining)==2 and entry.units.filter(func(u:Dictionary):return u.state=="reserved").is_empty())
	entry.erase("units")
	check("legacy food history is not backfilled with fictional serving identities",FoodPurpose.plan(entry,"ren","later","drain_wrap",true)!="" and FoodPurpose.units(entry).is_empty())
	G.recipes_known.plain_onigiri=true
	FoodPurpose.next_meal("deferred","later")
	G.save_game();G.flags.clear();G.load_game()
	check("choosing later survives SQLite and can still become a concrete next meal",FoodPurpose.followup_state().next.choice=="later" and FoodPurpose.next_meal("deferred","tea")=="" and G.recipe_known(FoodPurpose.NEXT_RECIPE))
	G.add_item("rice",2,true);G.add_item("salt",1,true)
	main.ui.instant=false
	main.ui.panels.open_craft("kitchen")
	await t.frames(3)
	for button: Button in main.ui.modal_layer.find_children("*","Button",true,false):
		if button.get_meta("recipe_id","")==FoodPurpose.NEXT_RECIPE and not button.disabled:
			button.pressed.emit()
			break
	check("the actual cooking button reports the correct two named portions after the recipe closes",main.ui.panels._status.text.contains("自己下一顿的盐饭团 ×2") and G.count(FoodPurpose.NEXT_PORTION)==2,main.ui.panels._status.text)
	main.ui.close_modal(false);main.ui.instant=true
	check("the finite meal leaves the stove after actual crafting rather than appearing as a locked repeated task",not G.recipes_db.has(FoodPurpose.NEXT_RECIPE))
	DailyLife.eat_food(FoodPurpose.NEXT_PORTION,true)
	check("a witnessed tea meal records only the one portion actually eaten",FoodPurpose.followup_state().next.state=="completed_tea" and FoodPurpose.followup_state().next.known_by=="haru" and G.count(FoodPurpose.NEXT_PORTION)==1)
	DailyLife.eat_food(FoodPurpose.NEXT_PORTION)
	check("eating the second portion privately preserves the earlier true witness without adding one",FoodPurpose.followup_state().next.state=="completed_tea" and FoodPurpose.followup_state().next.eaten==2)
	await obstacle_walk_check()
	G.from_dict(original.duplicate(true));G.clock_paused=true;main.ui.instant=instant;main.placement.rebuild();main._restore()

func obstacle_walk_check() -> void:
	var entry: Dictionary=fixture()
	FoodPurpose.plan(entry,"haru","tea","drain_wrap",true)
	var target: Vector3=main.story.gathering.view.stop()
	SummerGathering.take("haru",proof(target),target)
	main.npcs.haru.place(target,0)
	main.npcs.ren.place(Vector3(7,0,13),0)
	var old_auto: bool=main.ui.auto
	main.ui.instant=false;main.ui.auto=true;main.story.busy=true;main.player.frozen=true
	await main.story.food_use.tea_use(entry)
	var unit: Dictionary=FoodPurpose.owned(entry,"haru")
	var avoided:=true
	for point: Dictionary in unit.use.get("path",[]):
		if Vector2(float(point.x)-7,float(point.z)-13).length()<.64:avoided=false
	check("the real cup-side walk detours around a standing Ren instead of repeatedly colliding",unit.state=="placed" and avoided and unit.use.get("path",[]).size()>8 and main.npcs.haru.global_position.distance_to(Vector3(14.6,0,16.1))<.2)
	main.ui.auto=old_auto;main.ui.instant=true;main.ui.dialogue_end();main.story.busy=false;main.player.frozen=false

class_name StoryFoodUse
extends RefCounted
var s: Story
func _init(story: Story) -> void: s=story

func handles(id: String) -> bool:
	if id=="food_use": return true
	if id not in ["haru","ren","opening_paper"]: return false
	if s.lore.pending(id) or GameState.phase=="market" and GameState.qstate("Q05")!="done": return false
	if id=="haru":
		var entry: Dictionary=tea_entry()
		return not entry.is_empty() and (FoodPurpose.owned(entry,"haru").state=="held" or not FoodPurpose.was_presented(entry,"haru")) or not SummerGathering.current().is_empty() and not SummerGathering.current().closed
	return GameState.qstate("Q05")=="done" and not SummerProjects.opening().service.get("served",{}).is_empty() and not FoodPurpose.was_presented(SummerProjects.opening().service,"ren")

func prompt(id: String) -> Variant:
	if not handles(id): return null
	return "安排这份食物的用途" if id=="food_use" else "和%s聊这次食物的去向，也可以聊别的" % GameState.npc_display("ren" if id=="opening_paper" else id)

func present(who: String) -> bool:
	var actor: NPC=s.npcs.get(who)
	return actor!=null and not actor.home and actor.is_visible_in_tree() and actor.global_position.distance_to(s.player.global_position)<8

func handle(id: String) -> void:
	if id=="food_use": await arrange();return
	if id in ["ren","opening_paper"]:
		var choice: int=await s.ui.choose(["说说上回那一篮后来怎样了","聊其他事","先不聊这件事"])
		if choice==0: await ren_followup()
		elif choice==1: await other("ren")
		return
	var entry: Dictionary=tea_entry()
	if not entry.is_empty():
		var unit: Dictionary=FoodPurpose.owned(entry,"haru")
		if unit.state=="held":
			var choice: int=await s.ui.choose(["把已经领到的同一份放到麦茶旁","聊其他事","先保管着"])
			if choice==0: await tea_use(entry)
			elif choice==1: await other("haru")
			return
		if not FoodPurpose.was_presented(entry,"haru") or FoodPurpose.followup_state().next.get("choice","")=="later":
			var choice: int=await s.ui.choose(["聊聊上回杯边那一份","聊其他事","之后再聊"])
			if choice==0: await haru_followup(entry)
			elif choice==1: await other("haru")
			return
	var pick: int=await s.ui.choose(["听听这晚怎样用一份食物","聊其他事","先不安排"])
	if pick==1: await other("haru");return
	if pick==2: return
	await s.say("haru","neutral","我想去麦茶旁歇一会儿。给我留一份，放在杯边就好，不用守着摊子吃。")
	await arrange()

func other(who: String) -> void:
	if s.space.handles(who): await s.space.handle(who)
	elif s.lore.pending(who): await s.lore.handle(who)
	else: await s.call("_i_"+who)

func arrange() -> void:
	var entry: Dictionary=SummerGathering.current()
	if entry.is_empty(): await s.say("narrator","","篮里还空着。等莲烤好，再分这三份。") ;return
	var target: int=await s.ui.choose(["给春留一份，带去配茶","给莲留一份，等他忙完","我带一份回家","放桌上，谁来谁拿"])
	if target==3: return
	var who: String=["haru","ren","self"][target]
	if who!="self" and not present(who): await s.say("narrator","","先问问本人想怎么吃。人不在，这一份就先放着。") ;return
	if who=="haru": await s.say("haru","neutral","纸包拿小片省事。想留些汁，就用个盘子托着吧。")
	elif who=="ren": await s.say("ren","neutral","给我封好放桌上吧，烤箱边忙完我就来拿。")
	var prep: int=await s.ui.choose(["沥点汁，切小片，包好","留着汁，用盘子托住","就照现在这样"])
	if prep==2: return
	var why: String=FoodPurpose.plan(entry,who,["tea","later","home"][target],"drain_wrap" if prep==0 else "tray",who=="self" or present(who))
	if why!="": await s.say("narrator","",why);return
	await s.gathering.view.prepare_cut(who,prep==0)
	if who=="self":
		var choose: int=await s.ui.choose(["把我的一份装进背包","先留在桌上"])
		if choose==0:
			var packed: String=FoodPurpose.claim_self(entry)
			await s.say("narrator","",packed if packed!="" else "这一份装进背包了，回家可以放到饭桌上。")
	else:
		await s.say("narrator","","纸包上写好了名字。春的配茶，莲的等他忙完再拿。")

func tea_entry() -> Dictionary:
	var entries: Array=SummerGathering.state().sessions.values()
	entries.sort_custom(func(a:Dictionary,b:Dictionary):return int(a.day)>int(b.day))
	for entry: Dictionary in entries:
		var unit: Dictionary=FoodPurpose.owned(entry,"haru")
		if not unit.is_empty() and unit.purpose=="tea" and unit.state=="held": return entry
	for entry: Dictionary in entries:
		var unit: Dictionary=FoodPurpose.owned(entry,"haru")
		var next: Dictionary=FoodPurpose.followup_state().next
		if not unit.is_empty() and unit.purpose=="tea" and (not FoodPurpose.was_presented(entry,"haru") or next.get("choice","")=="later" and next.get("origin","")==unit.id): return entry
	return {}

func tea_use(entry: Dictionary) -> void:
	if not present("haru"): await s.say("narrator","","春这会儿不在附近。饭菜在她那儿，下次见面再问问。") ;return
	var actor: NPC=s.npcs.haru
	var surface: Vector3=s.gathering.view.tea_surface()
	if not surface.is_finite(): await s.say("narrator","","杯边放满了东西，先腾一点地方。饭菜还收着。") ;return
	var stop:=Vector3(14.6,0,16.1)
	var circles: Array=[[SummerSpace.DANCE_CENTER,SummerSpace.DANCE_RADIUS]] if SummerGathering.context()=="festival" else []
	var path: Array[Vector3]=NPC.MOTION_ROUTE.query(actor,actor.global_position,stop,circles)
	if path.is_empty():await s.say("narrator","","去杯边的路有人挡着，等空出来再过去。") ;return
	var speed: float=actor.speed;actor.speed=1.8;actor.set_talking(true)
	s.space.view.begin_walk(actor);s.ui.dlg.hide()
	var arrived:=true
	if s.ui.instant:
		actor.place(stop,0);s.space.view.trace.clear()
		for point: Vector3 in path: s.space.view.trace.append(point)
	else: arrived=await actor.walk_safe(path)
	s.ui.dialogue_begin()
	var result: Dictionary={"arrived":arrived and not s.space.view.aborted,"present":not actor.home and actor.is_visible_in_tree(),"supported":s.gathering.view.tea_surface().is_finite(),"position":{"x":surface.x,"y":surface.y,"z":surface.z},"standing":{"x":actor.global_position.x,"y":actor.global_position.y,"z":actor.global_position.z},"path":[]}
	for point: Vector3 in s.space.view.trace: result.path.append({"x":point.x,"y":point.y,"z":point.z})
	s.space.view.end_walk();actor.speed=speed;actor.set_talking(false)
	var why: String=FoodPurpose.place(entry,"haru",result)
	if OS.get_cmdline_user_args().has("--route-debug"):
		print("FOOD_ROUTE_DEBUG ",JSON.stringify({"reason":why,"result":result,"motion":actor.get_meta("motion_reason",""),"player":str(s.player.global_position)}))
	if why!="": await s.say("narrator","",why);return
	await s.gathering.view.show_tea()
	await s.say("haru","happy","放我茶杯旁吧，来喝茶就不用回摊子拿了。")
	await s.say("narrator","","春在麦茶旁停下来，把这一份放到杯边。夜风吹过来，纸包轻轻响了一下。")

func haru_followup(entry: Dictionary) -> void:
	if not present("haru"): return
	var unit: Dictionary=FoodPurpose.owned(entry,"haru")
	if unit.is_empty() or unit.state!="placed" or unit.use.get("place","")!="tea": return
	await s.say("haru","neutral","上回那份放在杯边，我歇着的时候也不用守在摊前。你照自己的打算留剩下的，就挺好。")
	if FoodPurpose.followup_state().next.is_empty() or FoodPurpose.followup_state().next.choice=="later":
		var known: bool=GameState.recipe_known("plain_onigiri")
		var choice: int=await s.ui.choose(["下一顿用自己会的饭团，在家吃" if known else "先回家看看米盐便笺，学自己的饭","下次带自己做的饭团来配茶","之后再想","我先不安排下一顿"])
		var why: String=FoodPurpose.next_meal(str(FoodPurpose.owned(entry,"haru").id),["home","tea","later","none"][choice])
		if why!="": await s.say("narrator","",why)
	FoodPurpose.mark_followup(entry,"haru")

func ren_followup() -> void:
	if not present("ren"): return
	var entry: Dictionary=SummerProjects.opening().service
	await s.say("ren","neutral","上回那一篮，后来怎么安排的？我只顾着烤，还没听你说。")
	var people: Array[String]=[]
	for who: String in entry.served: people.append(GameState.npc_display(who))
	var choices: Array[String]=["给了"+"、".join(people)]
	if int(entry.get("packed",0))>0: choices.append("剩下%d份，我包好了"%int(entry.packed))
	if int(entry.get("self_eaten",0))>0: choices.append("包好的那份，我自己吃了")
	choices.append("这件事以后再聊")
	var selected: int=await s.ui.choose(choices)
	if selected==choices.size()-1: return
	FoodPurpose.followup_state().disclosed[FoodPurpose.followup_key(entry,"ren")]={"day":GameState.day,"source":"player","text":choices[selected]}
	await s.say("ren","happy","哦，原来是这样。下次想做，来借烤箱就行。材料照配方带，我给你腾位置。")
	FoodPurpose.mark_followup(entry,"ren")

func own_meal_at_tea() -> void:
	if not present("haru") or not GameState.has(FoodPurpose.NEXT_PORTION): return
	var actor: NPC=s.npcs.haru
	if actor.global_position.distance_to(Vector3(14.6,0,16.1))>2.8:
		await s.say("narrator","","春还没在杯边，饭团先留着，等她实际来歇脚。")
		return
	var was_talking: bool=actor.talking
	actor.set_talking(true)
	var why: String=await s.gathering.view.eat_at_tea(s.player,FoodPurpose.NEXT_PORTION)
	var together: bool=present("haru") and actor.global_position.distance_to(Vector3(14.6,0,16.1))<=2.8
	actor.set_talking(was_talking)
	if why!="": await s.say("narrator","",why);return
	if not together: await s.say("narrator","","杯边已经没人，饭团还留在原处，之后再决定。") ;return
	var eaten: String=DailyLife.eat_food(FoodPurpose.NEXT_PORTION,true)
	if eaten!="": await s.say("narrator","",eaten);return
	await s.say("haru","happy","自己的饭团配茶，也很好。今天就在这儿歇一会儿，不用再添什么事。")

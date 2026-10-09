class_name StoryNeighbourMeals
extends RefCounted
var s: Story
var view: NeighbourMealView

func _init(story: Story) -> void:s=story
func build() -> void:
	view=NeighbourMealView.new();s.main.add_child(view);view.setup(s)

func present() -> bool:
	var actor: NPC=s.npcs.get("haru")
	return actor!=null and not actor.home and actor.is_visible_in_tree() and s.world.region=="town" and actor.global_position.distance_to(s.player.global_position)<8

func at_table() -> bool:
	var actor: NPC=s.npcs.get("haru")
	return table_available() and actor!=null and not actor.home and actor.is_visible_in_tree() and actor.global_position.distance_to(Vector3(14.6,0,16.1))<.8 and s.player.global_position.distance_to(view.surface())<3.2

func visit(explicit: bool=false) -> bool:
	if not present() or not explicit and s.lore.pending("haru") or GameState.phase=="market" and GameState.qstate("Q05")!="done": return false
	var entry: Dictionary=NeighbourMeals.current()
	if entry.is_empty() and not NeighbourMeals.can_offer():
		if explicit and NeighbourMeals.can_offer(true) and NeighbourMeals.state().deferred_day==GameState.day:
			var resume: int=await s.ui.choose(["现在看看春的一碗小菜","这会儿先不看","聊其他事"])
			if resume==2:return false
			if resume==1:return true
			NeighbourMeals.state().deferred_day=-1;NeighbourMeals.commit()
		else:return await own_meal(false)
	var actor: NPC=s.npcs.haru;var was_talking: bool=actor.talking;actor.set_talking(true)
	var handled: bool=await visit_inner()
	actor.set_talking(was_talking)
	return handled

func visit_inner() -> bool:
	var entry: Dictionary=NeighbourMeals.current()
	if entry.is_empty():
		await s.say("haru","happy","麦茶泡好了。我正想拌点黄瓜，一起吗？盐也有。")
		var invite: int=await s.ui.choose(["好，看看您怎么做","改天一起，我先忙别的","这回先不了","聊其他事"])
		if invite==3:return false
		if invite==1:NeighbourMeals.defer();return true
		if invite==2:NeighbourMeals.state().declined=true;NeighbourMeals.commit();return true
		NeighbourMeals.invite(present());entry=NeighbourMeals.current()
	if entry.stage=="invited":
		if entry.source=="player_request":
			await s.say("haru","happy","你送来的黄瓜还留着。咱们拌一点，盐我出，做完一人一份。")
			if int(entry.haru_materials.cucumber)>0:await s.say("haru","neutral","你那一根，我再添一根，正好够咱们分。")
			if int(entry.haru_kept_raw)>0:await s.say("haru","neutral","用两根就够了，余下那根留着做晚饭。")
		var role: int=await s.ui.choose(["我来切，您帮我看看","您来切，我在旁边学","改天再做","聊其他事","我回家做两份饭团来配","您拌好，我来分装摆碗"])
		if role==3:return false
		if role==2:return true
		var style: int=await s.ui.choose(["切薄片，沥点汁，配茶","切脆块，留着汁，带回配饭","先不决定"])
		if style==2:return true
		var chosen_role: String={0:"prepare",1:"watch",4:"rice",5:"serve"}[role]
		var start_error: String=NeighbourMeals.start(chosen_role,NeighbourMeals.STYLES[style],present())
		if start_error!="":await s.say("narrator","",start_error);return true
		entry=NeighbourMeals.current()
	if entry.stage in ["preparing","prepared","portioning"]:
		if not await reach_table():return true
		if entry.role=="serve" and entry.stage=="prepared" and view.layout_reason()!="":
			entry.stage="portioning";entry.arranged=false;NeighbourMeals.commit()
			await s.say("haru","neutral","换旁边那张干净小桌吧。碗照上回放，或挪挪都行。")
		if entry.stage=="preparing":
			if entry.role=="prepare":
				await s.say("haru","neutral","薄片容易入味，块大些吃着脆。撒一撮盐就够，尝尝再添。")
				var prep:=PicklePreparation.new();s.main.add_child(prep);await prep.run(s);prep.queue_free()
			else:
				await s.say("haru","neutral","我切给你看。薄片沥点汁，脆块留汁。你下回想配茶还是配饭，就照着切。")
				if not await view.watch_prepare():await s.say("narrator","","春去忙别的了。这碗还没拌完，下次接着做。") ;return true
				var finish_error: String=NeighbourMeals.finish(at_table())
				if finish_error!="":await s.say("narrator","",finish_error);return true
			if entry.stage not in ["prepared","portioning"]:return true
			DailyLife.mark_major("neighbour:haru_meal")
			await s.say("haru","happy","你一份，我一份。茶还没凉呢，一起尝尝。")
		if entry.stage=="portioning":
			await s.say("haru","happy","拌好了，你来分两只碗吧。茶托盘前留点地方，待会儿还要添茶。")
			var arrangement:=MealArrangement.new();s.main.add_child(arrangement);await arrangement.run(s);arrangement.queue_free()
			if entry.stage!="prepared":return true
		if entry.role=="rice" and int(entry.rice_made)==0:
			await s.say("haru","neutral","小菜先放杯边。你回家做两份饭团来，咱们一人一份。不急，我先喝茶。")
			return true
		await share(entry)
	return true

func reach_table() -> bool:
	var actor: NPC=s.npcs.haru
	var stop:=Vector3(14.6,0,16.1)
	if actor.global_position.distance_to(stop)>.7:
		var circles: Array=[[SummerSpace.DANCE_CENTER,SummerSpace.DANCE_RADIUS]] if GameState.festival_now()=="natsumatsuri" else []
		var route: Dictionary=ProjectRoute.query(s.world,actor.global_position,stop,[],"",circles)
		if not route.ok:await s.say("narrator","",str(route.reason));return false
		var speed: float=actor.speed;actor.speed=1.8;s.space.view.begin_walk(actor);s.ui.dlg.hide()
		var arrived: bool=true
		if s.ui.instant:
			actor.place(stop,0);s.space.view.trace.clear()
			for point: Vector3 in route.path:s.space.view.trace.append(point)
		else:arrived=await actor.walk_safe(route.path)
		var aborted: bool=s.space.view.aborted
		s.space.view.end_walk();actor.speed=speed;s.ui.dialogue_begin()
		if not arrived or aborted:await s.say("narrator","","春先停下来。小菜的半成品留着，下次接着走到杯边。") ;return false
	if not at_table():await s.say("haru","neutral","我在杯边等你。你慢慢走过来，咱们再开始。") ;return false
	return true

func share(entry: Dictionary) -> void:
	if entry.role=="rice" and int(entry.rice_given)==0:
		if int(entry.rice_made)!=2 or GameState.count(NeighbourMeals.rice_id(entry))<1:await s.say("haru","neutral","你这一顿的饭团还没带来，小菜先留着。") ;return
		var bring_error: String=NeighbourMeals.present_rice(at_table())
		if bring_error!="":await s.say("narrator","",bring_error);return
		var rice_error: String=await view.play_eat(s.npcs.haru,NeighbourMeals.rice_id(entry))
		if rice_error=="":rice_error=NeighbourMeals.give_rice(at_table())
		if rice_error!="":await s.say("narrator","",rice_error);return
		await s.say("haru","happy","你做饭，我备小菜，这样一顿就齐了。谢谢你给我留的一份。")
	if not entry.npc_ate:
		var haru_error: String=await view.play_eat(s.npcs.haru,NeighbourMeals.gift_id(entry))
		if haru_error!="":await s.say("narrator","",haru_error);return
		haru_error=NeighbourMeals.eat_haru(at_table())
		if haru_error!="":await s.say("narrator","",haru_error);return
		await s.say("haru","happy","薄片这样吃，清清爽爽的。配茶正好。" if entry.style=="thin" else "脆块嚼着有味道。回去配热饭，也挺好。")
	var choice: int=await s.ui.choose(["一起吃自己的这一小份","把自己的小份收好，回家配饭","这一份先留着","聊其他事"])
	if choice==2:return
	if choice==3:await s.farm.daily_talk("haru",true);return
	if choice==0:
		if entry.role=="rice" and GameState.unreserved_count(NeighbourMeals.rice_id(entry))>0:
			var own_rice_error: String=await view.play_eat(s.player,NeighbourMeals.rice_id(entry))
			if own_rice_error=="":own_rice_error=finish_own(NeighbourMeals.rice_id(entry))
			if own_rice_error!="":await s.say("narrator","",own_rice_error);return
		var player_error: String=await view.play_eat(s.player,NeighbourMeals.gift_id(entry))
		if player_error!="":await s.say("narrator","",player_error);return
	var take_error: String=NeighbourMeals.take("eat" if choice==0 else "pack",at_table())
	await s.say("narrator","",take_error if take_error!="" else ("把空碗放回托盘。盐味很轻，黄瓜还是脆的。" if choice==0 else "这一小份包好了，回家留着配自己的饭。"))

func own_foods(include_ordinary: bool=true) -> Array[String]:
	var foods: Array[String]=[]
	for iid: String in NeighbourMeals.RECIPES.values():
		if GameState.unreserved_count(iid)>0:foods.append(iid)
	for entry: Dictionary in NeighbourMeals.state().sessions:
		if GameState.unreserved_count(NeighbourMeals.rice_id(entry))>0:foods.append(NeighbourMeals.rice_id(entry))
		if entry.player_received and not entry.player_ate and GameState.unreserved_count(NeighbourMeals.gift_id(entry))>0:foods.append(NeighbourMeals.gift_id(entry))
	if include_ordinary:
		for iid: String in GameState.inventory:
			if iid!=FoodPurpose.NEXT_PORTION and not foods.has(iid) and DailyLife.edible(iid) and GameState.unreserved_count(iid)>0:foods.append(iid)
	return foods

func own_meal(include_ordinary: bool=true) -> bool:
	if not table_available():return false
	var foods: Array[String]=own_foods(include_ordinary)
	if foods.is_empty():return false
	var choice: int=await s.ui.choose_paged(foods.map(func(iid:String):return "带来的"+GameState.item_name(iid)+"，在麦茶旁吃"),"先收着，聊别的")
	if choice<0:return false
	var was_talking: bool=s.npcs.haru.talking
	s.npcs.haru.set_talking(true)
	if not await reach_table():s.npcs.haru.set_talking(was_talking);return true
	var why: String=await view.play_eat(s.player,foods[choice])
	if why=="":why=finish_own(foods[choice])
	s.npcs.haru.set_talking(was_talking)
	if why!="":await s.say("narrator","",why);return true
	if NeighbourMeals.rice_recipe(foods[choice]):await s.say("haru","happy","饭团也带来了呀，配茶正好。")
	elif foods[choice] in NeighbourMeals.RECIPES.values():await s.say("haru","happy","这是你自己拌的？闻着有点盐香。坐吧，茶壶就在手边。")
	elif foods[choice].begins_with("haru_side_"):await s.say("haru","happy","上回那一小份，还带着呀。坐这里，茶还有。")
	else:await s.say("haru","happy","带饭菜来了呀。坐吧，茶壶就在这边。")
	return true

func table_available() -> bool:
	return is_instance_valid(view) and view.table_model.visible and s.world.region=="town" and not s.main.in_room and view.surface().is_finite()

func table_meal() -> void:
	if not table_available():return
	var foods: Array[String]=own_foods()
	if foods.is_empty():
		await s.say("narrator","","小桌留着一块空面。下回带一份饭菜来，可以在这里歇一会儿；答应留给别人的那份先收好。")
		return
	var choice: int=await s.ui.choose_paged(foods.map(func(iid:String):return "在小桌吃一份"+GameState.item_name(iid)),"先收着")
	if choice<0:return
	var why: String=await view.play_eat(s.player,foods[choice])
	if why=="":why=finish_table(foods[choice])
	await s.say("narrator","",why if why!="" else "吃完带来的这一份，把空盘收好。今天在外面歇了一会儿。")

func finish_table(iid: String) -> String:
	if not table_available() or s.player.global_position.distance_to(view.surface())>3.2:return "这一份还收着。走到小桌旁，再慢慢吃。"
	return DailyLife.eat_food(iid)

func finish_own(iid: String) -> String:
	if not at_table():return "春先去忙了。这份小菜还留着，之后再决定。"
	return DailyLife.eat_food(iid,true)

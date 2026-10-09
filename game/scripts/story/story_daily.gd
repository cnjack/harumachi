class_name StoryDaily
extends RefCounted
var s: Story
var view: DailyLifeView


func _init(story: Story) -> void:
	s = story


func build() -> void:
	view = DailyLifeView.new()
	s.main.add_child(view)
	view.setup(s)


func prompt(id: String) -> Variant:
	if id == "life_tea" and GameState.day < int(DailyLife.state().introduced_day) + 1: return ""
	if id in ["life_bakery_card", "life_bakery_card_in"] and GameState.day < int(DailyLife.state().introduced_day) + 2: return ""
	match id:
		"life_pantry": return "看看碗柜上的食材便笺"
		"life_meal_table": return "在饭桌吃一点 · 收好饭团"
		"life_tea": return "春的麦茶 · 聊聊一碗小菜" if NeighbourMeals.can_offer() or not NeighbourMeals.current().is_empty() else "春的麦茶 · 育苗台旁"
		"life_bakery_card", "life_bakery_card_in": return "看看莲的小纸牌"
	return null


func handles(id: String) -> bool:
	return prompt(id) != null


func _say(who: String, mood: String, text: String) -> void:
	await s.say(who, mood, text)


func _present(who: String) -> bool:
	var npc: NPC = s.npcs.get(who)
	return npc != null and not npc.home and npc.is_visible_in_tree() and npc.global_position.distance_to(s.player.global_position) < 8.0


func _allowed(id: String) -> bool:
	if DailyLife.available(id):
		return true
	if not DailyLife.done(id) and int(DailyLife.event(id).deferred_day) == GameState.day and (not DailyLife.quota_used() or str(DailyLife.state().last_major_source) == "life:" + id):
		await _say("narrator", "", "东西还留着。现在想做，也可以。")
		var pick: int = await s.ui.choose(["现在看看", "先放着"])
		if pick == 0:
			return DailyLife.resume(id)
	await _say("narrator", "", "今天先忙自己的事也行。下次路过，这里还在。")
	return false


func handle(id: String) -> void:
	view.begin_scene(id)
	var partner: NPC = s.npcs.get("haru" if id == "life_tea" else ("ren" if id in ["life_bakery_card", "life_bakery_card_in"] else ""))
	if partner != null and _present(partner.npc_id):
		partner.face(s.player.global_position)
		partner.set_talking(true)
		s.player.face_towards(partner.global_position)
	match id:
		"life_pantry": await _pantry()
		"life_meal_table": await _table()
		"life_tea": await _tea()
		"life_bakery_card", "life_bakery_card_in": await _card()
	if partner != null: partner.set_talking(false)
	view.end_scene()


func arrival_invitation() -> void:
	await _say("sora", "neutral", "碗柜还在那边。小时候，得踩着凳子才够得着。")
	await _say("sora", "neutral", "先弄点吃的吧。公告栏等放好东西再去。")
	var pick: int = await s.ui.choose(["看看碗柜的食材便笺", "先放下行李，随便逛逛"])
	if pick == 0:
		DailyLife.track("meal")
	else:
		DailyLife.defer("meal")
	GameState.save_game()


func _pantry() -> void:
	if DailyLife.done("meal"):
		var next: Dictionary=FoodPurpose.followup_state().next
		if not next.is_empty():
			if next.choice=="later":
				var choice: int=await s.ui.choose(["下一顿在家吃","做饭团，带去配茶","以后再想","先不安排"])
				if choice!=2:
					FoodPurpose.next_meal(str(next.origin),["home","tea","later","none"][choice])
					next=FoodPurpose.followup_state().next
			await _say("narrator","","便笺上写着：%s。灶台还能用米和盐做两份饭团。" % {"home":"在家吃","tea":"带去配茶","later":"之后再想","none":"暂不安排"}.get(str(next.choice),"照旧"))
			return
		await _say("narrator", "", "盐饭团的便笺还在碗柜边，照着它就能再做。")
		return
	if DailyLife.event("meal").get("parcel_claimed", false):
		DailyLife.track("meal")
		await _say("sora", "neutral", "米和盐拿出来了。去灶台做两份吧，吃不完的带着走。")
		return
	if not await _allowed("meal"):
		return
	await _say("narrator", "", "碗柜旁压着一张便笺：“米和盐留了一小包。安顿好，先吃点东西。——和子”")
	await _say("sora", "neutral", "刚好两份。先吃一份，另一份包起来。")
	var pick: int = await s.ui.choose(["拿米和盐，去做饭", "先安顿，改天再做"])
	if pick != 0:
		DailyLife.defer("meal")
		GameState.save_game()
		return
	var why: String = DailyLife.claim_meal()
	if why != "":
		await _say("narrator", "", why)
		return
	Audio.fx("paper", -6)
	await _say("sora", "happy", "灶台就在旁边，先弄点吃的。")


func _table() -> void:
	if DailyLife.event("meal").get("cooked", false) and not DailyLife.done("meal"):
		await _say("sora", "neutral", "顺手拿了两只碗……今天先用一只吧。")
		await _say("narrator", "", "饭团做了两份。现在吃，还是包起来？")
		var pick: int = await s.ui.choose(["吃一份，包好另一份", "两份都打包", "晚点再来"])
		if pick == 2:
			DailyLife.defer("meal")
			GameState.save_game()
			return
		if GameState.count("onigiri") < 2:
			await _say("narrator", "", "手边没有那两份饭团。放在收纳箱里的话，先取回来吧。")
			return
		if pick == 0:
			var first_display_result: String=await view.play_action("eat")
			if first_display_result!="":
				await _say("narrator","",first_display_result)
				return
		else:
			Audio.fx("paper", -5)
		var why: String = DailyLife.finish_meal(pick)
		if why != "":
			await _say("narrator", "", why)
			return
		if pick == 0:
			await _say("sora", "happy", "盐放得刚好。今天就吃这个。")
			await _say("sora", "neutral", "这份包好，出去走走时带着。")
		else:
			await _say("sora", "neutral", "两份都包好了，饿了再拆。")
		await _say("narrator", "", "碗和包饭团的纸收好了。米和盐不够时，可以去商店买。")
		return
	var foods: Array = (GameState.inventory.keys() + GameState.key_items.keys()).filter(func(iid): return DailyLife.edible(iid) and GameState.unreserved_count(iid) > 0)
	if foods.is_empty():
		await _say("narrator", "", DailyLife.hint("meal") if not DailyLife.done("meal") else "饭桌收好了，屋子里还留着一点米饭的香味。")
		return
	var options: Array = foods.map(func(iid): return "吃一份%s" % GameState.item_name(iid))
	var selected: int = await s.ui.choose_paged(options, "先不吃")
	if selected < 0:
		return
	var item_id: String = str(foods[selected])
	var display_result: String = await view.play_action("eat", item_id)
	if display_result!="":
		await _say("narrator","",display_result)
		return
	var result: String = DailyLife.eat_food(item_id)
	await _say("narrator", "", "你吃完一份，把碗收好。" if result == "" else result)


func _tea() -> void:
	var next: Dictionary=FoodPurpose.followup_state().next
	var previous: Dictionary=s.food_use.tea_entry()
	var just_tea: bool=false
	var new_meal: bool=NeighbourMeals.can_offer() or not NeighbourMeals.current().is_empty() or NeighbourMeals.can_offer(true) and NeighbourMeals.state().deferred_day==GameState.day
	var own_side: bool=not s.neighbours.own_foods().is_empty()
	var rice_ready: bool=not next.is_empty() and next.choice=="tea" and GameState.has(FoodPurpose.NEXT_PORTION)
	if ((new_meal or own_side) and (rice_ready or not previous.is_empty()) or new_meal and own_side) and s.food_use.present("haru"):
		var topics: Array[String]=[]
		var actions: Array[String]=[]
		if new_meal:topics.append("春的一碗小菜");actions.append("neighbour")
		if own_side:topics.append("吃带来的饭菜");actions.append("own_side")
		if rice_ready:topics.append("在杯边吃自己带来的饭团");actions.append("rice")
		if not previous.is_empty():topics.append("继续晚会杯边那一份");actions.append("previous")
		topics.append("今天只聊麦茶");actions.append("tea")
		var topic: String=actions[await s.ui.choose(topics)]
		if topic=="neighbour":await s.neighbours.visit(true);return
		if topic=="own_side":await s.neighbours.own_meal();return
		if topic=="rice":await s.food_use.own_meal_at_tea();return
		if topic=="previous":
			if FoodPurpose.owned(previous,"haru").state=="held":await s.food_use.tea_use(previous)
			else:await s.food_use.haru_followup(previous)
			return
		just_tea=true
	if not just_tea and rice_ready and s.food_use.present("haru"):
		var share: int=await s.ui.choose(["在麦茶旁吃一份自己准备的饭团","今天先在家吃，之后再来","先做其他事"])
		if share==0: await s.food_use.own_meal_at_tea();return
		if share in [1,2]: return
	if not just_tea and not previous.is_empty() and FoodPurpose.owned(previous,"haru").state=="held":
		await s.food_use.handle("haru")
		return
	if not just_tea and not previous.is_empty() and (not FoodPurpose.was_presented(previous,"haru") or next.get("choice","")=="later") and s.food_use.present("haru"):
		await s.food_use.haru_followup(previous)
		return
	if not _present("haru"):
		await _say("narrator", "", "托盘先收在育苗台边。春下次在菜圃时，再一起喝一杯。")
		return
	if DailyLife.done("tea"):
		if not just_tea and own_side and not new_meal and await s.neighbours.own_meal():return
		if not just_tea and await s.neighbours.visit(true):return
		await _say("haru", "happy", "记着呢，你喜欢常温的。下次喝茶，我也给你留一杯。" if DailyLife.event("tea").get("temperature", 0) == 1 else "你上回把杯子放回了托盘。我洗过了，下次还用这只。")
		return
	if not await _allowed("tea"):
		return
	if not GameState.flags.get("met_haru", false):
		await _say("haru", "happy", "我是春，庭院里的花都是我照看的。先喝一口麦茶吧。")
		GameState.flags["met_haru"] = true
	await _say("haru", "neutral", "这壶是我早上泡的。冰的在这边，还有一杯没放冰。")
	var temperature: int = int(DailyLife.event("tea").get("temperature", -1))
	if not DailyLife.event("tea").get("drank", false):
		temperature = await s.ui.choose(["喝一杯冰麦茶", "喝一杯常温的", "今天先忙，改天再来"])
	if temperature == 2:
		DailyLife.defer("tea")
		GameState.save_game()
		return
	if not DailyLife.begin("tea"):
		return
	GameState.save_game()
	if not DailyLife.event("tea").get("drank", false):
		await view.play_action("sip")
		DailyLife.event("tea").drank = true
		DailyLife.event("tea").temperature = temperature
		GameState.save_game()
		if temperature == 0:
			await _say("sora", "happy", "凉凉的，还有一点烤麦子的香味。")
		else:
			await _say("sora", "happy", "不冰的也好。可以慢慢喝。")
	await _say("haru", "neutral", "喝完，把杯子放这里就行。我还得看看这几棵苗。")
	var help: int = await s.ui.choose(["问问怎么帮着种一点", "先歇一会儿，再去逛逛"])
	DailyLife.finish_tea(temperature, help == 0)
	await _say("haru", "neutral", "旁边的小桌留着。下回带一份饭菜来歇脚，自己吃也好，不用特意等我。")
	if help == 0:
		if GameState.at_step("Q03", "talk_haru"):
			await s._i_haru()
		elif GameState.qstate("Q03") == "locked":
			await _say("haru", "happy", "想学就来找我。澪那张清单也写着菜圃，你方便时先看看。")
		else:
			await _say("haru", "happy", "菜圃就在那边，按自己的时间来就行。想问什么再来找我。")
	else:
		await _say("haru", "happy", "好呀，今天就在这儿歇一歇。")


func _card() -> void:
	if not _present("ren"):
		await _say("narrator", "", "纸牌留在推车边。莲有空在店里或门口时，再找他聊聊。")
		return
	if DailyLife.done("card"):
		await _say("ren", "happy", "上回你扶正的纸牌，我把字也写大了一点。" if DailyLife.event("card").get("helped_sign", false) else "那张小纸牌还在。下次有新的试做，再找你尝尝。")
		return
	if not await _allowed("card"):
		return
	if GameState.qstate("Q02") == "locked":
		if not GameState.flags.get("met_ren",false):
			await _say("ren", "happy", "我是莲，旁边这家面包店的。今天切了一小份试吃，坐着也能尝。")
			GameState.flags["met_ren"] = true
		else:
			await _say("ren", "happy", "今天切了一小份试吃，坐着也能尝。")
	if DailyLife.is_weekend_stall():
		await _say("ren", "neutral", "周六傍晚了，我先把这一小篮摆出来。你看，纸牌又歪了。")
	elif GameState.weekday() == GameState.SATURDAY and GameState.minute < GameState.MARKET_OPEN:
		await _say("ren", "neutral", "离傍晚开摊还有一会儿，先理一下这张纸牌。小份试吃，不用买一整个才知道味道。")
	else:
		await _say("ren", "neutral", "周末前先理一下这张纸牌。写小份试吃，大家就不用买一整个才知道味道。")
	var pick: int = await s.ui.choose(["帮他扶正纸牌", "尝一小份菠萝包", "只看看，聊一会儿", "今天先忙，改天再来"])
	if pick == 3:
		DailyLife.defer("card")
		GameState.save_game()
		return
	if not DailyLife.begin("card"):
		return
	GameState.save_game()
	if pick == 0:
		await view.straighten()
		Audio.fx("paper", -5)
	elif pick == 1:
		DailyLife.claim_tasting()
		await _say("ren", "happy", "给。这一小份是我切好的，先尝尝。")
		var tasting_display_result: String=await view.play_action("eat", "melon_pan")
		if tasting_display_result!="":
			await _say("narrator","",tasting_display_result)
			return
	var result: String = DailyLife.finish_card(pick)
	if result != "":
		await _say("narrator", "", result)
	elif pick == 0:
		await _say("ren", "happy", "这样好看多了。下次我把字写大点，省得大家凑那么近。")
	elif pick == 1:
		await _say("sora", "happy", "外面脆脆的。小份也够尝出味道。")
		await _say("ren", "happy", "嗯，我记下了。以后试新口味也先切小份。")
	else:
		await _say("ren", "happy", "好，慢慢看。今天试做多了一点，我也得歇会儿。")

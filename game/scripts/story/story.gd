class_name Story
extends Node
const CONVERSATION = preload("res://scripts/story/neighbour_conversation.gd")
var personal_event_skipped := ""
## Everything the player can do with the world: prompts, dialogue, quest steps, shops, the
## market sequence and the ending. Rules and rewards stay in GameState; this node decides
## *when* to call them and what the neighbours say.

signal market_started
signal ended

var main: Node
var ui: GameUI
var world: WorldBuilder
var player: Player
var placement: PlacementSystem
var npcs := {}
var busy := false
var cutscene := false          # the first market's walk-in: NPC routines pause
var farm: StoryFarm
var fest: StoryFest
var lore: StoryLore
var bakery: StoryBakery
var homage: StoryHomage
var daily: StoryDaily
var projects: StoryProjects
var workshop: StoryWorkshop
var space: StorySpace
var gathering: StoryGathering
var food_use: StoryFoodUse
var neighbours: StoryNeighbourMeals
var morning: ResidentMorning
var _market_from := -1.0


func _ready() -> void:
	farm = StoryFarm.new(self)
	fest = StoryFest.new(self)
	lore = StoryLore.new(self)
	bakery = StoryBakery.new(self)
	homage = StoryHomage.new(self)
	daily = StoryDaily.new(self)
	projects = StoryProjects.new(self)
	workshop = StoryWorkshop.new(self)
	space = StorySpace.new(self)
	gathering = StoryGathering.new(self)
	food_use=StoryFoodUse.new(self)
	neighbours=StoryNeighbourMeals.new(self)
	Dialogue.load_db()


func npc_name(id: String) -> String:
	return str(Layout.NPC.get(id, {}).get("name", id))


# ================================================================== prompts
func prompt_for(id: String) -> String:
	var G := GameState
	if id=="resident_morning":return morning.prompt() if is_instance_valid(morning) else ""
	if id=="shared_meal_table":return "在小桌吃带来的饭菜 · 歇一会儿" if neighbours.table_available() else ""
	var daily_prompt: Variant = daily.prompt(id)
	if daily_prompt != null:
		return str(daily_prompt)
	var hp: Variant = homage.prompt(id)
	if hp != null:
		return str(hp)
	var workshop_prompt: Variant = workshop.prompt(id)
	if workshop_prompt != null: return str(workshop_prompt)
	var space_prompt: Variant = space.prompt(id)
	var gathering_prompt: Variant = gathering.prompt(id)
	var food_prompt: Variant=food_use.prompt(id)
	if food_prompt!=null: return str(food_prompt)
	if gathering_prompt != null: return str(gathering_prompt)
	if space_prompt != null: return str(space_prompt)
	var lp = lore.prompt(id)
	if lp != null:
		return lp
	var project_prompt: Variant = projects.prompt(id)
	if project_prompt != null: return str(project_prompt)
	var fe = fest.prompt(id)
	if fe != null:
		return fe
	var bp = bakery.prompt(id)
	if bp != null:
		return bp
	var fp = farm.prompt(id)
	if fp != null:
		return fp
	if id.begins_with("ambient_cat_"):return "摸摸猫"
	if id=="bus_driver":return "和司机聊聊"
	match id:
		"mio", "ren", "haru":
			return "和%s说话" % npc_name(id)
		"mailbox":
			return "打开信箱" if G.at_step("Q00", "mailbox") else "看看信箱"
		"home_door":
			return "用钥匙开门" if G.at_step("Q00", "enter_home") else "回家"
		"room_door":
			return "出门"
		"room_bed":
			return "躺一会儿（保存进度）"
		"room_desk":
			return "看看地图和自己的便笺" if G.qstate("Q15")=="done" else "看看书桌上的晴町地图"
		"house_boxes":
			return "再整理一次客厅（小游戏）" if G.flags.get("house_tidy", false) else "拆箱整理（小游戏）"
		"house_rice":
			return "看看厨房的米饭"
		"house_fridge":
			return "打开冰箱"
		"house_tv":
			return "看看电视"
		"house_kotatsu":
			return "钻进被炉歇一会儿"
		"house_cat":
			return "摸摸猫"
		"house_phone":
			return "拿起电话"
		"house_goldfish":
			return "看看金鱼" if G.flags.get("goldfish_home", false) else ""
		"house_garden":
			return "看看院子"
		"goldfish_pool":
			return "看看金鱼水槽"
		"taiko_drum":
			return "看看排练的太鼓"
		"board":
			if G.at_step("Q04", "post_sign") and G.has("event_sign"):
				return "贴上活动标牌"
			return "查看公告栏"
		"stall":
			if G.at_step("Q02", "deliver_basket") and G.has("bread_basket"):
				return "放下面包篮"
			return "看看集市摊位"
		"planter":
			if G.at_step("Q03", "plant"):
				return "种下番茄种子"
			if G.at_step("Q03", "water"):
				return "浇水" if G.flags.get("can_filled", false) else "看看种植箱"
			return "看看种植箱"
		"tap":
			return "给洒水壶装水" if G.at_step("Q03", "fill_can") else "喝口水"
		"center_door":
			return "取出活动标牌" if G.at_step("Q04", "get_sign") else "看看社区活动中心"
		"shop_florist":
			return "进花店「千代花坊」"
		"shop_zakka":
			return "进杂货铺「小町」"
		"bakery":
			return "闻闻面包香"
		"bus_stop":
			return "看看公交时刻表"
		"vending":
			return "看看自动售货机"
		"library":
			return "看看小书屋"
		"build_sign":
			if G.phase != "prep":
				return ""
			return "开始布置庭院（B）" if placement.can_enter() else "看看布置区告示"
		"lane_end", "east_end", "west_end":
			return "看看"
	return ""


## Where the floating map pin should hover for the current objective.
func marker_target() -> Variant:
	var G := GameState
	if SummerProjects.state().tracked:
		if SummerProjects.phase() == "ready" and G.phase != "market":
			if G.at_step("Q05", "invite"): return _npc_head("ren" if not G.invited("ren") else "haru")
			return _npc_head("mio")
		if SummerProjects.phase() == "feedback":
			var tasters: Dictionary = SummerProjects.current_batch().get("tasters", {})
			for who: String in ["mio", "haru", "kazuko"]:
				if tasters.has(who): continue
				var target: Variant = _npc_head(who)
				if target != null:
					if who == "kazuko" and (not main.in_room or main.room_kind != "store"): return _point("shop_store")
					return target
			return _point("opening_site")
		if SummerProjects.phase() == "trial" and main.in_room and main.room_kind == "bakery" and SummerProjects.opening().role == "food": return _point("bakery_oven")
		return _point("opening_site" if SummerProjects.phase() in ["site", "ready", "applied", "done"] else ("bakery" if not main.in_room or main.room_kind != "bakery" else "opening_paper"))
	var life_id: String = str(DailyLife.state().tracked)
	if life_id != "" and not DailyLife.done(life_id):
		if life_id == "meal":
			if not main.in_room or main.room_kind != "house":
				return _point("home_door")
			var doorway: Variant = HouseBuilder.kitchen_waypoint(player.global_position)
			if doorway != null: return doorway
			return _point("life_meal_table" if DailyLife.event("meal").get("cooked", false) else ("house_stove" if DailyLife.event("meal").get("parcel_claimed", false) else "life_pantry"))
		if life_id == "tea":
			return _point("life_tea")
		return _point("life_bakery_card_in" if main.in_room and main.room_kind == "bakery" else "life_bakery_card")
	var request: Dictionary = G.request()
	if G.flags.get("request_tracked", false) and not request.is_empty() and not request.get("done", false):
		return _npc_head(str(request.who))
	var q := G.tracked_quest
	if SummerProjects.uses_cooperation_mainline() and G.qstate("Q01") == "done" and G.qstate("Q05") == "locked" and G.qstate(q) != "active": return _point("opening_paper" if main.in_room and main.room_kind == "bakery" else "bakery")
	if G.qstate(q) != "active":
		for a in G.quest_order:
			if G.qstate(a) == "available":
				if a == "Q10":
					return _point("room_closet" if main.in_room and main.room_kind == "house" else "home_door")
				if G.quests_db[a].has("offer_target"):
					return _point(str(G.quests_db[a].offer_target))
				return _npc_head(str(G.quests_db[a].get("giver", "mio")))
		return null
	var s := G.qstep_id(q)
	if s.begins_with("bakery_"):
		if s == "bakery_taste":
			for who in ["mio", "haru"]:
				if not G.flags.get("bakery_tasters", {}).has(who):
					return _npc_head(who)
		if s == "bakery_supply" and G.bakery_order_ready():
			return _point("stall")
		return _point("bakery") if not main.in_room else _point("bakery_orders")
	var lm := lore.marker(s)
	if lm != "":
		return _npc_head(lm.substr(4)) if lm.begins_with("npc:") else _point(lm)
	match s:
		"mailbox": return _point("mailbox")
		"enter_home": return _point("home_door")
		"talk_mio", "talk_plan", "start": return _npc_head("mio")
		"read_board", "post_sign": return _point("board")
		"talk_ren": return _npc_head("ren")
		"deliver_basket": return _point("stall")
		"talk_haru", "report": return _npc_head("haru")
		"plant", "water": return _point("planter")
		"fill_can": return _point("tap")
		"get_sign": return _point("center_door")
		"place_seats": return _point("build_sign")
		"invite": return _npc_head("ren" if not G.invited("ren") else "haru")
		"chat":
			if SummerProjects.uses_cooperation_mainline() and not SummerProjects.market_used(): return _point("opening_site")
			for who in ["mio", "ren", "haru"]:
				if not G.flags.get("chat_" + who, false):
					return _npc_head(who)
		"talk_haru6": return _npc_head("haru")
		"go_farm": return _point("east_end")
		"talk_tanaka", "report6", "report7": return _npc_head("tanaka")
		"till", "sow", "water6": return _point("plot_farm0")
		"sell": return _point("veggie_stand")
		"talk_aoi", "give_aoi": return _npc_head("aoi")
		"sell_market": return _point("stall") if G.phase == "market" else null
		"report9": return _npc_head("mio")
	return null


func _point(id: String) -> Variant:
	for n in get_tree().get_nodes_in_group("interactables"):
		if (n as Interactable).id == id:
			return _regional((n as Node3D).global_position + Vector3(0, 1.6, 0))
	return null

## Scene placement must use real coordinates; marker routing may substitute an exit gate.
func physical_point(id: String) -> Variant:
	for node in get_tree().get_nodes_in_group("interactables"):
		if (node as Interactable).id == id: return (node as Node3D).global_position
	return null


func _npc_head(id: String) -> Variant:
	if npcs.has(id):
		var n: NPC = npcs[id]
		if n.home:
			return null
		return _regional(n.global_position + Vector3(0, 2.55, 0))
	return null


## A target on the other side (town vs. riverside farm) points at the way there instead.
func _regional(p: Vector3) -> Variant:
	var at_farm: bool = main.world.region == "farm"
	var on_farm := p.x > FarmBuilder.ORIGIN.x - 200.0
	if on_farm == at_farm:
		return p
	for n in get_tree().get_nodes_in_group("interactables"):
		if (n as Interactable).id == ("farm_exit" if at_farm else "east_end"):
			return (n as Node3D).global_position + Vector3(0, 1.6, 0)
	return null


# ================================================================== dispatch
func interact(it: Interactable) -> void:
	if busy:
		return
	if it.id.begins_with("ambient_cat_"):
		main.life.pet_cat(int(it.id.trim_prefix("ambient_cat_")));return
	busy = true
	personal_event_skipped = ""
	player.frozen = true
	ui.dialogue_begin()
	var npc: NPC = npcs.get(it.id)
	if npc:
		npc.face(player.global_position)
		npc.set_talking(true)
		player.face_towards(npc.global_position)
	else:
		player.face_towards(it.global_position)
	var fn := "_i_" + it.id
	var personal_handled := false
	if npc != null:
		await CONVERSATION.introduce(self, it.id)
		personal_handled = await CONVERSATION.personal_event(self, it.id)
	if personal_handled:
		pass
	elif it.id=="resident_morning":
		await morning.handle()
	elif it.id=="shared_meal_table":
		await neighbours.table_meal()
	elif daily.handles(it.id):
		await daily.handle(it.id)
	elif homage.handles(it.id):
		await homage.handle(it.id)
	elif workshop.handles(it.id):
		await workshop.handle(it.id)
	elif food_use.handles(it.id):
		await food_use.handle(it.id)
	elif gathering.handles(it.id):
		await gathering.handle(it.id)
	elif space.handles(it.id):
		await space.handle(it.id)
	elif lore.pending(it.id):
		await lore.handle(it.id)
	elif projects.handles(it.id):
		await projects.handle(it.id)
	elif fest.handles(it.id):
		await fest.handle(it.id)
	elif bakery.pending(it.id):
		await bakery.handle(it.id)
	elif farm.handles(it.id):
		await farm.handle(it.id)
	elif has_method(fn):
		await call(fn)
	if npc:
		npc.set_talking(false)
	ui.dialogue_end()
	player.frozen = false
	busy = false
	post_checks()


func say(who: String, mood: String, text: String) -> void:
	await ui.say(who, mood, text)


func post_checks() -> void:
	var G := GameState
	lore.checks()
	bakery.checks()
	SummerProjects.checks()
	if G.at_step("Q05", "place_seats") and G.seating_ready():
		G.advance("Q05", "place_seats")
		G.toast.emit("桌椅摆好了！接下来去邀请莲和春")
	if G.at_step("Q05", "invite") and G.invited("ren") and G.invited("haru"):
		G.advance("Q05", "invite")
		G.toast.emit("大家都答应来了，去告诉澪可以开始了")
	if G.at_step("Q05", "chat") and (not SummerProjects.uses_cooperation_mainline() or SummerProjects.market_used()) and G.flags.get("chat_mio", false) and G.flags.get("chat_ren", false) and G.flags.get("chat_haru", false):
		G.advance("Q05", "chat")
		_ending.call_deferred()


# ================================================================== NPCs
func _i_mio() -> void:
	var G := GameState
	if G.at_step("Q09", "report9"):
		await say("mio", "happy", "五份卖完啦？我就说，摆出来会有人想尝。")
		G.advance("Q09", "report9")
		await say("mio", "neutral", "町内会给摊主留了这份谢礼，你收着。下次还来吗？")
		return
	if G.phase == "market" and G.qstate("Q05") == "done":
		if await _offer_onigiri("mio"):
			return
		await farm.daily_talk("mio")
		return
	if G.phase == "market":
		# after the first market chat, a home-made onigiri can still be handed over
		if G.flags.get("chat_mio", false) and await _offer_onigiri("mio"):
			return
		await _market_chat("mio")
		return
	if G.qstate("Q00") != "done":
		await say("mio", "happy", "啊，你就是今天搬来三丁目的新邻居吧？我是澪，负责社区活动的联络。")
		await say("mio", "neutral", "先回家放下行李吧！支巷里那栋奶油色的两层小楼，钥匙我放在门口的信箱里啦。")
		return
	if G.at_step("Q01", "talk_mio"):
		G.advance("Q01", "talk_mio")
		await say("mio", "happy", "太好了！清单就贴在我身后的公告栏上。")
		return
	if G.qstate("Q01") == "available":
		await say("mio", "happy", "行李放好啦？欢迎来到晴町！")
		await say("mio", "neutral", "以前傍晚，这几张长椅总坐满。我现在擦完，常常还是空着。")
		await say("mio", "happy", "我想周末办个小集市。带点吃的过来，坐坐也行。")
		await say("mio", "neutral", "要做的事贴在旁边的公告栏上。你愿意看看吗？")
		var c := await ui.choose(["好啊，我去看看", "先让我逛逛"])
		if c == 0:
			G.start_quest("Q01")
			G.advance("Q01", "talk_mio")
			await say("mio", "happy", "太好了！清单就贴在我身后的公告栏上。")
		else:
			await say("mio", "neutral", "没关系。想帮忙的时候再来找我，今天先逛逛。")
		return
	if G.at_step("Q01", "read_board"):
		await say("mio", "neutral", "清单就贴在旁边的公告栏上哦。")
		return
	if G.qstate("Q05") == "available" or G.at_step("Q05", "talk_plan"):
		if SummerProjects.uses_cooperation_mainline():
			await say("mio", "happy", "菜单和取餐的位置试好了？跟我说说，我把分工写下来。")
			await say("narrator", "", SummerProjects.notes())
			await say("mio", "neutral", "桌椅就留在刚才试的位置吧。开摊后你招待，莲来烤，我去叫大家。")
		else:
			await say("mio", "happy", "三枚支持标记都拿到了！我这儿的桌椅也借到了。")
			await say("mio", "neutral", "野餐桌和长椅在仓库里，你拿去摆吧。哪边坐着舒服，咱们就放哪边。")
			G.add_item("picnic_table", 1)
			G.add_item("bench", 2)
		G.start_quest("Q05")
		G.advance("Q05", "talk_plan")
		if SummerProjects.uses_cooperation_mainline():
			await say("mio", "happy", "再去问问莲和春愿不愿意来。约好周六傍晚，在庭院碰头。")
		else:
			await say("mio", "neutral", "庭院中间的告示牌能开始布置，按 B 就行。先放一张野餐桌、一张长椅。")
			await say("mio", "happy", "花店和杂货铺还有装饰。这次的钱只够挑两种，你看看喜欢什么。")
		return
	if G.at_step("Q04", "get_sign"):
		Audio.fx("door")
		await say("mio", "neutral", "活动标牌在主街南边的社区中心，门口挂着木牌。")
		return
	if G.at_step("Q04", "post_sign"):
		await say("mio", "happy", "拿到啦？直接贴到公告栏上就好！")
		return
	if G.at_step("Q05", "place_seats"):
		await say("mio", "neutral", "还差桌椅吗？庭院告示牌那里按 B，野餐桌和长椅各放一件就够。")
		return
	if G.at_step("Q05", "invite"):
		var who := []
		if not G.invited("ren"):
			who.append("莲")
		if not G.invited("haru"):
			who.append("春")
		await say("mio", "neutral", "还没问过%s呢。有空去找他们说一声吧。" % "和".join(who))
		return
	if G.at_step("Q05", "start"):
		if G.weekday() != G.SATURDAY or G.minute >= G.MARKET_CLOSE:
			var d := (G.SATURDAY - G.weekday() + 7) % 7
			if d == 0:
				d = 7
			await say("mio", "neutral", "都准备好了！集市就定在周六傍晚——%s。" % ("还有 %d 天" % d if d > 1 else "就是明天"))
			await say("mio", "happy", "周六傍晚来庭院找我。这几天，你先安顿自己的事。")
			return
		if G.minute < G.MARKET_OPEN:
			await say("mio", "happy", "今天就是周六！集市傍晚四点半开始。")
			var w := await ui.choose(["在长椅上等到傍晚", "我先去逛逛"])
			if w == 1:
				await say("mio", "neutral", "好，傍晚见！")
				return
			_market_from = G.minute
			ui.dialogue_end()
			await ui.fade_out(0.6)
			G.skip_to(G.MARKET_OPEN)
			world.update_time(G.minute, G.weather, true)
			world.apply_phase(G.phase, false)
			await ui.fade_in(0.6)
			ui.dialogue_begin()
			await say("mio", "happy", "天边都红了。再等会儿，路灯也该亮了。")
		await say("mio", "neutral", "都准备好了吗？")
		var c := await ui.choose(["开始集市！", "再等一下"])
		if c == 1:
			await say("mio", "happy", "嗯，不着急。准备好了再来找我。")
			return
		var reasons := G.market_ready_reasons()
		if not reasons.is_empty():
			await say("mio", "neutral", "等等，好像还差一点：" + "；".join(reasons) + "。")
			return
		await say("mio", "happy", "那……晴町周末小集市，开始啦！")
		ui.dialogue_end()
		await _market_sequence()
		ui.dialogue_begin()
		return
	if G.qstate("Q09") == "available" and G.phase != "market":
		await say("mio", "happy", "下个周六还办，大家刚跟我说好了。")
		await say("mio", "neutral", "下次你也带点菜来卖？这里每份的价钱，比无人菜摊高一半。")
		G.start_quest("Q09")
		await say("mio", "happy", "第一次先试卖五份。卖完来找我，町内会留了谢礼。")
		return
	if G.at_step("Q09", "report9"):
		await say("mio", "happy", "五份卖完啦？我就说，摆出来会有人想尝。")
		G.advance("Q09", "report9")
		await say("mio", "neutral", "町内会给摊主留了这份谢礼，你收着。下次还来吗？")
		return
	if await _offer_onigiri("mio"):
		return
	# idle chat depends on which errands are still open
	var left := []
	if G.qstate("Q02") != "done":
		left.append("莲的面包")
	if G.qstate("Q03") != "done":
		left.append("春的种植箱")
	if G.qstate("Q04") != "done":
		left.append("活动标牌")
	if not left.is_empty() and G.qstate("Q01") == "done":
		await say("mio", "neutral", "还有这些要帮忙：%s。每做完一件，拿一枚支持标记回来。" % "、".join(left))
		G.note_talk("mio")
		return
	await farm.daily_talk("mio")


func _i_ren() -> void:
	var G := GameState
	if G.phase == "market" and G.qstate("Q05") == "done":
		if await _offer_onigiri("ren"):
			return
		await farm.daily_talk("ren")
		return
	if G.phase == "market":
		# after the first market chat, a home-made onigiri can still be handed over
		if G.flags.get("chat_ren", false) and await _offer_onigiri("ren"):
			return
		await _market_chat("ren")
		return
	if G.at_step("Q05", "invite") and not G.invited("ren"):
		await say("ren", "neutral", "嗯？集市的邀请……给我的？")
		var c := await ui.choose(["一起来吧，大家都等着你的面包", "有空的话来坐坐"])
		G.flags["invited_ren"] = true
		if c == 0:
			G.add_affinity("ren", 1)
			await say("ren", "happy", "被这么说就更得去了！我多烤两炉。")
		else:
			await say("ren", "happy", "好！关店后我就过去。")
		return
	if G.qstate("Q02") == "active" and G.at_step("Q02", "talk_ren"):
		if not G.flags.get("met_ren",false):
			await say("ren", "happy", "欢迎光临～啊，你就是澪说的新邻居？我是莲，这家面包店是我爷爷开的。")
			G.flags["met_ren"] = true
		await say("ren", "neutral", "我试做了一篮新口味，想放在集市的摊位上让大家尝尝……可店里一个人走不开。")
		await say("ren", "neutral", "能帮我把篮子送到庭院里的集市摊位吗？就是绿白条纹遮阳棚那个。")
		var c := await ui.choose(["包在我身上", "篮子沉吗？"])
		if c == 1:
			await say("ren", "happy", "哈哈，不沉，都是空气感的面包！")
		G.add_item("bread_basket", 1)
		G.add_item("melon_pan", 1)
		G.advance("Q02", "talk_ren")
		await say("ren", "happy", "这个菠萝包是谢礼，路上趁热吃！")
		return
	if G.at_step("Q02", "deliver_basket"):
		await say("ren", "neutral", "摊位在庭院南边，绿白条纹的遮阳棚。拜托啦！")
		return
	if await _offer_onigiri("ren"):
		return
	if G.qstate("Q01") != "done":
		if not G.flags.get("met_ren",false):
			await say("ren", "happy", "欢迎光临～是新面孔呢！我是莲。刚出炉的菠萝包，下次一定来尝尝。")
			G.flags["met_ren"] = true
		else: await farm.daily_talk("ren")
	elif G.qstate("Q02") == "done" and G.qstate("Q05") != "done" and not G.flags.get("ren_nervous", false):
		G.flags["ren_nervous"] = true
		await say("ren", "neutral", "大家会喜欢那篮面包吗……啊，集市还没开始，我就开始紧张了。")
	elif G.qstate("Q02") != "done":
		await say("ren", "neutral", "澪说你在帮忙准备集市？辛苦啦。")
	else:
		await farm.daily_talk("ren")


func _i_haru() -> void:
	var G := GameState
	if G.phase == "market" and G.qstate("Q05") == "done":
		if await _offer_onigiri("haru"):
			return
		await farm.daily_talk("haru")
		return
	if G.phase == "market":
		# after the first market chat, a home-made onigiri can still be handed over
		if G.flags.get("chat_haru", false) and await _offer_onigiri("haru"):
			return
		await _market_chat("haru")
		return
	if G.at_step("Q05", "invite") and not G.invited("haru"):
		await say("haru", "neutral", "集市？在庭院里办？")
		var c := await ui.choose(["就在您照顾的庭院里", "您坐着看热闹就好"])
		G.flags["invited_haru"] = true
		if c == 0:
			G.add_affinity("haru", 1)
			if G.crop_stage > 0: await say("haru", "happy", "那可得去看看。番茄也该长高了吧。")
			else: await say("haru", "happy", "好呀，给我留个能歇脚的位置，我带小凳子去。")
		else:
			await say("haru", "happy", "好啊，我就坐在庭院里看大家热闹。")
		return
	if G.at_step("Q03", "talk_haru"):
		if G.flags.get("met_haru", false):
			await say("haru", "happy", "歇好了？我带你看看这只种植箱。")
		else:
			await say("haru", "happy", "哎呀，是新来的孩子？我是春，在这个庭院种了三十年的花啦。")
			G.flags["met_haru"] = true
		await say("haru", "neutral", "这个种植箱空了好久……我膝盖不好，一个人忙不过来。")
		await say("haru", "neutral", "你愿意帮我种下番茄吗？种子和洒水壶都借给你。")
		var c := await ui.choose(["我来试试", "我没种过菜……"])
		if c == 1:
			await say("haru", "happy", "没种过也不碍事，我在旁边看着。")
		G.add_item("seeds", 1)
		G.add_item("watering_can", 1)
		G.advance("Q03", "talk_haru")
		await say("haru", "neutral", "先把种子撒进旁边的种植箱，再去南边墙角的饮水台装水。")
		return
	if G.at_step("Q03", "plant"):
		await say("haru", "neutral", "种植箱就在我旁边，把种子撒进土里就好。")
		return
	if G.at_step("Q03", "fill_can"):
		await say("haru", "neutral", "饮水台在南边墙角，先给壶里装满水。")
		return
	if G.at_step("Q03", "water"):
		await say("haru", "neutral", "水沿着种子旁边慢慢倒。洒到路上，鞋底容易打滑。")
		return
	if G.at_step("Q03", "report"):
		await say("haru", "happy", "这箱土总算又湿了。我看着都想再种两棵。")
		G.remove_item("watering_can", 1)
		G.advance("Q03", "report")
		await say("haru", "happy", "这个标记给你，零花钱也收着。想买什么就去看看。")
		return
	if G.qstate("Q06") == "available" and G.phase != "market":
		await say("haru", "neutral", "田中看见你种的番茄，准要过来瞧瞧。他也爱种这个。")
		await say("haru", "neutral", "主街东头下坡，就是河边农园。田中在那里，我认识他六十年啦。")
		await say("haru", "happy", "那儿还有空地。这封信你带给田中，他认得我的字。")
		G.start_quest("Q06")
		G.add_item("letter_haru", 1)
		G.advance("Q06", "talk_haru6")
		await say("haru", "neutral", "他要是板着脸，你别怕。他就是那副样子。")
		return
	if await _offer_onigiri("haru"):
		return
	if G.qstate("Q03") == "done" and not G.flags.get("court_plot", false) and G.crop_stage < 3:
		var stage_line: String = ["", "种子睡在土里呢。", "冒芽啦，你看见了吗？", "番茄结果了！红红的。"][G.crop_stage]
		await say("haru", "happy", "常来看看种植箱吧。" + stage_line)
		G.note_talk("haru")
	elif G.qstate("Q03") == "done" and not G.flags.get("court_plot", false) and G.crop_stage >= 3:
		await say("haru", "happy", "番茄都红了，去摘吧。头一回收，挑最红的看看。")
		G.note_talk("haru")
	elif G.qstate("Q01") != "done":
		if not G.flags.get("met_haru",false):
			await say("haru", "neutral", "哎呀，新来的孩子？我是春。庭院里的花都是我照看的。")
			G.flags["met_haru"] = true
		else: await farm.daily_talk("haru")
	else:
		await farm.daily_talk("haru")


# ------------------------------------------------------------------ new neighbours (v0.4)
func _i_tanaka() -> void:
	var G := GameState
	if G.at_step("Q06", "go_farm"):
		G.advance("Q06", "go_farm")
	if G.at_step("Q06", "talk_tanaka"):
		await say("tanaka", "neutral", "……新来的？从地边走，别踩着苗。")
		if G.has("letter_haru"):
			await say("narrator", "", "你把春的信递给他。田中爷爷读完，眉头慢慢松开了。")
			G.remove_item("letter_haru", 1)
		await say("tanaka", "happy", "春这家伙，信里把你夸上天了。……行吧。")
		await say("tanaka", "neutral", "前排四块地借你。锄头、壶拿去。壶够浇五次，空了去棚边的手压泵装。")
		G.add_item("hoe", 1)
		G.add_item("farm_can", 1)
		G.add_item("seed_radish", 1)
		G.add_item("seed_komatsuna", 1)
		G.can_water = G.CAN_CAP
		G.open_plots(["farm0", "farm1", "farm2", "farm3", "yard0", "yard1", "yard2", "yard3"])
		G.advance("Q06", "talk_tanaka")
		await say("tanaka", "neutral", "先翻土，撒种子，再浇水。家里的空地也能试。")
		return
	if G.qstate("Q06") == "active" and G.qstep("Q06") > 2 and not G.at_step("Q06", "report6"):
		var hint := {"till": "先翻土。站到荒地前面用锄头。", "sow": "土翻好了，撒种子。", "water6": "浇水。壶空了就去手压泵。"}
		await say("tanaka", "neutral", hint.get(G.qstep_id("Q06"), "慢慢来。"))
		return
	if G.at_step("Q06", "report6"):
		await say("tanaka", "neutral", "……嗯。土翻得匀，水也浇透了。")
		await say("tanaka", "happy", "水浇透了。晴天每天来浇一次，下雨就省了。")
		G.advance("Q06", "report6")
		await say("tanaka", "neutral", "第一批菜收了，路边无人菜摊能卖。我棚里也有种子。")
		if G.qstate("Q07") == "available":
			G.start_quest("Q07")
		return
	if G.at_step("Q07", "report7"):
		await say("tanaka", "happy", "第一批菜卖出去了？……我头一次卖菜，钱数了好几遍。")
		await say("tanaka", "neutral", "温室那两块也借你。草莓只种里面，这袋苗、两袋肥都拿去。")
		G.advance("Q07", "report7")
		G.open_plots(["gh0", "gh1"], true)
		return
	if G.phase != "market" and G.qstate("Q07") == "done" and G.farm_expand_cost() > 0 and G.flags.get("harvests", 0) >= 2:
		var cost := G.farm_expand_cost()
		var c := await ui.choose(["聊聊天", "再多租 4 块地（%d 生活币）" % cost])
		if c == 1:
			var r := G.expand_farm()
			if r != "":
				await say("tanaka", "neutral", r + "。攒够了再来。")
			else:
				await say("tanaka", "happy", "后排四块也借你。壶里的水不够，就到泵边添。")
			return
	await farm.daily_talk("tanaka")


func _i_aoi() -> void:
	var G := GameState
	if not G.flags.get("met_aoi", false):
		G.flags["met_aoi"] = true
		await say("aoi", "happy", "你就是新搬来的邻居？我叫小葵！是春奶奶的孙女，暑假来晴町住！")
		if G.qstate("Q03") == "done":
			await say("aoi", "neutral", "奶奶说你会种番茄。……真的吗？好厉害！")
		else:
			await say("aoi", "neutral", "我刚来的时候，连牙刷放在哪只包里都忘了。你记得自己的东西放哪儿了吗？")
		if G.qstate("Q08") != "available":
			await say("aoi", "happy", "以后我们一起玩吧！")
			return
	if G.qstate("Q08") == "available" and G.phase != "market":
		await say("aoi", "neutral", "那个……我可以拜托你一件事吗？")
		await say("aoi", "neutral", "奶奶生日快到了。我想送她一朵向日葵，要比我还高！")
		await say("aoi", "happy", "可是我不会种……这是我在花店买的种子，你帮我种好不好？")
		G.start_quest("Q08")
		G.add_item("seed_sunflower", 1)
		G.advance("Q08", "talk_aoi")
		await say("aoi", "happy", "先别告诉奶奶哦，我想让她猜是谁送的。")
		return
	if G.at_step("Q08", "give_aoi"):
		if G.has("sunflower"):
			G.remove_item("sunflower", 1)
			await say("aoi", "happy", "哇——！！好大！比我的脸还大！")
			await say("narrator", "", "小葵抱着向日葵跑向春。春愣了一下，然后笑得眼睛都眯起来了。")
			await say("haru", "happy", "呀，门口正缺一束花。你们先让我找个大点的瓶子。")
			await say("aoi", "happy", "这个发夹给你！我挑了最亮的那个。")
			G.advance("Q08", "give_aoi")
			return
		await say("aoi", "neutral", "向日葵开了没有？我去看奶奶，你帮我看花！")
		return
	await farm.daily_talk("aoi")


func _market_chat(who: String) -> void:
	var G := GameState
	var decor := G.placed_decor()
	var first: bool = not G.flags.get("chat_" + who, false)
	match who:
		"mio":
			if decor.has("bunting"):
				await say("mio", "happy", "彩旗！我一直想在这里挂一串的……你怎么知道？")
			else:
				await say("mio", "happy", "你看，大家真的都来了。")
			await say("mio", "neutral", "谢谢你。有你搭把手，庭院好久没这么热闹了。下次办秋祭吧？")
		"ren":
			if decor.has("lantern"):
				await say("ren", "happy", "灯笼一亮……好像回到了老家的夏祭。谢谢你挂上它。")
			if SummerProjects.uses_cooperation_mainline():
				await say("ren", "happy", "这一篮就照试吃时的纸签准备。有人来拿的时候，你招呼一声，我帮你添盘子。")
			else: await say("ren", "happy", "面包一下子就卖光了！有个小朋友说想天天吃。")
			if G.flags.get("gift_ren", false):
				await say("ren", "neutral", "对了，你送的饭团我配着汤吃了。下次教我怎么捏得那么圆？")
		"haru":
			if decor.has("flower_pot"):
				await say("haru", "happy", "绣球花！你还记得我喜欢花呀。")
			if G.crop_stage >= 3:
				await say("haru", "happy", "看，番茄都红了。第一个给你尝尝。")
			if G.flags.get("goldfish_home", false):
				await say("haru", "happy", "听说你捞到金鱼了？记得每天给它换一点水。")
			await say("haru", "neutral", "很多年没这么热闹了。坐下来，陪我看一会儿夕阳吧。")
	if first:
		G.flags["chat_" + who] = true
		G.state_changed.emit()


# ================================================================== places
func _i_mailbox() -> void:
	var G := GameState
	Audio.fx_at("mailbox",player.global_position+Vector3.UP*.8,-8)
	if G.at_step("Q00", "mailbox"):
		await say("narrator", "", "信箱里有一把挂着叶子木牌的钥匙，和一张折好的便笺。")
		G.add_item("house_key", 1)
		G.add_item("welcome_note", 1)
		await say("narrator", "", "便笺上写着：“欢迎搬来晴町！方便的时候，来庭院门口的公告栏找我。——澪”")
		G.advance("Q00", "mailbox")
	else:
		await say("narrator", "", "信箱空空的。门牌上写着：晴町 3-2。")


func _i_home_door() -> void:
	var G := GameState
	if not G.has("house_key"):
		await say("narrator", "", "门锁着。钥匙也许在信箱里。")
		return
	ui.dialogue_end()
	await main.enter_room()
	if G.at_step("Q00", "enter_home"):
		G.advance("Q00", "enter_home")
		ui.dialogue_begin()
		await say("sora", "happy", "这就是我的新家啊……纸箱还没拆完，不过阳光真好。")
		await daily.arrival_invitation()
		ui.dialogue_end()
	ui.dialogue_begin()


func _i_room_door() -> void:
	ui.dialogue_end()
	await main.exit_room()
	ui.dialogue_begin()


func _i_room_bed() -> void:
	await say("sora", "neutral", "在床上躺一会儿……")
	if GameState.save_game():
		Audio.sting("save")
		await say("narrator", "", "进度已保存。")


func _i_room_desk() -> void:
	var G := GameState
	if G.qstate("Q15")=="done":
		var choice: int = await ui.choose(["看看原来的晴町地图", "读读自己留下的便笺", "重新写一句下一步的打算", "先放着"])
		if choice==3: return
		if choice in [1,2]:
			if choice==2 or MainlineProgress.direction().is_empty(): await lore.future_direction("home")
			else: await say("narrator","",str(MainlineProgress.DIRECTION_NOTES[int(MainlineProgress.direction().choice)]))
			return
	if not G.flags.get("map_framed", false):
		await say("narrator", "", "奶奶留的滑块地图放在书桌上。旁边夹着一张完整的小图，能认出庭院和商店街。想拼的话，照着它慢慢来。")
	StoryKnowledge.observe_activity("puzzle")
	await play_mg("puzzle")


## Run a mini-game from an interaction (the dialogue box closes while it runs).
func play_mg(id: String, context: Dictionary = {}) -> Dictionary:
	ui.dialogue_end()
	var res: Dictionary = await ui.play_minigame(id, context)
	ui.dialogue_begin()
	GameState.save_game()
	return res


func _i_house_rice() -> void:
	var G := GameState
	var meal: Dictionary = DailyLife.event("meal")
	if meal.get("parcel_claimed", false) and not meal.get("cooked", false):
		await say("sora", "neutral", "米和盐拌好了。先捏一小份试手感，还是直接包成两份？")
		var choice: int = await ui.choose(["自己捏一小份，再包成两份", "简单制作，包成两份", "先放着"])
		if choice == 2: return
		if choice == 0:
			StoryKnowledge.observe_activity("onigiri")
			var shaped: Dictionary = await play_mg("onigiri", {"mode": "home_meal", "start_requested": true})
			if not shaped.get("completed", false) or not shaped.get("outcome", {}).get("shaped", false):
				await say("sora", "neutral", "先把米料盖好。想捏的时候再来，灶台也能直接做。")
				return
		var why: String = G.craft("first_home_onigiri", 1)
		if why != "":
			await say("narrator", "", why)
			return
		meal["method"] = "shaped" if choice == 0 else "simple"
		G.save_game()
		await say("sora", "happy", "两份包好了。放到饭桌上，先吃还是带走都行。")
		return
	if meal.get("cooked", false) and not DailyLife.done("meal"):
		await say("sora", "neutral", "这一包米料已经做成两份了。先去饭桌收好，练习等会儿再来。")
		return
	if not GameState.flags.get("rice_seen", false):
		GameState.flags["rice_seen"] = true
		await say("narrator", "", "电饭煲旁夹着几张馅料练习单。可以试试盛饭、放馅、捏形；想做自己的第一顿饭，碗柜上有和子留下的便笺。")
	StoryKnowledge.observe_activity("onigiri")
	await play_mg("onigiri")


func _i_house_fridge() -> void:
	Audio.fx("door", -8.0)
	var n := GameState.count("onigiri")
	if n > 0:
		await say("narrator", "", "冰箱里有麦茶、鸡蛋，还有你捏的 %d 个饭团。" % n)
	else:
		await say("narrator", "", "冰箱里只有一瓶麦茶和几个鸡蛋。该去商店街采购了。")


func _i_house_tv() -> void:
	var G := GameState
	var tomorrow: String = G.WEATHERS.get(G.weather_for(G.day + 1), "晴")
	var lines := ["电视里在播天气预报：“明天%s，晴町一带%s。”" % [G.weekday_name(G.day + 1), tomorrow],
		"电视里的主持人在介绍夏祭的捞金鱼摊。", "午间新闻说，今年的萤火虫比往年早。"]
	await say("narrator", "", lines[0])
	await say("narrator", "", lines[1 + G.day % 2])
	if tomorrow == "小雨":
		await say("sora", "neutral", "明天下雨的话，菜就不用浇水了。")


func _i_house_kotatsu() -> void:
	await say("sora", "happy", "被炉虽然没通电，钻进去还是暖暖的……")
	await say("narrator", "", "窗外的风铃叮铃响了一声。")


func _i_house_cat() -> void:
	Audio.sfx("cat_meow",-4.0)
	Audio.fx("purr", -4.0)
	var lines := ["猫咪眯着眼，喉咙里发出呼噜呼噜的声音。", "猫咪翻了个身，把肚子露给阳光。", "猫咪蹭了蹭你的手，又睡着了。"]
	var i := int(GameState.flags.get("cat_pets", 0))
	GameState.flags["cat_pets"] = i + 1
	await say("narrator", "", lines[i % lines.size()])
	if i == 0:
		await say("sora", "happy", "原来这只猫是附近的常客……以后就叫你“小团子”吧。")


func _i_house_phone() -> void:
	await say("sora", "neutral", "（给家里打了个电话。）")
	if DailyLife.done("meal"):
		if DailyLife.event("meal").get("ate", false):
			await say("sora", "happy", "我自己做过饭团了。盐放得刚好，当时还留了一份带出门。")
		else:
			await say("sora", "happy", "我自己包过两份饭团。出门带点吃的，走累了就歇一下。")
	else:
		await say("sora", "happy", "嗯，都安顿好了。邻居们都很好，下次寄晴町的菠萝包给你们。")


func _i_house_goldfish() -> void:
	await say("narrator", "", "缘侧的金鱼缸里，小金鱼摆着尾巴，追着水面的光点。")


func _i_house_garden() -> void:
	var lines := ["小院里的绿篱修得整整齐齐。邻居家的柿子树探过墙头。", "阳光落在踏脚石上，暖洋洋的。", "风吹过来，带着一点青草和晒过的被子的味道。"]
	if GameState.phase == "market":
		lines = ["远处庭院传来集市的笑声，天边一片橘红。"]
	await say("narrator", "", lines[int(GameState.play_time / 20.0) % lines.size()])


func _i_goldfish_pool() -> void:
	if not GameState.flags.get("goldfish_seen", false):
		GameState.flags["goldfish_seen"] = true
		await say("narrator", "", "花架旁摆着一个捞金鱼的水槽，牌子上写着：“集市练习用 · 随便玩”。")
	StoryKnowledge.observe_activity("goldfish")
	await play_mg("goldfish")


func _i_taiko_drum() -> void:
	if not GameState.flags.get("taiko_seen", false):
		GameState.flags["taiko_seen"] = true
		await say("narrator", "", "小舞台边放着一面太鼓。鼓面上贴着纸条：“祭典排练中，欢迎试打！”")
	StoryKnowledge.observe_activity("taiko")
	await play_mg("taiko")


## Neighbours happily take one home-made onigiri each (+1 familiarity, once per person).
func _offer_onigiri(who: String) -> bool:
	var G := GameState
	if G.unreserved_count("onigiri") < 1 or G.flags.get("gift_" + who, false):
		return false
	var c := await ui.choose(["送一个饭团", "只是来打个招呼"])
	if c != 0:
		return false
	G.remove_item("onigiri", 1)
	G.flags["gift_" + who] = true
	G.add_affinity(who, 1)
	Audio.sting("item")
	var line: String = {"mio": "哇，是你自己捏的？形状好可爱……我中午就吃它！", "ren": "饭团！面包师也最爱米饭了，谢谢你。",
			"haru": "哎呀，捏得真结实。让我想起孙子小时候。"}.get(who, "谢谢！")
	await say(who, "happy", line)
	G.state_changed.emit()
	return true


func _i_board() -> void:
	var G := GameState
	if G.at_step("Q04", "post_sign") and G.has("event_sign"):
		G.remove_item("event_sign", 1)
		Audio.fx("paper")
		world.poster.visible = true
		await say("narrator", "", "你把活动标牌贴在公告栏中间，压平卷起的纸角。")
		G.advance("Q04", "post_sign")
		return
	if G.at_step("Q01", "read_board"):
		if SummerProjects.uses_cooperation_mainline():
			await ui.show_notice("周末小集市 · 一起准备", ["面包店柜台旁：找莲试做一份，也可帮着招待。", "请两位街坊尝尝，选小份或整份、纸包或盘子，再去庭院试试路。", "试好告诉澪，约街坊来；周六开摊后，给来的人递一份。", "还有送面包、种菜、贴标牌的活儿。有空愿意帮哪件，按 J 看。"], "—— 晴町社区 · 澪")
		else:
			await ui.show_notice("周末小集市 · 准备清单", ["☐  面包店：把莲的试做面包送到庭院的集市摊位", "☐  庭院菜圃：和春一起把种植箱重新种上", "☐  活动中心：把活动标牌取来，贴到这块公告栏", "每件做完拿一枚邻里支持标记。先做哪件都行。"], "—— 晴町社区 · 澪")
		G.advance("Q01", "read_board")
		if not SummerProjects.uses_cooperation_mainline():
			for q in ["Q02", "Q03", "Q04"]: G.start_quest(q)
			G.tracked_quest = "Q02"
		G.state_changed.emit()
		return
	var lines := ["晴町社区公告"]
	lines.append("· 周六傍晚：庭院小集市（%s）" % ("进行中！" if G.phase == "market" else "筹备中"))
	lines.append("· 回收日：周二可燃、周五瓶罐")
	lines.append("· 失物招领：黄色小雨伞一把（请到活动中心领取）")
	lines.append_array(G.request_lines())
	if G.qstate("Q01") == "done":
		var cooperation: bool=SummerProjects.uses_cooperation_mainline()
		if cooperation:
			lines.append("本次合作："+SummerProjects.hint())
			lines.append("其他帮忙（可选，按 J 接一件）：")
		var community_jobs: Array[String]=[]
		for pair in [["Q02", "面包送到摊位"], ["Q03", "种植箱重新种上"], ["Q04", "活动标牌贴出来"]]:
			var job: String=("☑  " if G.qstate(pair[0]) == "done" else "☐  ")+pair[1]
			if cooperation:community_jobs.append(job)
			else:lines.append(job)
		if cooperation:lines.append(" · ".join(community_jobs))
	await ui.show_notice("公告栏", lines)


func _i_stall() -> void:
	var G := GameState
	if G.at_step("Q02", "deliver_basket"):
		if G.take_all({"bread_basket": 1}):
			Audio.fx_at("basket",player.global_position+Vector3.UP*.8,-8)
			world.stall_bread.visible = true
			await say("narrator", "", "你把面包篮放在摊位中央。黄油的香味一下子飘开了。")
			G.advance("Q02", "deliver_basket")
			await say("narrator", "", "（莲托人送来了谢礼：一个绣球花盆。）")
		return
	if G.phase == "market":
		await say("narrator", "", "摊位前排起了小队，面包和蔬菜都快卖完了。")
	elif world.stall_bread.visible:
		await say("narrator", "", "莲的面包篮已经摆好了，就等周末了。")
	else:
		await say("narrator", "", "空荡荡的集市摊位。遮阳棚被晒得暖暖的。")


func _i_planter() -> void:
	var G := GameState
	if G.at_step("Q03", "plant"):
		G.remove_item("seeds", 1)
		Audio.fx("soil")
		G.set_crop(1)
		world.set_crop_stage(1)
		await say("narrator", "", "你在土里戳出几个小坑，把番茄种子一颗颗放进去，再轻轻盖上土。")
		G.advance("Q03", "plant")
		return
	if G.at_step("Q03", "water"):
		if not G.flags.get("can_filled", false):
			await say("narrator", "", "洒水壶是空的。先去南边墙角的饮水台装水吧。")
			return
		ui.dialogue_end()
		Audio.fx_at("water_pour",player.global_position+Vector3.UP*.8,-8)
		world.splash_at(Layout.PLANTER_POS + Vector3(0, 0.75, 0))
		world.water_soil()
		await get_tree().create_timer(0.05 if ui.instant else 1.6).timeout
		ui.dialogue_begin()
		G.flags["can_filled"] = false
		G.set_crop(2)
		world.set_crop_stage(2)
		await say("narrator", "", "水渗进土里，颜色一点点变深。没过多久，冒出了几片嫩绿的小芽。")
		G.advance("Q03", "water")
		return
	var s: String = ["土是松软的，可是什么也没种。", "种子正在土里睡觉。", "土里冒出了几片嫩芽，叶子还卷着。", "番茄长得很高了，结了一串红果子。"][G.crop_stage]
	await say("narrator", "", s)


func _i_tap() -> void:
	var G := GameState
	if G.at_step("Q03", "fill_can"):
		G.flags["can_filled"] = true
		Audio.fx_at("water_tap",player.global_position+Vector3.UP*.8,-8)
		await say("narrator", "", "水龙头哗哗地响，洒水壶沉甸甸的了。")
		G.advance("Q03", "fill_can")
		return
	await say("narrator", "", "你捧起一口水。凉凉的，带点铁管的味道。")


func _i_center_door() -> void:
	var G := GameState
	if G.at_step("Q04", "get_sign"):
		await say("narrator", "", "活动中心的门没锁。长桌上放着卷好的海报，上面写着“周末小集市”。")
		G.add_item("event_sign", 1)
		G.advance("Q04", "get_sign")
		return
	await say("narrator", "", "社区活动中心。门上贴着“太极拳 周三上午”。")


func _i_shop_florist() -> void:
	ui.dialogue_end()
	await ui.open_shop("千代花坊", "千代", "今天的绣球开得正好，放在庭院里一下子就亮了。", ["flower_pot"])
	ui.dialogue_begin()


func _i_shop_zakka() -> void:
	ui.dialogue_end()
	await ui.open_shop("杂货铺 · 小町", "阿健", "办集市？那得有彩旗和灯笼啊！", ["bunting", "lantern"])
	ui.dialogue_begin()


func _i_bakery() -> void:
	if await _place_line("bakery"):
		return
	await say("narrator", "", "橱窗里摆着刚出炉的菠萝包和吐司。莲在门口招呼客人。")


func _i_bus_driver() -> void:
	await say("narrator","","司机朝你挥挥手：“回来了呀。这班到晴町就停了，我也下车歇歇。”")


func _i_bus_stop() -> void:
	if await _place_line("bus_stop"):
		return
	await say("narrator", "", "“晴町三丁目”站。下一班车是一小时后。")


func _i_vending() -> void:
	if await _place_line("vending"):
		return
	await say("narrator", "", "自动售货机里的麦茶看起来很冰。")


func _i_library() -> void:
	if await _place_line("library"):
		return
	await say("narrator", "", "“自由取阅”的小书屋。里面有一本旧旧的《晴町的四季》。")


func _i_build_sign() -> void:
	var G := GameState
	if placement.can_enter():
		ui.dialogue_end()
		busy = false
		player.frozen = false
		placement.enter()
		await placement.exited
		busy = true
		player.frozen = true
		ui.dialogue_begin()
		return
	if G.qstate("Q05") == "locked" or G.qstate("Q05") == "available":
		await say("narrator", "", "告示：“周末集市布置区。桌椅请向澪借用。”")
	else:
		await say("narrator", "", "背包里没有可以摆放的东西了。")


func _i_lane_end() -> void:
	await say("narrator", "", "小路在这里被链条拦住，牌子上写着：“山坡公园 · 整修中”。")


func _i_east_end() -> void:
	await say("narrator", "", "主街从这里拐下坡去。今天就在晴町里逛逛吧。")


func _i_west_end() -> void:
	await say("narrator", "", "这是通往村外的大路。暂时还不能离开晴町，先在镇里逛逛吧。")


func _place_line(id: String) -> bool:
	var e := Dialogue.pick("place:" + id, {"region": main.world.region})
	if e.is_empty():
		return false
	Dialogue.mark(e)
	for ln in e.lines:
		await say(str(ln[0]), str(ln[1]), str(ln[2]))
	return true


func try_build() -> void:
	if busy or GameState.input_locked() or not placement.can_enter():
		return
	var z: Array = Layout.ZONE
	var p := player.global_position
	if p.x < z[0] - 4 or p.x > z[2] + 4 or p.z < z[1] - 4 or p.z > z[3] + 4:
		GameState.toast.emit("走到庭院中间的布置区再按 B")
		return
	placement.enter()


# ================================================================== market & ending
func _market_sequence() -> void:
	DailyLife.mark_major("Q05")
	busy = true
	cutscene = true
	player.frozen = true
	GameState.lock_input("cutscene")
	await ui.fade_out(0.8)
	if not GameState.start_market():
		GameState.unlock_input("cutscene")
		cutscene = false
		await ui.fade_in(0.5)
		return
	main.to_market_positions(true)
	# off to the side of the walkway the neighbours come down, so nobody walks through the player
	player.global_position = Vector3(-5.8, 0.1, 9.2)
	player.velocity = Vector3.ZERO
	player.set_facing(0.75)
	main.rig.yaw = 205.0
	main.rig.pitch = 26.0
	main.rig.dist = 8.0
	main.rig.snap()
	world.stall_bread.visible = true
	world.poster.visible = true
	world.set_crop_stage(GameState.crop_stage)
	ui.set_hud_visible(false)
	Audio.play_music("market", 3.0)
	Audio.play_amb("evening", 3.0)
	await ui.fade_in(0.8)
	Audio.sting("fanfare")
	get_tree().create_timer(1.8).timeout.connect(func(): Audio.sting("sparkle"))
	world.apply_phase("market", not ui.instant, _market_from if _market_from >= 0.0 else GameState.minute - 60.0)
	_market_from = -1.0
	if ui.instant:
		main.to_market_positions(false)
	else:
		for id in npcs:
			var info: Dictionary = Layout.NPC[id]
			(npcs[id] as NPC).walk(info.route)
	await get_tree().create_timer(0.2 if ui.instant else 4.5).timeout
	for id in npcs:
		var n: NPC = npcs[id]
		var info: Dictionary = Layout.NPC[id]
		if n.is_moving():
			await n.walk_finished
		n.set_yaw(deg_to_rad(info.market_yaw))
	ui.set_hud_visible(true)
	GameState.unlock_input("cutscene")
	cutscene = false
	market_started.emit()
	GameState.toast.emit("集市开始了！在合作纸签摆出这一篮，递出第一份，再和邻居聊聊" if SummerProjects.uses_cooperation_mainline() else "集市开始了！去和三位邻居聊聊吧")


func _ending() -> void:
	while busy:
		await get_tree().process_frame
	var G := GameState
	busy = true
	player.frozen = true
	await get_tree().create_timer(0.05 if ui.instant else 0.6).timeout
	var counts := {}
	for p in G.placements:
		counts[p.item] = int(counts.get(p.item, 0)) + 1
	var placed := []
	for id in counts:
		placed.append("%s ×%d" % [G.item_name(id), counts[id]])
	var hearts := func(n: int) -> String: return GameState.hearts_text(n)
	var lines := [
		"你在晴町度过了第一个周末。庭院里第一次坐满了人。",
		"用时：%s" % GameUI._fmt_time(G.play_time),
		"庭院里摆着：%s" % ("、".join(placed) if not placed.is_empty() else "—"),
		"邻居熟悉度：澪 %s · 莲 %s · 春 %s" % [hearts.call(int(G.affinity.mio)), hearts.call(int(G.affinity.ren)), hearts.call(int(G.affinity.haru))],
	]
	var liked := []
	for d in G.placed_decor():
		var who: String = G.item(d).get("liked_by", "")
		if who != "":
			liked.append("%s很喜欢你挑的%s" % [npc_name(who), G.item_name(d)])
	if not liked.is_empty():
		lines.append("、".join(liked) + "。")
	if SummerProjects.uses_cooperation_mainline(): lines.append(SummerProjects.notes())
	lines.append("周六傍晚，集市照常开张。明天也可以先歇一歇，收拾家里留下的箱子。")
	MainlineProgress.weekend_complete()
	DailyLife.record_market()
	G.save_game()
	Audio.sting("quest_done")
	var r := await ui.show_ending(lines)
	busy = false
	player.frozen = false
	ended.emit()
	if r == "title":
		main.go_title()

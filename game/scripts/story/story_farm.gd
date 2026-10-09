class_name StoryFarm
extends RefCounted
## Farming, the riverside allotment and the everyday neighbour talk (requests, gifts, dialogue pool).
## Story forwards prompts and interactions here; rules stay in GameState.

var s: Story


func _init(story: Story) -> void:
	s = story


func _say(who: String, mood: String, text: String) -> void:
	await s.say(who, mood, text)


func _toast(t: String) -> void:
	GameState.toast.emit(t)


func _act_anim() -> void:
	if s.player.anim and s.player.anim.valid():
		s.player.anim.play_once("bow", 1.4)


func crop_name(cid: String) -> String:
	return str(GameState.crop_def(cid).get("name", cid))


# ================================================================== prompts
## Returns the prompt, "" to disable, or null when Story should decide.
func prompt(id: String) -> Variant:
	var G := GameState
	if LakesideLayout.SPOTS.has(id):return "在%s钓鱼" % str(LakesideLayout.SPOTS[id].name)
	if id=="lakeside_supplies":return "借钓竿 · 买鱼饵 / 卖鲜鱼"
	if id.begins_with("plot_"):
		return plot_prompt(id.substr(5))
	match id:
		"planter":
			if G.plots.court.open:
				return plot_prompt("court")
			if G.qstate("Q03") == "done" and G.crop_stage >= 3:
				return "摘下春的番茄"
			return null
		"tap":
			if G.has("farm_can") and not G.at_step("Q03", "fill_can"):
				return "给洒水壶装水（%d/%d）" % [G.can_water, G.can_cap()]
			return null
		"yard_tap":
			return "给洒水壶装水（%d/%d）" % [G.can_water, G.can_cap()] if G.has("farm_can") else "拧开水龙头"
		"farm_pump":
			return "压水装满洒水壶（%d/%d）" % [G.can_water, G.can_cap()] if G.has("farm_can") else "压一压手压泵"
		"farm_compost":
			if G.compost_ready > 0:
				return "取出堆肥 ×%d" % G.compost_ready
			if G.has("weeds"):
				return "把杂草放进堆肥箱"
			return "看看堆肥箱"
		"farm_shed":
			return "田中的种子铺" if G.qstate("Q06") == "done" or G.qstep("Q06") > 2 else "看看工具棚"
		"shop_store":
			return "进「晴町商店」"
		"bakery":
			return "进莲的面包店"
		"store_counter":
			return "和和子阿姨说话（买东西 / 卖东西）"
		"kazuko":
			return "和和子阿姨说话"
		"store_exit", "bakery_exit":
			return "出门"
		"store_fridge":
			return "看看冷饮柜"
		"store_freezer":
			return "看看冰柜"
		"bakery_counter":
			return "在柜台买面包 · 配方卡"
		"bakery_oven":
			return "借用烤箱（烘焙）"
		"bakery_mill":
			return "用石磨磨面粉"
		"cake_showcase":
			return "看看蛋糕柜"
		"shop_florist":
			return "进花店「千代花坊」"
		"shop_zakka":
			return "进杂货铺「小町」"
		"house_stove":
			return "在厨房做料理"
		"house_chest":
			return "打开收纳箱"
		"veggie_stand":
			return "在无人菜摊卖菜" if not G.produce_owned().is_empty() else "看看无人菜摊"
		"farm_bench":
			return "在河边坐一会儿"
		"farm_exit":
			return "回晴町"
		"farm_sign":
			return "看看农园告示"
		"scarecrow":
			return "看看稻草人"
		"east_end":
			return "下坡去河边农园"
		"tanaka", "aoi":
			return "和%s说话" % s.npc_name(id)
		"room_bed":
			return "睡觉（到第二天早上）" if G.hour() >= 18.0 else "躺一会儿（存档 / 午睡）"
		"stall":
			if G.phase == "market" and G.qstate("Q05") == "done" and not _market_goods().is_empty():
				return "在夏祭摊位卖料理（2 倍价）" if G.festival_now() == "natsumatsuri" else "在集市摊位卖菜和料理"
			return null
	return null


func plot_prompt(pid: String) -> String:
	var G := GameState
	var p: Dictionary = G.plots[pid]
	match G.plot_state(pid):
		"locked":
			return "看看空地"
		"wild":
			return "翻土" if G.has("hoe") else "看看荒地"
		"tilled":
			return "播种"
		"ripe":
			return "收获%s" % crop_name(p.crop)
		_:
			if not p.water:
				return "浇水（壶里 %d/%d）" % [G.can_water, G.can_cap()] if G.has("farm_can") else "看看%s" % crop_name(p.crop)
			return "看看%s" % crop_name(p.crop)


func handles(id: String) -> bool:
	if LakesideLayout.SPOTS.has(id) or id=="lakeside_supplies":return true
	if id.begins_with("plot_"):
		return true
	var G := GameState
	match id:
		"planter":
			return G.plots.court.open or (G.qstate("Q03") == "done" and G.crop_stage >= 3)
		"tap":
			return G.has("farm_can") and not G.at_step("Q03", "fill_can")
		"stall":
			return G.phase == "market" and G.qstate("Q05") == "done" and not _market_goods().is_empty()
		"yard_tap", "farm_pump", "farm_compost", "farm_shed", "veggie_stand", "farm_bench", "farm_exit", "farm_sign", "scarecrow", "east_end", "room_bed", \
				"shop_store", "bakery", "shop_florist", "shop_zakka", "house_stove", "house_chest", \
				"store_counter", "kazuko", "store_exit", "bakery_exit", "store_fridge", "store_freezer", "bakery_counter", \
				"bakery_oven", "bakery_mill", "cake_showcase":
			return true
	return false


func handle(id: String) -> void:
	if LakesideLayout.SPOTS.has(id):
		s.ui.dialogue_end()
		await s.main.start_fishing(id)
		s.ui.dialogue_begin()
		return
	if id=="lakeside_supplies":
		var why:=GameState.borrow_fishing_kit()
		if why!="":GameState.toast.emit(why)
		s.ui.dialogue_end()
		await s.ui.panels.open_store("lakeside")
		s.ui.dialogue_begin()
		return
	if id.begins_with("plot_"):
		await plot_act(id.substr(5))
		return
	match id:
		"planter":
			if GameState.plots.court.open:
				await plot_act("court")
			else:
				await _harvest_q03_tomatoes()
		"tap", "yard_tap", "farm_pump":
			await _refill(id)
		"farm_compost":
			await _compost()
		"farm_shed":
			await _shed()
		"veggie_stand":
			await _sell(GameState.STAND_RATE, "无人菜摊")
		"stall":
			await _sell(GameState.MARKET_RATE, "集市摊位")
		"shop_store":
			await _enter_shop("store")
		"store_counter", "kazuko":
			await _kazuko()
		"store_exit", "bakery_exit":
			s.ui.dialogue_end()
			await s.main.exit_interior()
			s.ui.dialogue_begin()
		"store_fridge":
			await _say("narrator", "", "冷饮柜里排着弹珠汽水、麦茶和瓶装牛奶，玻璃门上凝着一层细细的水珠。")
		"store_freezer":
			await _say("narrator", "", "冰柜里是一根根冰棍和雪糕。和子阿姨说，小葵每天下午都来挑一根。")
		"bakery_counter":
			await _ren_counter()
		"bakery_oven", "bakery_mill":
			await _oven()
		"cake_showcase":
			await _say("narrator", "", "玻璃柜里摆着草莓蛋糕、泡芙和小小的水果挞。莲说蛋糕是周末才做的。")
		"shop_florist":
			await _open_shop("florist")
		"shop_zakka":
			await _open_shop("zakka")
		"bakery":
			await _enter_shop("bakery")
		"house_stove":
			s.ui.dialogue_end()
			await s.ui.panels.open_craft("kitchen")
			s.ui.dialogue_begin()
		"house_chest":
			s.ui.dialogue_end()
			await s.ui.panels.open_storage()
			s.ui.dialogue_begin()
		"farm_bench":
			await _bench()
		"farm_exit":
			s.ui.dialogue_end()
			await s.main.leave_farm()
			s.ui.dialogue_begin()
		"east_end":
			s.ui.dialogue_end()
			await s.main.go_farm()
			s.ui.dialogue_begin()
			if GameState.at_step("Q06", "go_farm"):
				GameState.advance("Q06", "go_farm")
				_toast("到了河边的市民农园。去找田中爷爷吧")
		"farm_sign":
			await s.ui.show_notice("晴町 市民农园", [
				"· 一块地一个季度 150 生活币起（请找管理员田中）",
				"· 工具可以借，用完请放回工具棚",
				"· 手压泵的水随便用。堆肥箱只放杂草和菜叶",
				"· 无人菜摊：请把钱放进木箱，谢谢",
				"今日天气：%s　明日：%s" % [GameState.weather_name(), GameState.WEATHERS.get(GameState.weather_for(GameState.day + 1), "晴")],
			], "—— 晴町町内会")
		"scarecrow":
			var lines := ["稻草人穿着一件褪了色的法被，脸上画着一个笑。据说是小葵画的。", "稻草人的帽檐上停着一只麻雀。好像一点也不怕它。",
					"稻草人的袖子里塞着一张纸条：“辛苦了。——田中”"]
			await _say("narrator", "", lines[GameState.day % lines.size()])
		"room_bed":
			await _bed()


# ================================================================== plots
func plot_act(pid: String) -> void:
	var G := GameState
	var st := G.plot_state(pid)
	var region := G.plot_region(pid)
	var p: Dictionary = G.plots[pid]
	match st:
		"locked":
			match region:
				"yard":
					await _say("narrator", "", "院子里有一小片空地，长满了杂草。要是有把锄头，就能开出一块小菜地了。")
				"greenhouse":
					await _say("narrator", "", "温室里整整齐齐的两块地。田中爷爷说，等你第一次收获以后再用。")
				_:
					await _say("narrator", "", "这块地还没有租给你。插着一块小牌子：“空地 · 请洽管理员田中”。")
		"wild":
			var r := G.till(pid)
			if r != "":
				await _say("narrator", "", r + "。")
				return
			_act_anim()
			Audio.fx("hoe")
			_toast("翻好了一块地（杂草 ×2，可以放进堆肥箱）")
			if G.at_step("Q06", "till"):
				G.advance("Q06", "till")
		"tilled":
			var seeds := G.seeds_owned(pid)
			if seeds.is_empty():
				if region == "greenhouse":
					await _say("narrator", "", "温室的地是留给草莓苗的。背包里没有草莓苗。")
				else:
					await _say("narrator", "", "背包里没有能种的种子。田中爷爷的工具棚和主街的花店都有卖。")
				return
			seeds.sort_custom(func(a, b): return G.count(a) > G.count(b))
			var opts: Array = seeds.map(func(i): return "%s（%d）" % [G.item_name(i), G.count(i)])
			var c: int = await s.ui.choose_paged(opts)
			if c < 0:
				return
			var r := G.sow(pid, seeds[c])
			if r != "":
				await _say("narrator", "", r + "。")
				return
			_act_anim()
			var cid: String = G.plots[pid].crop
			_toast("种下了%s，%d 天后成熟。记得每天浇水" % [crop_name(cid), int(G.crop_def(cid).days)])
			if G.at_step("Q06", "sow"):
				G.advance("Q06", "sow")
			if cid == "sunflower" and G.at_step("Q08", "sow_sun"):
				G.advance("Q08", "sow_sun")
		"ripe":
			var res := G.harvest(pid)
			if res.is_empty():
				await _say("narrator", "", "背包满了，先腾出一格再来收吧。")
				return
			_act_anim()
			Audio.fx("harvest")
			_toast("收获了%s ×%d！" % [G.item_name(res.item), res.n])
			if G.at_step("Q07", "harvest"):
				G.advance("Q07", "harvest")
			if res.item == "sunflower" and G.at_step("Q08", "bloom"):
				G.advance("Q08", "bloom")
		_:
			var c: Dictionary = G.crop_def(p.crop)
			if not p.water:
				var r := G.water_plot(pid)
				if r != "":
					await _say("narrator", "", r + "。")
					return
				_act_anim()
				s.world.splash_at((s.main.world.farm.plot_views.get(pid, s.main.world.house.yard_plots.get(pid, s.world.court_plot)) as Node3D).global_position + Vector3(0, 0.5, 0))
				_toast("浇好了（壶里还剩 %d/%d）" % [G.can_water, G.can_cap()])
				if G.at_step("Q06", "water6"):
					G.advance("Q06", "water6")
				return
			var left := int(c.days) - int(p.days)
			var line := "%s长得很好。%s今天已经浇过水了。" % [crop_name(p.crop), "再过 %d 天就能收。" % left if left > 0 else ""]
			await _say("narrator", "", line)
			if G.has("fertilizer") and not p.fert:
				var k := await s.ui.choose(["撒一把堆肥（产量 +1，今晚多长 1 天）", "算了"])
				if k == 0 and G.fertilize(pid) == "":
					_toast("施了肥，土闻起来暖暖的")


## After Q03 the story tomatoes are picked and the planter becomes an ordinary plot.
func _harvest_q03_tomatoes() -> void:
	var G := GameState
	if not G.add_item("tomato", 3, true):
		await _say("narrator", "", "背包满了，先腾出一格再来摘吧。")
		return
	Audio.fx("harvest")
	G.flags["court_plot"] = true
	G.plots.court.open = true
	G.plots.court.tilled = true
	G.plots.court.crop = ""
	G.plots.court.days = 0
	G.plots_changed.emit()
	G.state_changed.emit()
	await _say("narrator", "", "你摘下了一串红透的迷你番茄（×3）。种植箱空出来了，以后可以种别的东西。")
	await _say("haru", "happy", "第一批番茄，是你种出来的哦。这个箱子以后就交给你啦。")


func _refill(id: String) -> void:
	var G := GameState
	if not G.has("farm_can"):
		match id:
			"farm_pump":
				Audio.fx("pump")
				await _say("narrator", "", "你压了几下手柄，冰凉的河水哗地涌了出来。")
			"yard_tap":
				Audio.fx_at("water_tap",s.player.global_position+Vector3.UP*.8,-8)
				await _say("narrator", "", "院子的水龙头有点紧。拧开以后，水声清清脆脆的。")
			_:
				await _say("narrator", "", "你捧起一口水。凉凉的，带点铁管的味道。")
		return
	Audio.fx("pump" if id == "farm_pump" else "water_tap")
	G.refill_can()
	_toast("洒水壶装满了（%d/%d）" % [G.can_water, G.can_cap()])


func _compost() -> void:
	var G := GameState
	if G.compost_ready > 0:
		var n := G.compost_take()
		if n > 0:
			_toast("取出堆肥 ×%d" % n)
		else:
			await _say("narrator", "", "背包满了，堆肥先放在箱子里吧。")
		return
	if G.has("weeds"):
		var n := G.compost_add("weeds")
		await _say("narrator", "", "你把 %d 份杂草丢进堆肥箱。现在箱子里有 %d 份材料，每 3 份第二天早上会变成一袋堆肥。" % [n, G.compost])
		return
	await _say("narrator", "", "堆肥箱里有 %d 份材料。翻土时拔出来的杂草可以放进来。" % G.compost)


func _shed() -> void:
	var G := GameState
	if G.qstate("Q06") != "done" and not (G.qstate("Q06") == "active" and G.qstep("Q06") > 2):
		await _say("narrator", "", "工具棚的门半开着，墙上挂着锄头、耙子和一顶草帽。管理员好像就在附近。")
		return
	await _open_shop("shed")


func _market_goods() -> Array:
	var G := GameState
	return G.inventory.keys().filter(func(i): return G.item(i).has("crop") or G.item(i).has("dish"))


func _open_shop(sid: String) -> void:
	var why := GameState.shop_closed_reason(sid)
	if why != "":
		await _say("narrator", "", "门上挂着牌子：%s。" % why)
		return
	s.ui.dialogue_end()
	await s.ui.panels.open_store(sid)
	s.ui.dialogue_begin()


## v0.6: the general store and the bakery are rooms you walk into (InteriorBuilder).
func _enter_shop(k: String) -> void:
	var why := GameState.shop_closed_reason(k)
	if why != "":
		await _say("narrator", "", "橱窗的灯灭了。门上写着：%s。" % why if k == "bakery" else "卷帘门拉下了一半。门上挂着牌子：%s。" % why)
		return
	s.ui.dialogue_end()
	await s.main.enter_interior(k)
	s.ui.dialogue_begin()


func _kazuko() -> void:
	var G := GameState
	if not G.flags.get("met_kazuko", false):
		G.flags["met_kazuko"] = true
		await _say("kazuko", "happy", "哎呀，是新搬来的那家孩子吧！我是和子，这家店开了四十年啦。")
		await _say("kazuko", "neutral", "种子、调料、日用品，还有你种的菜我也收。缺什么就跟我说！")
	else:
		var e := Dialogue.pick("kazuko", s.CONVERSATION.context(s, "kazuko"))
		if not e.is_empty():
			Dialogue.mark(e)
			for ln in e.lines:
				await _say(ln[0], ln[1], ln[2])
	await _open_shop("store")


func _ren_counter() -> void:
	var G := GameState
	if not G.flags.get("bakery_inside", false):
		G.flags["bakery_inside"] = true
		await _say("ren", "happy", "欢迎来到店里面！柜台这边是今天的面包，后面那台是烤箱，想用随时说。")
	await _open_shop("bakery")


func _oven() -> void:
	var G := GameState
	if not G.flags.get("oven_intro", false):
		G.flags["oven_intro"] = true
		await _say("ren", "happy", "烤箱随便用！配方卡买了就是你的。小麦拿来的话，那台小石磨也能用。")
	s.ui.dialogue_end()
	await s.ui.panels.open_craft("oven")
	s.ui.dialogue_begin()


func _bakery() -> void:
	var G := GameState
	var why := G.shop_closed_reason("bakery")
	if why != "":
		await _say("narrator", "", "橱窗的灯灭了。门上写着：%s。" % why)
		return
	var c := await s.ui.choose(["买面包 · 配方卡", "借用烤箱（烘焙 / 磨面粉）", "只是闻闻面包香"])
	match c:
		0:
			s.ui.dialogue_end()
			await s.ui.panels.open_store("bakery")
			s.ui.dialogue_begin()
		1:
			if not G.flags.get("oven_intro", false):
				G.flags["oven_intro"] = true
				await _say("ren", "happy", "烤箱随便用！配方卡买了就是你的。小麦拿来的话，后面那台小石磨也能用。")
			s.ui.dialogue_end()
			await s.ui.panels.open_craft("oven")
			s.ui.dialogue_begin()
		_:
			await _say("narrator", "", "橱窗里摆着刚出炉的菠萝包和吐司。莲在门口招呼客人。")


func _sell(rate: float, where: String) -> void:
	var G := GameState
	var fest := G.festival_now() == "natsumatsuri" and where == "集市摊位"
	var goods := _market_goods() if where == "集市摊位" else G.produce_owned()
	if goods.is_empty():
		if where == "无人菜摊":
			await _say("narrator", "", "木架上摆着几个空竹篮，木箱上写着：“一个 50 円，请自觉投币”。")
		else:
			await _say("narrator", "", "摊位前排着小队。可惜你手上没有能卖的菜。")
		return
	var rate_of := func(iid: String) -> float:
		return G.FESTIVAL_STALL_RATE if fest and G.item(iid).has("dish") else rate
	var opts: Array = goods.map(func(i): return "%s 可售%d%s（每个 %d）" % [G.item_name(i), G.unreserved_count(i), "，%s" % G.reservation_note(i) if G.reserved_count(i) > 0 else "", G.unit_price(i, rate_of.call(i))])
	opts.append("全部卖掉")
	var c: int = await s.ui.choose_paged(opts)
	if c < 0:
		return
	var pick: Array = (_market_goods() if where == "集市摊位" else G.produce_owned()) if c == goods.size() else [goods[c]]
	var total := 0
	var n := 0
	for iid in pick:
		var k := G.unreserved_count(iid)
		total += G.sell_produce(iid, k, rate_of.call(iid))
		n += k
	if n == 0:
		return
	_toast("在%s卖出了 %d 份，+%d 生活币" % [where, n, total])
	if where == "无人菜摊" and G.at_step("Q07", "sell"):
		G.advance("Q07", "sell")
	if where == "集市摊位" and G.at_step("Q09", "sell_market") and int(G.flags.get("sold_market", 0)) >= 5:
		G.advance("Q09", "sell_market")


func _bench() -> void:
	var G := GameState
	var e := Dialogue.pick("place:farm_bench", {"region": "farm"})
	if not e.is_empty():
		Dialogue.mark(e)
		await _say("narrator", "", e.lines[0][2])
	if G.hour() < 21.0:
		var c := await s.ui.choose(["坐着看一小时河水", "起身"])
		if c == 0:
			await s.ui.fade_out(0.5)
			G.skip_to(minf(G.minute + 60.0, 23.0 * 60.0))
			s.world.update_time(G.minute, G.weather, true)
			await s.ui.fade_in(0.5)
			_toast("时间过去了一小时（%s）" % G.clock_text())


func _bed() -> void:
	var G := GameState
	var opts := []
	if G.hour() >= 18.0:
		opts = ["睡到明天早上", "只存个档", "算了"]
	elif G.minute < G.NAP_UNTIL:
		opts = ["午睡到傍晚（16:30）", "只存个档", "算了"]
	else:
		opts = ["只存个档", "算了"]
	await _say("sora", "neutral", "要休息一下吗？")
	var c := await s.ui.choose(opts)
	var pick: String = opts[c]
	if pick == "算了":
		return
	if pick == "只存个档":
		if G.save_game():
			Audio.sting("save")
			await _say("narrator", "", "进度已保存。")
		return
	s.ui.dialogue_end()
	s.main._transition = true
	G.lock_input("transition")
	await s.ui.fade_out(0.9)
	if pick.begins_with("睡到"):
		await s.main.sleep_now()
	else:
		G.skip_to(G.NAP_UNTIL)
		s.world.update_time(G.minute, G.weather, true)
		G.save_game()
		_toast("睡了个好觉。窗外已经是傍晚了")
	await s.ui.fade_in(0.8)
	G.unlock_input("transition")
	s.main._transition = false
	s.ui.dialogue_begin()


# ================================================================== everyday neighbour talk
## After quest-specific lines: a daily request, a gift, then a line from the dialogue pool.
func daily_talk(who: String,skip_neighbours: bool=false) -> void:
	var G := GameState
	var first := G.note_talk(who)
	if who=="haru" and not skip_neighbours and await s.neighbours.visit():return
	var r := G.request()
	if not r.is_empty() and not r.done and r.who == who and G.unreserved_count(r.item) >= int(r.n):
		var c := await s.ui.choose(["交给%s：%s ×%d（公告栏委托）" % [s.npc_name(who), G.item_name(r.item), int(r.n)], "等会儿再给"])
		if c == 0:
			var pay := G.fulfil_request(who)
			await _say(who, "happy", _thanks(who, r.item))
			_toast("完成了今天的委托：+%d 生活币" % pay)
			return
	var e := Dialogue.pick(who, s.CONVERSATION.context(s, who))
	if not e.is_empty():
		if not await present_entry(e): return
	elif first:
		await _say(who, "neutral", "今天也辛苦啦。")
	if e.get("give", {}).is_empty():
		await _offer_gift(who)


func present_entry(e: Dictionary) -> bool:
	var G := GameState
	var who: String = str(e.who)
	if not e.get("give", {}).is_empty() and not G.can_add_bundle(e.get("give", {})):
		await _say("narrator", "", "背包有点满。腾出位置后，再来领街坊留给你的东西。")
		return false
	for ln in e.lines:
		await _say(str(ln[0]), str(ln[1]), str(ln[2]))
	if e.has("choice"):
		var c: int = await s.ui.choose(e.choice.options)
		for ln in e.choice.replies[c]:
			await _say(str(ln[0]), str(ln[1]), str(ln[2]))
		if e.choice.has("flag"):
			G.flags[str(e.choice.flag)] = c
			G.state_changed.emit()
	for iid in e.get("give", {}):
		G.add_item(iid, int(e.give[iid]))
	Dialogue.mark(e)
	if e.get("event", false):
		G.add_warmth(who, 1)
		Audio.sting("sparkle")
	GameState.save_game()
	return true


func _offer_gift(who: String) -> void:
	var G := GameState
	if G.gifted_today(who):
		return
	var goods := G.giftables()
	if goods.is_empty():
		return
	goods.sort_custom(func(a, b): return G.gift_points(who, a) > G.gift_points(who, b))
	var opts: Array = goods.map(func(i): return "送一份%s" % G.item_name(i))
	var c: int = await s.ui.choose_paged(opts, "不用了")
	if c < 0:
		return
	var gift: String = goods[c]
	var liked: bool = G.gift_points(who, gift) >= (3 if G.item(gift).has("dish") else 2)
	var pts := G.give_gift(who, gift)
	if pts <= 0:
		return
	if liked:
		await _say(who, "happy", _loved(who, gift))
	elif pts >= 2:
		await _say(who, "happy", "是你自己做的？闻起来好香……谢谢你！")
	elif pts == 1:
		await _say(who, "happy", "谢谢你！自己种的菜，吃起来就是不一样。")


func _loved(who: String, iid: String) -> String:
	var n := GameState.item_name(iid)
	if who == "tanaka":
		return "……%s啊。嗯，这个我留着。谢谢。" % n
	if who == "mio" and GameState.item(iid).has("dish"):
		return "%s！我带回去当晚饭，谢谢你。" % n
	if who == "ren" and GameState.item(iid).has("dish"):
		return "%s！正好，关店后吃这个。得换换口味了。" % n
	if who == "haru":
		if GameState.item(iid).has("dish") or iid in ["onigiri", "melon_pan"]:
			return "哎呀，%s……我留给晚饭。谢谢你呀。" % n
		if GameState.item(iid).has("crop") and iid != "sunflower":
			return "%s正好。晚饭还缺一道菜，谢谢你呀。" % n
	return {
		"mio": "%s！我最喜欢了……你怎么知道的？今晚就做沙拉！" % n,
		"ren": "%s！正好想试一款新面包——谢啦，合伙人！" % n,
		"haru": "哎呀，%s……真漂亮。我要插在老头子的照片旁边。" % n,
		"tanaka": "……%s啊。嗯，长得不错。比我第一年种的强。" % n,
		"aoi": "哇——%s！！你是全世界最好的邻居！" % n,
	}.get(who, "谢谢！")


func _thanks(who: String, iid: String) -> String:
	var n := GameState.item_name(iid)
	if who=="haru":return "辛苦你啦。这些黄瓜我留着，盐由我出，拌好了分你一小份。" if iid=="cucumber" else "辛苦你啦。%s正好，我留着做晚饭。"%n
	return {
		"mio": "来得正好！%s是给社区食堂的，大家会很开心的。" % n,
		"ren": "太好了，这样明天的三明治就有着落了。谢谢你！",
		"haru": "辛苦你啦。%s我拿去腌一点，腌好了分你。" % n,
		"tanaka": "……嗯，个头匀称。你已经是个像样的农人了。",
		"aoi": "谢谢！这是给奶奶的惊喜，要保密哦！",
	}.get(who, "谢谢！")

class_name GamePanels
extends RefCounted
## v0.5 panels built on GameUI's modal system: shops (buy / sell tabs), cooking and baking, the
## tabbed backpack, the home chest, the calendar, and the non-blocking cards (level up, festival,
## last night's ledger). Tests and autoplay drive them through ui.auto_choices (see each function).

var ui: GameUI
var _card_box: VBoxContainer
var _cards: Array = []
var _pending_cards: Array[Dictionary] = []

const TABS := [["all", "全部", "tab_all"], ["seed", "种子", "tab_seed"], ["crop", "作物", "tab_crop"],
	["fish", "鲜鱼", "fish"], ["dish", "料理", "tab_dish"], ["material", "材料", "tab_material"], ["key", "重要", "tab_key"]]


func _init(game_ui: GameUI) -> void:
	ui = game_ui
	_card_box = VBoxContainer.new()
	_card_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	GameUI._dock(_card_box, -250, 250, 120)
	_card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_box.add_theme_constant_override("separation", 10)
	ui.ambient_layer.add_child(_card_box)


## Hide/show the non-blocking notification cards (level up, achievement unlocked, festival
## announced, ...). Used by the evidence camera to capture clean marketing screenshots.
func set_cards_visible(v: bool) -> void:
	_card_box.visible = v


static func kind(iid: String) -> String:
	var it := GameState.item(iid)
	if GameState.is_key_item(iid):
		return "key"
	if it.has("seed"):
		return "seed"
	if it.has("crop"):
		return "crop"
	if it.get("fish",false):
		return "fish"
	if it.has("dish") or iid in ["onigiri", "melon_pan", "candy_apple"]:
		return "dish"
	return "material"


func _row_box() -> StyleBoxTexture:
	return UIKitStyles.row()


func _btn(text: String, cb: Callable, w: int = 110, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 50)
	b.disabled = not enabled
	b.pressed.connect(cb)
	return b


func _banner(v: VBoxContainer, id: String, w: int = 960) -> void:
	var p := "res://assets/ui/banners/%s.jpg" % id
	if not ResourceLoader.exists(p):p="res://assets/ui/banners/%s.png"%id
	if id == "" or not ResourceLoader.exists(p):
		return
	var tr := TextureRect.new()
	tr.texture = load(p)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.custom_minimum_size = Vector2(w, w / 5.0)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tr)


func _scroll(h: int) -> Array:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(960, h)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	return [sc, list]


func _chip(iid: String, have: int, need: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.add_child(UITheme.icon(str(GameState.item(iid).get("icon", iid)), 34))
	h.add_child(UITheme.label("%s %d/%d" % [GameState.item_name(iid), have, need], 20, UITheme.GOOD if have >= need else UITheme.BAD))
	return h


## Run the scripted choice for tests / autoplay: returns true when the panel was handled.
func _scripted(apply: Callable) -> bool:
	if not (ui.instant or ui.auto):
		return false
	var pick = ui.auto_choices.pop_front() if not ui.auto_choices.is_empty() else {}
	if ui.instant:
		apply.call(pick)
		return true
	ui.get_tree().create_timer(1.4).timeout.connect(func():
		apply.call(pick)
		ui.get_tree().create_timer(1.4).timeout.connect(func(): if ui.modal != "": ui.close_modal(), CONNECT_ONE_SHOT), CONNECT_ONE_SHOT)
	return false


# ================================================================== shops
var _sid := ""
var _tab := "buy"
var _list: VBoxContainer
var _status: Label
var _money: Label


func open_store(sid: String) -> void:
	var sh := GameState.shop(sid)
	_sid = sid
	_tab = "buy"
	var p := ui._open_modal("shop")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	_banner(v, str(sh.get("banner", "")))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.add_child(ui._header(str(sh.name), "coin_stack"))
	var spc := Control.new()
	spc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spc)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 8)
	tb.add_child(_btn("买东西", func(): _set_tab("buy"), 130))
	if not (sh.get("buys", []) as Array).is_empty():
		tb.add_child(_btn("卖东西", func(): _set_tab("sell"), 130))
	top.add_child(tb)
	v.add_child(top)
	var line := UITheme.label("%s：「%s」" % [sh.keeper, sh.line], 22, UITheme.INK_SOFT)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(960, 0)
	v.add_child(line)
	var sl := _scroll(430 if str(sh.get("banner", "")) != "" else 560)
	v.add_child(sl[0])
	_list = sl[1]
	_money = UITheme.label("", 24)
	_status = UITheme.label("", 22)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(960, 0)
	var bot := HBoxContainer.new()
	bot.add_child(_money)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(sp2)
	var cb := ui._close_button("走了")
	bot.add_child(cb)
	v.add_child(_status)
	v.add_child(bot)
	_refresh_store()
	cb.call_deferred("grab_focus")
	ui._center(p)
	if _scripted(func(pick): _apply_store(pick)):
		ui.close_modal(false)
		return
	await ui.panel_closed


## pick: {"buy": {id: n}, "sell": {id: n or -1 for all}} or the old style [id, id, ...]
func _apply_store(pick) -> void:
	if typeof(pick) == TYPE_ARRAY:
		for iid in pick:
			store_buy(str(iid), 1)
		return
	if typeof(pick) != TYPE_DICTIONARY:
		return
	var b: Dictionary = pick.get("buy", {})
	for iid in b:
		store_buy(str(iid), int(b[iid]))
	var s: Dictionary = pick.get("sell", {})
	for iid in s:
		store_sell(str(iid), GameState.count(iid) if int(s[iid]) < 0 else int(s[iid]))


func _set_tab(t: String) -> void:
	_tab = t
	_refresh_store()


func _set_bag_tab(t: String) -> void:
	_bag_tab = t
	_refresh_bag()


func store_buy(iid: String, n: int) -> void:
	var err := GameState.buy_item(iid, n)
	_say_status(err, "买好了：%s ×%d" % [GameState.item_name(iid), n] if not GameState.item(iid).has("upgrade") else "买好了：%s" % GameState.item_name(iid))
	_refresh_store()


func store_sell(iid: String, n: int) -> void:
	var sh := GameState.shop(_sid)
	n = mini(n, GameState.unreserved_count(iid))
	var pay := GameState.sell_produce(iid, n, float(sh.get("rate", 1.0)))
	_say_status(GameState.reservation_note(iid) if n == 0 and GameState.reserved_count(iid) > 0 else ("" if pay > 0 else "卖不了"), "卖出 %s ×%d，+%d 生活币" % [GameState.item_name(iid), n, pay])
	_refresh_store()


func _say_status(err: String, ok_text: String) -> void:
	if _status == null:
		return
	_status.text = ok_text if err == "" else err
	_status.add_theme_color_override("font_color", UITheme.GOOD if err == "" else UITheme.BAD)


func _refresh_store() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var G := GameState
	_money.text = "现有 %d 生活币 · 背包 %d/%d 格" % [G.coins, G.slots_used(), G.bag_cap]
	var sh := G.shop(_sid)
	if _tab == "buy":
		for iid in G.shop_stock(_sid):
			_list.add_child(_buy_row(iid))
	else:
		var rate := float(sh.get("rate", 1.0))
		var any := false
		for iid in G.inventory.keys():
			if G.buys_item(_sid, iid):
				_list.add_child(_sell_row(iid, rate))
				any = true
		if not any:
			_list.add_child(UITheme.label("背包里没有这家店收的东西。", 24, UITheme.INK_SOFT))


func _buy_row(iid: String) -> PanelContainer:
	var G := GameState
	var it := G.item(iid)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_box())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	h.add_child(UITheme.icon(str(it.get("icon", iid)), 64))
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var have := G.count(iid)
	tv.add_child(UITheme.label("%s　%d 生活币%s" % [it.name, int(it.get("price", 0)), ("　（有 %d）" % have) if have > 0 else ""], 24))
	var info := str(it.get("desc", ""))
	if it.has("seed"):
		var c := G.crop_def(str(it.seed))
		info = "%d 天成熟%s，一次收 %d 个，每个卖 %d" % [int(c.days), ("，之后每 %d 天再收" % int(c.regrow)) if int(c.regrow) > 0 else "", int(c["yield"]), int(c.sell)]
		if c.get("greenhouse", false):
			info += "（只能种在温室）"
	var d := UITheme.label(info, 19, UITheme.INK_SOFT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(560, 0)
	tv.add_child(d)
	h.add_child(tv)
	var block := G.buy_block(iid, 1)
	if block.begins_with("种植等级") or block.begins_with("先买"):
		h.add_child(UITheme.label("🔒 " + block, 20, UITheme.BAD))
	else:
		var once: bool = it.has("upgrade") or it.has("recipe")
		h.add_child(_btn("买 1" if not once else "买下", func(): store_buy(iid, 1), 96))
		if not once:
			h.add_child(_btn("买 5", func(): store_buy(iid, 5), 96))
	return row


func _sell_row(iid: String, rate: float) -> PanelContainer:
	var G := GameState
	var it := G.item(iid)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_box())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	h.add_child(UITheme.icon(str(it.get("icon", iid)), 64))
	var n := G.count(iid)
	var free := G.unreserved_count(iid)
	var held := mini(n, G.reserved_count(iid))
	var unit := G.unit_price(iid, rate)
	var sold := int(G.daily.get("sold_n", {}).get(iid, 0))
	var tl := UITheme.label("%s ×%d　每个 %d%s%s" % [it.name, n, unit, "（今天收得多了，打七折）" if sold >= G.GLUT_N else "", "\n%s · 可出售 %d" % [GameState.reservation_note(iid), free] if held > 0 else ""], 24)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tl)
	h.add_child(_btn("卖 1", func(): store_sell(iid, 1), 96, free > 0))
	h.add_child(_btn("卖可售部分（%d）" % G.sale_value(iid, free, rate), func(): store_sell(iid, G.unreserved_count(iid)), 185, free > 0))
	return row


func open_bakery_order() -> void:
	var G := GameState
	var p := ui._open_modal("bakery_order")
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(760, 0)
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	v.add_child(ui._header("莲的供货纸签", "bread_basket"))
	var menu := "菠萝包为主，三明治少量试吃" if int(G.flags.get("bakery_menu", 0)) == 0 else "街坊三明治为主，也留菠萝包"
	v.add_child(UITheme.label(menu, 26))
	var due := int(G.flags.get("bakery_due_day", G.next_market_day()))
	v.add_child(UITheme.label("第 %d 天 · 周六 16:30–22:00，在庭院摊位交给莲" % due, 22, UITheme.INK_SOFT))
	for iid in G.BAKERY_ORDER:
		v.add_child(_chip(iid, G.count(iid), int(G.BAKERY_ORDER[iid])))
	var hint := UITheme.label("订单会预留这些菜，卖东西和做其他料理会保留它们。赶不上可以改约；选择店里材料后，这次不发供货报酬，试吃剧情照常继续。", 22, UITheme.INK_SOFT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(740, 0)
	v.add_child(hint)
	if G.flags.get("bakery_order_active", false):
		v.add_child(_btn("改到下一次周六", func():
			G.flags["bakery_due_day"] = maxi(G.next_market_day(true), due + 7)
			G.state_changed.emit()
			G.save_game()
			ui.close_modal(), 250))
		v.add_child(_btn("这次用店里材料，取消预留", func():
			G.flags["bakery_order_active"] = false
			G.flags["bakery_shop_stock"] = true
			G.state_changed.emit()
			G.save_game()
			ui.close_modal(), 350))
	else:
		v.add_child(UITheme.label("这次由莲准备材料，没有预留。", 22, UITheme.GOOD))
	var close := ui._close_button("收好纸签")
	v.add_child(close)
	ui._center(p)
	close.call_deferred("grab_focus")
	if _scripted(func(_pick): pass):
		ui.close_modal(false)
		return
	await ui.panel_closed


# ================================================================== cooking / baking
var _station := ""


func open_craft(station: String) -> void:
	_station = station
	var p := ui._open_modal("craft")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	_banner(v, "ban_kitchen_anime" if station == "kitchen" else "ban_bakery")
	var top := HBoxContainer.new()
	top.add_child(ui._header("家里的厨房" if station == "kitchen" else "莲的烤箱", "st_pot" if station == "kitchen" else "st_oven"))
	var spc := Control.new()
	spc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spc)
	var clock := UITheme.label("", 22, UITheme.INK_SOFT)
	top.add_child(clock)
	v.add_child(top)
	var sl := _scroll(440)
	v.add_child(sl[0])
	_list = sl[1]
	_status = UITheme.label("做料理要花时间：时钟会往前走。做好的料理可以卖、送人，也能在集市和夏祭上卖出好价钱。", 21, UITheme.INK_SOFT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(960, 0)
	v.add_child(_status)
	_money = clock
	var cb := ui._close_button("收拾好了")
	v.add_child(cb)
	_refresh_craft()
	cb.call_deferred("grab_focus")
	ui._center(p)
	if _scripted(func(pick): _apply_craft(pick)):
		ui.close_modal(false)
		return
	await ui.panel_closed


## pick: {"craft": {rid: n}}
func _apply_craft(pick) -> void:
	if typeof(pick) != TYPE_DICTIONARY:
		return
	var c: Dictionary = pick.get("craft", {})
	for rid in c:
		craft(str(rid), int(c[rid]))


func craft(rid: String, n: int) -> void:
	var out: Dictionary = GameState.recipe(rid).get("output", {}).duplicate(true)
	var err := GameState.craft(rid, n)
	var oid: String = out.keys()[0] if not out.is_empty() else ""
	if err == "":
		if rid == "first_home_onigiri":
			DailyLife.event("meal")["method"] = "simple"
			GameState.save_game()
		Audio.fx("place")
		Audio.sting("item")
		ui.celebrate(GameState.item_name(oid),str(GameState.item(oid).get("icon",oid)),"×%d"%(int(out.get(oid,1))*n))
	_say_status(err, "做好了：%s ×%d（现在 %s）" % [GameState.item_name(oid), int(out.get(oid, 1)) * n, GameState.clock_text()])
	_refresh_craft()

func _shape_home_meal() -> void:
	StoryKnowledge.observe_activity("onigiri")
	GameState.save_game()
	# Finish the stove's awaiting interaction before transferring control to its short action.
	GameState.lock_input("meal_shape")
	ui.close_modal()
	await ui.get_tree().process_frame
	var result: Dictionary = await ui.play_minigame("onigiri", {"mode": "home_meal", "start_requested": true})
	GameState.unlock_input("meal_shape")
	if not result.get("completed", false) or not result.get("outcome", {}).get("shaped", false):
		GameState.toast.emit("米料还留着，灶台上随时可以继续。")
		return
	var why: String = GameState.craft("first_home_onigiri", 1)
	if why != "":
		GameState.toast.emit(why)
		return
	DailyLife.event("meal")["method"] = "shaped"
	GameState.save_game()
	GameState.toast.emit("两份饭团包好了。回饭桌决定吃一份还是收好。")


func _refresh_craft() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var G := GameState
	_money.text = "%s %s" % [G.date_text(), G.clock_text()]
	var ids := G.station_recipes(_station)
	ids.sort_custom(func(a, b):
		var pa: int = (4 if a == "first_home_onigiri" and G.craft_block(a, 1) == "" else 0) + (2 if G.craft_block(a, 1) == "" else 0) + int(G.recipe_known(a))
		var pb: int = (4 if b == "first_home_onigiri" and G.craft_block(b, 1) == "" else 0) + (2 if G.craft_block(b, 1) == "" else 0) + int(G.recipe_known(b))
		return pa > pb)
	for rid in ids:
		_list.add_child(_craft_row(rid))


func _craft_row(rid: String) -> PanelContainer:
	var G := GameState
	var r := G.recipe(rid)
	var out: Dictionary = r.output
	var oid: String = out.keys()[0]
	var known := G.recipe_known(rid)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_box() if known else UIKitStyles.row("disabled"))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	h.add_child(UITheme.icon(str(G.item(oid).get("icon", oid)), 64))
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sell := int(G.item(oid).get("sell", 0))
	tv.add_child(UITheme.label("%s%s　%d 分钟%s" % [r.name, (" ×%d" % int(out[oid])) if int(out[oid]) > 1 else "", int(r.minutes),
			("　卖 %d" % sell) if sell > 0 else ""], 24, UITheme.INK if known else UITheme.INK_SOFT))
	if known:
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 14)
		for k in r.inputs:
			chips.add_child(_chip(k, G.count(k), int(r.inputs[k])))
		chips.custom_minimum_size = Vector2(560, 0)
		tv.add_child(chips)
	else:
		tv.add_child(UITheme.label("🔒 " + G.recipe_hint(rid), 20, UITheme.INK_SOFT))
	h.add_child(tv)
	if known:
		var mx := G.craft_max(rid)
		if rid == "first_home_onigiri":
			h.add_child(_btn("亲手捏形", _shape_home_meal, 160, G.craft_block(rid, 1) == ""))
		var make_one := _btn("做 1 批 · %d 份" % int(out[oid]), func(): craft(rid, 1), 180, G.craft_block(rid, 1) == "")
		make_one.set_meta("recipe_id", rid)
		make_one.set_meta("batches", 1)
		h.add_child(make_one)
		if mx > 1:
			h.add_child(_btn("做 %d 批 · %d 份" % [mini(mx, 5), mini(mx, 5) * int(out[oid])], func(): craft(rid, mini(G.craft_max(rid), 5)), 190, G.craft_block(rid, mini(mx, 5)) == ""))
	return row


# ================================================================== backpack
var _bag_tab := "all"
var _bag_grid: GridContainer
var _bag_desc: Label
var _bag_cap: Label


func open_bag() -> void:
	var p := ui._open_modal("inventory")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.add_child(ui._header("背包", "backpack"))
	var spc := Control.new()
	spc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spc)
	top.add_child(UITheme.icon("level_badge", 40))
	var pr := GameState.level_progress()
	top.add_child(UITheme.label("种植 Lv%d（%s）" % [GameState.level(), ("%d/%d" % pr) if pr[1] > 0 else "满级"], 24))
	top.add_child(UITheme.icon("coin", 40))
	top.add_child(UITheme.label("%d 生活币" % GameState.coins, 26))
	v.add_child(top)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for t in TABS:
		var b := Button.new()
		b.text = t[1]
		b.icon = UITheme.icon_texture(t[2])
		b.expand_icon = true
		b.custom_minimum_size = Vector2(140, 52)
		var tid: String = t[0]
		b.pressed.connect(func(): _set_bag_tab(tid))
		tabs.add_child(b)
	v.add_child(tabs)
	_bag_cap = UITheme.label("", 22, UITheme.INK_SOFT)
	v.add_child(_bag_cap)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1060, 330)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = 10
	_bag_grid.add_theme_constant_override("h_separation", 8)
	_bag_grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(_bag_grid)
	v.add_child(sc)
	_bag_desc = UITheme.label("把鼠标移到物品上查看说明。", 22, UITheme.INK_SOFT)
	_bag_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bag_desc.custom_minimum_size = Vector2(1060, 60)
	v.add_child(_bag_desc)
	var close := ui._close_button()
	v.add_child(close)
	_refresh_bag()
	ui._center(p)


func _describe(iid: String) -> String:
	var it := GameState.item(iid)
	var extra := ""
	if int(it.get("sell", 0)) > 0 and not GameState.is_key_item(iid):
		extra = "　卖价 %d" % int(it.sell)
	return "%s — %s%s" % [it.get("name", iid), it.get("desc", ""), extra]


func _refresh_bag() -> void:
	if _bag_grid == null:
		return
	for c in _bag_grid.get_children():
		c.queue_free()
	var G := GameState
	_bag_cap.text = "普通物品 %d / %d 格（每格最多 %d 个）· 家里玄关旁的收纳箱能放 %d 格" % [G.slots_used(), G.bag_cap, G.STACK_MAX, G.STORAGE_SLOTS]
	var ids: Array = []
	if _bag_tab == "key" or _bag_tab == "all":
		ids.append_array(G.key_items.keys())
	for iid in G.inventory:
		if _bag_tab == "all" or kind(iid) == _bag_tab:
			ids.append(iid)
	for iid in ids:
		var n: int = G.count(iid)
		_bag_grid.add_child(_slot(iid, n))
	if _bag_tab == "all":
		for i in maxi(0, G.bag_cap - G.slots_used()):
			_bag_grid.add_child(_slot("", 0))


func _slot(iid: String, n: int, on_click: Callable = Callable()) -> PanelContainer:
	var s := PanelContainer.new()
	var size := 96
	s.custom_minimum_size = Vector2(size, size)
	var key := iid != "" and GameState.is_key_item(iid)
	s.add_theme_stylebox_override("panel", UIKitStyles.slot("selected" if key else ("normal" if iid!="" else "empty")))
	if iid == "":
		return s
	var it := GameState.item(iid)
	var ov := Control.new()
	s.add_child(ov)
	ov.add_child(UITheme.icon(str(it.get("icon", iid)), size - 16))
	if n > 1:
		var c := UITheme.label("×%d" % n, 21)
		c.position = Vector2(size - 56, size - 40)
		ov.add_child(c)
	s.tooltip_text = str(it.get("name", iid))
	s.mouse_entered.connect(func(): if _bag_desc: _bag_desc.text = _describe(iid))
	if on_click.is_valid():
		s.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed:
				on_click.call(iid, ev.button_index == MOUSE_BUTTON_RIGHT))
	return s


# ================================================================== the home chest
var _chest_bag: GridContainer
var _chest_box: GridContainer


func open_storage() -> void:
	var p := ui._open_modal("storage")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(ui._header("收纳箱", "storage_box"))
	v.add_child(UITheme.label("左键：整组放进 / 取出　右键：只移 1 个。重要物品不能放进箱子。", 21, UITheme.INK_SOFT))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var mk := func(title: String) -> GridContainer:
		var col := VBoxContainer.new()
		col.add_child(UITheme.label(title, 24))
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(530, 420)
		var g := GridContainer.new()
		g.columns = 5
		g.add_theme_constant_override("h_separation", 8)
		g.add_theme_constant_override("v_separation", 8)
		sc.add_child(g)
		col.add_child(sc)
		h.add_child(col)
		return g
	_chest_bag = mk.call("背包")
	_chest_box = mk.call("收纳箱")
	v.add_child(h)
	_bag_desc = UITheme.label("", 22, UITheme.INK_SOFT)
	v.add_child(_bag_desc)
	v.add_child(ui._close_button())
	_refresh_storage()
	ui._center(p)
	if _scripted(func(pick): _apply_storage(pick)):
		ui.close_modal(false)
		return
	await ui.panel_closed


## pick: {"store": {id: n or -1}, "take": {id: n or -1}}
func _apply_storage(pick) -> void:
	if typeof(pick) != TYPE_DICTIONARY:
		return
	var G := GameState
	var st: Dictionary = pick.get("store", {})
	for iid in st:
		G.store_in(str(iid), G.count(iid) if int(st[iid]) < 0 else int(st[iid]))
	var tk: Dictionary = pick.get("take", {})
	for iid in tk:
		G.take_out(str(iid), int(G.storage.get(iid, 0)) if int(tk[iid]) < 0 else int(tk[iid]))
	_refresh_storage()


func _refresh_storage() -> void:
	if _chest_bag == null:
		return
	var G := GameState
	for g in [_chest_bag, _chest_box]:
		for c in g.get_children():
			c.queue_free()
	for iid in G.inventory:
		_chest_bag.add_child(_slot(iid, G.count(iid), func(id, one):
			if not G.store_in(id, 1 if one else G.count(id)):
				G.toast.emit("收纳箱满了")
			Audio.ui("select")
			_refresh_storage()))
	for iid in G.storage:
		_chest_box.add_child(_slot(iid, int(G.storage[iid]), func(id, one):
			if not G.take_out(id, 1 if one else int(G.storage.get(id, 0))):
				G.toast.emit("背包满了")
			Audio.ui("select")
			_refresh_storage()))
	if _bag_desc:
		_bag_desc.text = "背包 %d/%d 格 · 收纳箱 %d/%d 格" % [G.slots_used(), G.bag_cap, G.storage_used(), G.STORAGE_SLOTS]


# ================================================================== calendar
func open_calendar() -> void:
	var G := GameState
	var p := ui._open_modal("calendar")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var dt := G.date_of(G.day)
	v.add_child(ui._header("%d月 · 晴町的夏天" % dt.x, "calendar"))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for w in ["一", "二", "三", "四", "五", "六", "日"]:
		var l := UITheme.label("周" + w, 22, UITheme.INK_SOFT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(140, 0)
		grid.add_child(l)
	# first game day of this month
	var first := G.day - (dt.y - 1)
	var lead: int=_calendar_weekday(first)
	for i in lead:
		grid.add_child(Control.new())
	var d := first
	while G.date_of(d).x == dt.x:
		grid.add_child(_cal_cell(d))
		d += 1
	v.add_child(grid)
	var nf := G.next_festival()
	if nf != "":
		var f := G.festival(nf)
		_banner(v, str(f.banner), 900)
		var l := UITheme.label("下一个节日：%s · %s（%s）%02d:%02d 起　%s" % [f.name, G.date_text(int(f.day)), G.weekday_name(int(f.day)),
				int(f.start), int(fmod(float(f.start), 1.0) * 60), f.desc], 22)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(1000, 0)
		v.add_child(l)
	if G.calendar_pending_save == G.day:
		var retry := Button.new()
		retry.text = "重试保存暂停的这一天"
		retry.pressed.connect(func():
			ui.close_modal(false)
			await ui.get_parent().calendar.run("retry_save"))
		v.add_child(retry)
	for appointment: Dictionary in CalendarAdvance.appointments():
		var button := Button.new()
		button.text = "去约好的%s · %s" % [str(appointment.title), G.date_text(int(appointment.day))]
		var selected: String = str(appointment.id)
		button.pressed.connect(func(): _advance_appointment(selected))
		v.add_child(button)
	v.add_child(ui._close_button())
	ui._center(p)

func _advance_appointment(id: String) -> void:
	var target: Dictionary = CalendarAdvance.appointment(id)
	if target.is_empty(): return
	ui.close_modal(false)
	ui.dialogue_begin()
	await ui.say("narrator", "", "歇到约好的时间，再从家里出门。菜照浇水和天气继续长，没做完的活儿还留着。")
	var choice: int = await ui.choose(["准备好了，歇到约定时间", "再忙一会儿"])
	ui.dialogue_end()
	if choice == 0:
		var scene: Node = ui.get_parent()
		await scene.calendar.run(id)


func _calendar_weekday(d: int) -> int:
	# Calendar dates before moving day are real dates, not weekday()'s negative sentinel.
	return posmod(d-1+GameState.FIRST_WEEKDAY,7)

func _cal_cell(d: int) -> PanelContainer:
	var G := GameState
	var c := PanelContainer.new()
	var today := d == G.day
	var fid := G.festival_on(d)
	c.add_theme_stylebox_override("panel", UIKitStyles.slot("selected" if today else "normal",6))
	if fid!="" and not today:c.get_theme_stylebox("panel").modulate_color=Color(1.0,.95,.91)
	c.custom_minimum_size = Vector2(140, 74)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	c.add_child(v)
	v.add_child(UITheme.label("%d%s" % [G.date_of(d).y, "  今天" if today else ""], 20, UITheme.INK if d >= G.day else UITheme.INK_SOFT))
	var note := ""
	if fid != "":
		note = str(G.festival(fid).name)
	elif _calendar_weekday(d) == G.SATURDAY:
		note = "傍晚集市"
	elif _calendar_weekday(d) == 2:
		note = "商店休息"
	if note != "":
		v.add_child(UITheme.label(note, 18, UITheme.BAD if fid != "" else UITheme.INK_SOFT))
	return c


# ================================================================== cards (non-blocking)
func card(title: String, lines: Array, icon_id: String = "", banner: String = "", secs: float = 5.0) -> void:
	if ui.conversation_active:
		if not _pending_cards.any(func(entry: Dictionary):return entry.title==title):
			_pending_cards.append({"title":title,"lines":lines.duplicate(true),"icon":icon_id,"banner":banner,"secs":secs})
		while _pending_cards.size()>2:_pending_cards.pop_front()
		return
	# the same card twice in a row (e.g. a festival announced by two systems) shows once
	for c in _cards:
		if is_instance_valid(c) and c.get_meta("title", "") == title:
			return
	# keep at most two cards on screen: the newest replaces the oldest
	while _cards.size() >= 2:
		var old: Control = _cards.pop_front()
		old.queue_free()
	var p := PanelContainer.new()
	p.set_meta("title", title)
	p.add_theme_stylebox_override("panel", UIKitStyles.notice("info",14))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	if banner != "":
		_banner(v, banner, 470)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	if icon_id != "":
		h.add_child(UITheme.icon(icon_id, 40))
	h.add_child(UITheme.label(title, 26))
	v.add_child(h)
	for ln in lines:
		var l := UITheme.label(str(ln), 19, UITheme.INK_SOFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(470, 0)
		v.add_child(l)
	_card_box.add_child(p)
	_cards.append(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.3)
	tw.tween_interval(0.1 if ui.instant else secs)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func():
		_cards.erase(p)
		if is_instance_valid(p):
			p.queue_free())


func flush_dialogue_cards() -> void:
	var queued: Array[Dictionary] = _pending_cards.duplicate(true)
	_pending_cards.clear()
	for entry: Dictionary in queued:
		card(entry.title,entry.lines,entry.icon,entry.banner,entry.secs)

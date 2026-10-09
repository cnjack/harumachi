class_name StoryBakery
extends RefCounted
## A small, optional partnership. Recipe, reservations and payments live in GameState.
var s: Story


func _init(story: Story) -> void:
	s = story


func checks() -> void:
	var G := GameState
	if G.qstate("Q16") == "locked" and G.qstate("Q05") == "done" and G.qstate("Q06") == "done":
		G.quests["Q16"] = {"state": "available", "step": 0}
		G.toast.emit("莲在面包店留了一张试吃纸签。也可以按 J 查看新委托。")
		G.quest_changed.emit("Q16")
		G.state_changed.emit()
	if G.at_step("Q16", "bakery_bake") and G.flags.get("bakery_trial_baked", false):
		G.advance("Q16", "bakery_bake")
		G.save_game()


func pending(id: String) -> bool:
	var G := GameState
	if id == "bakery_orders":
		return true
	if id == "ren":
		return G.qstate("Q16") == "active" and not G.at_step("Q16", "bakery_taste")
	if id in ["mio", "haru", "kazuko", "store_counter"]:
		var who := "kazuko" if id == "store_counter" else id
		return G.at_step("Q16", "bakery_taste") and not G.flags.get("bakery_tasters", {}).has(who)
	if id == "stall":
		return G.bakery_order_ready() and G.phase == "market"
	return false


func prompt(id: String) -> Variant:
	if not pending(id):
		return null
	if id == "stall":
		return "交给莲这一篮菜 / 卖其他东西"
	if id in ["mio", "haru", "kazuko", "store_counter"]:
		return "请%s尝尝三明治" % ("和子阿姨" if id in ["kazuko", "store_counter"] else s.npc_name(id))
	return "和莲聊试做与供货" if GameState.qstate("Q16") != "locked" else "看看柜台旁的试吃纸签"


func handle(id: String) -> void:
	if id == "stall":
		await _market()
	elif id in ["mio", "haru", "kazuko", "store_counter"]:
		await _taste("kazuko" if id == "store_counter" else id)
	else:
		await _ren()
	GameState.save_game()


func _ren() -> void:
	var G := GameState
	if G.qstate("Q16") == "locked":
		await s.say("ren", "neutral", "这张纸还空着。等农园那边安顿好了，咱们试个新面包。")
		return
	if G.qstate("Q16") == "available":
		await s.say("ren", "neutral", "这个给你。今天稍微……多做了两个。")
		await s.say("sora", "neutral", "柜台里还有六个。")
		await s.say("ren", "neutral", "……你别数那么仔细。要不做一份夹黄瓜的，让街坊尝尝？")
		var accept := await s.ui.choose(["试一份，先找人尝尝", "今天先歇一歇"])
		if accept != 0:
			await s.say("ren", "happy", "行。这张纸留着，什么时候想试了再来。")
			return
		G.start_quest("Q16")
		G.recipes_known["veg_sandwich"] = true
		await s.say("ren", "happy", "配方给你，烤箱也借你。一份试做材料我出了。")
		await _kit()
		G.save_game()
		return
	if G.at_step("Q16", "bakery_bake"):
		if not G.flags.get("bakery_kit_claimed", false):
			await _kit()
		else:
			await s.say("ren", "neutral", "烤箱在里面。黄瓜一根、番茄两个，再加面粉和黄油；就做一份。")
		return
	if G.at_step("Q16", "bakery_trial"):
		if not G.has("veg_sandwich"):
			await s.say("ren", "neutral", "三明治不在手上？没事，烤箱还借你。做一份再来，时间够。")
			return
		G.remove_item("veg_sandwich", 1)
		G.add_item("bakery_sample", 3, true)
		G.flags["bakery_tasters"] = {}
		G.advance("Q16", "bakery_trial")
		await s.say("ren", "happy", "切成三小份。澪、春婆婆、和子阿姨，找两个人就好。剩下一份你吃。")
		return
	if G.at_step("Q16", "bakery_taste"):
		await s.say("ren", "neutral", "和子阿姨多半会说好吃。得再找个肯说实话的。")
		return
	if G.at_step("Q16", "bakery_menu"):
		await s.say("ren", "neutral", "有人喜欢清爽，有人说切小份好拿。周六，咱们先摆哪一篮？")
		var menu := await s.ui.choose(["菠萝包为主，三明治少量试吃", "街坊三明治为主，也留菠萝包"])
		G.flags["bakery_menu"] = menu
		G.bakery_accept_order()
		G.advance("Q16", "bakery_menu")
		if menu == 0:
			await s.say("ren", "happy", "好。老味道留着，三明治先做一小篮。")
		else:
			await s.say("ren", "happy", "那我把三明治的牌子摆前面。菠萝包也不撤。")
		await s.say("ren", "neutral", "留两颗番茄、一根黄瓜。周六傍晚在庭院交；赶不上就来改约。")
		return
	if G.at_step("Q16", "bakery_supply") or G.flags.get("bakery_order_active", false):
		await _order()
		return
	if G.at_step("Q16", "bakery_followup"):
		if G.day <= int(G.flags.get("bakery_served_day", G.day)):
			await s.say("ren", "happy", "今天这篮先让大家尝尝。明天来，我把意见写到纸上。")
			return
		if G.flags.get("bakery_supplied_first", false):
			await s.say("ren", "happy", "今天有人直接问街坊三明治。还记得你那篮菜。")
		else:
			await s.say("ren", "happy", "这次用的店里材料。大家问起试吃，我说是你帮忙定的主意。")
		await s.say("ren", "neutral", "下个周六，还想一起做一篮吗？忙的话，歇一周也行。")
		var next := await s.ui.choose(["接下一篮，替你留菜", "这周先歇一歇"])
		G.remove_item("bakery_sample", G.count("bakery_sample"))
		G.flags["bakery_offer_after"] = G.next_market_day(true)
		G.advance("Q16", "bakery_followup")
		G.add_warmth("ren", 2)
		if next == 0:
			G.bakery_accept_order()
		G.save_game()
		return
	await s.say("ren", "happy", "这张试吃牌还在。看见它，就想起你挨个找人尝面包那天。")
	if G.day >= int(G.flags.get("bakery_offer_after", 0)):
		var again := await s.ui.choose(["接下一次周六的小订单", "这次先休息"])
		G.flags["bakery_offer_after"] = G.next_market_day(true)
		if again == 0:
			G.bakery_accept_order()
		G.save_game()


func _kit() -> void:
	if GameState.bakery_claim_kit():
		await s.say("ren", "happy", "材料装好了。背包里这一份够做三明治，别忘了留给试吃。")
	else:
		await s.say("ren", "neutral", "背包有点挤。腾出位置再来，材料我放着。")


func _taste(who: String) -> void:
	if not GameState.bakery_taste(who):
		return
	match who:
		"mio":
			await s.say("mio", "happy", "黄瓜脆脆的。天热的时候，拿着这个边走边吃挺好。")
		"haru":
			await s.say("haru", "happy", "切小一点就好了。坐着吃，也不用两只手都拿着。")
		"kazuko":
			await s.say("kazuko", "happy", "好吃！……等等，别光记好吃。让莲少放一点汁，纸袋就不会湿。")
	if GameState.flags.get("bakery_tasters", {}).size() >= 2:
		GameState.advance("Q16", "bakery_taste")
		GameState.toast.emit("两位街坊尝过了。回面包店和莲定下周六的试吃。")
	GameState.save_game()


func _order() -> void:
	var G := GameState
	await s.say("ren", "neutral", "订单在试吃纸签上。改约和休息都可以，提前跟我说就好。")
	var pick := await s.ui.choose(["看看订单与预留", "改到下一次周六", "这次用店里材料，取消预留", "以后再聊"])
	if pick == 0:
		s.ui.dialogue_end()
		await s.ui.panels.open_bakery_order()
		s.ui.dialogue_begin()
	elif pick == 1:
		G.flags["bakery_due_day"] = maxi(G.next_market_day(true), int(G.flags.get("bakery_due_day", G.day)) + 7)
		await s.say("ren", "happy", "好，纸签改好了。你慢慢种。")
	elif pick == 2:
		G.flags["bakery_order_active"] = false
		G.flags["bakery_shop_stock"] = true
		await s.say("ren", "neutral", "行，这次我用店里的。试吃的主意还照咱们说好的办。")
	G.state_changed.emit()
	G.save_game()


func _market() -> void:
	var G := GameState
	var pick := await s.ui.choose(["把预留的菜交给莲", "这次用店里材料", "改到下一次周六", "先卖其他东西"])
	if pick == 0:
		var err := G.bakery_deliver()
		if err != "":
			G.toast.emit(err)
			return
		await s.say("ren", "happy", "这一篮我收到了。黄瓜切薄点，番茄先沥一下。都是街坊教的。")
	elif pick == 1:
		G.bakery_serve(false)
		await s.say("ren", "happy", "这次我先用店里的材料。试吃牌照咱们选的摆。")
	elif pick == 2:
		G.flags["bakery_due_day"] = G.next_market_day(true)
		G.state_changed.emit()
		G.save_game()
		return
	else:
		await s.farm._sell(G.MARKET_RATE, "集市摊位")
		return
	if int(G.flags.get("bakery_menu", 0)) == 0:
		await s.say("ren", "happy", "菠萝包摆前面，三明治在旁边。一小篮，说到做到。")
	else:
		await s.say("ren", "happy", "三明治的牌子摆前面了。菠萝包也给老客人留着。")
	G.save_game()

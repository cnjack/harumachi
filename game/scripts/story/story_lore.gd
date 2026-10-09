class_name StoryLore
extends RefCounted
## 第三章「停了十五年的夏祭」(Q10–Q15) and the 晴町旧物 keepsakes found around town.
## The story is in docs/game-design/LORE.md. An interaction goes through this module only when
## chapter 3 has something to do with it right now (pending); otherwise the usual handlers run.

var s: Story

const LANTERNS := 5
const WOOD := 6


func _init(story: Story) -> void:
	s = story
	GameState.day_changed.connect(_on_day)


func _say(who: String, mood: String, text: String) -> void:
	await s.say(who, mood, text)


func _q(qid: String) -> String:
	return GameState.qstate(qid)


# ------------------------------------------------------------------ what chapter 3 wants now
func pending(id: String) -> bool:
	var G := GameState
	match id:
		"room_closet", "zelkova", "farm_logs", "farm_hokora":
			return true
		"mio":
			return G.at_step("Q10", "show_mio") or G.at_step("Q11", "report_mio11") or _q("Q11") == "available" \
				or (G.at_step("Q12", "give_lanterns") and (G.count("chochin_hand") >= LANTERNS or SummerProjects.uses_cooperation_mainline() and WorkshopProject.state().phase == "retained")) \
				or G.at_step("Q14", "goldfish_mio") or reunion_pending() or photo_optional() \
				or _q("Q11") == "done" and G.day <= 17 and not G.flags.get("summer_invitation",{}).get("presented",false)
		"haru":
			return G.at_step("Q11", "show_haru") or _q("Q12") == "available" or _q("Q13") == "available" \
				or (G.at_step("Q12", "make_lanterns") and G.count("washi") >= LANTERNS and G.has("bamboo_strip", LANTERNS))
		"tanaka":
			return G.at_step("Q12", "get_bamboo") or G.at_step("Q13", "ask_tanaka") \
				or (G.at_step("Q13", "give_wood") and G.has("wood", WOOD)) or _q("Q15") == "available"
		"ren":
			return _q("Q11") == "done" and not Progress.found("col_bakery1972") and G.phase != "market"
		"aoi":
			# the day before the summer festival (and its day), once, when she has nothing else to ask
			return G.day >= 16 and G.day <= 17 and not Progress.found("col_teruteru") and _q("Q05") == "done" \
				and _q("Q08") != "available" and not G.at_step("Q08", "talk_aoi") and not G.at_step("Q08", "give_aoi")
		"center_door":
			return G.at_step("Q11", "find_notebook")
		"board":
			return _q("Q11") == "done" and not Progress.found("col_zelkova1968")
		"shop_zakka":
			return _q("Q11") == "done" and not Progress.found("col_poster")
		"shop_florist":
			return _q("Q11") == "done" and not Progress.found("col_bookmark")
		"library":
			return _q("Q10") == "done" and not Progress.found("col_oldmap")
		"farm_shed":
			return G.at_step("Q15", "take_tube")
		"farm_bench":
			return G.at_step("Q15", "watch_hanabi") and fireworks_missed()
	return false


func prompt(id: String) -> Variant:
	if not pending(id):
		return null
	var G := GameState
	match id:
		"room_closet":
			return "打开奶奶的箱子" if G.at_step("Q10", "open_box") else "看看壁橱"
		"zelkova":
			return "看看庭院的榉树"
		"farm_logs":
			return "搬木料" if G.at_step("Q13", "carry_wood") else "看看柴堆"
		"farm_hokora":
			return "拜一拜小祠堂"
		"center_door":
			return "去储物间找账本"
		"board":
			return "看看公告栏上的老照片"
		"shop_zakka":
			return "和阿健聊聊夜市"
		"shop_florist":
			return "和千代阿姨聊聊"
		"library":
			return "翻翻小书屋的旧书"
		"farm_shed":
			return "取下旧花火筒"
		"farm_bench":
			return "和田中聊聊错过的花火"
		"mio":
			return "和澪约一次树下的晚会" if reunion_pending() else "和澪说话"
		_:
			return "和%s说话" % s.npc_name(id) if s.npcs.has(id) else null


## Where the quest marker should point for chapter-3 steps (a point id, "npc:<id>" or "").
func marker(step: String) -> String:
	if step in ["go_fest", "bon_odori14"] and reunion_pending():
		return "npc:mio"
	match step:
		"open_box": return "room_closet"
		"show_mio", "report_mio11", "give_lanterns", "goldfish_mio": return "npc:mio"
		"find_notebook": return "workroom_archive" if s.main.in_room and s.main.room_kind == "workroom" else "center_door"
		"show_haru", "take_blueprint": return "npc:haru"
		"make_lanterns", "buy_washi", "get_bamboo":
			if SummerProjects.uses_cooperation_mainline():
				if not s.main.in_room or s.main.room_kind != "workroom": return "center_door"
				return "workroom_lantern_test" if int(WorkshopProject.state().joints) == 3 else "workroom_table"
			return "npc:haru" if step == "make_lanterns" else "shop_zakka" if step == "buy_washi" else "npc:tanaka"
		"give_wood", "ask_tanaka": return "npc:tanaka"
		"carry_wood": return "space_plan" if SummerProjects.uses_cooperation_mainline() else "farm_logs"
		"go_fest": return "build_sign"
		"bon_odori14": return "yagura"
		"take_tube": return "farm_shed"
		"watch_hanabi": return "farm_bench"
	return ""


func handle(id: String) -> void:
	match id:
		"room_closet": await _closet()
		"zelkova": await _zelkova()
		"farm_logs": await _logs()
		"farm_hokora": await _hokora()
		"mio": await _mio()
		"haru": await _haru()
		"tanaka": await _tanaka()
		"ren": await _ren()
		"aoi": await _aoi()
		"center_door": await _notebook()
		"board": await _board()
		"shop_zakka": await _zakka()
		"shop_florist": await _florist()
		"library": await _library()
		"farm_shed": await _tube()
		"farm_bench": await _revisit_hanabi()


func summer_missed() -> bool:
	var G := GameState
	return G.day > 17 or (G.day == 17 and G.hour() >= float(G.festival("natsumatsuri").end))


func fireworks_missed() -> bool:
	var G := GameState
	return G.day > 24 or (G.day == 24 and G.hour() >= float(G.festival("hanabi").end))


func reunion_pending() -> bool:
	var G := GameState
	return summer_missed() and (_q("Q14") == "available" or G.at_step("Q14", "go_fest") or G.at_step("Q14", "bon_odori14"))


# ------------------------------------------------------------------ chapter start, fallbacks, checks
func _on_day(d: int) -> void:
	var G := GameState
	_unlock_box()
	# nothing can be missed: whatever is left the day before the festival, the town finishes
	if d >= 16:
		for qid in ["Q12", "Q13"]:
			if qid == "Q13" and SummerProjects.uses_cooperation_mainline() and SummerSpace.state().phase != "invitation": continue
			if qid == "Q12" and SummerProjects.uses_cooperation_mainline() and WorkshopProject.state().phase != "invitation": continue
			if _q(qid) == "active" or _q(qid) == "available":
				G.flags["town_finished_" + qid] = true
				G.complete_quest(qid, false, false)
	if d >= 17 and _q("Q14") == "locked" and _q("Q05") == "done":
		G.quests["Q14"] = {"state": "available", "step": 0}


## Called after every interaction and once a second: steps that finish by themselves.
func checks() -> void:
	var G := GameState
	_unlock_box()
	# Loaded old saves and late first markets also get the invitation, without a day-change event.
	if G.day >= 17 and _q("Q14") == "locked" and _q("Q05") == "done":
		G.quests["Q14"] = {"state": "available", "step": 0}
	if not SummerProjects.uses_cooperation_mainline() and G.at_step("Q12", "buy_washi") and G.count("washi") >= LANTERNS:
		G.advance("Q12", "buy_washi")
		G.toast.emit("和纸买齐了。去河边农园找田中爷爷要竹篾")
	if _q("Q14") == "available" and G.festival_now() == "natsumatsuri":
		G.start_quest("Q14")
		s.ui.chapter_card("晴町夏祭", "十五年后，庭院里又立起了盆舞台。")
	var at_courtyard: bool = Rect2(-13.0, -5.5, 30.0, 29.5).has_point(Vector2(s.player.global_position.x, s.player.global_position.z))
	if G.at_step("Q14", "go_fest") and G.festival_now() == "natsumatsuri" and s.main.world.region == "town" and not s.main.in_room and at_courtyard:
		DailyLife.mark_major("festival:summer_attended")
		G.flags["summer_attended"] = true
		G.advance("Q14", "go_fest")
	if G.at_step("Q14", "bon_odori14") and G.flags.get("fest_bon_odori", false):
		G.advance("Q14", "bon_odori14")
		G.toast.emit("盆舞跳完了。去找澪吧")
	if G.at_step("Q15", "watch_hanabi") and G.flags.get("fest_hanabi", false) and not s.busy:
		_hanabi_end.call_deferred()

func _unlock_box() -> void:
	if _q("Q05") == "done" and _q("Q10") == "locked":
		GameState.quests["Q10"] = {"state":"available","step":0}
		s.ui.panels.card("奶奶留下的箱子", ["壁橱里还有东西没收拾。有空时自己打开看看。"], "quest")


# ------------------------------------------------------------------ Q10 奶奶的箱子
func _reunion() -> void:
	var G := GameState
	await _say("mio", "neutral", "夏祭那晚，有些事还没来得及一起做。今晚去树下看看？金鱼摊的水槽还在。")
	var choice := await s.ui.choose(["今晚一起去", "之后再约"])
	if choice != 0:
		await _say("mio", "happy", "好。这次慢慢来，什么时候想去了就找我。")
		return
	if _q("Q14") == "available":
		G.start_quest("Q14")
	G.flags["summer_reunion"] = true
	SummerGathering.state().reunion_day = G.day
	if G.hour() < 18.5:
		G.skip_to(18.5 * 60.0)
	if G.at_step("Q14", "go_fest"):
		G.advance("Q14", "go_fest")
	if G.at_step("Q14", "bon_odori14"):
		await _say("mio", "neutral", "盆舞下次再学。今天，先把金鱼和照片补上。")
		G.advance("Q14", "bon_odori14")
	await _goldfish_promise()


func _revisit_hanabi() -> void:
	var G := GameState
	await _say("tanaka", "neutral", "……那晚没赶上？坐吧。")
	await _say("narrator", "", "田中翻开记着花火顺序的小本子，最后一发旁边，画了一朵金色的花。")
	await _say("tanaka", "neutral", "……这发是给健一的。孩子们说，还想看。")
	await _say("tanaka", "neutral", "下次，一起在这里看。台子也一起检查，别全压在一个人身上。")
	G.flags["hanabi_revisit"] = true
	await future_direction("record")
	G.advance("Q15", "watch_hanabi")
	s.ui.chapter_card("第三章 · 完", "花火已经放过，田中的小本子上留出了下一次的空白。")


func _closet() -> void:
	var G := GameState
	if _q("Q10") == "available":
		await _say("narrator", "", "壁橱最里面的纸箱上，写着你的名字。现在想打开看看吗？")
		var choice: int = await s.ui.choose(["打开看看", "先收好，之后再看"])
		if choice != 0: return
		G.start_quest("Q10")
		s.ui.chapter_card("第三章 · 停了十五年的夏祭", "奶奶的箱子里，留着一张旧照片。")
	if not G.at_step("Q10", "open_box"):
		await _say("narrator", "", "壁橱里叠着奶奶的被褥，还有一股樟脑的味道。" if _q("Q10") != "done" else "奶奶的箱子收好了。照片和信都在图鉴里（K）。")
		return
	await _say("narrator", "", "壁橱最里面，有一只写着“空”的纸箱。")
	await _say("narrator", "", "箱子里是一叠旧照片、一件叠好的小浴衣，还有一封没有寄出的信。")
	Progress.find("col_photo2011")
	await _say("sora", "neutral", "这是十岁那年的夏祭。背面写着“空和澪”……会是公告栏边的澪吗？拿去问问她。")
	Progress.find("col_letter")
	await _say("narrator", "", "“空：晴町的夏祭停了好多年了。要是哪天你回来，替奶奶去庭院看看那棵榉树，看它是不是又长高了。你们小时候，总约在树底下碰头。——千鹤”")
	await _say("sora", "neutral", "……树底下碰头。拿去问问澪吧，她什么都记得。")
	G.advance("Q10", "open_box")


func _mio() -> void:
	var G := GameState
	if G.at_step("Q10", "show_mio"):
		await _say("mio", "neutral", "嗯？一张旧照片……2011 年的夏祭？")
		await _say("mio", "surprised", "这个提着金鱼的女孩……是我。那旁边这个男孩，难道是——")
		var c := await s.ui.choose(["是我。那年夏天我住在奶奶家。", "……你还记得吗？"])
		if c == 0:
			await _say("mio", "happy", "真的是你！难怪我总觉得在哪儿见过。")
		await _say("mio", "happy", "我想起来了。捞金鱼的时候你把网弄破了，还非说是金鱼太重。")
		await _fragment("promise")
		await _say("mio", "neutral", "我们约好了，明年夏祭还要一起来。可是那之后，晴町再也没有办过夏祭。")
		await _fragment("stopped")
		await _say("mio", "neutral", "健一爷爷走了以后，町内会散了。灯笼收进仓库，再没人拿出来。")
		if summer_missed():
			await _say("mio", "happy", "……今年大家先办了一次。咱们还可以另约一晚，把那时的约定补上。")
		else:
			await _say("mio", "happy", "……喂。我们把夏祭办回来吧？就在这个夏天。")
		G.add_warmth("mio", 2)
		G.advance("Q10", "show_mio")
	if _q("Q11") == "available":
		await _say("mio", "neutral", "当年的准备都写在健一爷爷的账本里。先去社区中心储物间找找？")
		G.start_quest("Q11")
		return
	if G.at_step("Q11", "report_mio11"):
		await _say("mio", "neutral", "灯笼、盆舞台、屋台、花火……清单还挺长。")
		if summer_missed():
			await _say("mio", "neutral", "今年的夏祭，大家先办了一次。你没赶上的话，咱们另约一晚。")
		else:
			await _say("mio", "happy", "不过还来得及。夏祭就定在 7 月 20 日，星期六！")
		await _say("mio", "neutral", "灯笼可以请春婆婆教。盆舞台……得有人会搭才行。")
		if not summer_missed(): _record_summer_invitation()
		G.advance("Q11", "report_mio11")
		s.ui.panels.card("晴町夏祭的账本", ["健一爷爷的账本找到了。", "去找春聊灯笼和盆舞台；错过夏祭也可以和澪另约一晚。"], "chochin")
		return
	if _q("Q11") == "done" and G.day <= 17 and not G.flags.get("summer_invitation",{}).get("presented",false):
		await _say("mio", "happy", "不过还来得及。夏祭就定在 7 月 20 日，星期六！")
		await _say("narrator", "", "纸签上约了傍晚五点，按 C 可以等到那时。没做完的先收着，其他街坊也在帮忙准备。")
		_record_summer_invitation()
		G.save_game()
		return
	if reunion_pending():
		await _reunion()
		return
	if G.at_step("Q12", "give_lanterns") and SummerProjects.uses_cooperation_mainline() and WorkshopProject.state().phase == "retained":
		await _say("mio", "happy", "这盏从路口看得见，走过去也不碰头吧？我记下来。到夏祭再看看挂哪儿。")
		await _say("mio", "neutral", "其他的灯笼交给大家。这一盏你先收好，到时带来。")
		G.advance("Q12", "give_lanterns")
		return
	if G.at_step("Q12", "give_lanterns") and G.count("chochin_hand") >= LANTERNS:
		G.remove_item("chochin_hand", LANTERNS)
		await _say("mio", "happy", "五盏！还是手糊的……夏祭那晚，就把它们挂在庭院最显眼的地方。")
		await _say("mio", "neutral", "账本写着二十盏，阿健说仓库里还有。等会儿我去数数。")
		G.advance("Q12", "give_lanterns")
		return
	if G.at_step("Q14", "goldfish_mio"):
		await _goldfish_promise()
		return
	if photo_optional():
		var option: int = await s.ui.choose(["和澪聊聊今天", "一起到水槽旁补拍合影"])
		if option == 1:
			if await _photo():
				G.flags.summer_shared["photo_choice"] = 0
				G.save_game()
		else:
			await s._i_mio()

func photo_optional() -> bool:
	return GameState.qstate("Q14") == "done" and not GameState.flags.get("summer_shared", {}).is_empty() and not Progress.found("col_photo_new")

func _record_summer_invitation() -> void:
	GameState.flags["summer_invitation"] = {"presented":true,"source":"mio","day":17,"minute":int(float(GameState.festival("natsumatsuri").start)*60),"seen_day":GameState.day}


# ------------------------------------------------------------------ Q11 町内会的旧账本
func _notebook() -> void:
	await _say("narrator", "", "储物间里堆着旧桌椅和一卷卷红白布。最底下的纸箱里，压着一本布面的笔记本。")
	Progress.find("col_notebook")
	await _say("narrator", "", "封面印着三个灯笼。翻开，是一行行工整的字：灯笼二十盏、盆舞台的木料、屋台的排班、花火的申请……")
	await _say("narrator", "", "最后一页停在 2011 年 7 月。后面全是空白。")
	GameState.advance("Q11", "find_notebook")


func _haru() -> void:
	var G := GameState
	if G.at_step("Q11", "show_haru"):
		await _say("haru", "neutral", "这个本子……是健一的字。")
		await _say("haru", "happy", "你看，“灯笼二十盏，春负责糊”。他总爱把活儿派给我。")
		await _say("haru", "neutral", "2011 年那次，他发着烧还爬到盆舞台上系灯笼。那是最后一次了。")
		await _say("haru", "happy", "要是能再看一次那座台子呀……拿去给澪吧，她会有办法的。")
		G.add_warmth("haru", 2)
		G.advance("Q11", "show_haru")
		return
	if _q("Q12") == "available" and SummerProjects.uses_cooperation_mainline():
		await _say("haru", "happy", "工作间留了一份和纸和竹篾。先做一盏样灯，亮起来看看，其他街坊一起糊。")
		G.start_quest("Q12")
		return
	if _q("Q12") == "available":
		await _say("haru", "happy", "糊灯笼呀？我年轻时糊过好多。")
		await _say("haru", "neutral", "你去杂货铺买五张和纸，再找田中要些竹篾，他削得最好。东西齐了就来找我。")
		G.start_quest("Q12")
	if _q("Q13") == "available":
		await _say("haru", "neutral", "对了，还有这个——健一画的盆舞台图纸。放在我工具间里十五年了。")
		Progress.find("col_blueprint")
		if SummerProjects.uses_cooperation_mainline():
			await _say("haru", "happy", "拿去给田中吧。台子归他和街坊搭，今年观看和供餐的位置由你安排。分工现在就能商量，晚上的往事再听。")
		else: await _say("haru", "happy", "拿去给田中吧。台子怎么搭，他比谁都清楚。……就是那人，得等到傍晚才肯说话。")
		G.start_quest("Q13")
		G.advance("Q13", "take_blueprint")
		return
	if G.at_step("Q12", "make_lanterns") and G.count("washi") >= LANTERNS and G.has("bamboo_strip", LANTERNS):
		await _say("haru", "happy", "都带来啦？来，坐这儿。先把竹篾弯成圈。")
		await s.ui.fade_out(0.6)
		GameState.skip_to(GameState.minute + 60.0)
		await _say("narrator", "", "春婆婆把竹篾一圈圈弯好，你把和纸一张张糊上去。等浆糊干了，五盏灯笼排在长椅上。")
		await s.ui.fade_in(0.6)
		G.remove_item("washi", LANTERNS)
		G.remove_item("bamboo_strip", LANTERNS)
		G.add_item("chochin_hand", LANTERNS)
		await _say("haru", "happy", "糊得不错呀，比健一第一次糊的好多了。拿去给澪吧。")
		G.add_warmth("haru", 1)
		G.advance("Q12", "make_lanterns")


# ------------------------------------------------------------------ Q12 / Q13 / Q15 with Tanaka
func _tanaka() -> void:
	var G := GameState
	if G.at_step("Q12", "get_bamboo"):
		await _say("tanaka", "neutral", "……糊灯笼？")
		await _say("tanaka", "neutral", "给。泡过水的，湿一湿，好弯。")
		G.add_item("bamboo_strip", LANTERNS)
		G.advance("Q12", "get_bamboo")
		return
	if G.at_step("Q13", "ask_tanaka"):
		if G.hour() < 17.0:
			await _say("tanaka", "neutral", "……健一的图纸？")
			await _say("tanaka", "neutral", "……晚上再说吧。")
			return
		await _say("tanaka", "neutral", "……这张图纸，我看着他画的。改了三回。")
		await _say("tanaka", "neutral", "那年最后一发花火，是我和他一起点的。点完他说：明年换你点，我在台子上看。")
		await _say("tanaka", "neutral", "……后来就没有明年了。")
		await _say("tanaka", "neutral", "木料在柴堆那边。挑六根干的搬过来。台子，我来搭。")
		G.add_warmth("tanaka", 2)
		G.advance("Q13", "ask_tanaka")
		return
	if G.at_step("Q13", "give_wood") and G.has("wood", WOOD):
		G.remove_item("wood", WOOD)
		await _say("tanaka", "neutral", "……够了。")
		await _say("tanaka", "happy", "夏祭前一天，台子会立在榉树旁边。尺寸照健一画的，一毫米都不差。")
		G.advance("Q13", "give_wood")
		return
	if _q("Q15") == "available":
		await _say("tanaka", "neutral", "……夏祭办成了。台子上，孩子们还爬上去看了。")
		await _say("tanaka", "neutral", "工具棚最高那层架子上，有个旧花火筒。……拿下来吧。")
		G.start_quest("Q15")


func _logs() -> void:
	var G := GameState
	if SummerProjects.uses_cooperation_mainline():
		var moved: int = int(SummerSpace.state().get("optional_wood", 0))
		if moved >= WOOD:
			await _say("narrator", "", "六根木料已搬齐。田中在搭台子，桌椅的位置还可以接着看。")
			return
		var labour: int = await s.ui.choose(["顺手搬两根木料过去", "先去摆桌椅"])
		if labour == 0:
			SummerSpace.state()["optional_wood"] = moved + mini(2, WOOD - moved)
			G.flags["space_helped_wood"] = true
			Audio.fx("soil")
			await _say("narrator", "", "两根木料放到施工堆里了。桌椅还没试，有空再过去。")
			G.save_game()
		return
	if not G.at_step("Q13", "carry_wood"):
		await _say("narrator", "", "柴堆码得齐齐整整。最上面那根，端头还留着斧头的印子。")
		return
	var have := G.count("wood")
	G.add_item("wood", mini(2, WOOD - have))
	Audio.fx("soil")
	if G.count("wood") >= WOOD:
		await _say("narrator", "", "六根干透的木料，扛在肩上沉甸甸的。拿去给田中爷爷吧。")
		G.advance("Q13", "carry_wood")
	else:
		await _say("narrator", "", "你挑了两根干透的木料。（%d / %d）" % [G.count("wood"), WOOD])


func _tube() -> void:
	await _say("narrator", "", "最高那层架子上落满了灰。旧花火筒就立在最里面，标签上的红金色花纹已经褪了。")
	Progress.find("col_fire_tube")
	var tanaka: NPC = s.npcs.get("tanaka")
	var present: bool = tanaka != null and not tanaka.home and tanaka.is_visible_in_tree() and tanaka.global_position.distance_to(s.player.global_position)<8
	if present:
		if fireworks_missed(): await _say("tanaka", "neutral", "……2011 年最后一发。今年放过了。到河边坐坐吧，我给你讲。")
		else: await _say("tanaka", "neutral", "……2011 年最后一发。7 月 27 日，花火大会。我再放一次。")
	else:
		await _say("narrator", "", "旁边是田中留下的活动纸签：7月27日，晚上七点半，晴川河边。" + ("那晚已经过去了，可以去问问他留下的记录。" if fireworks_missed() else "到那时再和大家一起去，眼下先把这只筒收好。"))
	GameState.advance("Q15", "take_tube")


func _hanabi_end() -> void:
	var G := GameState
	if not G.at_step("Q15", "watch_hanabi"):
		return
	s.busy = true
	s.ui.dialogue_begin()
	await _say("narrator", "", "你想起那晚，最后一发花火在晴川上方开成金色的花。" if fireworks_missed() else "最后一发花火升上夜空，在晴川上方开成一朵很大的金色的花。")
	await _say("tanaka", "neutral", "……健一。你看见了吗？")
	await _say("haru", "happy", "看见了呀。他一定在台子上看着呢。")
	await future_direction("hanabi")
	s.ui.dialogue_end()
	s.busy = false
	G.advance("Q15", "watch_hanabi")
	s.ui.chapter_card("第三章 · 完", "田中爷爷把空了的花火筒擦干净，放回了架子最高那层。")

func future_direction(origin: String) -> void:
	await _say("narrator", "", "回家时，要不要在书桌上留张便笺？写写下一步想做什么。")
	var choice: int = await s.ui.choose(MainlineProgress.DIRECTION_OPTIONS)
	if MainlineProgress.choose_direction(choice,origin):
		await _say("narrator", "", "想不出来也可以先空着。便笺就放在家里的书桌上。")


# ------------------------------------------------------------------ Q14 the promise at the goldfish stall
func _goldfish_promise() -> void:
	var G := GameState
	var had_photo := Progress.found("col_photo2011")
	var shared: Dictionary = G.flags.get("summer_shared", {})
	if shared.is_empty():
		await _say("mio", "happy", "金鱼摊的水槽还在。一起待一会儿？想试试纸网，或坐旁边看看都行。")
		var activity: int = await s.ui.choose(["一起试试纸网", "坐在水槽边，陪澪看一会儿", "只在这里拍张合影", "今天先回去，之后再约"])
		if activity == 3: return
		if not await _stand_by_pool(): return
		if activity == 0:
			await _say("mio", "neutral", "慢一点。按住纸网沉进水里，松手就捞起；泡久了会破，按 Esc 随时回来。")
			StoryKnowledge.observe_activity("goldfish")
			var result: Dictionary = await s.play_mg("goldfish", {"mode": "shared_goldfish", "start_requested": true, "result_title": "和澪在水槽边", "return_label": "回到澪身边"})
			var outcome: Dictionary = result.get("outcome", {})
			if not outcome.get("started", false): return
			shared = {"participation": "played", "caught": int(outcome.get("caught", 0)), "day": G.day}
			if int(shared.caught) > 0:
				await _say("mio", "happy", "捞到了！先放回水槽吧，还能在这里看着它游。")
			else:
				await _say("mio", "happy", "没捞上来也没关系。刚才那尾，游得可真快。")
		elif activity == 1:
			await _say("narrator", "", "你和澪在水槽边停下。她扶住池沿，指给你看躲在纸网下面的小金鱼。")
			await _say("mio", "neutral", "小时候只顾着捞。现在这样看一会儿，也挺好。")
			shared = {"participation": "watched", "caught": 0, "day": G.day}
		else:
			shared = {"participation": "photo_only", "caught": 0, "day": G.day}
		G.flags["summer_shared"] = shared
		G.save_game()
	if not shared.has("photo_choice"):
		var photo_choice: int = await s.ui.choose(["在水槽旁拍张合影", "这次先不拍，记住今天就好", "下次再来拍"])
		if photo_choice == 0 and not await _photo(): photo_choice = 2
		shared["photo_choice"] = photo_choice
		G.save_game()
	await _say("mio", "neutral", "……十五年了。" if had_photo else "……晴町的夏祭，真的回来了。")
	await _say("mio", "happy", "这次，我们都没有忘记。" if had_photo else "谢谢你。")
	var c := await s.ui.choose(["明年夏祭，还一起来吧。", "如果我那时回来了，就在树下见。", "今年能一起待一会儿，已经很好了。"])
	G.flags["summer_promise"] = c
	if c == 0:
		await _say("mio", "happy", "好。下次也慢慢来。")
	elif c == 1:
		await _say("mio", "happy", "那我给你留一张网。到时候，树下见。")
	else:
		await _say("mio", "happy", "嗯。能一起待在这里，就很好。")
	G.add_warmth("mio", 3)
	G.advance("Q14", "goldfish_mio")

func _stand_by_pool() -> bool:
	if s.main.in_room:
		if s.main.room_kind == "house": await s.main.exit_room()
		else: await s.main.exit_interior()
	if s.main.world.region == "farm": await s.main.leave_farm()
	var pool: Variant = s.physical_point("goldfish_pool")
	if pool == null or not s.npcs.has("mio"): return false
	var at: Vector3 = pool
	await s.ui.fade_out(0.2)
	s.player.global_position = Vector3(at.x - .55, .05, at.z + 1.6)
	s.player.velocity = Vector3.ZERO
	s.player.face_towards(at)
	var mio: NPC = s.npcs.mio
	mio.place(Vector3(at.x + .55, 0, at.z + 1.6), 0)
	mio.visible = true
	mio.home = false
	mio.face(at)
	s.main.rig.snap()
	await s.ui.fade_in(0.2)
	return true


## The new group photo: frame the player and Mio at the goldfish pool and save the picture.
func _photo() -> bool:
	var m = s.main
	if not await _stand_by_pool(): return false
	var pool: Variant = s.physical_point("goldfish_pool")
	if pool == null:
		GameState.toast.emit("水槽的位置没有找到，之后再拍。")
		return false
	var at: Vector3 = pool
	s.ui.dialogue_end()
	await s.ui.fade_out(0.4)
	var mio: NPC = s.npcs["mio"]
	var base := Vector3(at.x, 0.05, at.z) + Vector3(0, 0, 1.4)
	m.player.global_position = base + Vector3(-0.45, 0, 0)
	mio.place(base + Vector3(0.45, -0.05, 0), 180.0)
	m.player.set_facing(PI)
	var rig = m.rig
	var keep := [rig.yaw, rig.pitch, rig.dist]
	rig.yaw = 180.0
	rig.pitch = 8.0
	rig.dist = 3.4
	rig.snap()
	s.ui.set_hud_visible(false)
	# a clean picture: no quest pin, no name tags
	var pin_was: bool = m.marker.visible
	m.marker.visible = false
	m.photo_mode = true
	var tags: Array = []
	for n in s.npcs.values():
		for l in (n as Node).find_children("*", "Label3D", true, false):
			if (l as Label3D).visible:
				tags.append(l)
				(l as Label3D).visible = false
	await s.ui.fade_in(0.4)
	await m.get_tree().create_timer(0.05 if s.ui.instant else 0.6).timeout
	Audio.fx("shutter")
	var img: Image
	if DisplayServer.get_name() == "headless":
		# nothing is drawn without a display: keep the festival keyframe as the picture
		img = (load("res://assets/ui/collection/col_photo_new.jpg") as Texture2D).get_image()
	else:
		await RenderingServer.frame_post_draw
		img = m.get_viewport().get_texture().get_image()
	img.resize(960, int(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
	var photo_error := img.save_png(GameState.photo_path())
	s.ui.flash()
	await m.get_tree().create_timer(0.05 if s.ui.instant else 0.8).timeout
	s.ui.set_hud_visible(true)
	m.photo_mode = false
	m.marker.visible = pin_was
	for l in tags:
		(l as Label3D).visible = true
	rig.yaw = keep[0]
	rig.pitch = keep[1]
	rig.dist = keep[2]
	rig.snap()
	if photo_error == OK:
		GameState.flags["photo_taken_day"] = GameState.day
		GameState.flags["photo_rendered"] = DisplayServer.get_name() != "headless"
		Progress.find("col_photo_new")
	else:
		GameState.toast.emit("照片没能保存，稍后可以再拍，不用重新捞鱼。")
	s.ui.dialogue_begin()
	return photo_error == OK


# ------------------------------------------------------------------ keepsakes around town
func _zelkova() -> void:
	await _fragment("tree")
	var e := Dialogue.pick("place:zelkova")
	if not e.is_empty():
		Dialogue.mark(e)
		for ln in e.lines:
			await _say(ln[0] if ln[0] != "place:zelkova" else "narrator", ln[1], ln[2])
		return
	if Progress.found("col_letter"):
		await _say("narrator", "", "榉树的叶子沙沙响。小时候，大家总约在这棵树底下碰头。")
	else:
		await _say("narrator", "", "庭院中央的老榉树，树干要两个人才抱得过来。树荫底下总是凉快的。")

func _fragment(id: String) -> void:
	if StoryKnowledge.presented(id): return
	var fragment: Dictionary = StoryKnowledge.fragment(id)
	if fragment.is_empty(): return
	await s.say(str(fragment.who), "neutral", str(fragment.text))
	StoryKnowledge.remember(id)
	GameState.save_game()


func _hokora() -> void:
	if Progress.found("col_ema"):
		await _say("narrator", "", "小祠堂前摆着新的野花。有人来拜过了。")
		return
	await _say("narrator", "", "河对岸的小祠堂里挂着几块褪色的绘马。其中一块画着一个笑眯眯的太阳。")
	Progress.find("col_ema")
	await _say("narrator", "", "传说晴川发大水那年，村民修了这座小祠。从那以后，晴町办祭典的日子，雨总会停。")


func _ren() -> void:
	await _say("ren", "happy", "你在收集晴町的老东西？等等，我这儿有一张——")
	Progress.find("col_bakery1972")
	await _say("ren", "neutral", "1972 年，爷爷奶奶开店那天。菠萝包的配方，从那天起就没改过。")
	await _say("ren", "happy", "……我偷偷改过一次，被奶奶骂了一顿。所以现在还是这个味道！")


func _aoi() -> void:
	await _say("aoi", "happy", "给你！我做的晴天娃娃。")
	Progress.find("col_teruteru")
	await _say("aoi", "neutral", "奶奶说，夏祭前一天挂在榉树上，第二天一定是晴天。你帮我挂高一点好不好？")


func _board() -> void:
	await _say("narrator", "", "公告栏的角落里，澪贴上了一张黑白照片：一群人正把一棵小树苗种进刚铺好的庭院。")
	Progress.find("col_zelkova1968")
	await _say("narrator", "", "照片下写着：“晴町共同庭院落成纪念 · 1968”。那棵小树苗，就是现在的榉树。")


func _zakka() -> void:
	await _say("narrator", "", "阿健从仓库里翻出一卷海报：“夜市？你等等——”")
	Progress.find("col_poster")
	await _say("narrator", "", "昭和年代的土曜夜市海报，红白灯笼下摆满了蔬菜和面包。阿健说，他小时候每个星期六都盼着它贴出来。")
	await s.farm.handle("shop_zakka")


func _florist() -> void:
	await _say("narrator", "", "千代阿姨从柜台下拿出一枚押花书签：“春年轻时送我的。那时候我们俩还争过，谁的紫阳花更蓝。”")
	Progress.find("col_bookmark")
	await s.farm.handle("shop_florist")


func _library() -> void:
	await _say("narrator", "", "小书屋最下面一层，夹着一张折起来的旧地图。")
	Progress.find("col_oldmap")
	await _say("narrator", "", "手绘的晴川、木桥和商店街。街上画满了小小的铺面，比现在多了一倍。")

class_name StoryFest
extends RefCounted
## The summer's festivals (data/festivals.json): what each one lets the player do, and the
## one-time rewards. Decorations live in WorldBuilder / FarmBuilder (sync_festivals), NPC places in
## the festival's "npc" table (applied by main.update_npcs).

var s: Story

const WISHES := [
	["希望晴町的集市一直办下去", "mio"], ["希望莲的面包店生意兴隆", "ren"],
	["希望春婆婆身体健康", "haru"], ["希望明年夏天还能和小葵一起玩", "aoi"],
]


func _init(story: Story) -> void:
	s = story


func _say(who: String, mood: String, text: String) -> void:
	await s.say(who, mood, text)


func done(key: String) -> bool:
	return GameState.flags.get("fest_" + key, false)


func mark(key: String) -> void:
	GameState.flags["fest_" + key] = true
	DailyLife.mark_major("festival:" + key)
	GameState.state_changed.emit()


## Prompt for a festival point, or "" when that festival is not running now.
func prompt(id: String) -> Variant:
	var G := GameState
	var now := G.festival_now()
	match id:
		"tanabata_bamboo":
			return ("写下愿望，挂上短册" if not done("tanabata_wish") else "看看大家的短册") if now == "tanabata" else ""
		"contest_table":
			return ("参加品评会（交一份作物）" if not done("contest_entry") else "看看品评会的桌子") if now == "contest" else ""
		"yagura":
			if now != "natsumatsuri":
				return ""
			return "加入盆舞" if G.hour() >= 20.0 and not done("bon_odori") else "看看盆舞台"
		"yatai":
			return "逛夏祭的摊位" if now == "natsumatsuri" else ""
		"bridge_toro":
			return ("放一盏灯笼" if not done("toro") else "看灯笼顺着河漂走") if now == "obon" else ""
		"offer_stand":
			return ("供上月见团子" if not done("tsukimi") else "看看供台") if now == "tsukimi" else ""
		"farm_bench":
			return "和大家一起看烟花" if now == "hanabi" and not done("hanabi") else null
	return null


func handles(id: String) -> bool:
	var p = prompt(id)
	return p != null and str(p) != ""


func handle(id: String) -> void:
	match id:
		"tanabata_bamboo":
			await _tanabata()
		"contest_table":
			await _contest()
		"yagura":
			await _bon_odori()
		"yatai":
			s.ui.dialogue_end()
			await s.ui.panels.open_store("yatai")
			s.ui.dialogue_begin()
		"bridge_toro":
			await _toro()
		"offer_stand":
			await _tsukimi()
		"farm_bench":
			await _hanabi()


func _tanabata() -> void:
	var G := GameState
	if done("tanabata_wish"):
		await _say("narrator", "", "竹枝上挂满了短册，红的黄的都有。你那张挂在最低的枝上，被风吹得直打转。")
		return
	await _say("narrator", "", "竹子旁的小桌上放着彩色的短册和笔。写点什么呢？")
	var c := await s.ui.choose(WISHES.map(func(w): return w[0]))
	var w: Array = WISHES[c]
	G.flags["tanabata_wish"] = c
	mark("tanabata_wish")
	s.world.hang_tanzaku(c)
	Audio.fx("paper")
	G.add_warmth(str(w[1]), 2)
	await _say("narrator", "", "你把短册系在竹枝上：“%s”。" % w[0])
	await _say(str(w[1]), "happy", {"mio": "诶……写的是这个？被你看穿了呢。谢谢。", "ren": "哈哈，那我可得更努力了！",
		"haru": "哎呀，这孩子……我会好好活到一百岁的。", "aoi": "拉钩！明年也要一起过七夕！"}.get(w[1], "谢谢。"))


func contest_score(iid: String) -> int:
	var G := GameState
	return int(round(float(G.item(iid).get("sell", 0)) * (1.0 + 0.08 * G.level())))


func _contest() -> void:
	var G := GameState
	var f := G.festival("contest")
	if done("contest_entry"):
		await _say("narrator", "", "长桌上摆着田中爷爷的特大萝卜、春的向日葵，还有你交的作物。")
		return
	var crops: Array = G.produce_owned().filter(func(iid): return G.unreserved_count(iid) > 0)
	if crops.is_empty():
		if not G.produce_owned().is_empty():
			await _say("narrator", "", "这些菜已经预留给莲。先留着这一篮，或者去试吃纸签改约，再挑别的菜参评。")
			return
		await _say("mio", "neutral", "品评会只收作物哦。去农园摘一份你最得意的来吧，下午三点前都可以！")
		return
	crops.sort_custom(func(a, b): return contest_score(a) > contest_score(b))
	await _say("mio", "happy", "欢迎参加晴町蔬菜品评会！交一份作物，评分看作物本身和种植的功夫。")
	var opts: Array = crops.map(func(i): return "交出%s（评分约 %d）" % [G.item_name(i), contest_score(i)])
	var c: int = await s.ui.choose_paged(opts, "再想想")
	if c < 0:
		return
	var iid: String = crops[c]
	var score := contest_score(iid)
	G.remove_item(iid, 1)
	mark("contest_entry")
	var board: Array = [["你", G.item_name(iid), score]]
	for r in f.rivals:
		board.append([G.npc_display(str(r[0])), str(r[1]), int(r[2])])
	board.sort_custom(func(a, b): return int(a[2]) > int(b[2]))
	var place := 0
	for i in board.size():
		if board[i][0] == "你":
			place = i
	var lines := []
	for i in board.size():
		lines.append("%s　%s 的%s　%d 分" % [["金奖", "银奖", "铜奖", "入选"][mini(i, 3)], board[i][0], board[i][1], int(board[i][2])])
	await s.ui.show_notice("晴町蔬菜品评会 · 结果", lines, "—— 评审：澪、町内会")
	var prize := int(f.prizes[mini(place, 3)])
	G.earn(prize, "品评会")
	Audio.sting("fanfare" if place == 0 else "coin")
	s.world.show_contest_entry(iid)
	if place == 0:
		G.add_item("ribbon_gold", 1)
		G.add_warmth("tanaka", 2)
		await _say("tanaka", "happy", "……输给你了。这%s，确实种得好。" % G.item_name(iid))
		await _say("mio", "happy", "金奖！奖金 %d 生活币，还有这条绶带！" % prize)
	else:
		await _say("mio", "happy", "第 %d 名！奖金 %d 生活币。明年再来挑战田中爷爷吧！" % [place + 1, prize])
		await _say("haru", "neutral", "品评会看的是个头和分量。向日葵、南瓜那种大个子最占便宜。")


func _bon_odori() -> void:
	var G := GameState
	if G.hour() < 20.0:
		await _say("mio", "happy", "盆舞八点开始！先去摊位逛逛吧，捞金鱼和太鼓也可以玩。")
		var choice: int = await s.ui.choose(["在舞台边歇到八点，再参加盆舞", "我再去逛逛，之后回来"])
		if choice==1: return
		await s.ui.fade_out(.3)
		G.skip_to(20*60)
		s.main.update_npcs(true)
		await s.ui.fade_in(.3)
	if done("bon_odori"):
		await _say("narrator", "", "太鼓咚咚地响，大家绕着盆舞台一圈一圈地跳。")
		return
	await _say("mio", "happy", "来来来，一起跳！跟着我：拍手、转身、往前走两步——")
	s.ui.dialogue_end()
	await s.main.bon_odori_scene()
	s.ui.dialogue_begin()
	mark("bon_odori")
	for who in ["mio", "ren", "haru", "tanaka", "aoi"]:
		G.add_warmth(who, 1)
	await _say("aoi", "happy", "跳得好开心！明年也要一起跳！")


func _toro() -> void:
	var G := GameState
	if done("toro"):
		await _say("narrator", "", "一盏盏灯笼顺着晴川慢慢漂远，水面上一片暖黄。")
		return
	if not G.has("toro"):
		await _say("haru", "neutral", "没有灯笼吗？给，这盏是我多糊的。")
		G.add_item("toro", 1)
	await _say("narrator", "", "你蹲在木桥上，把点亮的纸灯笼放到水面上。它晃了两下，顺着水漂走了。")
	G.remove_item("toro", 1)
	s.world.farm.float_lantern(true)
	mark("toro")
	G.add_warmth("haru", 2)
	G.add_warmth("tanaka", 2)
	await _say("haru", "neutral", "……老头子，今年也有人陪我放灯笼了。")
	await _say("tanaka", "neutral", "嗯。他一定看得见。")


func _tsukimi() -> void:
	var G := GameState
	if not G.has("dango"):
		await _say("haru", "neutral", "供台上还空着呢。月见团子在家里的厨房就能做：两份米、一份砂糖。")
		return
	G.remove_item("dango", 1)
	mark("tsukimi")
	s.world.show_offering(true)
	for who in ["mio", "haru", "ren"]:
		G.add_warmth(who, 1)
	await _say("narrator", "", "你把团子摆上供台。满月从屋顶后面升起来，把庭院照得一片银白。")
	await _say("haru", "happy", "今年的月亮，好像特别圆呢。")


func _hanabi() -> void:
	var G := GameState
	var here := []
	for who in ["mio", "ren", "haru", "aoi", "tanaka"]:
		var n: NPC = s.npcs[who]
		if not n.home and n.global_position.distance_to(s.player.global_position) < 30.0:
			here.append(who)
	if here.is_empty():
		here = ["mio"]
	await _say("narrator", "", "河边已经坐满了人。第一发烟花“咻”地升上夜空……")
	var c := await s.ui.choose(here.map(func(w): return "坐到%s旁边" % G.npc_display(w)))
	var who: String = here[c]
	s.ui.dialogue_end()
	await s.main.hanabi_scene(who)
	s.ui.dialogue_begin()
	mark("hanabi")
	G.add_warmth(who, 3)
	match who:
		"mio": await _say("mio", "happy", "……十五年了。刚才那声一响，我吓了一跳。")
		"ren": await _say("ren", "happy", "快看，金色的！……啊，光顾着说，后面那发没看清。")
		"haru": await _say("haru", "happy", "年轻的时候，老头子就坐在你这个位置。")
		"aoi": await _say("aoi", "happy", "哇——！！那个是心形的！你看到了吗！")
		"tanaka": await _say("tanaka", "happy", "……健一，该让你看看。")

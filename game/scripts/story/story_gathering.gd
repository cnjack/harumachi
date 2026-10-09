class_name StoryGathering
extends RefCounted
var s: Story
var view: GatheringView
func _init(story: Story) -> void: s = story

func build() -> void:
	view = GatheringView.new()
	s.main.add_child(view)
	view.setup(s)

func handles(id: String) -> bool:
	return id == "gathering_paper" or id == "mio" and GameState.day > 17 and GameState.qstate("Q14") == "done" and GameState.phase != "market" and not GameState.at_step("Q09", "report9") and not s.lore.pending("mio")

func prompt(id: String) -> Variant:
	if not handles(id): return null
	return "看晚会纸签 · 菜单再用与散场" if id == "gathering_paper" else "和澪聊聊，也可以另约树下一晚"

func _present(who: String) -> bool:
	var actor: NPC = s.npcs.get(who)
	return actor != null and not actor.home and actor.is_visible_in_tree() and actor.global_position.x < 40

func handle(id: String) -> void:
	if id == "mio":
		var choice: int = await s.ui.choose(["另约一晚，在树下坐坐", "聊其他事", "改天再约"])
		if choice == 1:
			if s.space.handles(id): await s.space.handle(id)
			elif s.lore.pending(id): await s.lore.handle(id)
			else: await s._i_mio()
			return
		if choice == 2: return
		var why: String = SummerGathering.agree_reunion(_present("mio") and s.npcs.mio.global_position.distance_to(s.player.global_position) < 8)
		await s.say("narrator", "", why if why != "" else "今晚在树下碰头。带点吃的或那盏灯来，也可以空着手来坐坐。")
		return
	await _paper()

func _paper() -> void:
	var entry: Dictionary = SummerGathering.current()
	if not entry.is_empty() and int(entry.day) != GameState.day:
		await s.say("narrator", "", "这是第%d天留下的一篮，已经凉了。剩的可以包好带走，今晚再备新的。" % int(entry.day))
		var old_pick: int = await s.ui.choose(["收好上回剩的饭菜", "只挂那盏灯", "先去逛逛"])
		if old_pick == 0: await _cleanup(SummerGathering.context())
		elif old_pick == 1: await s.workshop.site()
		return
	if SummerGathering.context() == "":
		var old: Array[String] = []
		for id: String in SummerGathering.state().sessions:
			if not SummerGathering.state().sessions[id].closed: old.append(id)
		if old.is_empty():
			await s.say("narrator", "", "上次的菜单还在。等夏祭，或先和澪约一晚，再找莲备一篮。灯可从现场收回工作间。")
			return
		var pick: int = await s.ui.choose(old.map(func(id: String): return "收好" + ("夏祭" if id == "festival" else "树下晚会") + "剩的饭菜") + ["之后再收"])
		if pick < old.size(): await _cleanup(old[pick])
		return
	await s.say("narrator", "", "今晚这篮重新烤，一篮三份。找莲说说，先分给谁？")
	var choice: int = await s.ui.choose(["给今晚备一篮" if entry.is_empty() else "请街坊来桌边拿一份", "带那盏灯来挂上", "看看吃饭和跳舞会不会挤", "散场，包好剩的饭菜", "先去逛逛","商量这三份留给谁"])
	match choice:
		0:
			if entry.is_empty(): await _prepare()
			else: await _take_choice()
		1: await s.workshop.site()
		2:
			if SummerSpace.ready(): await s.space.trial(true)
			else: await s.say("narrator", "", "先请街坊走走，看看桌椅摆得合不合适。篮里的饭菜留着。")
		3: await _cleanup(SummerGathering.context())
		5: await s.food_use.arrange()

func _prepare() -> void:
	var prior: Dictionary = SummerProjects.opening().final
	if prior.is_empty(): await s.say("narrator", "", "还没和莲定好菜单。去面包店看看纸签，也可以今晚先坐坐。") ; return
	await s.say("narrator", "", "上回是%s、%s。今晚照旧，还是换个装法？" % [SummerProjects.MENU_NAMES[prior.menu], "纸包" if prior.presentation == "paper" else "盘子"])
	var portion: int = await s.ui.choose(["一份切成三小份", "做三整份，食材用三倍", "先不备餐"])
	if portion == 2: return
	var style: int = await s.ui.choose(["纸包，拿了就能走", "盘子，得找张近处的桌子", "先看看桌子摆在哪"])
	if style == 2: return
	var source: int = await s.ui.choose(["我出食材，请莲来烤", "请莲用店里留的食材", "之后再准备"])
	if source == 2: return
	var surface: Vector3 = view.surface()
	if not surface.is_finite(): await s.say("narrator", "", "这里还没有桌子可放这一篮。先摆好，再回来选。") ; return
	if style == 1 and not SummerGathering.plate_ready():
		await s.say("narrator", "", "桌子离歇脚的地方超过5米，端盘子太远。把桌子挪近些，或改用纸包。")
		return
	var why: String = SummerGathering.prepare("bite" if portion == 0 else "whole", "paper" if style == 0 else "plate", "own" if source == 0 else "shop", _present("ren"))
	await s.say("narrator", "", why if why != "" else "新烤的一篮放在桌上了，请街坊过来拿吧。")

func _take_choice() -> void:
	var entry: Dictionary = SummerGathering.current()
	var people: Array[String] = []
	for who: String in ["mio", "haru", "ren"]:
		if not _present(who) or entry.served.has(who) or int(entry.remaining) <= 0: continue
		var actor: NPC = s.npcs[who]
		if SummerGathering.context() == "festival" and Vector2(actor.global_position.x,actor.global_position.z).distance_to(SummerSpace.DANCE_CENTER) < SummerSpace.DANCE_RADIUS + .38: continue
		people.append(who)
	if people.is_empty(): await s.say("narrator", "", "这一篮已分好，或现在没有尚未领取的在场者。剩下的可以收好。") ; return
	var choice: int = await s.ui.choose(people.map(func(who: String): return "请" + GameState.npc_display(who) + "到桌边领一份") + ["先留在桌上"])
	if choice < people.size(): await take(people[choice])

func take(who: String) -> void:
	var actor: NPC = s.npcs.get(who)
	if not _present(who) or not view.surface().is_finite(): await s.say("narrator", "", "人或桌面现在不在这里，食物先留着。") ; return
	var target: Vector3 = view.stop()
	var stamp: String = SummerSpace.revision()
	var circles: Array = [[SummerSpace.DANCE_CENTER, SummerSpace.DANCE_RADIUS]] if SummerGathering.context() == "festival" else []
	var route: Dictionary = ProjectRoute.query(s.world, actor.global_position, target, [], stamp, circles)
	if not route.ok: await s.say("narrator", "", str(route.reason)); return
	var old_speed: float = actor.speed
	actor.speed = 1.8
	actor.set_talking(true)
	s.space.view.begin_walk(actor)
	s.ui.dlg.hide()
	var arrived := true
	if s.ui.instant:
		actor.place(target, 0)
		s.space.view.trace.clear()
		for point: Vector3 in route.path: s.space.view.trace.append(point)
	else: arrived = await actor.walk_safe(route.path)
	s.ui.dialogue_begin()
	var result := {"present":_present(who), "arrived":arrived and not s.space.view.aborted, "revision":stamp,
		"position":{"x":actor.global_position.x,"y":actor.global_position.y,"z":actor.global_position.z}, "crossed_dance":SummerSpace.crosses_dance(s.space.view.trace), "path":[]}
	for point: Vector3 in s.space.view.trace: result.path.append({"x":point.x,"y":point.y,"z":point.z})
	s.space.view.end_walk()
	actor.speed = old_speed
	actor.set_talking(false)
	var why: String = SummerGathering.take(who, result, target)
	if OS.get_cmdline_user_args().has("--route-debug"):
		print("GATHERING_ROUTE_DEBUG ",JSON.stringify({"who":who,"reason":why,"result":result,"target":str(target),"motion":actor.get_meta("motion_reason",""),"player":str(s.player.global_position)}))
	if why != "": await s.say("narrator", "", why); return
	await view.show_table()
	await s.say("narrator", "", GameState.npc_display(who) + "把这一份带走了。" + ("桌上剩下的先留着。" if int(SummerGathering.current().get("remaining",0))>0 else "这一篮分完了。"))
	var unit: Dictionary=FoodPurpose.owned(SummerGathering.current(),who)
	if who=="haru" and not unit.is_empty() and unit.purpose=="tea": await s.food_use.tea_use(SummerGathering.current())

func _cleanup(id: String) -> void:
	var entry: Dictionary = SummerGathering.state().sessions.get(id, {})
	var lamp: Dictionary = WorkshopProject.state().installed
	var with_lamp: bool = not entry.is_empty() and not lamp.is_empty() and str(lamp.get("session_id", "")) == str(entry.session_id)
	var why: String = SummerGathering.cleanup(id)
	await s.say("narrator", "", why if why != "" else ("没分完的饭菜包好，带回家慢慢吃。" if int(entry.get("packed",0))>0 else "桌边收拾好了。") + ("灯也带回工作间，改天还能再挂。" if with_lamp else ""))

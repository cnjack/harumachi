class_name StorySpace
extends RefCounted
var s: Story
var view: SpaceView

func _init(story: Story) -> void: s = story

func build() -> void:
	view = SpaceView.new()
	s.main.add_child(view)
	view.setup(s)

func handles(id: String) -> bool:
	if id == "space_plan": return GameState.qstate("Q11") == "done" or SummerSpace.state().phase != "invitation"
	if not SummerProjects.uses_cooperation_mainline() and SummerSpace.state().phase == "invitation": return false
	if id == "tanaka": return GameState.at_step("Q13", "ask_tanaka") or GameState.at_step("Q13", "give_wood") or SummerSpace.state().phase != "invitation"
	return id in ["mio", "haru", "ren"] and SummerSpace.state().phase in ["arranging", "retained"]

func prompt(id: String) -> Variant:
	if not handles(id): return null
	if id == "space_plan": return "看场地纸签 · 观看、供餐与盆舞"
	return "和%s商量场地，也可以聊别的" % GameState.npc_display(id)

func _present(who: String) -> bool:
	var actor: NPC = s.npcs.get(who)
	return actor != null and not actor.home and actor.visible and actor.global_position.distance_to(s.player.global_position) < 8.0

func handle(id: String) -> void:
	if id == "space_plan": await _plan(); return
	if id == "tanaka": await _tanaka(); return
	var choice: int = await s.ui.choose(["请帮我试一下观看、入场或供餐", "聊别的事", "之后再约"])
	if choice == 1: await _other(id); return
	if choice == 2: return
	var why: String = SummerSpace.invite(id, _present(id))
	if why != "": await s.say("narrator", "", why); return
	match id:
		"haru": await s.say("haru", "neutral", "想歇一歇，也想看清楚怎么跳。长椅别只顾着塞进空处呀，我来看看。")
		"ren": await s.say("ren", "neutral", "纸包好拿，盘子得有地方放。你留好取放的停点，我去走一趟，别从跳舞的人中间穿。")
		"mio": await s.say("mio", "happy", "我试着从入口带人进来。先把示范点留出来，看舞和拿吃的就能分开。")

func _other(who: String) -> void:
	if s.lore.pending(who): await s.lore.handle(who)
	else: await s.call("_i_" + who)

func _tanaka() -> void:
	if GameState.at_step("Q13", "ask_tanaka") and SummerSpace.state().phase == "invitation":
		await s.say("tanaka", "neutral", "……图纸给我。台子我们来搭，你看看桌椅放哪儿，留好进出的路。")
		await s.say("tanaka", "neutral", "现在能聊怎么摆。健一的事，等我傍晚收工再说。")
		var mode: int = await s.ui.choose(["我来摆，再请大家走走", "先看看两种摆法", "之后再来"])
		if mode == 2: return
		var source: int = await s.ui.choose(["借一组夏祭桌椅", "用已有的桌椅", "先不领"])
		if source == 2: return
		var why: String = SummerSpace.start("manual" if mode == 0 else "light", "loan" if source == 0 else "own")
		await s.say("narrator", "", why if why != "" else "纸签放在庭院南侧。舞台和屋台的位置先空出来，再放长椅和桌子。")
		return
	if SummerSpace.ready() and GameState.at_step("Q13", "give_wood"):
		await s.say("tanaka", "neutral", "……他们都试过了？就照这样摆吧。台子这头有我。")
		GameState.advance("Q13", "give_wood")
		return
	var choice: int = await s.ui.choose(["看看还要挪什么", "听听健一与花火的那晚", "聊别的事"])
	if choice == 0: await s.say("narrator", "", SummerSpace.hint()); return
	if choice == 2: await _other("tanaka"); return
	if GameState.hour() < 17.0:
		await s.say("tanaka", "neutral", "……还没收工。健一的事晚点说，桌椅现在能看。")
		return
	await s.say("tanaka", "neutral", "那年最后一发花火，是我和他一起点的。点完他说：明年换你点，我在台子上看。")
	await s.say("tanaka", "neutral", "……后来就没有明年了。")
	SummerSpace.state().past_heard = true
	GameState.save_game()

func _plan() -> void:
	if SummerSpace.state().phase == "invitation":
		if GameState.qstate("Q13") == "done":
			await s.say("narrator", "", "台子已经搭好了。桌椅还可以按今天的空处摆摆，请人试试。")
			var late: int = await s.ui.choose(["借社区桌椅，试试怎么摆", "之后再看"])
			if late == 0:
				var started: String = SummerSpace.start("light", "loan")
				if started != "": await s.say("narrator", "", started)
		else: await s.say("narrator", "", SummerSpace.hint())
		return
	await s.say("narrator", "", "蓝色块留给舞台和屋台，圆圈留给盆舞。长椅要看得见示范；用盘子的话，桌子放在长椅5米以内。")
	var pick: int = await s.ui.choose(["自己布置桌椅", "看看两种摆法", "选坐着看舞的长椅和放饭菜的桌子", "改用纸包或盘子", "请三位街坊来试试", "就按试好的摆", "看看跳舞时怎么绕路", "先收好"])
	match pick:
		0:
			s.ui.dialogue_end()
			s.placement.enter("space")
			if s.placement.active: await s.placement.exited
			s.ui.dialogue_begin()
		1: await _schemes()
		2: await _targets()
		3:
			var style: int = await s.ui.choose(["纸包，取了可以带走", "盘子，旁边得有桌子可放", "先保持现在的"])
			if style < 2: SummerSpace.set_style("paper" if style == 0 else "plate")
		4: await trial(false)
		5:
			var why: String = SummerSpace.retain()
			await s.say("narrator", "", why if why != "" else "这份摆法记下了，去跟田中说吧。夏祭人多时，再看看能不能走开。")
		6:
			if not SummerSpace.ready(): await s.say("narrator", "", "先试好桌椅的摆法，再看看跳舞时怎么走。")
			else: await trial(true)

func _targets() -> void:
	for kind: String in ["bench", "picnic_table"]:
		var options: Array = SummerSpace.project_furniture(kind)
		if options.is_empty(): await s.say("narrator", "", "场地里还没有" + GameState.item_name(kind)); return
		var labels: Array = options.map(func(p: Dictionary): return "%s · (%.1f, %.1f)" % [GameState.item_name(kind), float(p.x), float(p.z)])
		labels.append("先不换")
		var selected: int = await s.ui.choose(labels)
		if selected < options.size(): SummerSpace.choose_target(kind, int(options[selected].uid))

func _schemes() -> void:
	var selected: int = await s.ui.choose(["东侧：近处放盘子，供餐绕外边", "西侧：看舞近，纸包从北边拿", "先不选"])
	if selected == 2: return
	var key: String = "east" if selected == 0 else "west"
	var choice: int = await s.ui.choose(["看看地上标的位置", "照这样摆，还能再挪", "先留着"])
	if choice == 0:
		var current_key: String = key
		var original: Camera3D = s.get_viewport().get_camera_3d()
		var camera := Camera3D.new()
		s.main.add_child(camera)
		camera.position = Vector3(0, 19, 31)
		camera.look_at(Vector3(0, 0, 18))
		camera.fov = 58
		camera.make_current()
		while true:
			view.show_scheme(current_key)
			var comparison: int = await s.ui.choose(["照这样摆，我再挪挪", "看看另一份", "收起预览"])
			if comparison == 1: current_key = "west" if current_key == "east" else "east"; continue
			if comparison == 0:
				var result: String = apply_scheme(current_key)
				if result != "": await s.say("narrator", "", result)
			break
		view.clear_scheme()
		if is_instance_valid(original): original.make_current()
		camera.queue_free()
		return
	if choice == 2: return
	var why: String = apply_scheme(key)
	await s.say("narrator", "", why if why != "" else "桌椅照这份草案摆下了。按 B 可以挪位置，挪好再请街坊来试。")

func apply_scheme(key: String) -> String:
	if not SummerSpace.SCHEMES.has(key): return "先选一份草案。"
	var saved: Dictionary = GameState.to_dict().duplicate(true)
	var previous_context: String = PlacementSystem.project_context
	PlacementSystem.project_context = "space"
	var why := ""
	for existing_uid: Variant in SummerSpace.state().owned_uids.duplicate():
		var still_placed: bool = GameState.placements.any(func(entry: Dictionary): return int(entry.uid) == int(existing_uid))
		if still_placed and not GameState.remove_placement(int(existing_uid)): why = "旧草案暂时收不回来，先给背包留位置。"; break
	SummerSpace.state().owned_uids = []
	for pair: Array in [["bench", SummerSpace.SCHEMES[key].bench], ["picnic_table", SummerSpace.SCHEMES[key].table]]:
		if why != "": break
		var coords: Array = pair[1]
		var id: String = pair[0]
		var at := Vector2(float(coords[0]), float(coords[1]))
		why = PlacementSystem.check_rect(at, PlacementSystem.footprint(id, int(coords[2])))
		if why == "" and not GameState.has(id): why = "缺少实际桌椅。可以收回已有的，或第一次开始时借一组。"
		if why == "":
			var uid: int = GameState.add_placement(id, at.x, at.y, int(coords[2]))
			SummerSpace.state()["bench_uid" if id == "bench" else "table_uid"] = uid
	PlacementSystem.project_context = previous_context
	if why != "":
		GameState.from_dict(saved)
		s.placement.rebuild()
		GameState.lock_input("dialogue")
		return why + "原方案已恢复，不丢桌椅。"
	SummerSpace.state().scheme = key
	SummerSpace.state().style = str(SummerSpace.SCHEMES[key].style)
	SummerSpace.state().phase = "arranging"
	GameState.state_changed.emit()
	GameState.save_game()
	return ""

func trial(application: bool) -> void:
	var pending: Array[String]=[]
	for who: String in ["mio","haru","ren"]:
		if not SummerSpace.trial_current(who,application):pending.append(who)
	if pending.is_empty():
		await s.say("narrator","","几处都还合用，沿用上回的安排就好。")
		return
	var needed: Array[String]=pending.duplicate()
	if pending.has("haru") and not needed.has("mio"):needed.append("mio")
	for candidate: String in needed:
		var available_actor: NPC = s.npcs[candidate]
		if not SummerSpace.state().invited.has(candidate) or available_actor.home or not available_actor.visible or available_actor.global_position.x > 40:
			await s.say("narrator", "", "先跟%s约好，等他来庭院再一起看。" % GameState.npc_display(candidate))
			return
	if not SummerSpace.stop_for("bench").is_finite() or not SummerSpace.stop_for("picnic_table").is_finite():
		await s.say("narrator", "", "先把长椅和桌子摆好。有好几件时，从纸签上选要试哪件。")
		return
	var speed: int = await s.ui.choose(["看大家走一遍", "快速看完这一轮", "先收好方案"])
	if speed == 2: return
	# Only stage the invited, present cast. These cuts are not recorded as travel.
	await s.ui.fade_out(.2)
	if pending.has("mio"):s.npcs.mio.place(SummerSpace.ENTRY,0)
	elif pending.has("haru"):s.npcs.mio.place(SummerSpace.DEMO,0)
	if pending.has("haru"):s.npcs.haru.place(SummerSpace.HARU_START,0)
	if pending.has("ren"):s.npcs.ren.place(SummerSpace.FOOD_START,0)
	await s.ui.fade_in(.2)
	var stamp: String = SummerSpace.revision()
	for who: String in pending:
		var actor: NPC = s.npcs[who]
		var started_at: Vector3=actor.global_position
		var original_speed: float = actor.speed
		actor.speed = 4.5 if speed == 1 else 1.5
		actor.set_talking(true)
		var target: Vector3 = SummerSpace.DEMO if who == "mio" else SummerSpace.stop_for("bench" if who == "haru" else "picnic_table")
		var circles: Array = [[SummerSpace.DANCE_CENTER, SummerSpace.DANCE_RADIUS]] if application and who != "mio" else []
		var route: Dictionary = ProjectRoute.query(s.world, actor.global_position, target, [], stamp, circles)
		if not route.ok:
			actor.speed = original_speed
			actor.set_talking(false)
			await s.say("narrator", "", GameState.npc_display(who) + "：" + str(route.reason))
			return
		view.begin_walk(actor)
		s.ui.dlg.hide()
		var arrived := true
		if s.ui.instant:
			actor.place(target, 0)
			view.trace = route.path.duplicate()
		else: arrived = await actor.walk_safe(route.path)
		s.ui.dialogue_begin()
		var result := {"present": true, "arrived": arrived and not view.aborted, "revision": stamp,
			"position": {"x": actor.global_position.x, "y": actor.global_position.y, "z": actor.global_position.z},
			"length": float(route.length), "crossed_dance": SummerSpace.crosses_dance(view.trace), "path": [], "day": GameState.day}
		for point: Vector3 in view.trace: result.path.append({"x": point.x, "y": point.y, "z": point.z})
		result.path.push_front(LayoutValidity.position(started_at))
		result.path.append(LayoutValidity.position(actor.global_position))
		view.end_walk()
		actor.speed = original_speed
		actor.face(SummerSpace.DEMO)
		if who == "mio": actor.set_pose("dance" if application else "wave")
		if who == "haru":
			await s.get_tree().process_frame
			result["visible_demo"] = view.see_demo(actor, s.npcs.mio)
			result["sight"]={"from":LayoutValidity.position(view.eye(actor)),"to":LayoutValidity.position(view.eye(s.npcs.mio))}
			if arrived: await view.look_from(actor, s.npcs.mio)
		var why: String = SummerSpace.record(who, result, application)
		actor.set_talking(false)
		if why != "":
			s.npcs.mio.set_pose("idle")
			await s.say("narrator", "", why)
			return
		var response: String={"mio":"澪从入口走到示范的位置。","haru":"春在长椅边看清了澪的动作。","ren":"莲走了一遍取餐的路。"}[who]
		if result.crossed_dance and who!="mio":response+="跳舞的时候，这段路得绕外边走。"
		await s.say("narrator","",response)
	s.npcs.mio.set_pose("idle")
	await s.say("narrator", "", "这份安排用得上。" if application else "这几处都试过了。就这样摆，还是再挪挪？")

class_name StoryProjects
extends RefCounted
var s: Story

func _init(story: Story) -> void:
	s = story

func handles(id: String) -> bool:
	return id in ["opening_paper", "opening_site"] or (SummerProjects.phase() == "feedback" and id in ["mio", "haru", "kazuko", "store_counter"])

func prompt(id: String) -> Variant:
	if not handles(id): return null
	if id == "opening_paper": return "看看莲的合作纸签" if SummerProjects.phase() == "invitation" else "继续这一小篮的合作"
	if id == "opening_site": return "看取餐停点 · 试走 · 招待"
	return "请%s尝这一批小份" % GameState.npc_display("kazuko" if id == "store_counter" else id)

func _present(who: String) -> bool:
	var actor: NPC = s.npcs.get(who)
	return actor != null and not actor.home and actor.is_visible_in_tree() and actor.global_position.distance_to(s.player.global_position) < 8.0

func handle(id: String) -> void:
	if id == "opening_paper": await _paper()
	elif id == "opening_site": await _site()
	else: await _taste("kazuko" if id == "store_counter" else id)

func _paper() -> void:
	if not _present("ren"):
		await s.say("narrator", "", "莲不在柜台旁。纸签放着，下次找他聊。")
		return
	var phase: String = SummerProjects.phase()
	if phase == "invitation":
		await s.say("ren", "neutral", "先做一份吧。切开让街坊尝尝，看看吃着怎么样。")
		await s.say("ren", "happy", "你想烤，还是帮我招待？我一个人两头跑，可顾不过来。")
		var role: int = await s.ui.choose(["我来试做，再请人尝尝", "你来烤，我招待来的人", "改天再做"])
		if role == 2: return
		var why: String = SummerProjects.accept("food" if role == 0 else "host")
		if why != "": await s.say("narrator", "", why); return
		phase = SummerProjects.phase()
	if phase == "plan":
		await s.say("ren", "neutral", "三明治吃着清爽，佛卡夏能切开分。你想试哪种？")
		await s.say("narrator", "", "三明治：黄瓜1、番茄2、面粉1、黄油1。佛卡夏：番茄3、面粉1。烤的时间也不同。")
		var menu: int = await s.ui.choose(["三明治，清爽好拿", "佛卡夏，切开一起吃", "之后再决定"])
		if menu == 2: return
		var source: int = await s.ui.choose(["我带食材来", "借店里一包试料", "先不领材料"])
		if source == 2: return
		var why: String = SummerProjects.choose_plan("sandwich" if menu == 0 else "focaccia", "own" if source == 0 else "shop")
		if why != "": await s.say("narrator", "", why); return
		phase = SummerProjects.phase()
	if phase == "trial":
		var p: Dictionary = SummerProjects.opening()
		var prepare: int = await s.ui.choose(["照这张纸签继续做", "换菜单或食材", "把没用的试料还给莲", "之后再来"])
		if prepare == 3: return
		if prepare == 2:
			var returned: String = SummerProjects.return_kit()
			await s.say("narrator", "", returned if returned != "" else "未用的试料还给莲了，想试别的可以再选。")
			return
		if prepare == 1:
			if p.kit_held: SummerProjects.return_kit()
			p.phase = "plan"
			GameState.save_game()
			return
		if p.source == "shop" and not p.kit_held:
			var why: String = SummerProjects.claim_kit()
			if why != "": await s.say("narrator", "", why); return
		if p.role == "host":
			var why: String = SummerProjects.shop_prepares()
			if why != "": await s.say("narrator", "", why); return
			await s.say("ren", "happy", "烤好了，我切了三小份。请两位街坊尝，剩下一份你吃。")
		else:
			await s.say("ren", "happy", "里面的烤箱借你。这份配方不用买卡，烤好切成三小份就行。")
		return
	if phase == "feedback":
		await s.say("ren", "neutral", "找澪、春婆婆、和子阿姨，问两个人就行。带着走和坐着吃，兴许想法不一样。")
		var choice: int = await s.ui.choose(["带小份去请人尝尝", "收好这批，另试一种", "之后再来"])
		if choice == 1:
			SummerProjects.opening().phase = "plan"
			GameState.state_changed.emit()
			GameState.save_game()
			await s.say("narrator", "", "这批先收好，意见也记在纸签上。另试一种时，去换张新纸签。")
		return
	if phase == "decision":
		await s.say("ren", "neutral", "两个人都说了意见。你想留这味道，还是换一种再尝？")
		var change: int = await s.ui.choose(["就做这种，选份量和装法", "换一种再试试", "先留着意见"])
		if change == 2: return
		if change == 1:
			var next_menu: String = "focaccia" if SummerProjects.opening().menu == "sandwich" else "sandwich"
			var why: String = SummerProjects.choose_plan(next_menu, "shop")
			if why != "": await s.say("narrator", "", why)
			return
		var portion: int = await s.ui.choose(["切三小份，一人尝一点", "每人一整份，用三倍食材", "再想想"])
		if portion == 2: return
		var presentation: int = await s.ui.choose(["纸包，拿着走", "盘子，坐下吃，要留取盘的位置", "再想想"])
		if presentation == 2: return
		var why: String = SummerProjects.confirm_plan("bite" if portion == 0 else "whole", "paper" if presentation == 0 else "plate")
		if why != "": await s.say("narrator", "", why)
		else: await s.say("ren", "happy", "写好了。去庭院请人走一趟，看看桌椅会不会挡路。")
		return
	await s.say("ren", "neutral", "纸签在这儿。下回来了，咱们接着做。")

func _taste(who: String) -> void:
	var has_demo: bool=not SummerProjects.current_batch().get("usage_feedback",[]).is_empty()
	var choice: int = await s.ui.choose(["递一小份，问问好不好拿" if has_demo else "请尝一小份", "聊别的事", "之后再来"])
	if choice != 0:
		if choice == 1:
			if who == "kazuko": await s.farm.handle("store_counter")
			else: await s.call("_i_" + who)
		return
	var why: String = SummerProjects.taste_error(who,_present(who))
	if why != "": await s.say("narrator", "", why); return
	var batch: Dictionary=SummerProjects.current_batch()
	var prior: Array=batch.get("usage_feedback",[])
	var presentation: String="paper"
	if prior.is_empty():
		await s.say("narrator","","找块空台面，摆出这批的小份。纸托或餐盘都能试，按 Esc 先收起。")
		var style: int=await s.ui.choose(["纸托，试试拿着吃","餐盘，试试坐着分","先收好"])
		if style==2:return
		presentation="paper" if style==0 else "plate"
	else:
		presentation=str(prior[0].presentation)
		await s.say("narrator","","%s用%s尝过了。再问问另一位？"%[GameState.npc_display(str(prior[0].who)),"纸托" if presentation=="paper" else "餐盘"])
		var recipient: NPC=s.npcs.get(who)
		var received: Dictionary={"completed":true,"batch_id":int(batch.id),"menu":str(batch.menu),"presentation":presentation,"purpose":SummerProjects.tasting_purpose(who),"mode":"received","reference_who":str(prior[0].who)}
		why=SummerProjects.taste(who,_present(who) and recipient.global_position.distance_to(s.player.global_position)<2.6,received)
		if why!="":await s.say("narrator","",why);return
		Audio.fx("paper",-8)
		await _received_feedback(who,str(batch.menu))
		return
	var tasting:=ProjectTasting.new();s.main.add_child(tasting)
	var usage: Dictionary=await tasting.run(s,who,presentation)
	tasting.queue_free()
	if usage.has("error"):await s.say("narrator","",str(usage.error));return
	why=SummerProjects.taste(who,_present(who),usage)
	if why!="":await s.say("narrator","",why);return
	await _tasting_feedback(who,str(batch.menu),presentation)

func _received_feedback(who: String, menu: String) -> void:
	match who:
		"mio":
			if menu=="sandwich":await s.say("mio","happy","三明治我带去河边吃。公告栏刚弄完，想换个地方坐坐。给我张纸托就行。")
			else:await s.say("mio","happy","这块佛卡夏我带去河边。取餐时先切好，我拿一块就能走。")
		"haru":
			if menu=="sandwich":await s.say("haru","happy","三明治留着配麦茶。下回你来，咱们切小份放盘里，边吃边聊。")
			else:await s.say("haru","happy","佛卡夏留着配麦茶。切开放盘里，你来坐坐时也能拿一块。")
		"kazuko":
			if menu=="sandwich":await s.say("kazuko","happy","三明治我等忙完再吃。纸托省事！用盘子也行，还盘的地方放另一边，别跟取餐的人挤。")
			else:await s.say("kazuko","happy","佛卡夏我忙完再吃。小块留在取餐那边，整份到桌边分，省得都等着一把刀。")

func _tasting_feedback(who: String, menu: String, presentation: String) -> void:
	match who:
		"mio":
			if menu=="sandwich":
				if presentation=="paper":await s.say("mio","happy","黄瓜真脆。我忙完想去河边，带纸托这份正好。再留点边，手就碰不到馅了。")
				else:await s.say("mio","happy","黄瓜脆，番茄也清爽。我想带去河边，待会儿换张纸托吧。")
			else:
				if presentation=="paper":await s.say("mio","happy","这面包边真香。纸托一兜就能走，大块的留着分吧。")
				else:await s.say("mio","happy","边上烤得香。这样切开，大家能各尝一块。我去河边那份，再垫张纸托。")
		"haru":
			if menu=="sandwich":
				if presentation=="paper":await s.say("haru","happy","黄瓜脆，配茶好。纸托拿着省事，下回坐着聊，我还是想用盘子。")
				else:await s.say("haru","happy","黄瓜配麦茶正好。小份放盘里，咱们吃完还坐坐，我一下子吃不完那么多。")
			else:
				if presentation=="paper":await s.say("haru","happy","番茄烤过更香。纸托这块够我配茶，下回你来，整份切开放盘里吧。")
				else:await s.say("haru","happy","番茄烤过真香。切开摆盘里，你也拿一块尝尝。")
		"kazuko":
			if menu=="sandwich":
				if presentation=="paper":await s.say("kazuko","happy","这一口真清爽！忙的时候拿纸托好，吃完就不用回来还盘子。")
				else:await s.say("kazuko","happy","好吃！端了盘子，我还得回来还。回收处摆另一边吧，别挡着下一个人。")
			else:
				if presentation=="paper":await s.say("kazuko","happy","这面包香！先切几小块，赶时间的各拿一块，省得等你切。")
				else:await s.say("kazuko","happy","这小块够我尝啦。用盘子也行，取盘和还盘分两边，人多时不打架。")

func _site() -> void:
	var phase: String = SummerProjects.phase()
	if phase in ["invitation", "plan", "trial", "feedback", "decision"]:
		await s.say("narrator", "", SummerProjects.hint())
		return
	if phase == "ready" and GameState.phase == "market":
		await _apply_basket()
		return
	if phase in ["site", "ready"]:
		await s.say("narrator", "", "取餐的地方在摊前，从入口走一趟，看看桌椅和树根挡不挡路。")
		var choice: int = await s.ui.choose(["请街坊过来走一趟", "布置庭院，挪挪桌椅", "之后再来"])
		if choice == 1:
			s.ui.dialogue_end()
			s.placement.enter()
			if s.placement.active: await s.placement.exited
			s.ui.dialogue_begin()
			return
		if choice == 2: return
		await _trial_route()
		return
	if phase in ["applied", "done"]:
		var candidates: Array[String] = []
		for who: String in ["mio", "haru", "kazuko"]:
			if _present(who) and int(SummerProjects.opening().service.remaining) > 0 and not SummerProjects.opening().service.served.has(who): candidates.append(who)
		var options: Array = candidates.map(func(who: String): return "递给" + GameState.npc_display(who))
		options.append("先收好合作纸签")
		options.append("包好剩的饭菜")
		options.append("再看看去摊边的路")
		var pick: int = await s.ui.choose(options)
		var why: String = ""
		if pick < candidates.size():
			await _deliver(candidates[pick])
			return
		elif pick == candidates.size(): why = SummerProjects.finish()
		elif pick == candidates.size() + 1: why = SummerProjects.pack_leftovers()
		else:
			await _trial_route(false)
			return
		if why != "": await s.say("narrator", "", why)
		elif pick == candidates.size(): await s.say("narrator", "", "合作纸签收好了，谁拿了哪份也记在上面。")
		else: await s.say("narrator", "", "剩的饭菜已包进背包，可以带回家吃。")
		return
	await s.say("narrator", "", "这回的菜单记好了。等夏祭还想做，拿这张纸签去找莲。")

func _trial_route(apply_after: bool = true) -> void:
	if not GameState.seating_ready():
		await s.say("narrator", "", "先把桌和长椅摆下，再请人走走，看看路够不够宽。")
		return
	var choices: Array[String] = []
	for who: String in ["mio", "haru", "kazuko"]:
		var actor: NPC = s.npcs.get(who)
		if actor != null and not actor.home and actor.is_visible_in_tree() and actor.global_position.x < 40.0: choices.append(who)
	if choices.is_empty():
		await s.say("narrator", "", "街坊不在庭院。下次见面，再约他们来走一趟。")
		return
	var options: Array = choices.map(func(who: String): return "请" + GameState.npc_display(who) + "过来走一趟")
	options.append("之后再约")
	var pick: int = await s.ui.choose(options)
	if pick >= choices.size(): return
	var who: String = choices[pick]
	var actor: NPC = s.npcs[who]
	var excluded: Array[RID] = [s.player.get_rid()]
	for npc: NPC in s.npcs.values(): excluded.append(npc.body.get_rid())
	var finish := Vector3(2.0, 0, 13.0)
	var result: Dictionary = ProjectRoute.query(s.world, actor.global_position, finish, excluded)
	if result.ok:
		actor.set_talking(true)
		if s.ui.instant: actor.place(finish, 180)
		else:
			var walked: bool = await actor.walk_safe(result.path)
			if not walked:
				result["ok"] = false
				result["reason"] = "路被挡住了。先看看哪张桌椅挤着，挪开再试。"
		actor.set_talking(false)
	var why: String = SummerProjects.record_layout(result, who, actor.global_position.distance_to(finish) < .8)
	if why != "": await s.say("narrator", "", why); return
	await s.say("narrator", "", "已经走到摊前了。桌椅再挪的话，记得也走一遍。")
	if not apply_after: return
	if SummerProjects.uses_cooperation_mainline() and GameState.phase != "market":
		await s.say("narrator", "", "路试好了，去跟澪说，约街坊来。等开摊再摆这一篮。")
		return
	await _apply_basket()

func _apply_basket() -> void:
	var use: int = await s.ui.choose(["就这样摆，我出这一篮食材", "就这样摆，请莲出这一篮食材", "先挪桌椅，待会儿再备"])
	if use == 2: return
	var applied: String = SummerProjects.apply("own" if use == 0 else "shop")
	if applied != "": await s.say("narrator", "", applied)
	else: await s.say("narrator", "", "莲烤好这一篮，摊前也留出了位置。街坊来了，就能递给他们。")

func _deliver(who: String) -> void:
	var actor: NPC = s.npcs[who]
	var service: Dictionary = SummerProjects.opening().service
	if not SummerProjects.current_layout_valid():
		await s.say("narrator", "", "桌椅挪过了，再走走去摊边的路吧。这一篮先留着。")
		return
	var finish := Vector3(2, 0, 13)
	var route: Dictionary = ProjectRoute.query(s.world, actor.global_position, finish)
	if not route.ok:
		await s.say("narrator", "", str(route.reason))
		return
	actor.set_talking(true)
	var walked := true
	if s.ui.instant: actor.place(finish, 90)
	else: walked = await actor.walk_safe(route.path)
	if not walked:
		actor.set_talking(false)
		await s.say("narrator", "", "到摊边的路被挡住了，这一份还在篮里。")
		return
	var giver_at := Vector3(2.95, .05, 13)
	var probe := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = .35
	probe.shape = sphere
	probe.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED
	probe.transform = Transform3D(Basis.IDENTITY, giver_at + Vector3.UP * .65)
	if not s.world.get_world_3d().direct_space_state.intersect_shape(probe, 1).is_empty():
		actor.set_talking(false)
		await s.say("narrator", "", "摊前站不下，先挪出一个人的位置。")
		return
	await s.ui.fade_out(.2)
	s.player.global_position = giver_at
	s.player.velocity = Vector3.ZERO
	s.player.face_towards(actor.global_position)
	actor.face(s.player.global_position)
	s.main.rig.snap()
	await s.ui.fade_in(.2)
	var why: String = SummerProjects.begin_handoff(who, _present(who), actor.global_position, s.player.global_position)
	if why != "":
		actor.set_talking(false)
		await s.say("narrator", "", why)
		return
	var prior: Camera3D = s.main.get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	s.main.add_child(camera)
	camera.global_position = Vector3(4.7, 1.65, 11.2)
	camera.look_at(Vector3(2.45, 1.05, 13))
	camera.fov = 45
	if not s.ui.instant: camera.make_current()
	var gesture := LivingAction.new()
	s.main.add_child(gesture)
	gesture.duration = .08 if s.ui.instant else 2.1
	gesture.setup(s.player, "give", str(SummerProjects.MENUS[SummerProjects.opening().final.menu]))
	gesture.destination = actor.global_position.lerp(s.player.global_position, .5) + Vector3.UP * 1.05
	var receive_pose: LivingPose = null
	var rigs: Array[Node] = actor.find_children("*", "Skeleton3D", true, false)
	if not rigs.is_empty():
		receive_pose = LivingPose.new()
		(rigs[0] as Skeleton3D).add_child(receive_pose)
		receive_pose.goal_world = gesture.destination
		receive_pose.amount = 1
	s.ui.dlg.hide()
	while not gesture.finished:
		if receive_pose != null: receive_pose.phase = clampf(gesture.clock / gesture.duration, 0, 1)
		await s.main.get_tree().process_frame
	if receive_pose != null: receive_pose.queue_free()
	gesture.queue_free()
	prior.make_current()
	camera.queue_free()
	s.ui.dlg.show()
	var delivered: String = SummerProjects.finish_handoff(who, _present(who), actor.global_position, s.player.global_position)
	actor.set_talking(false)
	if delivered != "": await s.say("narrator", "", delivered)
	else: await s.say("narrator", "", "对方收下了这一小份，篮里还剩的先留着。")

class_name StoryWorkshop
extends RefCounted
var s: Story

func _init(story: Story) -> void:
	s = story

func handles(id: String) -> bool:
	return id in ["workroom_sign", "workroom_exit", "workroom_archive", "workroom_table", "workroom_lantern_test", "festival_work"] or id == "center_door" and SummerProjects.uses_cooperation_mainline()

func prompt(id: String) -> Variant:
	if not handles(id): return null
	return {"center_door": "走进社区工作间", "workroom_sign": "看看活动标牌", "workroom_exit": "回到街上", "workroom_archive": "翻看储物架上的账本", "workroom_table": "制作这一盏代表灯笼", "workroom_lantern_test": "亮灯试挂 · 看朝向和净空", "festival_work": "带这一盏到夏祭现场"}.get(id, "")

func handle(id: String) -> void:
	match id:
		"center_door":
			s.ui.dialogue_end()
			WorkshopProject.return_to_workroom()
			await s.main.enter_interior("workroom")
			s.ui.dialogue_begin()
		"workroom_exit":
			s.ui.dialogue_end()
			await s.main.exit_interior()
			s.ui.dialogue_begin()
		"workroom_archive": await _archive()
		"workroom_sign": await s._i_center_door()
		"workroom_table": await _table()
		"workroom_lantern_test": await _test(false)
		"festival_work": await site()

func site() -> void:
	if not WorkshopProject.state().installed.is_empty():
		var choice: int = await s.ui.choose(["看看灯朝哪边，走过会不会碰头", "散场了，把灯带回工作间", "之后再看"])
		if choice == 2: return
		if choice == 1:
			var returned: String = WorkshopProject.stow()
			await s.say("narrator", "", returned if returned != "" else "灯放回工作台了，纸签上留着这回挂过的地方和日期。")
			return
	var why: String = WorkshopProject.begin_site()
	if why != "": await s.say("narrator", "", why); return
	await _test(true)

func _archive() -> void:
	var p: Dictionary = WorkshopProject.state()
	var page: int = await s.ui.choose(["翻用具清单，看看灯笼怎么用", "翻木料与花火的那一页", "收好账本，之后再看"])
	if page == 2: return
	if page == 0:
		await s.ui.show_notice("健一的账本 · 用具", ["灯笼二十盏，春负责糊。", "旧的灯笼除了照亮庭院，也挂在树下，方便约人碰头。", "今年做一盏样灯，先看看从来路能否看见、走过时会不会碰到。"])
	else:
		await s.ui.show_notice("健一的账本 · 场地", ["盆舞台的木料、屋台排班、花火申请，分开记在几栏。", "最后一页停在2011年7月，后面全是空白。", "今年的场地已经不同。旧图纸能参考，走道还得按现在的桌椅留。"])
	if not p.archive_seen.has(page): p.archive_seen.append(page)
	GameState.save_game()
	if GameState.at_step("Q11", "find_notebook"):
		await s.lore._notebook()

func _table() -> void:
	var p: Dictionary = WorkshopProject.state()
	if p.phase == "invitation" and GameState.qstate("Q11") != "done":
		await s.say("narrator", "", "账本还没给春和澪看。先问问，今年缺哪样东西。")
		return
	if p.phase == "invitation":
		await s.say("narrator", "", "纸签上写着：先做一盏样灯，其余街坊来糊。和纸一张、竹篾一份都留好了，没做完的可以放工作台上。")
		var mode: int = await s.ui.choose(["自己对齐，扣好三个接头", "请街坊做灯体，我来试挂", "之后再来"])
		if mode == 2: return
		var purpose: int = await s.ui.choose(["挂树下，碰头时好认", "挂入口，让来的人看见", "之后再决定"])
		if purpose == 2: return
		var pattern: int = await s.ui.choose(["暖黄和纸 · 榉叶", "浅蓝和纸 · 水纹", "之后再决定"])
		if pattern == 2: return
		var why: String = WorkshopProject.start("hand" if mode == 0 else "plan", "meeting" if purpose == 0 else "guide", "leaf" if pattern == 0 else "wave")
		if why != "": await s.say("narrator", "", why); return
	if p.phase == "assembly":
		var controller := LanternAssembly.new()
		s.main.add_child(controller)
		await controller.run(s)
		controller.queue_free()
	if p.phase == "assembled": await s.say("narrator", "", "灯体接好了。到旁边架上试挂，点亮看看路口认不认得出。")
	else: await s.say("narrator", "", "没接完的还放这里，接好了也能调挂高和朝向。下回来继续。")

func _test(outdoor: bool) -> void:
	var p: Dictionary = WorkshopProject.state()
	if not outdoor and p.stored: WorkshopProject.restore_to_rack()
	if int(p.joints) != 3:
		await s.say("narrator", "", "三个接头还没扣齐。先接牢，再挂上架子。")
		return
	var view: WorkroomView = s.world.interiors.workroom.get_node("WorkroomProject")
	var pick: int = await s.ui.choose(["点亮，看看近处的字和远处的灯", "改挂高：齐眼 / 高过头", "转纸面：朝来路 / 朝背面", "先收着，改天再试","换吊点：走道上方 / 走道旁边","走近看看纸面","从来路看看灯"])
	if pick == 3: return
	if pick in [5,6]:
		await view.inspect("near" if pick==5 else "far",outdoor,s)
		return
	if pick==4:
		var mount: int=await s.ui.choose(["走道上方：挂高一点，远处好认","走道旁边：让开路，近处看字"])
		WorkshopProject.configure(float(p.height),float(p.facing),"path" if mount==0 else "side")
		await s.say("narrator","","吊点换好了。再看看远处认灯、近处看字，哪边更合适。")
		return
	if pick in [1, 2]:
		var setting: int = await s.ui.choose(["低位 1.55米", "高位 2.4米"] if pick == 1 else ["正面 0°", "反面 180°"])
		WorkshopProject.configure((1.55 if setting == 0 else 2.4) if pick == 1 else float(p.height), (0.0 if setting == 0 else 180.0) if pick == 2 else float(p.facing))
		await s.say("narrator", "", "位置改好了，点亮再看看。")
		return
	await s.get_tree().physics_frame
	await s.get_tree().physics_frame
	var result: Dictionary = view.trial(outdoor)
	if outdoor:
		var why: String = WorkshopProject.install(result)
		await s.say("narrator", "", why if why != "" else "工作间那盏灯挂上了。这里的路不同，再走走看会不会碰头。")
		return
	var why: String = WorkshopProject.record_trial(result)
	if why != "": await s.say("narrator", "", why); return
	var passage: String="走过时不用低头。" if result.clear else "走过去还会碰到，灯得再挪一挪。"
	var nearby: String="站在近处，纸上的字看得清楚。" if result.near_text_visible else "近处也看不清，试试转纸面，或挪开挡路的东西。"
	var arrival: String="从来路能认出这盏灯。" if result.far_marker_visible else "从来路看过去，灯还被挡着。"
	await s.say("narrator","",passage+nearby+arrival)
	var choice: int = await s.ui.choose(["就这样挂", "之后再调整"])
	if choice == 0:
		var retained: String = WorkshopProject.retain()
		await s.say("narrator", "", retained if retained != "" else "灯收好了。跟澪说说挂在哪儿，到夏祭再带来。")

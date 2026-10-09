extends RefCounted
## A person's identity and a heard life event are presentation facts, separate from accepted work.
static func context(story: Node, who: String) -> Dictionary:
	var place := "street"
	var actor: NPC = story.npcs.get(who)
	if story.main.in_room:
		place = story.main.room_kind
	elif actor != null and actor.global_position.x > FarmBuilder.ORIGIN.x - 200:
		var local: Vector3 = actor.global_position - FarmBuilder.ORIGIN
		place = "farm_shed" if local.distance_to(Vector3(-10.3, 0, -5.2)) < 4.0 else ("riverbank" if local.z > 9.0 else "farm_plots")
	elif actor != null:
		var at: Vector3 = actor.global_position
		if at.distance_to(Vector3(-6.4,0,-6.6)) < 4: place = "notice_board"
		elif at.distance_to(Vector3(-22.3,0,-14.4)) < 4: place = "bakery_front"
		elif at.distance_to(Vector3(-35.2,0,-14.4)) < 4: place = "store_front"
		elif at.distance_to(Vector3(-9.8,0,13.2)) < 3: place = "tree_shade"
		elif Rect2(-13,-5,31,31).has_point(Vector2(at.x,at.z)): place = "courtyard"
	return {"region": str(story.main.world.region), "place": place, "skip_entry": str(story.personal_event_skipped)}

static func introduce(story: Node, who: String) -> void:
	var actor: NPC = story.npcs.get(who)
	if actor == null or actor.home or not actor.is_visible_in_tree() or actor.global_position.distance_to(story.player.global_position) > 8.0: return
	var data: Dictionary = GameState.flags.get("neighbour_identity", {})
	if int(data.get("version",0)) != 1 or not data.has("presented") or GameState.qstate("Q00") != "done" or data.presented.has(who) or GameState.flags.get("met_"+who,false): return
	if who not in ["mio","ren","haru","tanaka","kazuko"]: return
	if who == "mio":
		await story.say("mio","happy","你就是三丁目的新邻居吧？我是澪，负责社区活动的联络。钥匙合用吗？")
		await story.say("mio","neutral","信箱里的便笺是我写的。这里有事就往公告栏留张纸，我每天都会来看。")
	elif who == "ren":
		await story.say("ren","happy","我是莲，街北边那家面包店是我的。你闻着香味来，通常就能找着。")
		await story.say("ren","neutral","我总把自己的早饭烤得最深。忙起来一走神，就晚了半分钟。")
	elif who == "haru":
		await story.say("haru","neutral","哎呀，新来的孩子？我是春。庭院里的花都是我照看的。")
		await story.say("haru","neutral","你奶奶以前也在这里歇脚。累了就坐一会儿，不用每回都带什么来。")
	elif who == "tanaka":
		await story.say("tanaka","neutral","田中。要找我，先看看菜圃，再看看工具棚。")
		await story.say("tanaka","neutral","苗袋放在干的那层。下过雨，湿木板容易把字洇掉。认不清，就来问。")
	elif who == "kazuko":
		await story.say("kazuko","happy","哎呀，是新搬来的那家孩子吧！我是和子，这家店开了四十年啦。")
		await story.say("kazuko","neutral","要是忘了东西叫什么，就形容给我听。街上好几家都是这么来买东西的。")
	data.presented[who] = {"day":GameState.day,"place":context(story,who).place}
	GameState.flags["met_"+who] = true
	GameState.state_changed.emit()
	GameState.save_game()

static func personal_event(story: Node, who: String) -> bool:
	var actor: NPC = story.npcs.get(who)
	if actor == null or actor.home or not actor.is_visible_in_tree() or actor.global_position.distance_to(story.player.global_position) > 8.0: return false
	var entry: Dictionary = Dialogue.pick(who, context(story,who))
	if entry.is_empty() or not entry.get("event",false): return false
	var options: Array[String] = ["听听%s想说的小事" % story.npc_name(who),"继续手头的事","今天先各忙各的"]
	# The technical driver explicitly chooses the work topic; ordinary players see every option.
	if story.ui.auto_work_priority: story.ui.auto_choices.push_front(1)
	var choice: int = await story.ui.choose(options)
	if choice == 1:
		story.personal_event_skipped = str(entry.id)
		return false
	if choice == 2:
		if not GameState.flags.has("dlg_deferred"): GameState.flags["dlg_deferred"] = {}
		GameState.flags.dlg_deferred[str(entry.id)] = GameState.day
		GameState.save_game()
		return true
	await story.farm.present_entry(entry)
	return true

extends RefCounted
var t: Node
var G: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	G = GameState
	main = runner.main

func run() -> void:
	var original: Dictionary = G.to_dict().duplicate(true)
	if main.in_room:
		if main.room_kind == "house": await main.exit_room()
		else: await main.exit_interior()
	G.new_game()
	G.clock_paused = true
	G.quests.Q00 = {"state": "done", "step": 2}
	t.check("WORKROOM_GATE", "arriving never invents a crafted lantern or a known notebook", WorkshopProject.state().phase == "invitation" and WorkshopProject.state().work_id == "" and not Progress.found("col_notebook"))
	t.check("WORKROOM_GATE", "work starts after the actual notebook discussion", WorkshopProject.start("hand", "guide", "wave") != "" and not G.has("washi"))
	G.quests.Q11 = {"state": "active", "step": 0}
	await t.use("center_door")
	t.check("WORKROOM_SPACE", "the community doorway enters an actual third interior", main.in_room and main.room_kind == "workroom" and InteriorBuilder.at(main.player.global_position) == "workroom")
	var interior: InteriorBuilder = main.world.interiors.workroom
	var imported: bool = interior.pieces.size() == 1 and str(interior.pieces[0].get_meta("model_id", "")) == "W13_cedar_worktable"
	var surface: float = WorldBuilder.rendered_support_height(interior.pieces[0], interior.origin + Vector3(-1.2, 0, -.4)) if imported else NAN
	t.check("WORKROOM_MODEL", "the actual Hyper3D table supports the work at its measured 0.78 metre top", imported and is_finite(surface) and absf(surface - .78) < .015, str(surface))
	await t.use("workroom_archive", [0])
	t.check("WORKROOM_ARCHIVE", "a relevant page lets the notebook question continue without compulsory full reading", G.at_step("Q11", "show_haru") and WorkshopProject.state().archive_seen.size() == 1)
	await t.use("workroom_archive", [1])
	t.check("WORKROOM_ARCHIVE", "the other page stays optional and cannot skip the next character conversation", G.at_step("Q11", "show_haru") and Progress.found("col_notebook") and WorkshopProject.state().archive_seen.size() == 2)
	G.quests.Q11 = {"state": "done", "step": 3}
	G.quests.Q12 = {"state": "available", "step": 0}
	var why: String = WorkshopProject.start("hand", "guide", "wave")
	t.check("WORKROOM_MATERIAL", "one representative work receives precisely one paper and bamboo bundle", why == "" and G.count("washi") == 1 and G.count("bamboo_strip") == 1 and G.at_step("Q12", "make_lanterns"))
	t.check("WORKROOM_MATERIAL", "project materials are protected while a first connection is pending", G.reserved_count("washi") == 1 and G.unreserved_count("washi") == 0)
	WorkshopProject.start("hand", "meeting", "leaf")
	t.check("WORKROOM_MATERIAL", "repeating the invitation never issues more materials", G.count("washi") == 1 and G.count("bamboo_strip") == 1)
	t.check("WORKROOM_FIT", "a visibly misaligned join keeps the materials and unfinished work", WorkshopProject.fit() != "" and int(WorkshopProject.state().joints) == 0 and G.count("washi") == 1)
	WorkshopProject.rotate_part(-60)
	WorkshopProject.fit()
	t.check("WORKROOM_FIT", "the first aligned connection consumes the finite materials exactly once", int(WorkshopProject.state().joints) == 1 and G.count("washi") == 0 and G.count("bamboo_strip") == 0 and WorkshopProject.state().work_id != "")
	G.player_pos = main.player.global_position
	G.player_in_room = true
	G.has_player_pos = true
	G.save_game()
	var half: Dictionary = WorkshopProject.state().duplicate(true)
	G.flags.clear()
	G.load_game()
	main._restore()
	t.check("WORKROOM_SAVE", "SQLite restores the exact half-work and real workroom location", WorkshopProject.state() == half and main.room_kind == "workroom" and main.player.global_position.distance_to(G.player_pos) < .2, "expected=" + JSON.stringify(half) + " actual=" + JSON.stringify(WorkshopProject.state()) + " room=" + main.room_kind + " position=" + str(main.player.global_position) + " saved=" + str(G.player_pos))
	while int(WorkshopProject.state().joints) < 3:
		WorkshopProject.rotate_part(float(WorkshopProject.TARGETS[int(WorkshopProject.state().joints)]) - float(WorkshopProject.state().angle))
		WorkshopProject.fit()
	t.check("WORKROOM_FIT", "three actual connections yield one player-made body without five repeats", WorkshopProject.state().phase == "assembled" and WorkshopProject.state().maker == "player" and G.count("chochin_hand") == 0)
	var view: WorkroomView = main.world.interiors.workroom.get_node("WorkroomProject")
	WorkshopProject.configure(1.55, 0)
	await t.frames(3)
	var low: Dictionary = view.trial()
	WorkshopProject.record_trial(low)
	t.check("WORKROOM_TRIAL", "a low real collider blocks head clearance and cannot be retained", not low.clear and WorkshopProject.retain() != "")
	WorkshopProject.configure(2.4, 180)
	await t.frames(3)
	var back: Dictionary = view.trial()
	WorkshopProject.record_trial(back)
	t.check("WORKROOM_TRIAL", "a clear but reversed paper face is still an unusable wayfinding plan", back.clear and not back.readable and WorkshopProject.retain() != "")
	WorkshopProject.configure(2.4, 0)
	await t.frames(3)
	var good: Dictionary = view.trial()
	WorkshopProject.record_trial(good)
	t.check("WORKROOM_TRIAL", "a correct first available plan can be retained without remaking", good.clear and good.readable and good.lit and WorkshopProject.retain() == "" and G.at_step("Q12", "give_lanterns"), JSON.stringify(good))
	var identity: String = WorkshopProject.state().work_id
	main.story.lore._on_day(16)
	t.check("WORKROOM_CALENDAR", "residents do not overwrite a player's retained or half-complete representative", G.at_step("Q12", "give_lanterns") and not G.flags.get("town_finished_Q12", false) and WorkshopProject.state().work_id == identity)
	await t.use("workroom_exit")
	G.day = 17
	G.minute = 19 * 60
	main.world.sync_festivals()
	WorkshopProject.begin_site()
	await t.frames(3)
	var changed: Dictionary = view.trial(true)
	t.check("WORKROOM_REUSE", "an entrance guide meets a changed real viewing direction at the festival", not changed.readable and WorkshopProject.install(changed) != "")
	WorkshopProject.configure(2.4, 180)
	await t.frames(3)
	var installed: Dictionary = view.trial(true)
	t.check("WORKROOM_REUSE", "the same work can be installed after adapting to the festival approach", WorkshopProject.install(installed) == "" and str(WorkshopProject.state().installed.work_id) == identity and view.festival_lantern.get_meta("work_id") == identity, JSON.stringify(installed))
	WorkshopProject.configure(1.55, 180)
	t.check("WORKROOM_REUSE", "changing a hung work invalidates the old successful installation", WorkshopProject.state().installed.is_empty())
	WorkshopProject.return_to_workroom()
	await t.frames(3)
	t.check("WORKROOM_RECOVERY", "a cancelled field adjustment returns the same work to the trial rack", not WorkshopProject.state().site_preview and is_instance_valid(view.trial_lantern) and WorkshopProject.state().phase == "assembled" and WorkshopProject.state().work_id == identity)
	var phase_before: String = WorkshopProject.state().phase
	t.check("WORKROOM_RECOVERY", "a missing measurement cannot replace valid work progress", WorkshopProject.record_trial({"place": "missing", "revision": WorkshopProject.revision()}) != "" and WorkshopProject.state().phase == phase_before)
	G.new_game()
	G.quests.Q11 = {"state": "done", "step": 3}
	G.quests.Q12 = {"state": "available", "step": 0}
	WorkshopProject.start("plan", "meeting", "leaf")
	t.check("WORKROOM_CHOICE", "light interaction names the town as maker and still requires a real trial", WorkshopProject.state().maker == "town" and WorkshopProject.state().phase == "assembled" and WorkshopProject.retain() != "")
	G.from_dict(original.duplicate(true))
	G.clock_paused = true
	main._restore()

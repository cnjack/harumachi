extends "res://scripts/tools/daily_life_demo.gd"
func _ready() -> void:
	main = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): folder = arg.substr(11)
	if folder == "": folder = "/tmp/harumachi-calendar-demo"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(25)
	GameState.new_game()
	GameState.clock_paused = true
	NPC.roam_enabled = false
	Progress.quiet = true
	main.ui.instant = false
	main.ui.auto = false
	SummerProjects.state().mainline_mode = "legacy"
	GameState.quests.Q05 = {"state":"active","step":3}
	GameState.flags.invited_ren = true
	GameState.flags.invited_haru = true
	GameState.add_item("picnic_table",1,true)
	GameState.add_item("bench",1,true)
	GameState.add_placement("picnic_table",7,4,0)
	GameState.add_placement("bench",2.5,10.5,0)
	await tap(KEY_C)
	await frames(10)
	await shot("01_ready_appointment_in_calendar")
	var button: Button = null
	for candidate in main.ui.modal_layer.find_children("*","Button",true,false):
		if candidate.text.begins_with("去约好的首次集市"): button = candidate; break
	check("the real calendar offers the prepared appointment",button != null)
	if button:
		await click(button.get_global_rect().get_center())
		var deadline := Time.get_ticks_msec() + 10000
		while not main.ui.dlg_choices.visible and Time.get_ticks_msec() < deadline:
			await tap(KEY_E)
			await frames(6)
		await shot("02_informed_date_choice")
		await tap(KEY_1)
		while GameState.day < 3 or GameState.input_locked(): await frames(2)
	check("date arrival is saved at home before participation",GameState.day==3 and int(GameState.minute)==GameState.MARKET_OPEN and main.in_room and not GameState.flags.get("summer_attended",false))
	await shot("03_saved_arrival_at_home")
	GameState.day = 24
	GameState.minute = 18 * 60
	GameState.quests.Q15 = {"state":"active","step":1}
	check("the fireworks agreement uses its actual 19:30 start", int(CalendarAdvance.appointment("hanabi").minute) == 1170)
	await tap(KEY_C)
	await frames(10)
	button = null
	for candidate in main.ui.modal_layer.find_children("*","Button",true,false):
		if candidate.text.begins_with("去约好的晴川花火"): button = candidate; break
	check("the calendar exposes the fireworks appointment", button != null)
	if button:
		await click(button.get_global_rect().get_center())
		var deadline := Time.get_ticks_msec() + 10000
		while not main.ui.dlg_choices.visible and Time.get_ticks_msec() < deadline:
			await tap(KEY_E)
			await frames(6)
		await tap(KEY_1)
		await frames(30)
		while GameState.input_locked(): await frames(2)
	check("fireworks date arrival is 19:30 at home without fictional participation", int(GameState.minute) == 1170 and main.in_room and not GameState.flags.get("fest_hanabi",false))
	await shot("04_fireworks_1930_arrival")
	GameState.day = 30
	GameState.minute = GameState.DAY_END
	GameState.calendar_pending_save = 30
	var path: String = SaveDB.database_path
	var blocked: String = SaveDB.directory.path_join("native-blocked.db")
	DirAccess.make_dir_recursive_absolute(blocked)
	SaveDB.database_path = blocked
	main.ui.instant = true
	await main._on_late_night()
	main.ui.instant = false
	check("a real midnight save failure preserves the pending day", GameState.day == 30 and GameState.calendar_pending_save == 30)
	SaveDB.database_path = path
	DirAccess.remove_absolute(blocked)
	await tap(KEY_C)
	await frames(10)
	await shot("05_independent_retry_button")
	button = null
	for candidate in main.ui.modal_layer.find_children("*","Button",true,false):
		if candidate.text == "重试保存暂停的这一天": button = candidate; break
	check("the real retry button remains usable after appointments have expired", button != null)
	if button:
		main.ui.auto = true
		await click(button.get_global_rect().get_center())
		var deadline := Time.get_ticks_msec() + 15000
		while (GameState.day != 31 or GameState.input_locked()) and Time.get_ticks_msec() < deadline: await frames(2)
		main.ui.auto = false
	check("clicking retry saves the pending day and recovers midnight to the next morning", GameState.day == 31 and int(GameState.minute) == GameState.WAKE_MIN and GameState.calendar_pending_save == -1)
	await shot("06_midnight_retry_morning")
	await main.exit_room()
	GameState.new_game()
	GameState.clock_paused = true
	SummerProjects.state().mainline_mode = "legacy"
	GameState.day = 5
	GameState.minute = 18.5 * 60
	GameState.quests.Q00 = {"state":"done","step":2}
	GameState.quests.Q05 = {"state":"done","step":5}
	GameState.quests.Q11 = {"state":"done","step":3}
	GameState.quests.Q12 = {"state":"available","step":0}
	GameState.quests.Q13 = {"state":"available","step":0}
	main.update_npcs(true)
	await frames(8)
	await use_point("mio",[])
	check("an actual old-save conversation presents the invitation without inventing completed practice", GameState.flags.get("summer_invitation",{}).get("presented",false) and GameState.qstate("Q12") == "available" and GameState.qstate("Q13") == "available" and not CalendarAdvance.appointment("summer").is_empty())
	await tap(KEY_C)
	await frames(10)
	await shot("07_summer_invitation_without_two_required_projects")
	button = null
	for candidate in main.ui.modal_layer.find_children("*","Button",true,false):
		if candidate.text.begins_with("去约好的晴町夏祭"): button = candidate; break
	if button:
		await click(button.get_global_rect().get_center())
		var invitation_deadline: int = Time.get_ticks_msec() + 10000
		while not main.ui.dlg_choices.visible and Time.get_ticks_msec() < invitation_deadline:
			await tap(KEY_E)
			await frames(6)
		await tap(KEY_1)
		var arrival_deadline: int = Time.get_ticks_msec() + 20000
		while (GameState.day != 17 or GameState.input_locked()) and Time.get_ticks_msec() < arrival_deadline: await frames(2)
	check("the agreed summer date arrives at home with honest town preparation and no attendance", GameState.day == 17 and int(GameState.minute) == 1020 and main.in_room and GameState.flags.get("town_finished_Q12",false) and GameState.flags.get("town_finished_Q13",false) and not GameState.flags.get("summer_attended",false))
	await shot("08_summer_arrival_with_town_authorship")
	var file := FileAccess.open(folder.path_join("native-demo.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"shots":shots,"day":GameState.day,"minute":GameState.minute,"scope":"fixture ready legacy market/fireworks, old Q11-complete save and blocked database; actual conversation/invitation, C/mouse/E/1, daily saving, 19:30, late retry and town-authored summer arrival"},"  "))
	Audio.silence()
	get_tree().quit(0 if failures.is_empty() else 1)

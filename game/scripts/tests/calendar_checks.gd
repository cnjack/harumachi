extends RefCounted
var t: Node
var main: Node
var G: Node
var writes: Array[Dictionary] = []
var messages: Array[String] = []
func _init(runner: Node) -> void:
	t = runner
	main = runner.main
	G = GameState
func notice(ok: bool, automatic: bool) -> void: writes.append({"ok":ok,"automatic":automatic})
func message(value: String) -> void: messages.append(value)
func prepare() -> void:
	G.new_game()
	G.clock_paused = true
	SummerProjects.state().mainline_mode = "legacy"
	G.quests.Q00 = {"state":"done","step":2}
	G.quests.Q05 = {"state":"active","step":3}
	G.flags.invited_ren = true
	G.flags.invited_haru = true
	G.add_item("picnic_table",1,true)
	G.add_item("bench",1,true)
	G.add_placement("picnic_table",7,4,0)
	G.add_placement("bench",2.5,10.5,0)
	G.plots.farm0.open = true
	G.plots.farm0.crop = "radish"
	G.plots.farm0.tilled = true
	G.plots.farm0.days = 0
	G.plots.farm0.water = true
	G.save_game()
	writes.clear()
func saved(slot: String) -> Dictionary:
	for row: Dictionary in SaveDB.load_candidates():
		if row.slot == slot: return row.data
	return {}
func run() -> void:
	var original: Dictionary = G.to_dict().duplicate(true)
	await grid_checks()
	var instant: bool = main.ui.instant
	main.ui.instant = true
	G.save_finished.connect(notice)
	G.new_game()
	t.check("CALENDAR_READY","no prepared-date shortcut is invented on arrival",CalendarAdvance.appointments().is_empty())
	prepare()
	main.ui.auto_choices = [1]
	await main.ui.panels._advance_appointment("market")
	t.check("CALENDAR_CANCEL","declining the informed date advance preserves day and crops",G.day==1 and G.plots.farm0.days==0 and writes.is_empty())
	var ok: bool = await main.calendar.run("market")
	t.check("CALENDAR_SETTLE","ready first market advances to the real Saturday time",ok and G.day==3 and int(G.minute)==G.MARKET_OPEN)
	t.check("CALENDAR_SETTLE","unwatered skipped days do not grow crops as though cared for",int(G.plots.farm0.days)==1 and not G.plots.farm0.water)
	t.check("CALENDAR_SAVE","two daily rollovers save exactly twice without an extra final-day save",writes.size()==2 and writes.all(func(row:Dictionary):return row.ok and row.automatic) and int(saved("current").day)==3 and int(saved("previous").day)==2)
	t.check("CALENDAR_PLACE","agreed-date arrival stays at home without fictional event attendance",G.player_in_room and G.player_region=="town" and not G.flags.get("summer_attended",false))
	prepare()
	var path: String = SaveDB.database_path
	var backup: String = SaveDB.backup_path
	var blocked: String = SaveDB.directory.path_join("calendar-blocked.db")
	DirAccess.make_dir_recursive_absolute(blocked)
	SaveDB.database_path = blocked
	SaveDB.backup_path = SaveDB.directory.path_join("calendar-no-backup.db")
	var failed: bool = not await main.calendar.run("market")
	t.check("CALENDAR_FAILURE","write failure stops at the first unsettled-save day",failed and G.day==2 and G.calendar_pending_save==2 and int(G.plots.farm0.days)==1 and writes.size()==1 and not writes[0].ok)
	SaveDB.database_path = path
	SaveDB.backup_path = backup
	DirAccess.remove_absolute(blocked)
	writes.clear()
	var retried: bool = await main.calendar.run("market")
	t.check("CALENDAR_RETRY","retry writes the existing settled day rather than repeating its effects",retried and G.day==3 and int(G.plots.farm0.days)==1 and G.calendar_pending_save==-1 and writes.size()==2)
	t.check("CALENDAR_RETRY","successful retry retains the immediately previous real date",int(saved("current").day)==3 and int(saved("previous").day)==2)
	G.quests.Q11 = {"state":"done","step":3}
	G.quests.Q12 = {"state":"done","step":4}
	G.quests.Q13 = {"state":"done","step":4}
	G.quests.Q14 = {"state":"available","step":0}
	t.check("CALENDAR_INVITATION","quest state alone cannot invent a presented summer invitation",CalendarAdvance.appointment("summer").is_empty())
	G.quests.Q05 = {"state":"done","step":5}
	G.flags["summer_invitation"] = {"presented":true,"source":"mio","day":17,"minute":1020}
	t.check("CALENDAR_READY","a presented summer invitation exposes the actual agreed date",not CalendarAdvance.appointment("summer").is_empty())
	G.quests.Q13 = {"state":"available","step":0}
	t.check("CALENDAR_CHOICE","cooperation and lantern practice can reach the date without compulsory space practice",not CalendarAdvance.appointment("summer").is_empty())
	G.quests.Q12 = {"state":"available","step":0}
	G.quests.Q13 = {"state":"done","step":4}
	t.check("CALENDAR_CHOICE","cooperation and space practice can reach the date without compulsory lantern practice",not CalendarAdvance.appointment("summer").is_empty())
	G.day = 18
	t.check("CALENDAR_LATE","a missed date never offers a backwards time shortcut",CalendarAdvance.appointment("summer").is_empty())
	G.day = 20
	G.quests.Q15 = {"state":"active","step":1}
	t.check("CALENDAR_READY","the old tube investigation unlocks the actual fireworks agreement",not CalendarAdvance.appointment("hanabi").is_empty())
	# A pending day's protection must hold outside the calendar entry too.
	prepare()
	G.day = 2
	G.calendar_pending_save = 2
	G.plots.farm0.days = 1
	G.plots.farm0.water = true
	SaveDB.database_path = blocked
	SaveDB.backup_path = SaveDB.directory.path_join("calendar-no-backup.db")
	DirAccess.make_dir_recursive_absolute(blocked)
	var protected: bool = not G.advance_day()
	t.check("CALENDAR_PENDING", "ordinary sleep's day-cut cannot cross an unsaved date", protected and G.day == 2 and int(G.plots.farm0.days) == 1 and G.plots.farm0.water)
	SaveDB.database_path = path
	SaveDB.backup_path = backup
	DirAccess.remove_absolute(blocked)
	G.day = 2
	G.calendar_pending_save = 2
	G.save_game()
	t.check("CALENDAR_PENDING", "successful manual saving clears the pending-date marker", G.calendar_pending_save == -1)
	G.day = 30
	G.calendar_pending_save = 30
	writes.clear()
	var independent: bool = await main.calendar.run("retry_save")
	t.check("CALENDAR_PENDING", "saving a paused date does not depend on a still-valid appointment", independent and G.calendar_pending_save == -1 and writes.size() == 1 and int(saved("current").day) == 30)
	prepare()
	G.day = 3
	G.minute = 12 * 60
	G.save_game()
	SaveDB.database_path = blocked
	SaveDB.backup_path = SaveDB.directory.path_join("calendar-no-backup.db")
	DirAccess.make_dir_recursive_absolute(blocked)
	await main.calendar.run("market")
	SaveDB.database_path = path
	SaveDB.backup_path = backup
	DirAccess.remove_absolute(blocked)
	writes.clear()
	var same_day: bool = await main.calendar.run("market")
	t.check("CALENDAR_PENDING", "retry after an intraday write failure really commits time and home position once", same_day and writes.size() == 1 and int(saved("current").minute) == G.MARKET_OPEN and saved("current").player.in_room)
	prepare()
	G.day = 2
	G.minute = 18 * 60
	G.calendar_pending_save = 2
	G.plots.farm0.days = 1
	G.plots.farm0.water = true
	writes.clear()
	await main.sleep_now()
	t.check("CALENDAR_SLEEP", "a real sleep first saves the pending day then settles the requested next morning", G.day == 3 and int(G.minute) == G.WAKE_MIN and int(G.plots.farm0.days) == 2 and writes.size() == 2 and int(saved("previous").day) == 2)
	prepare()
	G.day = 8
	G.minute = G.DAY_END
	G.daily["late_sent"] = true
	G.calendar_pending_save = 8
	writes.clear()
	await main._on_late_night()
	t.check("CALENDAR_MIDNIGHT", "midnight retry reaches the next morning instead of remaining at 24:00", G.day == 9 and int(G.minute) == G.WAKE_MIN and writes.size() == 2 and int(saved("previous").day) == 8)
	G.day = 9
	G.minute = G.DAY_END
	G.daily["late_sent"] = true
	G.calendar_pending_save = 9
	SaveDB.database_path = blocked
	SaveDB.backup_path = SaveDB.directory.path_join("calendar-no-backup.db")
	DirAccess.make_dir_recursive_absolute(blocked)
	G.toast.connect(message)
	messages.clear()
	await main._on_late_night()
	G.toast.disconnect(message)
	t.check("CALENDAR_MIDNIGHT", "failed midnight writing stops without claiming that a successful overnight rest occurred", G.day == 9 and G.calendar_pending_save == 9 and not messages.any(func(value: String): return value.contains("昨晚太晚了")))
	SaveDB.database_path = path
	SaveDB.backup_path = backup
	DirAccess.remove_absolute(blocked)
	writes.clear()
	var midnight_retry: bool = await main.calendar.run("retry_save")
	t.check("CALENDAR_MIDNIGHT", "the independent retry also recovers a failed midnight to a real next morning", midnight_retry and G.day == 10 and int(G.minute) == G.WAKE_MIN and writes.size() == 2 and int(saved("previous").day) == 9)
	var broken_current: SQLite = SaveDB._open()
	broken_current.query("UPDATE snapshots SET checksum='calendar-test-corrupt' WHERE slot='current'")
	broken_current.close_db()
	G.load_game()
	G.clock_paused = true
	main._restore()

	writes.clear()
	G._tick_minute()
	var deadline: int = Time.get_ticks_msec() + 3000
	while (G.day == 9 or main._transition) and Time.get_ticks_msec() < deadline: await t.frames(1)
	G._tick_minute()
	t.check("CALENDAR_RESTORE", "loading a committed midnight backup resumes overnight rest exactly once", G.day == 10 and int(G.minute) == G.WAKE_MIN and writes.size() == 1 and int(saved("previous").get("day",0)) == 9, "day=%s minute=%s writes=%s" % [G.day,G.minute,writes.size()])
	G.save_finished.disconnect(notice)
	G.from_dict(original.duplicate(true))
	G.clock_paused = true
	main.ui.instant = instant
	main.placement.rebuild()
	main._restore()

func grid_checks() -> void:
	G.new_game();G.clock_paused=true
	for date_case: Array in [[1,3,"4"],[4,6,"7"],[33,0,"5"]]:
		G.day=int(date_case[0]);main.ui.panels.open_calendar();await t.frames(3)
		var grid: GridContainer=main.ui.modal_layer.find_children("*","GridContainer",true,false)[0]
		var today_column: int=-1
		for day_index: int in range(7,grid.get_child_count()):
			for label: Label in grid.get_child(day_index).find_children("*","Label",true,false):
				if label.text.begins_with(str(date_case[2])+"  今天"):today_column=day_index%7
		t.check("CALENDAR_GRID","calendar day %d appears in the same weekday column as its HUD"%G.day,today_column==int(date_case[1]) and today_column==G.weekday(),"column=%s weekday=%s"%[today_column,G.weekday()])
		if G.day==1:
			var saturday_column: int=-1
			for market_index: int in range(7,grid.get_child_count()):
				var labels: Array=grid.get_child(market_index).find_children("*","Label",true,false)
				if labels.size()>1 and labels[0].text=="6" and labels[1].text=="傍晚集市":saturday_column=market_index%7
			t.check("CALENDAR_GRID","the first actual Saturday market is shown under Saturday",saturday_column==5)
		main.ui.close_modal(false);await t.frames(2)

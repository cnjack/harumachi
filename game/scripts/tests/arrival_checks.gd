extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:
	t = runner; main = runner.main
func check(label: String, ok: bool) -> void:
	t.check("ARRIVAL_HOME", label, ok)
func run() -> void:
	var original: Dictionary = GameState.to_dict().duplicate(true)
	GameState.new_game()
	check("a fresh save explicitly owns its staged arrival", GameState.flags.get("arrival_home", {}).get("phase", "") == "bus")
	check("Main exposes the same arrival flow to ordinary and automatic entry", main.has_method("finish_arrival_home"))
	if not main.has_method("finish_arrival_home"):
		GameState.from_dict(original); return
	var written: int = 0
	var writes: Array[int] = [0]
	var write_days: Array[int] = []
	var counter: Callable = func(ok: bool, _automatic: bool):
		if ok: writes[0] += 1; write_days.append(GameState.day)
	GameState.save_finished.connect(counter)
	var result: bool = await main.finish_arrival_home(false)
	written = writes[0]
	check("arrival completes actual Q00 steps and gives exactly one key and note", result and GameState.qstate("Q00") == "done" and GameState.count("house_key") == 1 and GameState.count("welcome_note") == 1)
	check("free play starts on the next morning in the real bedroom", GameState.day == 2 and GameState.minute == GameState.WAKE_MIN and main.in_room and main.player.global_position.distance_to(HouseBuilder.ORIGIN + Vector3(-4.6, .05, -.6)) < .15)
	check("the actual meal remains a player action", not DailyLife.done("meal") and not DailyLife.event("meal").get("cooked", false))
	check("morning restores control and completes only the arrival stage", not GameState.input_locked() and not main.player.frozen and GameState.flags.arrival_home.phase == "done")
	check("arrival commits the next morning exactly once", write_days.count(2) == 1)
	var bed_snapshot: Dictionary = {}
	for candidate: Dictionary in SaveDB.load_candidates():
		if candidate.slot == "previous": bed_snapshot = candidate.data.duplicate(true)
	check("the previous committed snapshot is the actual first night", int(bed_snapshot.get("day", 0)) == 1 and bed_snapshot.get("flags", {}).get("arrival_home", {}).get("phase", "") == "bed")
	var overnight: int = GameState.day
	await main.finish_arrival_home(false)
	check("re-entering a completed arrival neither duplicates objects nor advances another day", GameState.day == overnight and GameState.count("house_key") == 1 and writes[0] == written)
	check("the persisted morning can really be read", GameState.load_game())
	main._restore()
	await main.finish_arrival_home(false)
	check("loading the saved morning cannot replay arrival or move away", GameState.day == overnight and GameState.flags.arrival_home.phase == "done" and main.in_room)
	# A persisted pre-overnight stage may come from a quit or a failed next-day write.
	GameState.new_game()
	GameState.flags.arrival_home.phase = "bed"
	GameState.flags.arrival_home.origin_day = 1
	GameState.add_item("house_key", 1, true); GameState.add_item("welcome_note", 1, true)
	GameState.advance("Q00", "mailbox"); GameState.advance("Q00", "enter_home")
	await main.finish_arrival_home(false)
	check("resuming the settled bedroom stage advances once without claiming a meal", GameState.day == 2 and GameState.count("house_key") == 1 and not DailyLife.done("meal"))
	GameState.flags.erase("arrival_home")
	GameState.day = 5
	var old_position: Vector3 = main.player.global_position
	await main.finish_arrival_home(false)
	check("legacy saves never acquire or replay a new arrival", GameState.day == 5 and main.player.global_position == old_position and not GameState.flags.has("arrival_home"))
	main.ui.open_arrival_retry(main.finish_arrival_home)
	var escape := InputEventAction.new(); escape.action = "pause"; escape.pressed = true
	Input.parse_input_event(escape)
	await t.frames(2)
	escape.pressed = false; Input.parse_input_event(escape)
	check("Escape cannot discard the failed arrival's retry controls", main.ui.modal == "arrival_retry")
	main.ui.close_modal(false)
	if not bed_snapshot.is_empty():
		bed_snapshot.flags.arrival_home.clock_was_paused = false
		GameState.from_dict(bed_snapshot); main._restore()
		var database: String = SaveDB.database_path; var backup: String = SaveDB.backup_path
		var blocked: String = SaveDB.directory.path_join("blocked-arrival.db")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked))
		SaveDB.database_path = blocked; SaveDB.backup_path = blocked + "/backup.db"
		var failed: bool = not await main.finish_arrival_home(false)
		check("failed morning writing preserves a retry stage and frozen world", failed and GameState.day == 2 and GameState.flags.arrival_home.phase == "wake" and GameState.clock_paused and main.player.frozen)
		SaveDB.database_path = database; SaveDB.backup_path = backup
		DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))
		var resumed: bool = await main.finish_arrival_home(false)
		check("retry saves the settled morning without another rollover", resumed and GameState.day == 2 and not GameState.clock_paused and not main.player.frozen and GameState.calendar_pending_save == -1)
	GameState.save_finished.disconnect(counter)
	GameState.from_dict(original); main._restore(); GameState.clock_paused = true

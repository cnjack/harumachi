extends Node
## Fixtures supply crops and starting positions; E and real dialogue choices do the work.
var main: Node
var out := "/tmp/harumachi-homage-demo"
var failures: Array[String] = []

func _ready() -> void:
	main = get_parent()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--homage-demo-out="):
			out = arg.substr(18)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code, true); await frames(1); key(code, false); await frames(1)

func shot(name: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("HOMAGE_DEMO SHOT ", name)

func _run() -> void:
	await frames(30)
	GameState.clock_paused = true
	GameState.minute = 10.0 * 60.0
	main.ui.refresh_hud()
	main.world.update_time(GameState.minute, GameState.weather, true)
	main.ui.auto = true
	for entry: Dictionary in Homage.entries():
		var farm_region: bool = str(entry.region) == "farm"
		if farm_region and main.world.region != "farm":
			await main.go_farm()
		elif not farm_region and main.world.region == "farm":
			await main.leave_farm()
		var stand: Vector3 = Homage.world_position(entry, true)
		var focus: Vector3 = Homage.world_position(entry)
		main.player.global_position = stand + Vector3(0, .12, 0)
		main.player.velocity = Vector3.ZERO
		main.player.face_towards(focus)
		await frames(15)
		var rig: CameraRig = main.rig
		rig.process_mode = Node.PROCESS_MODE_DISABLED
		rig.cam.global_position = stand + Vector3(1.1, 1.5, 1.6)
		rig.cam.look_at(focus + Vector3(0, .55, 0))
		await shot(str(entry.id) + "_before")
		if main.player.target == null or main.player.target.id != str(entry.id):
			failures.append("wrong target: " + str(entry.id))
			continue
		for crop_id: String in entry.requires:
			GameState.add_item(crop_id, 1, true)
		var visits: int = maxi(1, entry.requires.size())
		for visit in visits:
			main.ui.auto_choices = [0]
			await tap(KEY_E)
			await frames(3)
			var deadline := Time.get_ticks_msec() + 20000
			while main.story.busy and Time.get_ticks_msec() < deadline:
				await frames(1)
			if main.story.busy:
				failures.append("dialogue timed out: " + str(entry.id))
				_finish(); return
		if not Homage.found(str(entry.id)):
			failures.append("not recorded: " + str(entry.id))
		await shot(str(entry.id) + "_after")
	main.ui.auto = false
	main.ui.book.open("homage")
	await frames(8)
	var grid: Node = main.ui.book._body.get_child(0)
	for index in grid.get_child_count():
		var tile := grid.get_child(index) as Button
		tile.pressed.emit()
		await shot("book_%02d" % index)
	main.ui.close_modal()
	var save_ok := GameState.save_game()
	GameState.flags.erase(Homage.STATE_KEY)
	var load_ok := GameState.load_game()
	if not save_ok or not load_ok or Homage.count() != Homage.entries().size():
		failures.append("SQLite round trip failed")
	_finish()

func _finish() -> void:
	var report := {"passed": failures.is_empty(), "failures": failures, "found": Homage.count(), "state": Homage.state(), "legacy_keepsakes": GameState.collection.size(), "fixture": "starting positions and crop inventory only; real E input and dialogue callbacks; SQLite save/load"}
	var file := FileAccess.open(out.path_join("demo.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("HOMAGE_DEMO DONE ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

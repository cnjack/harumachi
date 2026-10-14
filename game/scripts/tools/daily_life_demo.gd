extends Node
## Rendered keyboard/mouse verification with isolated HARUMACHI_SAVE_DIR.
## Fixture positioning is explicit; dialogue, choices, stove and eating use actual UI inputs.
var main: Node
var folder := ""
var failures: Array[String] = []
var shots: Array[String] = []
var seen_actions: Array[String] = []
var _qa_bakery_sample_captures: Array[Dictionary] = []
const DAILY_QA_CAPTURE = preload("res://scripts/tools/activity_visual_capture.gd")
var _daily_qa_capture_ms: int = 0

func _ready() -> void:
	main = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): folder = arg.substr(11)
	if folder == "": folder = "/tmp/harumachi-daily-demo"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(25)
	GameState.new_game()
	GameState.clock_paused = true
	NPC.roam_enabled = false
	Progress.quiet = true
	main.ui.instant = false
	main.ui.auto = false
	Audio.game_on = true
	await use_point("mailbox", [])
	await use_point("home_door", [0])
	check("arrival completed without accepting Q01", GameState.qstate("Q00") == "done" and GameState.qstate("Q01") == "available")
	await shot("01_arrival_invitation_result")
	await use_point("life_pantry", [0])
	check("pantry parcel", GameState.has("home_meal_parcel"))
	await use_point("house_stove", [])
	await frames(5)
	await shot("02_real_kitchen_recipe")
	var cook: Button = null
	for button in main.ui.root.find_children("*", "Button", true, false):
		if button.get_meta("recipe_id", "") == "first_home_onigiri" and not button.disabled and button.is_visible_in_tree():
			cook = button
			break
	if cook == null: failures.append("no available first-meal recipe button")
	else: await click(cook.get_global_rect().get_center())
	await frames(12)
	check("stove produces two portions", GameState.count("onigiri") == 2)
	await tap(KEY_ESCAPE)
	await frames(8)
	await use_point("life_meal_table", [0])
	check("first meal eats one", DailyLife.done("meal") and GameState.count("onigiri") == 1)
	await shot("03_first_meal_result")
	await tap(KEY_J)
	await frames(8)
	await shot("04_life_journal")
	await tap(KEY_ESCAPE)
	await main.exit_room()
	GameState.advance_day()
	GameState.minute = 12.0 * 60
	main.update_npcs(true)
	main.story.daily.view.sync_state()
	await use_point("life_tea", [1, 1])
	check("tea rest does not accept planting", DailyLife.done("tea") and GameState.qstate("Q03") == "locked" and GameState.crop_stage == 0)
	await shot("05_tea_result")
	GameState.advance_day()
	GameState.minute = 12.0 * 60
	main.update_npcs(true)
	main.story.daily.view.sync_state()
	var bakery_sample: bool = "--qa-bakery-sample" in OS.get_cmdline_user_args()
	if bakery_sample:
		# Re-observe the actual third-day meal rather than reusing first-home-meal
		# screenshots. Ordinary demos retain the original paper-helping choice.
		seen_actions.erase("eat")
		seen_actions.erase("eat_empty")
	await use_point("life_bakery_card", [1 if bakery_sample else 0])
	if bakery_sample:
		check("native bakery tasting eats the reserved sample and records tasting without helping the paper", DailyLife.event("card").get("tasted", false) and not DailyLife.event("card").get("helped_sign", false) and not GameState.has("life_bread_sample"))
		check("the real bakery eating action was photographed before and after eating", _qa_bakery_sample_captures.size() == 2)
	else: check("paper helped", DailyLife.event("card").get("helped_sign", false))
	await shot("06_bakery_taste_result" if bakery_sample else "06_bakery_sign_result")
	await prop_views()
	GameState.save_game()
	var facts: Dictionary = DailyLife.state().duplicate(true)
	GameState.flags.clear()
	var loaded: bool = GameState.load_game()
	print("DAILY_RELOAD ", loaded, " ", JSON.stringify(DailyLife.state()), " expected ", JSON.stringify(facts))
	check("SQLite restores all three life events", DailyLife.state().events == facts.events)
	check("meal table cut and supported tea pause rendered", seen_actions.has("eat") and seen_actions.has("eat_empty") and seen_actions.has("sip"))
	var file := FileAccess.open(folder.path_join("native-demo.json"), FileAccess.WRITE)
	var report: Dictionary = {"engine": Engine.get_version_info().string, "passed": failures.is_empty(), "failures": failures, "shots": shots, "input": "E / numeric choices / mouse cook / J / Escape", "scope": "fixture-positioned three-day sample; not human fun evidence", "facts": facts}
	if bakery_sample: report.bakery_sample = {"scope": "Real third-day life_bakery_card E interaction and tasting choice; actual LivingAction surfaces captured without moving the meal.", "captures": _qa_bakery_sample_captures}
	file.store_string(JSON.stringify(report, "  "))
	Audio.silence()
	get_tree().quit(0 if failures.is_empty() else 1)

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func frames(n: int) -> void:
	for _index in n: await get_tree().physics_frame

func tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	Input.parse_input_event(event)
	await frames(2)

func click(at: Vector2) -> void:
	var pixel: Vector2 = at * Vector2(DisplayServer.window_get_size()) / get_viewport().get_visible_rect().size
	var motion := InputEventMouseMotion.new()
	motion.position = pixel
	Input.parse_input_event(motion)
	await frames(2)
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = InputEventMouseButton.new()
	event.position = pixel
	event.button_index = MOUSE_BUTTON_LEFT
	Input.parse_input_event(event)
	await frames(4)

func use_point(id: String, picks: Array) -> void:
	var point: Interactable = null
	for candidate in get_tree().get_nodes_in_group("interactables"):
		if candidate.id == id: point = candidate; break
	if point == null: failures.append("missing point " + id); return
	var dir := Vector3(0, 0, 1)
	if id in ["center_door", "workroom_exit", "room_door"]: dir = Vector3(0, 0, -1)
	if id == "house_stove": dir = Vector3(1, 0, 0)
	if id == "life_meal_table": dir = Vector3(0, 0, -1)
	main.player.global_position = Vector3(point.global_position.x, .1, point.global_position.z) + dir * 1.15
	main.player.velocity = Vector3.ZERO
	main.player.face_towards(point.global_position)
	main.rig.snap()
	await frames(10)
	if main.player.target != point and main.npcs.has(id):
		# The fixture tests a valid E approach, not a forced target pointer through another point.
		for alternative: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD]:
			main.player.global_position = Vector3(point.global_position.x, .1, point.global_position.z) + alternative * 1.15
			main.player.velocity = Vector3.ZERO
			main.player.face_towards(point.global_position)
			main.rig.snap()
			await frames(10)
			if main.player.target == point: break
	if main.player.target != point:
		failures.append("E cannot target " + id + ": " + (main.player.target.id if main.player.target else "none"))
		return
	await tap(KEY_E)
	var deadline := _daily_qa_now_msec() + 35000
	var choices: Array = picks.duplicate()
	var captured := false
	while main.story.busy and _daily_qa_now_msec() < deadline:
		if main.ui.modal != "": return
		var action: LivingAction = null
		for child in main.get_children():
			if child is LivingAction: action = child
		if action != null:
			if action.mode == "eat" and action.clock > action.duration * .68 and not seen_actions.has("eat_empty"):
				seen_actions.append("eat_empty")
				await shot_action(action,"action_eat_after")
				if not is_instance_valid(action): continue
				check("the same plate becomes empty without a hand pose or floating completion text", action.pose == null and not action.meal_food.visible and action.prop.find_children("*", "Label3D", true, false).is_empty())
			if action.clock > action.duration * (.18 if action.mode == "eat" else .42) and not seen_actions.has(action.mode):
				seen_actions.append(action.mode)
				await shot_action(action,"action_" + action.mode)
				if not is_instance_valid(action): continue
				if action.mode == "eat":
					check("eating is shown on a real surface without character rigging", action.pose == null and action.skeleton == null and action.surface_at.is_finite() and action.meal_food.visible)
				else:
					check("tea stays on its real tray without hand or mouth IK", action.mode == "sip" and action.hand < 0 and action.pose == null and action.skeleton == null and action.surface_at.is_finite())
		elif main.ui.dlg.visible:
			var observed_camera: Camera3D=get_viewport().get_camera_3d()
			if id=="workroom_lantern_test" and main.ui.dlg_choices.visible and observed_camera!=main.rig.cam:
				var places: Dictionary=WorkroomView.observations(false)
				var observer: String="near" if observed_camera.global_position.distance_to(places.near)<.1 else "far"
				var observation: String="observe_%s_%s_%d" % [observer,WorkshopProject.state().mount,int(float(WorkshopProject.state().height)*100)]
				if not seen_actions.has(observation): seen_actions.append(observation);await shot(observation)
			if not captured:
				await frames(22)
				await shot("dialogue_" + id)
				captured = true
			if main.ui.dlg_choices.visible:
				await frames(4)
				var selected: Variant = choices.pop_front() if not choices.is_empty() else 0
				if selected is String:
					var found := false
					for button in main.ui.dlg_choices.get_children():
						if str(selected) in button.text:
							await click(button.get_global_rect().get_center())
							found = true
							break
					if not found: failures.append("missing actual choice " + str(selected)); return
				else: await tap(KEY_1 + int(selected))
			else:
				await frames(12)
				await tap(KEY_E)
		await frames(3)
	if main.story.busy: failures.append("dialogue timeout " + id)

func continue_dialogue(picks: Array) -> void:
	var choices: Array = picks.duplicate()
	var deadline := _daily_qa_now_msec() + 35000
	while main.story.busy and _daily_qa_now_msec() < deadline:
		if main.ui.modal != "": break
		if main.ui.dlg_choices.visible:
			await frames(5)
			var pick: int = int(choices.pop_front()) if not choices.is_empty() else 0
			await tap(KEY_1 + pick)
		elif main.ui.dlg.visible:
			await frames(14)
			await tap(KEY_E)
		await frames(3)

func shot_action(action: LivingAction, label: String) -> void:
	if "--qa-bakery-sample" in OS.get_cmdline_user_args() and GameState.day >= int(DailyLife.state().introduced_day) + 2 and action.mode == "eat":
		_qa_bakery_sample_captures.append({"label": label, "surface_at": [action.surface_at.x, action.surface_at.y, action.surface_at.z],
			"action_clock": action.clock, "in_room": main.in_room, "room_kind": main.room_kind,
			"player_position": [main.player.global_position.x, main.player.global_position.y, main.player.global_position.z]})
	# The action may finish and free itself while PNG capture awaits a rendered
	# frame. Hold only its presentation clock until that exact state is captured.
	var was_processing: bool = action.is_processing()
	action.set_process(false)
	await shot(label)
	if is_instance_valid(action): action.set_process(was_processing)
	else: failures.append("action disappeared during screenshot " + label)

func shot(label: String) -> void:
	if DAILY_QA_CAPTURE.enabled():
		var activity: String = str(get_script().resource_path).get_file().get_basename()
		var result: Dictionary = await DAILY_QA_CAPTURE.capture(main, folder, label, _daily_qa_focus(label), activity)
		_daily_qa_capture_ms += int(result.hold_ms)
		for saved_path: String in result.shots:
			if not "_diagnostic_angle_" in saved_path.get_file(): shots.append(saved_path)
		for message: String in result.failures: failures.append(message)
		return
	await RenderingServer.frame_post_draw
	var path: String = folder.path_join(label + ".png")
	if get_viewport().get_texture().get_image().save_png(path) == OK: shots.append(path)
	else: failures.append("screenshot failed " + label)


func _daily_qa_focus(label: String) -> Vector3:
	if label == "prop_tea_tray": return main.story.daily.view.tea_root.global_position + Vector3.UP * .08
	if label == "prop_bakery_paper": return main.story.daily.view.paper_root.global_position
	if label == "prop_meal_table": return main.story.daily.view.meal_root.global_position + Vector3.UP * .08
	return Vector3.INF


func _daily_qa_now_msec() -> int:
	# With diagnostics disabled this is the original wall-clock watchdog. Held
	# still images are excluded only from the opt-in native integration run.
	return Time.get_ticks_msec() - _daily_qa_capture_ms

func prop_views() -> void:
	var bench: Node3D = main.world.get_node("P08")
	var actual_tea: Node3D = main.story.daily.view.tea_root
	print("LIVING_TEA_STATE ", JSON.stringify({"position": [actual_tea.global_position.x, actual_tea.global_position.y, actual_tea.global_position.z],
		"visible": actual_tea.visible, "visible_in_tree": actual_tea.is_visible_in_tree(), "morning_blocked": actual_tea.get_meta("morning_blocked", false),
		"original_legal": main.story.morning.legal(main.story.morning.original_tray), "actual_legal": main.story.morning.legal(actual_tea.global_position)}))
	for xx in [15.0, 15.3, 15.6, 15.9, 16.2]:
		for zz in [14.9, 15.2, 15.5]:
			print("TEA_SUPPORT ", xx, " ", zz, " ", DailyLifeView.support_height(bench, Vector3(xx, 0, zz)))
	var camera := Camera3D.new()
	main.add_child(camera)
	var previous: Camera3D = get_viewport().get_camera_3d()
	camera.fov = 45
	camera.make_current()
	camera.global_position = Vector3(12.4, 2.0, 17.6)
	camera.look_at(main.story.daily.view.tea_root.global_position + Vector3.UP * .08)
	await frames(8)
	await shot("prop_tea_tray")
	camera.global_position = Vector3(-20.5, 2.0, -13.5)
	camera.look_at(main.story.daily.view.paper_root.global_position)
	await frames(8)
	await shot("prop_bakery_paper")
	previous.make_current()
	camera.queue_free()
	await main.enter_room()
	camera = Camera3D.new()
	main.add_child(camera)
	camera.fov = 48
	camera.global_position = HouseBuilder.ORIGIN + Vector3(-.4, 2.3, 5.0)
	camera.look_at(main.story.daily.view.meal_root.global_position)
	camera.make_current()
	await frames(8)
	await shot("prop_meal_table")
	main.rig.cam.make_current()
	camera.queue_free()

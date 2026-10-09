extends Node
## Rendered keyboard/mouse verification with isolated HARUMACHI_SAVE_DIR.
## Fixture positioning is explicit; dialogue, choices, stove and eating use actual UI inputs.
var main: Node
var folder := ""
var failures: Array[String] = []
var shots: Array[String] = []
var seen_actions: Array[String] = []

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
	await use_point("life_bakery_card", [0])
	check("paper helped", DailyLife.event("card").get("helped_sign", false))
	await shot("06_bakery_sign_result")
	await prop_views()
	GameState.save_game()
	var facts: Dictionary = DailyLife.state().duplicate(true)
	GameState.flags.clear()
	var loaded: bool = GameState.load_game()
	print("DAILY_RELOAD ", loaded, " ", JSON.stringify(DailyLife.state()), " expected ", JSON.stringify(facts))
	check("SQLite restores all three life events", DailyLife.state().events == facts.events)
	check("meal table cut and tea gesture rendered", seen_actions.has("eat") and seen_actions.has("eat_empty") and seen_actions.has("sip"))
	var file := FileAccess.open(folder.path_join("native-demo.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "passed": failures.is_empty(), "failures": failures, "shots": shots, "input": "E / numeric choices / mouse cook / J / Escape", "scope": "fixture-positioned three-day sample; not human fun evidence", "facts": facts}, "  "))
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
	if id in ["center_door", "workroom_exit"]: dir = Vector3(0, 0, -1)
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
	var deadline := Time.get_ticks_msec() + 35000
	var choices: Array = picks.duplicate()
	var captured := false
	while main.story.busy and Time.get_ticks_msec() < deadline:
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
					check("gesture hand approaches mouth " + action.mode, action.prop.global_position.distance_to(action.pose.goal_world) < .22)
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
	var deadline := Time.get_ticks_msec() + 35000
	while main.story.busy and Time.get_ticks_msec() < deadline:
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
	# The action may finish and free itself while PNG capture awaits a rendered
	# frame. Hold only its presentation clock until that exact state is captured.
	var was_processing: bool = action.is_processing()
	action.set_process(false)
	await shot(label)
	if is_instance_valid(action): action.set_process(was_processing)
	else: failures.append("action disappeared during screenshot " + label)

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = folder.path_join(label + ".png")
	if get_viewport().get_texture().get_image().save_png(path) == OK: shots.append(path)
	else: failures.append("screenshot failed " + label)

func prop_views() -> void:
	var bench: Node3D = main.world.get_node("P08")
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

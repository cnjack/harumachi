extends Node
## Observe the real dance and fireworks routines while their animations run.
## --qa-festival=<directory>; date/prior quests are fixtures, camera is diagnostic.
var main: Node3D
var camera: Camera3D
var output := ""
var rows: Array[Dictionary] = []
var failures: Array[String] = []
var frame_samples: Array[Dictionary] = []

func _ready() -> void:
	main = get_parent()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-festival="): output = argument.trim_prefix("--qa-festival=")
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	for frame: int in 30: await get_tree().process_frame
	GameState.new_game()
	GameState.clock_paused = true
	NPC.roam_enabled = false
	main.ui.instant = false
	main.ui.visible = false
	main.in_room = false
	GameState.player_in_room = false
	main.world.set_indoor_look(false)
	GameState.phase = "prep"
	GameState.quests.Q00 = {"state": "done", "step": 2}
	camera = Camera3D.new()
	camera.fov = 55
	camera.near = .03
	main.add_child(camera)
	main.weather_fx.rig = camera
	for weather: String in ["sunny", "cloudy", "rain"]:
		GameState.weather = weather
		GameState.day = 17
		GameState.minute = 20.1 * 60
		main.world.set_region("town")
		camera.fov = 55
		main.world.sync_festivals()
		main.world.update_time(GameState.minute, weather, true)
		main.player.global_position = Vector3(-2, .05, 11)
		main.update_npcs(true)
		camera.global_position = WorldBuilder.YAGURA_POS + Vector3(5.7, 4.0, 8.2)
		camera.look_at(WorldBuilder.YAGURA_POS + Vector3.UP)
		main.weather_fx.set_weather(weather, false)
		main.bon_odori_scene()
		await get_tree().create_timer(1.1).timeout
		await sample_frames(weather)
		for phase: int in 3:
			for angle: float in [35.0, 155.0, 275.0]:
				var focus: Vector3 = WorldBuilder.YAGURA_POS + Vector3.UP * 1.0
				camera.global_position = focus + Vector3(0, 3.0, 10).rotated(Vector3.UP, deg_to_rad(angle))
				camera.look_at(focus)
				await shot("dance", weather, phase, angle)
			await get_tree().create_timer(.7).timeout
		while main.dancing or main.story.cutscene: await get_tree().process_frame
		main.rig.cam.make_current()
		if GameState.input_locked(): failures.append("dance did not release input")
		GameState.day = 24
		GameState.minute = 19.8 * 60
		main.world.set_region("farm")
		camera.fov = 72
		main.world.sync_festivals()
		main.world.update_time(GameState.minute, weather, true)
		main.player.global_position = FarmBuilder.ORIGIN + Vector3(9.2, .1, 11.4)
		main.update_npcs(true)
		camera.global_position = FarmBuilder.ORIGIN + Vector3(10.0, 2.2, 6.0)
		camera.look_at(FarmBuilder.ORIGIN + Vector3(9.7, 2.7, 11.4))
		main.hanabi_scene("mio")
		await get_tree().create_timer(1.2).timeout
		for phase: int in 3:
			for angle: float in [15.0, 100.0, 250.0]:
				var focus: Vector3 = FarmBuilder.ORIGIN + Vector3(9.7, 1.2, 11.4)
				camera.global_position = focus + Vector3(0, 1.0, -7.5).rotated(Vector3.UP, deg_to_rad(angle))
				camera.look_at(focus + Vector3.UP * 2.8)
				await shot("fireworks", weather, phase, angle)
			await get_tree().create_timer(.8).timeout
		while GameState.input_locked(): await get_tree().process_frame
		main.rig.cam.make_current()
	FileAccess.open(output.path_join("native-demo.json"), FileAccess.WRITE).store_string(JSON.stringify({
		"passed": failures.is_empty(), "failures": failures, "shots": rows, "performance": frame_samples,
		"scope": "real bon_odori_scene and hanabi_scene; prior quests, dates and diagnostic cameras are fixtures"}, "\t"))
	get_tree().quit(0 if failures.is_empty() else 1)

func sample_frames(weather: String) -> void:
	var supports: Dictionary = {}
	var apron_supports: Dictionary = {}
	var actors: Dictionary = {"sora": main.player}
	for id: String in main.npcs: actors[id] = main.npcs[id]
	for id: String in actors:
		var support: Node = actors[id].model.find_child("CharacterFootSupport", true, false)
		if support != null:
			support.call("reset_performance")
			supports[id] = support
		var apron: Node = actors[id].model.find_child("CharacterApronSupport", true, false)
		if apron != null:
			apron.call("reset_performance")
			apron_supports[id] = apron
	var times: Array[float] = []
	await get_tree().process_frame
	var previous: int = Time.get_ticks_usec()
	var start: int = previous
	while Time.get_ticks_usec() - start < 600000:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		times.append(float(now - previous) / 1000.0)
		previous = now
	var elapsed: float = float(previous - start) / 1000000.0
	var foot_times: Dictionary = {}
	for id: String in supports:
		foot_times[id] = supports[id].call("performance")
		if int(foot_times[id].updates) == 0: failures.append(weather + ": " + id + " was absent during the dance performance sample")
	if supports.size() != 7: failures.append("expected seven real dancer skeletons")
	var apron_times: Dictionary = {}
	for id: String in apron_supports:
		apron_times[id] = apron_supports[id].call("performance")
		if int(apron_times[id].updates) == 0: failures.append(weather + ": " + id + " apron was not sampled during the real dance")
	if apron_supports.size() != 1 or not apron_supports.has("kazuko"): failures.append("expected the corrective apron only on Kazuko")
	frame_samples.append({"weather": weather, "seconds": elapsed, "frames": times.size(),
		"fps": float(times.size()) / maxf(elapsed, .001), "longest_frame_ms": times.max(),
		"foot_support": foot_times, "apron_support": apron_times,
		"scope": "seven actors and Kazuko apron in the real dance; no PNG encoding or full shoe/apron probe during sample"})

func shot(activity: String, weather: String, phase: int, angle: float) -> void:
	camera.make_current()
	for frame: int in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var file: String = "%s_%s_phase%d_angle%d.png" % [activity, weather, phase, int(angle)]
	if get_viewport().get_texture().get_image().save_png(output.path_join(file)) != OK: failures.append("save " + file)
	var actors: Dictionary = {"sora": main.player.anim.ap.current_animation}
	var visible_actors: Dictionary = {"sora": main.player.model.is_visible_in_tree()}
	for id: String in main.npcs: actors[id] = main.npcs[id].anim.ap.current_animation
	for id: String in main.npcs: visible_actors[id] = main.npcs[id].model.is_visible_in_tree()
	if activity == "dance":
		for id: String in actors:
			if actors[id] != "dance": failures.append(file + ": " + id + " interrupted dance with " + str(actors[id]))
			if not visible_actors[id]: failures.append(file + ": " + id + " is an invisible dancer")
	rows.append({"file": file, "activity": activity, "weather": weather, "phase": phase,
		"day": GameState.day, "time": GameState.minute, "angle": angle, "clips": actors, "actors_visible": visible_actors,
		"dancing": main.dancing, "input_locked": GameState.input_locked()})
	print("FESTIVAL_SHOT ", file)

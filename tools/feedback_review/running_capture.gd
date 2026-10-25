extends "res://scripts/tools/feedback_qa_base.gd"
## Reuses the native QA camera/floor fixture; Player drives the run without animation seeks.
func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.substr(6)
	DirAccess.make_dir_recursive_absolute(output)
	GameState.new_game()
	GameState.clock_paused = true
	GameState.minute = 630
	NPC.roam_enabled = false
	main = get_parent() as Node3D
	await settle(40)
	support_audit = load("res://scripts/tests/placement_checks.gd").new(self)
	floor_meshes = WorldBuilder.find_meshes(main.world)
	main.set_process(false)
	main.set_physics_process(false)
	main.rig.set_process(false)
	main.player.set_physics_process(false)
	main.ui.visible = false
	main.marker.visible = false
	if main.shop_life: main.shop_life.set_process(false)
	for npc: NPC in main.npcs.values():
		npc.set_process(false)
		npc.tag.visible = false
		npc.set_home(true)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.05
	camera.near = .02
	main.add_child(camera)
	camera.current = true
	main.weather_fx.rig = camera
	outdoors()
	var cases: Array[Dictionary] = []
	for view: String in ["right", "front"]:
		choose("sora", Vector3(-14, .03, -10))
		anim._oneshot = ""
		anim.set_idle("idle", true)
		await settle(8)
		main.player.frozen = false
		main.player.velocity = Vector3.ZERO
		main.player.set_facing(PI * .5)
		main.player.auto_move = Vector3.RIGHT
		main.player.auto_run = true
		main.player.set_physics_process(true)
		for warmup: int in 30:
			look(view)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var start: int = Engine.get_frames_drawn()
		var start_pos: Vector3 = main.player.global_position
		for frame: int in 90:
			look(view)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var distance: float = start_pos.distance_to(main.player.global_position)
		assert(distance > 6.0)
		cases.append({"view": view, "start_frame": start, "frames": 90, "fps": 30, "actual_displacement_m": distance})
	FileAccess.open(output.path_join("clip.json"), FileAccess.WRITE).store_string(JSON.stringify({"cases": cases, "controller": "actual Player auto_move and auto_run; no pose writes"}))
	get_tree().quit(0)

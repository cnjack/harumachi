extends Node
## Declared day/time/location fixtures exercise the real schedule and motion, not natural play time.
var main: Node

func _ready() -> void:
	main = get_parent()
	call_deferred("run")

func run() -> void:
	GameState.clock_paused = true
	NPC.roam_enabled = true
	if "--audit-counterexample" in OS.get_cmdline_user_args():
		var reached: bool = await obstacle_case()
		get_tree().call_group("spatial_audits", "finish")
		get_tree().quit(0 if reached else 1)
		return
	var hours: Array[float] = [6.5, 9.0, 12.0, 13.5, 18.5, 20.5]
	Engine.time_scale = 4.0
	for day: int in [1, 2, 3, 7]:
		GameState.day = day
		GameState.weather = GameState.weather_for(day)
		main.update_npcs(true)
		for hour: float in hours:
			GameState.minute = hour * 60.0
			for actor: NPC in main.npcs.values():
				main.player.global_position = actor.global_position + Vector3(2.5, .05, 2.5)
				if actor.npc_id == "aoi" and day < 2: actor.set_home(true)
				else: actor.apply_schedule(hour, main.player.global_position, false)
			print("WORLD AUDIT fixture day=%d hour=%.1f weather=%s" % [day, hour, GameState.weather])
			await get_tree().create_timer(24.0).timeout
		# The actual market loops use the same NPC movement implementation.
		GameState.phase = "market"
		main.player.global_position = Vector3(-9, .05, 2)
		main._on_phase("market")
		await get_tree().create_timer(36.0).timeout
		GameState.phase = "prep"
		main._on_phase("prep")
	Engine.time_scale = 1.0
	get_tree().call_group("spatial_audits", "finish")
	get_tree().quit()

func obstacle_case() -> bool:
	var obstruction := StaticBody3D.new()
	obstruction.name = "AuditObstacle"
	obstruction.set_meta("audit_category", "fixture")
	obstruction.collision_layer = WorldBuilder.L_PLACED
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(1.0, 1.8, 1.0)
	collider.shape = box; collider.position.y = .9
	obstruction.add_child(collider)
	main.add_child(obstruction)
	obstruction.global_position = Vector3(-3.0, 0, 3.0)
	main.player.global_position = Vector3(-10.0, .05, -4.0)
	var actor: NPC = main.npcs.mio
	actor.set_home(false); actor.place(Vector3(-3.0, 0, 1.0), 0)
	actor.fest_key = "audit:counterexample"; actor.hold = true
	await get_tree().physics_frame
	actor.walk.call_deferred([Vector3(-3.0, 0, 5.0)])
	await get_tree().create_timer(8.0).timeout
	print("WORLD AUDIT counterexample final=" + str(actor.global_position))
	return actor.global_position.distance_to(Vector3(-3.0, 0, 5.0)) < .15

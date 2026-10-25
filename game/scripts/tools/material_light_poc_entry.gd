extends SceneTree
## Isolated opt-in look development. Never loaded by the normal game.

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	if OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():
		printerr("Material/light POC requires HARUMACHI_SAVE_DIR")
		quit(2)
		return
	seed(20261025)
	(root.get_node("Audio") as Node).call("silence")
	root.get_node("GameState").set("clock_paused", true)
	var main: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	var started: int = Time.get_ticks_msec()
	while not bool(main.get("loading_ready")):
		if Time.get_ticks_msec() - started > 120000:
			printerr("POC scene load timeout")
			quit(3)
			return
		await process_frame
	for frame: int in range(8): await process_frame
	(root.get_node("Audio") as Node).call("silence")
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var review: Node = load("res://scripts/tools/material_light_poc.gd").new() as Node
	review.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(review)

func finish_review(code: int = 0) -> void:
	# Release the scene while rendering and resource services are still alive.
	(root.get_node("Audio") as Node).call("silence")
	var scene: Node = current_scene
	if is_instance_valid(scene):
		for child: Node in scene.get_children():
			if child.has_method("release_candidates"): await child.call("release_candidates")
	current_scene = null
	if is_instance_valid(scene): scene.queue_free()
	await process_frame
	await process_frame
	quit(code)

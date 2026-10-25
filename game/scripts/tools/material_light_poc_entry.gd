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
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var review: Node = load("res://scripts/tools/material_light_poc.gd").new() as Node
	review.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(review)

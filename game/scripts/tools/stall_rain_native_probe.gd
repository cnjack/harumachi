extends SceneTree
## Fixed GPU comparison of the real canopy and production rain shader.
func _initialize() -> void:
	_start.call_deferred()
func _start() -> void:
	if OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():quit(2);return
	var output: String=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):output=arg.substr(6)
	if output.is_empty():quit(2);return
	var main: Node=(load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main);current_scene=main
	var warm:=0
	while not bool(main.get("loading_ready")) and warm<1200:
		await process_frame;warm+=1
	if not bool(main.get("loading_ready")):quit(3);return
	(main.get("ui") as Node).call("set_hud_visible",false)
	((main.get("ui") as Node).get("panels") as RefCounted).call("set_cards_visible",false)
	(main.get("rig") as Node).process_mode=Node.PROCESS_MODE_DISABLED
	var state: Node=root.get_node("GameState");state.set("clock_paused",true)
	main.process_mode=Node.PROCESS_MODE_DISABLED
	await load("res://scripts/tools/stall_rain_visual_probe.gd").new().capture(main,output)
	quit(0)

extends Node
## Real title/loading/new-game path, with automatic reading; not natural play time.
var main: Node
var output := ""
func _ready() -> void:
	main = get_parent()
	main.ui.auto = true
	if DisplayServer.get_name() == "headless": main.ui.instant = true
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--arrival-report="): output = argument.trim_prefix("--arrival-report=")
	call_deferred("run")
func run() -> void:
	var deadline: int = Time.get_ticks_msec() + 45000
	while (GameState.flags.get("arrival_home", {}).get("phase", "") != "done" or GameState.input_locked() or main.player.frozen) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var before: float = GameState.minute
	await get_tree().create_timer(2.0).timeout
	var passed: bool = GameState.day == 2 and main.in_room and not GameState.input_locked() and not main.player.frozen and not GameState.clock_paused and GameState.minute > before and GameState.qstate("Q00") == "done" and not DailyLife.done("meal")
	if output != "":
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		if DisplayServer.get_name() != "headless":
			await get_tree().process_frame
			main.get_viewport().get_texture().get_image().save_png(output.get_basename()+".png")
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify({"passed":passed,"day":GameState.day,"minute_before":before,"minute_after":GameState.minute,"clock_paused":GameState.clock_paused,"at_home":main.in_room,"q00":GameState.qstate("Q00"),"arrival":GameState.flags.get("arrival_home",{}),"scope":"Title direct newgame and real Loading path; automatic dialogue reading and authored arrival cuts. No natural-time or human-fun claim."},"  "))
	get_tree().call_group("spatial_audits", "finish")
	get_tree().quit(0 if passed else 1)

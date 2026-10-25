extends SceneTree
var out := ""
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var mg: Control = load("res://scripts/minigames/mg_goldfish.gd").new()
	mg.set("id", "goldfish")
	mg.set("auto", true)
	layer.add_child(mg)
	mg.get("rng").seed = 261025
	mg.call("_start_round")
	while not mg.call("playing"): await process_frame
	for _i: int in 30: await process_frame
	await RenderingServer.frame_post_draw
	var start: int = Engine.get_frames_drawn()
	for i: int in 366:
		await process_frame
		await RenderingServer.frame_post_draw
		if i in [2, 182, 362]: root.get_texture().get_image().save_png(out.path_join("fish_%03d.png" % i))
	assert(Engine.get_frames_drawn() - start >= 366)
	FileAccess.open(out.path_join("clip.json"), FileAccess.WRITE).store_string(JSON.stringify({"start_frame": start + 3, "frames": 360, "fps": 30, "score": mg.get("score"), "caught": mg.get("caught"), "native_frames": Engine.get_frames_drawn() - start}))
	quit(0)

extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output: String = ""
	var video_frames: int = 0
	var movie_seconds: float = 0.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output=argument.substr(6)
		if argument.begins_with("--frames="): video_frames=int(argument.substr(9))
		if argument.begins_with("--seconds="): movie_seconds=float(argument.substr(10))
	DirAccess.make_dir_recursive_absolute(output)
	var title_scene: PackedScene = load("res://scenes/title.tscn") as PackedScene
	var title: Control = title_scene.instantiate() as Control
	root.add_child(title)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("title.png"))
	if video_frames>0:
		DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
		for frame: int in range(video_frames):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("frames/%04d.png"%frame))
	if movie_seconds>0:
		for frame: int in range(roundi(movie_seconds*30)):
			await RenderingServer.frame_post_draw
			if frame==roundi(movie_seconds*30*.8):root.get_texture().get_image().save_png(output.path_join("title-return.png"))
	var cat: Node = title.get_node_or_null("MenuCat")
	var report: Dictionary = {"cat_present":cat!=null,"engine":Engine.get_version_info(),"menu_buttons":[],"drawn_frames":Engine.get_frames_drawn()}
	for child: Node in title.menu.get_children():
		if child is Button: (report.menu_buttons as Array).append((child as Button).text)
	FileAccess.open(output.path_join("state.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	if cat!=null: FileAccess.open(output.path_join("cat-telemetry.json"),FileAccess.WRITE).store_string(JSON.stringify(cat.telemetry(),"\t"))
	title.queue_free()
	await process_frame
	quit()

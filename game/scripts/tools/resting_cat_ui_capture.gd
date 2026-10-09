extends SceneTree
## Actual backpack, calendar and settings panels, with isolated game storage.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output: String=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var state_node: Node=root.get_node("GameState")
	state_node.new_game()
	state_node.clock_paused=true
	var main: Node3D=(load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	for frame: int in range(35):await process_frame
	var results: Array[Dictionary]=[]
	for panel_name: String in ["inventory","calendar","settings"]:
		match panel_name:
			"inventory":main.ui.open_inventory()
			"calendar":main.ui.panels.open_calendar()
			"settings":main.ui.open_settings()
		for frame: int in range(20):await process_frame
		var cat: Control=main.ui.modal_layer.find_child("RestingCat",true,false) as Control
		assert(cat!=null,"Requested panel has no resting cat")
		var body: Sprite2D=cat.get_node("RestBody") as Sprite2D
		var tail: AnimatedSprite2D=cat.get_node("DanglingTail") as AnimatedSprite2D
		var body_position: Vector2=body.position
		var body_texture: Texture2D=body.texture
		var tail_frame: int=tail.frame
		var tail_changed: bool=false
		var body_fixed: bool=true
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(panel_name+"-0.png"))
		for sample: int in range(35):
			await process_frame
			tail_changed=tail_changed or tail.frame!=tail_frame
			body_fixed=body_fixed and body.texture==body_texture and body.position.distance_to(body_position)<.01
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(panel_name+"-1.png"))
		results.append({"panel":panel_name,"passed":body_fixed and tail_changed and cat.mouse_filter==Control.MOUSE_FILTER_IGNORE and cat.focus_mode==Control.FOCUS_NONE,"body_fixed":body_fixed,"tail_frame_changed":tail_changed,"tail":cat.telemetry()})
		main.ui.close_modal()
		for frame: int in range(3):await process_frame
	var passed: bool=true
	for result: Dictionary in results:passed=passed and bool(result.passed)
	FileAccess.open(output.path_join("panels.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"results":results},"\t"))
	main.queue_free()
	await process_frame
	quit(0 if passed else 1)

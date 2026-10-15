extends RefCounted
## Used only in a temporary clone by the promotional recording tool.
func record(main: Node, directory: String, view_name: String, _configuration: Dictionary) -> void:
	var action: bool=view_name in ["promo_harvest","promo_water"]
	var plot_id: String="farm0" if view_name=="promo_harvest" else "farm1"
	var previous_count: int=GameState.count("tomato")
	if action:
		main.player.visible=true
		GameState.can_water=GameState.can_cap()
		if plot_id=="farm1":
			GameState.plots.farm1.days=1;GameState.plots.farm1.water=false
			GameState.plots_changed.emit()
		main.player.global_position=FarmBuilder.ORIGIN+Vector3(-3.45 if plot_id=="farm0" else -1.15,.05,-1.85)
		main.player.set_facing(PI)
		main.player.reset_physics_interpolation();main.rig.snap()
		for settle in 20:await main.get_tree().process_frame
	var started: int=Engine.get_frames_drawn()
	var camera: Camera3D=main.rig.cam
	var original: Vector3=camera.global_position
	var basis_x: Vector3=camera.global_basis.x
	var moving_camera: bool=main.rig.process_mode==Node.PROCESS_MODE_DISABLED
	var show_play: bool=view_name in ["town_store","farm_field"] or action
	main.ui.set_hud_visible(show_play)
	main.ui.panels.set_cards_visible(false)
	print("PROMO_START ",view_name," frame=",started," screen=",DisplayServer.window_get_current_screen()," position=",DisplayServer.window_get_position()," no_focus=",get_project_setting("display/window/size/no_focus"))
	var length: int=240
	for frame: int in range(length):
		if action and frame in [45,46]:
			main.player._update_target()
			var input_event:=InputEventKey.new()
			input_event.keycode=KEY_E;input_event.physical_keycode=KEY_E;input_event.pressed=frame==45
			Input.parse_input_event(input_event);Input.flush_buffered_events()
		if moving_camera:
			camera.global_position=original+basis_x*(float(frame)/float(length)-.5)*.45
		if view_name=="town_store":
			main.player.auto_move=Vector3(.65,0,0) if frame<150 else Vector3.ZERO
			main.player.auto_run=false
		await main.get_tree().process_frame
		if frame==120:
			await RenderingServer.frame_post_draw
			main.get_viewport().get_texture().get_image().save_png(directory.path_join(view_name+"_mid.png"))
	if action:
		var passed: bool=GameState.count("tomato")>previous_count if plot_id=="farm0" else bool(GameState.plots.farm1.water)
		print("PROMO_ACTION ",view_name," passed=",passed)
		if not passed:push_error("Promotional farming interaction did not complete")
	main.player.auto_move=Vector3.ZERO
	camera.global_position=original
	print("PROMO_END ",view_name," frame=",Engine.get_frames_drawn())

func get_project_setting(key: String) -> Variant:
	return ProjectSettings.get_setting(key)

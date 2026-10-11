extends SceneTree
## Short before/after native frame samples; PNG encoding is outside all timing windows.
func _initialize() -> void:_start.call_deferred()
func _start() -> void:
	if OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():quit(2);return
	var output: String=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):output=arg.substr(6)
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	var main: Node=(load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main);current_scene=main
	var warm:=0
	while not bool(main.get("loading_ready")) and warm<1200:
		await process_frame;warm+=1
	if not bool(main.get("loading_ready")):quit(3);return
	var state: Node=root.get_node("GameState");state.set("clock_paused",true)
	(main.get("ui") as Node).call("set_hud_visible",false)
	((main.get("ui") as Node).get("panels") as RefCounted).call("set_cards_visible",false)
	var rig: Node=main.get("rig") as Node;rig.process_mode=Node.PROCESS_MODE_DISABLED
	var camera: Camera3D=rig.get("cam") as Camera3D
	camera.near=.05;camera.fov=42.0
	var world: Node3D=main.get("world") as Node3D
	var player: Node3D=main.get("player") as Node3D
	player.set_physics_process(false)
	var views: Dictionary=load("res://scripts/tools/environment_visual_qa.gd").get_views()
	var rows: Array[Dictionary]=[]
	for view_id: String in ["qa_street_east_lane","qa_plaza_reverse","qa_river_bend_bank_low","qa_bakery_reverse"]:
		var view: Dictionary=views[view_id]
		for condition: String in ["noon","rain","night"]:
			var minute: float=1260.0 if condition=="night" else 720.0
			var weather: String="rain" if condition=="rain" else "sunny"
			state.set("minute",minute);state.set("weather",weather)
			if bool(main.get("in_room")):
				main.set("in_room",false);main.set("room_kind","");state.set("player_in_room",false);world.call("set_indoor_look",false)
			world.call("set_region","farm" if bool(view.get("farm",false)) else "town")
			var origin: Vector3=Vector3.ZERO
			if view.has("interior"):
				await main.call("enter_interior",str(view.interior))
				origin=((load("res://scripts/world/interior_builder.gd") as GDScript).call("spec_for",str(view.interior)) as Dictionary).origin
				player.global_position=origin+view.at
				camera.global_position=origin+view.inside_camera
				camera.look_at(origin+view.inside_focus)
			else:
				if bool(view.get("farm",false)):origin=(world.get("farm") as Node3D).global_position
				player.global_position=origin+view.player
				camera.global_position=origin+view.camera_at
				camera.look_at(origin+view.camera_focus)
			world.call("update_time",minute,weather,true);main.call("_sync_weather");main.call("update_npcs",true)
			for settle: int in 45:await process_frame
			var intervals: Array[float]=[]
			var last: int=Time.get_ticks_usec()
			for sample: int in 150:
				await process_frame
				var now: int=Time.get_ticks_usec();intervals.append(float(now-last)/1000.0);last=now
			var total:=0.0
			for interval: float in intervals:total+=interval
			intervals.sort()
			rows.append({"view":view_id,"condition":condition,"frames":intervals.size(),"fps":150000.0/total,"median_ms":intervals[75],"p95_ms":intervals[142],"longest_ms":intervals[-1],"png_encoding_excluded":true})
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png(output.path_join(view_id+"__"+condition+".png"))
	var file:=FileAccess.open(output.path_join("performance.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"samples":rows,"scope":"150 normal native frames per scene/weather, short local comparison; screenshot encoding excluded"},"\t"));file.close()
	quit(0)

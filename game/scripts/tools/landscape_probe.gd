extends Node
## Native moving-camera sample; does not save a game or alter player data.
func _ready() -> void:
	GameState.new_game();GameState.clock_paused=true;NPC.roam_enabled=false
	var main: Node=load("res://scenes/main.tscn").instantiate();add_child(main)
	for frame in 30:await get_tree().process_frame
	var records: Array=[]
	for farm: bool in [false,true]:
		main.world.set_region("farm" if farm else "town")
		main.world.set_indoor_look(false)
		var origin: Vector3=FarmBuilder.ORIGIN if farm else Vector3.ZERO
		main.player.global_position=origin+(Vector3(139,0.2,18) if farm else Vector3(20,0.2,27))
		main.rig.dist=8;main.rig.pitch=18;main.rig.yaw=0;main.rig.snap()
		for frame in 90:await get_tree().process_frame
		var intervals: Array[float]=[]
		var started: int=Time.get_ticks_usec()
		var previous: int=started
		var primitives:=0;var draw_calls:=0
		for frame in 360:
			main.rig.yaw+=1.0
			await get_tree().process_frame
			var now: int=Time.get_ticks_usec();intervals.append(float(now-previous)/1000.0);previous=now
			primitives=maxi(primitives,get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
			draw_calls=maxi(draw_calls,get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		intervals.sort()
		records.append({"region":"farm" if farm else "town","frames":intervals.size(),"fps":360.0/(float(previous-started)/1000000.0),"median_ms":intervals[180],"p95_ms":intervals[342],"max_ms":intervals.back(),"max_primitives":primitives,"max_draw_calls":draw_calls})
	var out: String="/tmp/landscape-performance.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):out=argument.trim_prefix("--out=")
	var file:=FileAccess.open(out,FileAccess.WRITE);file.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"samples":records},"  "));file.close()
	get_tree().quit()

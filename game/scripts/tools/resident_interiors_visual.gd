extends SceneTree
## Native diagnostic gallery, not proof of the invitation/story path. Requires isolated saves.
var main: Node3D
var camera: Camera3D
var state: Node
var places
var visits
var interior_api
var builder
var output := ""
var room_filter: Array[String]=[]
var skip_outside:=false
var rows: Array[Dictionary]=[]
var entry_results: Array[Dictionary]=[]
func _initialize() -> void:_start.call_deferred()
func _start() -> void:
	if OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():quit(2);return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):output=arg.substr(6)
		elif arg.begins_with("--rooms="):room_filter.assign(arg.substr(8).split(","))
		elif arg=="--skip-outside":skip_outside=true
	if output.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	state=root.get_node("GameState");state.call("new_game");state.set("clock_paused",true)
	# SceneTree entry scripts compile before autoload identifiers are registered.
	# Load project classes only now, after the autoload bootstrap has completed.
	places=load("res://scripts/world/resident_places.gd")
	visits=load("res://scripts/story/resident_visits.gd")
	interior_api=load("res://scripts/world/interior_builder.gd")
	builder=load("res://scripts/world/resident_interior_builder.gd")
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);current_scene=main
	var warm:=0
	while not bool(main.get("loading_ready")) and warm<1800:
		await process_frame;warm+=1
	if not bool(main.get("loading_ready")):quit(3);return
	main.ui.instant=true
	var p: Dictionary=visits.state()
	p.blueprint_seen=true;p.measured=true;p.photo_compared=true
	for key: String in ["tool_repaired","tanaka_supper","packing_chosen","tags_sorted","flower_delivered","cushion_fixed","letter_sent","map_traced"]:p.followups[key]={"day":0}
	p.choices.packing_chosen="paper";p.choices.flower_pick="blue"
	# A new scene photo must come from the actual trial; no replacement is fabricated here.
	p.photo_rendered=false
	main.ui.root.visible=false;main.marker.visible=false
	camera=Camera3D.new();camera.name="ResidentGalleryCamera";camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.near=.05;camera.far=210;main.add_child(camera)
	for id: String in places.SPECS:
		if not room_filter.is_empty() and id not in room_filter:continue
		var spec: Dictionary=places.SPECS[id]
		visits.invite(id,"原生画面诊断专用")
		state.minute=int(maxf(11.0,float(spec.open)+.35)*60)
		state.weather="sunny"
		await main.enter_interior(id)
		main.player.global_position=interior_api.door_point(id)
		main.player.velocity=Vector3.ZERO;main.player.reset_physics_interpolation()
		main.rig.process_mode=Node.PROCESS_MODE_DISABLED
		main.world.update_time(state.minute,"sunny",true)
		main.story.visits.view.sync_state()
		camera.make_current()
		var origin: Vector3=spec.origin
		await capture(id+"_whole",id,"sunny",whole_at(spec),origin+Vector3(0,.70,0),44.0)
		var key: String=builder._state_keys(id)[0]
		var detail: Vector3=origin+builder._state_at(id,key)
		await capture(id+"_story",id,"sunny",detail+Vector3(2.15,1.65,2.45),detail,42.0)
		var before: Vector3=main.player.global_position
		await main.exit_interior()
		entry_results.append({"room":id,"entered":interior_api.at(before)==id,"exit_room":main.room_kind,"exit":[main.player.global_position.x,main.player.global_position.y,main.player.global_position.z],"expected_return_room":spec.return_room})
	for sample: Array in [["home_haru","rain",11.0],["toolshed","sunny",18.7],["photo_room","sunny",20.3]]:
		var id: String=sample[0];var spec: Dictionary=places.SPECS[id]
		if not room_filter.is_empty() and id not in room_filter:continue
		state.minute=int(float(sample[2])*60);state.weather=str(sample[1])
		await main.enter_interior(id);main.world.update_time(state.minute,state.weather,true)
		camera.make_current()
		await capture(id+("_rain" if sample[1]=="rain" else "_night"),id,state.weather,whole_at(spec),spec.origin+Vector3(0,.70,0),44.0)
		await main.exit_interior()
	if main.in_room:await main.exit_interior()
	state.minute=720;state.weather="sunny"
	main.world.set_region("town");main.world.set_indoor_look(false);main.world.update_time(720,"sunny",true)
	main.player.visible=false
	for id: String in ["home_haru","home_mio"]:
		if skip_outside:continue
		var door: Vector3=places.SPECS[id].outside_point
		await capture(id+"_outside_door",id,"sunny",door+Vector3(-3.0,.65,1.3),door+Vector3(0,.20,0),48.0)
	FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify({"kind":"native_resident_room_diagnostic","screenshots":rows,"entry_exit":entry_results,"real_new_photo":"Requires the separate actual-trial demo; not fabricated here"},"\t"))
	root.get_node("Audio").call("silence");quit(0)
func capture(label: String,id: String,weather: String,at: Vector3,target: Vector3,fov: float) -> void:
	camera.global_position=at;camera.look_at(target,Vector3.UP);camera.fov=fov;camera.reset_physics_interpolation()
	for settle: int in 12:await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image=root.get_texture().get_image()
	var file: String=label+".png";var result: Error=pixels.save_png(output.path_join(file))
	rows.append({"file":file,"room":id,"weather":weather,"minute":state.minute,"camera":[at.x,at.y,at.z],"look_at":[target.x,target.y,target.z],"fov":fov,"png_error":result})
	print("RESIDENT_SHOT ",file," result=",result)

func whole_at(spec: Dictionary) -> Vector3:
	# Solve framing against real room corners, including the full north/side walls.
	var slope: float=deg_to_rad(55.0);var outward:=Vector3(0,sin(slope),cos(slope));var up:=Vector3(0,cos(slope),-sin(slope))
	var half_v: float=tan(deg_to_rad(22.0));var half_h: float=half_v*(1280.0/720.0);var distance:=0.0
	for x: float in [-spec.size.x*.5,spec.size.x*.5]:
		for y: float in [0.0,2.55]:
			for z: float in [-spec.size.y*.5,spec.size.y*.5]:
				var corner:=Vector3(x,y-.70,z)
				distance=maxf(distance,corner.dot(outward)+maxf(absf(corner.dot(up))/half_v,absf(x)/half_h))
	return spec.origin+Vector3(0,.70,0)+outward*(distance+.25)

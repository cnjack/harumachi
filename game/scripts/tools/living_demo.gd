extends Node
## Native keyboard evidence: arrival, physical residential walk, photo, fishing and bedtime.
var main: Node
var folder:=""
var failures: Array[String]=[]
var catches: Array[Dictionary]=[]
var photos: Array[String]=[]
var started:=0

func _ready() -> void:
	main=get_parent();started=Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):folder=argument.substr(11)
	if folder=="":folder="/tmp/harumachi-living-demo"
	DirAccess.make_dir_recursive_absolute(folder)
	await frames(35)
	GameState.new_game();GameState.clock_paused=true;Audio.game_on=true
	main.player.global_position=Layout.SPAWN;main.player.set_facing(PI*.5)
	main.world.bus.arrival(main)
	await get_tree().create_timer(1.7).timeout;await shot("00_bus_approach")
	await get_tree().create_timer(1.6).timeout;await shot("01_bus_step_off")
	var arrival_deadline:=Time.get_ticks_msec()+8000
	while GameState.input_locked() and Time.get_ticks_msec()<arrival_deadline:await get_tree().process_frame
	if GameState.input_locked() or not GameState.flags.get("bus_arrival_seen",false):failures.append("arrival did not restore player input")
	main.player.global_position=Vector3(19.7,.08,29);main.rig.yaw=180;main.rig.pitch=22;main.rig.dist=7;main.rig.snap()
	main.player.auto_move=Vector3(0,0,1);main.player.auto_run=true
	var walking:=Time.get_ticks_msec()+21000
	while main.player.global_position.z<80 and Time.get_ticks_msec()<walking:await get_tree().physics_frame
	main.player.auto_move=Vector3.ZERO;main.player.auto_run=false
	if main.player.global_position.z<79:failures.append("residential walk blocked at "+str(main.player.global_position))
	var walked_to: Vector3=main.player.global_position
	await shot("02_residential_walk")
	await animal_views()
	GameState.minute=17.3*60;main.world.update_time(GameState.minute,"sunny",true)
	await tap(KEY_F8);await frames(8)
	if not main.photo.active:failures.append("F8 did not enter photo mode")
	else:
		main.photo.camera.global_position=Vector3(19.7,2.7,68);main.photo.camera.look_at(Vector3(20,2.3,38));main.photo.camera.fov=53
		(main.photo.tools.find_child("PhotoActors",true,false) as Button).button_pressed=false
		await frames(8);await shot("03_photo_controls")
		await tap(KEY_F12);await frames(12)
		var path: String=main.photo.last_path;photos.append(path)
		var pixels:=Image.load_from_file(path) if FileAccess.file_exists(path) else null
		if pixels==null or pixels.get_width()!=3840 or pixels.get_height()!=2160:failures.append("F12 did not save a full-resolution PNG")
		elif pixels.save_png(folder.path_join("04_wallpaper_residential.png"))!=OK:failures.append("photo copy failed")
		await tap(KEY_ESCAPE);await frames(5)
		if main.photo.active or GameState.input_locked():failures.append("photo exit kept input locked")
	GameState.minute=18*60;GameState.borrow_fishing_kit();GameState.add_item("fishing_bait",6,true)
	main.world.set_region("farm");GameState.player_region="farm"
	for spot_id: String in LakesideLayout.SPOTS:
		var spot: Dictionary=LakesideLayout.SPOTS[spot_id];var at: Vector2=spot.stand
		main.player.global_position=FarmBuilder.ORIGIN+Vector3(at.x,.12 if spot_id=="fish_pier" else LakesideLayout.height_at(at)+.1,at.y)
		main.player.velocity=Vector3.ZERO;main.rig.yaw=180;main.rig.pitch=24;main.rig.dist=6.5;main.rig.snap()
		await frames(10)
		var point: Interactable=null
		for candidate: Interactable in get_tree().get_nodes_in_group("interactables"):
			if candidate.id==spot_id:point=candidate;break
		if point==null:failures.append("missing fishing point "+spot_id);continue
		main.player.face_towards(point.global_position);main.player.target=point
		await tap(KEY_E);await frames(8)
		if main.ui.modal!="fishing":failures.append("E did not open "+spot_id);continue
		var panel: FishingPanel=main.ui.fishing_panel
		await tap(KEY_E);await get_tree().create_timer(.22).timeout;await shot("cast_"+spot_id)
		var deadline:=Time.get_ticks_msec()+15000
		while panel.session.state not in [FishingSession.State.BITE,FishingSession.State.MISSED] and Time.get_ticks_msec()<deadline:await frames(1)
		if panel.session.state!=FishingSession.State.BITE:failures.append("no bite "+spot_id)
		else:
			await tap(KEY_E);var held:=false;var seen:=false;deadline=Time.get_ticks_msec()+42000
			while panel.session.state==FishingSession.State.REEL and Time.get_ticks_msec()<deadline:
				var next:=panel.session.suggested_hold()
				if next!=held:key(KEY_E,next);held=next
				if panel.session.reel_progress>.45 and not seen:seen=true;await shot("reel_"+spot_id)
				await frames(1)
			key(KEY_E,false)
			if panel.session.state!=FishingSession.State.LANDED:failures.append("catch failed "+spot_id+": "+panel.session.message)
			else:
				catches.append(panel.session.result.duplicate());await get_tree().create_timer(.25).timeout;await shot("landed_"+spot_id)
		await tap(KEY_ESCAPE);await frames(10)
	var original_lens: Transform3D=main.rig.cam.transform
	main.rig.cam.top_level=true
	main.player.global_position=FarmBuilder.ORIGIN+Vector3(115,.1,48)
	main.rig.cam.global_position=FarmBuilder.ORIGIN+Vector3(126,4.5,52);main.rig.cam.look_at(FarmBuilder.ORIGIN+Vector3(100,0,17))
	GameState.minute=18.5*60;main.world.update_time(GameState.minute,"sunny",true);await frames(10)
	await tap(KEY_F8);await frames(5)
	if main.photo.active:
		await tap(KEY_F12);await frames(12);photos.append(main.photo.last_path)
		if FileAccess.file_exists(main.photo.last_path):Image.load_from_file(main.photo.last_path).save_png(folder.path_join("05_wallpaper_lake.png"))
		await tap(KEY_ESCAPE)
	main.rig.cam.top_level=false;main.rig.cam.transform=original_lens
	for caught: Dictionary in catches:GameState.sell_produce(str(caught.fish),1,1.0)
	GameState.plots["farm0"].merge({"open":true,"tilled":true,"crop":"radish","days":9,"water":true,"fert":false,"boost":false},true)
	GameState.harvest("farm0")
	main.world.set_region("town");GameState.player_region="town"
	main._put_in_room(HouseBuilder.ORIGIN+Vector3(-5,.05,-.5));main.player.velocity=Vector3.ZERO
	main.rig.pitch=38;main.rig.dist=7;main.rig.snap()
	var expected_day:=GameState.day;var expected_income:=int(GameState.ledger.get("in",0))
	main.ui.instant=false;main.ui.auto=false
	var bed: Interactable=null
	for candidate: Interactable in get_tree().get_nodes_in_group("interactables"):
		if candidate.id=="room_bed":bed=candidate;break
	main.player.target=bed;await tap(KEY_E)
	await get_tree().create_timer(.7).timeout;await tap(KEY_E);await frames(10)
	if not main.ui.dlg_choices.visible:await tap(KEY_E);await frames(8)
	await shot("06_sleep_choice")
	var first:=main.ui.dlg_choices.get_child(0) as Button if main.ui.dlg_choices.get_child_count()>0 else null
	if first!=null:await tap(KEY_1)
	else:failures.append("bed did not offer sleep choice")
	var summary_deadline:=Time.get_ticks_msec()+5000
	while main.get_node_or_null("DaySummary")==null and Time.get_ticks_msec()<summary_deadline:await frames(1)
	if main.get_node_or_null("DaySummary")==null:failures.append("bed did not open daily summary")
	await get_tree().create_timer(.8).timeout;await shot("07_daily_summary")
	await tap(KEY_ENTER);await get_tree().create_timer(2).timeout
	if GameState.day!=expected_day+1 or int(GameState.flags.get("last_day_summary",{}).get("income",-1))!=expected_income:failures.append("bedtime report or morning advance failed")
	await shot("08_next_morning")
	if not GameState.load_game() or GameState.day!=expected_day+1:failures.append("next morning was not persisted")
	var report:= {"passed":failures.is_empty(),"failures":failures,"catches":catches,"photos":photos,"day":GameState.day,"last_summary":GameState.flags.get("last_day_summary",{}),"walk_end":walked_to,"seconds":(Time.get_ticks_msec()-started)/1000.0}
	var file:=FileAccess.open(folder.path_join("verification.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("LIVING_DEMO ",JSON.stringify(report));Audio.silence();await frames(4);get_tree().quit(0 if failures.is_empty() else 1)

func key(code: Key,down: bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=down;Input.parse_input_event(event);Input.flush_buffered_events()
func tap(code: Key) -> void:
	key(code,true);await frames(2);key(code,false);await frames(2)
func frames(count: int) -> void:
	for i in count:await get_tree().process_frame
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(label+".png"));print("LIVING_SHOT ",label)

func animal_views() -> void:
	var local_lens: Transform3D=main.rig.cam.transform
	var original_fov: float=main.rig.cam.fov
	var old_pin_mode: bool=main.photo_mode;main.photo_mode=true
	main.rig.cam.top_level=true;main.ui.hud.visible=false;main.marker.visible=false
	var flock: Dictionary=main.life.flocks[0];flock.state="ground";flock.timer=0.0
	for member: Dictionary in flock.birds:
		(member.node as Node3D).position=flock.home+member.off
		member.hop=0.0
	var bird: Node3D=flock.birds[0].node
	main.player.global_position=flock.home+Vector3(5,.05,0);await frames(6)
	main.rig.cam.global_position=bird.global_position+Vector3(-.35,.28,.65);main.rig.cam.look_at(bird.global_position+Vector3(0,.07,0))
	await shot("animal_bird_ground")
	main.player.global_position=flock.home+Vector3(2,.05,0)
	for index in 12:
		await frames(2)
		main.rig.cam.global_position=bird.global_position+Vector3(-.35,.28,.65);main.rig.cam.look_at(bird.global_position+Vector3(0,.07,0))
		await shot("animal_bird_flight_%02d"%index)
	if not (flock.birds[0].anim.wings[0] as Node3D).visible:failures.append("bird takeoff did not articulate its wings")
	var cat: Node3D=main.life.cats[1].node
	main.player.global_position=cat.global_position+Vector3(9,-1,0);await frames(15)
	main.rig.cam.global_position=cat.global_position+Vector3(-1.8,.35,1.5);main.rig.cam.look_at(cat.global_position+Vector3(0,.18,0));main.rig.cam.fov=35
	await shot("animal_cat_rest")
	main.player.global_position=cat.global_position+Vector3(2,-1,2);await get_tree().create_timer(.6).timeout
	await shot("animal_cat_look")
	main.rig.cam.top_level=false;main.rig.cam.transform=local_lens;main.rig.cam.fov=original_fov;main.rig.snap();main.ui.hud.visible=true;main.photo_mode=old_pin_mode

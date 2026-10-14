extends Node
## Explicit position fixtures; real E/Esc input exercises interaction and recovery.
var main: Node
var folder := "/tmp/harumachi-seating-demo"
var camera: Camera3D
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var shots: Array[String] = []
var transition_samples: Array[Dictionary] = []
var started := 0

func _ready() -> void:
	main=get_parent();started=Time.get_ticks_msec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seating-demo-out="):folder=arg.trim_prefix("--seating-demo-out=")
	DirAccess.make_dir_recursive_absolute(folder)
	_run.call_deferred()

func frames(count: int) -> void:
	for index: int in count:await get_tree().process_frame

func check(label: String, ok: bool) -> void:
	checks.append({"name":label,"ok":ok});print(("PASS " if ok else "FAIL ")+label)
	if not ok:failures.append(label)

func tap(code: Key) -> void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.pressed=true
	Input.parse_input_event(event);Input.flush_buffered_events();await frames(1)
	event=InputEventKey.new();event.physical_keycode=code;event.keycode=code
	Input.parse_input_event(event);Input.flush_buffered_events();await frames(1)

func shot(label: String) -> void:
	var visible: bool=main.ui.visible;main.ui.visible=false
	await RenderingServer.frame_post_draw
	var path: String=folder.path_join(label+".png")
	check("render "+label,get_viewport().get_texture().get_image().save_png(path)==OK)
	shots.append(path);main.ui.visible=visible

func idle_story() -> void:
	var deadline: int=Time.get_ticks_msec()+10000
	while main.story.busy and Time.get_ticks_msec()<deadline:await frames(1)
	check("interaction finishes",not main.story.busy)

func frame_seat(point: Interactable, side: bool=false) -> void:
	var at: Vector3=point.get_parent().to_global(point.get_meta("seat_position"))
	var yaw: float=deg_to_rad(float(point.get_meta("seat_yaw")))
	var front:=Vector3(sin(yaw),0,cos(yaw));var right:=Vector3(front.z,0,-front.x)
	camera.global_position=at+front*(1.7 if side else 3.6)+right*(3.0 if side else .65)+Vector3.UP*1.7
	camera.look_at(at+Vector3.UP*.75);camera.make_current()

func use_seat(point: Interactable, label: String) -> void:
	main.story.public_life.stand(true)
	var region: String=str(point.get_meta("rest_region","town"))
	if main.world.region!=region:
		if region=="farm":await main.go_farm()
		else:await main.leave_farm()
	GameState.player_region=region;main.in_room=false;GameState.player_in_room=false
	main.world.set_indoor_look(false);main._sync_weather()
	main.player.global_position=point.get_parent().to_global(point.get_meta("stand_position"))+Vector3.UP*.01
	main.player.velocity=Vector3.ZERO;main.player.frozen=false;main.player.face_towards(point.global_position+Vector3.RIGHT*.01)
	main.player.reset_physics_interpolation();frame_seat(point)
	await frames(20);main.player._update_target()
	check(label+" actual target",main.player.target==point)
	main.ui.auto_choices=[2] if point.id=="farm_bench" else []
	await tap(KEY_E)
	await get_tree().create_timer(.09).timeout
	var amount: float=main.story.public_life.pose.blend if main.story.public_life.pose!=null else -1.0
	transition_samples.append({"seat":point.id,"blend":amount})
	check(label+" captures a real partial sitting pose",amount>0.0 and amount<1.0)
	await shot(label+"_transition")
	await idle_story();await frames(8)
	check(label+" seated through E",main.player.seated and main.story.public_life.current_seat==point)
	frame_seat(point);await frames(3);await shot(label+"_front")
	frame_seat(point,true);await frames(3);await shot(label+"_side")
	await tap(KEY_ESCAPE);await get_tree().create_timer(.4).timeout
	check(label+" Esc restores standing",not main.player.seated and main.story.public_life.current_seat==null)
	await shot(label+"_standing")

func _drink(result: Dictionary) -> void:
	result.ok=await main.story.public_life.drink("coffee");result.done=true

func _run() -> void:
	while not main.loading_ready or Loading.scene_busy:await frames(1)
	await frames(20)
	GameState.new_game();GameState.clock_paused=true;GameState._ui_locks.clear()
	GameState.quests.Q00={"state":"done","step":2};GameState.flags.erase("arrival_home")
	GameState.day=2;GameState.minute=10*60;GameState.weather="sunny";NPC.roam_enabled=false;Progress.quiet=true
	main.ui.instant=false;main.ui.auto=true;main._restore();main.ui.dialogue_end()
	camera=Camera3D.new();main.add_child(camera);camera.fov=48;camera.far=210;camera.make_current()
	main.rig.process_mode=Node.PROCESS_MODE_DISABLED
	var town: Interactable;var farm: Interactable;var lake: Interactable
	for point: Interactable in main.story.public_life.outdoor.points:
		if str(point.get_meta("rest_region"))=="town" and town==null:town=point
		elif point.id=="farm_bench":farm=point
		elif str(point.get_meta("rest_scene"))=="镜波湖畔" and lake==null:lake=point
	check("town farm and lake all supply an existing seat",town!=null and farm!=null and lake!=null)
	if town!=null:await use_seat(town,"01_town")
	if farm!=null:await use_seat(farm,"02_farm")
	if lake!=null:await use_seat(lake,"03_lake")
	await main.enter_interior("bakery");await frames(10)
	var cafe: Interactable
	for point: Node in get_tree().get_nodes_in_group("interactables"):
		if point.get("id")=="public_cafe_1":cafe=point as Interactable;break
	check("cafe seat exists",cafe!=null)
	if cafe!=null:
		main.player.global_position=cafe.get_parent().to_global(cafe.get_meta("stand_position"));main.player.face_towards(cafe.global_position)
		main.player.reset_physics_interpolation();main.ui.auto_choices=[0];await frames(6);main.player._update_target()
		check("cafe actual target",main.player.target==cafe);await tap(KEY_E);await idle_story()
		check("cafe E seats the player",main.player.seated)
		var origin: Vector3=InteriorBuilder.spec_for("bakery").origin
		camera.global_position=origin+Vector3(-1.8,1.55,3.9);camera.look_at(origin+Vector3(.2,.85,2.55));camera.make_current()
		GameState.add_item("coffee",1,true);var before: int=GameState.count("coffee")
		var result: Dictionary={"done":false,"ok":false};_drink(result);await frames(8)
		var action: LivingAction
		for child: Node in main.get_children():
			if child is LivingAction:action=child as LivingAction;break
		check("coffee uses a supported cup with natural hands",action!=null and action.pose==null and action.prop!=null and action.prop.global_position.distance_to(action.surface_at+Vector3.UP*.055)<.001)
		await shot("04_cafe_table_cup")
		await tap(KEY_ESCAPE);await frames(4)
		check("real Esc cancels without consuming coffee",result.done and not result.ok and GameState.count("coffee")==before)
		await shot("05_cafe_cancelled")
		var saved: bool=GameState.save_game();main.story.public_life.stand(true)
		var loaded: bool=GameState.load_game();main._restore();await frames(8)
		check("SQLite reload stands without a leftover seated modifier",saved and loaded and not main.player.seated and main.story.public_life.current_seat==null and main.story.public_life.pose==null)
		await shot("06_reloaded_standing")
	var report: Dictionary={"passed":failures.is_empty(),"failures":failures,"checks":checks,"shots":shots,"transition_samples":transition_samples,"seconds":(Time.get_ticks_msec()-started)/1000.0}
	FileAccess.open(folder.path_join("demo.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SEATING_DEMO ",JSON.stringify(report));get_tree().quit(0 if failures.is_empty() else 1)

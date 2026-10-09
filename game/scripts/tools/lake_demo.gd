extends Node
## Visual integration run. Use an isolated HARUMACHI_SAVE_DIR and --newgame --lake-demo.
## Walks the lake loop, drives the real fishing key handlers, sells, cooks and saves.
var main: Node
var out := "/tmp/harumachi-lake-demo"
var failures: Array[String] = []
var catches: Array[Dictionary] = []
var started := 0

func _ready() -> void:
	main=get_parent();started=Time.get_ticks_msec()
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--lake-demo-out="):out=arg.substr(16)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func _frames(n:int) -> void:
	for i in n:await get_tree().process_frame

func _key(code:Key,pressed:bool)->void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)

func _tap(code:Key)->void:
	_key(code,true);await _frames(1);_key(code,false);await _frames(1)

func _shot(name:String)->void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name+".png"))
	print("LAKE_DEMO SHOT ",name)

func _point(id:String)->Interactable:
	for node:Node in get_tree().get_nodes_in_group("interactables"):
		if node is Interactable and node.id==id:return node as Interactable
	return null

func _walk(p:Vector2)->bool:
	var target:=FarmBuilder.ORIGIN+Vector3(p.x,LakesideLayout.height_at(p),p.y)
	var elapsed:=0.0
	while Vector2(main.player.global_position.x-target.x,main.player.global_position.z-target.z).length()>.36 and elapsed<45.0:
		var delta:Vector3=target-main.player.global_position;delta.y=0
		main.player.auto_move=delta.normalized();main.player.auto_run=true
		await get_tree().physics_frame
		elapsed+=1.0/float(Engine.physics_ticks_per_second)
	main.player.auto_move=Vector3.ZERO;main.player.auto_run=false
	if elapsed>=45.0:
		failures.append("walking blocked before %s at %s"%[p,main.player.global_position-FarmBuilder.ORIGIN]);return false
	return true

func _cast_once(index:int)->bool:
	var panel:FishingPanel=main.ui.fishing_panel
	await _tap(KEY_E)
	if index==0:await _shot("03_cast")
	var deadline:=Time.get_ticks_msec()+16000
	while panel.session.state not in [FishingSession.State.BITE,FishingSession.State.MISSED] and Time.get_ticks_msec()<deadline:await _frames(1)
	if panel.session.state!=FishingSession.State.BITE:
		failures.append("no bite in native input run");return false
	if index==0:await _shot("04_bite")
	await _tap(KEY_E)
	var held:=false
	var photographed:=false
	deadline=Time.get_ticks_msec()+35000
	while panel.session.state==FishingSession.State.REEL and Time.get_ticks_msec()<deadline:
		var next:=held
		next=panel.session.suggested_hold()
		if next!=held:_key(KEY_E,next);held=next
		if index==0 and panel.session.reel_progress>.4 and not photographed:
			photographed=true;await _shot("05_reeling")
		await _frames(1)
	_key(KEY_E,false)
	if panel.session.state!=FishingSession.State.LANDED:
		failures.append("catch failed: "+panel.session.message);return false
	catches.append(panel.session.result.duplicate(true))
	await _shot("06_catch_%d"%index)
	return true

func _run()->void:
	await _frames(30)
	GameState.clock_paused=true;GameState.minute=10*60;main.ui.instant=false;main.ui.auto=false
	await main.go_farm()
	main.rig.dist=9.5;main.rig.pitch=28.0;main.rig.yaw=-100;main.rig.snap()
	if not await _walk(Vector2(24,.3)):_finish();return
	await _frames(10);await _tap(KEY_E)
	for i in 90:
		if main.ui.modal=="shop":break
		await _frames(1)
	await _shot("01_supplies")
	main.ui.close_modal();await _frames(8)
	# Actual collision movement follows the same curved path shown by the map.
	var route:PackedVector2Array=LakesideLayout.walk_paths()[0]
	for i in range(6,67,3):
		if not await _walk(route[i]):_finish();return
	if not await _walk(Vector2(94,48)):_finish();return
	await _tap(KEY_M);await _shot("02_full_map");await _tap(KEY_M)
	if not await _walk(Vector2(94,37.9)):_finish();return
	await _frames(15)
	await _tap(KEY_E)
	for i in 90:
		if main.ui.modal=="fishing":break
		await _frames(1)
	if main.ui.modal!="fishing":
		failures.append("pier E interaction did not open fishing");_finish();return
	await _shot("02_fishing_ready")
	if not await _cast_once(0):_finish();return
	if not await _cast_once(1):_finish();return
	await _tap(KEY_ESCAPE);await _frames(10)
	# Buyer and kitchen locations are explicit fixtures; their real UI callbacks
	# and inventory rules are used, with no invented catch or money reward.
	main.player.global_position=FarmBuilder.ORIGIN+Vector3(24,.15,.3);main.player.velocity=Vector3.ZERO
	main.story.call_deferred("interact",_point("lakeside_supplies"))
	for i in 90:
		if main.ui.modal=="shop":break
		await _frames(1)
	main.ui.panels._set_tab("sell")
	var coins_before:int=GameState.coins
	main.ui.panels.store_sell(str(catches[0].fish),1)
	if GameState.coins<=coins_before:failures.append("buyer did not pay for caught fish")
	await _shot("07_sell_catch")
	var recipes:Dictionary={"fish_crucian":"crucian_soup","fish_carp":"carp_kanroni","fish_ayu":"grilled_ayu","fish_trout":"trout_rice","fish_bass":"butter_bass","fish_eel":"eel_rice"}
	var recipe_id:String=recipes[str(catches[1].fish)]
	for iid:String in GameState.recipe(recipe_id).inputs:
		if not GameState.item(iid).get("fish",false):main.ui.panels.store_buy(iid,int(GameState.recipe(recipe_id).inputs[iid]))
	main.ui.close_modal();await _frames(8)
	await main.leave_farm()
	main._put_in_room(HouseBuilder.ORIGIN+Vector3(-4.5,.15,3.0))
	main.player.face_towards(_point("house_stove").global_position)
	await _frames(10);await _tap(KEY_E)
	for i in 90:
		if main.ui.modal=="craft":break
		await _frames(1)
	if main.ui.modal!="craft":
		failures.append("kitchen interaction did not open cooking");_finish();return
	main.ui.panels.craft(recipe_id,1)
	if GameState.count(recipe_id)!=1:failures.append("caught fish could not be cooked")
	await _shot("08_cook_catch")
	main.ui.close_modal();await _frames(6)
	main.ui.book.open("fish");await _shot("09_fish_records");main.ui.close_modal()
	var count_before:int=GameState.fishing.landed
	if not GameState.save_game() or not GameState.load_game() or int(GameState.fishing.landed)!=count_before:failures.append("fishing progress did not persist")
	_finish()

func _finish()->void:
	if is_instance_valid(main.ui.fishing_panel):main.ui.fishing_panel.finish()
	main.player.auto_move=Vector3.ZERO
	var report:Dictionary={"passed":failures.is_empty(),"failures":failures,"catches":catches,"fishing":GameState.fishing,"coins":GameState.coins,"seconds":float(Time.get_ticks_msec()-started)/1000.0,"area_ratio":LakesideLayout.expansion_ratio()}
	var file:=FileAccess.open(out.path_join("demo.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("LAKE_DEMO DONE ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

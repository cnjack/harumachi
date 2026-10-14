extends RefCounted
var t: Object
var main: Node
func _init(runner: Object) -> void:t=runner;main=t.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("SEATING",label,ok,detail)

func _action() -> LivingAction:
	for child: Node in main.get_children():
		if child is LivingAction:return child as LivingAction
	return null

func _drink(result: Dictionary) -> void:
	result.ok=await main.story.public_life.drink("coffee");result.done=true

func _sit(point: Interactable,result: Dictionary) -> void:
	result.ok=await main.story.public_life.call("sit_down",point);result.done=true

func _stand(result: Dictionary) -> void:
	await main.story.public_life.stand();result.done=true

func _wait(result: Dictionary) -> bool:
	var until: int=Time.get_ticks_msec()+1800
	while not result.done and Time.get_ticks_msec()<until:await main.get_tree().process_frame
	return bool(result.done)

func run() -> void:
	var saved: Dictionary=GameState.to_dict().duplicate(true)
	var original_instant: bool=main.ui.instant
	var life: Object=main.story.public_life
	var drink:=LivingAction.new();main.add_child(drink)
	drink.surface_at=Vector3(0,.8,0);drink.duration=100;drink.setup(main.player,"sip","coffee");drink.clock=50
	await t.frames(3)
	check("drinking never creates an arm modifier, mouth target or hand-bound cup",drink.pose==null and drink.skeleton==null and drink.hand<0)
	check("a visible coffee cup stays on its supplied tabletop",drink.prop!=null and drink.prop.name=="TableCup" and drink.prop.global_position.distance_to(drink.surface_at+Vector3.UP*.055)<.001)
	drink.queue_free()
	var give:=LivingAction.new();main.add_child(give);give.duration=100;give.setup(main.player,"give","onigiri")
	await t.frames(2)
	check("handoff timing no longer invents a hovering hand-held serving",give.pose==null and give.hand<0 and give.prop==null)
	give.queue_free()
	if "--seating-legacy-check" in OS.get_cmdline_user_args():
		await t.frames(1)
		GameState.from_dict(saved);main.ui.instant=original_instant;return
	GameState.add_item("coffee",1,true)
	var owned: int=GameState.count("coffee")
	main.ui.instant=false
	var drinking: Dictionary={"done":false,"ok":false};_drink(drinking)
	await t.frames(2)
	var current: LivingAction=_action()
	if current!=null and current.has_method("cancel"):current.call("cancel")
	elif current!=null:current.clock=current.duration
	var cancellation_finished: bool=await _wait(drinking)
	check("cancelling a drink completes the pending operation without consuming the owned cup",cancellation_finished and not drinking.ok and GameState.count("coffee")==owned)
	main.ui.instant=true
	check("finishing a quiet drink consumes exactly one owned cup",await life.drink("coffee") and GameState.count("coffee")==owned-1)
	var prior_day: int=GameState.day;var prior_minute: float=GameState.minute
	var had_hanabi: bool=GameState.flags.has("fest_hanabi");var prior_hanabi: Variant=GameState.flags.get("fest_hanabi")
	GameState.day=24;GameState.minute=19.8*60;GameState.flags.erase("fest_hanabi")
	check("ordinary resting yields the farm bench to the active fireworks story",main.story.fest.handles("farm_bench") and not life.handles("farm_bench"))
	GameState.day=prior_day;GameState.minute=prior_minute
	if had_hanabi:GameState.flags["fest_hanabi"]=prior_hanabi
	var outdoor: RefCounted=life.get("outdoor")
	var points: Array[Interactable]=[]
	if outdoor!=null:points.assign(outdoor.get("points"))
	check("all nine existing courtyard, farm and lakeside benches have a use",points.size()==9)
	var identities: Dictionary={};var duplicate: bool=false
	for point: Interactable in points:
		if identities.has(point.id):duplicate=true
		identities[point.id]=true
	var farm_entries: int=0
	for point: Node in main.get_tree().get_nodes_in_group("interactables"):
		if point.get("id")=="farm_bench":farm_entries+=1
	check("the old farm bench has one interaction, with no competing duplicate rest point",not duplicate and farm_entries==1 and identities.has("farm_bench"))
	if points.is_empty():
		check("the new seating lifecycle exists for transition and save checks",false)
		GameState.from_dict(saved);main.ui.instant=original_instant;return
	var skeleton: Skeleton3D=main.player.model.find_children("*","Skeleton3D",true,false)[0]
	var probe: SkeletonModifier3D=load("res://scripts/tools/character_qa_pose_probe.gd").new()
	skeleton.add_child(probe);probe.call("prepare",main.player.model);probe.set("measure_feet",true)
	var seat_edges_clear: bool=true
	var keepsakes_clear: bool=true
	for point: Interactable in points:
		var farm: bool=str(point.get_meta("rest_region","town"))=="farm"
		main.world.set_region("farm" if farm else "town");GameState.player_region="farm" if farm else "town"
		main.in_room=false;GameState.player_in_room=false;main.world.set_indoor_look(false)
		var stand_at: Vector3=point.get_parent().to_global(point.get_meta("stand_position"))
		main.player.global_position=stand_at+Vector3.UP*.01;main.player.velocity=Vector3.ZERO
		main.player.face_towards(point.global_position+Vector3.RIGHT*.01)
		await t.frames(4);main.player._update_target()
		var targeted: bool=main.player.target==point and point.is_visible_in_tree()
		main.ui.auto_choices=[2] if point.id=="farm_bench" else []
		if targeted:await main.story.interact(main.player.target)
		skeleton.move_child(probe,skeleton.get_child_count()-1);await t.frames(12)
		var seated: bool=main.player.seated and life.current_seat==point
		var soles: Dictionary=probe.get("soles")
		var feet: bool=absf(float(soles.get("L",INF))-main.player.global_position.y)<.025 and absf(float(soles.get("R",INF))-main.player.global_position.y)<.025
		var supported: bool=seated and life.pose!=null and absf(life.pose.measured_hip_height-(float(point.get_meta("seat_height"))+.09))<.02
		check("real interaction seats and supports the player at "+point.id,targeted and supported and feet,"target=%s hips=%s feet=%s"%[str(main.player.target.id if main.player.target else "none"),str(life.pose.measured_hip_height if life.pose else INF),str(soles)+" joints="+JSON.stringify(probe.get("joints"))])
		var support: Node3D=main.get_node(point.get_meta("seat_support")) as Node3D
		for keepsake: HomageDisplay in main.world.find_children("*","HomageDisplay",true,false):
			var book_at: Vector3=support.to_local(keepsake.global_position)
			if absf(book_at.x)<.9 and absf(book_at.z)<.3:
				var separation: Vector3=main.player.global_position-keepsake.global_position
				keepsakes_clear=keepsakes_clear and Vector2(separation.x,separation.z).length()>float(keepsake.entry.width)*.5+.30
		var joints: Dictionary=probe.get("joints")
		for side: String in ["L","R"]:
			var knee_data: Array=joints.get("shin."+side,[0,0,0]);var hand_data: Array=joints.get("hand."+side,[0,0,0])
			var knee_at: Vector3=support.to_local(Vector3(knee_data[0],knee_data[1],knee_data[2]))
			var hand_at: Vector3=support.to_local(Vector3(hand_data[0],hand_data[1],hand_data[2]))
			seat_edges_clear=seat_edges_clear and knee_at.z>.36 and (hand_at.z>.31 or hand_at.y>float(point.get_meta("seat_height"))+.045)
		life.stand(true);await t.frames(2)
	check("both knees clear the real bench front and relaxed hands stay above or ahead of its planks at all nine seats",seat_edges_clear)
	check("seated bodies leave the illustrated keepsakes on existing benches unobstructed",keepsakes_clear)
	var chosen: Interactable=points[0]
	main.world.set_region("town");GameState.player_region="town"
	var start: Vector3=chosen.get_parent().to_global(chosen.get_meta("stand_position"))
	main.player.global_position=start+Vector3.RIGHT*4
	check("sitting cannot pull the player from across the courtyard",not life.sit(chosen) and not main.player.seated)
	main.player.global_position=start
	main.ui.instant=false
	var interrupted: Dictionary={"done":false,"ok":false};_sit(chosen,interrupted)
	await t.frames(2);life.stand(true)
	check("forced cleanup during the sit transition releases its awaiting caller",await _wait(interrupted) and not interrupted.ok and not main.player.seated and life.current_seat==null)
	main.ui.instant=true;main.player.global_position=start;life.sit(chosen);main.ui.instant=false
	var rising: Dictionary={"done":false};_stand(rising);await t.frames(2);life.stand()
	check("repeated stand requests do not strand the first transition",await _wait(rising) and not main.player.seated and life.current_seat==null)
	main.ui.instant=true;main.player.global_position=start;life.sit(chosen)
	main.ui.dialogue_end()
	var escape:=InputEventKey.new();escape.physical_keycode=KEY_ESCAPE;escape.keycode=KEY_ESCAPE;escape.pressed=true
	Input.parse_input_event(escape);Input.flush_buffered_events();await t.frames(3)
	escape=InputEventKey.new();escape.physical_keycode=KEY_ESCAPE;escape.keycode=KEY_ESCAPE
	Input.parse_input_event(escape);Input.flush_buffered_events();await t.frames(1)
	check("real Esc leaves the seat before the UI can open pause",not main.player.seated and life.current_seat==null and main.ui.modal=="")
	main.player.global_position=start;life.sit(chosen)
	main.before_save();var standing_save: Vector3=GameState.player_pos
	check("saving from an outdoor bench stores a clear ground-level standing point",standing_save.distance_to(main.player.global_position)>.45 and absf(standing_save.y-start.y)<.04)
	var written: bool=GameState.save_game();life.stand(true)
	var loaded: bool=GameState.load_game();main._restore();await t.frames(3)
	check("SQLite reload restores standing and removes every transient seated modifier",written and loaded and not main.player.seated and life.current_seat==null and life.pose==null)
	main.player.global_position=start;life.sit(chosen)
	await main.go_farm();await t.frames(3)
	check("leaving town clears the seat before the region changes",not main.player.seated and life.current_seat==null and main.world.region=="farm")
	await main.leave_farm();main.player.global_position=start;life.sit(chosen);GameState.minute=23*60
	var slept: bool=await main.sleep_now(true)
	check("sleeping from a bench wakes in the bedroom with movement and a room-local save",slept and not main.player.seated and life.current_seat==null and main.in_room and GameState.player_in_room and GameState.player_pos.distance_to(main.player.global_position)<.15)
	probe.queue_free();main.ui.instant=original_instant
	GameState.from_dict(saved);main._restore()

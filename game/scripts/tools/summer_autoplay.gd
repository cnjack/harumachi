class_name SummerAutoplay
extends RefCounted
## Fresh cooperation route. No quest, crop, project result or driver teleport fixtures.
var a: Node
var main: Node
var G: Node
var checks: Array[Dictionary]=[]
var failures: Array[String]=[]
var report_path: String=""
var started: int=0
var resumed:=false
var start_snapshot: Dictionary={}
var resume_stage: String=""

class AssemblyKeys extends Node:
	var main: Node
	var delay:=0.0
	var released: Key=KEY_NONE
	func _process(delta: float) -> void:
		if released!=KEY_NONE:
			var up:=InputEventKey.new();up.keycode=released;up.physical_keycode=released
			Input.parse_input_event(up);released=KEY_NONE
		delay-=delta
		if delay>0: return
		for child in main.get_children():
			if not child is LanternAssembly or not child.active: continue
			var p: Dictionary=WorkshopProject.state()
			var difference: float=wrapf(float(WorkshopProject.TARGETS[int(p.joints)])-float(p.angle),-180,180)
			var key: Key=KEY_SPACE if absf(difference)<=10 else (KEY_A if difference<0 else KEY_D)
			var down:=InputEventKey.new();down.keycode=key;down.physical_keycode=key;down.pressed=true
			Input.parse_input_event(down);released=key;delay=.22
			return

func _init(driver: Node) -> void:
	a=driver;main=driver.main;G=GameState
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--autoplay-report="): report_path=arg.trim_prefix("--autoplay-report=")
		if arg=="--autoplay-resume": resumed=true

func run() -> bool:
	started=Time.get_ticks_msec()
	if resumed:
		if not record("resume loads a real isolated save",G.load_game()): return false
		main._restore()
		if G.at_step("Q05","start") and SummerProjects.ready() and G.player_in_room: resume_stage="opening_event"
		elif G.qstate("Q14")=="done" and WorkshopProject.state().stored and not SummerGathering.state().sessions.get("festival",{}).is_empty(): resume_stage="finish_festival"
		if not record("the persisted state matches a supported debugging checkpoint",resume_stage!=""): return false
	start_snapshot={"day":G.day,"q05":G.qstate("Q05"),"q05_step":G.qstep_id("Q05"),"q15":G.qstate("Q15"),"slot":SaveDB.active_slot,"sha256":JSON.stringify(G.to_dict()).sha256_text()}
	G.clock_paused=true
	NPC.roam_enabled=false
	var inputs:=AssemblyKeys.new();inputs.main=main;main.add_child(inputs)
	var stages: Array=["arrival","opening","old_work","festival","fireworks"]
	if resumed: stages=["opening_event","old_work","festival","fireworks"] if resume_stage=="opening_event" else ["finish_festival","fireworks"]
	for stage: String in stages:
		print("AP SUMMER stage="+stage)
		var success: bool=await call("_"+stage)
		if not success: break
	inputs.queue_free()
	main.player.auto_move=Vector3.ZERO
	var passed: bool=failures.is_empty() and G.qstate("Q15")=="done" and not G.input_locked() and not main.story.busy
	var report: Dictionary={"passed":passed,"failures":failures,"checks":checks,"day":G.day,"minute":G.minute,
		"q05":G.qstate("Q05"),"q15":G.qstate("Q15"),"summer_complete":MainlineProgress.summer_complete(),
		"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"driver_player_teleports":0,"fresh_run":not resumed,
		"starting_state":start_snapshot,"scope":("resumed debugging segment from "+resume_stage if resumed else "fresh new cooperation save")+"; real collision walking and reachable Story interactions, placement controller, recipe panel, keyboard assembly, invited CalendarAdvance, actual festival/photo/cleanup/fireworks. Auto dialogue and paused clock; authored scene cuts retained. Technical coverage, not natural duration.",
		"projects":SummerProjects.state().duplicate(true),"work":WorkshopProject.state().duplicate(true),
		"gathering":SummerGathering.state().duplicate(true),"direction":MainlineProgress.direction().duplicate(true)}
	if report_path!="":
		DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
		var file:=FileAccess.open(report_path,FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  "))
	print("AUTOPLAY SUMMER %s Q05=%s Q15=%s" % ["PASS" if passed else "FAIL",G.qstate("Q05"),G.qstate("Q15")])
	return passed

func record(name: String, condition: bool) -> bool:
	checks.append({"name":name,"ok":condition,"day":G.day,"minute":G.minute})
	print(("PASS AP " if condition else "FAIL AP ")+name)
	if not condition: failures.append(name)
	return condition

func _arrival() -> bool:
	await a.shot("summer_arrival")
	if not await main.finish_arrival_home(true): return false
	if not record("authored arrival reaches the next morning without player finding home", G.day == 2 and main.in_room and G.qstate("Q00") == "done" and not DailyLife.done("meal")): return false
	if not await use("life_pantry",[0,0]): return false
	if not await use("house_stove",[{"craft":{"first_home_onigiri":1}}]): return false
	if not await use("life_meal_table",[0]): return false
	await a.shot("summer_first_meal")
	if not record("real first meal and home arrival",G.qstate("Q00")=="done" and DailyLife.done("meal") and G.count("onigiri")==1): return false
	return await leave()

func _opening() -> bool:
	# Arrival now wakes at 06:30. Let the real morning clock run while walking
	# and meeting people; freezing it at 06:45 must not bypass a closed shop.
	G.clock_paused=false
	if not await use("mio",[0]): return false
	if not await use("board"): return false
	if not await use("bakery"): return false
	if not record("the actual morning walk reaches an open bakery interior",main.in_room and main.room_kind=="bakery"):return false
	G.clock_paused=true
	if not await use("opening_paper",[0,0,1,0]): return false
	if not await use("bakery_oven",[{"craft":{"opening_trial":1}}]): return false
	if not await leave(): return false
	if not await use("mio",[0]): return false
	if not await use("haru",[0]): return false
	if not await use("bakery"): return false
	if not await use("opening_paper",[0,0,0]): return false
	if not await leave(): return false
	if not await place_opening(): return false
	if not await use("opening_site",[0,0]): return false
	if not record("sample, two opinions and real layout trial",SummerProjects.ready()): return false
	if not await use("mio"): return false
	if not await use("ren",[0]): return false
	if not await use("haru",[0]): return false
	if not await appointment("market"): return false
	return await _opening_event()

func _opening_event() -> bool:
	if not await leave(): return false
	if not await use("mio",[0]): return false
	if not await use("opening_site",[1]): return false
	if not await use("opening_site",[0]): return false
	# Pack real remaining food before the date changes, without reproducing an old basket later.
	if not await pack_opening(): return false
	for who: String in ["mio","ren","haru"]:
		if not await use(who,[1]): return false
	if not await idle(): return false
	await a.shot("summer_first_market_complete")
	return record("first market and genuine received portion",G.qstate("Q05")=="done" and SummerProjects.market_used() and not MainlineProgress.summer_complete())

func _old_work() -> bool:
	if not await use("home_door"): return false
	if not await use("room_closet",[0]): return false
	if not await leave(): return false
	if not await use("mio",[0]): return false
	if not await use("center_door"): return false
	if not await use("workroom_archive",[0]): return false
	if not await leave(): return false
	if not await use("haru"): return false
	if not await use("mio"): return false
	if not record("actual notebook, conversations and summer invitation",G.qstate("Q11")=="done" and G.flags.get("summer_invitation",{}).get("presented",false)): return false
	if not await use("center_door"): return false
	if not await use("workroom_table",[0,1,1]): return false
	if not record("keyboard assembles a single player-made representative",int(WorkshopProject.state().joints)==3 and WorkshopProject.state().maker=="player"): return false
	if not await use("workroom_lantern_test",[0,0]): return false
	await a.shot("summer_real_lantern_trial")
	if not await leave(): return false
	if not await use("mio"): return false
	if not record("one preparation route is retained and reported without a compulsory second route",G.qstate("Q12")=="done" and SummerSpace.state().phase=="invitation"): return false
	return await appointment("summer")

func _festival() -> bool:
	if not await leave(): return false
	if not await use("gathering_paper",[0,0,0,1]): return false
	if not await use("gathering_paper",[0,0]): return false
	# Decide for the known incoming approach before checking, rather than forcing a failed first trial.
	if not await use("gathering_paper",[1,2,1]): return false
	if not await use("gathering_paper",[1,0]): return false
	if not record("the same work and a finite new menu are actually used at the festival",not WorkshopProject.state().installed.is_empty() and not SummerGathering.current().get("served",{}).is_empty()): return false
	await a.shot("summer_same_work_and_new_basket")
	if not await use("yagura",[0]): return false
	if not await use("mio",[1,0,0]): return false
	if not record("real festival, watched fish, explicit photo and promise",G.qstate("Q14")=="done" and G.flags.get("summer_attended",false) and G.flags.get("summer_shared",{}).get("participation","")=="watched" and Progress.found("col_photo_new")): return false
	await a.shot("summer_actual_photo_and_promise")
	if not await use("gathering_paper",[3]): return false
	if not record("real leftovers and the same work are stored after the event",SummerGathering.state().sessions.festival.closed and WorkshopProject.state().stored): return false
	return await _finish_festival()

func _finish_festival() -> bool:
	if not await use("tanaka"): return false
	if not await use("east_end"): return false
	if not await use("farm_shed"): return false
	return record("old fire tube leads to the real fireworks agreement",G.at_step("Q15","watch_hanabi"))

func _fireworks() -> bool:
	if not await appointment("hanabi"): return false
	if not await leave(): return false
	if not await use("east_end"): return false
	if not await use("farm_bench",[0]): return false
	if not await idle(): return false
	if not record("actual fireworks reach Q15 and a chosen future intention",G.qstate("Q15")=="done" and G.flags.get("fest_hanabi",false) and not MainlineProgress.direction().is_empty()): return false
	await a.shot("summer_fireworks_conclusion")
	if not await use("farm_exit"): return false
	if not await use("home_door"): return false
	if not await use("room_desk",[1]): return false
	await a.shot("summer_note_at_home")
	return record("final control, saved note and one stored work",not main.story.busy and not G.input_locked() and main.world.house.future_note.visible and WorkshopProject.state().stored and G.save_game())

func appointment(id: String) -> bool:
	var target: Dictionary=CalendarAdvance.appointment(id)
	if not record("available actual appointment: "+id,not target.is_empty()): return false
	main.ui.auto_choices=[0]
	await main.ui.panels._advance_appointment(id)
	if not await idle(): return false
	return record("appointment saved at the actual date and time: "+id,G.day==int(target.day) and int(G.minute)>=int(target.minute) and G.calendar_pending_save==-1)

func idle() -> bool:
	# Post-interaction checks may schedule the chapter conclusion with call_deferred.
	for frame in 2: await main.get_tree().process_frame
	var deadline: int=Time.get_ticks_msec()+60000
	while (main.story.busy or G.input_locked() or main.ui.modal!="") and Time.get_ticks_msec()<deadline:
		await main.get_tree().process_frame
	return record("interaction and modal recover control",not main.story.busy and not G.input_locked() and main.ui.modal=="")

func point(id: String) -> Interactable:
	if main.npcs.has(id): return main.npcs[id].talk
	for candidate in main.get_tree().get_nodes_in_group("interactables"):
		if candidate.id==id: return candidate
	return null

func use(id: String, choices: Array=[]) -> bool:
	var it: Interactable=point(id)
	if not record("visible interaction exists: "+id,it!=null and it.is_visible_in_tree()): return false
	var held: NPC=main.npcs.get(id)
	if held: held.hold=true
	var ready: bool=await approach(it)
	if not record("physically reachable target: "+id,ready):
		if held: held.hold=false
		return false
	print("AP SUMMER use="+id+" day="+str(G.day)+" minute="+str(G.minute))
	main.ui.auto_choices=choices.duplicate()
	await main.story.interact(it)
	if held: held.hold=false
	return await idle()

func leave() -> bool:
	if not main.in_room: return record("inside before leaving through doorway",false)
	var id: String="room_door" if main.room_kind=="house" else ("workroom_exit" if main.room_kind=="workroom" else main.room_kind+"_exit")
	return await use(id)

func place_opening() -> bool:
	var it: Interactable=point("opening_site")
	if not await approach(it): return record("opening placement entry reachable",false)
	main.ui.auto_choices=[1]
	main.story.interact(it)
	var deadline: int=Time.get_ticks_msec()+15000
	while not main.placement.active and Time.get_ticks_msec()<deadline: await main.get_tree().process_frame
	if not record("actual placement controller opens",main.placement.active): return false
	for entry: Array in [["picnic_table",7.0,4.0],["bench",2.5,10.5]]:
		main.placement._select(str(entry[0]))
		main.placement.rot=0
		await a._glide_mouse(main.placement,Vector3(float(entry[1]),0,float(entry[2])))
		main.placement.try_place()
		await main.get_tree().physics_frame
	await a.shot("summer_actual_opening_placement")
	main.placement.exit()
	if not await idle(): return false
	return record("actual finite loan placed by controller",G.seating_ready())

func pack_opening() -> bool:
	var it: Interactable=point("opening_site")
	if not await approach(it): return record("leftover packing entry reachable",false)
	var recipients:=0
	var service: Dictionary=SummerProjects.opening().service
	for who: String in ["mio","haru","kazuko"]:
		if main.story.projects._present(who) and int(service.remaining)>0 and not service.served.has(who): recipients+=1
	main.ui.auto_choices=[recipients+1]
	await main.story.interact(it)
	return await idle()

func approach(it: Interactable) -> bool:
	var location: Vector3=it.global_position
	var offsets: Array[Vector2]=[Vector2(0,1.05),Vector2(1.05,0),Vector2(-1.05,0),Vector2(0,-1.05),Vector2(.75,.75),Vector2(-.75,.75)]
	if main.npcs.has(it.id):
		for direction: Vector2 in [Vector2.DOWN,Vector2.UP,Vector2.LEFT,Vector2.RIGHT]: offsets.append(direction*1.8);offsets.append(direction*2.1)
	if it.id.ends_with("_exit") or it.id=="room_door": offsets.push_front(Vector2(0,-1.05))
	for offset: Vector2 in offsets:
		location=it.global_position
		var destination: Vector3=Vector3(location.x+offset.x,.05,location.z+offset.y)
		var path: Array[Vector3]=path_to(destination)
		if path.is_empty():
			if it.id=="tanaka" or OS.get_cmdline_user_args().has("--approach-debug"): print("AP APPROACH "+it.id+" no path "+str(destination))
			continue
		if not await walk(path): continue
		main.player.face_towards(location)
		main.rig.snap()
		for frame in 8: await main.get_tree().physics_frame
		if main.player.target==it: return true
		if it.id=="tanaka" or OS.get_cmdline_user_args().has("--approach-debug"): print("AP APPROACH "+it.id+" reached "+str(main.player.global_position)+" actual target="+(main.player.target.id if main.player.target else "none"))
	main.player.auto_move=Vector3.ZERO
	return false

func path_to(destination: Vector3) -> Array[Vector3]:
	var origin:=Vector2(-46,-18)
	var dimensions:=Vector2(96,48)
	if main.in_room:
		if main.room_kind=="house": origin=Vector2(HouseBuilder.ORIGIN.x-7,HouseBuilder.ORIGIN.z-9);dimensions=Vector2(15,15)
		else:
			var room: Dictionary=InteriorBuilder.SPECS[main.room_kind]
			origin=Vector2(room.origin.x-room.size.x/2-1,room.origin.z-room.size.y/2-1)
			dimensions=room.size+Vector2(2,3)
	elif main.world.region=="farm": origin=Vector2(FarmBuilder.ORIGIN.x-30,FarmBuilder.ORIGIN.z-16);dimensions=Vector2(60,40)
	var cell:=.4
	var grid:=AStarGrid2D.new()
	grid.region=Rect2i(Vector2i.ZERO,Vector2i(ceil(dimensions.x/cell),ceil(dimensions.y/cell)))
	grid.cell_size=Vector2.ONE*cell;grid.offset=origin
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;grid.update()
	var probe:=PhysicsShapeQueryParameters3D.new()
	var capsule:=CapsuleShape3D.new();capsule.radius=.32;capsule.height=1.6
	probe.shape=capsule
	probe.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_BLOCK|WorldBuilder.L_ACTORS
	probe.exclude=[main.player.get_rid()]
	var space: PhysicsDirectSpaceState3D=main.world.get_world_3d().direct_space_state
	for y in grid.region.size.y:
		for x in grid.region.size.x:
			var at: Vector2=origin+Vector2(x,y)*cell
			probe.transform=Transform3D(Basis.IDENTITY,Vector3(at.x,.85,at.y))
			grid.set_point_solid(Vector2i(x,y),not space.intersect_shape(probe,1).is_empty())
	var start: Vector3=main.player.global_position
	var from:=Vector2i((Vector2(start.x,start.z)-origin)/cell+Vector2.ONE*.5)
	var to:=Vector2i((Vector2(destination.x,destination.z)-origin)/cell+Vector2.ONE*.5)
	var out: Array[Vector3]=[]
	if not grid.region.has_point(from) or not grid.region.has_point(to) or grid.is_point_solid(to): return out
	# Grid rounding can put a valid current actor on an occupied adjacent cell. Actual walking still checks collisions.
	grid.set_point_solid(from,false)
	var flat: PackedVector2Array=grid.get_point_path(from,to)
	for at: Vector2 in flat: out.append(Vector3(at.x,0,at.y))
	if not out.is_empty(): out.append(destination)
	return out

func walk(path: Array[Vector3]) -> bool:
	var entered: bool=main.in_room
	var kind: String=main.room_kind
	var region: String=main.world.region
	for destination: Vector3 in path:
		var deadline: int=Time.get_ticks_msec()+10000
		var stagnant:=0.0
		var last: Vector3=main.player.global_position
		while Vector2(main.player.global_position.x-destination.x,main.player.global_position.z-destination.z).length()>.19:
			if main.in_room!=entered or main.room_kind!=kind or main.world.region!=region:
				main.player.auto_move=Vector3.ZERO
				return false
			var difference: Vector3=destination-main.player.global_position;difference.y=0
			main.player.auto_move=difference.normalized();main.player.auto_run=true
			await main.get_tree().physics_frame
			var moved: float=Vector2(main.player.global_position.x-last.x,main.player.global_position.z-last.z).length()
			stagnant=stagnant+main.get_physics_process_delta_time() if moved<.003 else 0
			last=main.player.global_position
			if stagnant>1.5 or Time.get_ticks_msec()>deadline:
				print("AP WALK blocked at "+str(last)+" -> "+str(destination))
				main.player.auto_move=Vector3.ZERO
				return false
	main.player.auto_move=Vector3.ZERO
	for frame in 3: await main.get_tree().physics_frame
	return true

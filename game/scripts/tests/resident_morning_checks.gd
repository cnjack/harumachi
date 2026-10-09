extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=t.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("RESIDENT_MORNING",label,ok,detail)

func use_scene(choices: Array) -> void:
	main.player.global_position=Vector3(15.1,.1,17.75)
	main.player.velocity=Vector3.ZERO
	await t.use("resident_morning",choices)

func fresh() -> ResidentMorning:
	GameState.new_game();GameState.clock_paused=true
	GameState.quests.Q00={"state":"done","step":2}
	GameState.day=3;GameState.minute=8*60;GameState.phase="prep"
	main.world.set_region("town");main.in_room=false;GameState.player_in_room=false
	for who: String in ["haru","aoi"]:
		main.npcs[who].set_home(false);main.npcs[who].fest_key=""
		main.npcs[who].place(Layout.NPC[who].prep,0)
	main.story.daily.view.sync_state()
	var view: ResidentMorning=main.story.morning
	view.set_process(false);view.sync_tray()
	return view

func run() -> void:
	var original: Dictionary=GameState.to_dict().duplicate(true)
	var view: ResidentMorning=fresh()
	check("old saves do not invent observation, planting or tray help",not view.facts().observed and not view.facts().asked and not view.facts().helped)
	check("the optional object has a real reachable interaction entry",main.story._point("resident_morning")!=null and main.story.prompt_for("resident_morning")!="")
	GameState.minute=449
	check("the scene is absent before Aoi's actual morning schedule",not view.together() and view.prompt()=="")
	GameState.minute=450
	check("both actual residents and the visible tray open the morning scene",view.together())
	main.npcs.aoi.set_home(true)
	check("an absent resident cannot be spoken for",not view.together() and await view.move_tray(0)!="" and not view.facts().helped)
	main.npcs.aoi.set_home(false);main.npcs.aoi.place(Layout.NPC.aoi.prep,0)
	main.npcs.haru.fest_key="festival"
	check("festival stations take priority over the small life scene",not view.together())
	main.npcs.haru.fest_key="";GameState.minute=600
	check("Haru's later work does not replay the morning exchange",not view.together())
	view=fresh();main.in_room=true
	check("an interior player cannot trigger the courtyard conversation",not view.together())
	main.in_room=false
	var tray: Node3D=main.story.daily.view.tea_root
	check("both candidate tray positions have complete rendered support and no joined plant overlap",view.legal(view.target_at(0)) and view.legal(view.target_at(1)))
	check("the seemingly supported patch with joined plants is rejected",not view.legal(Vector3(15.8,1.009,16.05)))
	var original_tray: Vector3=tray.global_position
	var consequences: Dictionary={"inventory":GameState.inventory.duplicate(true),"recipes":GameState.recipes_known.duplicate(true),"q03":GameState.quests.Q03.duplicate(true),"q08":GameState.quests.Q08.duplicate(true),"crop":GameState.crop_stage,"major":DailyLife.state().last_major_day,"hearts":GameState.affinity.duplicate(true)}
	await use_scene([3])
	check("walking away neither moves the tray nor accepts a task",not view.facts().asked and not view.facts().helped and tray.global_position==original_tray)
	await use_scene([0])
	check("asking records knowledge separately from physical help",view.facts().asked and view.facts().observed and not view.facts().helped and tray.global_position==original_tray)
	await use_scene([3])
	check("cancelling at the physical choice keeps the original place",not view.facts().helped and tray.global_position==original_tray)
	await use_scene([1])
	check("one actual E choice moves the existing tray and records only the completed placement",view.facts().helped and int(view.facts().place)==0 and tray.global_position.distance_to(view.target_at(0))<.003 and tray.global_position.distance_to(original_tray)>.25)
	check("the optional help changes neither crops, recipes, inventory, quests, hearts nor the daily quota",consequences=={"inventory":GameState.inventory.duplicate(true),"recipes":GameState.recipes_known.duplicate(true),"q03":GameState.quests.Q03.duplicate(true),"q08":GameState.quests.Q08.duplicate(true),"crop":GameState.crop_stage,"major":DailyLife.state().last_major_day,"hearts":GameState.affinity.duplicate(true)})
	var after_help: Dictionary=view.facts().duplicate(true)
	await use_scene([])
	check("returning gives a short response without repeating the operation or reward",view.facts()==after_help and tray.global_position.distance_to(view.target_at(0))<.003 and not main.story.busy and not GameState.input_locked())
	GameState.flags.erase("resident_morning");tray.global_position=original_tray
	var loaded: bool=GameState.load_game();view.sync_tray()
	check("SQLite restores the actual changed place without auto-playing dialogue",loaded and view.facts().helped and tray.global_position.distance_to(view.target_at(0))<.003 and not main.story.busy)
	GameState.day+=1;GameState.minute=700;view.sync_tray()
	check("later days retain the place without treating it as a new daily task",tray.global_position.distance_to(view.target_at(0))<.003 and view.prompt()=="" and int(view.facts().helped_day)==3)
	view=fresh();tray=main.story.daily.view.tea_root
	var second_result: String=await view.move_tray(1)
	check("the second valid plan genuinely leaves a different amount of room",second_result=="" and view.facts().helped and int(view.facts().place)==1 and tray.global_position.distance_to(view.target_at(1))<.003,second_result+" together="+str(view.together()))
	view=fresh();tray=main.story.daily.view.tea_root;original_tray=tray.global_position
	var instant: bool=main.ui.instant;main.ui.instant=false
	view.move_tray(0)
	var cancel_deadline: int=Time.get_ticks_msec()+2000
	while view.active and tray.global_position.distance_to(original_tray)<.005 and Time.get_ticks_msec()<cancel_deadline:await main.get_tree().process_frame
	var moved_before_cancel: bool=view.active and tray.global_position.distance_to(original_tray)>.001
	view.aborted=true
	while view.active:await t.frames(1)
	check("interrupting a visible slide returns the same tray without claiming help",moved_before_cancel and not view.facts().helped and tray.global_position.distance_to(original_tray)<.003)
	view.move_tray(1)
	var departure_deadline: int=Time.get_ticks_msec()+2000
	while view.active and tray.global_position.distance_to(original_tray)<.005 and Time.get_ticks_msec()<departure_deadline:await main.get_tree().process_frame
	var moving_before_departure: bool=view.active and tray.global_position.distance_to(original_tray)>.001
	main.npcs.aoi.set_home(true)
	while view.active:await t.frames(1)
	check("an actor leaving mid-slide prevents fictional completion",moving_before_departure and not view.facts().helped and tray.global_position.distance_to(original_tray)<.003)
	main.ui.instant=instant;view=fresh();tray=main.story.daily.view.tea_root;original_tray=tray.global_position
	var obstruction:=MeshInstance3D.new();var block:=BoxMesh.new();block.size=Vector3(.1,.12,.1);obstruction.mesh=block;main.add_child(obstruction);obstruction.global_position=view.target_at(0)+Vector3.UP*.05
	check("a new object on the destination preserves the original tray",await view.move_tray(0)!="" and not view.facts().helped and tray.global_position==original_tray)
	obstruction.queue_free();await t.frames(2)
	var database: String=SaveDB.database_path;var backup: String=SaveDB.backup_path
	var blocked: String=SaveDB.directory.path_join("blocked-morning.db");DirAccess.make_dir_recursive_absolute(blocked)
	SaveDB.database_path=blocked;SaveDB.backup_path=SaveDB.directory.path_join("missing-morning-backup.db")
	var failed: String=await view.move_tray(0)
	SaveDB.database_path=database;SaveDB.backup_path=backup;DirAccess.remove_absolute(blocked)
	check("failed save rolls back the physical place and the help fact",failed.contains("进度还没有保存") and not view.facts().helped and tray.global_position==original_tray and not view.active,failed)
	var recovered: String=await view.move_tray(0)
	check("a recovered save can commit the same operation once",recovered=="" and view.facts().helped,recovered+" together="+str(view.together()))
	var new_block:=MeshInstance3D.new();new_block.mesh=block;main.add_child(new_block);new_block.global_position=view.target_at(0)+Vector3.UP*.05
	view.sync_tray()
	check("a later obstacle retains historical help but does not claim the empty place is still valid",view.facts().helped and not view.placed_now and view.prompt().contains("又放了东西") and tray.global_position.distance_to(view.original_tray)<.003)
	new_block.queue_free();await t.frames(2);view.sync_tray()
	check("removing that obstacle restores the saved place without repeating help",view.placed_now and tray.global_position.distance_to(view.target_at(0))<.003)
	view=fresh();original_tray=tray.global_position
	DirAccess.make_dir_recursive_absolute(blocked);SaveDB.database_path=blocked;SaveDB.backup_path=SaveDB.directory.path_join("missing-morning-backup.db")
	await use_scene([0])
	SaveDB.database_path=database;SaveDB.backup_path=backup;DirAccess.remove_absolute(blocked)
	check("failed question save does not claim a persisted explanation or physical help",not view.facts().asked and not view.facts().helped and tray.global_position==original_tray and not main.story.busy)
	view=fresh();main.ui.instant=false
	var support: Node3D=main.world.get_node("P08")
	view.move_tray(0)
	await main.get_tree().process_frame
	var moving_without_support: bool=view.active
	main.world.remove_child(support)
	while view.active:await main.get_tree().process_frame
	check("removing the support during a slide cancels safely without a completed help fact",moving_without_support and not view.facts().helped and tray.global_position.distance_to(view.original_tray)<.003)
	main.world.add_child(support);main.ui.instant=instant
	view=fresh();main.ui.instant=false
	var replacement: Node3D=tray.duplicate();var tray_parent: Node=tray.get_parent()
	view.move_tray(0)
	await main.get_tree().process_frame
	var moving_before_removal: bool=view.active
	tray.queue_free();await main.get_tree().process_frame
	while view.active:await main.get_tree().process_frame
	check("a freed tray cancels the async action without a stale-object access",moving_before_removal and not view.facts().helped and not view.active)
	tray_parent.add_child(replacement);main.story.daily.view.tea_root=replacement
	main.story.daily.view.tea_label=replacement.find_children("*","Label3D",true,false)[0]
	tray=replacement;main.ui.instant=instant
	view=fresh();main.player.global_position=Vector3(15.1,.1,17.75)
	var prior_camera: Camera3D=main.get_viewport().get_camera_3d()
	var observe_camera:=Camera3D.new();main.add_child(observe_camera)
	observe_camera.global_position=Vector3(10.4,4.5,23.8);observe_camera.fov=46
	observe_camera.look_at(Vector3(14.4,1.0,16.8));observe_camera.make_current()
	view.bubble.visible=true;view.seen_seconds=0.0
	view._process(.6);view._process(.6)
	check("a brief camera sweep does not invent a readable observation",view.readable() and not view.facts().observed)
	observe_camera.look_at(observe_camera.global_position+Vector3.BACK)
	view._process(.3)
	observe_camera.look_at(Vector3(14.4,1.0,16.8))
	view._process(1.1)
	check("looking away resets the continuous observation instead of accumulating glimpses",not view.facts().observed)
	view._process(1.0)
	check("two visible residents and continuously readable words can record observation without a quest or lock",view.facts().observed and not view.facts().asked and not view.facts().helped and not GameState.input_locked())
	prior_camera.make_current();observe_camera.queue_free()
	GameState.from_dict(original);GameState.clock_paused=true
	view.set_process(true);main._restore();view.sync_tray()

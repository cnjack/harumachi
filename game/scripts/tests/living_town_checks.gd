extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("LIVING",label,ok,detail)
func supports(object: Object,property: String) -> bool:return object.get_property_list().any(func(p: Dictionary):return p.name==property)

func run() -> void:
	var saved: Dictionary=GameState.to_dict().duplicate(true)
	var old_position: Vector3=main.player.global_position
	var old_region: String=main.world.region
	var old_room: bool=main.in_room
	GameState.new_game();GameState.clock_paused=true;GameState.minute=600;main.in_room=false;main.world.set_region("town")
	check("unpacking is no longer playable or listed",not GameState.MINIGAMES.has("unpack") and t.point("house_boxes")==null)
	var old_money:=GameState.coins
	GameState.minigames={"unpack":{"stars":3},"onigiri":{"stars":1}}
	check("old unpack rewards remain saved without inflating the active star total",GameState.mg_total_stars()==1 and GameState.coins==old_money and int(GameState.minigames.unpack.stars)==3)
	GameState.minigames={}
	for game_id: String in GameState.MINIGAMES:GameState.minigames[game_id]={"stars":3}
	check("all-three-star achievement is reachable with the four remaining games",Progress.holds("mg_all>=3") and Progress.MG_IDS.size()==4 and str(Progress.ach_by_id["mg_all_3"].desc).begins_with("4"))
	GameState.minigames={}
	check("six additional homes separate residential and commercial areas",Layout.BUILDINGS.filter(func(spec: Array):return float(spec[2])>32).size()>=6)
	check("town map covers the far end of the residential street",LakesideLayout.TOWN_BOUNDS.has_point(Vector2(19.7,81)))
	await t.frames(4)
	var space: PhysicsDirectSpaceState3D=main.get_world_3d().direct_space_state
	var route: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(19.7,.8,30),Vector3(19.7,.8,82),WorldBuilder.L_SOLID|WorldBuilder.L_BLOCK))
	check("the lane is physically open from old homes to South Town",route.is_empty(),str(route.get("position","")))
	var terrain: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(19.7,4,79),Vector3(19.7,-2,79),WorldBuilder.L_GROUND))
	check("new homes have a rendered walkable street",not terrain.is_empty() and absf((terrain.get("position",Vector3.INF) as Vector3).y)<.1)
	var bus: Node=main.world.get_node_or_null("CountryBus")
	check("arrival has a vehicle with independently moving doors and wheels",bus!=null and bus.get("doors").size()==2 and bus.get("wheels").size()==4)
	if bus!=null:
		bus.call("open_doors",1.0);check("bus door animation changes the leaf transforms",absf((bus.get("doors")[0] as Node3D).rotation.y)>1.0);bus.call("open_doors",0.0)
	else:check("bus door animation changes the leaf transforms",false)
	if bus!=null and supports(bus,"left_town"):
		bus.call("park_at_stop");main.world.set_region("farm");main.world.set_region("town");await t.frames(2)
		check("bus stays parked when returning to town",(bus as Node3D).visible and not bool(bus.get("travelling")))
		bus.set("left_town",false);(bus as Node3D).visible=true
	else:check("a departed bus stays hidden when returning to town",false)
	var flock: Dictionary=main.life.flocks[0];var bird: Dictionary=flock.birds[0]
	check("sparrow flight has two articulated wings",bird.has("anim") and (bird.get("anim") as RefCounted).get("wings").size()==2)
	if bird.has("anim"):
		bird.anim.set("phase",0.0)
		var grounded_body: Transform3D=(bird.node as Node3D).transform
		bird.anim.call("update",.04,true);var wings: Array=bird.anim.get("wings")
		check("wing poses change independently of the grounded body",(wings[0] as Node3D).visible and absf((wings[0] as Node3D).rotation.z)>.3 and (bird.node as Node3D).transform.is_equal_approx(grounded_body));bird.anim.call("update",.04,false)
	else:check("wing poses change independently of the grounded body",false)
	var cat: Dictionary=main.life.cats[1]
	main.player.global_position=(cat.node as Node3D).global_position+Vector3(2,-1,2)
	var base: Transform3D=(cat.node as Node3D).transform
	main.life.call("_process",.2)
	check("watching cats keep body and paws planted while looking",(cat.node as Node3D).transform.is_equal_approx(base) and cat.has("anim"))
	var modern_pool:=GameState.has_method("spot_fish_pool")
	check("same river has different shallow and bend fish communities",modern_pool and GameState.call("spot_fish_pool","fish_river",8,"sunny")!=GameState.call("spot_fish_pool","fish_bend",8,"sunny"))
	check("lake pier and reed beds have different catches",modern_pool and GameState.call("spot_fish_pool","fish_pier",20,"sunny")!=GameState.call("spot_fish_pool","fish_reeds",20,"sunny"))
	GameState.borrow_fishing_kit()
	var session: RefCounted=FishingSession.new("fish_river");session.call("tap",0.0,.5);session.set("wait_seconds",.01)
	for i in 16:session.call("step",.05,false)
	session.call("tap")
	for i in 850:
		if int(session.get("state"))!=FishingSession.State.REEL:break
		session.call("step",.05,true)
	check("holding reel continuously cannot land a fish",session.get("state")==FishingSession.State.MISSED and GameState.count("fish_crucian")==0)
	session.call("close")
	var tracking:=session.has_method("suggested_hold")
	var outcomes: Array[String]=[]
	if tracking:
		for location: String in ["fish_river","fish_bend","fish_pier","fish_reeds"]:
			GameState.minute=20*60;GameState.add_item("fishing_bait",1,true)
			var attempt: RefCounted=FishingSession.new(location);attempt.call("tap",.999,.8);attempt.set("wait_seconds",.01)
			for i in 16:attempt.call("step",.05,false)
			attempt.call("tap")
			for i in 850:
				if attempt.get("state")!=FishingSession.State.REEL:break
				attempt.call("step",.05,bool(attempt.call("suggested_hold")))
			if attempt.get("state")!=FishingSession.State.LANDED:outcomes.append(location+": "+str(attempt.get("message")))
			attempt.call("close")
	check("tracking and tension control can catch fish in every water area",tracking and outcomes.is_empty(),str(outcomes))
	var fish_art:=true
	for species: String in GameState.fish_db:
		var texture: Texture2D=UITheme.icon_texture(species)
		fish_art=fish_art and texture is AtlasTexture and texture.get_image().get_pixel(0,0).a<.10
	check("fish rewards use six transparent anime sprites",fish_art)
	check("every fish species has a distinct movement profile",GameState.fish_db.values().all(func(row: Dictionary):return row.has("behaviour")) and GameState.fish_db.size()==6)
	var today: Dictionary=GameState.daily.get("fish_items",{})
	check("landed fish are counted in today's report",tracking and today.values().reduce(func(a: int,b: int):return a+b,0)==4)
	var summary_script: Script=load("res://scripts/ui/day_summary.gd") if ResourceLoader.exists("res://scripts/ui/day_summary.gd") else null
	if summary_script!=null:
		GameState.ledger={"in":180,"out":35};GameState.daily["xp"]=12
		var report: Dictionary=summary_script.call("capture")
		GameState.daily["fish_items"]={}
		check("night report captures actual income expenses and immutable item counts",report.income==180 and report.expense==35 and report.xp==12 and report.fish.size()>0)
		GameState.daily["fish_items"]=report.fish.duplicate(true);GameState.advance_day()
		var snapshot_report: Dictionary=GameState.flags.get("last_day_summary",{})
		check("summary is saved before daily counters reset",snapshot_report.get("income",0)==180 and snapshot_report.get("fish",{}).size()>0 and GameState.daily.get("fish_items",{}).is_empty())
		GameState.load_game();check("the last night report survives a SQLite reload",GameState.flags.get("last_day_summary",{}).get("expense",0)==35)
	else:
		check("night report captures actual income expenses and immutable item counts",false)
		check("summary is saved before daily counters reset",false)
		check("the last night report survives a SQLite reload",false)
	var photo: Node=main.get("photo") if supports(main,"photo") else null
	if photo!=null:
		GameState.clear_locks();GameState.clock_paused=false;main.ui.ambient_layer.visible=true
		photo.call("toggle")
		await t.frames(2)
		check("photo mode pauses time and removes HUD pins and NPC names",bool(photo.get("active")) and GameState.clock_paused and not main.ui.ambient_layer.visible and not main.marker.visible and main.npcs.values().all(func(n: NPC):return not n.tag.visible))
		photo.call("finish");await t.frames(2)
		check("leaving photo mode restores camera time and input",not GameState.input_locked() and not GameState.clock_paused and main.rig.cam.current and main.ui.ambient_layer.visible)
	else:
		check("photo mode pauses time and removes HUD pins and NPC names",false)
		check("leaving photo mode restores camera time and input",false)
	var shortcut: Node=main.ui.hud.find_child("Shortcuts",true,false)
	check("movement hints and shortcut buttons use symbols with key labels",main.ui.hint_label.text=="" and shortcut!=null and shortcut.find_child("Shortcut_camera",true,false)!=null and (shortcut.find_child("Shortcut_map",true,false) as Button).text=="M")
	GameState.from_dict(saved);main.player.global_position=old_position;main.in_room=old_room;main.world.set_region(old_region)

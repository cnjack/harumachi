extends RefCounted
var t: Node
var G: Node
var main: Node

func _init(runner: Node) -> void:
	t=runner;G=GameState;main=runner.main

func check(name:String,ok:bool,detail:String="")->void:
	t.check("LAKE",name,ok,detail)

func _pool_ids(pool:Array)->Array:
	return pool.map(func(row:Dictionary):return str(row.id))

func _tick(session:FishingSession,seconds:float,held:bool=false)->void:
	for i in ceili(seconds/.05):session.step(.05,held)

func run() -> void:
	var snapshot:Dictionary=G.to_dict().duplicate(true)
	var old_position:Vector3=main.player.global_position
	var old_region:String=main.world.region
	G.new_game();G.clock_paused=true;G.minute=600.0
	check("outdoor land includes the lake and new residential street",LakesideLayout.expansion_ratio()>=2.0 and LakesideLayout.expansion_ratio()<=4.0,"%.3f"%LakesideLayout.expansion_ratio())
	check("lake has an actual depression below its water surface",LakesideLayout.height_at(LakesideLayout.LAKE_CENTER)<LakesideLayout.WATER_Y-.5)
	check("river flows continuously into the lake",LakesideLayout.water_distance(Vector2(72,19))<0 and LakesideLayout.water_distance(Vector2(78,19))<0)
	var spots_ok:=true
	for spot_id:String in LakesideLayout.SPOTS:
		var spec:Dictionary=LakesideLayout.SPOTS[spot_id]
		spots_ok=spots_ok and t.point(spot_id)!=null and LakesideLayout.BOUNDS.has_point(spec.stand) and LakesideLayout.water_distance(spec["float"])<-.5
	check("all four fishing spots exist and cast into actual water",spots_ok)
	check("six fish and usable kitchen recipes are configured",G.fish_db.size()==6 and G.recipe_known("grilled_ayu") and G.recipe_known("crucian_soup") and G.recipe_known("trout_rice"))
	var noon_lake:=_pool_ids(G.fish_pool("lake",12,"sunny"))
	var noon_river:=_pool_ids(G.fish_pool("river",12,"sunny"))
	check("lake and river have distinct fish pools",noon_lake.has("fish_carp") and not noon_river.has("fish_carp") and noon_river.has("fish_ayu") and not noon_lake.has("fish_ayu"))
	check("eel appears in the evening but not at noon",not noon_lake.has("fish_eel") and _pool_ids(G.fish_pool("lake",20,"sunny")).has("fish_eel"))
	var rain:Array=G.fish_pool("river",8,"rain")
	var sunny:Array=G.fish_pool("river",8,"sunny")
	var rain_weight:=0.0;var sun_weight:=0.0
	for row:Dictionary in rain:
		if row.id=="fish_trout":rain_weight=float(row.weight)
	for row:Dictionary in sunny:
		if row.id=="fish_trout":sun_weight=float(row.weight)
	check("rain changes trout availability weight",rain_weight>sun_weight and sun_weight>0)
	check("the starter kit is given once",G.borrow_fishing_kit()=="" and G.has("fishing_rod") and G.count("fishing_bait")==10 and G.borrow_fishing_kit()=="" and G.count("fishing_bait")==10)
	var start_minute:float=G.minute
	var session:=FishingSession.new("fish_river")
	session.tap(0,.5)
	var used_ticket:=session.ticket
	check("casting spends one bait and twelve minutes",G.count("fishing_bait")==9 and G.minute==start_minute+12 and used_ticket>0)
	check("a second cast cannot double-spend while a line is active",G.begin_fishing("fish_river").has("error") and G.count("fishing_bait")==9)
	session.wait_seconds=.05;session.tap();_tick(session,.85)
	check("early taps never award a fish",G.count("fish_crucian")==0 and session.state==FishingSession.State.BITE)
	session.tap()
	for i in 350:
		if session.state!=FishingSession.State.REEL:break
		session.step(.05,session.suggested_hold())
	check("the timing and tension game can land an actual inventory fish",session.state==FishingSession.State.LANDED and G.count("fish_crucian")==1 and int(G.fishing.landed)==1,session.message)
	check("catch completion cannot award the same ticket twice",G.land_fish(used_ticket,1).has("error") and G.count("fish_crucian")==1)
	check("invalid negative catch tickets are harmless",G.land_fish(-1,1).has("error"))
	var timed:=FishingSession.new("fish_river");timed.tap(0,.3);timed.wait_seconds=.01;_tick(timed,4)
	check("missing a bite consumes the cast without inventing a catch",timed.state==FishingSession.State.MISSED and G.count("fish_crucian")==1 and G.count("fishing_bait")==8)
	var cut:=FishingSession.new("fish_river");cut.tap(0,.3);cut.close()
	check("cancelling clears the active line and does not award fish",G._fishing_ticket.is_empty() and G.count("fish_crucian")==1 and G.count("fishing_bait")==7)
	var full_snapshot:Dictionary=G.to_dict().duplicate(true)
	G.inventory={"washi":G.STACK_MAX*G.bag_cap,"fishing_bait":1}
	var full_min:float=G.minute
	check("full bags reject a cast without losing bait or time",G.begin_fishing("fish_river",0,.3).has("error") and G.count("fishing_bait")==1 and G.minute==full_min)
	G.from_dict(full_snapshot)
	var active:Dictionary=G.begin_fishing("fish_river",0,.2)
	G.inventory={"washi":G.STACK_MAX*G.bag_cap}
	check("a bag filled during a cast releases the fish safely",G.land_fish(int(active.ticket),1).has("error") and int(G.fishing.landed)==1)
	G.from_dict(full_snapshot)
	var old_coins:int=G.coins
	var pay:int=G.sell_produce("fish_crucian",1,1.0)
	check("caught fish sell for actual coins at both buyers",G.buys_item("store","fish_crucian") and G.buys_item("lakeside","fish_crucian") and pay==18 and G.coins==old_coins+18 and G.count("fish_crucian")==0)
	for recipe_id:String in ["grilled_ayu","crucian_soup","trout_rice","carp_kanroni","butter_bass","eel_rice"]:
		var recipe:Dictionary=G.recipe(recipe_id)
		for iid:String in recipe.inputs:G.add_item(iid,int(recipe.inputs[iid]),true)
		var error:String=G.craft(recipe_id,1)
		check("fresh fish cooks through the normal kitchen: "+recipe_id,error=="" and G.count(recipe_id)==1,error)
	var caught_before:int=G.fishing.caught.get("fish_crucian",0)
	var best_before:float=G.fishing.best_cm.get("fish_crucian",0)
	check("fish records serialize and restore",G.from_dict(G.to_dict().duplicate(true)) and G.fishing.caught.get("fish_crucian",0)==caught_before and G.fishing.best_cm.get("fish_crucian",0)==best_before)
	var saved_ok:bool=G.save_game()
	G.fishing={"casts":0,"landed":0,"caught":{},"best_cm":{}}
	var loaded_ok:bool=G.load_game()
	check("caught fish records survive a real SQLite save and load",saved_ok and loaded_ok and G.fishing.caught.get("fish_crucian",0)==caught_before and is_equal_approx(float(G.fishing.best_cm.get("fish_crucian",0)),best_before),"save=%s load=%s record=%s / %.3f; %s"%[saved_ok,loaded_ok,str(G.fishing),best_before,G.last_error])
	var legacy:Dictionary=G.to_dict().duplicate(true);legacy.erase("fishing")
	check("older v4 saves load with empty fishing records",G.from_dict(legacy) and int(G.fishing.landed)==0 and G.fishing.caught.is_empty())
	G.new_game();G.clock_paused=true;G.minute=600;G.borrow_fishing_kit()
	main.world.set_region("farm");G.player_region="farm"
	main.player.global_position=FarmBuilder.ORIGIN+Vector3(10,.15,12)
	await t.frames(10)
	var space:PhysicsDirectSpaceState3D=main.get_world_3d().direct_space_state
	var ray:=PhysicsRayQueryParameters3D.create(FarmBuilder.ORIGIN+Vector3(115,10,-15),FarmBuilder.ORIGIN+Vector3(115,-3,-15),WorldBuilder.L_GROUND)
	var hit:Dictionary=space.intersect_ray(ray)
	check("expanded hills have walkable collision at the rendered height",not hit.is_empty() and absf((hit.get("position",Vector3.ZERO) as Vector3).y-LakesideLayout.height_at(Vector2(115,-15)))<.12)
	var blocked:Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(FarmBuilder.ORIGIN+Vector3(10,1,11),FarmBuilder.ORIGIN+Vector3(10,1,17),WorldBuilder.L_BLOCK))
	var bridge_clear:Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(FarmBuilder.ORIGIN+Vector3(0,1,12),FarmBuilder.ORIGIN+Vector3(0,1,22),WorldBuilder.L_BLOCK))
	check("shore prevents walking into water while the old bridge stays open",not blocked.is_empty() and bridge_clear.is_empty())
	var east_edge:Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(FarmBuilder.ORIGIN+Vector3(140,1,18),FarmBuilder.ORIGIN+Vector3(125,1,18),WorldBuilder.L_BLOCK))
	check("lake shore also has player collision",not east_edge.is_empty())
	var route_blocked:Array=[]
	for route:PackedVector2Array in LakesideLayout.walk_paths():
		for i in route.size()-1:
			var a:Vector2=route[i];var b:Vector2=route[i+1]
			var from:=FarmBuilder.ORIGIN+Vector3(a.x,LakesideLayout.height_at(a)+.85,a.y)
			var to:=FarmBuilder.ORIGIN+Vector3(b.x,LakesideLayout.height_at(b)+.85,b.y)
			var obstacle:Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,WorldBuilder.L_SOLID|WorldBuilder.L_BLOCK))
			if not obstacle.is_empty():route_blocked.append([a,b,str(obstacle.collider.get_path())])
	check("the full lakeside walking loop has clear route segments",route_blocked.is_empty(),str(route_blocked))
	main.player.global_position=FarmBuilder.ORIGIN+Vector3(94,.15,46.8);main.player.velocity=Vector3.ZERO
	main.player.auto_move=Vector3(0,0,-1);main.player.auto_run=true
	for i in 250:
		await t.frames(1)
		if main.player.global_position.z<38.0:break
	main.player.auto_move=Vector3.ZERO;main.player.auto_run=false
	check("player can physically walk from shore to the pier fishing point",main.player.global_position.z<38.3 and main.player.global_position.y>LakesideLayout.WATER_Y+.1,str(main.player.global_position-FarmBuilder.ORIGIN))
	main.player.global_position=FarmBuilder.ORIGIN+Vector3(10,.15,12);main.player.velocity=Vector3.ZERO
	await t.frames(3)
	check("minimap follows the farm's real local coordinates",main.ui.minimap.canvas.local_player().distance_to(Vector2(10,12))<1.0 and main.ui.minimap.canvas.map_region()=="farm")
	main.ui.open_world_map();await t.frames(3)
	check("M map uses a modal input lock and closes cleanly",main.ui.modal=="map" and G.input_locked())
	main.ui.close_modal();await t.frames(2)
	var bait_before:int=G.count("fishing_bait")
	main.story.call_deferred("interact",t.point("fish_river"))
	await t.frames(5)
	check("world interaction opens the actual fishing panel and rod",main.ui.modal=="fishing" and is_instance_valid(main.ui.fishing_panel) and is_instance_valid(main.get_node_or_null("Fishing_view")))
	check("fishing overlay has a visible viewport-sized layout",is_instance_valid(main.ui.fishing_panel) and main.ui.fishing_panel.get_global_rect().size.x>=main.ui.root.size.x*.9 and main.ui.fishing_panel.get_global_rect().size.y>=main.ui.root.size.y*.9,str(main.ui.fishing_panel.get_global_rect()) if is_instance_valid(main.ui.fishing_panel) else "missing")
	if is_instance_valid(main.ui.fishing_panel):
		var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.physical_keycode=KEY_ESCAPE;key.pressed=true;Input.parse_input_event(key)
		await t.frames(6)
		var release:=InputEventKey.new();release.keycode=KEY_ESCAPE;release.physical_keycode=KEY_ESCAPE;release.pressed=false;Input.parse_input_event(release)
	check("escape before casting restores movement without spending bait",main.ui.modal=="" and not main.story.busy and not main.player.frozen and not G.input_locked() and G.count("fishing_bait")==bait_before,"modal=%s busy=%s frozen=%s locked=%s"%[main.ui.modal,main.story.busy,main.player.frozen,G.input_locked()])
	G.from_dict(snapshot);main.world.set_region(old_region);main.player.global_position=old_position

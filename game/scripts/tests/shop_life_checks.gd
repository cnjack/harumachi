extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("SHOP_LIFE",label,ok,detail)
func run() -> void:
	var life: Node=main.get_node_or_null("ShopLife")
	check("shops have a shared living-business controller",life!=null)
	check("store shelves have solid grocery and produce models",main.world.interiors.store.find_children("StockProduct_*","Node3D",true,false).size()>=12)
	check("bakery displays include new bread, donuts and cake",main.world.interiors.bakery.find_children("StockProduct_*","Node3D",true,false).size()>=12)
	check("posters are actually mounted in both playable shops",main.world.interiors.store.find_children("ShopPoster_*","Node3D",true,false).size()>=2 and main.world.interiors.bakery.find_children("ShopPoster_*","Node3D",true,false).size()>=1)
	check("television is an actual 3D model with a live screen",life!=null and life.get("content").televisions.size()>=1)
	check("welcome lines have recorded speech",ResourceLoader.exists("res://assets/audio/voice/ren/%s.ogg"%"欢迎光临！面包刚出炉，先闻闻香。".md5_text()))
	if life==null:return
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--shop-support-debug="):continue
		var audit: GDScript=load("res://scripts/tests/prop_audit.gd")
		var details: Array=[]
		for entry: Dictionary in life.content.products:
			if audit.mount_supported(entry.node,entry.support):continue
			var hull: PackedVector2Array=audit.footprint(entry.node)
			var centre: Vector2=audit._centroid(hull)
			details.append({"product":str(entry.node.get_path()),"support":str(entry.support.get_path()),"model":entry.node.get_meta("model_id"),"position":str(entry.node.global_position),"centre":str(centre),"base":audit.base_y(entry.node),"declared_height":entry.height,"raw_triangle_height":WorldBuilder.surface_height(entry.support,centre,entry.height+.025),"flat_triangle_height":WorldBuilder.rendered_support_height(entry.support,Vector3(centre.x,0,centre.y),entry.height+.025),"support_path":str(entry.node.get_meta("support_surface"))})
		var debug_file:=FileAccess.open(argument.trim_prefix("--shop-support-debug="),FileAccess.WRITE)
		debug_file.store_string(JSON.stringify(details,"  "))
	var snapshot: Dictionary=GameState.to_dict().duplicate(true)
	GameState.day=1;GameState.minute=600;GameState.weather="sunny";life.tick(0.0)
	var tv: Dictionary=life.content.televisions[0]
	check("an open shop broadcasts on its television",bool(tv.screen.material_override.get_shader_parameter("broadcast_on")))
	GameState.weather="rain";life.tick(0.0)
	check("weather changes reach the television forecast",tv.screen.material_override.get_shader_parameter("rain_amount")==1.0)
	GameState.minute=21*60;life.tick(0.0)
	check("closing hours switch television to standby",not bool(tv.screen.material_override.get_shader_parameter("broadcast_on")))
	GameState.minute=600;GameState.weather="sunny";life.tick(0.0)
	var morning_count: int=life.content.visible_products("bakery")
	GameState.minute=17*60;life.tick(0.0)
	check("the afternoon display has fewer portions than the fresh morning",life.content.visible_products("bakery")<morning_count)
	check("food products are real meshes rather than product image fronts",life.content.products.all(func(entry: Dictionary):return not WorldBuilder.find_meshes(entry.node).is_empty() and entry.node.find_children("*","Sprite3D",true,false).is_empty()))
	check("all stocked products rest on measured shelves or counters",life.content.supported())
	check("separate cake tiers are distinct volumes while intersecting cakes still fail",not PropAudit.volumes_share_height(.60,.732,.84,.972) and PropAudit.volumes_share_height(.60,.732,.70,.832))
	check("new display furniture leaves the entry and keeper walk clear",life.content.walkways_clear())
	GameState.minute=600;GameState.day=1
	if main.in_room:await main.exit_room()
	await main.enter_interior("bakery");await t.frames(4)
	var spoke: bool=life.greeting_count>0
	check("entering an open staffed bakery triggers its actual welcome",spoke)
	var count_before: int=life.greeting_count
	life.greet("bakery",true);life.greet("bakery",true)
	check("repeated welcomes are throttled",life.greeting_count==count_before)
	main.story.busy=true;life.last_greeting["store"]=-999.0
	check("story dialogue blocks ambient sales calls",not life.greet("store",true))
	main.story.busy=false
	main.update_npcs(true)
	var keeper_spec: Dictionary=InteriorBuilder.spec_for("bakery")
	check("forced story positioning returns the keeper to the exact counter",main.npcs.ren.global_position.distance_to(keeper_spec.origin+keeper_spec.keeper)<.08)
	var played: bool=await life.perform_work("bakery",true)
	check("keeper performs an actual collision-checked work trip",played and life.completed_trips>0)
	check("keeper returns behind the counter after the work trip",main.npcs.ren.global_position.distance_to(keeper_spec.origin+keeper_spec.keeper)<.08)
	check("completing a work trip actually replenishes the display",life.content.restock_count>0)
	check("new foods are offered by their appropriate real shops",GameState.shop_stock("bakery").has("donut") and GameState.shop_stock("bakery").has("cream_bun") and GameState.shop_stock("store").has("sushi_box") and GameState.shop_stock("store").has("bento"))
	GameState.coins=1000
	var owned: int=GameState.count("donut")
	check("buying a new food charges the advertised amount and grants one portion",GameState.buy_item("donut",1)=="" and GameState.count("donut")==owned+1 and GameState.coins==955)
	check("new shop foods have native UI-kit icons and a solid serving model",UITheme.icon_texture("shop_donut")!=null and MealModels.model_id("donut")=="B07_iced_donut")
	await main.exit_room();GameState.from_dict(snapshot)

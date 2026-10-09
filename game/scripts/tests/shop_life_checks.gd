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
	var screen_vertices:=PackedVector3Array()
	if tv.screen.mesh is ArrayMesh:screen_vertices=tv.screen.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var depth_min:=INF;var depth_max:=-INF
	for vertex: Vector3 in screen_vertices:
		depth_min=minf(depth_min,vertex.z);depth_max=maxf(depth_max,vertex.z)
	check("television picture uses a curved surface rather than a flat card",screen_vertices.size()>100 and depth_max-depth_min>.012)
	var fit_error: float=INF
	if screen_vertices.size()>100:
		fit_error=0.0
		for index: int in [screen_vertices.size()/4,screen_vertices.size()/2,screen_vertices.size()*3/4]:
			var point: Vector3=screen_vertices[index]+tv.screen.position
			var height: float=_front_surface(tv.node,Vector2(point.x,point.y),tv.screen)
			fit_error=maxf(fit_error,absf(point.z-height))
	check("live picture lies within four millimetres of the actual television glass",fit_error<.004 and tv.screen.get_meta("measured_source_sha256","")==FileAccess.get_sha256("res://assets/models/W18_retro_tv.glb"),str(fit_error))
	var snow: Variant=tv.screen.material_override.get_shader_parameter("snow_amount")
	check("powered television has a nonzero animated snow signal",snow is float and float(snow)>=.04)
	var store_ids: Dictionary={};var bakery_ids: Dictionary={};var stock_turns: Dictionary={};var gondola_rows: Dictionary={}
	for entry: Dictionary in life.content.products:
		var item_id: String=str(entry.node.get_meta("model_id",""))
		if entry.kind=="store":
			if item_id.begins_with("W") and item_id!="W12_cedar_tray":store_ids[item_id]=true
			stock_turns[snappedf(rad_to_deg(entry.node.rotation.y),.5)]=true
			if entry.support.get_meta("model_id","")=="P_gondola":
				var row_key: String="%d:%.2f"%[entry.support.get_instance_id(),snappedf(float(entry.height),.02)]
				gondola_rows[row_key]=int(gondola_rows.get(row_key,0))+1
		elif item_id.begins_with("B"):bakery_ids[item_id]=true
	check("store carries at least eight independent kinds of solid goods",store_ids.size()>=8,str(store_ids.keys()))
	check("bakery has at least six bread and pastry shapes",bakery_ids.size()>=6,str(bakery_ids.keys()))
	check("stocked goods do not all share one repeated facing",stock_turns.size()>=4,str(stock_turns.keys()))
	var row_counts: Dictionary={}
	for quantity: int in gondola_rows.values():row_counts[quantity]=true
	check("gondola rows do not all repeat the same quantity and spacing",row_counts.size()>=2,str(gondola_rows))
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

func _front_surface(root: Node3D,point: Vector2,excluded: Node3D) -> float:
	var best: float=-INF
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		if mesh==excluded or excluded.is_ancestor_of(mesh):continue
		var transform: Transform3D=root.global_transform.affine_inverse()*mesh.global_transform
		var faces: PackedVector3Array=mesh.mesh.get_faces()
		for offset: int in range(0,faces.size(),3):
			var a: Vector3=transform*faces[offset];var b: Vector3=transform*faces[offset+1];var c: Vector3=transform*faces[offset+2]
			var edge_b: Vector3=b-a;var edge_c: Vector3=c-a
			var determinant: float=edge_b.x*edge_c.y-edge_b.y*edge_c.x
			if absf(determinant)<.000000001:continue
			var delta: Vector2=point-Vector2(a.x,a.y)
			var u: float=(delta.x*edge_c.y-delta.y*edge_c.x)/determinant
			var v: float=(edge_b.x*delta.y-edge_b.y*delta.x)/determinant
			if u>=-.000001 and v>=-.000001 and u+v<=1.000001:best=maxf(best,a.z+u*edge_b.z+v*edge_c.z)
	return best

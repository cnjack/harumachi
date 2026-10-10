extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("INHABITED",label,ok,detail)
func run() -> void:
	var rooms: Dictionary=main.world.interiors
	check("community has a shared table and six actual chairs",rooms.workroom.find_children("SharedNeighbourTable","Node3D",true,false).size()==1)
	check("community has a furnished reading corner",rooms.workroom.find_children("ReadingChair_*","Node3D",true,false).size()==2 and rooms.workroom.find_children("NeighbourBookcase","Node3D",true,false).size()==1)
	check("community has a separate tea and washing station",rooms.workroom.find_children("NeighbourTeaStation","Node3D",true,false).size()==1)
	check("trial beam fits below the community ceiling",float(InteriorBuilder.spec_for("workroom").get("ceiling_height",2.8))>3.05)
	check("bakery has two usable cafe table groups",rooms.bakery.find_children("CafeTable_*","Node3D",true,false).size()==2)
	check("bakery has an espresso machine and grinder in its service area",rooms.bakery.find_children("EspressoStation","Node3D",true,false).size()==1)
	var cakes: Dictionary={};var milk_cold:=true;var dry_night:=true
	var content: ShopContent=main.shop_life.content
	for entry: Dictionary in content.products:
		var id: String=entry.node.get_meta("model_id","")
		if entry.kind=="bakery" and id in ["B12_strawberry_slice","B13_chocolate_slice","B14_basque_slice","B15_fruit_tart"]:cakes[id]=true
		if entry.kind=="store" and id in ["W20_milk_carton","W23_egg_carton"]:milk_cold=milk_cold and entry.support.get_meta("model_id","")=="I03_drink_fridge"
	check("cake case carries four distinct patisserie silhouettes",cakes.size()==4,str(cakes.keys()))
	check("milk and eggs are stocked inside the actual cold cabinet",milk_cold)
	var snapshot: Dictionary=GameState.to_dict().duplicate(true)
	GameState.minute=21*60;content.update(0.0)
	for entry: Dictionary in content.products:
		if entry.kind=="store" and entry.node.get_meta("model_id","") in ["W19_flour_bag","W09_rice_sacks","W22_soy_bottle"]:dry_night=dry_night and entry.node.visible
	check("closing the shop does not make ambient pantry stock disappear",dry_night)
	check("desserts and coffee are offered by the real bakery shop",GameState.shop_stock("bakery").has("chocolate_cake") and GameState.shop_stock("bakery").has("basque_cheesecake") and GameState.shop_stock("bakery").has("fruit_tart") and GameState.shop_stock("bakery").has("coffee") and GameState.shop_stock("bakery").has("cafe_latte"))
	check("coffee is a drink in the backpack and never mistaken for a plated meal",not DailyLife.edible("coffee") and not DailyLife.edible("cafe_latte") and GamePanels.kind("coffee")=="dish")
	var levels: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/_stats/_level.json"))
	var desserts_level:=true
	for id: String in ["B12_strawberry_slice","B13_chocolate_slice","B14_basque_slice","B15_fruit_tart"]:
		var data: Dictionary=levels.get(id,{})
		desserts_level=desserts_level and float(data.get("base_frac",0))>=.30 and float(data.get("tilt",99))<2.0
	var tart: Node3D=WorldBuilder.model_scene("B15_fruit_tart").instantiate()
	desserts_level=desserts_level and WorldBuilder.local_aabb(tart).size.y<=.065;tart.free()
	check("desserts have measured level bases and the tart has no lower shadow debris",desserts_level)
	var route_failures: Array[String]=[]
	for kind: String in ["workroom","bakery"]:
		for point: Interactable in rooms[kind].find_children("public_*","Interactable",true,false):
			var finish: Vector3=point.global_position;finish.y=rooms[kind].origin.y
			var route: PackedVector3Array=NPC.MOTION_ROUTE.query(main.player,InteriorBuilder.door_point(kind),finish)
			if route.is_empty():route_failures.append(point.id)
	check("every new seat, reading, tea and coffee point has a real entry route",route_failures.is_empty(),str(route_failures))
	await main.enter_interior("bakery");await t.frames(3)
	var seat: Interactable=rooms.bakery.find_child("public_cafe_1",true,false) as Interactable
	var life: PublicLife=main.story.public_life
	check("sitting uses a real chair position",life.sit(seat) and main.player.seated)
	await t.frames(8)
	check("actual skeleton hips lower onto the seat and knees bend forward",life.pose!=null and life.pose.measured_hip_height<.65 and life.pose.measured_knee_forward>.20,str(life.pose.measured_hip_height)+" "+str(life.pose.measured_knee_forward))
	main.before_save()
	check("saving while seated records a clear standing position",GameState.player_pos.distance_to(main.player.global_position)>.45 and GameState.player_pos.distance_to(life.standing_at)<.70)
	life.stand();await t.frames(2)
	check("standing removes the seat modifier and resumes normal movement",not main.player.seated and life.current_seat==null and main.player.global_position.distance_to(GameState.player_pos)<.10)
	GameState.minute=600;GameState.coins=1000
	var coins_before: int=GameState.coins;var coffee_before: int=GameState.count("coffee")
	check("coffee service charges the real price and grants one owned cup",life.buy_drink("coffee")=="" and GameState.coins==coins_before-120 and GameState.count("coffee")==coffee_before+1)
	check("drinking the owned coffee consumes exactly that cup",await life.drink("coffee") and GameState.count("coffee")==coffee_before)
	GameState.minute=21*60;coins_before=GameState.coins;coffee_before=GameState.count("coffee")
	check("closed cafe cannot charge or issue a drink",life.buy_drink("coffee")!="" and GameState.coins==coins_before and GameState.count("coffee")==coffee_before)
	var alpha_icons:=true
	for id: String in ["shop_chocolate_cake","shop_basque_cheesecake","shop_fruit_tart","shop_coffee","shop_cafe_latte"]:alpha_icons=alpha_icons and UITheme.icon_texture(id)!=null
	check("new foods and drinks have native UI kit icons",alpha_icons)
	GameState.minute=600;GameState.day=1
	var work_facing:=true;var work_details: Array[String]=[]
	for kind: String in ["bakery","store"]:
		if main.in_room:await main.exit_interior()
		await main.enter_interior(kind);await t.frames(3)
		var keeper: NPC=main.npcs["ren" if kind=="bakery" else "kazuko"]
		var station: Node3D=rooms[kind].get_node("PublicPlaceArt/EspressoStation" if kind=="bakery" else "G10_store_shelf")
		var spec: Dictionary=InteriorBuilder.spec_for(kind)
		var work_at: Vector3=spec.origin+spec.work_at
		var last_dot: float=-2.0
		main.shop_life.perform_work(kind,true)
		while main.shop_life._working:
			await t.frames(1)
			if keeper._moving or keeper.global_position.distance_to(work_at)>.06 or not bool(keeper.get_meta("shop_work_active",false)):continue
			var toward: Vector3=station.global_position-keeper.global_position;toward.y=0
			last_dot=keeper.model.global_basis.z.normalized().dot(toward.normalized())
		work_facing=work_facing and last_dot>.95;work_details.append(kind+" %.3f"%last_dot)
	check("keepers face the actual coffee and stocking surfaces while working",work_facing,str(work_details))
	await main.exit_interior();GameState.from_dict(snapshot)

class_name ShopContent
extends RefCounted
## Actual product meshes on measured shelves, plus native titles and changing TV artwork.
var world: WorldBuilder
var products: Array[Dictionary] = []
var televisions: Array[Dictionary] = []
var labels: Array[Dictionary] = []
var fixture_roots: Dictionary = {}
var restock_until := {"store":-1.0,"bakery":-1.0}
var restock_count := 0

func build(w: WorldBuilder) -> void:
	world=w
	for kind: String in ["store","bakery"]:
		var room: InteriorBuilder=world.interiors[kind]
		var root:=Node3D.new();root.name="LivingShopContent";room.add_child(root);fixture_roots[kind]=root
		if kind=="store":_store(room,root)
		else:_bakery(room,root)

func _group(room: InteriorBuilder,root: Node3D,support: Node3D,id: String,count: int,width: float,ceiling: float,depth: float,kind: String,scale_value: float=1.0,facing: float=0.0,category: String="",back_row: bool=false) -> void:
	var shelf_turn: float=rad_to_deg(support.global_rotation.y-root.global_rotation.y)
	for index in count:
		var x: float=-width*.5+(float(index)+.5)*width/float(count)
		var at: Vector3=support.to_global(Vector3(x,0,depth))
		var turn: float=[-1.5,.8,0.0,1.4][index%4]
		var product:=stock(room,root,support,id,at,ceiling,scale_value,kind,index,facing+shelf_turn+turn)
		if product:
			product.set_meta("stock_category",category);product.set_meta("back_row",back_row)
			var names: Dictionary={"W24_sugar_pack":"砂糖","W25_salt_box":"塩","W26_miso_tub":"味噌","W27_curry_box":"咖喱","W28_seed_packets":"种子"}
			if names.has(id) and not back_row:
				var bounds: AABB=WorldBuilder.local_aabb(product)
				var title:=ClearSignage.label(names[id],Vector3(0,bounds.size.y*.58,bounds.end.z+.004),0,.027 if id!="W28_seed_packets" else .018)
				product.add_child(title)
			products[-1]["fresh"]=category in ["bread","cake","prepared"]

func _store(room: InteriorBuilder,root: Node3D) -> void:
	var shelf:=world.spawn("W17_display_shelf",Vector3(2.2,0,-3.15),0,1,root);shelf.name="LivingDisplayShelf";HouseBuilder.toonify(shelf)
	_group(room,root,shelf,"W09_rice_sacks",2,.84,.36,0,"store",.72,0,"rice")
	_group(room,root,shelf,"W19_flour_bag",4,.88,.66,0,"store",.86,0,"flour")
	_group(room,root,shelf,"W22_soy_bottle",7,.88,1.01,0,"store",1,0,"seasoning")
	var gondola_index:=0
	for piece: Node3D in room.pieces:
		if piece.get_meta("model_id","")!="P_gondola":continue
		for face in 2:
			var sign_value: float=1.0 if face==0 else -1.0
			var facing: float=0.0 if face==0 else 180.0
			var ids: Array=["W09_rice_sacks","W19_flour_bag","W24_sugar_pack","W25_salt_box"] if gondola_index==0 else ["W10_bottle_crate","W26_miso_tub","W27_curry_box","W21_tea_tin"]
			var counts: Array=[4,8,9,10] if gondola_index==0 else [4,10,9,10]
			var scales: Array=[.73,.90,1.0,1.0] if gondola_index==0 else [.65,1.0,1.0,1.0]
			for row in 4:
				var ceiling: float=[.20,.54,.88,1.22][row]
				_group(room,root,piece,ids[row],counts[row],1.65,ceiling,sign_value*.17,"store",scales[row],facing,"pantry" if gondola_index==0 else "tea")
				if row>=2:
					_group(room,root,piece,ids[row],counts[row],1.65,ceiling,sign_value*.065,"store",scales[row],facing,"pantry" if gondola_index==0 else "tea",true)
			ClearSignage.paper_tag(piece,"Aisle_%d"%face,"米面 · 调料" if gondola_index==0 else "味噌 · 咖喱 · 茶",Vector3(0,1.52,sign_value*.325),Vector2(1.0,.16),deg_to_rad(facing),.08)
		gondola_index+=1
	for wall_shelf: Node3D in room.wall_shelves:
		var levels: Array=wall_shelf.get_meta("levels")
		for row in levels.size():
			_group(room,root,wall_shelf,"W11_ceramic_set" if wall_shelf.rotation.y>1 else ["W22_soy_bottle","W24_sugar_pack","W25_salt_box"][row%3],4 if wall_shelf.rotation.y>1 else 7,1.5,float(levels[row])+.01,.14,"store",.8,0,"homewares" if wall_shelf.rotation.y>1 else "pantry")
	var fridge: Node3D=_piece(room,"I03_drink_fridge")
	for row in 4:
		var y: float=[.28,.66,1.04,1.42][row]
		_group(room,root,fridge,"W23_egg_carton" if row==0 else "W20_milk_carton",5 if row==0 else 10,1.15,y+.01,.14,"store",.90,0,"chilled")
		_group(room,root,fridge,"W23_egg_carton" if row==0 else "W20_milk_carton",5 if row==0 else 10,1.15,y+.01,-.14,"store",.90,0,"chilled",true)
	var food_counter:=world.spawn("W13_cedar_worktable",Vector3(1.65,0,2.85),0,1,root,.70);food_counter.name="PreparedFoodCounter";HouseBuilder.toonify(food_counter)
	for index in 3:
		var at: Vector3=food_counter.to_global(Vector3(-.40+index*.40,0,0))
		var tray:=stock(room,root,food_counter,"W12_cedar_tray",at,1.1,.48,"store",index)
		if tray:
			stock(room,root,tray,"B09_sushi_tray" if index%2==0 else "B10_bento_box",tray.global_position,1.2,.56,"store",index)
			products[-1]["fresh"]=true
	var crates: Node3D=_piece(room,"D03_veg_crates")
	for index in 2:stock(room,root,crates,"W15_produce_basket",crates.to_global(Vector3(-.25+index*.5,0,0)),1.4,.64,"store",index)
	var tools:=world.spawn("W16_handtools_board",Vector3(-5.03,0,1.05),90,0,root,.78);tools.name="GardeningTools";HouseBuilder.toonify(tools)
	var seeds:=PublicPlaceArt.bench(root,"SeedDisplay",Vector3(-4.35,0,3.35),.58,.34,.72)
	_group(room,root,seeds,"W28_seed_packets",5,.48,.73,0,"store",1,0,"seeds")
	ClearSignage.paper_tag(seeds,"SeedPrice","晴町育苗 · 种子",Vector3(0,-.10,.19),Vector2(.56,.13),0,.055)
	poster(room,root,"store_poster","晴町商店\n本日鲜蔬",Vector3(2.2,2.20,-3.975),0)
	poster(room,root,"tools_poster","园艺与种子",Vector3(-5.465,2.45,1.05),PI*.5)
	ClearSignage.paper_tag(root,"PantryPrice","米 %d · 面粉 %d · 酱油 %d"%[int(GameState.item("rice").price),int(GameState.item("flour").price),int(GameState.item("soy_sauce").price)],Vector3(2.2,.28,-2.875),Vector2(.98,.14),0,.065)
	ClearSignage.paper_tag(fridge,"ColdTitle","冷藏 · 牛奶与鸡蛋",Vector3(0,1.85,.405),Vector2(1.2,.13),0,.075)
	_television(room,root)

func _bakery(room: InteriorBuilder,root: Node3D) -> void:
	var shelf:=world.spawn("W17_display_shelf",Vector3(-2.7,0,-.3),0,1,root);shelf.name="LivingDisplayShelf";HouseBuilder.toonify(shelf)
	for row in 3:
		var id: String=["B04_shokupan","B07_iced_donut","B11_cream_bun"][row]
		_group(room,root,shelf,id,4 if row==0 else 6,.92,[.36,.66,1.01][row],.11,"bakery",.92,0,"bread")
		if row>0:_group(room,root,shelf,id,5,.86,[.36,.66,1.01][row],-.11,"bakery",.92,0,"bread",true)
		ClearSignage.paper_tag(shelf,"BreadTag_%d"%row,["吐司 %d"%int(GameState.item("shokupan").price), "甜甜圈 %d"%int(GameState.item("donut").price), "奶油包 %d"%int(GameState.item("cream_bun").price)][row],Vector3(0,[.35,.65,1.0][row],.265),Vector2(.62,.10),0,.055)
	var rack_index:=0
	for rack: Node3D in room.pieces:
		if rack.get_meta("model_id","")!="I05_bread_shelf":continue
		for row in 4:
			var id: String=["B02_croissant","B01_melon_pan","B06_curry_pan","B03_baguette","B04_shokupan","B05_anpan","B02_croissant","B11_cream_bun"][rack_index*4+row]
			var baguette: bool=id=="B03_baguette"
			_group(room,root,rack,id,4 if id=="B04_shokupan" else (3 if baguette else 5),.91,[.28,.62,.95,1.27][row],0 if baguette else .15,"bakery",.94,90 if baguette else 0,"bread")
			if not baguette:_group(room,root,rack,id,4,.82,[.28,.62,.95,1.27][row],-.12,"bakery",.94,0,"bread",true)
			var menu_ids: Array=["croissant","melon_pan","curry_pan","baguette","shokupan","anpan","croissant","cream_bun"]
			var item_id: String=menu_ids[rack_index*4+row]
			ClearSignage.paper_tag(rack,"TrayPrice_%d"%row,GameState.item_name(item_id)+" %d"%int(GameState.item(item_id).price),Vector3(0,[.27,.61,.94,1.26][row],.325),Vector2(.63,.095),0,.053)
		rack_index+=1
	var cake_case: Node3D=_piece(room,"I02_cake_showcase")
	for glass_node: MeshInstance3D in WorldBuilder.find_meshes(cake_case):
		if not glass_node.name.begins_with("Glass"):continue
		var glazing:=ShaderMaterial.new();glazing.shader=load("res://shaders/shop_glass.gdshader")
		for surface in glass_node.mesh.get_surface_count():glass_node.set_surface_override_material(surface,glazing)
	for row in 2:
		for family in 4:
			var id: String=["B12_strawberry_slice","B13_chocolate_slice","B14_basque_slice","B15_fruit_tart"][family]
			for depth_index in 2:
				var at: Vector3=cake_case.to_global(Vector3(-.45+family*.30,0,-.11+depth_index*.23))
				var portion:=stock(room,root,cake_case,id,at,[.60,.84][row],1.0,"bakery",depth_index+family)
				if portion:portion.set_meta("stock_category","cake");products[-1]["fresh"]=true
		for family in 4:
			ClearSignage.paper_tag(cake_case,"CakePrice_%d_%d"%[row,family],["草莓","巧克力","巴斯克","水果塔"][family]+" %d"%int(GameState.item(["shortcake","chocolate_cake","basque_cheesecake","fruit_tart"][family]).price),Vector3(-.45+family*.30,[.586,.826][row],.333),Vector2(.27,.075),0,.039)
	for wall_shelf: Node3D in room.wall_shelves:
		var levels: Array=wall_shelf.get_meta("levels")
		for row in levels.size():_group(room,root,wall_shelf,"W19_flour_bag",6,1.4,float(levels[row])+.01,.14,"bakery",.82,0,"pantry")
	poster(room,root,"bakery_poster","莲的面包店\n每日烘焙",Vector3(5.465,2.05,.8),-PI*.5)
	var price:=ClearSignage.paper_tag(shelf,"ShelfPriceSign","当日烘焙",Vector3(0,.20,.265),Vector2(.78,.13),0,.075)
	labels.append({"node":price,"kind":"bakery"})

func _piece(room: InteriorBuilder,id: String) -> Node3D:
	for piece: Node3D in room.pieces:
		if piece.get_meta("model_id","")==id:return piece
	return null

func stock(room: InteriorBuilder,parent: Node3D,support: Node3D,id: String,at: Vector3,ceiling: float,scale_value: float,kind: String,slot: int,yaw: float=0.0) -> Node3D:
	if support==null:return null
	var height: float=WorldBuilder.surface_height(support,Vector2(at.x,at.z),room.global_position.y+ceiling)
	if not is_finite(height):
		push_warning("No product support: "+id+" on "+support.name);return null
	var product:=world.spawn(id,Vector3.ZERO,yaw,0,parent,scale_value)
	if product==null:return null
	product.name="StockProduct_%s_%d"%[id,products.size()]
	product.global_position=Vector3(at.x,height+.001,at.z)
	WorldBuilder.rest_on(product,height,-.001)
	product.set_meta("shop_product",true);product.set_meta("support_surface",product.get_path_to(support))
	product.set_meta("support_ceiling",height+.025)
	HouseBuilder.toonify(product)
	products.append({"node":product,"support":support,"height":height,"kind":kind,"slot":slot,"base":product.position,"day":GameState.day})
	return product

func _box(parent: Node3D,name_value: String,size: Vector3,at: Vector3,colour: Color) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=name_value
	var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh
	node.material_override=LivingAction.matte(colour);node.position=at;parent.add_child(node);return node

func _label(text_value: String,at: Vector3,parent: Node3D) -> Label3D:
	var label:=Label3D.new();label.name="ReadableTitle_%d"%parent.get_child_count()
	label.font=load("res://assets/fonts/LXGWWenKai-Medium.ttf");label.text=text_value;label.font_size=42;label.pixel_size=.0022
	label.modulate=Color(.23,.25,.24);label.outline_size=0;label.position=at;parent.add_child(label);return label

func poster(room: InteriorBuilder,parent: Node3D,art: String,title: String,at: Vector3,yaw: float) -> void:
	var root:=Node3D.new();root.name="ShopPoster_"+art;parent.add_child(root);root.rotation.y=yaw
	# The wall frame projects 7.3 cm from its centre; hang the poster on its inward face.
	root.position=at+Basis(Vector3.UP,yaw)*Vector3(0,0,.11)
	_box(root,"CedarFrame",Vector3(.66,.97,.035),Vector3.ZERO,Color(.53,.38,.25))
	var image_node:=MeshInstance3D.new();image_node.name="IllustratedPaper"
	var quad:=QuadMesh.new();quad.size=Vector2(.62,.93);image_node.mesh=quad;image_node.position.z=.02
	var material:=LivingAction.matte(Color.WHITE);material.albedo_texture=load("res://assets/textures/shop_life/%s.png"%art)
	image_node.material_override=material;root.add_child(image_node)
	_label(title,Vector3(0,.30,.021),root)

func _television(room: InteriorBuilder,parent: Node3D) -> void:
	var shelf:=_box(parent,"TelevisionWallShelf",Vector3(.52,.045,.85),Vector3(5.05,1.69,-.8),Color(.56,.39,.25))
	var television:=world.spawn("W18_retro_tv",Vector3(5.05,1.714,-.8),-90,0,parent)
	television.name="LivingTelevision";HouseBuilder.toonify(television)
	television.set_meta("support_surface",television.get_path_to(shelf))
	var bounds: AABB=WorldBuilder.local_aabb(television)
	var screen:=ShopTelevision.make_screen()
	television.add_child(screen)
	var title:=_label("晴町小记",Vector3(-bounds.size.x*.105,.073,.195),television)
	title.pixel_size=.00075;title.font_size=30;title.modulate=Color.WHITE
	televisions.append({"node":television,"screen":screen,"title":title,"kind":"store"})

func update(elapsed: float) -> void:
	for entry: Dictionary in products:
		var shop: Dictionary=GameState.shop(entry.kind)
		var open: bool=GameState.hour()>=float(shop.open) and GameState.hour()<float(shop.close) and GameState.weekday()!=int(shop.get("closed_weekday",-1))
		var fresh: bool=bool(entry.get("fresh",false))
		entry.node.visible=not fresh or ((open or GameState.hour()<21.0) and (GameState.hour()<14.0 or int(entry.slot)%3!=2 or elapsed<float(restock_until[entry.kind])))
	for television: Dictionary in televisions:
		var shop: Dictionary=GameState.shop(television.kind)
		var open: bool=GameState.hour()>=float(shop.open) and GameState.hour()<float(shop.close) and GameState.weekday()!=int(shop.get("closed_weekday",-1))
		var channel: int=int(elapsed/12.0)%2
		ShopTelevision.update(television.screen,elapsed,open,GameState.weather=="rain")
		television.title.text=("晴町小记" if channel==0 else "晴町天气 · "+GameState.weather_name()) if open else ""
	for label: Dictionary in labels:
		label.node.text=("午后少量烘焙" if GameState.hour()>=14 else "当日烘焙") if label.kind=="bakery" else "米粮 · 日用"

func replenish(kind: String,elapsed: float) -> void:
	restock_until[kind]=elapsed+50.0;restock_count+=1;update(elapsed)

func visible_products(kind: String) -> int:
	return products.filter(func(entry: Dictionary):return entry.kind==kind and entry.node.visible).size()

func supported() -> bool:
	for entry: Dictionary in products:
		var bounds: AABB=entry.node.global_transform*WorldBuilder.local_aabb(entry.node)
		var actual: float=WorldBuilder.surface_height(entry.support,Vector2(entry.node.global_position.x,entry.node.global_position.z),entry.height+.03)
		if not is_finite(actual) or absf(bounds.position.y-actual)>.009:return false
	return true

func walkways_clear() -> bool:
	for kind: String in ["store","bakery"]:
		var room: InteriorBuilder=world.interiors[kind]
		var at: Vector3=InteriorBuilder.door_point(kind)
		var probe:=PhysicsShapeQueryParameters3D.new();probe.shape=NPC.MOTION_ROUTE.capsule();probe.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED
		probe.transform=Transform3D(Basis.IDENTITY,at+Vector3(0,.8,0))
		if not room.get_world_3d().direct_space_state.intersect_shape(probe,1).is_empty():return false
	return true

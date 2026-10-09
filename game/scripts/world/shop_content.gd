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
		var shelf:=world.spawn("W17_display_shelf",Vector3(2.2,0,-3.15) if kind=="store" else Vector3(-2.7,0,-.3),0,1,root)
		shelf.name="LivingDisplayShelf";HouseBuilder.toonify(shelf)
		if kind=="store":
			_row(room,root,shelf,["W09_rice_sacks","W09_rice_sacks"],[-.26,.25],[.55,.50],.35,kind,0,-.05)
			_row(room,root,shelf,["W19_flour_bag","W21_tea_tin","W22_soy_bottle"],[-.29,.025,.29],[.72,.87,.80],.65,kind,1,-.05)
			_row(room,root,shelf,["W11_ceramic_set","W20_milk_carton"],[-.22,.28],[.67,.78],1.00,kind,2,-.05)
		else:
			_row(room,root,shelf,["B04_shokupan","B03_baguette","B02_croissant"],[-.30,-.015,.29],[.85,.36,.90],.35,kind,0,-.05)
			_row(room,root,shelf,["B07_iced_donut","B05_anpan","B07_iced_donut","B01_melon_pan"],[-.32,-.13,.10,.31],[1.0,.98,.95,1.02],.65,kind,1,-.05)
			_row(room,root,shelf,["B11_cream_bun","B06_curry_pan","B02_croissant"],[-.28,.02,.30],[.98,1.03,.82],1.00,kind,2,-.05)
		if kind=="store":
			var gondola_index: int=0
			for piece: Node3D in room.pieces:
				if piece.get_meta("model_id","")!="P_gondola":continue
				for face: int in 2:
					var depth: float=.14 if face==0 else -.14
					var facing: float=0.0 if face==0 else 180.0
					var seed_value: int=gondola_index*17+face*9
					if gondola_index%2==1:
						_row(room,root,piece,["W03_cucumber_crate","W23_egg_carton","W23_egg_carton","W23_egg_carton"],[-.60,-.14,.16,.58],[.40,.79,.76,.71],.20,kind,seed_value,depth,facing)
						_row(room,root,piece,["W20_milk_carton","W20_milk_carton","W10_bottle_crate"],[-.57,-.29,.44],[.80,.76,.48],.54,kind,seed_value+1,depth,facing)
						_row(room,root,piece,["W11_ceramic_set","W21_tea_tin","W21_tea_tin","W11_ceramic_set"],[-.57,-.14,.13,.59],[.56,.86,.78,.57],.88,kind,seed_value+2,depth,facing)
						_row(room,root,piece,["W19_flour_bag","W22_soy_bottle","W22_soy_bottle","W19_flour_bag"],[-.66,-.23,.09,.54],[.72,.81,.78,.77],1.22,kind,seed_value+3,depth,facing)
						continue
					_row(room,root,piece,["W09_rice_sacks","W23_egg_carton","W23_egg_carton","W19_flour_bag"],[-.63,-.24,.25,.66],[.47,.82,.78,.73],.20,kind,seed_value,depth,facing)
					_row(room,root,piece,["W19_flour_bag","W19_flour_bag","W21_tea_tin","W22_soy_bottle","W21_tea_tin","W22_soy_bottle"],[-.69,-.47,-.12,.12,.42,.68],[.71,.70,.83,.77,.83,.76],.54,kind,seed_value+1,depth,facing)
					_row(room,root,piece,["W20_milk_carton","W20_milk_carton","W20_milk_carton","W10_bottle_crate"],[-.65,-.40,-.12,.46],[.78,.76,.80,.46],.88,kind,seed_value+2,depth,facing)
					_row(room,root,piece,["W11_ceramic_set","W21_tea_tin","W19_flour_bag","W22_soy_bottle"],[-.61,-.25,.16,.65],[.59,.86,.70,.80],1.22,kind,seed_value+3,depth,facing)
				gondola_index+=1
			for wall_shelf: Node3D in room.wall_shelves:
				var levels: Array=wall_shelf.get_meta("levels")
				for row: int in levels.size():
					var goods: Array=[["W19_flour_bag","W09_rice_sacks","W19_flour_bag","W22_soy_bottle"],["W20_milk_carton","W20_milk_carton","W21_tea_tin","W22_soy_bottle"],["W11_ceramic_set","W21_tea_tin","W19_flour_bag","W21_tea_tin"]][row%3]
					_row(room,root,wall_shelf,goods,[-.58,-.20,.14,.59],[.70,.62,.71,.73],float(levels[row])+.02,kind,row+5,.14)
			var food_counter:=world.spawn("W13_cedar_worktable",Vector3(1.85,0,3.0),0,1,root,.70)
			food_counter.name="PreparedFoodCounter";HouseBuilder.toonify(food_counter)
			for index: int in 4:
				var stock_at: Vector3=food_counter.to_global(Vector3(-.51+index*.34,0,0))
				var tray:=stock(room,root,food_counter,"W12_cedar_tray",stock_at,1.1,.48,kind,index)
				if tray:
					stock(room,root,tray,"B09_sushi_tray" if index%2==0 else "B10_bento_box",tray.global_position,1.2,.56,kind,index)
			var crates: Node3D=_piece(room,"D03_veg_crates")
			for index: int in 2:stock(room,root,crates,"W15_produce_basket",crates.to_global(Vector3(-.25+index*.5,0,0)),1.4,.64,kind,index)
			var tools:=world.spawn("W16_handtools_board",Vector3(-4.7,0,-1.35),90,1,root,.85);tools.name="GardeningTools";HouseBuilder.toonify(tools)
			poster(room,root,"store_poster","晴町商店\n本日鲜蔬",Vector3(2.2,2.20,-3.975),0)
			poster(room,root,"tools_poster","园艺与种子",Vector3(-5.465,2.15,-2.35),PI*.5)
			_television(room,root)
		else:
			var counter: Node3D=_piece(room,"I04_shop_counter")
			_row(room,root,counter,["B11_cream_bun","B07_iced_donut","B02_croissant","B05_anpan"],[-.42,-.12,.17,.41],[1.0,1.0,.83,1.05],1.3,kind,11,0.0)
			var cake_case: Node3D=_piece(room,"I02_cake_showcase")
			for glass_node: MeshInstance3D in WorldBuilder.find_meshes(cake_case):
				if not glass_node.name.begins_with("Glass"):continue
				var glazing:=ShaderMaterial.new();glazing.shader=load("res://shaders/shop_glass.gdshader")
				for surface: int in glass_node.mesh.get_surface_count():glass_node.set_surface_override_material(surface,glazing)
			for shelf_y: float in [.60,.84]:
				for index: int in 3:stock(room,root,cake_case,"B08_strawberry_cake",cake_case.to_global(Vector3(-.42+index*.42,0,0)),shelf_y,.87,kind,index)
			for wall_shelf: Node3D in room.wall_shelves:
				var pantry_levels: Array=wall_shelf.get_meta("levels")
				for row: int in pantry_levels.size():
					_row(room,root,wall_shelf,["W19_flour_bag","W19_flour_bag","W20_milk_carton","W23_egg_carton"],[-.48,-.22,.11,.43],[.82,.78,.74,.70],float(pantry_levels[row])+.02,kind,row+8,.14)
			poster(room,root,"bakery_poster","莲的面包店\n每日烘焙",Vector3(5.465,2.05,.8),-PI*.5)
		var shelf_box: AABB=WorldBuilder.local_aabb(shelf)
		var price:=ClearSignage.paper_tag(shelf,"ShelfPriceSign","当日烘焙" if kind=="bakery" else "米粮 · 日用",Vector3(shelf_box.get_center().x,.27,shelf_box.end.z+.014),Vector2(.78,.13),0,.075)
		labels.append({"node":price,"kind":kind})

func _piece(room: InteriorBuilder,id: String) -> Node3D:
	for piece: Node3D in room.pieces:
		if piece.get_meta("model_id","")==id:return piece
	return null

func _row(room: InteriorBuilder,parent: Node3D,support: Node3D,goods: Array,positions: Array,scales: Array,ceiling: float,kind: String,seed_value: int,depth: float,facing: float=0.0) -> void:
	# Stable arrangements survive a reload; gaps and small turns are placed around usable shelf space.
	for index: int in goods.size():
		var offset: float=[-.012,.009,.002,-.006,.013][(seed_value+index)%5]
		var turn: float=[-5.0,2.5,0.0,4.0,-2.0,6.0][(seed_value*3+index)%6]
		var at: Vector3=support.to_global(Vector3(float(positions[index]),0,depth+offset))
		var shelf_turn: float=rad_to_deg(support.global_rotation.y-parent.global_rotation.y)
		stock(room,parent,support,str(goods[index]),at,ceiling,float(scales[index]),kind,index,facing+turn+shelf_turn)

func stock(room: InteriorBuilder,parent: Node3D,support: Node3D,id: String,at: Vector3,ceiling: float,scale_value: float,kind: String,slot: int,yaw: float=0.0) -> Node3D:
	if support==null:return null
	var height: float=WorldBuilder.surface_height(support,Vector2(at.x,at.z),room.global_position.y+ceiling)
	if not is_finite(height):
		push_warning("No product support: "+id+" on "+support.name);return null
	var product:=world.spawn(id,Vector3.ZERO,yaw,0,parent,scale_value)
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
		entry.node.visible=open and (GameState.hour()<14.0 or int(entry.slot)%3!=2 or elapsed<float(restock_until[entry.kind]))
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

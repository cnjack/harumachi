class_name MealModels
extends RefCounted
## Table portions use solid meshes. The asset is spawned through the world's common registry.
const MODELS := {"croissant":"B02_croissant","baguette":"B03_baguette","shokupan":"B04_shokupan","anpan":"B05_anpan","onigiri": "B02_onigiri", "dish_edamame_onigiri": "B02_onigiri", "melon_pan": "B01_melon_pan", "bread_sandwich": "B07_veg_sandwich", "bread_focaccia": "B08_focaccia", "bread_curry_pan": "B06_curry_pan", "donut": "B07_iced_donut", "cream_bun": "B11_cream_bun", "shortcake": "B12_strawberry_slice", "chocolate_cake":"B13_chocolate_slice", "basque_cheesecake":"B14_basque_slice", "fruit_tart":"B15_fruit_tart", "sushi_box": "B09_sushi_tray", "bento": "B10_bento_box"}
static func model_id(item_id: String) -> String:
	var icon: String = str(GameState.item(item_id).get("icon",item_id))
	return str(MODELS.get(item_id,MODELS.get(icon,"")))
static func can_display(item_id: String) -> bool:
	var id: String = model_id(item_id)
	if id!="" and ResourceLoader.exists("res://assets/models/%s.glb"%id): return true
	var temporary: Node3D = solid_dish(item_id)
	if temporary==null:return false
	temporary.free()
	return true
static func spawn(world: WorldBuilder, parent: Node3D, item_id: String, width: float=.105) -> Node3D:
	var id: String = model_id(item_id)
	var model: Node3D
	if id != "" and ResourceLoader.exists("res://assets/models/%s.glb"%id):
		model = world.spawn(id,Vector3.ZERO,0,0,parent)
	else:
		model = solid_dish(item_id)
		if model != null: parent.add_child(model)
	if model == null: return null
	var box: AABB = WorldBuilder.local_aabb(model)
	if WorldBuilder.find_meshes(model).is_empty() or maxf(box.size.x,box.size.z)<=.0001:
		parent.remove_child(model);model.free();return null
	model.scale *= width/maxf(box.size.x,box.size.z)
	box = Transform3D(model.basis,Vector3.ZERO) * WorldBuilder.local_aabb(model)
	model.position -= Vector3(box.get_center().x,box.position.y,box.get_center().z)
	model.set_meta("audit_item",item_id)
	model.set_meta("audit_category","food_model")
	HouseBuilder.toonify(model)
	# Detach only this instance's render base while its material references are
	# still alive. Never mutate the shared mesh or free renderer RIDs directly.
	for mesh_node: MeshInstance3D in WorldBuilder.find_meshes(model):
		mesh_node.tree_exiting.connect(func():
			if OS.get_cmdline_user_args().has("--material-debug"):
				print("FOOD_BASE_DETACH ",JSON.stringify({"item":item_id,"node":str(mesh_node.name),"instance":str(mesh_node.get_instance()),"base":str(mesh_node.mesh.get_rid()) if mesh_node.mesh!=null else "none","parent":str(model.name)}))
			mesh_node.mesh=null)
	return model

## Small cooked ingredients stay solid too; recipe icons are only used by the inventory UI.
static func solid_dish(item_id: String) -> Node3D:
	var icon: String = str(GameState.item(item_id).get("icon",item_id))
	var root := Node3D.new()
	root.name = "CookedPortion"
	root.set_meta("model_part",true)
	var cream := Color(.95,.87,.61)
	var green := Color(.43,.70,.26)
	var red := Color(.85,.25,.16)
	var gold := Color(.87,.61,.28)
	var brown := Color(.48,.27,.12)
	if icon == "dish_pickles":
		for index: int in 3:
			var at := Vector3((index-1)*.037,.012,index*.006)
			part(root,"Peel_%d"%index,"disk",Vector3(.07,.012,.07),at,green)
			part(root,"Flesh_%d"%index,"disk",Vector3(.056,.002,.056),at+Vector3.UP*.007,Color(.78,.88,.53))
	elif icon in ["dish_miso_soup","dish_crucian_soup","dish_corn_soup","dish_strawberry_jam"]:
		var liquid: Color = gold if icon=="dish_corn_soup" else (red if icon=="dish_strawberry_jam" else brown)
		part(root,"Soup","disk",Vector3(.12,.026,.12),Vector3(0,.013,0),liquid)
		for index: int in 3: part(root,"Garnish_%d"%index,"box",Vector3(.021,.012,.025),Vector3((index-1)*.025,.029,.013*(index%2)),green if icon!="dish_strawberry_jam" else red)
	elif icon=="dish_salad":
		for index: int in 4:
			part(root,"Cucumber_%d"%index,"disk",Vector3(.042,.01,.042),Vector3((index%2-.5)*.058,.008,(index/2-.5)*.047),green)
			part(root,"Tomato_%d"%index,"round",Vector3(.04,.028,.035),Vector3((index%2-.5)*.04,.024,(index/2-.5)*.04),red)
	elif icon in ["fest_dango","fest_candy_apple"]:
		if icon=="fest_dango":
			for index: int in 3: part(root,"Dango_%d"%index,"round",Vector3(.04,.04,.04),Vector3((index-1)*.043,.02,0),cream)
		else: part(root,"Apple","round",Vector3(.085,.085,.085),Vector3(0,.0425,0),red)
	elif icon=="dish_watermelon_slice":
		part(root,"Rind","box",Vector3(.13,.014,.065),Vector3(0,.007,0),green)
		part(root,"Melon","box",Vector3(.12,.04,.055),Vector3(0,.034,0),red)
	elif icon in ["cake_carrot","cake_shortcake"]:
		part(root,"Cake","box",Vector3(.11,.055,.085),Vector3(0,.0275,0),gold)
		part(root,"Icing","box",Vector3(.11,.012,.085),Vector3(0,.061,0),cream)
		part(root,"Topping","round",Vector3(.035,.025,.035),Vector3(0,.079,0),red if icon=="cake_shortcake" else gold)
	elif icon in ["bread_sunflower","bread_corn","bread_pumpkin"]:
		part(root,"Bread","round",Vector3(.12,.07,.09),Vector3(0,.035,0),gold)
		for index: int in 3: part(root,"Topping_%d"%index,"round",Vector3(.009,.006,.017),Vector3((index-1)*.025,.069,0),brown if icon=="bread_sunflower" else cream)
	elif icon in ["dish_trout_rice","dish_eel_rice","dish_curry"]:
		part(root,"Rice","round",Vector3(.12,.032,.10),Vector3(0,.016,0),cream)
		part(root,"Topping","box",Vector3(.085,.022,.055),Vector3(.016,.04,0),brown if icon!="dish_curry" else gold)
	elif icon in ["dish_grilled_ayu","dish_carp_kanroni","dish_butter_bass"]:
		part(root,"Fish","round",Vector3(.12,.034,.045),Vector3(0,.017,0),gold if icon=="dish_butter_bass" else brown)
		var tail: MeshInstance3D = part(root,"Tail","box",Vector3(.035,.014,.035),Vector3(-.059,.016,0),brown)
		tail.rotation.y=PI/4
	elif icon in ["dish_kinpira","dish_radish_nimono","dish_korokke","dish_nasu_dengaku","dish_tempura","dish_pumpkin_nimono"]:
		var color: Color = cream if icon=="dish_radish_nimono" else (Color(.45,.28,.53) if icon=="dish_nasu_dengaku" else gold)
		for index: int in 3:
			var size: Vector3 = Vector3(.075,.012,.016) if icon=="dish_kinpira" else Vector3(.042,.034,.045)
			part(root,"Bite_%d"%index,"round",size,Vector3((index-1)*.035,size.y/2,index*.007),color)
	else:
		root.free()
		return null
	return root

static func part(root: Node3D, label: String, shape: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var piece := MeshInstance3D.new(); piece.name=label
	if shape=="disk":
		var mesh := CylinderMesh.new(); mesh.top_radius=size.x/2; mesh.bottom_radius=size.x/2; mesh.height=size.y; mesh.radial_segments=16; piece.mesh=mesh
	elif shape=="round":
		var mesh := SphereMesh.new(); mesh.radius=.5; mesh.height=1; mesh.radial_segments=16; mesh.rings=8; piece.mesh=mesh; piece.scale=size
	else:
		var mesh := BoxMesh.new(); mesh.size=size; piece.mesh=mesh
	piece.position=at; piece.material_override=LivingAction.matte(color); root.add_child(piece)
	return piece

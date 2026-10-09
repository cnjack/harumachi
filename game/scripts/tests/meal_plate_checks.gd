extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void: t=runner; main=runner.main
func check(label: String, ok: bool, detail: String="") -> void: t.check("MEAL_PLATE",label,ok,detail)
func run() -> void:
	var original: Dictionary = GameState.to_dict().duplicate(true)
	GameState.new_game(); GameState.clock_paused=true
	GameState.quests.Q00={"state":"done","step":2}
	if not main.in_room: await main.enter_room()
	DailyLife.claim_meal(); GameState.craft("first_home_onigiri")
	main.story.daily.view.sync_state()
	var view: DailyLifeView = main.story.daily.view
	var tray: Node3D = view.meal_root.get_node("W12_cedar_tray")
	var action := LivingAction.new(); main.add_child(action)
	action.surface_at = view._food_surface()
	action.surface_normal = view._meal_normal()
	action.duration = 100
	action.setup(main.player,"eat","onigiri")
	action.set_process(false)
	var plate: MeshInstance3D = action.prop.get_node("Plate")
	var plate_box: AABB = plate.global_transform*plate.get_aabb()
	var tray_box: AABB = tray.global_transform*WorldBuilder.local_aabb(tray)
	var radius: float = plate_box.size.x/2.0
	var center: Vector3 = plate.global_position
	var center_height: float = WorldBuilder.surface_height(tray,Vector2(center.x,center.z),tray_box.end.y+.01)
	var supported := is_finite(center_height)
	var samples: Array = []
	for index: int in 16:
		var angle: float = float(index)*TAU/16.0
		var on_plane: Vector3 = action.prop.global_transform * Vector3(cos(angle)*(radius+.008),.0005,sin(angle)*(radius+.008))
		var point := Vector2(on_plane.x,on_plane.z)
		var height: float = WorldBuilder.surface_height(tray,point,tray_box.end.y+.01)
		samples.append(height)
		if not is_finite(height) or absf(height-on_plane.y)>.003: supported=false
	check("the complete plate and margin sit inside the tray's actual flat basin",supported,"plate=%s tray=%s center=%s perimeter=%s"%[plate_box,tray_box,center_height,samples])
	var plate_base_center: Vector3 = action.prop.global_transform*Vector3(0,.0005,0)
	check("the plate base rests on the tray rather than below its frame",is_finite(center_height) and plate_base_center.y>=center_height-.001 and plate_base_center.y<=center_height+.003,"plate base center=%s support=%s"%[plate_base_center.y,center_height])
	var food: Node3D = action.meal_food
	var inner_radius: float = radius-.012
	var max_radius := 0.0
	var local: AABB = Transform3D(food.basis,food.position)*WorldBuilder.local_aabb(food)
	for corner: Vector3 in [local.position,local.end,Vector3(local.position.x,0,local.end.z),Vector3(local.end.x,0,local.position.z)]:
		max_radius=maxf(max_radius,Vector2(corner.x,corner.z).length())
	check("the 3D food footprint stays within the plate basin",max_radius<=inner_radius,"food radius=%s basin=%s"%[max_radius,inner_radius])
	check("the 3D food has real thickness and no image plane",WorldBuilder.find_meshes(food).size()>0 and local.size.y>.02 and food.find_children("*","Sprite3D",true,false).is_empty())
	check("the food rests just above the plate's center surface",local.position.y>.0095 and local.position.y-.0095<.006)
	check("eating remains independent of gripping or a hand rig",action.pose==null and action.skeleton==null and action.hand<0)
	var before: int = GameState.count("onigiri")
	action.clock=action.duration*.8; action._process(0)
	check("the empty state removes the food while retaining the exact same supported plate",not food.visible and plate.is_visible_in_tree() and plate.global_transform*plate.get_aabb()==plate_box)
	check("the presentation does not consume or duplicate inventory",GameState.count("onigiri")==before)
	var missing: Array[String]=[]
	var images: Array[String]=[]
	var unsupported: Array[String]=[]
	var too_wide: Array[String]=[]
	var probe := Node3D.new();main.add_child(probe)
	for iid: String in GameState.items_db:
		if not DailyLife.edible(iid):continue
		var portion: Node3D=MealModels.spawn(main.world,probe,iid,.105)
		if portion==null:
			missing.append(iid);continue
		var portion_box: AABB=Transform3D(portion.basis,portion.position)*WorldBuilder.local_aabb(portion)
		if WorldBuilder.find_meshes(portion).is_empty() or not portion.find_children("*","Sprite3D",true,false).is_empty():images.append(iid)
		if absf(portion_box.position.y)>.001 or portion_box.size.y<.006:unsupported.append(iid)
		# Circular soup/fruit have empty AABB corners; inspect their actual mesh footprint.
		var radius_actual: float=0
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(portion):
			var relative: Transform3D=probe.global_transform.affine_inverse()*mesh.global_transform
			for vertex: Vector3 in mesh.mesh.get_faces():
				var actual: Vector3=relative*vertex
				radius_actual=maxf(radius_actual,Vector2(actual.x,actual.z).length())
		if radius_actual>.073:too_wide.append(iid)
		probe.remove_child(portion);portion.free()
	check("every currently open edible item has a solid portion, including dynamic meal items",missing.is_empty(),str(missing))
	check("all edible portions use meshes instead of image planes",images.is_empty(),str(images))
	check("all edible portions are grounded with real thickness",unsupported.is_empty(),str(unsupported))
	check("every edible portion fits the existing plate basin",too_wide.is_empty(),str(too_wide))
	check("an unknown portion cannot begin an eating scene or lose inventory",not MealModels.can_display("unregistered_food") and await view.play_action("eat","unregistered_food")!="")
	# A resource may exist but instantiate without a mesh. Exercise the actual story entries.
	var rice_scene: PackedScene=WorldBuilder.model_scene("B02_onigiri")
	var bread_scene: PackedScene=WorldBuilder.model_scene("B01_melon_pan")
	var empty_root:=Node3D.new();var empty_scene:=PackedScene.new();empty_scene.pack(empty_root);empty_root.free()
	WorldBuilder._cache["B02_onigiri"]=empty_scene
	DailyLife.event("meal").state="in_progress"
	await t.use("life_meal_table",[0])
	check("the real first-meal entry preserves both portions when the resource has no mesh",not DailyLife.done("meal") and GameState.count("onigiri")==before)
	WorldBuilder._cache["B02_onigiri"]=rice_scene
	WorldBuilder._cache["B01_melon_pan"]=empty_scene
	await main.exit_room()
	GameState.day=3;GameState.minute=12*60;GameState.quests.Q00={"state":"done","step":2}
	main.npcs.ren.set_home(false);main.npcs.ren.place(Vector3(-21.8,0,-14.3),0)
	await t.use("life_bakery_card",[1])
	check("the real bakery taste entry keeps its claimed food rather than recording a fictional bite",not DailyLife.done("card") and GameState.count("life_bread_sample")==1,"card=%s count=%s dialogue=%s"%[DailyLife.event("card"),GameState.count("life_bread_sample"),main.ui.dlg_text.text])
	WorldBuilder._cache["B01_melon_pan"]=bread_scene
	probe.queue_free()
	action.queue_free(); await t.frames(2)
	GameState.from_dict(original); main._restore(); GameState.clock_paused=true

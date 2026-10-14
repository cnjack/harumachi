extends Node
## Same real furniture, cameras and lighting before/after. Diagnostic setup only;
## this does not stand in for interaction or story validation.
var main: Node
var camera: Camera3D
var folder := ""
var rows: Array[Dictionary] = []
var failures: Array[String] = []
var filter := ""
const TARGETS := [
	["bakery", "P_deck_oven", "oven", 0],
	["bakery", "P_deck_oven", "oven_side", 1],
	["bakery", "P_deck_oven", "oven_night", 2],
	["bakery", "I04_shop_counter", "bakery_counter", 0],
	["bakery", "EspressoStation", "coffee", 0],
	["bakery", "EspressoStation", "coffee_detail", 3],
	["bakery", "CafeTable_0", "cafe", 0],
	["bakery", "CafeTable_0", "cafe_side", 1],
	["bakery", "I02_cake_showcase", "cake_glass", 0],
	["bakery", "I04_shop_counter", "bakery_play_camera", 5],
	["store", "I04_shop_counter", "store_counter_rotated", 0],
	["store", "I03_drink_fridge", "fridge", 0],
	["store", "I07_ice_freezer", "freezer", 0],
	["workroom", "W13_cedar_worktable", "worktable", 0],
	["workroom", "SharedNeighbourTable", "shared_table", 0],
	["workroom", "ReadingChair_0", "reading_chair", 0],
	["home_haru", "FamilyLowTable", "family_table", 0],
	["home_haru", "AoiDrawingDesk", "drawing_desk", 0],
	["toolshed", "DirtyWorkBench", "toolshed", 0],
	["florist", "FlowerWrapping", "florist", 0],
	["post", "PostalCounter", "postal_counter", 0],
	["post", "PostalCounter", "postal_detail", 3],
	["library", "MapReadingDesk", "library", 0],
	["house", "J01_kitchen_counter", "home_kitchen", 0],
	["house", "J03_dining_set", "home_dining", 0],
	["house", "J05_dish_cabinet", "home_dishes", 0],
	["house", "G07_hall_cabinet", "home_cabinet", 0],
	["house", "I03_bookshelf", "home_books", 0],
	["house", "J09_tansu", "home_tansu", 0],
	["house", "G01_getabako", "home_shoes", 0],
	["house", "J07_kotatsu", "home_kotatsu", 0],
	["town", "A12_bench", "town_bench", 0],
	["town", "A12_bench", "town_bench_side", 1],
	["farm", "A12_bench", "farm_bench", 0],
	["farm", "A12_bench", "farm_bench_rain", 4],
	["lake", "A12_bench", "lake_bench", 0],
]

func _ready() -> void:
	main=get_parent()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--furniture-review-out="):folder=arg.trim_prefix("--furniture-review-out=")
		if arg.begins_with("--furniture-review-filter="):filter=arg.trim_prefix("--furniture-review-filter=")
	_run.call_deferred()

func frames(count: int) -> void:
	for index: int in count:await get_tree().process_frame

func target(root: Node, key: String, region: String) -> Node3D:
	if region=="farm" and root==main.world.farm.lakeside:return null
	if root is Node3D and (root.name==key or str(root.get_meta("model_id",""))==key):
		var x: float=(root as Node3D).global_position.x
		if region!="town" or x<500.0:return root as Node3D
	for child: Node in root.get_children():
		var found: Node3D=target(child,key,region)
		if found!=null:return found
	return null

func vec(value: Vector3) -> Array[float]:return [value.x,value.y,value.z]

func capture(label: String, context: Dictionary) -> void:
	await frames(12);await RenderingServer.frame_post_draw
	var error: Error=get_viewport().get_texture().get_image().save_png(folder.path_join(label+".png"))
	if error!=OK:failures.append(label+": png error "+str(error))
	var row: Dictionary=context.duplicate(true)
	row.file=label+".png";row.png_error=error;rows.append(row)
	print("FURNITURE_SHOT ",label," error=",error)

func control(item: Node3D, label: String, context: Dictionary, parameters: Array[String]) -> void:
	var changed: Array[Dictionary]=[]
	var seen: Array[int]=[]
	var meshes: Array[MeshInstance3D]=WorldBuilder.find_meshes(item)
	if item is MeshInstance3D and item not in meshes:meshes.append(item)
	for mesh: MeshInstance3D in meshes:
		for surface: int in mesh.mesh.get_surface_count():
			var material: ShaderMaterial=mesh.get_active_material(surface) as ShaderMaterial
			if material==null or material.get_instance_id() in seen:continue
			seen.append(material.get_instance_id())
			for parameter: String in parameters:
				var value: Variant=material.get_shader_parameter(parameter)
				if value is float and float(value)>0.0:
					changed.append({"material":material,"parameter":parameter,"value":value})
					material.set_shader_parameter(parameter,0.0)
	if not changed.is_empty():
		var details: Dictionary=context.duplicate(true);details.control=parameters;details.surfaces=changed.size()
		await capture(label,details)
	for record: Dictionary in changed:record.material.set_shader_parameter(record.parameter,record.value)

func _run() -> void:
	if folder.is_empty() or OS.get_environment("HARUMACHI_SAVE_DIR").is_empty():get_tree().quit(2);return
	DirAccess.make_dir_recursive_absolute(folder)
	while not main.loading_ready or Loading.scene_busy:await frames(1)
	GameState.new_game();GameState.clock_paused=true;GameState._ui_locks.clear()
	GameState.quests.Q00={"state":"done","step":2};GameState.flags.erase("arrival_home")
	GameState.day=2;GameState.minute=660;GameState.weather="sunny";Progress.quiet=true;NPC.roam_enabled=false
	main.ui.instant=true;main.ui.auto=true;main._restore();main.ui.dialogue_end()
	main.player.process_mode=Node.PROCESS_MODE_DISABLED
	main.rig.process_mode=Node.PROCESS_MODE_DISABLED
	camera=Camera3D.new();camera.near=.04;camera.far=210;camera.fov=43;main.add_child(camera)
	for sample: Array in TARGETS:
		var region: String=sample[0];var key: String=sample[1];var label: String=sample[2];var variant: int=sample[3]
		if not filter.is_empty() and label not in filter.split(","):continue
		GameState.minute=1210 if variant==2 else 660
		GameState.weather="rain" if variant==4 else "sunny"
		var scope: Node=main.world
		if InteriorBuilder.SPECS.has(region):
			if main.room_kind!=region:await main.enter_interior(region)
			scope=main.world.interiors[region]
		elif region=="house":
			scope=main.world.house
			var furniture: Node3D=target(scope,key,region)
			if furniture!=null:main._put_in_room(furniture.global_position+Vector3.UP*.05)
		else:
			if main.in_room:await main.exit_interior()
			main.in_room=false;main.room_kind="";GameState.player_in_room=false
			main.world.set_region("town" if region=="town" else "farm");main.world.set_indoor_look(false)
			if region=="farm":scope=main.world.farm
			if region=="lake":scope=main.world.farm.lakeside
		main.world.update_time(GameState.minute,GameState.weather,true);main._sync_weather()
		main.ui.root.visible=false;main.marker.visible=false;main.player.visible=false
		main.shop_life._caption_left=0.0;main.shop_life._caption.visible=false
		for npc: Node3D in main.npcs.values():npc.visible=false
		var item: Node3D=target(scope,key,region)
		if item==null:failures.append(label+": target missing "+key);continue
		var bounds: AABB=WorldBuilder.local_aabb(item)
		if item is MeshInstance3D:bounds=(item as MeshInstance3D).get_aabb()
		var extent: float=maxf(.65,maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z)))
		var centre: Vector3=item.to_global(bounds.get_center())
		var direction:=Vector3(-.65,.60,1.38) if variant==1 else Vector3(.62,.64,1.42)
		if label in ["coffee","fridge","freezer"]:direction=Vector3(-.75,.75,1.15)
		if label.begins_with("cafe"):direction=Vector3(.40,1.0,-1.30) if variant==0 else Vector3(-.60,.80,-1.25)
		if label in ["family_table","drawing_desk"]:direction=Vector3(.45,1.10,.80)
		if label=="coffee_detail":direction=Vector3(.12,.65,1.15);centre+=Vector3.UP*.20
		if label=="postal_detail":extent=.85;direction=Vector3(-.20,1.1,1.05);centre+=Vector3(-.25,.02,.04)
		var offset: Vector3=item.global_basis.orthonormalized()*direction*extent
		if label in ["home_books","home_tansu"]:offset=Vector3(1.25,.25,.20)*extent
		camera.global_position=centre+offset;camera.look_at(centre);camera.make_current();camera.reset_physics_interpolation()
		if variant==5:
			main.rig.snap();camera.global_transform=main.rig.cam.global_transform;camera.fov=main.rig.cam.fov
		else:camera.fov=43
		var context: Dictionary={"region":region,"node":str(item.get_path()),"minute":GameState.minute,"weather":GameState.weather,"camera":vec(camera.global_position),"target":vec(centre),"bounds_size":vec(bounds.size)}
		await capture(label,context)
		if label in ["oven","bakery_counter","cafe","toolshed","town_bench"]:
			await control(item,label+"_gloss_off",context,["sheen_strength","gloss_strength"])
			await control(item,label+"_wear_off",context,["wear_strength"])
	FileAccess.open(folder.path_join("manifest.json"),FileAccess.WRITE).store_string(JSON.stringify({"kind":"actual_native_furniture_diagnostic","passed":failures.is_empty(),"failures":failures,"screenshots":rows},"\t"))
	Audio.silence();get_tree().quit(0 if failures.is_empty() else 1)

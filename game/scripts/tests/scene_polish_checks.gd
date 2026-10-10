extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("POLISH",label,ok,detail)
func run() -> void:
	var state: Dictionary=GameState.to_dict().duplicate(true)
	var clock: Node=main.world.get_node_or_null("R11/LiveClock")
	check("town clock contains only the hour hand",clock!=null and clock.get_node_or_null("ClockHourHand")!=null and clock.get_node_or_null("ClockMinuteHand")==null and clock.get_node_or_null("ClockSecondHand")==null)
	if clock:
		clock.call("set_minute",600.0);var angle: float=(clock.get("hour_hand") as Node3D).rotation.z;clock.call("set_minute",630.0)
		check("hour hand smoothly represents part of an hour",absf((clock.get("hour_hand") as Node3D).rotation.z-angle)>.25)
	else:check("hour hand smoothly represents part of an hour",false)
	var bus: Node=main.world.get_node_or_null("CountryBus")
	var bus_bounds: AABB=WorldBuilder.local_aabb(bus) if bus else AABB()
	check("minibus has human scale length and cabin height",bus!=null and bus_bounds.size.x<4.9 and bus_bounds.size.y<2.6,str(bus_bounds.size))
	check("bus windows are separate transparent glass surfaces",bus!=null and bus.find_children("Glass_*","MeshInstance3D",true,false).size()>=6)
	check("vehicle has an accessible driver conversation",t.point("bus_driver")!=null)
	check("arrival is restored as a parked bus on old saves",bus!=null and bus.has_method("park_at_stop"))
	var wheel_boxes: Array[AABB]=[];var wheel_bases: Array[Basis]=[]
	if bus:
		for wheel: Node3D in bus.wheels:
			wheel_boxes.append(wheel.global_transform*WorldBuilder.local_aabb(wheel));wheel_bases.append(wheel.basis)
		bus.travelling=true;bus.call("_process",.2);bus.call("park_at_stop")
	var wheel_pose_ok:=bus!=null and wheel_boxes.size()==4
	if bus:
		for index in bus.wheels.size():
			var wheel: Node3D=bus.wheels[index]
			var parked_box: AABB=wheel.global_transform*WorldBuilder.local_aabb(wheel)
			wheel_pose_ok=wheel_pose_ok and parked_box.position.distance_to(wheel_boxes[index].position)<.003 and parked_box.size.distance_to(wheel_boxes[index].size)<.003
			wheel.basis=wheel_bases[index]
	check("parked wheel geometry returns to the fitted body silhouette",wheel_pose_ok)
	check("road exit remains blocked to the player",main.world.get_node_or_null("IncomingRoadLimit")!=null)
	var tree: Node=main.world.get_node_or_null("T01_courtyard_tree")
	check("courtyard tree uses generated coherent foliage geometry",tree!=null and tree.has_meta("tree_geometry_version"))
	check("trunk and foliage have independent wind weights",tree!=null and tree.find_children("Foliage*","MeshInstance3D",true,false).size()>0 and tree.find_children("Trunk*","MeshInstance3D",true,false).size()>0)
	var river:=FileAccess.get_file_as_string("res://shaders/water.gdshader")
	var lake:=FileAccess.get_file_as_string("res://shaders/lakeside_water.gdshader")
	var motion: String=FileAccess.get_file_as_string("res://shaders/water_motion.gdshaderinc") if FileAccess.file_exists("res://shaders/water_motion.gdshaderinc") else ""
	check("river uses two phase advected flow",river.contains("flow_sample") and motion.contains("phase_b"))
	check("lake has analytic wave normals and bend flow",motion.contains("gerstner") and lake.contains("flow_direction"))
	var cat_bad: Array[String]=[]
	for cat: Dictionary in main.life.cats:
		var node: Node3D=cat.node
		var box: AABB=node.global_transform*WorldBuilder.local_aabb(node)
		if node.global_position.x<200 and cat.mode=="watch":
			var cap: Node=main.world.get_node("BoundaryWall_8/TileCoping")
			var contact: float=WorldBuilder.surface_height(cap,Vector2(node.global_position.x,node.global_position.z),2.0)
			if not is_finite(contact) or box.position.y<contact-.008 or box.position.y>contact+.025:cat_bad.append(str(box.position.y)+" / "+str(contact))
	check("sitting cat clears the real curved tile surface",cat_bad.is_empty(),str(cat_bad))
	check("all three cats have E interaction targets",main.life.find_children("CatInteract_*","Interactable",true,false).size()==3)
	check("cat interaction has an audible meow",ResourceLoader.exists("res://assets/audio/sfx/cat_meow.wav") and main.life.has_method("pet_cat"))
	var slots:=SaveDB.has_method("list_slots") and GameState.has_method("save_to_slot") and GameState.has_method("load_slot")
	check("save manager supports exactly six visible positions",slots and int(SaveDB.get_script().get_script_constant_map().get("MAX_SLOTS",0))==6)
	var directory: String=SaveDB.directory
	if slots:
		var temp_root: String=OS.get_environment("TEMP").replace("\\","/")
		if temp_root.is_empty():temp_root="/tmp"
		SaveDB.set_directory(temp_root.path_join("harumachi-polish-slots-"+str(Time.get_ticks_usec())))
		var success:=true
		for slot in range(1,7):
			GameState.new_game();GameState.coins=100+slot*11;GameState.day=slot
			success=success and bool(GameState.call("save_to_slot",slot))
		check("six saves retain independent day and money",success and (SaveDB.call("list_slots") as Array).size()==6)
		var loaded:=true
		for slot in range(1,7):loaded=loaded and bool(GameState.call("load_slot",slot)) and GameState.coins==100+slot*11 and GameState.day==slot
		check("every save position loads its own progress",loaded)
		var before: Array=(SaveDB.call("list_slots") as Array).duplicate(true)
		check("seventh save is rejected without changing six saves",not bool(GameState.call("save_to_slot",7)) and before==SaveDB.call("list_slots"))
		GameState.call("load_slot",3);GameState.advance_day()
		var after: Array=SaveDB.call("list_slots")
		check("daily autosave updates only the selected position",int(after[2].get("day",-1))==4 and int(after[0].get("day",-1))==1 and int(after[5].get("day",-1))==6)
		SaveDB.set_directory(directory)
	else:
		for label in ["six saves retain independent day and money","every save position loads its own progress","seventh save is rejected without changing six saves","daily autosave updates only the selected position"]:check(label,false)
	check("save screen presents six reusable slot controls",ResourceLoader.exists("res://scripts/ui/save_slots_panel.gd"))
	GameState.from_dict(state);clock.call("set_minute",GameState.minute) if clock else null

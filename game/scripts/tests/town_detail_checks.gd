extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("TOWN_DETAIL",label,ok,detail)
func run() -> void:
	var world: Node=main.world
	var saved_time: float=GameState.minute
	main.in_room=false;world.call("set_region","town");await t.frames(3)
	var bus: Node=world.get_node_or_null("CountryBus")
	var generated:=bus.find_children("*","Node3D",true,false).any(func(n: Node):return n.get_meta("model_id","")=="B01_bus") if bus else false
	check("bus uses the generated vehicle mesh",generated)
	var articulated: bool=bus!=null and bus.get("doors").size()==2 and bus.get("wheels").size()==4
	check("generated bus has two door leaves and four separate wheels",generated and articulated)
	if articulated:
		bus.call("open_doors",1);check("door opening changes the actual generated leaf pose",generated and absf((bus.get("doors")[0] as Node3D).rotation.y)>1.0);bus.call("open_doors",0)
	else:check("door opening changes the actual generated leaf pose",false)
	var road:=world.get_node_or_null("IncomingRoad") as MeshInstance3D
	check("incoming road continues sixty metres beyond the village",road!=null and road.mesh.get_aabb().size.x>=59)
	var space: PhysicsDirectSpaceState3D=main.get_world_3d().direct_space_state
	var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-59,.8,-11),Vector3(-48,.8,-11),WorldBuilder.L_SOLID|WorldBuilder.L_BLOCK))
	check("west road opening has no wall across the arrival path",hit.is_empty(),str(hit.get("position","")))
	check("road has sandy shoulders",world.get_node_or_null("RoadShoulder_-157")!=null and world.get_node_or_null("RoadShoulder_-76")!=null)
	var stop:=world.get_node_or_null("R06")
	for title: String in ["StopName","Timetable","RouteMap","BusStopPole"]:
		var panel:=stop.get_node_or_null(title) if stop else null
		check("bus shelter has readable "+title,panel!=null and panel.find_children("*","Label3D",true,false).all(func(n: Node):return n.get("font_size")>=128))
	var clock_model:=world.get_node_or_null("R11")
	var clock:=clock_model.get_node_or_null("LiveClock") if clock_model else null
	check("clock replaces baked marks with sixty sharp ticks",clock!=null and clock.find_children("DialTick_*","MeshInstance3D",false,false).size()==60)
	check("clock numerals are independent high resolution glyphs",clock!=null and clock.find_children("*","Label3D",true,false).size()==12)
	if clock:
		clock.call("set_minute",600.0);var before_hour: float=(clock.get("hour_hand") as Node3D).rotation.z
		clock.call("set_minute",615.0)
		check("hour hand follows game time",absf((clock.get("hour_hand") as Node3D).rotation.z-before_hour)>.10)
		clock.call("set_minute",saved_time)
	else:check("hour hand follows game time",false)
	var decorated:=true
	for wall: Node in world.find_children("BoundaryWall_*","MeshInstance3D",false,false):decorated=decorated and wall.get_node_or_null("TileCoping")!=null and wall.get_node_or_null("CopingTileEndRosettes")!=null
	check("every boundary wall has roof tiles and end rosettes",decorated)
	var painted:=true
	for kind: String in ["grass","stone","sand"]:painted=painted and ResourceLoader.exists("res://assets/textures/town_detail/"+kind+".png")
	check("grass stone and sand use authored anime textures",painted)
	check("southern gardens contain actual grass clumps",int(world.get_meta("south_grass_clumps",0))>1000)
	var pit:=world.get_node_or_null("P06")
	check("sandbox has a separate detailed sand surface",pit!=null and pit.get_node_or_null("SandpitSurface")!=null)
	check("physical lettering is upgraded throughout town",int(world.get_meta("clear_sign_count",0))>=20)
	GameState.minute=saved_time

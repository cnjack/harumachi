class_name TransitStop
extends RefCounted
## Clear physical route information replaces lettering baked into reconstructed textures.
static func build(world: WorldBuilder) -> void:
	var shelter:=world.get_node_or_null("R06") as Node3D
	if shelter:
		var header:=ClearSignage.plate(shelter,"StopName",Vector2(2.4,.28),Vector3(0,2.13,1.02),0,Color(.19,.40,.36))
		header.add_child(ClearSignage.label("晴町  HARUMACHI",Vector3(0,0,.02),0,.21,Color(.99,.96,.83)))
		ClearSignage.plate(shelter,"RouteBacking",Vector2(2.42,1.12),Vector3(0,1.53,.15),0,Color(.32,.40,.38))
		var timetable:=ClearSignage.plate(shelter,"Timetable",Vector2(1.05,1.05),Vector3(.62,1.53,.18),0,Color(.96,.93,.81))
		for index in 5:
			var row: String=["路 线  07","晴町 → 青海駅","08:10   10:40","13:20   16:50","末班车  18:30"][index]
			timetable.add_child(ClearSignage.label(row,Vector3(0,.37-.18*index,.025),0,.11))
		var map:=ClearSignage.plate(shelter,"RouteMap",Vector2(1.05,1.05),Vector3(-.62,1.53,.18),0,Color(.94,.94,.83))
		map.add_child(ClearSignage.label("晴町 · 青海線",Vector3(0,.36,.025),0,.13))
		for i in 3:
			var y:=.13-.23*i
			var dot:=MeshInstance3D.new();dot.name="RouteDot_%d"%i;var circle:=SphereMesh.new();circle.radius=.034;circle.height=.068;dot.mesh=circle;dot.material_override=JapaneseArchitecture._flat(Color(.19,.42,.37));dot.position=Vector3(-.29,y,.027);map.add_child(dot)
			map.add_child(ClearSignage.label(["晴町","山下橋","青海駅"][i],Vector3(.08,y,.025),0,.12))
		var pole:=ClearSignage.plate(shelter,"BusStopPole",Vector2(.40,1.35),Vector3(1.78,1.63,.61),0,Color(.18,.39,.38))
		pole.add_child(ClearSignage.label("BUS\n07\n晴町\n青海線",Vector3(0,0,.025),0,.14,Color(1,.97,.86)))
	# The incoming road passes through the opened west boundary, continuing into the hills.
	var asphalt:=WorldBuilder.ground_material("gravel");asphalt.set_shader_parameter("tint",Color(.39,.44,.48));asphalt.set_shader_parameter("tile",4.0)
	var road: MeshInstance3D=world.call("_plane",[-112.0,-14.4,-51.9,-7.6],asphalt,.01)
	road.name="IncomingRoad";road.set_meta("external_road",true)
	var sand:=WorldBuilder.ground_material("sand")
	for edge in [-15.7,-7.6]:
		var shoulder: MeshInstance3D=world.call("_plane",[-112.0,edge,-52.0,edge+1.3],sand,.004)
		shoulder.name="RoadShoulder_%d"%int(edge*10)
	var stripe:=JapaneseArchitecture._flat(Color(.95,.92,.75))
	for index in 10:
		var mark:=MeshInstance3D.new();mark.name="IncomingRoadMark_%d"%index;var mesh:=PlaneMesh.new();mesh.size=Vector2(2.4,.12);mark.mesh=mesh;mark.material_override=stripe;mark.position=Vector3(-55.0-index*6,.019,-11);world.add_child(mark)
	for index in 5:
		var tree:=world.spawn("T03_round_ginkgo",Vector3(-62-index*9,0,-18.5),index*65,0,world,.8)
		if tree:WorldBuilder.rest_on_terrain(tree,0)
	var verge:=WorldBuilder.ground_material("grass")
	var verges: Array=[[-112.0,-25.0,-52.0,-15.7],[-112.0,-6.3,-52.0,1.5]]
	for index in verges.size():
		var field: MeshInstance3D=world.call("_plane",verges[index],verge,.001);field.name="RoadsideGrass_%d"%index
	var tufts:=GrassField.new();tufts.name="ApproachGrass";world.add_child(tufts);tufts.lawn(verges,[],"meadow",2.0,612)
	for side in [-15.3,-6.7]:
		for index in 10:
			var post:=MeshInstance3D.new();post.name="RoadRailPost_%d_%d"%[int(side*10),index];var mesh:=BoxMesh.new();mesh.size=Vector3(.055,.7,.055);post.mesh=mesh;post.material_override=stripe;post.position=Vector3(-60-index*5,.35,side);world.add_child(post)
		var rail:=MeshInstance3D.new();rail.name="RoadRail_%d"%int(side*10);var beam:=BoxMesh.new();beam.size=Vector3(48,.16,.055);rail.mesh=beam;rail.material_override=stripe;rail.position=Vector3(-82,.55,side);world.add_child(rail)
	# Walkable village stops at the approach; the vehicle can continue on the scenic road.
	var limit:=StaticBody3D.new();limit.name="IncomingRoadLimit";limit.collision_layer=WorldBuilder.L_BLOCK
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(.3,3,8);collision.shape=shape;collision.position=Vector3(-61,1,-11);limit.add_child(collision);world.add_child(limit)
	var sandbox:=world.get_node_or_null("P06") as Node3D
	if sandbox:
		var patch:=MeshInstance3D.new();patch.name="SandpitSurface";var plane:=PlaneMesh.new();plane.size=Vector2(1.61,1.61);patch.mesh=plane;patch.material_override=WorldBuilder.ground_material("sand");patch.position.y=.31;sandbox.add_child(patch)
	_replace_small_signs(world)

static func _replace_small_signs(world: WorldBuilder) -> void:
	var directions:=world.get_node_or_null("R09") as Node3D
	if directions:
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(directions):
			var old: StandardMaterial3D=mesh.get_active_material(0) as StandardMaterial3D
			var finish:=ShaderMaterial.new();finish.shader=load("res://shaders/direction_support.gdshader")
			finish.set_shader_parameter("albedo_tex",old.albedo_texture)
			finish.set_shader_parameter("part_transform",directions.global_transform.affine_inverse()*mesh.global_transform);mesh.material_override=finish
		for index in 3:
			# The post faces west: local -X points north to the main street;
			# local +X points south into the residential lane.
			var arrow:=ClearSignage.arrow(directions,"ClearDirection_%d"%index,Vector3(.10,2.15-.34*index,-.016),index!=1,[Color(.60,.48,.28),Color(.34,.48,.37),Color(.62,.36,.23)][index])
			var caption: String=["商店街","住宅支巷","农园 · 沿主街向东"][index]
			var em: float=.125 if index<2 else .075
			arrow.add_child(ClearSignage.label(caption,Vector3(0,0,.017),0,em,Color(.99,.98,.88)))
			# Back lettering is placed beside the measured upright, not behind it.
			var back_caption: String=caption if index<2 else "农园\n沿主街向东"
			arrow.add_child(ClearSignage.label(back_caption,Vector3(.235,0,-.017),PI,em if index<2 else .068,Color(.99,.98,.88)))
	var chalk:=world.get_node_or_null("A13_chalkboard") as Node3D
	if chalk:
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(chalk):
			var old: StandardMaterial3D=mesh.get_active_material(0) as StandardMaterial3D
			var finish:=ShaderMaterial.new();finish.shader=load("res://shaders/chalk_face.gdshader")
			finish.set_shader_parameter("albedo_tex",old.albedo_texture)
			finish.set_shader_parameter("part_transform",chalk.global_transform.affine_inverse()*mesh.global_transform)
			mesh.material_override=finish
		var menu:=Node3D.new();menu.name="ClearCafeMenu";chalk.add_child(menu)
		menu.position=Vector3(0,.568,.124);menu.rotation.x=-.215
		var heading:=ClearSignage.label("本日烘焙",Vector3(0,.23,.005),0,.078,Color(.97,.94,.83));menu.add_child(heading)
		for row: int in 3:
			var item_id: String=["melon_pan","cream_bun","donut"][row]
			var item: Dictionary=GameState.item(item_id)
			var title:=ClearSignage.label(str(item.name),Vector3(-.052,.09-row*.125,.005),0,.051,Color(.96,.94,.82))
			menu.add_child(title)
			menu.add_child(ClearSignage.label(str(int(item.get("price",0))),Vector3(.205,.09-row*.125,.005),0,.057,Color(.96,.94,.82)))
	var board:=world.get_node_or_null("P02") as Node3D
	if board:
		var notice:=ClearSignage.plate(board,"ClearNoticeHeader",Vector2(1.95,.24),Vector3(0,1.94,.24),0,Color(.35,.24,.16))
		notice.add_child(ClearSignage.label("晴町  お知らせ",Vector3(0,0,.025),0,.18,Color(.98,.95,.84)))

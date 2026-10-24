class_name TransitStop
extends RefCounted
## Clear physical route information replaces lettering baked into reconstructed textures.
static func build(world: WorldBuilder) -> void:
	var shelter:=world.get_node_or_null("R06") as Node3D
	if shelter:
		_station_name(shelter)
		ClearSignage.plate(shelter,"RouteBacking",Vector2(2.42,1.12),Vector3(0,1.53,.15),0,Color(.32,.40,.38))
		var timetable: Node3D=ModularProps.part(world,shelter,"MS07_timetable_case","Timetable",Vector3(.62,1.005,.18),Vector3(1.05,1.05,.08))
		for index in 5:
			var row: String=["路 线  07","晴町 → 青海駅","08:10   10:40","13:20   16:50","末班车  18:30"][index]
			timetable.add_child(ClearSignage.label(row,Vector3(0,.87-.18*index,.052),0,.11))
		var map: Node3D=ModularProps.part(world,shelter,"MS07_timetable_case","RouteMap",Vector3(-.62,1.005,.18),Vector3(1.05,1.05,.08))
		map.add_child(ClearSignage.label("晴町 · 青海線",Vector3(0,.86,.052),0,.13))
		for i in 3:
			var y:=.63-.23*i
			var dot:=MeshInstance3D.new();dot.name="RouteDot_%d"%i;var circle:=SphereMesh.new();circle.radius=.034;circle.height=.068;dot.mesh=circle;dot.material_override=JapaneseArchitecture._flat(Color(.19,.42,.37));dot.position=Vector3(-.29,y,.054);map.add_child(dot)
			map.add_child(ClearSignage.label(["晴町","山下橋","青海駅"][i],Vector3(.08,y,.052),0,.12))
		var pole: Node3D=ModularProps.part(world,shelter,"MS06_bus_pole","BusStopPole",Vector3(1.78,0,.61))
		if pole:
			ModularProps.engrave(pole,"晴町",Vector4(0,2.09,.29,.15),true,.72)
			var pole_body:=StaticBody3D.new();pole_body.name="PoleCollision";pole_body.collision_layer=WorldBuilder.L_SOLID;pole_body.set_meta("model_part",true)
			var pole_shape:=CollisionShape3D.new();var pole_volume:=CylinderShape3D.new();pole_volume.radius=.07;pole_volume.height=2.0
			pole_shape.shape=pole_volume;pole_shape.position.y=1.0;pole_body.add_child(pole_shape);pole.add_child(pole_body)

	# The incoming road passes through the opened west boundary, continuing into the hills.
	var asphalt:=WorldBuilder.ground_material("gravel");asphalt.set_shader_parameter("tint",Color(.39,.44,.48));asphalt.set_shader_parameter("tile",4.0)
	var road: MeshInstance3D=world.call("_plane",[-330.0,-14.4,-51.9,-7.6],asphalt,.01)
	road.name="IncomingRoad";road.set_meta("external_road",true)
	var sand:=WorldBuilder.ground_material("sand")
	for edge in [-15.7,-7.6]:
		var shoulder: MeshInstance3D=world.call("_plane",[-330.0,edge,-52.0,edge+1.3],sand,.004)
		shoulder.name="RoadShoulder_%d"%int(edge*10)
	var stripe:=JapaneseArchitecture._flat(Color(.95,.92,.75))
	for index in 46:
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

static func _station_name(shelter: Node3D) -> void:
	# The original R06 eave is at z=.903 around y=2.27. Two bent steel
	# brackets bridge it to this 78 mm casing; the bottom stays above 2.02 m.
	var header := Node3D.new()
	header.name = "StopName"
	header.position = Vector3(-.35, 2.185, 1.01)
	shelter.add_child(header)
	var casing: StandardMaterial3D = JapaneseArchitecture._flat(Color(.16, .30, .28))
	casing.specular_mode = BaseMaterial3D.SPECULAR_TOON
	casing.metallic = .12
	casing.metallic_specular = .22
	casing.roughness = .58
	var enamel: StandardMaterial3D = JapaneseArchitecture._flat(Color(.20, .40, .35))
	enamel.specular_mode = BaseMaterial3D.SPECULAR_TOON
	enamel.metallic_specular = .18
	enamel.roughness = .62
	var steel: StandardMaterial3D = JapaneseArchitecture._flat(Color(.42, .48, .44))
	steel.specular_mode = BaseMaterial3D.SPECULAR_TOON
	steel.metallic = .38
	steel.metallic_specular = .25
	steel.roughness = .55
	_sign_block(header, "Board", Vector3(2.46, .32, .078), Vector3.ZERO, casing, .006)
	# A distinct enamel insert seats in the casing; only 0.8 mm separates the
	# shaded printed glyphs from its actual front triangles.
	_sign_block(header, "EnamelFace", Vector3(2.34, .238, .012), Vector3(0, 0, .035), enamel, .002)
	var station: Label3D = ClearSignage.label("晴町", Vector3(-.73, 0, .0418), 0, .205, Color(.98, .96, .84))
	station.name = "StationNameInk"
	station.shaded = true
	station.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ClearSignage.fit(station, Vector2(.72, .206), .006)
	header.add_child(station)
	var romanization: Label3D = ClearSignage.label("HARUMACHI", Vector3(.38, 0, .0418), 0, .14, Color(.98, .96, .84))
	romanization.name = "RomanizationInk"
	romanization.shaded = true
	romanization.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ClearSignage.fit(romanization, Vector2(1.30, .168), .006)
	header.add_child(romanization)
	for side: int in 2:
		var mount := Node3D.new()
		mount.name = "RoofMount_Left" if side == 0 else "RoofMount_Right"
		mount.position = Vector3(-.92 if side == 0 else .92, .085, -.105)
		header.add_child(mount)
		# Keep both screws on the flat timber fascia, below its projecting
		# roof lip. The rear enters the measured face by only about 1 mm.
		_sign_block(mount, "EaveAnchor", Vector3(.105, .050, .012), Vector3(0, -.012, .0025), steel, .001)
		_sign_block(mount, "BentArm", Vector3(.070, .016, .084), Vector3(0, -.025, .036), steel, .001)
		_sign_block(mount, "RearStrap", Vector3(.105, .16, .014), Vector3(0, -.040, .071), steel, .001)
		for bolt: int in 2:
			_sign_bolt(mount, "EaveBolt_%d" % bolt, Vector3(-.027 if bolt == 0 else .027, -.012, .0105), steel)
	for column: int in 2:
		for row: int in 2:
			_sign_bolt(header, "CasingBolt_%d_%d" % [column, row], Vector3(-1.193 if column == 0 else 1.193, -.126 if row == 0 else .126, .041), steel)

static func _sign_bolt(parent: Node3D, label_name: String, at: Vector3, material: Material) -> void:
	var bolt := MeshInstance3D.new()
	bolt.name = label_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .0075
	cylinder.bottom_radius = .009
	cylinder.height = .004
	cylinder.radial_segments = 12
	bolt.mesh = cylinder
	bolt.material_override = material
	bolt.position = at
	bolt.rotation.x = PI * .5
	parent.add_child(bolt)
	_sign_block(parent, label_name + "Slot", Vector3(.009, .0015, .0008), at + Vector3(0, 0, .0022), JapaneseArchitecture._flat(Color(.22, .29, .27)), .0001)

static func _sign_block(parent: Node3D, label_name: String, size: Vector3, at: Vector3, material: Material, bevel: float) -> MeshInstance3D:
	var block := MeshInstance3D.new()
	block.name = label_name
	block.position = at
	block.mesh = _sign_casing_mesh(size, bevel)
	block.material_override = material
	parent.add_child(block)
	return block

static func _sign_ring(half_size: Vector2, corner: float, depth: float) -> PackedVector3Array:
	var x: float = half_size.x
	var y: float = half_size.y
	return PackedVector3Array([
		Vector3(-x + corner, -y, depth), Vector3(-x, -y + corner, depth),
		Vector3(-x, y - corner, depth), Vector3(-x + corner, y, depth),
		Vector3(x - corner, y, depth), Vector3(x, y - corner, depth),
		Vector3(x, -y + corner, depth), Vector3(x - corner, -y, depth),
	])

static func _sign_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	for point: Vector3 in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(point)

static func _sign_casing_mesh(size: Vector3, bevel: float) -> ArrayMesh:
	# Closed solid with real corner and depth chamfers, rather than a bright
	# line pretending to be an edge. The face remains flat for the lettering.
	var half_size := Vector2(size.x, size.y) * .5
	var corner: float = minf(bevel * 2.5, minf(size.x, size.y) * .15)
	var depth: float = size.z * .5
	var rings: Array[PackedVector3Array] = [
		_sign_ring(half_size - Vector2.ONE * bevel, corner * .5, -depth),
		_sign_ring(half_size, corner, -depth + bevel),
		_sign_ring(half_size, corner, depth - bevel),
		_sign_ring(half_size - Vector2.ONE * bevel, corner * .5, depth),
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge: int in 8:
		var following: int = (edge + 1) % 8
		_sign_triangle(surface, Vector3(0, 0, -depth), rings[0][following], rings[0][edge])
		_sign_triangle(surface, Vector3(0, 0, depth), rings[3][edge], rings[3][following])
		for band: int in 3:
			_sign_triangle(surface, rings[band + 1][edge], rings[band][edge], rings[band][following])
			_sign_triangle(surface, rings[band + 1][edge], rings[band][following], rings[band + 1][following])
	return surface.commit()

static func _replace_small_signs(world: WorldBuilder) -> void:
	var directions:=world.get_node_or_null("R09") as Node3D
	if directions:
		ModularProps.directions(directions,["商店街","住宅支巷","河边农园"])
	var chalk:=world.get_node_or_null("A13_chalkboard") as Node3D
	if chalk:
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(chalk):
			var old: StandardMaterial3D=mesh.get_active_material(0) as StandardMaterial3D
			var finish:=ShaderMaterial.new();finish.shader=load("res://shaders/chalk_face.gdshader")
			finish.set_shader_parameter("albedo_tex",old.albedo_texture)
			finish.set_shader_parameter("part_transform",Projection(chalk.global_transform.affine_inverse()*mesh.global_transform))
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
		SurfaceFinish.notice_frame(board)
		var notice:=ClearSignage.plate(board,"ClearNoticeHeader",Vector2(1.95,.24),Vector3(0,1.94,.24),0,Color(.35,.24,.16))
		var header_board:=notice.get_node("Board") as MeshInstance3D
		header_board.material_override=SurfaceFinish.timber(header_board.mesh.get_aabb(),Color(.35,.27,.18),0,true)
		ClearSignage.pins(notice,Vector2(1.95,.24))
		notice.add_child(ClearSignage.label("晴町  お知らせ",Vector3(0,0,.025),0,.18,Color(.98,.95,.84)))

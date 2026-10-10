class_name PublicRoomLife
extends RefCounted
## Furniture groups have ordinary uses first; work props occupy their own activity bay.
static func fixture(room: InteriorBuilder,root: Node3D,id: String,label: String,at: Vector3,yaw: float=0.0) -> Node3D:
	var node:=room.wb.spawn(id,at,yaw,0,root);node.name=label;HouseBuilder.toonify(node)
	# Individual seats and tabletops block movement; the gaps between chairs remain usable.
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(node):
		if not (str(mesh.name).contains("Seat") or str(mesh.name).contains("Back") or str(mesh.name).contains("Top") or str(mesh.name).contains("Cabinet")):continue
		var body:=StaticBody3D.new();body.collision_layer=WorldBuilder.L_SOLID;body.collision_mask=0;body.set_meta("model_part",true)
		var collision:=CollisionShape3D.new();var volume:=BoxShape3D.new();volume.size=mesh.get_aabb().size;collision.shape=volume;collision.position=mesh.get_aabb().get_center();body.add_child(collision);mesh.add_child(body)
	return node

static func point(root: Node3D,id: String,at: Vector3,radius: float=1.0) -> Interactable:
	var node:=Interactable.new();node.name=id;node.id=id;node.position=at;node.radius=radius;root.add_child(node);return node

static func seat(root: Node3D,id: String,at: Vector3,yaw: float,stand: Vector3,table_at: Vector3) -> void:
	var node:=point(root,id,stand+Vector3.UP*.75,1.0)
	node.set_meta("seat_position",at);node.set_meta("seat_yaw",yaw);node.set_meta("stand_position",stand);node.set_meta("table_position",table_at)

static func book(root: Node3D,label: String,at: Vector3,support: Node3D,tint: Color) -> void:
	var cover:=PublicPlaceArt.box(root,label,Vector3(.22,.025,.29),at+Vector3.UP*.0125,PublicPlaceArt.matte(tint));PublicPlaceArt.supported(cover,support)
	PublicPlaceArt.box(root,label+"Pages",Vector3(.20,.018,.27),at+Vector3.UP*.025,PublicPlaceArt.matte(Color(.93,.89,.76)))

static func build(room: InteriorBuilder,root: Node3D) -> void:
	var clock:=PublicRoomClock.new();clock.position=Vector3(1.5,2.65,-4.38) if room.kind=="workroom" else Vector3(-1.9,2.45,-3.88);root.add_child(clock)
	if room.kind=="workroom":
		var table:=fixture(room,root,"P_community_table","SharedNeighbourTable",Vector3(-3.1,0,2.1))
		PublicPlaceArt.box(root,"SharedWovenRug",Vector3(3.05,.006,2.5),Vector3(-3.1,.006,2.1),PublicPlaceArt.canvas(Color(.63,.66,.55)))
		book(root,"TownJournal",Vector3(-3.55,.75,2.1),table,Color(.38,.48,.45))
		book(root,"NeighbourNewspaper",Vector3(-2.85,.75,1.95),table,Color(.87,.83,.68))
		var tray:=PublicPlaceArt.tray(root,"SharedTeaTray",Vector3(-3.12,.75,2.35),Vector2(.37,.26),table)
		PublicPlaceArt.prop(room,root,"W11_ceramic_set",Vector3(-3.12,.775,2.35),.13,tray)
		for index in 2:
			var at:=Vector3(4.35,0,1.35+index*1.9)
			fixture(room,root,"P_reading_chair","ReadingChair_%d"%index,at,0 if index==0 else 180)
			seat(root,"public_reading_%d"%index,at,0 if index==0 else 180,at+Vector3(-.85,0,0),Vector3(4.35,.55,2.3))
		var reading:=PublicPlaceArt.cylinder(root,"ReadingTeaTable",Vector3(4.35,.525,2.3),.30,.05,PublicPlaceArt.wood())
		PublicPlaceArt.cylinder(root,"ReadingTableLeg",Vector3(4.35,.25,2.3),.045,.50,PublicPlaceArt.wood())
		book(root,"LocalHistoryBook",Vector3(4.35,.55,2.3),reading,Color(.45,.57,.59))
		fixture(room,root,"P_low_bookcase","NeighbourBookcase",Vector3(5.65,0,2.3),-90)
		var tea:=PublicPlaceArt.bench(root,"NeighbourTeaStation",Vector3(-2.20,0,-3.93),1.60,.68,.86)
		var tea_tray:=PublicPlaceArt.tray(root,"TeaServiceTray",Vector3(-2.48,.86,-3.93),Vector2(.48,.34),tea)
		PublicPlaceArt.prop(room,root,"W11_ceramic_set",Vector3(-2.48,.885,-3.93),.23,tea_tray)
		PublicPlaceArt.box(root,"SinkRim",Vector3(.44,.024,.39),Vector3(-1.78,.872,-3.93),PublicPlaceArt.matte(Color(.62,.67,.64)))
		PublicPlaceArt.box(root,"SinkBowl",Vector3(.36,.008,.30),Vector3(-1.78,.885,-3.93),PublicPlaceArt.matte(Color(.32,.39,.39)))
		PublicPlaceArt.rod(root,"TapUpright",Vector3(-1.78,.86,-4.16),Vector3(-1.78,1.1,-4.16),.014,PublicPlaceArt.matte(Color(.56,.62,.60)))
		PublicPlaceArt.rod(root,"TapSpout",Vector3(-1.78,1.1,-4.16),Vector3(-1.78,1.1,-4.00),.014,PublicPlaceArt.matte(Color(.56,.62,.60)))
		point(root,"public_tea",Vector3(-2.2,.9,-3.05))
		point(root,"public_news",Vector3(-1.55,.8,2.1))
		ClearSignage.paper_tag(root,"NeighbourWelcome","街坊歇脚处\n读书 · 喝茶 · 做手工",Vector3(-1.9,1.9,-4.39),Vector2(1.50,.45),0,.12)
		PublicPlaceArt.sketch(root,"NeighbourPhoto",Vector3(-5.86,1.95,3.45),Vector2(.52,.63),1,PI*.5)
		PublicPlaceArt.prop(room,root,"A15_potted_plant",Vector3(5.65,.84,2.3),.36,root.get_node("NeighbourBookcase"))
		var board:=Node3D.new();board.name="NeighbourNoticeBoard";board.position=Vector3(-5.86,1.85,3.1);board.rotation.y=PI*.5;root.add_child(board)
		PublicPlaceArt.box(board,"CorkBacking",Vector3(1.02,.83,.045),Vector3.ZERO,PublicPlaceArt.wood(Color(.45,.35,.24)))
		for index in 3:
			ClearSignage.paper_tag(board,"NeighbourNotice_%d"%index,["图书交换\n看完放回书架","周日下午\n一起修旧伞","茶水自取\n杯子洗好晾着"][index],Vector3(-.32+index*.32,0,.03),Vector2(.29,.56),0,.046)
		var umbrella:=PublicPlaceArt.box(root,"IndoorUmbrellaStand",Vector3(.32,.48,.32),Vector3(-5.65,.24,4.0),PublicPlaceArt.wood())
		for index in 3:PublicPlaceArt.rod(root,"StoredUmbrella_%d"%index,Vector3(-5.75+index*.10,.35,4.0),Vector3(-5.72+index*.10,.97,4.0),.012,PublicPlaceArt.matte(Color(.30,.42,.42)))
		umbrella.set_meta("daily_storage",true)
		for index in 3:
			var folded:=Node3D.new();folded.name="SpareFoldingChair_%d"%index;folded.position=Vector3(5.40,0,-.65+index*.15);folded.rotation.z=.12;root.add_child(folded)
			PublicPlaceArt.box(folded,"FoldedBack",Vector3(.43,.26,.035),Vector3(0,.68,0),PublicPlaceArt.canvas(Color(.53,.62,.52)))
			PublicPlaceArt.box(folded,"FoldedSeat",Vector3(.43,.38,.055),Vector3(0,.38,0),PublicPlaceArt.wood())
			for side: float in [-1.0,1.0]:PublicPlaceArt.box(folded,"Frame_%d"%int(side),Vector3(.025,.80,.025),Vector3(side*.205,.40,0),PublicPlaceArt.matte(Color(.40,.44,.40)))
		seat(root,"public_shared_seat",Vector3(-3.1,0,2.97),180,Vector3(-1.45,0,3.15),Vector3(-3.1,.75,2.1))
	elif room.kind=="bakery":
		for index in 2:
			var at:=Vector3(-3.55+index*3.05,0,2.55)
			var table:=fixture(room,root,"P_cafe_table","CafeTable_%d"%index,at)
			seat(root,"public_cafe_%d"%index,at+Vector3(.70,0,0),-90,at+Vector3(.70,0,.85),at+Vector3(0,.76,0))
			var mat:=PublicPlaceArt.box(root,"CafePlacemat_%d"%index,Vector3(.32,.004,.24),at+Vector3(0,.762,0),PublicPlaceArt.canvas(Color(.79,.80,.65)));PublicPlaceArt.supported(mat,table)
		fixture(room,root,"P_coffee_station","EspressoStation",Vector3(4.8,0,-3.2))
		PublicPlaceArt.box(root,"CounterConnector",Vector3(.18,.82,.75),Vector3(1.01,.41,.30),PublicPlaceArt.matte(Color(.73,.76,.61)),true)
		ClearSignage.paper_tag(root,"CoffeeMenu","咖啡 %d\n拿铁 %d\n坐下来慢慢喝"%[int(GameState.item("coffee").price),int(GameState.item("cafe_latte").price)],Vector3(5.39,1.92,.2),Vector2(.94,.69),-PI*.5,.09)
		point(root,"public_cafe_order",Vector3(3.5,1,1.1),1.2)
		var return_shelf:=PublicPlaceArt.bench(root,"CafeReturnStation",Vector3(4.8,0,2.7),.65,.55,.84)
		PublicPlaceArt.tray(root,"ReturnedDishTray",Vector3(4.8,.84,2.7),Vector2(.55,.40),return_shelf)
		ClearSignage.paper_tag(root,"ReturnDishes","杯碟回收",Vector3(5.38,1.20,2.7),Vector2(.54,.20),-PI*.5,.09)

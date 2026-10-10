class_name RoomIdentity
extends RefCounted

static func _box(parent: Node3D,name_value: String,size: Vector3,at: Vector3,material: Material) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=name_value;var shape:=BoxMesh.new();shape.size=size
	node.mesh=shape;node.position=at;node.material_override=material;node.set_meta("model_part",true);parent.add_child(node);return node

static func build(room: InteriorBuilder) -> void:
	var root:=Node3D.new();root.name="RoomIdentity";room.add_child(root)
	match room.kind:
		"store":
			ClearSignage.paper_tag(root,"ToolsCategory","种子与园艺",Vector3(-5.40,2.20,-.65),Vector2(1.16,.24),PI*.5,.12)
			ClearSignage.paper_tag(root,"PantryCategory","米粮 · 调料",Vector3(-3.50,2.45,-3.88),Vector2(1.32,.26),0,.12)
			ClearSignage.paper_tag(root,"DailyCategory","晴町的日用",Vector3(5.40,2.28,3.28),Vector2(1.24,.25),-PI*.5,.12)
		"bakery":
			ClearSignage.paper_tag(root,"FreshBread","每日少量烘焙",Vector3(-5.40,2.25,-.15),Vector2(1.46,.28),PI*.5,.12)
			ClearSignage.paper_tag(root,"OvenArea","揉面 · 发酵 · 烘烤",Vector3(2.85,2.48,-3.87),Vector2(2.02,.25),0,.115)
			ClearSignage.paper_tag(root,"CakeCategory","甜点与蛋糕",Vector3(.48,.34,.393),Vector2(.94,.17),0,.075)
		"workroom":
			_workshop(room,root)

static func _workshop(room: InteriorBuilder,root: Node3D) -> void:
	var archive:=Node3D.new();archive.name="WorkshopArchiveDisplay";room.add_child(archive)
	var paper:=StandardMaterial3D.new();paper.albedo_color=Color(.96,.91,.78)
	paper.albedo_texture=load("res://assets/ui/paper.jpg");paper.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON;paper.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	var wood: StandardMaterial3D=room.wb.house.wood_mat(false)
	for x: float in [-5.76,-4.94]:_box(archive,"ShelfUpright_%d"%int(x*100),Vector3(.055,1.58,.055),Vector3(x,.79,-2.50),wood)
	for index: int in 3:
		var x: float=-5.65+index*.31
		_box(archive,"ArchiveBox_%d"%index,Vector3(.27,.21,.55),Vector3(x,.94,-2.43),paper)
		ClearSignage.paper_tag(archive,"ArchiveLabel_%d"%index,["旧账本","会场图","邻里便笺"][index],Vector3(x,.947,-2.146),Vector2(.245,.12),0,.047)
	var plan:=ClearSignage.plate(root,"FestivalPlan",Vector2(1.70,.95),Vector3(-3.45,1.93,-4.39),0,Color(.93,.88,.75))
	var route: StandardMaterial3D=LivingAction.matte(Color(.42,.51,.48))
	var yard: StandardMaterial3D=LivingAction.matte(Color(.71,.78,.55))
	var building: StandardMaterial3D=LivingAction.matte(Color(.76,.59,.39))
	_box(plan,"MainStreet",Vector3(1.40,.035,.003),Vector3(0,.15,.015),route)
	_box(plan,"LaneToFestival",Vector3(.035,.36,.003),Vector3(.31,-.03,.016),route)
	_box(plan,"FestivalGround",Vector3(.49,.27,.003),Vector3(-.12,-.15,.017),yard)
	for index: int in 5:_box(plan,"Shops_%d"%index,Vector3(.18,.10,.003),Vector3(-.54+index*.25,.235,.017),building)
	_box(plan,"FestivalTable",Vector3(.18,.045,.003),Vector3(-.14,-.17,.020),building)
	plan.add_child(ClearSignage.label("庭院",Vector3(-.12,-.06,.024),0,.066))
	plan.add_child(ClearSignage.label("灯",Vector3(.34,-.19,.024),0,.07,Color(.67,.33,.22)))
	plan.add_child(ClearSignage.label("晴町 · 旧夏祭会场图",Vector3(0,.365,.025),0,.09))
	ClearSignage.paper_tag(root,"PaperStorage","试样和纸",Vector3(4.90,.69,1.865),Vector2(.86,.13),0,.079)
	for x: float in [4.43,5.37]:
		for z: float in [1.24,1.76]:_box(root,"SpareTableLeg_%d_%d"%[int(x*100),int(z*100)],Vector3(.07,.70,.07),Vector3(x,.35,z),wood)
	# Materials stay against the walls; x=1.8 is the existing full-height trial aisle.
	for index: int in 4:
		var sheet:=_box(root,"SparePaper_%d"%index,Vector3(.44,.012,.32),Vector3(4.82,.792+index*.013,1.45),paper)
		sheet.rotation.y=deg_to_rad(float(index-1)*3.0)
	ClearSignage.paper_tag(root,"RoomPurpose","夏祭共同工作间",Vector3(3.90,2.15,-4.39),Vector2(2.02,.28),0,.135)
	var chest: Node3D=room.wb.spawn("P_chest",Vector3(4.70,0,-3.67),0,1,root,.82)
	chest.name="CommunityMaterialChest";HouseBuilder.toonify(chest)
	var bounds: AABB=WorldBuilder.local_aabb(chest)
	ClearSignage.paper_tag(chest,"MaterialChestLabel","灯笼与布料",Vector3(bounds.get_center().x,bounds.get_center().y,bounds.end.z+.014),Vector2(.72,.13),0,.069)
	var bamboo:=Node3D.new();bamboo.name="BambooStock";bamboo.set_meta("model_part",true);root.add_child(bamboo)
	_box(bamboo,"RackBase",Vector3(.48,.065,1.10),Vector3(5.60,.033,-2.45),wood)
	for index: int in 9:
		var rod:=MeshInstance3D.new();rod.name="Bamboo_%d"%index
		var cylinder:=CylinderMesh.new();cylinder.top_radius=.024;cylinder.bottom_radius=.029;cylinder.height=1.30+float(index%3)*.12
		rod.mesh=cylinder;rod.material_override=wood;rod.position=Vector3(5.57+float(index%2)*.065,cylinder.height*.5+.065,-2.84+index*.095)
		bamboo.add_child(rod)
	var body:=StaticBody3D.new();body.name="BambooRackCollision";body.collision_layer=WorldBuilder.L_SOLID;body.set_meta("model_part",true)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(.48,1.65,1.10);collision.shape=shape;collision.position=Vector3(5.60,.825,-2.45)
	body.add_child(collision);bamboo.add_child(body)
	ClearSignage.paper_tag(root,"BambooLabel","备用竹条",Vector3(5.985,1.78,-2.45),Vector2(.88,.19),-PI*.5,.095)

static func home(house: HouseBuilder) -> void:
	var root:=Node3D.new();root.name="HomeIdentity";house.add_child(root)
	# Furniture stays visible when room walls lower for the camera.
	var cabinet: Node3D=house.get_node("J05_dish_cabinet")
	var bounds: AABB=WorldBuilder.local_aabb(cabinet)
	ClearSignage.paper_tag(cabinet,"KitchenMemo","茶碗与茶具",Vector3(bounds.get_center().x,bounds.position.y+bounds.size.y*.60,bounds.end.z+.014),Vector2(.64,.14),0,.079)

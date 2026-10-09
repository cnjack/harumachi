class_name ShopDisplays
extends RefCounted
## Actual small display rooms inside the exterior shells, separate from playable interiors.
const PASTRY_TRAY_FLOOR := .0236354 # nine ray samples of the exported W12's inner floor

static func _material(colour: Color, texture: String = "") -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	if texture != "":
		mat.albedo_texture = load(texture)
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 1.0
	return mat

static func _box(root: Node3D, name: String, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = mat
	root.add_child(mesh)
	return mesh

static func _prop(world: WorldBuilder, root: Node3D, id: String, at: Vector3, scale: float = 1.0, yaw: float = 0.0) -> Node3D:
	var prop := world.spawn(id, at, yaw, 0, root, scale)
	if prop:
		prop.name = "%s_Display_%d" % [id, root.get_child_count()]
		prop.set_meta("shop_display", true)
		HouseBuilder.toonify(prop)
	return prop

static func build(building: Node3D, id: String, world: WorldBuilder) -> OmniLight3D:
	var panes: Array = ShopWindows.WINDOWS[id]
	var x0 := INF
	var x1 := -INF
	var front := -INF
	var nearest := INF
	for pane: Array in panes:
		x0 = minf(x0, float(pane[0]))
		x1 = maxf(x1, float(pane[1]))
		front = maxf(front, float(pane[4]))
		nearest = minf(nearest, float(pane[4]))
	var back := front - 2.20
	var mid := (x0+x1)*.5
	var width := x1-x0+.30
	var root := Node3D.new()
	root.name = "ActualShopDisplay_" + id
	root.set_meta("real_display_room", true)
	building.add_child(root)
	var plaster := _material(Color(.91,.87,.75))
	var wood := _material(Color(.80,.66,.45), "res://assets/textures/house/wood_floor.jpg")
	_box(root,"RoomFloor",Vector3(mid,.035,(front+back)*.5),Vector3(width,.07,front-back),wood)
	_box(root,"RoomRear",Vector3(mid,1.30,back+.015),Vector3(width,2.60,.03),plaster)
	_box(root,"RoomLeft",Vector3(x0-.12,1.30,(front+back)*.5),Vector3(.03,2.60,front-back),plaster)
	_box(root,"RoomRight",Vector3(x1+.12,1.30,(front+back)*.5),Vector3(.03,2.60,front-back),plaster)
	_box(root,"RoomCeiling",Vector3(mid,2.60,(front+back)*.5),Vector3(width,.04,front-back),plaster)
	_box(root,"RearWainscot",Vector3(mid,.44,back+.045),Vector3(width,.88,.035),wood)
	_box(root,"RearChairRail",Vector3(mid,.91,back+.072),Vector3(width,.045,.055),wood)
	for index in panes.size():
		var pane: Array = panes[index]
		var pane_mid_x := (float(pane[0])+float(pane[1]))*.5
		var pane_mid_y := (float(pane[2])+float(pane[3]))*.5
		var pane_front := float(pane[4])
		_box(root,"WindowSill_%d"%index,Vector3(pane_mid_x,float(pane[2])+.012,pane_front-.16),Vector3(float(pane[1])-float(pane[0]),.04,.42),wood)
		for edge in 2:
			_box(root,"WindowJamb_%d_%d"%[index,edge],Vector3(float(pane[edge]),pane_mid_y,pane_front-.16),Vector3(.045,float(pane[3])-float(pane[2]),.42),plaster)
	var goods_z := nearest-.62
	match id:
		"S02":
			# Flat, straight timber shelves carry separate generated basket modules.
			var rack_x := -.66
			var rack_z := 2.83
			for column in 2:
				_box(root,"BakeryRackPost_%d"%column,Vector3(rack_x+float(column*2-1)*.65,1.01,rack_z-.13),Vector3(.055,1.92,.055),wood)
			for row in 3:
				var shelf_y := 1.00+float(row)*.42
				_box(root,"BakeryRackBoard_%d"%row,Vector3(rack_x,shelf_y-.025,rack_z-.08),Vector3(1.36,.045,.47),wood)
				for column in 3:
					var basket_id := "W08_baguette_basket" if (row+column)%3==0 else "W07_pastry_tray"
					var product_at := Vector3(rack_x-.44+float(column)*.44,shelf_y,rack_z-.04)
					var product_yaw := float(column-1)*6.0
					if basket_id == "W07_pastry_tray":
						_prop(world,root,"W12_cedar_tray",product_at,.88,product_yaw)
						product_at.y += PASTRY_TRAY_FLOOR*.88+.003
					_prop(world,root,basket_id,product_at,.88,product_yaw)
			_box(root,"DoorBreadTable",Vector3(.86,.86,2.40),Vector3(.70,1.64,.48),wood)
			_prop(world,root,"W08_baguette_basket",Vector3(.86,1.70,2.40),.90)
			_box(root,"BakeryRearShelf",Vector3(rack_x,2.23,back+.27),Vector3(1.45,.045,.42),wood)
			for index in 3:
				_prop(world,root,"B04_shokupan",Vector3(rack_x-.48+float(index)*.48,2.255,back+.27),.85)
		"S03":
			for index in 2:
				_prop(world,root,"W01_flower_buckets",Vector3(.58+float(index)*1.13,.08,2.12),.90,float(index)*-8.0)
			_box(root,"FloristFrontLowBench",Vector3(1.30,.22,3.20),Vector3(2.24,.40,.45),wood)
			for index in 4:
				var flower_id: String = ["W05_hydrangea_pot","W06_lily_vase","W04_sunflower_pot","W05_hydrangea_pot"][index]
				_prop(world,root,flower_id,Vector3(.36+float(index)*.61,.43,3.18),.84,float(index-2)*7.0)
			_box(root,"FloristRearShelf",Vector3(1.28,1.44,back+.23),Vector3(2.21,.045,.35),wood)
			for index in 3:
				_prop(world,root,"W05_hydrangea_pot",Vector3(.55+float(index)*.72,1.465,back+.23),.66,float(index-1)*18.0)
			_prop(world,root,"A14_hydrangea_pot",Vector3(-1.85,.82,goods_z),.52)
			_box(root,"DoorFlowerTable",Vector3(-1.85,.42,goods_z),Vector3(.60,.78,.55),wood)
		"S01":
			for index in 3:
				_prop(world,root,"W02_grocer_shelf",Vector3(-1.42+float(index)*1.30,.08,1.25),1.15)
			_box(root,"GrocerWindowCounter",Vector3(mid,.48,2.18),Vector3(4.08,.87,.55),wood)
			for index in 4:
				var stock_id := "W09_rice_sacks" if index%2==0 else "W10_bottle_crate"
				_prop(world,root,stock_id,Vector3(-1.53+float(index)*1.01,.94,2.20),1.0,float(index-2)*5.0)
			_prop(world,root,"J04_rice_cabinet",Vector3(mid,.07,back+.42),.85)
		"S05":
			for index in 2:
				_prop(world,root,"I03_bookshelf",Vector3(mid-.50+float(index),.46,goods_z-.38),.66)
			_box(root,"SortingCounter",Vector3(mid,.43,goods_z+.10),Vector3(1.86,.81,.48),wood)
			_prop(world,root,"I08_boxes",Vector3(mid-.43,.87,goods_z+.10),.52)
		"S08":
			_prop(world,root,"J05_dish_cabinet",Vector3(-1.04,.05,1.50),.85)
			_prop(world,root,"W02_grocer_shelf",Vector3(1.65,.05,1.53),.94)
			_box(root,"PotteryWindowTable",Vector3(mid,.41,nearest-.65),Vector3(4.25,.76,.49),wood)
			for index in 4:
				_prop(world,root,"W11_ceramic_set",Vector3(-1.48+float(index)*1.10,.81,nearest-.68),1.08,float(index-2)*9.0)
	var light := OmniLight3D.new()
	light.name = "ActualDisplayLight_" + id
	light.position = Vector3(mid,2.20,(front+back)*.5)
	light.light_color = Color(1.0,.85,.65)
	light.omni_range = maxf(3.2,width)
	light.omni_attenuation = .45
	light.light_energy = .45
	light.shadow_enabled = false
	root.add_child(light)
	return light

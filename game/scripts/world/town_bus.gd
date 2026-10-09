class_name TownBus
extends Node3D
## A cream and jade country bus, assembled with separate doors, wheels and window frames.
var doors: Array[Node3D]=[]
var wheels: Array[Node3D]=[]
var wheel_rest_bases: Array[Basis]=[]
var clock:=0.0
var travelling:=false
var depart:=false
var left_town:=false
var parked:=true

func build(world: WorldBuilder) -> void:
	name="CountryBus";position=Vector3(-44.8,0,-11.3)
	var model:=world.spawn("B01_bus",Vector3.ZERO,0,0,self)
	if model==null:return
	HouseBuilder.toonify(model)
	for i in 4:
		var wheel:=model.find_child("Wheel_%d"%i,true,false) as Node3D
		if wheel:wheels.append(wheel);wheel_rest_bases.append(wheel.basis)
	for i in 2:
		var leaf:=model.find_child("DoorLeaf_%d"%i,true,false) as Node3D
		if leaf:doors.append(leaf)
	_glazing(model)
	var occupant:=world.spawn("CH_tanaka",Vector3(1.30,.40,-.28),90,0,model,.72)
	if occupant:
		occupant.name="SeatedDriver"
		var skeleton:=occupant.find_child("Skeleton3D",true,false) as Skeleton3D
		if skeleton:
			for side: String in ["L","R"]:
				var thigh:=skeleton.find_bone("thigh."+side);var shin:=skeleton.find_bone("shin."+side)
				if thigh>=0:skeleton.set_bone_pose_rotation(thigh,Quaternion(Vector3.RIGHT,-PI*.45))
				if shin>=0:skeleton.set_bone_pose_rotation(shin,Quaternion(Vector3.RIGHT,PI*.45))
	var route:=ClearSignage.plate(model,"RoutePlate",Vector2(.75,.18),Vector3(2.17,1.96,0),PI*.5,Color(.12,.26,.28))
	route.add_child(ClearSignage.label("07 晴町",Vector3(0,0,.02),0,.13,Color(.98,.96,.80)))
	var collider:=StaticBody3D.new();collider.name="BusCollider";collider.collision_layer=WorldBuilder.L_SOLID;collider.set_meta("model_part",true)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(4.05,1.9,1.60);shape.shape=box;shape.position.y=1.05;collider.add_child(shape);model.add_child(collider)
	var driver:=Interactable.new();driver.name="BusDriver";driver.id="bus_driver";driver.radius=2.2;driver.position=Vector3(1.0,1.1,1.10);driver.body=collider;add_child(driver)

func _glazing(model: Node3D) -> void:
	var glass:=ShaderMaterial.new();glass.shader=load("res://shaders/bus_glass.gdshader")
	var rectangles: Array[Vector2]=[Vector2(-1.92,-1.22),Vector2(-1.12,-.42),Vector2(-.32,.44),Vector2(1.32,1.94)]
	for side in [-1.0,1.0]:
		for index in rectangles.size():
			var limits: Vector2=rectangles[index];var pane:=MeshInstance3D.new();pane.name="Glass_%d_%d"%[int(side),index]
			var quad:=QuadMesh.new();quad.size=Vector2(limits.y-limits.x,.72);pane.mesh=quad;pane.material_override=glass;pane.position=Vector3((limits.x+limits.y)/2,1.49,side*.848)
			pane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;model.add_child(pane)
	var front:=MeshInstance3D.new();front.name="Glass_Windscreen";var windscreen:=QuadMesh.new();windscreen.size=Vector2(1.26,.78);front.mesh=windscreen;front.material_override=glass;front.position=Vector3(2.15,1.53,0);front.rotation.y=PI*.5;front.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;model.add_child(front)

func part(label: String, extent: Vector3, at: Vector3, material: Material, parent: Node3D=null) -> void:
	var piece:=MeshInstance3D.new();piece.name=label
	var shape:=BoxMesh.new();shape.size=extent;piece.mesh=shape;piece.material_override=material;piece.position=at
	(parent if parent else self).add_child(piece)

func open_doors(amount: float) -> void:
	for i in doors.size():doors[i].rotation.y=amount*1.25*(1 if i==0 else -1)

func park_at_stop() -> void:
	position=Vector3(-44.8,0,-11.3);depart=false;travelling=false;left_town=false;parked=true;visible=true
	# Generated wheel parts are not perfectly symmetric. At rest their fitted
	# silhouette must align with the body instead of freezing midway through a roll.
	for index in wheels.size():wheels[index].basis=wheel_rest_bases[index]

func arrival(main: Node, keep_locked: bool = false) -> void:
	left_town=false;visible=true;parked=false
	GameState.lock_input("arrival")
	var old_pause:=GameState.clock_paused;GameState.clock_paused=true
	var old_view:=Vector3(main.rig.yaw,main.rig.pitch,main.rig.dist)
	main.ui.ambient_layer.visible=false;main.marker.visible=false;main.player.model_root.visible=false
	main.rig.yaw=100;main.rig.pitch=20;main.rig.dist=9;main.rig.snap()
	position.x=-78;travelling=true
	var approach:=create_tween();approach.tween_property(self,"position:x",-44.8,3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT);await approach.finished
	travelling=false;open_doors(1);Audio.fx("door",-8)
	main.player.model_root.visible=true
	main.player.global_position=Vector3(-43.8,.08,-9.75);main.player.set_facing(deg_to_rad(90))
	main.player.auto_move=Vector3(1,0,0)
	await get_tree().create_timer(.9).timeout
	main.player.auto_move=Vector3.ZERO
	await get_tree().create_timer(.8).timeout
	open_doors(0);park_at_stop()
	main.rig.yaw=old_view.x;main.rig.pitch=old_view.y;main.rig.dist=old_view.z;main.rig.snap()
	GameState.flags["bus_arrival_seen"]=true
	if not keep_locked:
		main.ui.ambient_layer.visible=true;GameState.clock_paused=old_pause;GameState.unlock_input("arrival")

func _process(delta: float) -> void:
	if left_town:visible=false;return
	clock+=delta
	if travelling:
		for wheel in wheels:wheel.rotate_object_local(Vector3.FORWARD,delta*9)

func _material(colour: Color, label: String) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new();material.resource_name=label;material.albedo_color=colour
	material.roughness=1.0;material.specular_mode=BaseMaterial3D.SPECULAR_DISABLED;material.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON
	return material

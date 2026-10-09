class_name GatheringView
extends Node3D
var s: Story
var food: Node3D
var note: Label3D
var used_food: Node3D
var current_serving_axis := Vector3.RIGHT
var _surface_model: WeakRef
var _surface_transform := Transform3D.IDENTITY
var _surface_invitation := false
var _surface_value := Vector3.INF
var _surface_axis := Vector3.RIGHT
func setup(story: Story) -> void:
	s = story
	food = Node3D.new()
	food.name = "GatheringFood"
	add_child(food)
	used_food=Node3D.new();used_food.name="FoodUses";add_child(used_food)
	note = Label3D.new()
	note.font = load("res://assets/fonts/LXGWWenKai-Medium.ttf")
	note.font_size = 40
	note.pixel_size = .002
	note.position = Vector3(8.5, 1.4, 10.4)
	note.rotation.y = PI
	note.modulate = Color(.26,.35,.3)
	add_child(note)
	GameState.state_changed.connect(sync_state)
	GameState.placements_changed.connect(sync_state)
	GameState.time_changed.connect(func(_minute: int): sync_state())
	sync_state()

func table() -> Node3D:
	if SummerSpace.state().phase != "invitation":
		var selected: Dictionary = SummerSpace.furniture("picnic_table")
		return s.placement.placed_nodes.get(int(selected.get("uid", -1)))
	return s.world.get_node_or_null("P09")

func surface() -> Vector3:
	var model: Node3D = table()
	if not is_instance_valid(model): return Vector3.INF
	var invitation: bool = SummerSpace.state().phase == "invitation"
	var table_transform: Transform3D = model.global_transform
	if _surface_model != null and _surface_model.get_ref() == model and _surface_transform == table_transform and _surface_invitation == invitation:
		current_serving_axis = _surface_axis
		return _surface_value
	# The imported mesh stays fixed. A replacement, move, turn or scale needs a
	# fresh measurement; an unchanged tabletop must not rescan faces every minute.
	_surface_model = weakref(model)
	_surface_transform = table_transform
	_surface_invitation = invitation
	_surface_value = Vector3.INF
	var at: Vector3 = model.global_position
	# P09's left side holds the bread basket. Keep this finite three-portion set
	# on the clear right half and measure the new deck rather than its old front lip.
	if invitation: at += Vector3(.45,0,0)
	var height: float = WorldBuilder.rendered_support_height(model, at, 1.5,true)
	if not is_finite(height):return Vector3.INF
	var found_axis:=false
	for axis: Vector3 in [Vector3.RIGHT,Vector3.BACK]:
		if supported_row(model,at,height,axis):
			current_serving_axis=axis;found_axis=true;break
	if not found_axis:return Vector3.INF
	_surface_axis = current_serving_axis
	_surface_value = Vector3(at.x, height + .012, at.z) if is_finite(height) and height > .35 else Vector3.INF
	return _surface_value

func supported_row(model: Node3D, at: Vector3, height: float, axis: Vector3) -> bool:
	for index: int in 3:
		for offset: Vector3 in [Vector3(-.145,0,-.145),Vector3(.145,0,-.145),Vector3(-.145,0,.145),Vector3(.145,0,.145)]:
			var edge: Vector3=at+axis*(index-1)*.32+offset
			var rim_height: float=WorldBuilder.rendered_support_height(model,edge,1.5,true)
			if not is_finite(rim_height) or absf(rim_height-height)>.02:return false
	return true

func serving_at(index: int, at: Vector3) -> Vector3:
	return at+current_serving_axis*(index-1)*.32

func stop() -> Vector3:
	return SummerSpace.stop_for("picnic_table") if SummerSpace.state().phase != "invitation" else Vector3(2,0,13)

func sync_state() -> void:
	var exposed: bool = GameState.qstate("Q05") == "done" and GameState.day >= 16
	var town: bool = s.world.region == "town"
	note.visible = exposed and town
	for point in get_tree().get_nodes_in_group("interactables"):
		if point.id == "gathering_paper": point.visible = exposed and town
	note.text = "晚会纸签\n菜单再用 · 同灯再挂 · 散场收好"
	for child in food.get_children():
		food.remove_child(child)
		child.queue_free()
	var entry: Dictionary = SummerGathering.current()
	for child in used_food.get_children(): used_food.remove_child(child);child.queue_free()
	for id: String in SummerGathering.state().sessions:
		var session: Dictionary=SummerGathering.state().sessions[id]
		for unit: Dictionary in FoodPurpose.units(session):
			if unit.state=="placed" and unit.use.get("place","")=="tea" and int(unit.use.get("placed_day",0))==GameState.day:
				var location: Vector3=tea_surface()
				if location.is_finite(): portion(used_food,session,unit,location,"Use_"+str(unit.index))
	used_food.visible=town
	food.visible = town and not entry.is_empty() and not entry.get("closed",false) and int(entry.get("day",0)) == GameState.day
	if not food.visible: return
	var at: Vector3 = surface()
	food.visible = at.is_finite()
	if not food.visible: return
	if not FoodPurpose.units(entry).is_empty():
		for unit: Dictionary in FoodPurpose.units(entry):
			if unit.state in ["table","reserved"]: portion(food,entry,unit,serving_at(int(unit.index),at),"Unit_"+str(unit.index))
		note.text="%s · 这篮三份\n桌上%d份，留给街坊%d份\n有名字的先留给约好的人" % [SummerProjects.MENU_NAMES[entry.menu],FoodPurpose.units(entry).filter(func(u:Dictionary):return u.state=="table").size(),FoodPurpose.units(entry).filter(func(u:Dictionary):return u.state=="reserved").size()]
		return
	for index in int(entry.remaining):
		var base := MeshInstance3D.new()
		if entry.presentation == "plate":
			var plate := CylinderMesh.new()
			plate.top_radius = .14
			plate.bottom_radius = .13
			plate.height = .012
			base.mesh = plate
		else:
			var paper := BoxMesh.new()
			paper.size = Vector3(.28,.008,.24)
			base.mesh = paper
		base.material_override = LivingAction.matte(Color(.95,.9,.76))
		base.position = serving_at(index,at)
		food.add_child(base)
		var bite: Node3D = MealModels.spawn(s.world,food,str(SummerProjects.MENUS[entry.menu]),.18 if entry.portion=="bite" else .23)
		if bite != null: bite.position+=base.position+Vector3.UP*.009
	note.text = "%s · 莲烤制\n%s · 还剩%d份\n散场把剩的包好" % [SummerProjects.MENU_NAMES[entry.menu],"夏祭" if entry.context == "festival" else "树下重约",int(entry.remaining)]

func portion(parent: Node3D,entry: Dictionary,unit: Dictionary,at: Vector3,prefix: String) -> void:
	var root:=Node3D.new();root.name=prefix;parent.add_child(root);root.position=at;root.set_meta("unit_id",str(unit.id))
	var base:=MeshInstance3D.new();base.name="Container"
	if unit.format=="plate":
		var plate:=CylinderMesh.new();plate.top_radius=.14;plate.bottom_radius=.13;plate.height=.012;base.mesh=plate
	else:
		var paper:=BoxMesh.new();paper.size=Vector3(.28,.012,.24);base.mesh=paper
	base.material_override=LivingAction.matte(Color(.95,.9,.76));root.add_child(base)
	var count: int=3 if unit.prep=="drain_wrap" else 1
	for index in count:
		var slice: Node3D = MealModels.spawn(s.world,root,str(SummerProjects.MENUS[entry.menu]),.065 if count==3 else (.18 if entry.portion=="bite" else .23))
		if slice != null:
			slice.name="Food_%d"%index
			slice.position+=Vector3((index-1)*.07 if count==3 else 0,.009,0)
	if unit.prep=="drain_wrap":
		var fold:=MeshInstance3D.new();fold.name="FoldedPaperBand";var band:=BoxMesh.new();band.size=Vector3(.035,.025,.26);fold.mesh=band;fold.material_override=LivingAction.matte(Color(.84,.76,.57));fold.position.y=.02;root.add_child(fold)
	elif unit.prep=="tray":
		var juice:=MeshInstance3D.new();juice.name="JuiceOnPlate";var drop:=CylinderMesh.new();drop.top_radius=.08;drop.bottom_radius=.08;drop.height=.002;juice.mesh=drop;juice.material_override=LivingAction.matte(Color(.74,.32,.18));juice.position=Vector3(.07,.009,.035);root.add_child(juice)
	if unit.target!="":
		var tag:=Label3D.new();tag.name="NameTag";tag.font=note.font;tag.font_size=32;tag.pixel_size=.0016;tag.outline_size=0;tag.modulate=Color(.22,.31,.24);tag.text=GameState.npc_display(unit.target) if unit.target!="self" else "空";tag.rotation.x=-PI/2;tag.position=Vector3(0,.025,.085);root.add_child(tag)

func tea_surface() -> Vector3:
	var model: Node3D=s.world.get_node_or_null("P08")
	if not is_instance_valid(model): return Vector3.INF
	var at:=Vector3(15.8,0,14.60)
	var height: float=WorldBuilder.rendered_support_height(model,at,1.5)
	return Vector3(at.x,height+.012,at.z) if height>.35 and height<1.5 else Vector3.INF

func prepare_cut(target: String,drained: bool) -> void:
	if s.ui.instant: return
	var original: Camera3D=s.get_viewport().get_camera_3d()
	var camera:=Camera3D.new();s.main.add_child(camera)
	var at: Vector3=surface();camera.global_position=at+Vector3(.12,.72,.36);camera.look_at(at);camera.fov=65;camera.make_current()
	s.ui.dlg.hide()
	var sprinkles:=Node3D.new();s.main.add_child(sprinkles)
	if drained:
		for index in 4:
			var drop:=MeshInstance3D.new();var bead:=SphereMesh.new();bead.radius=.01;bead.height=.03;drop.mesh=bead;drop.material_override=LivingAction.matte(Color(.66,.31,.16));sprinkles.add_child(drop);drop.global_position=at+Vector3(-.1+.04*index,.18,.03)
			var tween:=drop.create_tween();tween.tween_property(drop,"position:y",drop.position.y-.16,.5)
	await s.get_tree().create_timer(.8).timeout
	if is_instance_valid(original): original.make_current()
	camera.queue_free();sprinkles.queue_free();s.ui.dialogue_begin()
	await s.say("narrator","",("沥了点汁，切成小片，纸包折好了。" if drained else "汁留在盘里，底下托稳了。")+"纸签写上了这一份留给谁。")

func show_tea() -> void:
	if s.ui.instant: return
	var original: Camera3D=s.get_viewport().get_camera_3d();var camera:=Camera3D.new();s.main.add_child(camera)
	var at: Vector3=tea_surface();camera.global_position=at+Vector3(-.9,1.15,1.6);camera.look_at(at);camera.fov=44;camera.make_current();s.ui.dlg.hide()
	await s.get_tree().create_timer(1.2).timeout
	if is_instance_valid(original): original.make_current()
	camera.queue_free();s.ui.dialogue_begin()

func eat_at_tea(actor: Node3D,iid: String) -> String:
	if not MealModels.can_display(iid): return "这份先收着，还没有摆上桌。"
	var at: Vector3=spare_tea_surface()
	if not at.is_finite(): return "杯边放不下这份饭菜，先找一块空处。"
	var action:=LivingAction.new();s.main.add_child(action);action.surface_at=at;action.duration=.08 if s.ui.instant else 1.8;action.setup(actor,"eat",iid)
	if action.meal_food==null:
		action.queue_free();return "这份先收着，还没有摆上桌。"
	var original: Camera3D=s.get_viewport().get_camera_3d();var camera: Camera3D=null
	if not s.ui.instant:
		camera=Camera3D.new();s.main.add_child(camera);camera.global_position=at+Vector3(-.6,.9,1.2);camera.look_at(at);camera.fov=42;camera.make_current();s.ui.dlg.hide()
	while not action.finished: await s.get_tree().process_frame
	action.queue_free()
	if is_instance_valid(camera):
		if is_instance_valid(original): original.make_current()
		camera.queue_free();s.ui.dialogue_begin()
	return ""

func spare_tea_surface() -> Vector3:
	var centre: Vector3=tea_surface()
	var model: Node3D=s.world.get_node_or_null("P08")
	if not centre.is_finite() or not is_instance_valid(model):return Vector3.INF
	# A prepared serving has a .14m radius. A new .085m plate needs its own clear patch.
	var candidates: Array[Vector3]=[Vector3(-.30,0,0),Vector3(.30,0,0),Vector3(0,0,-.30),Vector3(0,0,.30),Vector3.ZERO]
	for ix: int in range(-6,7):
		for iz: int in range(-6,7):candidates.append(Vector3(ix*.1,0,iz*.1))
	for offset: Vector3 in candidates:
		var candidate: Vector3=centre+offset
		var middle: float=WorldBuilder.rendered_support_height(model,candidate,1.5)
		if not is_finite(middle) or middle<.35:continue
		var supported: bool=true
		for index: int in 12:
			var angle: float=index*TAU/12.0
			var point: Vector3=candidate+Vector3(cos(angle)*.095,0,sin(angle)*.095)
			var height: float=WorldBuilder.rendered_support_height(model,point,1.5)
			if not is_finite(height) or absf(height-middle)>.006:supported=false
		if not supported:continue
		var occupied: bool=false
		for serving: Node3D in used_food.get_children():
			if Vector2(serving.global_position.x-candidate.x,serving.global_position.z-candidate.z).length()<.24:occupied=true
		var cups: Node3D=s.daily.view.tea_root
		if cups.visible and Vector2(cups.global_position.x-candidate.x,cups.global_position.z-candidate.z).length()<.25:occupied=true
		if not occupied:return Vector3(candidate.x,middle,candidate.z)
	return Vector3.INF

func show_table() -> void:
	if s.ui.instant: return
	var original: Camera3D = s.get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	s.main.add_child(camera)
	var at: Vector3 = surface()
	camera.global_position = at + Vector3(.12,.72,.36)
	camera.fov = 65
	camera.look_at(at)
	camera.make_current()
	s.ui.dlg.hide()
	await s.get_tree().create_timer(.8).timeout
	if is_instance_valid(original): original.make_current()
	camera.queue_free()
	s.ui.dialogue_begin()

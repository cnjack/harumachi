class_name DailyLifeView
extends Node
## Existing trays/ceramics and actual rendered furniture support the new life props.
var s: Story
var meal_root: Node3D
var meal_food: Node3D
var meal_wrap: Node3D
var tea_root: Node3D
var tea_label: Label3D
var paper_root: Node3D
var paper: Node3D
var paper_label: Label3D
var paper_inside: Node3D
var paper_inside_label: Label3D
var _tick := 0.0
var _sign_animating := false
var _eating := false
var _scene_camera: Camera3D
var _scene_previous: Camera3D


func setup(story: Story) -> void:
	s = story
	var pantry_note: Node3D = _card("米与盐\n——和子", .28, .20)
	pantry_note.name = "LifePantryNote"
	s.world.house.add_child(pantry_note)
	pantry_note.position = Vector3(-2.95, 1.18, 1.65)
	meal_root = Node3D.new()
	meal_root.name = "LifeMeal"
	s.world.house.add_child(meal_root)
	var dining: Node3D = s.world.house.get_node("J03_dining_set")
	var at: Vector3 = HouseBuilder.ORIGIN + Vector3(-2.3, 0, 3.0)
	meal_root.global_position = Vector3(at.x, support_height(dining, at), at.z)
	var meal_tray: Node3D = s.world.spawn("W12_cedar_tray", Vector3(-.16,0,0), 0, 0, meal_root, 1.0)
	WorldBuilder.rest_on(meal_tray, meal_root.global_position.y)
	meal_tray.set_meta("support_surface", dining.get_path())
	var meal_cups: Node3D = s.world.spawn("W11_ceramic_set", Vector3(.28, .014, -.05), 0, 0, meal_root, .85)
	meal_cups.set_meta("support_surface", dining.get_path())
	meal_food = Node3D.new()
	meal_food.name = "PreparedRice"
	meal_root.add_child(meal_food)
	var ready_at: Vector3 = meal_root.global_position + Vector3(-.16,0,0)
	var tray_top: float = (meal_tray.global_transform*WorldBuilder.local_aabb(meal_tray)).end.y+.01
	ready_at.y = WorldBuilder.surface_height(meal_tray,Vector2(ready_at.x,ready_at.z),tray_top)
	meal_food.global_position = ready_at
	meal_food.global_basis = Basis(Quaternion(Vector3.UP,_meal_normal()))
	for food_index in 2:
		var food: Node3D = MealModels.spawn(s.world,meal_food,"onigiri",.105)
		if food != null:
			food.name = "RicePortion_%d" % food_index
			food.position += Vector3(-.08 + food_index * .16,.003,0)
	meal_wrap = _card("已收好", .25, .17)
	meal_wrap.name = "FoldedWrapping"
	meal_wrap.rotation.x = -PI / 2.0
	meal_wrap.position = Vector3(-.1, .025, .05)
	meal_root.add_child(meal_wrap)
	tea_root = Node3D.new()
	tea_root.name = "LifeTea"
	s.world.add_child(tea_root)
	var bench: Node3D = s.world.get_node("P08")
	var tea_at := Vector3(15.8, 0, 15.15)
	tea_root.position = Vector3(tea_at.x, support_height(bench, tea_at), tea_at.z)
	var tea_tray: Node3D = s.world.spawn("W12_cedar_tray", Vector3.ZERO, 0, 0, tea_root, .50)
	tea_tray.set_meta("support_surface", bench.get_path())
	var tea_cups: Node3D = s.world.spawn("W11_ceramic_set", Vector3(0, .015, 0), 0, 0, tea_root, .90)
	tea_cups.set_meta("support_surface", tea_tray.get_path())
	tea_label = _label("麦茶 · 春", .0017)
	tea_label.position = Vector3(0, .23, 0)
	tea_root.add_child(tea_label)
	paper_root = Node3D.new()
	paper_root.name = "LifeBakeryPaper"
	s.world.add_child(paper_root)
	var cart: Node3D = s.world.get_node("G11_bread_cart")
	var paper_at := Vector3(-21.25, 0, -15.10)
	paper_root.position = Vector3(paper_at.x, support_height(cart, paper_at) + .13, paper_at.z)
	paper = _card("小份试吃", .38, .26, true)
	paper_label = paper.get_node("Text") as Label3D
	paper_root.add_child(paper)
	paper_inside = _card("小份试吃", .38, .26, true)
	paper_inside.name = "LifeBakeryPaperInside"
	paper_inside_label = paper_inside.get_node("Text") as Label3D
	s.world.interiors.bakery.add_child(paper_inside)
	var counter: Node3D = s.world.interiors.bakery.get_node("I04_shop_counter")
	var inside_at: Vector3 = s.world.interiors.bakery.origin + Vector3(2.681, 0, 1.667)
	paper_inside.global_position = Vector3(inside_at.x, support_height(counter, inside_at) + .13, inside_at.z)
	GameState.state_changed.connect(sync_state)
	sync_state()


func _process(delta: float) -> void:
	_tick += delta
	if _tick > .5 and is_instance_valid(s):
		_tick = 0.0
		sync_state()


func sync_state() -> void:
	if not is_instance_valid(meal_root):
		return
	var meal: Dictionary = DailyLife.event("meal")
	meal_root.visible = meal.get("parcel_claimed", false) or DailyLife.done("meal")
	meal_root.set_meta("meal_choice", int(meal.get("choice", -1)))
	meal_root.set_meta("meal_cooked", bool(meal.get("cooked", false)))
	meal_food.visible = meal.get("cooked", false) and not DailyLife.done("meal") and not _eating
	meal_wrap.visible = DailyLife.done("meal") and int(meal.get("choice", -1)) == 1
	if is_instance_valid(tea_root):
		tea_root.visible = GameState.day >= int(DailyLife.state().introduced_day) + 1 and s.world.region == "town" and not tea_root.get_meta("morning_blocked",false)
	var tea: Dictionary = DailyLife.event("tea")
	if is_instance_valid(tea_label):
		tea_label.text = "常温麦茶 · 杯子已还" if tea.get("temperature", -1) == 1 else ("麦茶 · 春" if not DailyLife.done("tea") else "冰麦茶 · 杯子已还")
	var card: Dictionary = DailyLife.event("card")
	paper_root.visible = GameState.day >= int(DailyLife.state().introduced_day) + 2 and s.world.region == "town"
	paper_inside.visible = GameState.day >= int(DailyLife.state().introduced_day) + 2
	if not _sign_animating:
		paper.rotation.z = 0.0 if card.get("helped_sign", false) else deg_to_rad(-7)
		paper_inside.rotation.z = paper.rotation.z
	paper_label.font_size = 44 if card.get("helped_sign", false) else 38
	paper_inside_label.font_size = paper_label.font_size
	var note := "小份试吃\n慢慢尝" if card.get("helped_sign", false) else ("小份试吃\n切小一点" if card.get("tasted", false) else "小份试吃")
	paper_label.text = note
	paper_inside_label.text = note


func straighten() -> void:
	_sign_animating = true
	var tween := create_tween().set_parallel()
	tween.tween_property(paper, "rotation:z", 0.0, .75)
	tween.tween_property(paper_inside, "rotation:z", 0.0, .75)
	if not s.ui.instant:
		await tween.finished
	_sign_animating = false


func play_action(kind: String, item_id: String = "onigiri") -> String:
	if kind=="eat" and not MealModels.can_display(item_id): return "这份先收好，餐点还没有摆上桌。"
	var action := LivingAction.new()
	s.main.add_child(action)
	action.duration = .08 if s.ui.instant else (1.8 if kind == "eat" else 2.4)
	if kind == "eat":
		action.surface_at = _food_surface()
		if s.main.in_room and s.main.room_kind == "house": action.surface_normal = _meal_normal()
		_eating = true
		meal_food.hide()
	action.setup(s.player, kind, item_id)
	if kind=="eat" and action.meal_food==null:
		action.queue_free();_eating=false;sync_state()
		return "这份先收好，餐点还没有摆上桌。"
	var previous_camera: Camera3D = get_viewport().get_camera_3d()
	var camera: Camera3D = null
	var dialogue_visible: bool = s.ui.dlg.visible
	if not s.ui.instant:
		s.ui.dlg.hide()
		camera = Camera3D.new()
		s.main.add_child(camera)
		if kind == "eat" and action.surface_at.is_finite():
			camera.global_position = action.surface_at + Vector3(.55, .8, 1.1)
			camera.fov = 40.0
			camera.look_at(action.surface_at + Vector3.UP * .025)
		else:
			var forward: Vector3 = s.player.model_root.global_basis.z.normalized()
			var side: Vector3 = s.player.model_root.global_basis.x.normalized()
			camera.global_position = s.player.global_position + forward * 2.15 + side * .65 + Vector3.UP * 1.5
			camera.fov = 44.0
			camera.look_at(s.player.global_position + Vector3.UP * 1.1)
		camera.make_current()
	if kind not in ["sip","eat"]:Audio.fx_at("paper",s.player.global_position,-9)
	while not action.finished:
		await get_tree().process_frame
	action.queue_free()
	_eating = false
	if is_instance_valid(camera):
		if is_instance_valid(previous_camera):
			previous_camera.make_current()
		camera.queue_free()
		s.ui.dlg.visible = dialogue_visible
	return ""


func _meal_normal() -> Vector3:
	var tray: Node3D = meal_root.get_node("W12_cedar_tray")
	var at: Vector3 = meal_root.global_position + Vector3(-.16,0,0)
	var ceiling: float = (tray.global_transform*WorldBuilder.local_aabb(tray)).end.y+.01
	var dx: float = (WorldBuilder.surface_height(tray,Vector2(at.x+.04,at.z),ceiling)-WorldBuilder.surface_height(tray,Vector2(at.x-.04,at.z),ceiling))/.08
	var dz: float = (WorldBuilder.surface_height(tray,Vector2(at.x,at.z+.04),ceiling)-WorldBuilder.surface_height(tray,Vector2(at.x,at.z-.04),ceiling))/.08
	return Vector3(-dx,1,-dz).normalized()

func _food_surface() -> Vector3:
	if s.main.in_room and s.main.room_kind == "house":
		var tray: Node3D = meal_root.get_node("W12_cedar_tray")
		var at: Vector3 = meal_root.global_position + Vector3(-.16,0,0)
		var box: AABB = tray.global_transform * WorldBuilder.local_aabb(tray)
		return Vector3(at.x, WorldBuilder.surface_height(tray, Vector2(at.x,at.z),box.end.y+.01), at.z)
	if s.main.in_room and s.main.room_kind == "bakery":
		var counter: Node3D = s.world.interiors.bakery.get_node("I04_shop_counter")
		var at: Vector3 = s.world.interiors.bakery.origin + Vector3(2.681, 0, 1.667)
		return Vector3(at.x, support_height(counter, at), at.z)
	var cart: Node3D = s.world.get_node("G11_bread_cart")
	var at_cart := Vector3(-21.25, 0, -15.10)
	return Vector3(at_cart.x, support_height(cart, at_cart), at_cart.z)


func begin_scene(id: String) -> void:
	if s.ui.instant or id not in ["life_tea", "life_bakery_card"]: return
	_scene_previous = get_viewport().get_camera_3d()
	_scene_camera = Camera3D.new()
	s.main.add_child(_scene_camera)
	_scene_camera.fov = 50.0
	_scene_camera.global_position = Vector3(11.8, 2.7, 19.8) if id == "life_tea" else Vector3(-19.0, 2.5, -10.8)
	_scene_camera.look_at(Vector3(14.4, 1.0, 16.1) if id == "life_tea" else Vector3(-21.5, 1.0, -14.2))
	_scene_camera.make_current()


func end_scene() -> void:
	if is_instance_valid(_scene_camera):
		if is_instance_valid(_scene_previous): _scene_previous.make_current()
		_scene_camera.queue_free()


func _label(text: String, pixel: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = load("res://assets/fonts/LXGWWenKai-Medium.ttf")
	label.font_size = 38
	label.pixel_size = pixel
	label.modulate = Color(.20, .27, .23)
	label.outline_size = 0
	label.no_depth_test = false
	return label


func _card(text: String, width: float, height: float, standing: bool = false) -> Node3D:
	var root := Node3D.new()
	var surface := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	surface.mesh = quad
	surface.material_override = LivingAction.matte(Color(.96, .90, .74))
	root.add_child(surface)
	if standing:
		var foot := MeshInstance3D.new()
		var fold := BoxMesh.new()
		fold.size = Vector3(width, .006, .08)
		foot.mesh = fold
		foot.material_override = LivingAction.matte(Color(.96, .90, .74))
		foot.position = Vector3(0, -height * .5 + .003, -.03)
		root.add_child(foot)
	var label: Label3D = _label(text, .0018)
	label.name = "Text"
	label.position.z = .002
	root.add_child(label)
	return root


static func support_height(model: Node3D, at: Vector3) -> float:
	return WorldBuilder.rendered_support_height(model, at)

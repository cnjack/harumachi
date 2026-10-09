class_name SpaceView
extends Node3D
var s: Story
var world: WorldBuilder
var preview: Node3D
var pins: Node3D
var observer: NPC
var trace: Array[Vector3] = []
var aborted := false
var walk_panel: PanelContainer
var scheme_preview: Node3D

func setup(story: Story) -> void:
	s = story
	world = s.world
	add_to_group("summer_space_views")
	preview = Node3D.new()
	preview.name = "SummerOccupancyPreview"
	add_child(preview)
	pins = Node3D.new()
	pins.name = "SpaceUsePins"
	add_child(pins)
	for index in SummerSpace.FUTURE_RECTS.size():
		var rect: Rect2 = SummerSpace.FUTURE_RECTS[index]
		var height: float = 4.23 if index == 0 else 2.4
		var shape := BoxShape3D.new()
		shape.size = Vector3(rect.size.x, height, rect.size.y)
		var body := StaticBody3D.new()
		body.name = "Occupancy_%d" % index
		body.set_meta("model_part", true)
		body.collision_layer = WorldBuilder.L_SOLID
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		preview.add_child(body)
		body.position = Vector3(rect.get_center().x, height / 2.0, rect.get_center().y)
		var mesh := MeshInstance3D.new()
		mesh.name = "OccupancyMesh_%d" % index
		var box := BoxMesh.new()
		box.size = shape.size
		mesh.mesh = box
		var material: StandardMaterial3D = LivingAction.matte(Color(.42, .64, .73, .15))
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mesh)
		var label: Label3D = _label("舞台占地预览" if index == 0 else "屋台占地预览")
		label.position.y = height / 2.0 + .3
		body.add_child(label)
	var ring := MeshInstance3D.new()
	ring.name = "DanceOccupancy"
	var disk := CylinderMesh.new()
	disk.top_radius = SummerSpace.DANCE_RADIUS
	disk.bottom_radius = SummerSpace.DANCE_RADIUS
	disk.height = .01
	disk.radial_segments = 64
	ring.mesh = disk
	var circle_material: StandardMaterial3D = LivingAction.matte(Color(.81, .60, .36, .18))
	circle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = circle_material
	ring.position = Vector3(SummerSpace.DANCE_CENTER.x, .025, SummerSpace.DANCE_CENTER.y)
	add_child(ring)
	ring.set_meta("space_circle", true)
	GameState.state_changed.connect(sync_state)
	GameState.placements_changed.connect(sync_state)
	GameState.time_changed.connect(func(_minute: int): sync_state())
	sync_state()

func sync_state() -> void:
	var active: bool = SummerSpace.state().phase != "invitation"
	for point in get_tree().get_nodes_in_group("interactables"):
		if point.id == "space_plan": point.visible = GameState.qstate("Q11") == "done" or active
	var actual_stage: bool = is_instance_valid(world.fest_nodes.get("natsumatsuri")) and world.fest_nodes.natsumatsuri.visible
	preview.visible = active and not actual_stage and world.region == "town"
	for child in preview.get_children():
		(child as StaticBody3D).collision_layer = WorldBuilder.L_SOLID if active and not actual_stage else 0
	for child in get_children():
		if child.has_meta("space_circle"): child.visible = active and world.region == "town"
	for child in pins.get_children():
		pins.remove_child(child)
		child.queue_free()
	if not active: return
	for pair: Array in [["示范点", SummerSpace.DEMO], ["观看停点", SummerSpace.stop_for("bench")], ["供餐停点", SummerSpace.stop_for("picnic_table")]]:
		var at: Vector3 = pair[1]
		if not at.is_finite(): continue
		var label: Label3D = _label(str(pair[0]))
		label.position = at + Vector3.UP * .25
		pins.add_child(label)

func show_scheme(key: String) -> void:
	clear_scheme()
	scheme_preview = Node3D.new()
	add_child(scheme_preview)
	for pair: Array in [["bench", SummerSpace.SCHEMES[key].bench], ["picnic_table", SummerSpace.SCHEMES[key].table]]:
		var coordinates: Array = pair[1]
		var mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = PlacementSystem.footprint(str(pair[0]), int(coordinates[2]))
		mesh.mesh = plane
		var material: StandardMaterial3D = LivingAction.matte(Color(.37, .68, .46, .5))
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = material
		mesh.position = Vector3(float(coordinates[0]), .06, float(coordinates[1]))
		scheme_preview.add_child(mesh)
		var label: Label3D = _label("草案 · " + GameState.item_name(str(pair[0])))
		label.position = mesh.position + Vector3.UP * .22
		scheme_preview.add_child(label)

func clear_scheme() -> void:
	if is_instance_valid(scheme_preview):
		remove_child(scheme_preview)
		scheme_preview.queue_free()

func _process(_delta: float) -> void:
	if is_instance_valid(observer):
		if trace.is_empty() or trace.back().distance_to(observer.global_position) > .08: trace.append(observer.global_position)

func begin_walk(actor: NPC) -> void:
	observer = actor
	trace.clear()
	aborted = false
	if s.ui.instant: return
	walk_panel = PanelContainer.new()
	walk_panel.add_theme_stylebox_override("panel", UITheme.paper("hud", 18))
	s.ui.root.add_child(walk_panel)
	walk_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	walk_panel.offset_left = -470
	walk_panel.offset_right = -24
	walk_panel.offset_top = 24
	walk_panel.offset_bottom = 150
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(400, 0)
	walk_panel.add_child(column)
	column.add_child(UITheme.label("看看%s怎样走这条路" % actor.display_name, 25))
	var cancel := Button.new()
	cancel.text = "停止观察 · Esc（方案会保留）"
	cancel.pressed.connect(cancel_walk)
	column.add_child(cancel)

func end_walk() -> void:
	observer = null
	if is_instance_valid(walk_panel): walk_panel.queue_free()

func cancel_walk() -> void:
	aborted = true
	if is_instance_valid(observer): observer.cancel_safe_walk()

func _input(event: InputEvent) -> void:
	if is_instance_valid(observer) and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel_walk()
		get_viewport().set_input_as_handled()

func see_demo(actor: NPC, target: NPC) -> bool:
	var from: Vector3 = eye(actor)
	var to: Vector3 = eye(target)
	var query := PhysicsRayQueryParameters3D.create(from, to, WorldBuilder.L_SOLID | WorldBuilder.L_PLACED)
	return world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

static func eye(actor: NPC) -> Vector3:
	var rigs: Array[Node] = actor.find_children("*", "Skeleton3D", true, false)
	if not rigs.is_empty():
		var skeleton: Skeleton3D = rigs[0] as Skeleton3D
		var head: int = LivingPose.bone(skeleton, "head")
		if head >= 0: return skeleton.global_transform * skeleton.get_bone_global_pose(head).origin
	return actor.global_position + Vector3.UP * 1.4

func look_from(actor: NPC, target: NPC) -> void:
	if s.ui.instant: return
	var original: Camera3D = get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	s.main.add_child(camera)
	camera.position = eye(actor) + Vector3(.18, .03, 0)
	camera.look_at(eye(target))
	camera.fov = 58.0
	camera.make_current()
	await s.say("narrator", "", "这是春从观看停点看到的方向。看清楚了再继续，也可以回去换一处。")
	if is_instance_valid(original): original.make_current()
	camera.queue_free()

func _label(text: String) -> Label3D:
	var label := Label3D.new()
	label.font = load("res://assets/fonts/LXGWWenKai-Medium.ttf")
	label.text = text
	label.font_size = 42
	label.pixel_size = .002
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(.27, .36, .39)
	return label

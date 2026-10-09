class_name MealArrangement
extends Node
signal finished
var s: Story
var active: bool=false
var selected: int=0
var dragging: bool=false
var panel: PanelContainer
var status: Label
var camera: Camera3D
var original: Camera3D

func run(story: Story) -> void:
	s=story
	if NeighbourMeals.current().stage!="portioning" or not s.neighbours.view.surface().is_finite():return
	active=true;GameState.lock_input("meal_arrangement");s.ui.dialogue_end();s.ui.set_hud_visible(false)
	panel=s.ui._open_modal("meal_arrangement");s.ui.dim.hide()
	var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(400,0);box.add_theme_constant_override("separation",10);panel.add_child(box)
	box.add_child(UITheme.label("给两个人留一块空面",28))
	box.add_child(UITheme.label("1 春的碗 · 2 自己的碗\nA/D/W/S 移动，也能直接拖碗\n让开茶托盘，两碗不重叠\nR 回到初案 · 合适可直接保留",21))
	status=UITheme.label("",22);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(status)
	for row: Array in [[["春的碗","haru"],["自己的碗","self"]],[["左","left"],["右","right"],["前","up"],["后","down"]],[["回到初案","reset"],["保留摆法","retain"]],[["先收好，之后再摆","leave"]]]:
		var controls:=HBoxContainer.new();controls.add_theme_constant_override("separation",8);box.add_child(controls)
		for entry: Array in row:
			var button:=Button.new();button.text=entry[0];button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;var action: String=entry[1];button.pressed.connect(func():act(action));controls.add_child(button)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);panel.grow_vertical=Control.GROW_DIRECTION_END;panel.offset_left=-460;panel.offset_right=-24;panel.offset_top=24;panel.offset_bottom=590
	original=s.get_viewport().get_camera_3d();camera=Camera3D.new();s.main.add_child(camera)
	var at: Vector3=s.neighbours.view.surface();camera.global_position=at+Vector3(.8,1.3,1.7);camera.look_at(at);camera.fov=40;camera.make_current()
	update_status()
	if s.ui.instant:
		act("retain")
		if active:act("leave")
	if active:await finished
	if is_instance_valid(original):original.make_current()
	camera.queue_free();s.ui.set_hud_visible(true);GameState.unlock_input("meal_arrangement");s.ui.dialogue_begin()

func _input(event: InputEvent) -> void:
	if not active:return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:act("haru")
			KEY_2:act("self")
			KEY_A:act("left")
			KEY_D:act("right")
			KEY_W:act("up")
			KEY_S:act("down")
			KEY_R:act("reset")
			KEY_ENTER:act("retain")
			KEY_ESCAPE:act("leave")
			_:return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if not event.pressed:dragging=false;return
		if panel.get_global_rect().has_point(event.position):return
		var point: Variant=table_point(event.position)
		if point is Vector3:
			for index in 2:
				if point.distance_to(s.neighbours.view.bowl_at(index))<.16:selected=index;dragging=true;update_status();get_viewport().set_input_as_handled();return
	elif event is InputEventMouseMotion and dragging:
		if (event.button_mask&MOUSE_BUTTON_MASK_LEFT)==0:dragging=false;return
		var dragged_point: Variant=table_point(event.position)
		if dragged_point is Vector3:NeighbourMeals.move_bowl(selected,dragged_point);update_status();get_viewport().set_input_as_handled()

func table_point(pixel: Vector2) -> Variant:
	var plane:=Plane(Vector3.UP,s.neighbours.view.surface().y)
	return plane.intersects_ray(camera.project_ray_origin(pixel),camera.project_ray_normal(pixel))

func act(action: String) -> void:
	if not active:return
	if action=="leave":close();return
	if action=="reset":NeighbourMeals.reset_bowls();update_status();return
	if action=="retain":
		var why: String=NeighbourMeals.retain_layout(s.neighbours.view.layout_reason(),s.neighbours.at_table())
		if why!="":status.text=why;return
		close();return
	if action in ["haru","self"]:selected=0 if action=="haru" else 1
	else:
		var at: Vector3=s.neighbours.view.bowl_at(selected)
		var offset: Vector3={"left":Vector3(-.1,0,0),"right":Vector3(.1,0,0),"up":Vector3(0,0,-.1),"down":Vector3(0,0,.1)}.get(action,Vector3.ZERO)
		NeighbourMeals.move_bowl(selected,at+offset)
	update_status()

func update_status() -> void:
	var why: String=s.neighbours.view.layout_reason()
	status.text=("春的碗" if selected==0 else "自己的碗")+"已选中\n"+("取茶空处留好了，可以保留" if why=="" else why)
	for index in 2:
		var node: MeshInstance3D=s.neighbours.view.dish.get_node_or_null("Bowl_%d"%index)
		if node:node.material_override=LivingAction.matte(Color(.91,.83,.46) if selected==index else Color(.92,.96,.98))

func close() -> void:
	active=false;s.ui.close_modal(false);finished.emit()

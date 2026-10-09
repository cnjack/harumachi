class_name PicklePreparation
extends Node
signal finished
var s: Story
var active: bool=false
var status: Label
var camera: Camera3D
var original: Camera3D

func run(story: Story) -> void:
	s=story;active=true
	if not s.neighbours.view.surface().is_finite():active=false;return
	GameState.lock_input("pickle_preparation")
	s.ui.dialogue_end();s.ui.set_hud_visible(false)
	var panel: PanelContainer=s.ui._open_modal("pickle_preparation")
	s.ui.dim.hide()
	var box:=VBoxContainer.new();box.custom_minimum_size=Vector2(410,0);box.add_theme_constant_override("separation",10);panel.add_child(box)
	box.add_child(UITheme.label("杯边的一小碗",30))
	var source: Dictionary=NeighbourMeals.current()
	box.add_child(UITheme.label("黄瓜：空 %d 根，春 %d 根\n盐：春留的一撮"%[int(source.player_materials.get("cucumber",0)),int(source.haru_materials.get("cucumber",0))],21))
	box.add_child(UITheme.label("薄片入味快，脆块留着配饭。\nA / D 换切法 · 空格切一段\nS 撒盐 · W 沥汁 · Esc 收好半成品",21))
	status=UITheme.label("",22);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(status)
	for option: Array in [["薄片","thin"],["脆块","chunk"],["切一段","cut"],["撒一撮盐","salt"],["沥汁 / 留汁","drain"],["分成两小份","finish"],["收好，之后接着做","leave"]]:
		var button:=Button.new();button.text=option[0];var action: String=option[1];button.pressed.connect(func():act(action));box.add_child(button)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);panel.offset_left=-470;panel.offset_right=-24;panel.offset_top=30;panel.offset_bottom=580
	original=s.get_viewport().get_camera_3d();camera=Camera3D.new();s.main.add_child(camera)
	var at: Vector3=s.neighbours.view.surface();camera.global_position=at+Vector3(.8,1.3,1.7);camera.look_at(at);camera.fov=40;camera.make_current()
	update_status()
	if s.ui.instant:
		while int(NeighbourMeals.current().cuts)<3:act("cut")
		act("salt");NeighbourMeals.drain(NeighbourMeals.current().style=="thin");act("finish")
	if active: await finished
	if is_instance_valid(original):original.make_current()
	camera.queue_free();s.ui.set_hud_visible(true);GameState.unlock_input("pickle_preparation");s.ui.dialogue_begin()

func _input(event: InputEvent) -> void:
	if not active or not event is InputEventKey or not event.pressed or event.echo:return
	match event.keycode:
		KEY_A:act("thin")
		KEY_D:act("chunk")
		KEY_SPACE:act("cut")
		KEY_S:act("salt")
		KEY_W:act("drain")
		KEY_ENTER:act("finish")
		KEY_ESCAPE:act("leave")
		_:return
	get_viewport().set_input_as_handled()

func act(action: String) -> void:
	if not active:return
	match action:
		"thin","chunk":NeighbourMeals.change_style(action)
		"cut":NeighbourMeals.cut(1);Audio.fx("paper",-8)
		"salt":NeighbourMeals.salt();Audio.fx("place",-8)
		"drain":NeighbourMeals.drain(not NeighbourMeals.current().drained)
		"finish":
			var why: String=NeighbourMeals.finish(s.neighbours.at_table())
			if why!="":status.text=why;return
			close();return
		"leave":close();return
	update_status()

func update_status() -> void:
	var entry: Dictionary=NeighbourMeals.current()
	status.text="%s · 切好 %d/3\n%s · %s"%[NeighbourMeals.NAMES[entry.style],int(entry.cuts),"盐已拌入" if entry.salted else "盐还在旁边","沥过汁，纸包不湿" if entry.drained else "汁留在碗里"]

func close() -> void:
	active=false;s.ui.close_modal(false);finished.emit()

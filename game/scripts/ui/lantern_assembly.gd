class_name LanternAssembly
extends Node
signal finished
var s: Story
var active := false
var panel: PanelContainer
var status: Label
var saved_rig: Dictionary
var close_camera: Camera3D
var original_camera: Camera3D

func run(story: Story) -> void:
	s = story
	if WorkshopProject.state().phase != "assembly": return
	GameState.lock_input("workshop")
	active = true
	saved_rig = {"fixed": s.main.rig.fixed, "yaw": s.main.rig.yaw, "pitch": s.main.rig.pitch, "dist": s.main.rig.dist}
	s.ui.dialogue_end()
	s.ui.set_hud_visible(false)
	# Look at the actual room table rather than a flat illustration of a completed lantern.
	s.main.rig.fixed = true
	s.main.rig.yaw = 190.0
	s.main.rig.pitch = 25.0
	s.main.rig.dist = 3.2
	s.main.rig.snap()
	original_camera = s.get_viewport().get_camera_3d()
	close_camera = Camera3D.new()
	s.main.add_child(close_camera)
	var origin: Vector3 = InteriorBuilder.SPECS.workroom.origin
	close_camera.global_position = origin + Vector3(-2.6, 2.1, 2.6)
	close_camera.look_at(origin + Vector3(-1.2, 1.03, -.4))
	close_camera.fov = 38.0
	close_camera.make_current()
	panel = s.ui._open_modal("workshop")
	panel.add_theme_stylebox_override("panel", UITheme.paper("modal", 24))
	s.ui.dim.visible = false
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(390, 0)
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	column.add_child(UITheme.label("对齐这一盏的接头", 30))
	column.add_child(UITheme.label("A / D 转动竹篾\n空格扣上 · 绿色处是接头\nEsc 收好半成品，之后再来", 23))
	status = UITheme.label("", 24)
	column.add_child(status)
	var controls := HBoxContainer.new()
	for entry: Array in [["向左转", -15.0], ["向右转", 15.0], ["扣上", 0.0]]:
		var button := Button.new()
		button.text = str(entry[0])
		var delta: float = float(entry[1])
		button.pressed.connect(func(): _act(delta))
		controls.add_child(button)
	column.add_child(controls)
	var leave := Button.new()
	leave.text = "收好半成品"
	leave.pressed.connect(_finish)
	column.add_child(leave)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left=-450
	panel.offset_right=-24
	panel.offset_top=40
	panel.offset_bottom=390
	_update()
	if s.ui.instant:
		# Rule automation is distinct from native input evidence.
		while int(WorkshopProject.state().joints) < 3:
			WorkshopProject.rotate_part(float(WorkshopProject.TARGETS[int(WorkshopProject.state().joints)]) - float(WorkshopProject.state().angle))
			if WorkshopProject.fit() != "": break
		_finish()
	if active: await finished
	s.main.rig.fixed = bool(saved_rig.fixed)
	s.main.rig.yaw = float(saved_rig.yaw)
	s.main.rig.pitch = float(saved_rig.pitch)
	s.main.rig.dist = float(saved_rig.dist)
	s.main.rig.snap()
	if is_instance_valid(original_camera): original_camera.make_current()
	close_camera.queue_free()
	s.ui.set_hud_visible(true)
	GameState.unlock_input("workshop")
	s.ui.dialogue_begin()

func _input(event: InputEvent) -> void:
	if not active or not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_A: _act(-15.0)
		KEY_D: _act(15.0)
		KEY_SPACE: _act(0.0)
		KEY_ESCAPE: _finish()
		_: return
	get_viewport().set_input_as_handled()

func _act(delta: float) -> void:
	if not active: return
	if delta != 0.0: WorkshopProject.rotate_part(delta)
	else:
		var why: String = WorkshopProject.fit()
		if why != "": status.text = why; return
	_update()
	if WorkshopProject.state().phase == "assembled": _finish()

func _update() -> void:
	status.text = "接好 %d / 3 · 当前 %d°" % [int(WorkshopProject.state().joints), int(WorkshopProject.state().angle)]

func _finish() -> void:
	if not active: return
	active = false
	s.ui.close_modal(false)
	finished.emit()

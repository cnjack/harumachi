class_name PhotoMode
extends CanvasLayer
## Pause world time and control a separate camera; save only after all overlays disappear.
var main: Node
var active:=false
var last_path:=""
var capture_size:=Vector2i(3840,2160)
var camera: Camera3D
var tools: Control
var _old_pause:=false
var _old_marker:=false
var _old_actor:=false
var _drag:=false
var _yaw:=0.0
var _pitch:=0.0
var _saving:=false
var _tags: Array[Dictionary]=[]

func setup(world_main: Node) -> void:
	main=world_main;layer=40
	camera=Camera3D.new();camera.name="PhotoCamera";camera.far=1200;main.add_child(camera)

func toggle() -> void:
	if active:finish();return
	if GameState.input_locked() or main.in_room and main._transition:return
	active=true;_old_pause=GameState.clock_paused;GameState.clock_paused=true;GameState.lock_input("photo")
	_old_marker=main.marker.visible;_old_actor=main.player.model_root.visible
	main.ui.ambient_layer.visible=false;main.marker.visible=false
	_tags.clear()
	for npc: NPC in main.npcs.values():_tags.append({"tag":npc.tag,"visible":npc.tag.visible});npc.tag.visible=false
	camera.global_transform=main.rig.cam.global_transform;camera.fov=main.rig.cam.fov
	_yaw=camera.rotation.y;_pitch=camera.rotation.x;camera.make_current()
	_build_tools()

func _build_tools() -> void:
	tools=Control.new();tools.theme=UITheme.make();tools.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);tools.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(tools)
	var bar:=PanelContainer.new();bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM);bar.grow_horizontal=Control.GROW_DIRECTION_BOTH
	bar.offset_left=-290;bar.offset_right=290;bar.offset_top=-78;bar.offset_bottom=-22;bar.add_theme_stylebox_override("panel",UITheme.paper("hud",12));tools.add_child(bar)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);bar.add_child(row)
	row.add_child(ControlGlyph.make("move","WASD 平移；Q/E 升降"));row.add_child(ControlGlyph.make("mouse","右键转动镜头；滚轮焦距"))
	var actors:=Button.new();actors.name="PhotoActors";actors.text="人物";actors.toggle_mode=true;actors.button_pressed=_old_actor;UIKitComponents.style_button(actors,"quiet")
	actors.toggled.connect(func(v: bool):main.player.model_root.visible=v);row.add_child(actors)
	var capture:=Button.new();capture.name="PhotoCapture";capture.text="F12";capture.custom_minimum_size=Vector2(100,42);UIKitComponents.style_button(capture,"primary")
	capture.tooltip_text="保存无界面 PNG";capture.pressed.connect(save_picture);row.add_child(capture)
	row.add_child(ControlGlyph.make("camera","F12 拍照 · F6 隐藏操作条 · Esc 返回"))
	var close:=Button.new();close.text="Esc";UIKitComponents.style_button(close,"quiet");close.pressed.connect(finish);row.add_child(close)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F6:
			if active:tools.visible=not tools.visible
			get_viewport().set_input_as_handled();return
		if event.keycode==KEY_F8:
			toggle();get_viewport().set_input_as_handled();return
		if active and event.keycode==KEY_ESCAPE:
			finish();get_viewport().set_input_as_handled();return
		if active and event.keycode==KEY_F12:
			save_picture();get_viewport().set_input_as_handled();return
	if not active:return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:_drag=event.pressed
		elif event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP:camera.fov=clampf(camera.fov-2,20,85)
		elif event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN:camera.fov=clampf(camera.fov+2,20,85)
	elif event is InputEventMouseMotion and _drag:
		_yaw-=event.relative.x*.0035;_pitch=clampf(_pitch-event.relative.y*.0035,-1.45,1.45)
		camera.rotation=Vector3(_pitch,_yaw,0)

func _process(delta: float) -> void:
	if not active or _saving:return
	var input:=Input.get_vector("move_left","move_right","move_forward","move_back")
	var rise:=float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q))
	var speed:=7.0 if Input.is_action_pressed("sprint") else 2.6
	var move: Vector3=camera.basis*Vector3(input.x,0,input.y)+Vector3.UP*rise
	var next: Vector3=camera.global_position+move*speed*delta
	if main.world.region=="town":
		next.x=clampf(next.x,-58,48);next.z=clampf(next.z,-35,90)
	elif not main.in_room:
		next.x=clampf(next.x,FarmBuilder.ORIGIN.x-35,FarmBuilder.ORIGIN.x+150);next.z=clampf(next.z,-40,70)
	next.y=clampf(next.y,.55,24);camera.global_position=next

func save_picture() -> void:
	if not active or _saving:return
	_saving=true
	var shown:=tools.visible;tools.visible=false
	var render:=SubViewport.new();render.name="PhotoRender";render.size=capture_size
	render.world_3d=main.get_world_3d();render.msaa_3d=Viewport.MSAA_4X
	render.render_target_update_mode=SubViewport.UPDATE_ONCE;add_child(render)
	var lens:=Camera3D.new();render.add_child(lens);lens.global_transform=camera.global_transform
	lens.fov=camera.fov;lens.near=camera.near;lens.far=camera.far;lens.make_current()
	await RenderingServer.frame_post_draw
	var pixels:=render.get_texture().get_image()
	render.queue_free()
	var folder:=OS.get_system_dir(OS.SYSTEM_DIR_PICTURES).path_join("Harumachi")
	if folder=="Harumachi":folder=ProjectSettings.globalize_path("user://photos")
	var error:=DirAccess.make_dir_recursive_absolute(folder)
	var stamp:=Time.get_datetime_string_from_system().replace(":","-")
	last_path=folder.path_join("晴町_"+stamp+"_"+str(Time.get_ticks_msec())+".png")
	if error==OK and pixels!=null:error=pixels.save_png(last_path)
	tools.visible=shown;_saving=false
	if error==OK:
		Audio.ui("click");print("PHOTO_SAVED ",last_path)
		var button:=tools.find_child("PhotoCapture",true,false) as Button
		if button:button.text="✓ 4K";button.tooltip_text=last_path
	else:last_path="";GameState.toast.emit("照片保存失败：%d"%error)

func finish() -> void:
	if not active:return
	active=false;_drag=false;main.rig.cam.make_current()
	main.player.model_root.visible=_old_actor;main.marker.visible=_old_marker
	for tag: Dictionary in _tags:
		if is_instance_valid(tag.tag):tag.tag.visible=tag.visible
	_tags.clear()
	main.ui.ambient_layer.visible=true;GameState.clock_paused=_old_pause;GameState.unlock_input("photo")
	if is_instance_valid(tools):tools.queue_free()

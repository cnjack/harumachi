class_name FishingPanel
extends Control
signal closed
var session: FishingSession
var scene_view: FishingView
var state_label: Label
var status_label: Label
var detail_label: Label
var tension_bar: ProgressBar
var progress_bar: ProgressBar
var action_button: Button
var _held := false
var _closed := false
var _last_state := -1
var _result_icon: TextureRect

func setup(spot_id: String,view: FishingView) -> void:
	session=FishingSession.new(spot_id);scene_view=view
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	card.grow_vertical=Control.GROW_DIRECTION_BEGIN
	card.grow_horizontal=Control.GROW_DIRECTION_BOTH
	card.offset_left=-330;card.offset_right=330;card.offset_top=-275;card.offset_bottom=-65
	card.add_theme_stylebox_override("panel",UITheme.paper("modal",24))
	add_child(card)
	var body := VBoxContainer.new();body.add_theme_constant_override("separation",8);card.add_child(body)
	var header := HBoxContainer.new();body.add_child(header)
	state_label=UITheme.label(str(LakesideLayout.SPOTS[spot_id].name),25);state_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(state_label)
	var leave := Button.new();leave.text="收竿  Esc";leave.pressed.connect(finish);header.add_child(leave)
	status_label=UITheme.label("按 E / 空格抛竿",26,UITheme.ACCENT);status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(status_label)
	var track:=FishingTrack.new();track.session=session;track.custom_minimum_size=Vector2(580,70);body.add_child(track)
	var row := HBoxContainer.new();body.add_child(row)
	_result_icon=UITheme.icon("fish_ayu",90);_result_icon.visible=false;row.add_child(_result_icon)
	var bars := VBoxContainer.new();bars.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(bars)
	progress_bar=_bar(UITheme.GOOD);bars.add_child(progress_bar)
	tension_bar=_bar(Color(.82,.58,.28));bars.add_child(tension_bar)
	detail_label=UITheme.label("按住 →  ·  松开 ←  ·  让鱼影留在绿色区间",18,UITheme.INK_SOFT)
	detail_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(detail_label)
	action_button=Button.new();action_button.text="抛竿  E / 空格";action_button.custom_minimum_size.y=42
	action_button.button_down.connect(func():_held=true;session.tap())
	action_button.button_up.connect(func():_held=false)
	body.add_child(action_button)

func _bar(colour: Color) -> ProgressBar:
	var bar := ProgressBar.new();bar.custom_minimum_size=Vector2(400,10);bar.show_percentage=false;bar.max_value=1.0
	bar.add_theme_stylebox_override("background",UIKitStyles.progress())
	bar.add_theme_stylebox_override("fill",UIKitStyles.progress("fill",colour));return bar

func _process(delta: float) -> void:
	if session==null or _closed:return
	session.step(delta,_held)
	scene_view.update_view(session,delta)
	status_label.text=session.message
	progress_bar.value=session.reel_progress;tension_bar.value=session.tension
	tension_bar.modulate=Color(1,.45,.40) if session.tension>.84 else Color.WHITE
	if _last_state!=session.state:
		_last_state=session.state
		if session.state==FishingSession.State.BITE:Audio.ui("click")
		if session.state==FishingSession.State.LANDED:
			Audio.sting("sparkle")
			var burst:=Celebration.new();add_child(burst)
			burst.setup(GameState.item_name(str(session.result.fish)),str(session.result.fish),"%.1f cm%s"%[float(session.result.cm),"  新纪录" if session.result.new_record else ""])
			if scene_view.player.anim:scene_view.player.anim.play_once("cheer")
			_result_icon.texture=UITheme.icon_texture(str(session.result.fish))
			_result_icon.visible=true
			detail_label.text="背包 +1  ·  %d 生活币%s" % [int(session.result.sell)," · 新的长度纪录！" if session.result.new_record else ""]
		else:
			_result_icon.visible=false
			detail_label.text="按住 →  ·  松开 ←  ·  跟住鱼影，红线时松开"
		action_button.text="再抛一竿  E / 空格" if session.state in [FishingSession.State.LANDED,FishingSession.State.MISSED] else ("按住 →   /   松开 ←" if session.state==FishingSession.State.REEL else "抛竿 / 提竿  E / 空格")
	state_label.text="%s  ·  %d" % [LakesideLayout.SPOTS[session.spot].name,GameState.count("fishing_bait")]

func _input(event: InputEvent) -> void:
	if session==null or _closed:return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled();finish();return
	if event is InputEventKey and (event.keycode==KEY_E or event.keycode==KEY_SPACE):
		if event.echo:return
		_held=event.pressed
		if event.pressed:session.tap()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		# Clicks on buttons are handled by their own signals; empty scene clicks reel.
		if get_viewport().gui_get_hovered_control() is Button:return
		_held=event.pressed
		if event.pressed:session.tap()
		get_viewport().set_input_as_handled()

func finish() -> void:
	if _closed:return
	_closed=true;_held=false;session.close()
	if is_instance_valid(scene_view):scene_view.queue_free()
	closed.emit()

func _exit_tree() -> void:
	if session!=null:finish()

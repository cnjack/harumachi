extends Control
## Title screen: key art, new game / continue / settings / quit.

var menu := VBoxContainer.new()
var status: Label
var panel_layer := Control.new()
const MENU_CAT=preload("res://scripts/ui/menu_cat.gd")


func _ready() -> void:
	Audio.game_on = false
	Audio.set_indoor(false, "")
	Audio.play_music("title", 1.5)
	theme = UITheme.make()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/title_keyart.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.1, 0.06, 0.03, 0.55))
	g.set_color(1, Color(0.1, 0.06, 0.03, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0.62, 0)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(shade)
	var title := UITheme.label("明年夏祭", 118, Color(1, 0.98, 0.92))
	title.name="TitleHeading"
	title.add_theme_color_override("font_outline_color", Color(0.36, 0.22, 0.12, 0.9))
	title.add_theme_constant_override("outline_size", 22)
	title.position = Vector2(110, 120)
	add_child(title)
	var walking_cat: Control=MENU_CAT.new() as Control
	walking_cat.name="MenuCat"
	add_child(walking_cat)
	var sub := UITheme.label("Harumachi: Next Summer · 晴町的这个夏天", 34, Color(1, 0.96, 0.88))
	sub.add_theme_color_override("font_outline_color", Color(0.3, 0.2, 0.1, 0.85))
	sub.add_theme_constant_override("outline_size", 10)
	sub.position = Vector2(118, 280)
	add_child(sub)
	menu.position = Vector2(118, 420)
	menu.add_theme_constant_override("separation", 16)
	add_child(menu)
	var items := [["新的一天", _new_game], ["继续", _continue], ["设置", _settings], ["退出", func(): get_tree().quit()]]
	var first: Button = null
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.custom_minimum_size = Vector2(380, 70)
		b.add_theme_font_size_override("font_size", 32)
		b.pressed.connect(it[1])
		menu.add_child(b)
		if it[0] == "继续":
			b.disabled = not GameState.has_save()
		if first == null:
			first = b
	status = UITheme.label("", 26, Color(1, 0.9, 0.8))
	status.add_theme_color_override("font_outline_color", Color(0.3, 0.1, 0.05))
	status.add_theme_constant_override("outline_size", 8)
	status.position = Vector2(118, 800)
	add_child(status)
	var ver := UITheme.label("晴町的这个夏天 · 开发中", 20, Color(1, 1, 1, 0.85))
	ver.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.08, 0.8))
	ver.add_theme_constant_override("outline_size", 6)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(118, -54)
	add_child(ver)
	panel_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel_layer)
	first.call_deferred("grab_focus")
	if "--autoplay" in OS.get_cmdline_user_args() or "--newgame" in OS.get_cmdline_user_args() or "--prologue-only" in OS.get_cmdline_user_args():
		get_tree().create_timer(1.5 if "--autoplay" in OS.get_cmdline_user_args() else 0.05).timeout.connect(_new_game)


func _start_new(slot: int) -> void:
	if Loading.scene_busy:
		return
	SaveDB.select_slot(slot)
	GameState.clock_paused = false
	GameState.new_game()
	GameState.load_on_enter = false
	# v0.6: a new game opens with the prologue slideshow (skipped under --autoplay / --newgame;
	# --prologue-only plays it and quits, which also works in the exported app)
	var direct := "--autoplay" in OS.get_cmdline_user_args() or "--newgame" in OS.get_cmdline_user_args()
	Loading.change_scene("res://scenes/main.tscn" if direct else "res://scenes/prologue.tscn", "开始新的一天")


func _new_game() -> void:
	if OS.get_cmdline_user_args().has("--autoplay-resume"):
		if GameState.load_game():
			GameState.load_on_enter=true
			Loading.change_scene("res://scenes/main.tscn","恢复自动验证进度")
		return
	var direct:=OS.get_cmdline_user_args().has("--newgame") or OS.get_cmdline_user_args().has("--autoplay") or OS.get_cmdline_user_args().has("--prologue-only")
	if direct:
		var chosen:=1
		for row: Dictionary in SaveDB.list_slots():
			if bool(row.empty):chosen=int(row.slot);break
		_start_new(chosen);return
	_slots("new")


func _continue() -> void:
	_slots("load")


func _slots(mode: String) -> void:
	for child: Node in panel_layer.get_children():child.queue_free()
	var panel:=PanelContainer.new();panel.name="TitleSaveSlots";panel.add_theme_stylebox_override("panel",UITheme.paper("modal",24))
	panel.set_anchors_preset(Control.PRESET_CENTER);panel.offset_left=0;panel.offset_top=0;panel.offset_right=0;panel.offset_bottom=0;panel.grow_horizontal=Control.GROW_DIRECTION_BOTH;panel.grow_vertical=Control.GROW_DIRECTION_BOTH;panel_layer.add_child(panel)
	var slots:=SaveSlotsPanel.new();panel.add_child(slots);slots.setup(mode)
	slots.cancelled.connect(func():panel.queue_free())
	slots.slot_chosen.connect(func(slot: int):
		if mode=="new":_start_new(slot)
		elif GameState.load_slot(slot):
			GameState.clock_paused = false
			GameState.load_on_enter=true;Loading.change_scene("res://scenes/main.tscn","回到晴町")
		else:slots.status.text=GameState.last_error)


func _settings() -> void:
	for c in panel_layer.get_children():
		c.queue_free()
	var p := PanelContainer.new()
	p.position = Vector2(560, 420)
	panel_layer.add_child(p)
	p.add_child(UIKitComponents.resting_cat(76,.82))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.custom_minimum_size = Vector2(620, 0)
	p.add_child(v)
	v.add_child(UITheme.label("设置", 38))
	GameUI.build_settings_rows(v)
	var b := Button.new()
	b.text = "完成"
	b.custom_minimum_size = Vector2(180, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(func(): p.queue_free())
	v.add_child(b)
	b.grab_focus()

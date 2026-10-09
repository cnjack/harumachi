class_name HUDLayout
extends RefCounted

static func build(ui: GameUI) -> void:
	ui.objective_panel=PanelContainer.new();ui.objective_panel.name="ObjectiveCard"
	ui.objective_panel.position=Vector2(28,24);ui.objective_panel.custom_minimum_size=Vector2(460,0)
	ui.objective_panel.add_theme_stylebox_override("panel",UITheme.paper("hud",24))
	ui.objective_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.hud.add_child(ui.objective_panel)
	var objective:=VBoxContainer.new();objective.add_theme_constant_override("separation",6);ui.objective_panel.add_child(objective)
	var heading:=HBoxContainer.new();heading.add_theme_constant_override("separation",10)
	heading.add_child(UITheme.icon("quest",30));ui.obj_title=UITheme.label("",20,UITheme.INK_SOFT);heading.add_child(ui.obj_title);objective.add_child(heading)
	ui.obj_text=UITheme.label("",25);ui.obj_text.custom_minimum_size.x=420;ui.obj_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;objective.add_child(ui.obj_text)
	ui.resource_panel=PanelContainer.new();ui.resource_panel.name="Resources";ui.resource_panel.custom_minimum_size=Vector2(460,0)
	ui.resource_panel.add_theme_stylebox_override("panel",UITheme.paper("hud",18))
	ui.resource_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.hud.add_child(ui.resource_panel)
	var resource_row:=HBoxContainer.new();resource_row.add_theme_constant_override("separation",9);ui.resource_panel.add_child(resource_row)
	resource_row.add_child(UITheme.icon("coin",30));ui.coin_label=UITheme.label("",22);resource_row.add_child(ui.coin_label)
	resource_row.add_child(UITheme.icon("support_token",30));ui.token_label=UITheme.label("",21);resource_row.add_child(ui.token_label)
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;resource_row.add_child(spacer)
	resource_row.add_child(UITheme.icon("level_badge",28));ui.level_label=UITheme.label("",20);resource_row.add_child(ui.level_label)
	ui.xp_bar=ProgressBar.new();ui.xp_bar.custom_minimum_size=Vector2(86,10);ui.xp_bar.show_percentage=false;ui.xp_bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	ui.xp_bar.add_theme_stylebox_override("background",UIKitStyles.progress())
	ui.xp_bar.add_theme_stylebox_override("fill",UIKitStyles.progress("fill"));resource_row.add_child(ui.xp_bar)
	ui.objective_panel.resized.connect(func():ui.resource_panel.position=ui.objective_panel.position+Vector2(0,ui.objective_panel.size.y+9))
	ui.resource_panel.position=Vector2(28,147)
	ui.coin_pop=UITheme.label("",24,UITheme.GOOD);ui.coin_pop.position=Vector2(77,148);ui.coin_pop.modulate.a=0;ui.hud.add_child(ui.coin_pop)
	ui.clock_panel=PanelContainer.new();ui.clock_panel.name="ClockCard";ui.clock_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ui.clock_panel.offset_left=-346;ui.clock_panel.offset_right=-28;ui.clock_panel.offset_top=24;ui.clock_panel.offset_bottom=24
	ui.clock_panel.custom_minimum_size=Vector2(318,0);ui.clock_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.hud.add_child(ui.clock_panel)
	ui.clock_panel.add_theme_stylebox_override("panel",UITheme.paper("hud",26))
	var time_column:=VBoxContainer.new();time_column.add_theme_constant_override("separation",3);ui.clock_panel.add_child(time_column)
	ui.area_label=UITheme.label("晴町",23);time_column.add_child(ui.area_label)
	var time_row:=HBoxContainer.new();time_row.add_theme_constant_override("separation",14);time_column.add_child(time_row)
	ui.weather_icon=UITheme.icon("w_sunny",39);time_row.add_child(ui.weather_icon);ui.clock_label=UITheme.label("",35);time_row.add_child(ui.clock_label)
	ui.date_label=UITheme.label("",18,UITheme.INK_SOFT);time_column.add_child(ui.date_label)
	ui.fest_label=UITheme.label("",18,UITheme.ACCENT);ui.fest_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;ui.fest_label.visible=false;time_column.add_child(ui.fest_label)
	ui.prompt_panel=PanelContainer.new();ui.prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM);ui.prompt_panel.grow_horizontal=Control.GROW_DIRECTION_BOTH
	GameUI._dock(ui.prompt_panel,-200,200,-160);ui.prompt_panel.custom_minimum_size=Vector2(400,0);ui.prompt_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.prompt_panel.add_theme_stylebox_override("panel",UITheme.paper("hud",22))
	var prompt_row:=HBoxContainer.new();prompt_row.alignment=BoxContainer.ALIGNMENT_CENTER;prompt_row.add_theme_constant_override("separation",10)
	prompt_row.add_child(UITheme.icon("interact",32));ui.prompt_label=UITheme.label("",25);prompt_row.add_child(ui.prompt_label);ui.prompt_panel.add_child(prompt_row)
	ui.prompt_panel.visible=false;ui.hud.add_child(ui.prompt_panel)
	var movement:=PanelContainer.new();movement.name="MovementHints";movement.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	movement.offset_left=28;movement.offset_right=278;movement.offset_top=-63;movement.offset_bottom=-19
	movement.mouse_filter=Control.MOUSE_FILTER_IGNORE;movement.add_theme_stylebox_override("panel",UITheme.paper("hud",16));ui.hud.add_child(movement)
	var hints:=HBoxContainer.new();hints.add_theme_constant_override("separation",16);movement.add_child(hints)
	for symbol: Array in [["move","WASD / 方向键 移动"],["run","Shift 奔跑"],["mouse","右键转镜头"],["zoom","滚轮缩放"]]:hints.add_child(ControlGlyph.make(str(symbol[0]),str(symbol[1]),30))
	ui.hint_label=UITheme.label("",1);ui.hint_label.visible=false;hints.add_child(ui.hint_label)
	ui.shortcuts_bar=PanelContainer.new();ui.shortcuts_bar.name="Shortcuts";ui.shortcuts_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ui.shortcuts_bar.offset_left=-486;ui.shortcuts_bar.offset_right=-28;ui.shortcuts_bar.offset_top=-65;ui.shortcuts_bar.offset_bottom=-19
	ui.shortcuts_bar.add_theme_stylebox_override("panel",UITheme.paper("hud",12));ui.hud.add_child(ui.shortcuts_bar)
	var commands:=HBoxContainer.new();commands.add_theme_constant_override("separation",5);ui.shortcuts_bar.add_child(commands)
	for spec: Array in [["map","地图","M"],["backpack","背包","Tab"],["quest","委托","J"],["calendar","日历","C"],["book","图鉴","K"],["camera","拍照","F8"],["settings","菜单","Esc"]]:
		var id: String=spec[0]
		var button:=Button.new();button.name="Shortcut_"+id;button.text=str(spec[2]);button.icon=UITheme.icon_texture(id)
		button.expand_icon=true;button.add_theme_constant_override("icon_max_width",24);button.add_theme_font_size_override("font_size",18)
		button.custom_minimum_size=Vector2(60,38);button.focus_mode=Control.FOCUS_NONE;button.tooltip_text=str(spec[1])+"（"+str(spec[2])+"）"
		UIKitComponents.style_button(button,"quiet",true)
		button.pressed.connect(func():_command(ui,id));commands.add_child(button)
	ui.toast_box=VBoxContainer.new();ui.toast_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ui.toast_box.position=Vector2(-488,198);ui.toast_box.custom_minimum_size=Vector2(460,0);ui.toast_box.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.toast_box.add_theme_constant_override("separation",8);ui.hud.add_child(ui.toast_box)

static func _command(ui: GameUI,id: String) -> void:
	if ui.modal!="" or GameState.input_locked():return
	match id:
		"map":ui.open_world_map()
		"backpack":ui.open_inventory()
		"quest":ui.open_quests()
		"calendar":ui.panels.open_calendar()
		"book":ui.book.open()
		"settings":ui.open_pause()
		"camera":ui.world_main.photo.toggle()

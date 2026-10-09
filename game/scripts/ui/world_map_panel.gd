class_name WorldMapPanel
extends VBoxContainer
var ui: GameUI
var canvas: WorldMapCanvas
var _places: VBoxContainer
var _detail: Label
var _distance: Label
var _tabs: Dictionary={}
var _region := "town"

func setup(game_ui: GameUI) -> void:
	ui=game_ui
	add_theme_constant_override("separation",14)
	var header:=HBoxContainer.new()
	header.add_child(UITheme.icon("map",44));header.add_child(UITheme.label("晴町漫游图",34))
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(spacer)
	header.add_child(UITheme.label("选择一个想去的地方",21,UITheme.INK_SOFT));add_child(header)
	var tabs:=HBoxContainer.new();tabs.add_theme_constant_override("separation",10);add_child(tabs)
	var group:=ButtonGroup.new()
	for region: String in ["town","farm"]:
		var button:=Button.new();button.name="Region_"+region
		button.text="晴町街巷" if region=="town" else "农园 · 晴川 · 镜波湖"
		button.icon=UITheme.icon_texture("home" if region=="town" else "fish")
		button.expand_icon=true;button.add_theme_constant_override("icon_max_width",30)
		button.custom_minimum_size=Vector2(275,48);button.toggle_mode=true;button.button_group=group
		button.pressed.connect(func():set_region(region));tabs.add_child(button);_tabs[region]=button
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",20);add_child(row)
	var holder:=Control.new();holder.name="MapViewport";holder.custom_minimum_size=Vector2(880,470);holder.clip_contents=true;row.add_child(holder)
	canvas=WorldMapCanvas.new();canvas.name="MapCanvas";canvas.main=ui.world_main;canvas.full=true;canvas.size=holder.custom_minimum_size
	canvas.place_selected.connect(select_place);holder.add_child(canvas)
	var side:=VBoxContainer.new();side.custom_minimum_size=Vector2(260,0);side.add_theme_constant_override("separation",10);row.add_child(side)
	side.add_child(UITheme.label("想去哪里",24))
	var sc:=ScrollContainer.new();sc.custom_minimum_size=Vector2(260,300);sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;sc.follow_focus=true;side.add_child(sc)
	_places=VBoxContainer.new();_places.add_theme_constant_override("separation",6);_places.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sc.add_child(_places)
	_detail=UITheme.label("",21);_detail.custom_minimum_size.x=250;_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;side.add_child(_detail)
	_distance=UITheme.label("",19,UITheme.INK_SOFT);side.add_child(_distance)
	var clear:=Button.new();clear.name="ClearDestination";clear.text="清除地点标记";clear.custom_minimum_size.y=42;clear.pressed.connect(func():ui.map_destination.clear();canvas.queue_redraw();_refresh_detail());side.add_child(clear)
	var footer:=HBoxContainer.new();footer.add_theme_constant_override("separation",12);add_child(footer)
	footer.add_child(UITheme.icon("compass",30));footer.add_child(UITheme.label("红箭头是你 · 金圈是方向 · 地图始终朝北",20,UITheme.INK_SOFT))
	var fill:=Control.new();fill.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(fill)
	footer.add_child(ui._close_button("收起地图  M"))
	set_region(str(ui.world_main.world.region))

func set_region(region: String) -> void:
	_region=region;canvas.region_override=region;canvas.queue_redraw()
	(_tabs[region] as Button).set_pressed_no_signal(true)
	for child: Node in _places.get_children():child.free()
	for place: Dictionary in MapPlaces.places(region):
		var selected: Dictionary=place.duplicate()
		var button:=Button.new();button.name="Place_"+str(place.id);button.text=place.name
		button.icon=UITheme.icon_texture(place.icon);button.expand_icon=true;button.add_theme_constant_override("icon_max_width",28)
		button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.custom_minimum_size=Vector2(245,40)
		UIKitComponents.style_button(button,"quiet",true)
		button.add_theme_font_size_override("font_size",21);button.pressed.connect(func():select_place(selected));_places.add_child(button)
	_refresh_detail()

func select_place(place: Dictionary) -> void:
	ui.map_destination=place.duplicate(true)
	canvas.queue_redraw();_refresh_detail()

func _refresh_detail() -> void:
	var selected: Dictionary=ui.map_destination
	if selected.is_empty():
		_detail.text="点击图标或右侧地点，\n标记接下来想去的地方。"
		_distance.text="未标记时，跟随当前委托。"
	else:
		_detail.text=str(selected.name)+"\n"+str(selected.get("info",""))
		if selected.region!=str(ui.world_main.world.region):_distance.text="需要先通过区域出口。"
		elif ui.world_main.in_room:_distance.text="走出室内后开始指路。"
		else:
			var distance: float=ui.world_main.player.global_position.distance_to(MapPlaces.world_position(selected))
			_distance.text="直线距离  %d m"%roundi(distance)

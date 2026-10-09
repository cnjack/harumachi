class_name GameMinimap
extends Control
var canvas: WorldMapCanvas
var main: Node
var _title: Label
var _destination: Label
var open_button: Button

func setup(owner_main: Node) -> void:
	main=owner_main;name="Minimap"
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left=28;offset_right=314;offset_top=-403;offset_bottom=-71
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var header:=Panel.new();header.size=Vector2(286,38);header.mouse_filter=Control.MOUSE_FILTER_IGNORE
	header.add_theme_stylebox_override("panel",UITheme.paper("hud",0));add_child(header)
	var map_icon:=UITheme.icon("map",23);map_icon.position=Vector2(13,7);add_child(map_icon)
	_title=UITheme.label("晴町",19);_title.position=Vector2(44,6);add_child(_title)
	var header_button:=Button.new();header_button.text="M";header_button.position=Vector2(246,5);header_button.size=Vector2(28,28)
	header_button.add_theme_font_size_override("font_size",16);header_button.focus_mode=Control.FOCUS_NONE
	UIKitComponents.style_button(header_button,"icon",true)
	header_button.pressed.connect(func():main.ui.open_world_map());add_child(header_button)
	var halo:=ColorRect.new();halo.position=Vector2(11,36);halo.size=Vector2(264,264);halo.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var halo_material:=ShaderMaterial.new();halo_material.shader=load("res://shaders/minimap_halo.gdshader");halo.material=halo_material;add_child(halo)
	var holder:=Control.new();holder.name="MapViewport";holder.position=Vector2(19,44);holder.size=Vector2(248,248)
	holder.clip_contents=true;holder.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(holder)
	canvas=WorldMapCanvas.new();canvas.main=main;canvas.circular=true;canvas.size=holder.size;holder.add_child(canvas)
	var ring:=TextureRect.new();ring.name="PaintedMinimapRim";ring.position=Vector2(7,32);ring.size=Vector2(272,272)
	ring.texture=UIKitAssets.artwork("minimap_ring");ring.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;ring.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(ring)
	open_button=CircularMapButton.new();open_button.name="OpenMap";open_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	open_button.focus_mode=Control.FOCUS_NONE;open_button.tooltip_text="展开地图（M）"
	for state: String in ["normal","hover","pressed"]:open_button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	open_button.mouse_entered.connect(func():canvas.modulate=Color(1.04,1.04,1.02))
	open_button.mouse_exited.connect(func():canvas.modulate=Color.WHITE)
	open_button.pressed.connect(func():main.ui.open_world_map());holder.add_child(open_button)
	var footer:=PanelContainer.new();footer.position=Vector2(0,298);footer.custom_minimum_size=Vector2(286,0)
	footer.add_theme_stylebox_override("panel",UITheme.paper("hud",12));footer.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(footer)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);footer.add_child(row)
	row.add_child(UITheme.icon("quest",21));_destination=UITheme.label("",17);row.add_child(_destination)

func _process(_delta: float) -> void:
	if main==null:return
	visible=not main.in_room and main.ui.modal=="" and not main.story.cutscene
	_title.text="镜波湖水岸" if main.world.region=="farm" and canvas.local_player().x>70 else ("晴川与农园" if main.world.region=="farm" else "晴町街巷")
	var target: Dictionary=MapPlaces.next_target(main)
	if target.is_empty():_destination.text="随处走走，看看晴町。"
	else:
		var distance: float=main.player.global_position.distance_to(MapPlaces.world_position(target))
		_destination.text="%s  ·  %s"%[target.name,"已到附近" if distance<3 else "%d m"%roundi(distance)]

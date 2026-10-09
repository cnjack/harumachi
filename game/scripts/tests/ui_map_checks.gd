extends RefCounted
var t: Node
var main: Node
var ui: Node
func _init(runner: Node) -> void:
	t=runner;main=runner.main;ui=main.ui
func check(name: String,ok: bool,detail: String="") -> void:
	t.check("UI_MAP",name,ok,detail)
func supports(object: Object,property: String) -> bool:
	return object.get_property_list().any(func(p: Dictionary):return p.name==property)
func indicator(canvas: Node) -> Dictionary:
	return canvas.call("navigation_indicator") if canvas.has_method("navigation_indicator") else {}

func run() -> void:
	var snapshot: Dictionary=GameState.to_dict().duplicate(true)
	var old_position: Vector3=main.player.global_position
	var old_region: String=main.world.region
	GameState.new_game();GameState.clock_paused=true
	ui.close_modal();main.in_room=false;main.world.set_region("town")
	main.player.global_position=Vector3(-41,.2,-10)
	await t.frames(5)
	var ids:= ["home","store","bakery","florist","post","hall","farm","fish","tree","exit","quest","book","backpack","calendar","map","coin","w_sunny","w_night","w_cloudy","w_rain","w_festival","level_badge","support_token","compass"]
	var illustrated:=true
	for id: String in ids:
		var icon:=UITheme.icon(id,32)
		illustrated=illustrated and icon.texture is AtlasTexture
		if icon.texture is AtlasTexture:
			var image: Image=icon.texture.get_image()
			illustrated=illustrated and image.get_width()>100 and image.get_height()>100 and image.get_pixel(0,0).a<.1
		icon.free()
	check("24 coherent icons use original transparent illustrated atlas regions",illustrated)
	var modern:=supports(ui,"map_destination")
	var fields: Array=["objective_panel","resource_panel","clock_panel","shortcuts_bar"]
	var widgets: Array[Control]=[]
	for field: String in fields:
		if supports(ui,field) and ui.get(field) is Control:widgets.append(ui.get(field))
	check("quest and resources are separate compact cards",widgets.size()==4 and not widgets[0].get_global_rect().intersects(widgets[1].get_global_rect()))
	check("HUD backgrounds use the generated paper skin",widgets.size()==4 and widgets.all(func(widget: Control):return widget.get_theme_stylebox("panel") is StyleBoxTexture))
	var rim: TextureRect=ui.minimap.get_node_or_null("PaintedMinimapRim") as TextureRect
	var ring_hollow:=false
	if rim and rim.texture:
		var ring_image: Image=rim.texture.get_image()
		ring_hollow=ring_image.get_pixel(ring_image.get_width()/2,ring_image.get_height()/2).a==0
	check("illustrated minimap rim has an actual transparent opening",ring_hollow)
	var shortcuts: Control=ui.get("shortcuts_bar") if supports(ui,"shortcuts_bar") else null
	var commands: Array[Node]=[]
	if shortcuts:commands.assign(shortcuts.find_children("Shortcut_*","Button",true,false))
	check("seven HUD shortcuts have illustrated icons and clickable controls",commands.size()==7 and commands.all(func(button: Node):return (button as Button).icon is AtlasTexture))
	GameState.weather="rain";GameState.minute=610;ui.refresh_clock()
	check("clock separates readable time from date and changes illustrated weather",ui.clock_label.text==GameState.clock_text() and ui.weather_icon.texture is AtlasTexture)
	var canvas: Node=ui.minimap.canvas
	var round_trip:=canvas.has_method("unproject") and canvas.has_method("configure_view")
	if round_trip:
		canvas.call("configure_view")
		for at: Vector2 in [Vector2(-36,-14.9),Vector2(21.8,5.9),Vector2(44.3,-11)]:
			round_trip=round_trip and (canvas.call("unproject",canvas.call("project",at)) as Vector2).distance_to(at)<.001
	check("map projection and inverse preserve world metres",round_trip)
	if modern:ui.set("map_destination",{"id":"home","name":"奶奶的家","icon":"home","region":"town","at":Vector2(21.8,5.9)})
	var offscreen: Dictionary=indicator(canvas)
	var safe:=Rect2(Vector2(21,21),(canvas as Control).size-Vector2(42,42))
	check("offscreen destination remains visible at the inset edge",not offscreen.is_empty() and offscreen.offscreen and safe.has_point(offscreen.at))
	check("offscreen arrow points toward the destination rather than the camera",not offscreen.is_empty() and offscreen.direction.x>.9 and (offscreen.at-(canvas as Control).size*.5).length()>=minf((canvas as Control).size.x,(canvas as Control).size.y)*.5-23)
	check("minimap uses a feathered circular mask and round hit testing",(canvas as Control).material is ShaderMaterial and (canvas as Control).material.shader.resource_path.ends_with("minimap_softmask.gdshader") and supports(ui.minimap,"open_button") and not (ui.minimap.get("open_button") as Control)._has_point(Vector2.ZERO))
	if modern:ui.set("map_destination",{"id":"fish_reeds","name":"芦苇东岸","icon":"fish","region":"farm","at":Vector2(136.8,17)})
	var outward: Dictionary=indicator(canvas)
	check("a farm destination first guides town players to the real east exit",not outward.is_empty() and outward.target.id=="farm_exit" and (outward.target.at as Vector2).distance_to(Vector2(44.3,-11))<.001)
	main.world.set_region("farm");main.player.global_position=FarmBuilder.ORIGIN+Vector3(94,.2,40);await t.frames(5)
	if modern:ui.set("map_destination",{"id":"home","name":"奶奶的家","icon":"home","region":"town","at":Vector2(21.8,5.9)})
	var inward: Dictionary=indicator(canvas)
	check("a town destination guides lake players to the local west exit",not inward.is_empty() and inward.target.id=="town_exit" and inward.direction.x<-.8)
	ui.open_world_map();await t.frames(6)
	var framed_modal: Control=ui.modal_layer.get_child(0) as Control
	check("popup outer frame uses generated nine-slice artwork",framed_modal.get_theme_stylebox("panel") is StyleBoxTexture)
	var panel: Node=ui.get("map_panel") if supports(ui,"map_panel") else null
	check("full map opens on the player's current region with an active tab",panel!=null and (panel.find_child("Region_farm",true,false) as Button).button_pressed)
	if panel:
		var place_button:=panel.find_child("Place_fish_reeds",true,false) as Button
		place_button.pressed.emit()
	check("landmark selection creates the same real-coordinate marker",modern and (ui.get("map_destination") as Dictionary).get("id")=="fish_reeds")
	ui.close_modal();await t.frames(3)
	check("closing the map keeps the selected destination and restores input",modern and (ui.get("map_destination") as Dictionary).get("id")=="fish_reeds" and not GameState.input_locked())
	main.world.set_region("town");ui.open_world_map();await t.frames(6)
	var town_canvas: WorldMapCanvas=ui.get("map_panel").canvas
	var label_rects: Array[Rect2]=town_canvas._labels
	var labels_clear: bool=true
	for first_label: int in label_rects.size():
		for second_label: int in range(first_label+1,label_rects.size()):
			if label_rects[first_label].grow(2).intersects(label_rects[second_label]):labels_clear=false
	check("town map labels do not overlap each other in the actual rendered layout",label_rects.size()>10 and labels_clear)
	check("relocated town labels stay inside the actual map canvas",label_rects.all(func(rect:Rect2):return Rect2(Vector2.ZERO,town_canvas.size).encloses(rect)))
	ui.close_modal();await t.frames(3)
	ui.open_world_map();await t.frames(4)
	panel=ui.get("map_panel") if supports(ui,"map_panel") else null
	if panel:(panel.find_child("ClearDestination",true,false) as Button).pressed.emit()
	check("clear removes the manual marker and returns to quest guidance",modern and (ui.get("map_destination") as Dictionary).is_empty())
	ui.close_modal();await t.frames(3)
	GameState.lock_input("ui_map_regression")
	if shortcuts:(shortcuts.find_child("Shortcut_map",true,false) as Button).pressed.emit()
	check("HUD clicks respect story input locks",shortcuts!=null and ui.modal=="")
	GameState.unlock_input("ui_map_regression")
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1600,1000),Vector2i(1920,1080)]:
		main.get_window().size=resolution;await t.frames(4)
		var screen:=Rect2(Vector2.ZERO,ui.root.size).grow(1)
		var on_screen:=widgets.size()==4 and widgets.all(func(widget: Control):return screen.encloses(widget.get_global_rect()))
		on_screen=on_screen and screen.encloses((ui.minimap as Control).get_global_rect())
		check("HUD and minimap fit %dx%d"%[resolution.x,resolution.y],on_screen)
		ui.open_world_map();await t.frames(5)
		var modal_panel:=ui.modal_layer.get_child(0) as Control
		check("full map and landmark list fit %dx%d"%[resolution.x,resolution.y],screen.encloses(modal_panel.get_global_rect()))
		ui.close_modal();await t.frames(3)
	main.get_window().size=Vector2i(1920,1080)
	if modern:ui.set("map_destination",{})
	GameState.from_dict(snapshot);main.world.set_region(old_region);main.player.global_position=old_position

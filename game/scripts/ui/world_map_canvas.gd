class_name WorldMapCanvas
extends Control
## North-up cartography driven by real world coordinates and actual roof bounds.
signal place_selected(place: Dictionary)
var main: Node
var full := false
var circular := false
var region_override := ""
var _clock := 0.0
var _bounds := Rect2()
var _scale := 1.0
var _centre := Vector2.ZERO
var _font: Font
var _labels: Array[Rect2]=[]
var _roofs: Array[Rect2]=[]
const LAND := Color(.83,.88,.71)
const WATER := Color(.46,.71,.77)
const PATH := Color(.97,.90,.72)

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP if full else Control.MOUSE_FILTER_IGNORE
	_font=load("res://assets/fonts/LXGWWenKai-Medium.ttf")
	if circular:
		var mask:=ShaderMaterial.new();mask.shader=load("res://shaders/minimap_softmask.gdshader")
		mask.set_shader_parameter("surface_size",size);material=mask
	for child: Node in main.world.get_children():
		if child is Node3D and str(child.get_meta("model_id", "")) in ["S01","S02","S03","S05","S08","S06","H01","H02","H03","M01_timber_machiya","M03_gable_house","M05_residential"]:
			var house:=child as Node3D
			var box: AABB=house.global_transform*WorldBuilder.local_aabb(house)
			_roofs.append(Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)))

func _process(delta: float) -> void:
	_clock+=delta
	if _clock>.10:
		_clock=0.0;queue_redraw()

func map_region() -> String:
	return region_override if region_override!="" else str(main.world.region)

func local_player() -> Vector2:
	var p: Vector3=main.player.global_position
	if str(main.world.region)=="farm":p-=FarmBuilder.ORIGIN
	return Vector2(p.x,p.z)

func configure_view() -> void:
	_bounds=LakesideLayout.BOUNDS.grow(4.0) if map_region()=="farm" else LakesideLayout.TOWN_BOUNDS.grow(7.0)
	_centre=_bounds.get_center() if full else local_player()
	_scale=minf((size.x-68)/_bounds.size.x,(size.y-52)/_bounds.size.y) if full else size.x/72.0

func project(p: Vector2) -> Vector2:
	return (p-_centre)*_scale+size*.5

func unproject(p: Vector2) -> Vector2:
	return (p-size*.5)/_scale+_centre

func navigation_indicator() -> Dictionary:
	configure_view()
	var target: Dictionary=MapPlaces.navigation_target(main) if full else MapPlaces.next_target(main)
	if target.is_empty() or target.region!=map_region():return {}
	var pixel:=project(target.at)
	var safe:=Rect2(Vector2(22,22),size-Vector2(44,44))
	var offscreen: bool=pixel.distance_to(size*.5)>minf(size.x,size.y)*.5-22 if circular else not safe.has_point(pixel)
	var direction: Vector2=(pixel-size*.5).normalized()
	if offscreen:
		var delta: Vector2=pixel-size*.5
		if circular:pixel=size*.5+direction*(minf(size.x,size.y)*.5-22)
		else:
			var half: Vector2=safe.size*.5
			var ratio:=minf(half.x/maxf(absf(delta.x),.001),half.y/maxf(absf(delta.y),.001))
			pixel=size*.5+delta*ratio
	return {"at":pixel,"offscreen":offscreen,"direction":direction,"target":target}

func _poly(points: PackedVector2Array,colour: Color) -> void:
	var transformed:=PackedVector2Array()
	for p in points:transformed.append(project(p))
	draw_colored_polygon(transformed,colour)

func _path(points: PackedVector2Array,width: float,colour: Color) -> void:
	var transformed:=PackedVector2Array()
	for p in points:transformed.append(project(p))
	draw_polyline(transformed,colour,maxf(width*_scale,2.0),true)

func _icon(at: Vector2,id: String,diameter: float) -> void:
	var texture: Texture2D=UITheme.icon_texture(id)
	if texture:
		var ratio: float=texture.get_width()/float(texture.get_height())
		var extent:=Vector2(diameter,diameter/ratio) if ratio>=1 else Vector2(diameter*ratio,diameter)
		draw_texture_rect(texture,Rect2(at-extent*.5,extent),false)

func _label(at: Vector2,text: String,font_size: int=17) -> void:
	var extent: Vector2=_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var rect: Rect2=_label_position(at,extent+Vector2(10,5))
	_labels.append(rect)
	var anchor: Vector2=Vector2(clampf(at.x,rect.position.x,rect.end.x),clampf(at.y,rect.position.y,rect.end.y))
	if anchor.distance_to(at)>30:draw_line(at,anchor,Color(.35,.43,.29,.65),1.0,true)
	draw_style_box(UITheme.box(Color(.99,.97,.88,.87),Color.TRANSPARENT,0,4,0,false),rect)
	draw_string(_font,rect.position+Vector2(5,extent.y*.80),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,UITheme.INK)

func _label_position(at: Vector2,extent: Vector2) -> Rect2:
	var initial: Vector2=at+Vector2(-extent.x*.5,18)
	for row: int in range(12):
		var distance: float=18+row*(extent.y+6)
		for offset: Vector2 in [Vector2(-extent.x*.5,distance),Vector2(-extent.x*.5,-distance-extent.y),Vector2(22+row*24,-extent.y*.5),Vector2(-22-row*24-extent.x,-extent.y*.5)]:
			var candidate:=Rect2(at+offset,extent)
			candidate.position.x=clampf(candidate.position.x,6,maxf(6,size.x-extent.x-6))
			candidate.position.y=clampf(candidate.position.y,5,maxf(5,size.y-extent.y-5))
			var clear: bool=true
			for previous: Rect2 in _labels:
				if candidate.grow(3).intersects(previous):clear=false;break
			if clear:return candidate
	return Rect2(initial,extent)

func _water(points: PackedVector2Array) -> void:
	_poly(points,WATER)
	var edge:=PackedVector2Array()
	for p in points:edge.append(project(p))
	if not edge.is_empty():edge.append(edge[0]);draw_polyline(edge,Color(.70,.86,.83),2,true)

func _draw() -> void:
	if main==null or main.player==null:return
	configure_view();_labels.clear()
	var farm:=map_region()=="farm"
	draw_rect(Rect2(Vector2.ZERO,size),LAND)
	for at: Vector2 in [Vector2(-28,2),Vector2(-3,3),Vector2(12,21),Vector2(37,-22),Vector2(76,-28),Vector2(130,47)]:
		draw_circle(project(at),8*_scale,Color(.75,.83,.62))
	if farm:
		_water(LakesideLayout.river_outline());_water(LakesideLayout.lake_outline())
		for route: PackedVector2Array in LakesideLayout.walk_paths():
			_path(route,3.4,Color(.74,.72,.52));_path(route,2.6,PATH)
		_path(PackedVector2Array([Vector2(-30,.3),Vector2(20,.3)]),3.1,PATH)
		_path(PackedVector2Array([Vector2(0,.3),Vector2(0,25.4),Vector2(10,25.4)]),2.8,PATH)
		_path(PackedVector2Array([Vector2(-3,15),Vector2(3,15)]),2.4,Color(.62,.44,.29))
		_path(PackedVector2Array([Vector2(94,46),Vector2(94,36)]),2.1,Color(.62,.44,.29))
		for row in 3:
			for column in 5:
				var plot:=Rect2(project(Vector2(-6+column*2.5,-10+row*2.4)),Vector2(1.8,1.6)*_scale)
				draw_rect(plot,Color(.66,.49,.30));draw_line(plot.position,plot.end,Color(.79,.68,.42),1)
		if full:
			_label(project(Vector2(101,16)),"镜波湖",26)
			_label(project(Vector2(30,30)),"晴川",21)
	else:
		_path(PackedVector2Array([Vector2(-52,-11),Vector2(46,-11)]),8.2,Color(.72,.75,.62))
		_path(PackedVector2Array([Vector2(-52,-11),Vector2(46,-11)]),7.0,PATH)
		_path(PackedVector2Array([Vector2(19.7,-11),Vector2(19.7,85)]),5.8,PATH)
		_path(PackedVector2Array([Vector2(-3,-11),Vector2(-3,2),Vector2(4,7),Vector2(4,14)]),2.8,PATH)
		for lane_z in [51.2,68.2]:_path(PackedVector2Array([Vector2(-1,lane_z),Vector2(39,lane_z)]),2.5,PATH)
		if full:_label(project(Vector2(19.7,57)),"南町住宅街",22)
		for roof: Rect2 in _roofs:
			var box:=Rect2(project(roof.position),roof.size*_scale)
			draw_style_box(UITheme.box(Color(.69,.70,.62),Color(.49,.58,.51),1,3,0,false),box)
			draw_line(box.position+Vector2(1,box.size.y*.5),box.position+Vector2(box.size.x-1,box.size.y*.5),Color(.88,.88,.74),1)
	var viewport:=Rect2(Vector2(-24,-24),size+Vector2(48,48))
	for place: Dictionary in MapPlaces.places(map_region()):
		var at:=project(place.at)
		if not viewport.has_point(at):continue
		draw_circle(at,17 if full else 13,Color(.99,.97,.88,.90))
		_icon(at,place.icon,34 if full else 25)
		if full:_label(at,place.name,16)
	if str(main.world.region)==map_region() and not main.in_room:
		var player_at:=project(local_player())
		var yaw: float=main.player._face_yaw
		var facing:=Vector2(sin(yaw),cos(yaw))
		var side:=Vector2(-facing.y,facing.x)
		draw_circle(player_at,10,UITheme.PAPER)
		draw_colored_polygon(PackedVector2Array([player_at+facing*12,player_at-facing*8+side*6,player_at-facing*8-side*6]),Color(.86,.38,.26))
	var indicator: Dictionary=navigation_indicator()
	if not indicator.is_empty():
		var pin_at: Vector2=indicator.at
		draw_arc(pin_at,15,0,TAU,32,Color(.80,.54,.20),2,true)
		if indicator.offscreen:
			var forward: Vector2=indicator.direction
			var right:=Vector2(-forward.y,forward.x)
			draw_colored_polygon(PackedVector2Array([pin_at+forward*8,pin_at-forward*5+right*5,pin_at-forward*5-right*5]),Color(.80,.54,.20))
		else:_icon(pin_at,"quest",22)
	if circular:draw_string(_font,Vector2(size.x*.5-7,33),"北",HORIZONTAL_ALIGNMENT_LEFT,-1,14,UITheme.INK)
	else:
		_icon(Vector2(size.x-21,21),"compass",26)
		draw_string(_font,Vector2(size.x-27,47),"北",HORIZONTAL_ALIGNMENT_LEFT,-1,14,UITheme.INK)

func _gui_input(event: InputEvent) -> void:
	if not full:return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		configure_view()
		var nearest: Dictionary={}
		var distance:=26.0
		for place: Dictionary in MapPlaces.places(map_region()):
			var candidate: float=project(place.at).distance_to(event.position)
			if candidate<distance:nearest=place;distance=candidate
		if not nearest.is_empty():place_selected.emit(nearest);accept_event()

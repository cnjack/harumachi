class_name ResidentInteriorBuilder
extends RefCounted
## Eleven rooms with actual openings, distinct circulation and supported reusable props.

static func build(room: InteriorBuilder) -> void:
	room.spec.furniture.clear()
	var root:=Node3D.new();root.name="ResidentInterior";room.add_child(root)
	var size: Vector2=room.spec.size
	var wall:=room.wb.house.wall_mat("plaster").duplicate() as ShaderMaterial
	var palette: Array=_wall_palette(room.kind)
	wall.set_shader_parameter("tint",palette[0]);wall.set_shader_parameter("cornice_y",2.48)
	wall.set_shader_parameter("wain_tint",palette[1]);wall.set_shader_parameter("wainscot_h",.58 if room.kind in ["home_mio","photo_room","florist","post"] else .86)
	_outer(room,wall)
	var zones: Array=_zones(room.kind,size)
	for zone: Array in zones:_floor(room,str(zone[0]),zone[1],zone[2])
	room._collider(Vector3(size.x+.6,.30,size.y+2.2),Vector3(0,-.15,.7),WorldBuilder.L_GROUND).name="ResidentGround"
	match room.kind:
		"home_haru":_haru(room,root,wall)
		"home_mio":_mio(room,root,wall)
		"home_tanaka":_tanaka(room,root,wall)
		"home_ren":_ren(room,root,wall)
		"home_kazuko":_kazuko(room,root,wall)
		"toolshed":_toolshed(room,root,wall)
		"photo_room":_photos(room,root,wall)
		"florist":_florist(room,root,wall)
		"zakka":_zakka(room,root,wall)
		"post":_post(room,root,wall)
		"library":_library(room,root,wall)
	_functional_fitout(room,root,wall)
	var states:=Node3D.new();states.name="StoryState";room.add_child(states)
	for key: String in _state_keys(room.kind):
		var marker: Node3D=Sprite3D.new() if key=="ActualPhoto" else Node3D.new();marker.name=key;marker.position=_state_at(room.kind,key)
		marker.set_meta("story_state_key",key);states.add_child(marker)
		_story_object(room,marker,key)
	for who: String in room.spec.seats:
		var seat: Dictionary=room.spec.seats[who];var spot: Vector3=seat.at
		var support:=_table(room,root,"VisitSeat_"+who,Vector3(spot.x,0,spot.z),Vector2(.68,.58),.31)
		support.set_meta("seat_owner",who);support.set_meta("seat_surface",.31)
	for pt: Array in room.spec.points:
		var point:=Interactable.new();point.id=str(pt[0]);point.name=point.id;point.radius=float(pt[4])
		point.position=Vector3(float(pt[1]),float(pt[2]),float(pt[3]));room.add_child(point)
	for lamp_at: Vector3 in room.spec.lamps:room._lamp(lamp_at)
	ClearSignage.paper_tag(root,"RoomName",str(room.spec.name),Vector3(size.x*.5-.10,1.9,size.y*.5-.7),Vector2(1.2,.22),-PI*.5,.09)
	# A visitor sees a single resident instance supplied by Main, never a duplicate model.
	room.set_meta("resident_owners",room.spec.owners);room.set_meta("interior_layout",room.kind)
	sync_state(room)

static func sync_state(room: Node3D) -> void:
	var packing: Node3D=room.get_node_or_null("StoryState/packing")
	if packing:
		var presentation: String=str(packing.get_meta("presentation","paper"))
		packing.get_node("Paper").visible=presentation!="share"
		packing.get_node("Share").visible=presentation=="share"
	var bouquet: Node3D=room.get_node_or_null("StoryState/flowergift")
	if bouquet:
		var selected: String=str(bouquet.get_meta("flower_choice","blue"))
		bouquet.get_node("Blue").visible=selected!="white"
		bouquet.get_node("White").visible=selected=="white"

static func _story_object(room: InteriorBuilder,marker: Node3D,key: String) -> void:
	var paper:=PublicPlaceArt.matte(Color(.98,.95,.83))
	if key=="ActualPhoto":
		var photo:=marker as Sprite3D;photo.pixel_size=.0004;photo.rotation.x=-PI*.5;photo.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR
		photo.shaded=true;photo.set_meta("photo_source","actual_gameplay_png");return
	if key in ["Blueprint","maptrace","replyletter","oldtags"]:
		var image:=MeshInstance3D.new();image.name="StoryPaper";var quad:=QuadMesh.new();quad.size=Vector2(.58,.39);image.mesh=quad;image.rotation.x=-PI*.5
		var drawn:=PublicPlaceArt.matte(Color.WHITE)
		if key in ["Blueprint","maptrace"]:drawn.albedo_texture=load("res://assets/ui/collection/"+("col_blueprint" if key=="Blueprint" else "col_oldmap")+".jpg")
		else:drawn.albedo_color=Color(.96,.92,.73)
		image.material_override=drawn;marker.add_child(image)
		if key=="oldtags":
			for index: int in 3:
				var tag:=Node3D.new();tag.name="SavedTag_%d"%index;tag.position=Vector3(-.18+index*.18,.006,.02);tag.rotation.x=-PI*.5;marker.add_child(tag)
				ClearSignage.paper_tag(tag,"Price",["小豆\n一合","麦茶\n量り売り","貸出\n返却済"][index],Vector3.ZERO,Vector2(.15,.22),0,.035)
		if key=="maptrace":
			for index: int in 4:PublicPlaceArt.box(marker,"TracedRoad_%d"%index,Vector3(.09,.004,.012),Vector3(-.19+index*.12,.004,.06 if index<2 else -.02),PublicPlaceArt.matte(Color(.72,.30,.22)))
		return
	if key=="newdrawing":
		marker.position.z+=.37
		PublicPlaceArt.box(marker,"ChildPaper",Vector3(.40,.008,.28),Vector3.ZERO,paper)
		PublicPlaceArt.box(marker,"DrawnStage",Vector3(.23,.004,.05),Vector3(0,.008,.05),PublicPlaceArt.matte(Color(.74,.35,.28)))
		for index: int in 3:PublicPlaceArt.box(marker,"ChildMark_%d"%index,Vector3(.025,.004,.10),Vector3(-.08+index*.08,.008,-.03),PublicPlaceArt.matte(Color(.25,.51,.61)))
		return
	if key=="packing":
		for presentation: String in ["Paper","Share"]:
			var group:=Node3D.new();group.name=presentation;marker.add_child(group)
			var width: float=.28 if presentation=="Paper" else .46
			PublicPlaceArt.box(group,"FoodBase",Vector3(width,.025,.24),Vector3(0,.0125,0),paper if presentation=="Paper" else PublicPlaceArt.wood())
			for portion: int in (1 if presentation=="Paper" else 2):PublicPlaceArt.box(group,"BreadPortion_%d"%portion,Vector3(.15,.055,.14),Vector3((portion-.5)*.18 if presentation=="Share" else 0,.052,0),PublicPlaceArt.matte(Color(.92,.69,.35)))
		return
	if key=="flowergift":
		for choice: String in ["Blue","White"]:
			var flowers:=Node3D.new();flowers.name=choice;marker.add_child(flowers)
			PublicPlaceArt.cylinder(flowers,"Vase",Vector3(0,.085,0),.075,.17,PublicPlaceArt.matte(Color(.76,.64,.48)))
			for stem: int in 3:
				var x: float=(stem-1)*.045
				PublicPlaceArt.cylinder(flowers,"Stem_%d"%stem,Vector3(x,.23,0),.008,.27,PublicPlaceArt.matte(Color(.31,.48,.28)))
				PublicPlaceArt.box(flowers,"Bloom_%d"%stem,Vector3(.085,.065,.085),Vector3(x,.37+float(stem%2)*.035,0),PublicPlaceArt.matte(Color(.44,.60,.89) if choice=="Blue" else Color(.98,.97,.88)))
		return
	if key=="seedpack":
		var packet: Node3D=room.wb.spawn("W28_seed_packets",Vector3.ZERO,0,0,marker,1.5)
		HouseBuilder.toonify(packet);WorldBuilder.rest_on(packet,0.0);return
	if key=="travelbag":
		PublicPlaceArt.box(marker,"TravelBag",Vector3(.37,.23,.24),Vector3(0,.115,0),PublicPlaceArt.canvas(Color(.37,.46,.52)))
		PublicPlaceArt.box(marker,"Handle",Vector3(.14,.05,.025),Vector3(0,.25,0),PublicPlaceArt.wood());return
	PublicPlaceArt.box(marker,"RepairedWoodPart",Vector3(.35,.035,.045),Vector3(0,.0175,0),PublicPlaceArt.wood())
	PublicPlaceArt.box(marker,"NewBinding",Vector3(.045,.040,.055),Vector3(.10,.02,0),paper)

static func _wall_palette(id: String) -> Array:
	var colours: Dictionary={"home_mio":[Color(.83,.91,.96),Color(.53,.61,.63)],"home_tanaka":[Color(.89,.91,.80),Color(.55,.56,.40)],"home_ren":[Color(.99,.91,.79),Color(.70,.47,.37)],"home_kazuko":[Color(.97,.87,.85),Color(.67,.48,.44)],"photo_room":[Color(.85,.92,.94),Color(.52,.58,.60)],"florist":[Color(.88,.96,.85),Color(.54,.66,.48)],"zakka":[Color(.97,.91,.74),Color(.67,.55,.38)],"post":[Color(.88,.96,.91),Color(.43,.61,.55)],"library":[Color(.91,.95,.83),Color(.58,.64,.46)]}
	return colours.get(id,[Color(.96,.96,.88),Color(.66,.56,.44)])

static func _outer(room: InteriorBuilder,wall: Material) -> void:
	var w: float=room.spec.size.x;var d: float=room.spec.size.y
	for side: float in [-1.0,1.0]:
		if room.kind=="home_mio" and side<0:
			# Reading / invitation desk receives a real west opening, above its worktop.
			room._wall(Vector3(.14,2.55,d*.5-1.25),Vector3(-w*.5-.07,1.275,(-d*.5-1.25)*.5),wall)
			room._wall(Vector3(.14,2.55,d*.5-.55),Vector3(-w*.5-.07,1.275,(.55+d*.5)*.5),wall)
			room._wall(Vector3(.14,1.0,1.8),Vector3(-w*.5-.07,.50,-.35),wall)
			room._wall(Vector3(.14,.30,1.8),Vector3(-w*.5-.07,2.40,-.35),wall)
			PublicPlaceArt._window(room,-1.0,-.35,1.8,11,1.0,2.25)
		elif room.kind=="home_haru" and side>0:
			room._wall(Vector3(.14,2.55,d*.5+1.55),Vector3(w*.5+.07,1.275,(-d*.5+1.55)*.5),wall)
			room._wall(Vector3(.14,2.55,d*.5-3.25),Vector3(w*.5+.07,1.275,(3.25+d*.5)*.5),wall)
			room._wall(Vector3(.14,.85,1.70),Vector3(w*.5+.07,.425,2.40),wall)
			room._wall(Vector3(.14,.30,1.70),Vector3(w*.5+.07,2.40,2.40),wall)
			PublicPlaceArt._window(room,1.0,2.40,1.70,10,.85,2.25)
		else:room._wall(Vector3(.14,2.55,d),Vector3(side*(w*.5+.07),1.275,0),wall)
	# A true north window aperture, not a card pasted onto an unbroken wall.
	var wx: float=-w*.19;var width:=1.65;var left: float=wx-width*.5+w*.5;var right: float=w*.5-wx-width*.5
	room._wall(Vector3(left,2.55,.14),Vector3(-w*.5+left*.5,1.275,-d*.5-.07),wall)
	room._wall(Vector3(right,2.55,.14),Vector3(wx+width*.5+right*.5,1.275,-d*.5-.07),wall)
	room._wall(Vector3(width,1.15,.14),Vector3(wx,.575,-d*.5-.07),wall)
	room._wall(Vector3(width,.30,.14),Vector3(wx,2.40,-d*.5-.07),wall)
	var timber:=PublicPlaceArt.wood(Color(.54,.40,.27))
	for x: float in [wx-width*.5,wx+width*.5]:PublicPlaceArt.box(room,"WindowJamb_%d"%int(x*100),Vector3(.055,1.2,.18),Vector3(x,1.7,-d*.5+.015),timber)
	for y: float in [1.15,2.25]:PublicPlaceArt.box(room,"WindowRail_%d"%int(y*100),Vector3(width+.12,.055,.18),Vector3(wx,y,-d*.5+.015),timber)
	for bar: int in 3:PublicPlaceArt.box(room,"WindowLattice_%d"%bar,Vector3(.025,1.1,.05),Vector3(wx-width*.5+float(bar+1)*width*.25,1.7,-d*.5+.075),timber)
	var view:=MeshInstance3D.new();view.name="SummerView";var quad:=QuadMesh.new();quad.size=Vector2(width,1.1);view.mesh=quad
	view.position=Vector3(wx,1.7,-d*.5-.16);view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var painted:=ShaderMaterial.new();painted.shader=load("res://shaders/public_window_view.gdshader");painted.set_shader_parameter("view_tex",load(PublicPlaceArt.TEX+"summer_window_view.png"));view.material_override=painted;room.add_child(view)
	for side: float in [-1.0,1.0]:
		var width_front: float=w*.5-.85
		room._wall(Vector3(width_front,.60,.14),Vector3(side*(.85+width_front*.5),.30,d*.5+.07),wall)
		PublicPlaceArt.box(room,"EntryPost_%d"%int(side),Vector3(.075,2.2,.14),Vector3(side*.85,1.1,d*.5),timber)
	var roof:=PublicPlaceArt.box(room,"ShadowRoof",Vector3(w+.4,.08,d+.4),Vector3(0,2.64,0),wall)
	roof.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

static func _zones(id: String,size: Vector2) -> Array:
	var w: float=size.x*.5;var d: float=size.y*.5
	if id=="home_haru":return [["living",[-w,-d,1.2,1.0],Color(.90,.89,.74)],["kitchen",[1.2,-d,w,1.0],Color(.88,.88,.80)],["drawing",[-w,1,-1,d],Color(.81,.71,.54)],["hall",[-1,1,1,d],Color(.74,.72,.63)],["utility",[1,1,3.4,d],Color(.76,.65,.49)],["engawa",[3.4,1,w,d],Color(.85,.72,.53)]]
	if id in ["toolshed","florist"]:return [["dry",[-w,-d,w,-.7],Color(.72,.64,.48)],["wet",[-w,-.7,w,d],Color(.72,.77,.75)]]
	if id=="post":return [["sorting",[-w,-d,w,-1.1],Color(.73,.66,.54)],["public",[-w,-1.1,w,d],Color(.88,.89,.82)]]
	if id=="home_tanaka":return [["living",[-w,-d,w,1.5],Color(.73,.68,.54)],["boots",[-w,1.5,w,d],Color(.72,.76,.73)]]
	return [["main",[-w,-d,w,d],Color(.88,.80,.65)]]

static func _floor(room: InteriorBuilder,label: String,rect: Array,tint: Color) -> void:
	if label in ["wet","boots"]:
		var stone:=MeshInstance3D.new();stone.name="Floor_"+label;var plane:=PlaneMesh.new()
		plane.size=Vector2(float(rect[2])-float(rect[0]),float(rect[3])-float(rect[1]));stone.mesh=plane;stone.material_override=PublicPlaceArt.matte(Color(.69,.72,.66))
		stone.position=Vector3((float(rect[0])+float(rect[2]))*.5,.002,(float(rect[1])+float(rect[3]))*.5);stone.set_meta("floor_zone",label);room.add_child(stone);return
	if room.kind=="home_haru" and label=="living":
		var painted:=room.wb.house.floor_mat("tatami" if label=="living" else "genkan",rect)
		painted.set_shader_parameter("house_origin",room.origin)
		var panel:=MeshInstance3D.new();panel.name="Floor_"+label;var tatami_plane:=PlaneMesh.new()
		tatami_plane.size=Vector2(float(rect[2])-float(rect[0]),float(rect[3])-float(rect[1]));panel.mesh=tatami_plane;panel.material_override=painted
		panel.position=Vector3((float(rect[0])+float(rect[2]))*.5,.002,(float(rect[1])+float(rect[3]))*.5);panel.set_meta("floor_zone",label);room.add_child(panel)
		return
	var mat:=ShaderMaterial.new();mat.shader=load("res://shaders/public_planks.gdshader")
	mat.set_shader_parameter("grain_tex",load(PublicPlaceArt.TEX+"quiet_pine_grain.png"));mat.set_shader_parameter("room_origin",room.origin);mat.set_shader_parameter("tint",tint)
	mat.set_shader_parameter("board_width",.27);mat.set_shader_parameter("board_length",1.6);mat.set_shader_parameter("along_x",label in ["living","main"])
	var surface:=MeshInstance3D.new();surface.name="Floor_"+label;var quad:=PlaneMesh.new()
	quad.size=Vector2(float(rect[2])-float(rect[0]),float(rect[3])-float(rect[1]));surface.mesh=quad;surface.material_override=mat
	surface.position=Vector3((float(rect[0])+float(rect[2]))*.5,.002,(float(rect[1])+float(rect[3]))*.5);surface.set_meta("floor_zone",label);room.add_child(surface)

static func _partition(room: InteriorBuilder,at: Vector3,length: float,door: float,along_x: bool,wall: Material) -> void:
	# Low cutaway partition preserves the fixed camera; a 1.3m real opening remains.
	for endpoints: Vector2 in [Vector2(-length*.5,door-.65),Vector2(door+.65,length*.5)]:
		var span: float=endpoints.y-endpoints.x
		if span<=0:continue
		var mid: float=(endpoints.x+endpoints.y)*.5
		room._wall(Vector3(span,1.05,.10) if along_x else Vector3(.10,1.05,span),at+Vector3(mid,.525,0) if along_x else at+Vector3(0,.525,mid),wall)
	for edge: float in [door-.65,door+.65]:PublicPlaceArt.box(room,"PartitionPost_%d"%room.get_child_count(),Vector3(.055,1.95,.055),at+(Vector3(edge,.975,0) if along_x else Vector3(0,.975,edge)),PublicPlaceArt.wood())

static func _model(room: InteriorBuilder,parent: Node3D,id: String,at: Vector3,yaw: float=0.0,scale_value: float=1.0,solid: bool=true) -> Node3D:
	var node: Node3D=room.wb.spawn(id,at,yaw,0,parent,scale_value)
	if node==null:return null
	node.name=id+"_%d"%room.pieces.size();HouseBuilder.toonify(node);WorldBuilder.rest_on(node,at.y)
	if solid:
		room.wb.add_box_collider(node,.85,WorldBuilder.L_SOLID)
		for body: StaticBody3D in node.find_children("*","StaticBody3D",true,false):body.set_meta("model_part",true)
	room.pieces.append(node)
	room.spec.furniture.append([id,at.x,at.z,yaw,scale_value,solid])
	return node

static func _table(room: InteriorBuilder,parent: Node3D,label: String,at: Vector3,size: Vector2,height: float=.76) -> MeshInstance3D:
	return PublicPlaceArt.bench(parent,label,at,size.x,size.y,height)
static func _prop(room: InteriorBuilder,parent: Node3D,id: String,at: Vector3,height: float,support: Node3D) -> Node3D:
	return PublicPlaceArt.prop(room,parent,id,at,height,support)
static func _paper(parent: Node3D,label: String,at: Vector3,size: Vector2,support: Node3D) -> void:
	var sheet:=PublicPlaceArt.box(parent,label,Vector3(size.x,.008,size.y),at+Vector3(0,.004,0),PublicPlaceArt.matte(Color(.97,.94,.81)))
	PublicPlaceArt.supported(sheet,support)
static func _state_keys(id: String) -> Array[String]:
	var keys: Dictionary={"home_haru":["Blueprint","newdrawing","flowergift"],"toolshed":["repairedtool","seedpack"],"home_tanaka":["seedpack","repairedtool"],"home_mio":["travelbag"],"home_ren":["packing"],"home_kazuko":["oldtags"],"florist":["flowergift"],"zakka":["repairedpart"],"post":["replyletter"],"library":["maptrace"],"photo_room":["ActualPhoto"]}
	var result: Array[String]=[];result.assign(keys.get(id,[]));return result
static func _state_at(id: String,key: String) -> Vector3:
	var anchors: Dictionary={"home_haru":Vector3(-2.3,.45,-.45),"toolshed":Vector3(-2.3,.72,0),"home_tanaka":Vector3(-2.6,.70,-.2),"home_mio":Vector3(-2.1,.74,-.1),"home_ren":Vector3(-2.3,.76,-.05),"home_kazuko":Vector3(-2.2,.45,-.1),"florist":Vector3(-2.6,.80,-.3),"zakka":Vector3(-2.25,.80,-.8),"post":Vector3(-3.3,.76,-.25),"library":Vector3(-2.5,.76,-1.0),"photo_room":Vector3(-1.9,.76,-1.1)}
	if id=="toolshed" and key=="seedpack":return Vector3(2.55,1.10,-1.55)
	if id=="home_haru" and key=="flowergift":return Vector3(4.2,.20,-3.2)
	return anchors.get(id,Vector3(-2.3,.8,-1.5))
static func _picture(parent: Node3D,label: String,at: Vector3,size: Vector2,asset: String,yaw: float=0.0) -> void:
	var frame:=Node3D.new();frame.name=label;frame.position=at;frame.rotation.y=yaw;parent.add_child(frame)
	PublicPlaceArt.box(frame,"Backing",Vector3(size.x+.07,size.y+.07,.04),Vector3.ZERO,PublicPlaceArt.wood())
	var painting:=MeshInstance3D.new();painting.name="ExistingStoryPicture";var quad:=QuadMesh.new();quad.size=size;painting.mesh=quad;painting.position.z=.022
	var ink:=PublicPlaceArt.matte(Color.WHITE);ink.albedo_texture=load("res://assets/ui/collection/"+asset+".jpg");painting.material_override=ink;frame.add_child(painting)

static func _haru(room: InteriorBuilder,root: Node3D,wall: Material) -> void:
	_partition(room,Vector3(1.2,0,-1.5),5.0,.6,false,wall)
	_partition(room,Vector3(0,0,1.1),10.0,0,true,wall)
	_model(room,root,"I01_bed",Vector3(-4.05,0,-2.7),0,.80)
	_model(room,root,"I01_bed",Vector3(-2.8,0,-2.7),0,.65)
	_model(room,root,"J01_kitchen_counter",Vector3(4.48,0,-2),-90,.82)
	_model(room,root,"G01_getabako",Vector3(1.65,0,3.40),-90,.72)
	var drawing:=_table(room,root,"AoiDrawingDesk",Vector3(-3.25,0,2.05),Vector2(1.75,.76),.39)
	_paper(root,"AoiEverydaySketch",Vector3(-3.25,.39,2.05),Vector2(.46,.31),drawing)
	_prop(room,root,"W21_tea_tin",Vector3(-3.82,.39,2.05),.16,drawing)
	_model(room,root,"G06_zabuton",Vector3(-3.25,0,2.95),0,.75,false)
	_model(room,root,"G07_hall_cabinet",Vector3(-4.55,0,3.40),90,.65)
	_table(room,root,"EngawaWindowSeat",Vector3(4.40,0,2.35),Vector2(.70,1.65),.42)
	_model(room,root,"J05_dish_cabinet",Vector3(2.65,0,3.45),0,.62)
	var table:=_table(room,root,"FamilyLowTable",Vector3(-2.3,0,-.45),Vector2(1.45,.85),.43)
	_paper(root,"KeptBlueprint",Vector3(-2.3,.43,-.45),Vector2(.67,.44),table)
	_prop(room,root,"W11_ceramic_set",Vector3(-2.75,.43,-.45),.16,table)
	_model(room,root,"J08_fan",Vector3(-4.3,0,.45),20,.85,false)
	_model(room,root,"W05_hydrangea_pot",Vector3(4.2,0,-3.5),0,.45,false)
	_table(room,root,"GiftFlowerStand",Vector3(4.2,0,-3.2),Vector2(.38,.32),.20)
	ClearSignage.paper_tag(root,"FamilyNames","春 · 小葵的暑假",Vector3(4.93,1.4,.85),Vector2(1.15,.2),-PI*.5,.08)

static func _mio(room: InteriorBuilder,root: Node3D,wall: Material) -> void:
	_partition(room,Vector3(0,0,-1.25),7.0,.0,true,wall)
	_model(room,root,"I01_bed",Vector3(2.45,0,-2.3),0,.80)
	_model(room,root,"I03_bookshelf",Vector3(-2.9,0,-2.7),90,.60)
	var desk:=_table(room,root,"PrivateWindowDesk",Vector3(-2.4,0,-.3),Vector2(1.65,.95),.72)
	_paper(root,"TravelNote",Vector3(-2.7,.72,-.45),Vector2(.42,.27),desk)
	_model(room,root,"G06_zabuton",Vector3(1.25,0,-.65),0,.85,false)
	_model(room,root,"I08_boxes",Vector3(2.8,0,2.5),0,.36)
	_model(room,root,"G01_getabako",Vector3(-2.85,0,2.65),90,.65)
	ClearSignage.paper_tag(root,"PrivateMemo","下次休息，去远处看看",Vector3(-3.39,1.6,2.65),Vector2(1.3,.24),PI*.5,.085)

static func _tanaka(room: InteriorBuilder,root: Node3D,wall: Material) -> void:
	_partition(room,Vector3(-1.5,0,-1.75),3.5,.65,false,wall)
	_model(room,root,"I01_bed",Vector3(2.85,0,-2.4),0,.80)
	_model(room,root,"J05_dish_cabinet",Vector3(-3.4,0,-2.9),0,.65)
	var table:=_table(room,root,"OnePersonSupper",Vector3(-2.6,0,-.2),Vector2(1.10,.75),.68)
	_single_meal(root,Vector3(-2.6,.68,-.2),table)
	_model(room,root,"G06_zabuton",Vector3(1.25,0,-.65),0,.85,false)
	_model(room,root,"G01_getabako",Vector3(3.1,0,3.12),-90,.70)
	ClearSignage.paper_tag(root,"HomeBoundary","农具留在工具屋",Vector3(3.9,1.65,2.3),Vector2(1.15,.2),-PI*.5,.08)

static func _ren(room: InteriorBuilder,root: Node3D,wall: Material) -> void:
	_partition(room,Vector3(.3,0,-2.1),3.8,.5,false,wall)
	_model(room,root,"I01_bed",Vector3(2.35,0,-2.65),0,.80)
	_model(room,root,"I05_wardrobe",Vector3(-2.9,0,-3.15),0,.55)
	var table:=_table(room,root,"AfterClosingTable",Vector3(-2.3,0,-.4),Vector2(1.35,.75),.74)
	_prop(room,root,"W07_pastry_tray",Vector3(-2.3,.74,-.4),.18,table)
	_paper(root,"PackingTrial",Vector3(-2.3,.74,-.05),Vector2(.42,.24),table)
	_model(room,root,"W19_flour_bag",Vector3(2.8,0,2.9),0,.45,false)
	var breakfast:=_table(room,root,"PrivateBreakfastShelf",Vector3(2.8,0,1.65),Vector2(.75,1.35),.72)
	_single_meal(root,Vector3(2.8,.72,1.65),breakfast)
	_model(room,root,"G01_getabako",Vector3(-2.85,0,3.55),90,.58)
	_picture(root,"GrandparentsPhotoFrame",Vector3(-3.39,1.7,-2.3),Vector2(.65,.5),"col_bakery1972",PI*.5)

static func _kazuko(room: InteriorBuilder,root: Node3D,wall: Material) -> void:
	_partition(room,Vector3(0,0,-1.6),8.0,.35,true,wall)
	_model(room,root,"I01_bed",Vector3(2.7,0,-2.55),0,.72)
	_model(room,root,"J09_tansu",Vector3(-3.4,0,-2.6),0,.65)
	var table:=_table(room,root,"RoundConversationTable",Vector3(-2.4,0,-.1),Vector2(1.35,.85),.43)
	_prop(room,root,"W21_tea_tin",Vector3(-2.8,.43,-.1),.18,table)
	_paper(root,"OldPriceTags",Vector3(-2.2,.43,-.1),Vector2(.40,.27),table)
	_model(room,root,"G06_zabuton",Vector3(1.25,0,-.65),0,.85,false)
	_model(room,root,"J05_dish_cabinet",Vector3(3.3,0,2.5),-90,.60)

static func _toolshed(room: InteriorBuilder,root: Node3D,_wall: Material) -> void:
	var work:=_table(room,root,"DirtyWorkBench",Vector3(-2.3,0,.0),Vector2(1.8,.75),.70)
	_prop(room,root,"W16_handtools_board",Vector3(-2.3,.70,0),.45,work)
	_model(room,root,"D08_tool_rack",Vector3(-2.4,0,-2.65),0,.82)
	var high_rack: Node3D=_model(room,root,"I03_bookshelf",Vector3(2.85,0,-2.70),0,.80)
	var high_top: float=WorldBuilder.rendered_support_height(high_rack,room.origin+Vector3(2.85,0,-2.70),2.0,true)
	if is_finite(high_top):
		var tube:=MeshInstance3D.new();tube.name="EmptyFestivalTube"
		var cylinder:=CylinderMesh.new();cylinder.top_radius=.09;cylinder.bottom_radius=.09;cylinder.height=.31;cylinder.radial_segments=20;cylinder.cap_top=false
		tube.mesh=cylinder;tube.material_override=PublicPlaceArt.matte(Color(.60,.43,.27));root.add_child(tube);tube.position=Vector3(2.85,high_top+.155,-2.70)
		PublicPlaceArt.supported(tube,high_rack)
		PublicPlaceArt.cylinder(root,"EmptyTubeInterior",Vector3(2.85,high_top+.02,-2.70),.082,.015,PublicPlaceArt.matte(Color(.20,.18,.15)))
		ClearSignage.paper_tag(root,"EmptyTubeYear","2011 · 空筒",Vector3(2.85,high_top+.20,-2.60),Vector2(.18,.07),0,.033)
	var dry:=_table(room,root,"RaisedSeedCounter",Vector3(2.55,0,-1.55),Vector2(1.35,.65),1.08)
	_prop(room,root,"W28_seed_packets",Vector3(2.55,1.08,-1.55),.24,dry)
	_model(room,root,"I08_boxes",Vector3(-2.7,0,2.70),0,.40)
	var wash:=_table(room,root,"ToolCleaningShelf",Vector3(2.55,0,2.50),Vector2(1.30,.70),.70)
	_prop(room,root,"W12_cedar_tray",Vector3(2.85,.70,2.50),.13,wash)
	PublicPlaceArt.folded_cloth(root,"ToolDryingCloth",Vector3(2.23,.70,2.50),Color(.49,.62,.59),wash)
	ClearSignage.paper_tag(root,"WetDry","先清理泥土 ／ 种子放干燥架",Vector3(-3.39,1.7,1.6),Vector2(1.65,.24),PI*.5,.08)

static func _photos(room: InteriorBuilder,root: Node3D,_wall: Material) -> void:
	var table:=_table(room,root,"PhotoComparisonDesk",Vector3(-1.9,0,-1.1),Vector2(1.25,2.1),.74)
	_paper(root,"OpenAlbum",Vector3(-1.9,.74,-1.1),Vector2(.7,.55),table)
	_model(room,root,"I03_bookshelf",Vector3(2.4,0,-2.9),0,.52)
	_model(room,root,"G07_hall_cabinet",Vector3(-2.35,0,2.65),90,.55)
	for index: int in 2:_picture(root,"PhotoWall_%d"%index,Vector3(2.79,1.55,-1.55+index*1.6),Vector2(.66,.48),["col_zelkova1968","col_photo2011"][index],-PI*.5)
	ClearSignage.paper_tag(root,"ArchiveRule","确认过的事，再写下来",Vector3(-2.79,1.8,.9),Vector2(1.6,.24),PI*.5,.08)

static func _florist(room: InteriorBuilder,root: Node3D,_wall: Material) -> void:
	var wet:=_table(room,root,"FlowerWrapping",Vector3(-2.6,0,-.3),Vector2(1.75,.85),.78)
	_prop(room,root,"W01_flower_buckets",Vector3(-2.6,.78,-.3),.46,wet)
	var dry:=_table(room,root,"PressedFlowerDesk",Vector3(2.8,0,-2.9),Vector2(1.6,.7),.76)
	_paper(root,"PressedFlowerBook",Vector3(2.8,.76,-2.9),Vector2(.50,.32),dry)
	var drain:=_table(room,root,"FlowerDrainShelf",Vector3(2.85,0,.65),Vector2(1.30,.70),.66)
	_prop(room,root,"W01_flower_buckets",Vector3(2.85,.66,.65),.35,drain)
	ClearSignage.paper_tag(root,"WetDryFlowers","沥水 ／ 包花 ／ 押花",Vector3(-3.89,1.75,-1.3),Vector2(1.6,.24),PI*.5,.09)

static func _zakka(room: InteriorBuilder,root: Node3D,wall: Material) -> void:
	_partition(room,Vector3(.45,0,-2.9),4.2,-.3,false,wall)
	_model(room,root,"I03_bookshelf",Vector3(-2.85,0,3.05),90,.63)
	_model(room,root,"I03_bookshelf",Vector3(2.85,0,2.6),-90,.65)
	var bench:=_table(room,root,"RepairWorkbench",Vector3(-2.25,0,-.8),Vector2(1.6,.80),.78)
	_prop(room,root,"W16_handtools_board",Vector3(-2.25,.78,-.8),.34,bench)
	_model(room,root,"I08_boxes",Vector3(2.65,0,-3.9),0,.38)
	ClearSignage.paper_tag(root,"RepairQueue","寄修物件 · 修好归还",Vector3(-3.39,1.6,-2.75),Vector2(1.45,.24),PI*.5,.085)

static func _post(room: InteriorBuilder,root: Node3D,_wall: Material) -> void:
	# Counter stops short of the west side, leaving a real short circulation loop.
	var counter:=_table(room,root,"PostalCounter",Vector3(1.4,0,-1.5),Vector2(4.3,.65),.90)
	_paper(root,"DeliveryLedger",Vector3(.3,.90,-1.5),Vector2(.5,.3),counter)
	var writing:=_table(room,root,"LetterWriting",Vector3(-3.3,0,-.25),Vector2(1.15,1.45),.74)
	_paper(root,"ReplyPaper",Vector3(-3.3,.74,-.25),Vector2(.45,.30),writing)
	_model(room,root,"I03_bookshelf",Vector3(3.7,0,-2.8),0,.68)
	_model(room,root,"I08_boxes",Vector3(1.1,0,-2.8),0,.42)
	var parcels:=_table(room,root,"ParcelDropShelf",Vector3(3.65,0,2.10),Vector2(.70,1.25),.68)
	_prop(room,root,"W12_cedar_tray",Vector3(3.65,.68,2.10),.10,parcels)
	ClearSignage.paper_tag(root,"PostRoutes","晴町 · 寄出与收取",Vector3(4.39,1.8,.5),Vector2(1.45,.25),-PI*.5,.09)

static func _library(room: InteriorBuilder,root: Node3D,_wall: Material) -> void:
	_model(room,root,"I03_bookshelf",Vector3(-3.4,0,2.25),90,.67)
	_model(room,root,"I03_bookshelf",Vector3(3.4,0,1.9),-90,.67)
	_model(room,root,"I03_bookshelf",Vector3(2.9,0,-3.1),0,.67)
	var table:=_table(room,root,"MapReadingDesk",Vector3(-2.5,0,-1.0),Vector2(1.65,1.25),.74)
	_paper(root,"OldTownMap",Vector3(-2.5,.74,-1.0),Vector2(.82,.62),table)
	_model(room,root,"G06_zabuton",Vector3(1.25,0,-.65),0,.85,false)
	ClearSignage.paper_tag(root,"ReadingName","借阅 · 小镇旧地图",Vector3(-3.89,1.8,-2.9),Vector2(1.45,.24),PI*.5,.09)

static func _book_stack(parent: Node3D,label: String,at: Vector3,support: Node3D,count: int=3) -> void:
	var colours: Array[Color]=[Color(.32,.48,.54),Color(.67,.40,.31),Color(.72,.69,.47)]
	for index: int in count:
		var book:=PublicPlaceArt.box(parent,label+"_%d"%index,Vector3(.29,.040,.35),at+Vector3(float(index%2)*.015,.020+index*.045,0),PublicPlaceArt.matte(colours[index%3]))
		if index==0:PublicPlaceArt.supported(book,support)
		PublicPlaceArt.box(parent,label+"Pages_%d"%index,Vector3(.265,.025,.326),at+Vector3(float(index%2)*.015,.025+index*.045,.005),PublicPlaceArt.matte(Color(.94,.91,.80)))

static func _cubbies(parent: Node3D,label: String,at: Vector3,width: float,height: float,columns: int,rows: int,filled: bool=true) -> void:
	var cedar:=PublicPlaceArt.wood(Color(.64,.50,.34));var depth:=.40
	PublicPlaceArt.box(parent,label+"Back",Vector3(width,height,.035),at+Vector3(0,height*.5,-depth*.5),PublicPlaceArt.matte(Color(.48,.53,.47)))
	var body:=StaticBody3D.new();body.name=label+"Collision";body.collision_layer=WorldBuilder.L_SOLID;body.collision_mask=0;body.set_meta("model_part",true)
	var collision:=CollisionShape3D.new();var volume:=BoxShape3D.new();volume.size=Vector3(width,height,depth)
	collision.shape=volume;body.add_child(collision);parent.add_child(body);body.position=at+Vector3(0,height*.5,0)
	for column: int in columns+1:PublicPlaceArt.box(parent,label+"Upright_%d"%column,Vector3(.035,height,depth),at+Vector3(-width*.5+column*width/columns,height*.5,0),cedar)
	for row: int in rows+1:PublicPlaceArt.box(parent,label+"Shelf_%d"%row,Vector3(width,.035,depth),at+Vector3(0,.025+row*(height-.05)/rows,0),cedar)
	if filled:
		for row: int in rows:
			for column: int in columns:
				var x: float=-width*.5+(column+.5)*width/columns;var y: float=.043+row*(height-.05)/rows
				PublicPlaceArt.box(parent,label+"Bundle_%d_%d"%[row,column],Vector3(width/columns*.72,.08,depth*.72),at+Vector3(x,y+.04,.025),PublicPlaceArt.matte(Color(.83,.80,.64) if column%2==0 else Color(.58,.67,.64)))
				PublicPlaceArt.box(parent,label+"Label_%d_%d"%[row,column],Vector3(width/columns*.35,.06,.007),at+Vector3(x,y+.04,depth*.43),PublicPlaceArt.matte(Color(.98,.95,.82)))

static func _single_meal(parent: Node3D,at: Vector3,support: Node3D) -> void:
	var placemat:=PublicPlaceArt.box(parent,"SingleMealMat_%d"%parent.get_child_count(),Vector3(.67,.008,.48),at+Vector3(0,.004,0),PublicPlaceArt.canvas(Color(.63,.70,.55)))
	PublicPlaceArt.supported(placemat,support)
	var bowl:=PublicPlaceArt.cylinder(parent,"SingleBowl_%d"%parent.get_child_count(),at+Vector3(-.13,.050,0),.10,.084,PublicPlaceArt.matte(Color(.87,.91,.86)))
	var rim:=bowl.mesh as CylinderMesh;rim.top_radius=.105;rim.bottom_radius=.065;rim.cap_top=false
	PublicPlaceArt.cylinder(parent,"Rice_%d"%parent.get_child_count(),at+Vector3(-.13,.082,0),.087,.012,PublicPlaceArt.matte(Color(.98,.96,.85)))
	PublicPlaceArt.cylinder(parent,"SingleCup_%d"%parent.get_child_count(),at+Vector3(.20,.056,-.06),.044,.096,PublicPlaceArt.matte(Color(.53,.65,.63)))
	PublicPlaceArt.cylinder(parent,"Tea_%d"%parent.get_child_count(),at+Vector3(.20,.105,-.06),.035,.003,PublicPlaceArt.matte(Color(.37,.43,.29)))
	for index: int in 2:PublicPlaceArt.box(parent,"Chopstick_%d_%d"%[parent.get_child_count(),index],Vector3(.29,.008,.008),at+Vector3(-.04,.013,.18+index*.025),PublicPlaceArt.wood())

static func _rug(parent: Node3D,label: String,at: Vector3,size: Vector2,tint: Color) -> void:
	PublicPlaceArt.box(parent,label,Vector3(size.x,.008,size.y),at+Vector3(0,.008,0),PublicPlaceArt.canvas(tint))

static func _functional_fitout(room: InteriorBuilder,root: Node3D,wall: Material) -> void:
	# Furnish actual working / living bays while preserving the central capsule route.
	match room.kind:
		"home_mio":
			_partition(room,Vector3(0,0,1.95),7.0,0,true,wall)
			_rug(root,"QuietReadingRug",Vector3(2.15,0,.85),Vector2(1.75,2.0),Color(.58,.67,.70))
			_model(room,root,"P_low_bookcase",Vector3(3.20,0,.65),-90,.92)
			_model(room,root,"P_reading_chair",Vector3(2.30,0,1.20),135,1.0)
			_model(room,root,"P_reading_chair",Vector3(-2.35,0,.65),180,.92)
			var desk: Node3D=root.get_node("PrivateWindowDesk")
			_book_stack(root,"InvitationRecords",Vector3(-2.95,.72,.02),desk)
			ClearSignage.paper_tag(root,"ReadingLabel","还没收到回信的邀请",Vector3(-3.39,1.55,1.2),Vector2(.9,.2),PI*.5,.070)
			var side:=_table(room,root,"ReadingSideTable",Vector3(2.45,0,-.05),Vector2(.55,.52),.56)
			_book_stack(root,"BorrowedBooks",Vector3(2.45,.56,-.05),side,2)
			_model(room,root,"P_low_bookcase",Vector3(2.35,0,2.95),0,.9)
			var clock:=PublicRoomClock.new();clock.position=Vector3(2.8,2.0,-3.4);root.add_child(clock)
		"home_tanaka":
			_model(room,root,"J01_kitchen_counter",Vector3(3.50,0,.10),-90,.57)
			var kettle:=_table(room,root,"PrivateKettleShelf",Vector3(2.80,0,2.20),Vector2(1.10,.68),.78)
			_prop(room,root,"N01_enamel_kettle",Vector3(2.85,.78,2.20),.28,kettle)
			_model(room,root,"P_reading_chair",Vector3(-2.60,0,.70),180,.95)
			_model(room,root,"J09_tansu",Vector3(.35,0,-2.95),0,.64)
			_rug(root,"BedsideWovenMat",Vector3(2.0,0,-1.65),Vector2(2.1,2.3),Color(.64,.65,.43))
			_table(room,root,"BootChangingBench",Vector3(-2.7,0,2.70),Vector2(1.55,.52),.40)
		"home_ren":
			_model(room,root,"P_low_bookcase",Vector3(-2.85,0,1.65),90,1.0)
			var packing:=_table(room,root,"CleanPackingStorage",Vector3(-2.3,0,2.75),Vector2(1.5,.65),.72)
			PublicPlaceArt.folded_cloth(root,"BreadLinen",Vector3(-2.60,.72,2.75),Color(.72,.45,.32),packing)
			_paper(root,"SavedPaperSheets",Vector3(-1.95,.72,2.75),Vector2(.42,.38),packing)
			_model(room,root,"P_reading_chair",Vector3(1.95,0,1.65),90,.94)
			_rug(root,"PrivateBedRug",Vector3(2.10,0,-2.3),Vector2(2.0,2.6),Color(.72,.51,.42))
			var linen:=Node3D.new();linen.name="DryingLinenFrame";linen.position=Vector3(3.0,0,-.55);root.add_child(linen)
			for x: float in [-.30,.30]:PublicPlaceArt.box(linen,"Frame_%d"%int(x*100),Vector3(.045,1.45,.045),Vector3(x,.725,0),PublicPlaceArt.wood())
			PublicPlaceArt.box(linen,"Rail",Vector3(.72,.04,.04),Vector3(0,1.43,0),PublicPlaceArt.wood())
			PublicPlaceArt.box(linen,"Linen",Vector3(.52,.72,.018),Vector3(0,1.04,.025),PublicPlaceArt.canvas(Color(.86,.78,.64)))
		"home_kazuko":
			_rug(root,"ConversationRug",Vector3(-2.20,0,.45),Vector2(2.7,2.6),Color(.76,.57,.56))
			_model(room,root,"G06_zabuton",Vector3(-2.6,0,.98),0,.90,false)
			_model(room,root,"G06_zabuton",Vector3(-3.3,0,-.1),90,.85,false)
			_cubbies(root,"BorrowReturnCabinet",Vector3(-3.2,0,2.6),1.30,1.05,2,2)
			var ledger:=_table(room,root,"HouseholdLedgerDesk",Vector3(2.9,0,.75),Vector2(1.15,.65),.72)
			_book_stack(root,"BorrowingLedgers",Vector3(2.9,.72,.75),ledger,3)
			ClearSignage.paper_tag(root,"ReturnedItems","借来的东西，记得还给人家",Vector3(-3.89,1.7,2.6),Vector2(1.4,.22),PI*.5,.08)
		"toolshed":
			_table(room,root,"WorkStep",Vector3(-2.4,0,1.45),Vector2(1.55,.65),.36)
			var potting:=_table(room,root,"PottingSupplies",Vector3(-.65,0,-2.85),Vector2(1.65,.6),.80)
			_prop(room,root,"W28_seed_packets",Vector3(-.95,.80,-2.85),.20,potting)
			_prop(room,root,"W16_handtools_board",Vector3(-.25,.80,-2.85),.27,potting)
			_model(room,root,"P_library_bucket",Vector3(2.9,0,1.30),0,1.0,false)
		"photo_room":
			_partition(room,Vector3(0,0,1.75),5.8,0,true,wall)
			_cubbies(root,"DatedArchive",Vector3(-.25,0,-3.35),3.15,1.04,4,3)
			var archive:=_table(room,root,"ArchiveDrawers",Vector3(2.35,0,.10),Vector2(.65,2.4),.86)
			for index: int in 3:
				PublicPlaceArt.box(root,"ArchiveDrawer_%d"%index,Vector3(.52,.18,.65),Vector3(2.35,.55,-.65+index*.75),PublicPlaceArt.matte(Color(.62,.68,.67)))
				_paper(root,"ArchiveContactSheet_%d"%index,Vector3(2.35,.86,-.65+index*.75),Vector2(.44,.55),archive)
			_model(room,root,"P_reading_chair",Vector3(-.85,0,-1.10),-90,.90)
			_table(room,root,"ArchiveBagBench",Vector3(2.0,0,2.9),Vector2(1.25,.55),.42)
			_rug(root,"PhotoWorkMat",Vector3(-1.3,0,-1.1),Vector2(2.0,2.4),Color(.62,.70,.71))
		"florist":
			for side: int in [-1,1]:
				var display:=_table(room,root,"FlowerDisplay_%d"%side,Vector3(side*2.65,0,2.1),Vector2(1.45,1.15),.38)
				_prop(room,root,"W01_flower_buckets",Vector3(side*2.65,.38,2.1),.68,display)
				var high:=_table(room,root,"FlowerDisplayHigh_%d"%side,Vector3(side*2.65,0,3.25),Vector2(1.45,.65),.68)
				_prop(room,root,"W06_lily_vase" if side<0 else "W05_hydrangea_pot",Vector3(side*2.65,.68,3.25),.52,high)
			var wrap: Node3D=root.get_node("FlowerWrapping")
			_paper(root,"BouquetWrappingPaper",Vector3(-3.20,.78,-.3),Vector2(.44,.60),wrap)
			_cubbies(root,"DryFlowerPaperStorage",Vector3(.7,0,-3.55),2.0,1.10,3,2)
		"zakka":
			for side: int in [-1,1]:
				var island:=_table(room,root,"DailyGoodsIsland_%d"%side,Vector3(side*2.05,0,1.65),Vector2(1.2,1.8),.65)
				for index: int in 3:_prop(room,root,["W25_salt_box","W24_sugar_pack","W26_miso_tub"][index],Vector3(side*2.05,.65,1.1+index*.55),.22,island)
				PublicPlaceArt.folded_cloth(root,"ShopLinen_%d"%side,Vector3(side*2.05,.2225,1.65),Color(.69,.68,.48),root.get_node("DailyGoodsIsland_%dLowerBoard"%side))
			_cubbies(root,"AwaitingRepair",Vector3(-2.25,0,-3.95),1.75,1.04,3,2)
			var checkout:=_table(room,root,"ZakkaCheckout",Vector3(2.5,0,-.65),Vector2(1.3,.75),.85)
			_paper(root,"RepairReceipt",Vector3(2.5,.85,-.65),Vector2(.38,.26),checkout)
		"post":
			_cubbies(root,"MailRouteSorting",Vector3(.25,0,-3.15),3.7,1.04,5,3)
			_model(room,root,"P_reading_chair",Vector3(-2.30,0,-.25),-90,.94)
			_table(room,root,"WaitingBench",Vector3(-2.6,0,2.65),Vector2(2.3,.55),.43)
			var returntray:=_table(room,root,"StampAndEnvelopeShelf",Vector3(1.6,0,2.3),Vector2(1.7,.68),.72)
			_paper(root,"BlankEnvelopes",Vector3(1.2,.72,2.3),Vector2(.35,.25),returntray)
			PublicPlaceArt.tray(root,"OutgoingLetterTray",Vector3(1.95,.72,2.3),Vector2(.48,.35),returntray)
		"library":
			var reading:=_table(room,root,"QuietReadingTable",Vector3(1.8,0,1.75),Vector2(2.0,1.10),.72)
			_book_stack(root,"TownHistory",Vector3(1.25,.72,1.75),reading,2)
			_paper(root,"OpenLocalJournal",Vector3(2.15,.72,1.75),Vector2(.46,.34),reading)
			_model(room,root,"P_reading_chair",Vector3(1.2,0,2.75),180,1.0)
			_model(room,root,"P_reading_chair",Vector3(2.4,0,.75),0,1.0)
			_model(room,root,"P_low_bookcase",Vector3(-2.8,0,3.25),0,1.2)
			_model(room,root,"P_low_bookcase",Vector3(2.95,0,-1.1),-90,1.1)
			_rug(root,"QuietReadingMat",Vector3(1.8,0,1.75),Vector2(2.65,3.25),Color(.62,.69,.48))

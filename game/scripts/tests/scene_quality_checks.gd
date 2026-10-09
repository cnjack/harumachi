extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void: t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void: t.check("SCENE_QUALITY",label,ok,detail)

func painted(material: Material) -> bool:
	if material is StandardMaterial3D: return material.albedo_texture!=null
	if material is ShaderMaterial:
		for name: String in ["painted_tex","albedo_tex","wood_tex"]:
			if material.get_shader_parameter(name) is Texture2D: return true
	return false

func run() -> void:
	var world: WorldBuilder=main.world
	var chalk: Node3D=world.get_node("A13_chalkboard")
	var menu: Node3D=chalk.get_node_or_null("ClearCafeMenu")
	check("chalk lettering follows the measured leaning board instead of an upright cover",menu!=null and absf(menu.rotation.x)>.15 and absf(menu.position.z-.12)<.04)
	var text: String=""
	if menu:
		for glyph: Label3D in menu.find_children("*","Label3D",true,false): text+=glyph.text
	check("physical bakery menu advertises actual available food and its real price",text.contains("菠萝包") and text.contains(str(int(GameState.item("melon_pan").get("price",0)))) and not text.contains("珈琲") and not text.contains("咖啡"),text)
	var directions: Node=world.get_node("R09")
	var direction_text: String=""
	for glyph: Label3D in directions.find_children("*","Label3D",true,false): direction_text+=glyph.text
	check("direction names have consistent spacing and retain all three destinations",direction_text.contains("商店街") and direction_text.contains("住宅支巷") and direction_text.contains("农园") and not direction_text.contains("商 店") and not direction_text.contains("农 园"))
	for index: int in 3:
		var arrow: Node3D=directions.get_node("ClearDirection_%d"%index)
		var board: MeshInstance3D=arrow.get_node_or_null("ArrowBoard") as MeshInstance3D
		var aligned: bool=false
		if board:
			for vertex: Vector3 in board.mesh.get_faces():
				if absf(vertex.x)>.625 and absf(vertex.y)<.001:
					var vector: Vector3=arrow.global_basis*Vector3(vertex.x,0,0)
					aligned=vector.normalized().dot(Vector3(0,0,1 if index==1 else -1))>.98
		check("physical arrow %d points along the actual village route"%index,aligned)
		check("physical arrow %d is readable from both approaches"%index,arrow.find_children("*","Label3D",true,false).size()==2)
		var unobscured: bool=false
		for glyph: Label3D in arrow.find_children("*","Label3D",true,false):
			if glyph.position.z>=0:continue
			var ink: AABB=glyph.transform*glyph.get_aabb()
			unobscured=ink.position.x>-.16 and ink.end.x<.62
		check("back lettering %d clears the measured wooden upright"%index,unobscured)
	var work: InteriorBuilder=world.interiors.workroom
	var loose: int=0
	for glyph: Label3D in work.find_children("*","Label3D",true,false):
		if glyph.get_parent()==work: loose+=1
	check("workroom descriptions are attached to physical tags rather than floating in the room",loose==0,str(loose))
	var tabletop: MeshInstance3D=null
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(work.pieces[0]):
		if mesh.name.to_lower().contains("tabletop"): tabletop=mesh
	check("shared working tabletop has an actual painted wood finish",tabletop!=null and painted(tabletop.get_active_material(0)))
	var showcase: Node3D=null
	for piece: Node3D in world.interiors.bakery.pieces:
		if piece.get_meta("model_id","")=="I02_cake_showcase":showcase=piece
	var cedar: bool=false
	var glass: bool=false
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(showcase):
		if mesh.name=="CabinetBase": cedar=painted(mesh.get_active_material(0))
		if mesh.name=="GlassFront":
			var material: Material=mesh.get_active_material(0)
			glass=(material is StandardMaterial3D and material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED) or (material is ShaderMaterial and material.shader.resource_path=="res://shaders/shop_glass.gdshader")
	check("cake cabinet wood has grain while its front remains transparent",cedar and glass)
	var archive: Node=work.get_node_or_null("WorkshopArchiveDisplay")
	check("workroom archives contain readable physical plans and labelled storage",archive!=null and archive.find_children("*","Label3D",true,false).size()>=2 and archive.find_children("*","MeshInstance3D",true,false).size()>=4)
	var identity: bool=true
	for kind: String in ["store","bakery","workroom"]:
		identity=identity and world.interiors[kind].get_node_or_null("RoomIdentity")!=null
	check("each public interior has its own functional wall display",identity)
	var note: Node=world.interiors.bakery.get_node_or_null("OpeningNoteStand/OpeningProjectPaper")
	check("cooperation note is a physical paper on a supported stand",note!=null and note.get_node_or_null("Board")!=null and world.interiors.bakery.get_node("OpeningNoteStand").get_node_or_null("OpeningNoteCollision")!=null)
	var hint: Label3D=main.get_node("ProjectView").board if main.get_node_or_null("ProjectView")!=null else null
	if hint==null:
		for child: Node in main.get_children():
			if child is ProjectView:hint=child.board
	check("outdoor cooperation guidance is explicitly a UI hint rather than floating physical lettering",hint!=null and hint.billboard!=BaseMaterial3D.BILLBOARD_DISABLED and hint.get_meta("ui_hint",false))
	check("workroom entrance to the real trial stand stays reachable",NPC.MOTION_ROUTE.query(main.player,InteriorBuilder.door_point("workroom"),work.origin+Vector3(1.8,0,.4)).size()>0)
	var food: RefCounted=main.get_node("ShopLife").content
	check("shop entrances and existing product supports remain valid",food.walkways_clear() and food.supported())
	check("shop shelf titles are mounted on paper strips instead of floating above the floor",food.labels.all(func(entry: Dictionary):return entry.node.get_parent().get_node_or_null("Board")!=null))
	var cabinet: Node3D=world.house.get_node("J05_dish_cabinet")
	check("kitchen note stays on its real cabinet when walls lower",cabinet.get_node_or_null("KitchenMemo")!=null and world.house.get_node_or_null("HomeIdentity/KitchenMemo")==null)
	var dining: Node=world.house.get_node_or_null("J03_dining_set")
	check("home dining tabletop receives a painted surface rather than a single beige fill",dining!=null and WorldBuilder.find_meshes(dining).any(func(mesh: MeshInstance3D):return mesh.get_active_material(0) is ShaderMaterial))
	var summer: Node=world.house.get_node_or_null("J07_kotatsu")
	check("living-room fabric has a dedicated summer finish",summer!=null and WorldBuilder.find_meshes(summer).any(func(mesh: MeshInstance3D):return mesh.get_active_material(0) is ShaderMaterial))
	var player_listener: AudioListener3D=main.player.get_node_or_null("PlayerEar") as AudioListener3D
	check("spatial sound is heard at the player rather than the distant diorama camera",player_listener!=null and player_listener.is_current())
	check("world interactions have a bounded spatial sound path",Audio.has_method("fx_at") and Audio.get_node_or_null("WorldEffects")!=null)

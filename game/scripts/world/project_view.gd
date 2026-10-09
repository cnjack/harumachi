class_name ProjectView
extends Node3D
var s: Story
var board: Label3D
var tray: Node3D
var food: Node3D

func _process(_delta: float) -> void:
	if is_instance_valid(board):board.visible=s.world.region=="town" and not s.main.in_room and GameState.qstate("Q01")=="done" and s.player.global_position.distance_to(board.global_position)<5.0

func setup(story: Story) -> void:
	s = story
	board = Label3D.new()
	board.name="OpeningSiteHint"
	board.font = load("res://assets/fonts/LXGWWenKai-Medium.ttf")
	board.font_size = 144
	board.pixel_size = .0006
	board.position = Vector3(4.3, 1.25, 13.2)
	board.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	board.outline_size = 18
	board.outline_modulate=Color(.24,.26,.36)
	board.modulate = Color(.98,.95,.83)
	board.set_meta("ui_hint",true)
	add_child(board)
	_note_stand()
	food = Node3D.new()
	food.name = "OpeningFood"
	add_child(food)
	GameState.state_changed.connect(sync_state)
	sync_state()

func sync_state() -> void:
	var p: Dictionary = SummerProjects.opening()
	board.text = "一小篮的合作\n面包店有试做纸签" if str(p.menu) == "" else "%s\n试走 · 取餐 · 收好" % SummerProjects.MENU_NAMES.get(str(p.menu), "这次合作")
	board.visible = s.world.region == "town" and not s.main.in_room and GameState.qstate("Q01") == "done" and s.player.global_position.distance_to(board.global_position)<5.0
	for child in food.get_children():
		food.remove_child(child)
		child.queue_free()
	food.visible = s.world.region == "town" and not p.service.is_empty()
	if not food.visible: return
	var output: String = str(SummerProjects.MENUS.get(str(p.final.menu), "veg_sandwich"))
	var remaining: int = int(p.service.remaining)
	var counter: Node3D = s.world.get_node_or_null("P09")
	if counter==null:food.visible=false;return
	var height: float=WorldBuilder.rendered_support_height(counter,counter.global_position+Vector3(.45,0,0),1.5,true)
	if not is_finite(height):food.visible=false;return
	for index in remaining:
		var at: Vector3=counter.global_position+Vector3(.07+index*.38,0,0)
		var surface: float = WorldBuilder.rendered_support_height(counter,at,1.5,true)
		if not is_finite(surface): continue
		var supported:=true
		for offset: Vector3 in [Vector3(-.175,0,-.175),Vector3(.175,0,-.175),Vector3(-.175,0,.175),Vector3(.175,0,.175)]:
			var edge: float=WorldBuilder.rendered_support_height(counter,at+offset,1.5,true)
			if not is_finite(edge) or absf(edge-surface)>.02:supported=false
		if not supported:continue
		var base := MeshInstance3D.new()
		base.name = "Presentation_%d" % index
		if p.final.presentation == "plate":
			var plate := CylinderMesh.new()
			plate.top_radius = .17
			plate.bottom_radius = .15
			plate.height = .015
			base.mesh = plate
		else:
			var paper := BoxMesh.new()
			paper.size = Vector3(.32, .008, .28)
			base.mesh = paper
		base.material_override = s.world.house.flat_mat(Color(.94, .89, .76), "opening_presentation")
		base.position = Vector3(at.x, surface + .008, at.z)
		food.add_child(base)
		var node: Node3D = MealModels.spawn(s.world,food,output,.20 if p.final.portion=="bite" else .26)
		if node != null:
			node.name="Serving_%d"%index
			node.position+=Vector3(at.x,surface+.018,at.z)
	var sign := Label3D.new()
	sign.name = "ServingCaption"
	sign.font = board.font
	sign.font_size = 40
	sign.pixel_size = .002
	sign.position = Vector3(counter.global_position.x+.45,height+.35,counter.global_position.z-.28)
	sign.rotation.y = PI
	sign.text = "%s · %s\n%s · 还剩%d份" % [SummerProjects.MENU_NAMES[p.final.menu], "小份" if p.final.portion == "bite" else "整份", "纸包取走" if p.final.presentation == "paper" else "留盘坐下吃", remaining]
	food.add_child(sign)

func _note_stand() -> void:
	var room: InteriorBuilder=s.world.interiors.bakery
	var stand:=Node3D.new();stand.name="OpeningNoteStand";stand.position=Vector3(-1.55,0,1.35);stand.set_meta("model_part",true);room.add_child(stand)
	var wood:=StandardMaterial3D.new();wood.albedo_color=Color(.74,.60,.40);wood.albedo_texture=SurfaceFinish.GRAIN
	wood.uv1_triplanar=true;wood.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON;wood.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	var foot:=MeshInstance3D.new();foot.name="Base";var disk:=CylinderMesh.new();disk.top_radius=.16;disk.bottom_radius=.16;disk.height=.04
	foot.mesh=disk;foot.position.y=.022;foot.material_override=wood;stand.add_child(foot)
	var post:=MeshInstance3D.new();post.name="Post";var pole:=CylinderMesh.new();pole.top_radius=.024;pole.bottom_radius=.027;pole.height=1.03
	post.mesh=pole;post.position.y=.555;post.material_override=wood;stand.add_child(post)
	var back:=MeshInstance3D.new();back.name="CedarBacking";var plank:=BoxMesh.new();plank.size=Vector3(.73,.36,.02)
	back.mesh=plank;back.position=Vector3(0,1.15,.015);back.material_override=wood;stand.add_child(back)
	ClearSignage.paper_tag(stand,"OpeningProjectPaper","一小篮的合作\n先做一份\n请人尝尝",Vector3(0,1.15,.031),Vector2(.67,.32),0,.073)
	var body:=StaticBody3D.new();body.name="OpeningNoteCollision";body.collision_layer=WorldBuilder.L_SOLID;body.set_meta("model_part",true);stand.add_child(body)
	var shapes: Array=[ [Vector3(.055,1.07,.055),Vector3(0,.535,0)], [Vector3(.73,.36,.055),Vector3(0,1.15,.02)] ]
	for entry: Array in shapes:
		var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=entry[0];collision.shape=box;collision.position=entry[1];body.add_child(collision)

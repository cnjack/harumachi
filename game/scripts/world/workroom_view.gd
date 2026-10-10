class_name WorkroomView
extends Node3D
var world: WorldBuilder
var specimen: RepresentativeLantern
var trial_lantern: RepresentativeLantern
var festival_mount: Node3D
var festival_lantern: RepresentativeLantern
var activity_frames: Node3D

func setup(builder: InteriorBuilder) -> void:
	world = builder.wb
	name = "WorkroomProject"
	activity_frames=Node3D.new();activity_frames.name="CommunityActivityNotes";world.add_child(activity_frames)
	for index in 2:
		var at: Vector3=[Vector3(-3.9,0,-4.6),Vector3(3.1,0,9.8)][index]
		var frame: Node3D=paper_frame(activity_frames,at,world.house.wood_mat(false),world.house.flat_mat(Color(.95,.88,.68),"field_work_note"))
		frame.name="ActivityNote_%d"%index
	GameState.state_changed.connect(sync_state)
	sync_state()

func sync_state() -> void:
	var p: Dictionary = WorkshopProject.state()
	for node in [specimen, trial_lantern, festival_lantern, festival_mount]:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	specimen = null
	trial_lantern = null
	festival_lantern = null
	festival_mount = null
	var activity: bool=(GameState.day>=16 and GameState.day<=17) or SummerGathering.context()=="reunion"
	activity_frames.visible=activity and world.region=="town"
	for body in activity_frames.find_children("*","StaticBody3D",true,false): body.collision_layer=WorldBuilder.L_SOLID if activity else 0
	if str(p.phase) == "invitation": return
	if not p.get("site_preview", false) and (int(p.joints) < 3 or p.stored):
		specimen = RepresentativeLantern.new()
		add_child(specimen)
		specimen.position = Vector3(-2.8, 1.01, -1.5)
		specimen.build(int(p.joints), str(p.pattern), str(p.purpose), float(p.angle))
	if int(p.joints) < 3: return
	if not p.get("site_preview", false) and not p.stored:
		trial_lantern = RepresentativeLantern.new()
		add_child(trial_lantern)
		trial_lantern.position = Vector3(.75 if p.mount=="side" else 1.8, float(p.height), -1.8)
		trial_lantern.rotation_degrees.y = float(p.facing)
		trial_lantern.build(3, str(p.pattern), str(p.purpose), 0.0, 2.9)
	# The scene reuse is one work identity, not another inventory reward.
	if p.get("site_preview", false) and SummerGathering.context() != "" and str(p.phase) == "retained":
		festival_lantern = RepresentativeLantern.new()
		world.add_child(festival_lantern)
		festival_lantern.position = festival_position()
		festival_lantern.rotation_degrees.y = float(p.facing)
		festival_lantern.build(3, str(p.pattern), str(p.purpose), 0.0, 2.9)
		festival_mount = _mount(festival_base())
		festival_mount.visible = world.region == "town"
		festival_lantern.visible = world.region == "town"

static func festival_position() -> Vector3:
	var p: Dictionary = WorkshopProject.state()
	var at: Vector3=festival_base()
	if p.mount=="side": at.x-=1.05
	return Vector3(at.x,float(p.height),at.z)

static func festival_base() -> Vector3:
	return Vector3(-3,0,-3.8) if WorkshopProject.state().purpose=="guide" else Vector3(4,0,10.8)

func trial(outdoor: bool = false) -> Dictionary:
	var lantern: RepresentativeLantern = festival_lantern if outdoor else trial_lantern
	if not is_instance_valid(lantern): return {"clear": false, "readable": false, "revision": WorkshopProject.revision(), "place": "missing"}
	var center: Vector3 = lantern.global_position
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var head := SphereShape3D.new()
	head.radius = .23
	query.shape = head
	query.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED
	var aisle: Dictionary=observations(outdoor)
	var clear:=true
	var body:=CapsuleShape3D.new();body.radius=.32;body.height=1.6
	for offset: float in [-.3,0.0,.3]:
		for index in 26:
			var at: Vector3=(aisle.far as Vector3).lerp(aisle.end,float(index)/25.0)
			at.x+=offset
			query.shape=body;query.transform=Transform3D(Basis.IDENTITY,Vector3(at.x,.85,at.z))
			if not space.intersect_shape(query,1).is_empty(): clear=false
			query.shape=head;query.transform=Transform3D(Basis.IDENTITY,Vector3(at.x,1.65,at.z))
			if not space.intersect_shape(query,1).is_empty(): clear=false
	var near: Vector3=aisle.near
	query.shape=body;query.transform=Transform3D(Basis.IDENTITY,Vector3(near.x,.85,near.z))
	var near_clear: bool=space.intersect_shape(query,1).is_empty() and _reachable(aisle.far,near)
	var near_face: bool=_face_visible(lantern,near)
	var far_face: bool=_face_visible(lantern,aisle.far)
	var far_light: bool=_unblocked(lantern,aisle.far,lantern.global_position)
	var usable: bool=(near_clear and near_face) or far_face or WorkshopProject.state().purpose=="meeting" and far_light
	var distance: float=near.distance_to(lantern.caption.global_position)
	var letter_angle: float=rad_to_deg(2*atan(.0675/(2*distance)))
	return {"geometry_version":2,"revision": WorkshopProject.revision(), "clear": clear, "readable": usable,
		"near_text_visible":near_clear and near_face,"near_reachable":near_clear,"far_marker_visible":far_light,"far_paper_visible":far_face,"near_letter_angle":letter_angle,
		"near_elevation":rad_to_deg(atan2(center.y-near.y,Vector2(center.x-near.x,center.z-near.z).length())),"mount":str(WorkshopProject.state().mount),
		"lit": lantern.lamp.light_energy > 0.0, "place": SummerGathering.context() if outdoor else "workroom",
		"position": {"x": center.x, "y": center.y, "z": center.z}, "purpose": str(WorkshopProject.state().purpose)}

static func observations(outdoor: bool) -> Dictionary:
	if not outdoor:
		var origin: Vector3=InteriorBuilder.SPECS.workroom.origin
		return {"far":origin+Vector3(1.8,1.6,3.3),"near":origin+Vector3(.35,1.6,-.8),"end":origin+Vector3(1.8,1.6,-2.8)}
	if WorkshopProject.state().purpose=="guide": return {"far":Vector3(-3,1.6,-7),"near":Vector3(-4.45,1.6,-4.8),"end":Vector3(-3,1.6,-2.8)}
	return {"far":Vector3(4,1.6,12),"near":Vector3(1.1,1.6,11.8),"end":Vector3(4,1.6,10.4)}

func _face_visible(lantern: RepresentativeLantern,viewer: Vector3) -> bool:
	if lantern.global_basis.z.dot((viewer-lantern.global_position).normalized())<=.35: return false
	return _unblocked(lantern,viewer,lantern.caption.global_position)

func _unblocked(lantern: RepresentativeLantern,viewer: Vector3,target: Vector3) -> bool:
	var query:=PhysicsRayQueryParameters3D.create(viewer,target,WorldBuilder.L_SOLID|WorldBuilder.L_PLACED)
	var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or lantern.is_ancestor_of(hit.collider)

func _reachable(start: Vector3,finish: Vector3) -> bool:
	var origin:=Vector2(minf(start.x,finish.x)-1.0,minf(start.z,finish.z)-1.0)
	var size:=Vector2i(ceili((absf(start.x-finish.x)+2)/.2)+1,ceili((absf(start.z-finish.z)+2)/.2)+1)
	var grid:=AStarGrid2D.new();grid.region=Rect2i(Vector2i.ZERO,size);grid.cell_size=Vector2.ONE*.2;grid.offset=origin
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;grid.update()
	var probe:=PhysicsShapeQueryParameters3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.32;capsule.height=1.6;probe.shape=capsule
	probe.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED
	var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	for y in size.y:
		for x in size.x:
			var at: Vector2=origin+Vector2(x,y)*.2
			probe.transform=Transform3D(Basis.IDENTITY,Vector3(at.x,.85,at.y))
			grid.set_point_solid(Vector2i(x,y),not space.intersect_shape(probe,1).is_empty())
	var from:=Vector2i((Vector2(start.x,start.z)-origin)/.2+Vector2.ONE*.5)
	var to:=Vector2i((Vector2(finish.x,finish.z)-origin)/.2+Vector2.ONE*.5)
	if not grid.region.has_point(from) or not grid.region.has_point(to) or grid.is_point_solid(from) or grid.is_point_solid(to): return false
	return not grid.get_point_path(from,to).is_empty()

func inspect(observer: String,outdoor: bool,s: Story) -> void:
	var lantern: RepresentativeLantern=festival_lantern if outdoor else trial_lantern
	if not is_instance_valid(lantern): return
	var original: Camera3D=s.get_viewport().get_camera_3d()
	var camera:=Camera3D.new();s.main.add_child(camera)
	camera.global_position=observations(outdoor)[observer]
	camera.fov=55
	camera.look_at(lantern.caption.global_position)
	camera.make_current()
	var hud: bool=s.ui.hud.visible
	s.ui.set_hud_visible(false)
	var result: Dictionary=trial(outdoor)
	var explanation: String="近处的纸面%s，偏转约%.1f°，抬头约%.0f°。" % ["看得清" if result.near_text_visible else "被挡着或转向了另一边",float(result.near_letter_angle),float(result.near_elevation)]
	if observer=="far": explanation="从路口看，灯%s，纸面%s。想检查会不会碰头，还得亮灯试挂。" % ["看得见" if result.far_marker_visible else "被挡着","朝着这边" if result.far_paper_visible else "背向这边或被挡着"]
	await s.say("narrator","",explanation)
	await s.ui.choose(["看好了，回到纸签"])
	if is_instance_valid(original): original.make_current()
	camera.queue_free()
	s.ui.set_hud_visible(hud)

static func paper_frame(parent: Node3D,at: Vector3,wood: Material,paper: Material) -> Node3D:
	var root:=Node3D.new();root.name="PaperDryingFrame";parent.add_child(root);root.position=at
	for entry: Array in [[Vector3(.04,1.75,.04),Vector3(-.19,.875,0),wood],[Vector3(.04,1.75,.04),Vector3(.19,.875,0),wood],[Vector3(.42,.04,.04),Vector3(0,1.73,0),wood],[Vector3(.38,1.4,.02),Vector3(0,1.02,0),paper],[Vector3(.46,.04,.35),Vector3(0,.02,0),wood]]:
		var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=entry[0];mesh.mesh=box;mesh.material_override=entry[2];mesh.position=entry[1];root.add_child(mesh)
	var solid:=StaticBody3D.new();solid.collision_layer=WorldBuilder.L_SOLID;solid.collision_mask=0;solid.set_meta("model_part",true)
	var collision:=CollisionShape3D.new();var box_shape:=BoxShape3D.new();box_shape.size=Vector3(.42,1.75,.08);collision.shape=box_shape;collision.position.y=.875;solid.add_child(collision);root.add_child(solid)
	return root

func _mount(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "RepresentativeLanternStand"
	world.add_child(root)
	root.position = Vector3(at.x, 0, at.z)
	var wood := world.house.wood_mat(false)
	for dimensions: Array in [[Vector3(.08, 2.9, .08), Vector3(-1.5, 1.45, 0)], [Vector3(1.6, .08, .08), Vector3(-.75, 2.9, 0)]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = dimensions[0]
		mesh.mesh = box
		mesh.material_override = wood
		mesh.position = dimensions[1]
		root.add_child(mesh)
		var body := StaticBody3D.new()
		body.collision_layer = WorldBuilder.L_SOLID
		body.collision_mask = 0
		body.set_meta("model_part", true)
		var shape := CollisionShape3D.new()
		var solid := BoxShape3D.new()
		solid.size = dimensions[0]
		shape.shape = solid
		body.add_child(shape)
		body.position = dimensions[1]
		root.add_child(body)
	return root

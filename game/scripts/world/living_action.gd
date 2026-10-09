class_name LivingAction
extends Node3D
## Eating uses a table cut. Other actions can still follow the rig.
var actor: Node3D
var skeleton: Skeleton3D
var hand := -1
var pose: LivingPose
var prop: Node3D
var clock := 0.0
var duration := 2.4
var finished := false
var mode := "eat"
var destination := Vector3.INF
var surface_at := Vector3.INF
var surface_normal := Vector3.UP
var meal_food: Node3D
var meal_presentation := "plate"


static func matte(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.roughness = 1.0
	return material


static func cup() -> Node3D:
	var root := Node3D.new()
	root.name = "HandCup"
	var ceramic := MeshInstance3D.new()
	var shell := CylinderMesh.new()
	shell.top_radius = .055
	shell.bottom_radius = .043
	shell.height = .11
	shell.radial_segments = 16
	ceramic.mesh = shell
	ceramic.material_override = matte(Color(.95, .89, .73))
	root.add_child(ceramic)
	var tea := MeshInstance3D.new()
	var surface := CylinderMesh.new()
	surface.top_radius = .048
	surface.bottom_radius = .048
	surface.height = .002
	surface.radial_segments = 16
	tea.mesh = surface
	tea.position.y = .052
	tea.material_override = matte(Color(.52, .28, .10))
	root.add_child(tea)
	return root


func setup(who: Node3D, kind: String, item_id: String = "onigiri") -> void:
	actor = who
	mode = kind
	set_meta("model_part", true)
	if kind == "eat":
		_setup_meal(item_id)
		return
	var models: Array[Node] = actor.find_children("*", "Skeleton3D", true, false)
	if not models.is_empty():
		skeleton = models[0] as Skeleton3D
		hand = LivingPose.bone(skeleton, "hand.R")
		pose = LivingPose.new()
		pose.sip = kind == "sip"
		skeleton.add_child(pose)
		skeleton.move_child(pose, 0)
		pose.modification_processed.connect(_position_prop)
	if kind == "sip":
		prop = cup()
	else:
		var world: WorldBuilder = get_parent().get("world") as WorldBuilder
		prop = MealModels.spawn(world,self,item_id,.105)
		if prop==null: prop=Node3D.new()
		prop.name="HandFood"
	if prop.get_parent()==null: add_child(prop)


func _setup_meal(item_id: String) -> void:
	# A surface is supplied by the scene; never attach an eating prop to a hand.
	if not surface_at.is_finite(): return
	prop = Node3D.new()
	prop.name = "MealTableCut"
	add_child(prop)
	prop.global_position = surface_at
	prop.global_basis = Basis(Quaternion(Vector3.UP, surface_normal.normalized()))
	if meal_presentation == "paper":
		var paper := MeshInstance3D.new()
		paper.name = "PaperBase"
		var sheet := BoxMesh.new()
		sheet.size = Vector3(.17, .002, .15)
		paper.mesh = sheet
		paper.position.y = .0015
		paper.material_override = matte(Color(.96,.89,.71))
		prop.add_child(paper)
		for index: int in 2:
			var fold := MeshInstance3D.new()
			fold.name = "PaperFold_%d" % index
			var edge := BoxMesh.new()
			edge.size = Vector3(.008,.011,.15)
			fold.mesh = edge
			fold.position = Vector3((index*2-1)*.081,.0055,0)
			fold.material_override = paper.material_override
			prop.add_child(fold)
	else:
		_add_plate()
	var world: WorldBuilder = get_parent().get("world") as WorldBuilder
	meal_food = MealModels.spawn(world, prop, item_id, .105)
	if meal_food != null:
		meal_food.name = "OnePortion"
		meal_food.position.y += .003 if meal_presentation == "paper" else .011

func _add_plate() -> void:
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var disk := CylinderMesh.new()
	disk.top_radius = .085
	disk.bottom_radius = .08
	disk.height = .009
	disk.radial_segments = 24
	plate.mesh = disk
	plate.material_override = matte(Color(.97, .92, .81))
	plate.position.y = .005
	prop.add_child(plate)
	var rim := MeshInstance3D.new()
	rim.name = "PlateRim"
	var ring := TorusMesh.new()
	ring.inner_radius = .079
	ring.outer_radius = .085
	rim.mesh = ring
	rim.position.y = .0125
	rim.material_override = matte(Color(.92,.88,.79))
	prop.add_child(rim)


func _process(delta: float) -> void:
	clock += delta
	var phase: float = clampf(clock / duration, 0.0, 1.0)
	if not get_meta("foley_played",false) and phase>=.55:
		set_meta("foley_played",true)
		if mode=="eat" and surface_at.is_finite():Audio.fx_at("dish_place",surface_at,-10)
		elif mode=="sip" and is_instance_valid(prop):Audio.fx_at("cup_sip",prop.global_position,-9)
	if mode == "eat":
		if is_instance_valid(meal_food): meal_food.visible = phase < .55
		finished = phase >= 1.0
		return
	if is_instance_valid(pose):
		pose.amount = 1.0
		pose.phase = phase
		var head: int = LivingPose.bone(skeleton, "head")
		var mouth: Vector3 = actor.global_position + Vector3.UP * 1.52
		if head >= 0:
			mouth = (skeleton.global_transform * skeleton.get_bone_global_pose(head)).origin - Vector3.UP * .05
		pose.goal_world = destination if mode == "give" and destination.is_finite() else mouth + actor.model_root.global_basis.z.normalized() * .16
	if is_instance_valid(prop):
		prop.visible = phase > .05 and phase < .97
	if not is_instance_valid(pose):
		_position_prop()
	finished = phase >= 1.0


func _position_prop() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(prop): return
	var anchor: Vector3 = actor.global_position + Vector3(0, 1.12, -.1)
	if is_instance_valid(skeleton) and hand >= 0:
		anchor = (skeleton.global_transform * skeleton.get_bone_global_pose(hand)).origin
	prop.global_position = anchor + Vector3(0, .02, 0)
	var phase: float = clampf(clock / duration, 0.0, 1.0)
	prop.rotation.z = -.20 * sin(phase * PI) if mode == "sip" else 0.0


func _exit_tree() -> void:
	if OS.get_cmdline_user_args().has("--material-debug"):
		var entries: Array=[]
		for mesh_node: MeshInstance3D in WorldBuilder.find_meshes(self):
			var materials: Array=[]
			if mesh_node.mesh!=null:
				for index: int in mesh_node.mesh.get_surface_count():
					var inherited: Material=mesh_node.mesh.surface_get_material(index)
					var overridden: Material=mesh_node.get_surface_override_material(index)
					materials.append({"base":str(inherited.get_rid()) if inherited!=null else "none","surface":str(overridden.get_rid()) if overridden!=null else "none"})
			entries.append({"node":str(mesh_node.name)+"#"+str(mesh_node.get_instance_id()),"geometry":str(mesh_node.material_override.get_rid()) if mesh_node.material_override!=null else "none","surfaces":materials})
		print("MEAL_MATERIAL_DEBUG ",JSON.stringify(entries))
	if is_instance_valid(pose):
		pose.queue_free()

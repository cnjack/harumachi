class_name MeadowDetails
extends RefCounted
## Imagegen-designed Hyper3D meadow clumps, with roots projected onto actual terrain.
var roots: Array[Dictionary] = []
var batch_count := 0
var owner_world: WorldBuilder

func build(world: WorldBuilder) -> int:
	owner_world=world
	var town:=Node3D.new();town.name="TownMeadowDetails";world.add_child(town)
	var farm:=Node3D.new();farm.name="BankMeadowDetails";world.farm.add_child(farm)
	var rng:=RandomNumberGenerator.new();rng.seed=60610
	for patch: Array in [[-10.8,20.8],[-7.8,22.0],[13.0,21.1],[15.3,19.4],[-11.6,12.6],[24.8,50.0],[14.7,61.6],[36.3,63.0]]:
		for index: int in 7:
			var at:=Vector2(float(patch[0])+rng.randf_range(-.85,.85),float(patch[1])+rng.randf_range(-.65,.65))
			if _town_blocked(world,at):continue
			var y:=.008
			for ground_index: int in Layout.GROUND.size():
				var ground: Array=Layout.GROUND[ground_index]
				if Rect2(float(ground[1]),float(ground[2]),float(ground[3])-float(ground[1]),float(ground[4])-float(ground[2])).has_point(at):y=.002*ground_index
			_place(town,at,y,"daisy",rng)
		batch_count+=1
	for patch: Array in [[8.0,12.1],[18.0,21.8],[45.0,19.5],[57.0,29.0],[78.0,-2.0],[116.0,43.0],[134.0,17.0],[130.0,-.5]]:
		for kind: String in ["daisy","reed"]:
			for index: int in (32 if kind=="reed" else 24):
				var at:=Vector2(float(patch[0])+rng.randf_range(-4.0,4.0),float(patch[1])+rng.randf_range(-3.0,3.0))
				if not bank_clear(at,kind):continue
				_place(farm,at,LakesideLayout.height_at(at),kind,rng)
			batch_count+=1
	world.set_meta("meadow_detail_count",roots.size())
	world.get_tree().physics_frame.connect(_project_roots,CONNECT_ONE_SHOT)
	return roots.size()

func _place(parent: Node3D,at: Vector2,y: float,kind: String,rng: RandomNumberGenerator) -> void:
	# The daisy asset already includes clover, violet flowers, grass and unopened buds.
	var asset: String="V05_river_reeds" if kind=="reed" else "V04_daisy_meadow"
	var scale_value: float=rng.randf_range(.76,1.10)
	var node:=owner_world.spawn(asset,Vector3(at.x,y,at.y),rng.randf()*360.0,0,parent,scale_value)
	if node==null:return
	node.name="Meadow_%s_%d"%[kind,roots.size()]
	node.set_meta("detail_kind",kind)
	for mesh_node: MeshInstance3D in WorldBuilder.find_meshes(node):
		mesh_node.visibility_range_end=42.0;mesh_node.visibility_range_end_margin=6.0
		mesh_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	roots.append({"at":at,"y":y,"kind":kind,"region":"farm" if parent.get_parent() is FarmBuilder else "town","node":node})

func _town_blocked(world: WorldBuilder,at: Vector2) -> bool:
	for child: Node in world.get_children():
		if not child is Node3D or not child.has_meta("model_id"):continue
		var node:=child as Node3D
		var box: AABB=node.transform*WorldBuilder.local_aabb(node)
		if Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)).grow(.30).has_point(at):return true
	for point: Array in Layout.POINTS:
		if at.distance_to(Vector2(float(point[1]),float(point[2])))<1.35:return true
	return false

static func bank_clear(at: Vector2,kind: String) -> bool:
	var water:=LakesideLayout.water_distance(at)
	if water<.85 or water>(3.2 if kind=="reed" else 8.0):return false
	if LakesideLayout.path_distance(at)<2.1:return false
	for spot: Dictionary in LakesideLayout.SPOTS.values():
		if at.distance_to(spot.stand)<2.3:return false
	if at.x<28.0 and (absf(at.x)<2.0 or Rect2(4.6,9.0,9.0,5.5).has_point(at) or at.y>23.0):return false
	return true

func _project_roots() -> void:
	# Wait for newly built static terrain to enter the physics space before reading it.
	await owner_world.get_tree().physics_frame
	for entry: Dictionary in roots:
		if entry.region=="town":continue
		var at: Vector3=entry.node.global_position
		var query:=PhysicsRayQueryParameters3D.create(at+Vector3(0,2,0),at-Vector3(0,2,0),WorldBuilder.L_GROUND)
		var hit: Dictionary=owner_world.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():continue
		entry.node.global_position.y=(hit.position as Vector3).y+.002
		entry.y=entry.node.position.y

func safe_reeds() -> bool:
	for entry: Dictionary in roots:
		if entry.kind=="reed" and not bank_clear(entry.at,"reed"):return false
	return roots.any(func(entry: Dictionary):return entry.kind=="reed")

func rooted() -> bool:
	for index: int in range(0,roots.size(),7):
		var entry: Dictionary=roots[index]
		var at: Vector3=entry.node.global_position
		var query:=PhysicsRayQueryParameters3D.create(at+Vector3(0,2,0),at-Vector3(0,2,0),WorldBuilder.L_GROUND)
		var hit: Dictionary=owner_world.get_world_3d().direct_space_state.intersect_ray(query)
		var tolerance: float=.025 if entry.region=="town" else .008
		if hit.is_empty() or absf((hit.position as Vector3).y-at.y)>tolerance:
			print("MEADOW_ROOT_MISMATCH ",entry.at," hit=",hit.get("position"))
			return false
	return true

class_name LayoutValidity
extends RefCounted
## Past participation is immutable. Current applicability uses anchors and actual static collision.
static func point(value: Variant) -> Vector3:
	if value is Vector3:return value
	if value is Dictionary and value.has_all(["x","y","z"]):return Vector3(float(value.x),float(value.y),float(value.z))
	return Vector3.INF

static func anchor(entry: Dictionary) -> Array:
	if entry.is_empty():return []
	return [int(entry.uid),str(entry.item),snappedf(float(entry.x),.0001),snappedf(float(entry.z),.0001),int(entry.rot)]

static func world() -> Node3D:
	var views: Array[Node]=GameState.get_tree().get_nodes_in_group("summer_space_views")
	return views[0].get("world") as Node3D if not views.is_empty() else null

static func path_clear(path: Array) -> bool:
	if path.is_empty():return true # older stored trials cannot acquire invented new travel
	var scene: Node3D=world()
	if scene==null:return false
	var query:=PhysicsShapeQueryParameters3D.new()
	var capsule:=CapsuleShape3D.new();capsule.radius=.33;capsule.height=1.6
	query.shape=capsule;query.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED
	var space: PhysicsDirectSpaceState3D=scene.get_world_3d().direct_space_state
	for index: int in path.size():
		var start: Vector3=point(path[index])
		if not start.is_finite():return false
		query.transform=Transform3D(Basis.IDENTITY,start+Vector3.UP*.8);query.motion=Vector3.ZERO
		if not space.intersect_shape(query,1).is_empty():return false
		if index+1<path.size():
			query.motion=point(path[index+1])-start
			var swept: PackedFloat32Array=space.cast_motion(query)
			if swept.size()==2 and swept[0]<.999:return false
	return true

static func sight_clear(sight: Dictionary) -> bool:
	if sight.is_empty():return true
	var scene: Node3D=world()
	if scene==null:return false
	var start: Vector3=point(sight.get("from",{}));var finish: Vector3=point(sight.get("to",{}))
	if not start.is_finite() or not finish.is_finite():return false
	var query:=PhysicsRayQueryParameters3D.create(start,finish,WorldBuilder.L_SOLID|WorldBuilder.L_PLACED)
	return scene.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

static func measured(path: Array,sight: Dictionary={},view_required: bool=false) -> bool:
	if path.is_empty():return false
	for value: Variant in path:
		if not point(value).is_finite():return false
	return not view_required or (sight.has_all(["from","to"]) and point(sight.from).is_finite() and point(sight.to).is_finite())

static func position(at: Vector3) -> Dictionary:
	return {"x":at.x,"y":at.y,"z":at.z}

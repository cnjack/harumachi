extends RefCounted
## Small local detours through the actual full-body collision, in town, farm or interiors.
const CELL := .4
static func capsule() -> CapsuleShape3D:
	var shape := CapsuleShape3D.new(); shape.radius = .33; shape.height = 1.6
	return shape
static func query(actor: Node3D, start: Vector3, finish: Vector3, circles: Array = []) -> Array[Vector3]:
	var margin := Vector2(3.0, 3.0)
	var low := Vector2(minf(start.x, finish.x), minf(start.z, finish.z)) - margin
	# Align the grid to the actor's exact safe start; rounding it into a nearby wall can strand a detour.
	low = Vector2(start.x, start.z) + (low - Vector2(start.x, start.z)).snapped(Vector2.ONE * CELL)
	var high := Vector2(maxf(start.x, finish.x), maxf(start.z, finish.z)) + margin
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, Vector2i(ceili((high.x-low.x)/CELL)+1, ceili((high.y-low.y)/CELL)+1))
	grid.cell_size = Vector2.ONE * CELL; grid.offset = low
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var parameters := PhysicsShapeQueryParameters3D.new()
	parameters.shape = capsule(); parameters.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED | WorldBuilder.L_ACTORS
	if actor is CharacterBody3D: parameters.collision_mask |= WorldBuilder.L_BLOCK
	var body: CollisionObject3D=actor as CollisionObject3D
	if body==null: body=actor.get("body") as CollisionObject3D
	if body!=null:parameters.exclude=[body.get_rid()]
	var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	for y: int in grid.region.size.y:
		for x: int in grid.region.size.x:
			var point: Vector2 = low + Vector2(x, y) * CELL
			parameters.transform = Transform3D(Basis.IDENTITY, Vector3(point.x, start.y + .8, point.y))
			var occupied: bool=not space.intersect_shape(parameters,1).is_empty()
			for circle: Array in circles:
				if point.distance_to(circle[0])<float(circle[1])+.33:occupied=true
			grid.set_point_solid(Vector2i(x, y),occupied)
	var from := Vector2i((Vector2(start.x,start.z)-low)/CELL + Vector2.ONE*.5)
	var to := Vector2i((Vector2(finish.x,finish.z)-low)/CELL + Vector2.ONE*.5)
	var out: Array[Vector3] = []
	if grid.is_point_solid(from):
		# Existing actor overlap may be escaped, but a solid prop/wall must never be ignored.
		parameters.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED
		parameters.transform=Transform3D(Basis.IDENTITY,start+Vector3.UP*.8)
		if space.intersect_shape(parameters,1).is_empty():grid.set_point_solid(from,false)
	if grid.is_point_solid(from) or grid.is_point_solid(to): return out
	for point: Vector2 in grid.get_point_path(from, to): out.append(Vector3(point.x, start.y, point.y))
	if not out.is_empty(): out.append(finish)
	return out

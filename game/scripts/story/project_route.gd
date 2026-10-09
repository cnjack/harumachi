class_name ProjectRoute
extends RefCounted
## Walkability comes from the current world's actual collision, not a scripted arrival.
const ORIGIN := Vector2(-43.5, -15.5)
const CELL := 0.5
const SIZE := Vector2i(127, 83)

static func query(world: Node3D, start: Vector3, finish: Vector3, excluded: Array[RID] = [], stamp: String = "", circles: Array = []) -> Dictionary:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, SIZE)
	grid.cell_size = Vector2.ONE * CELL
	grid.offset = ORIGIN
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var shape := SphereShape3D.new()
	shape.radius = 0.38
	var parameters := PhysicsShapeQueryParameters3D.new()
	parameters.shape = shape
	parameters.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED
	parameters.exclude = excluded
	var space := world.get_world_3d().direct_space_state
	for y in SIZE.y:
		for x in SIZE.x:
			var cell: Vector2i = Vector2i(x, y)
			var pos: Vector2 = ORIGIN + Vector2(cell) * CELL
			parameters.transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, 0.7, pos.y))
			var occupied: bool = not space.intersect_shape(parameters, 1).is_empty()
			for circle: Array in circles:
				if pos.distance_to(circle[0]) < float(circle[1]) + .38: occupied = true
			grid.set_point_solid(cell, occupied)
	var from: Vector2i = Vector2i((Vector2(start.x, start.z) - ORIGIN) / CELL + Vector2.ONE * .5)
	var to: Vector2i = Vector2i((Vector2(finish.x, finish.z) - ORIGIN) / CELL + Vector2.ONE * .5)
	var revision: String = stamp if stamp != "" else SummerProjects.layout_fingerprint()
	if not grid.region.has_point(from) or not grid.region.has_point(to):
		return {"ok": false, "reason": "试走只检查这片庭院，先到摊位附近再试。", "revision": revision}
	if grid.is_point_solid(from) or grid.is_point_solid(to):
		return {"ok": false, "reason": "起点或取餐停点被挡住，给人留出一小片站立的位置。", "revision": revision}
	var flat_path: PackedVector2Array = grid.get_point_path(from, to)
	if flat_path.is_empty():
		return {"ok": false, "reason": "入口到取餐停点还没有连通，试着把挡路的桌椅收回或转一下。", "revision": revision}
	var path: Array = []
	var length := 0.0
	for i in flat_path.size():
		var at: Vector2 = flat_path[i]
		path.append(Vector3(at.x, 0, at.y))
		if i > 0: length += at.distance_to(flat_path[i - 1])
	return {"ok": true, "revision": revision, "path": path, "length": length,
		"start": {"x": start.x, "z": start.z}, "finish": {"x": finish.x, "z": finish.z}}

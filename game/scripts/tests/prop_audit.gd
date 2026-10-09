class_name PropAudit
extends RefCounted
## Where the generated models stand, measured from their meshes (not their bounding boxes, which
## are far too fat for shelves with canopies or carts with handles).
##   * two props share floor space      (their footprints within LOW of the base overlap)
##   * a prop pushes into a building    (a building's wall faces run through the prop)
##   * a prop pushes into a block wall  (Layout.WALLS)
##   * a prop floats or sinks           (its base is off the ground and nothing holds it up)
## Every instance made by WorldBuilder.spawn() carries meta "model_id"; that is what gets checked.

const LOW := 0.3          # a footprint is what a model occupies within 0.3 m of its base
const TOUCH := 0.06       # footprints may touch or overlap this much before it counts
const WALL_TOP := 2.2     # building faces up to this height are tested against props
const BIG_AREA := 6.0     # footprints this large are buildings: their walls are tested, not their hull
const CELL := 0.12
## Plants, animals and hanging things: overlapping or floating is how they are meant to look.
const LOOSE := ["C0", "C1", "T01", "T02", "T03", "T04", "T05", "V0", "M12b", "M12d", "D11", "A20", "A21", "A22", "G08", "P_chochin", "E01_furin", "A07", "F08"]

static var _tris := {}     # model id -> PackedVector3Array (root-local triangles, unscaled)
static var _hull := {}     # "id@scale@band" -> PackedVector2Array (local XZ)


static func instances(root: Node, out: Array = []) -> Array:
	for c in root.get_children():
		if c.has_meta("model_id"):
			out.append(c)
		else:
			instances(c, out)
	return out


static func loose(id: String) -> bool:
	for p in LOOSE:
		if id.begins_with(p):
			return true
	return false


static func tris(n: Node3D) -> PackedVector3Array:
	var id: String = n.get_meta("model_id")
	if _tris.has(id):
		return _tris[id]
	var out := PackedVector3Array()
	var inv := n.global_transform.affine_inverse()
	for mi in WorldBuilder.find_meshes(n):
		var xf := inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var a: Array = mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				for p in v:
					out.append(xf * p)
			else:
				for i in idx:
					out.append(xf * v[i])
	_tris[id] = out
	return out


## Footprint in world XZ. band < 0 = the whole height.
static func footprint(n: Node3D, band: float = LOW) -> PackedVector2Array:
	var s := n.global_transform.basis.get_scale().x
	var key := "%s@%.3f@%.2f" % [n.get_meta("model_id"), s, band]
	var local: PackedVector2Array
	if _hull.has(key):
		local = _hull[key]
	else:
		var t := tris(n)
		var lo := INF
		for p in t:
			lo = minf(lo, p.y)
		var cut := INF if band < 0.0 else lo + band / maxf(s, 0.01)
		var pts := PackedVector2Array()
		for p in t:
			if p.y <= cut:
				pts.append(Vector2(p.x, p.z))
		local = Geometry2D.convex_hull(pts) if pts.size() >= 3 else PackedVector2Array()
		_hull[key] = local
	var w := PackedVector2Array()
	var xf := n.global_transform
	for q in local:
		var g := xf * Vector3(q.x, 0.0, q.y)
		w.append(Vector2(g.x, g.z))
	return w


## A declared support is valid only where its rendered surface actually meets the prop's base.
static func mount_supported(prop: Node3D, support: Node3D) -> bool:
	if not prop.has_meta("support_surface") or prop.get_node_or_null(prop.get_meta("support_surface")) != support: return false
	var hull: PackedVector2Array = footprint(prop)
	if hull.is_empty(): return false
	var centre: Vector2 = _centroid(hull)
	var surface_y: float = WorldBuilder.rendered_support_height(support, Vector3(centre.x, 0, centre.y),float(prop.get_meta("support_ceiling",INF)))
	return absf(base_y(prop) - surface_y) <= .04


static func area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]; var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


static func overlap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var t := 0.0
	for pa in Geometry2D.offset_polygon(a, -TOUCH * 0.5):
		for pb in Geometry2D.offset_polygon(b, -TOUCH * 0.5):
			for r in Geometry2D.intersect_polygons(pa, pb):
				t += area(r)
	return t


static func base_y(n: Node3D) -> float:
	var t := tris(n)
	var lo := INF
	for p in t:
		lo = minf(lo, p.y)
	return n.global_transform.origin.y + lo * n.global_transform.basis.get_scale().y


static func top_y(n: Node3D) -> float:
	var t := tris(n)
	var hi := -INF
	for p in t:
		hi = maxf(hi, p.y)
	return n.global_transform.origin.y + hi * n.global_transform.basis.get_scale().y


## Points sampled over a building's near-vertical faces, world space.
static func wall_points(n: Node3D) -> PackedVector3Array:
	var t := tris(n)
	var xf := n.global_transform
	var out := PackedVector3Array()
	var y0 := base_y(n)
	var i := 0
	while i + 2 < t.size():
		var a := xf * t[i]; var b := xf * t[i + 1]; var c := xf * t[i + 2]
		i += 3
		if minf(a.y, minf(b.y, c.y)) > y0 + WALL_TOP:
			continue
		var nrm := (b - a).cross(c - a)
		if nrm.length_squared() < 1e-10 or absf(nrm.normalized().y) > 0.6:
			continue
		var k := clampi(ceili(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / CELL), 1, 40)
		for u in k + 1:
			for v in k + 1 - u:
				var p := a + (b - a) * (float(u) / k) + (c - a) * (float(v) / k)
				if p.y <= y0 + WALL_TOP:
					out.append(p)
	return out


## All findings under root. Each: {kind, a, b, at, amount}.
static func run(root: Node3D, walls: Array = []) -> Array:
	var all := instances(root)
	var small: Array = []
	var big: Array = []
	var info := {}
	for n: Node3D in all:
		if not n.is_visible_in_tree():
			continue
		var fl := footprint(n)
		var body := footprint(n, -1.0)
		if body.size() < 3:
			continue
		var d := {"n": n, "id": n.get_meta("model_id"), "low": fl, "body": body, "base": base_y(n), "top": top_y(n),
			"box": _rect(body)}
		info[n] = d
		if area(body) >= BIG_AREA and not loose(d.id):
			big.append(d)
		else:
			small.append(d)
	var found: Array = []
	# prop against prop, on the same level
	for i in small.size():
		var a: Dictionary = small[i]
		if loose(a.id) or a.low.size() < 3:
			continue
		for j in range(i + 1, small.size()):
			var b: Dictionary = small[j]
			if loose(b.id) or b.low.size() < 3 or absf(a.base - b.base) > 0.25:
				continue
			# Separate shelf levels can share XZ space without sharing physical volume.
			if a.top<b.base-.004 or b.top<a.base-.004:continue
			# Adjacent shelf tiers may be less than .25m apart without sharing any volume.
			if not volumes_share_height(float(a.base),float(a.top),float(b.base),float(b.top)):
				continue
			if not a.box.grow(0.05).intersects(b.box):
				continue
			if mount_supported(a.n, b.n) or mount_supported(b.n, a.n):
				continue
			var ov := overlap(a.low, b.low)
			if ov > 0.004:
				found.append({"kind": "overlap", "a": a.id, "b": b.id, "at": _xz(a.n), "amount": ov})
	# building walls through props
	for g: Dictionary in big:
		var pts := wall_points(g.n)
		for a: Dictionary in small:
			if loose(a.id) or not g.box.intersects(a.box):
				continue
			var inner := Geometry2D.offset_polygon(a.body, -TOUCH)
			if inner.is_empty():
				continue
			var cnt := 0
			for p in pts:
				if p.y < a.base - 0.05 or p.y > a.top:
					continue
				var q := Vector2(p.x, p.z)
				if not a.box.has_point(q):
					continue
				for poly in inner:
					if Geometry2D.is_point_in_polygon(q, poly):
						cnt += 1
						break
			if cnt >= 3:
				found.append({"kind": "in_building", "a": a.id, "b": g.id, "at": _xz(a.n), "amount": cnt})
	# block walls
	for a: Dictionary in small:
		if loose(a.id):
			continue
		for w in walls:
			var seg := PackedVector2Array([Vector2(w[0], w[1]), Vector2(w[2], w[3])])
			for poly in Geometry2D.offset_polygon(a.body, -TOUCH - 0.1):
				if not Geometry2D.intersect_polyline_with_polygon(seg, poly).is_empty():
					found.append({"kind": "in_wall", "a": a.id, "b": "wall %s" % str(w), "at": _xz(a.n), "amount": 1})
					break
	var space := root.get_world_3d().direct_space_state
	# built walls, counters and fences (procedural colliders that are not part of any model)
	for a: Dictionary in small:
		if loose(a.id):
			continue
		for poly in Geometry2D.offset_polygon(a.body, -TOUCH - 0.04):
			if poly.size() < 3:
				continue
			var h := clampf(a.top - a.base - 0.2, 0.1, 1.6)
			var pts := PackedVector3Array()
			for q in poly:
				pts.append(Vector3(q.x, -h * 0.5, q.y))
				pts.append(Vector3(q.x, h * 0.5, q.y))
			var sh := ConvexPolygonShape3D.new()
			sh.points = pts
			var sq := PhysicsShapeQueryParameters3D.new()
			sq.shape = sh
			sq.transform = Transform3D(Basis.IDENTITY, Vector3(0, a.base + 0.15 + h * 0.5, 0))
			sq.collision_mask = WorldBuilder.L_SOLID
			for r in space.intersect_shape(sq, 16):
				var col: Node = r.collider
				if _in_model(col):
					continue
				var what := str(col.get_parent().name) + "/" + str(col.name)
				for sc in col.get_children():
					if sc is CollisionShape3D and (sc as CollisionShape3D).shape is BoxShape3D:
						var gp := (sc as CollisionShape3D).global_position
						what += " box %s at (%.2f, %.2f, %.2f)" % [((sc as CollisionShape3D).shape as BoxShape3D).size, gp.x, gp.y, gp.z]
						break
				found.append({"kind": "in_wall", "a": a.id, "b": what, "at": _xz(a.n), "amount": 1})
				break
	# floating / sunk (ground = L_GROUND colliders straight below)
	for a: Dictionary in small + big:
		if loose(a.id):
			continue
		# A bridge spans water: its centre is supported by end banks/piles, not floor.
		# WORLD/LAKE check the actual walkable deck, abutments and bank connection.
		if a.id=="P_bridge":continue
		var c := _centroid(a.low if a.low.size() >= 3 else a.body)
		var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, a.base + 1.5, c.y), Vector3(c.x, a.base - 1.5, c.y), WorldBuilder.L_GROUND)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var dy: float = a.base - (hit.position as Vector3).y
		if dy > 0.04:
			var held := false
			for b: Dictionary in small + big:
				if b.n != a.n and absf(b.top - a.base) < 0.08 and b.box.has_point(c):
					held = true
					break
			if not held and a.n.has_meta("support_surface"):
				var support: Node3D = a.n.get_node_or_null(a.n.get_meta("support_surface")) as Node3D
				if support != null: held = mount_supported(a.n, support)
			if not held:
				found.append({"kind": "floating", "a": a.id, "b": "", "at": _xz(a.n), "amount": dy})
		elif dy < -0.06:
			found.append({"kind": "sunk", "a": a.id, "b": "", "at": _xz(a.n), "amount": -dy})
	return found

static func volumes_share_height(a_base: float,a_top: float,b_base: float,b_top: float) -> bool:
	return a_top>b_base+.003 and b_top>a_base+.003


static func _in_model(n: Node) -> bool:
	while n != null:
		if n.has_meta("model_id") or n.has_meta("model_part"):
			return true
		n = n.get_parent()
	return false


static func _rect(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


static func _centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for q in p:
		c += q
	return c / maxf(p.size(), 1)


static func _xz(n: Node3D) -> String:
	var p := n.global_position
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]


static func describe(f: Dictionary) -> String:
	match f.kind:
		"overlap":
			return "%s overlaps %s by %.3f m² at %s" % [f.a, f.b, f.amount, f.at]
		"in_building":
			return "%s runs into %s (%d wall samples) at %s" % [f.a, f.b, f.amount, f.at]
		"in_wall":
			return "%s crosses %s at %s" % [f.a, f.b, f.at]
		"floating":
			return "%s floats %.2f m at %s" % [f.a, f.amount, f.at]
		"sunk":
			return "%s sinks %.2f m at %s" % [f.a, f.amount, f.at]
	return str(f)

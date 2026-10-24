extends RefCounted
## Shape, planting depth and walk space are read from the rendered geometry.
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("STREET_TREE", label, ok, detail)

func _part_bounds(root: Node3D, prefix: String) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		if not str(mesh.name).begins_with(prefix): continue
		var actual: AABB = mesh.global_transform * mesh.get_aabb()
		box = actual if first else box.merge(actual)
		first = false
	return box

func _section(root: Node3D, height: float) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		if not str(mesh.name).begins_with("Trunk"): continue
		var faces: PackedVector3Array = mesh.global_transform * mesh.mesh.get_faces()
		for offset: int in range(0, faces.size(), 3):
			for edge: int in 3:
				var a: Vector3 = faces[offset+edge]
				var b: Vector3 = faces[offset+(edge+1)%3]
				if (a.y < height and height <= b.y) or (b.y < height and height <= a.y):
					var point: Vector3 = a.lerp(b, (height-a.y)/(b.y-a.y))
					var xz := Vector2(point.x, point.z)
					low = low.min(xz)
					high = high.max(xz)
	return Rect2(low, high-low) if is_finite(low.x) else Rect2()

func _ground_kind(at: Vector2) -> String:
	var kind := "meadow"
	for patch: Array in Layout.GROUND:
		if Rect2(float(patch[1]),float(patch[2]),float(patch[3])-float(patch[1]),float(patch[4])-float(patch[2])).has_point(at): kind = str(patch[0])
	return kind

func run() -> void:
	var paved_trees: Array[Node3D] = []
	var retained_garden_trees := 0
	for candidate: Node in main.world.get_children():
		if not candidate is Node3D or not str(candidate.get_meta("model_id", "")).begins_with("T"): continue
		var town_tree := candidate as Node3D
		if _ground_kind(Vector2(town_tree.global_position.x,town_tree.global_position.z)) == "stone": paved_trees.append(town_tree)
		elif str(town_tree.get_meta("model_id", "")) == "T01_courtyard_tree": retained_garden_trees += 1
	check("all town trees planted into paving are included in the street audit", paved_trees.size() == 1)
	check("the seven garden and rear-greenbelt trees retain their own source", retained_garden_trees == 7)
	var bed := main.world.get_node_or_null("StreetTreeBed") as Node3D
	check("the shop street has an open soil pit with a stone perimeter", bed != null)
	if bed == null: return
	var soil := bed.get_node_or_null("RecessedSoil") as MeshInstance3D
	check("the exposed soil occupies at least one square metre", soil != null and soil.get_aabb().size.x*soil.get_aabb().size.z >= 1.0)
	var inside_open := true
	for dx: float in [-.46, 0.0, .46]:
		for dz: float in [-.46, 0.0, .46]:
			var at := StreetTree.CENTRE+Vector2(dx,dz)
			var soil_top: float = WorldBuilder.surface_height(main.world, at, .03, true)
			inside_open = inside_open and absf(soil_top-StreetTree.SOIL_Y)<.002
	check("paving and gravel triangles are actually absent from nine soil-hole probes", inside_open)
	var outside_intact := true
	for offset: Vector2 in [Vector2(-.84,0),Vector2(.84,0),Vector2(0,-.84),Vector2(0,.84)]:
		var paving_top: float = WorldBuilder.surface_height(main.world, StreetTree.CENTRE+offset, .03, true)
		outside_intact = outside_intact and absf(paving_top-.010)<.002
	check("opening the pit keeps all four surrounding paving edges intact", outside_intact)
	var bed_box: AABB = bed.global_transform*WorldBuilder.local_aabb(bed)
	var curb_edge: float = Layout.STREET_Z-Layout.STREET_HALF-.11
	var walk_width: float = curb_edge-bed_box.end.z
	check("the actual stone rim leaves a 1.25 metre pedestrian passage before the curb", walk_width >= 1.25, "%.3fm" % walk_width)
	for tree: Node3D in paved_trees:
		var root_box: AABB = _part_bounds(tree, "Trunk")
		var crown: AABB = _part_bounds(tree, "Foliage")
		var height: float = maxf(root_box.end.y, crown.end.y)-root_box.position.y
		var waist: Rect2 = _section(tree, tree.global_position.y+.60)
		var lower: Rect2 = _section(tree, tree.global_position.y+.35)
		var upper: Rect2 = _section(tree, tree.global_position.y+1.05)
		check("street stem is 8–20 cm thick at 60 cm above its roots", maxf(waist.size.x,waist.size.y)>=.08 and maxf(waist.size.x,waist.size.y)<=.20, str(waist.size))
		check("the stem narrows before the fork instead of keeping a wooden-post profile", maxf(upper.size.x,upper.size.y)<=maxf(lower.size.x,lower.size.y)*.82)
		check("street crown has horizontal reach and pedestrian head clearance", crown.position.y>=1.85 and maxf(crown.size.x,crown.size.z)>=2.0 and maxf(crown.size.x,crown.size.z)/height>=.60, str(crown))
		var forks: Rect2 = _section(tree, tree.global_position.y+2.05)
		check("real branches spread through both dimensions below the leaf crown", forks.size.x>=.50 and forks.size.y>=.35, str(forks))
		check("root collar enters the exposed soil without floating", absf(root_box.position.y-(StreetTree.SOIL_Y-.008))<.003)
		var tree_footprint := Rect2(Vector2(crown.position.x,crown.position.z),Vector2(crown.size.x,crown.size.z))
		var clear_shop_fronts := true
		for shop_id: String in ["S02","S03"]:
			var shop := main.world.get_node_or_null(shop_id) as Node3D
			if shop == null: clear_shop_fronts = false; continue
			var shop_box: AABB = shop.global_transform*WorldBuilder.local_aabb(shop)
			var footprint := Rect2(Vector2(shop_box.position.x,shop_box.position.z),Vector2(shop_box.size.x,shop_box.size.z))
			clear_shop_fronts = clear_shop_fronts and not tree_footprint.intersects(footprint.grow(.10))
		check("the rendered crown clears both neighbouring shop facades and windows", clear_shop_fronts)

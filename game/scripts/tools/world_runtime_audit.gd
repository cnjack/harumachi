extends Node
## Optional observation only. Captures real scene instances and physics contacts; never moves them.
var main: Node
var output := ""
var elapsed := 0.0
var wait := 0.0
var finished := false
var census: Dictionary = {}
var previous: Dictionary = {}
var contacts: Dictionary = {}
var events: Array = []
var samples := 0
var event_file: FileAccess
var moving_nodes: Array[WeakRef] = []
var physical_previous: Dictionary = {}
var render_candidates: Array = []

func setup(scene: Node, path: String) -> void:
	main = scene
	output = path
	add_to_group("spatial_audits")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	event_file = FileAccess.open(path.get_basename() + ".jsonl", FileAccess.WRITE)

func _physics_process(delta: float) -> void:
	if finished: return
	elapsed += delta
	for reference: WeakRef in moving_nodes:
		var actor: Node3D = reference.get_ref() as Node3D
		if actor == null or not actor.is_inside_tree(): continue
		var key: String = str(actor.get_instance_id())
		_probe(actor, physical_previous.get(key, {}))
		physical_previous[key] = {"position": actor.global_position, "visible": actor.is_visible_in_tree()}
	wait -= delta
	if wait > 0.0: return
	wait = .2
	sample()

func _position(at: Vector3) -> Array:
	return [at.x, at.y, at.z]

func _emit(kind: String, data: Dictionary) -> void:
	var record: Dictionary = {"event": kind, "sample": samples, "seconds": elapsed,
		"day": GameState.day, "minute": GameState.minute, "region": GameState.player_region}
	record.merge(data)
	if event_file: event_file.store_line(JSON.stringify(record))
	if kind != "motion": events.append(record)

func _category(node: Node3D) -> String:
	if node is NPC or node == main.player: return "character"
	if node.get_meta("audit_category", "") != "": return str(node.get_meta("audit_category"))
	if node is MultiMeshInstance3D:
		var parent: Node = node.get_parent()
		while parent != null:
			var script: Script = parent.get_script() as Script
			if script != null and script.resource_path.ends_with("grass_field.gd"): return "plant_field"
			parent = parent.get_parent()
	var id: String = str(node.get_meta("model_id", ""))
	if id.begins_with("CH_"): return "character_visual"
	if id.begins_with("AN_") or id.begins_with("A20") or id.begins_with("A21") or id.begins_with("A22"): return "animal"
	if id.begins_with("T0") or id.begins_with("V0") or id.begins_with("C0") or id.begins_with("C1"): return "plant"
	return "prop" if id != "" else "scene_geometry"

func _collect(node: Node, out: Array[Node3D]) -> void:
	if node is Node3D and (node.has_meta("model_id") or node.has_meta("audit_category") or node is NPC or node == main.player):
		out.append(node as Node3D)
	elif node is GeometryInstance3D:
		var owned := false
		var parent: Node = node.get_parent()
		while parent != null:
			if parent.has_meta("model_id") or parent is NPC or parent == main.player: owned = true; break
			parent = parent.get_parent()
		if not owned: out.append(node as Node3D)
	for child: Node in node.get_children(): _collect(child, out)

func _body_id(node: Node3D) -> String:
	var current: Node = node
	while current != null:
		if current.has_meta("model_id"): return str(current.get_meta("model_id")) + "@" + str(current.get_path())
		current = current.get_parent()
	return str(node.get_path())

func _contact(actor: Node3D, other: Node3D, reason: String, at: Vector3) -> void:
	var key: String = str(actor.get_path()) + "|" + _body_id(other) + "|" + reason
	if contacts.has(key):
		contacts[key].count = int(contacts[key].count) + 1
		contacts[key].last_seconds = elapsed
		return
	var info: Dictionary = {"actor": str(actor.get_path()), "other": _body_id(other),
		"kind": reason, "position": _position(at), "first_seconds": elapsed, "last_seconds": elapsed, "count": 1}
	contacts[key] = info
	_emit("contact", info)

func _probe(node: Node3D, before: Dictionary) -> void:
	if not node.is_visible_in_tree(): return
	var shape: Shape3D
	var offset := Vector3.ZERO
	var exclude: Array[RID] = []
	if node is NPC:
		var capsule := CapsuleShape3D.new(); capsule.radius = .27; capsule.height = 1.5
		shape = capsule; offset.y = .8; exclude.append(node.body.get_rid())
	elif node == main.player:
		var capsule := CapsuleShape3D.new(); capsule.radius = .27; capsule.height = 1.5
		shape = capsule; offset.y = .8; exclude.append(main.player.get_rid())
	elif node is CharacterBody3D and node.get_meta("audit_category", "") == "animal":
		var box := BoxShape3D.new(); box.size = Vector3(.14, .20, .22)
		shape = box; offset.y = .12; exclude.append((node as CharacterBody3D).get_rid())
	elif _category(node) == "animal":
		if node.get_parent() is CharacterBody3D: return
		var sphere := SphereShape3D.new(); sphere.radius = .075
		shape = sphere
		if node.has_meta("model_id"):
			var bounds: AABB=node.global_transform*WorldBuilder.local_aabb(node)
			offset=Vector3(bounds.get_center().x,bounds.position.y+minf(.075,bounds.size.y*.45),bounds.get_center().z)-node.global_position
	else: return
	var ancestor: Node = node.get_parent()
	while ancestor != null:
		if ancestor is CollisionObject3D: exclude.append((ancestor as CollisionObject3D).get_rid())
		ancestor = ancestor.get_parent()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape; query.exclude = exclude
	query.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED | WorldBuilder.L_ACTORS
	query.transform = Transform3D(Basis.IDENTITY, node.global_position + offset)
	var space: PhysicsDirectSpaceState3D = node.get_world_3d().direct_space_state
	for hit: Dictionary in space.intersect_shape(query, 8):
		if hit.collider is Node3D: _contact(node, hit.collider, "body_inside_solid", node.global_position)
	if before.is_empty() or not bool(before.visible): return
	var start: Vector3 = before.position
	var motion: Vector3 = node.global_position - start
	# Authored cuts and region changes are recorded as jumps rather than swept through the whole town.
	if motion.length() > 3.0 or motion.length() < .02: return
	query.transform.origin = start + offset
	query.motion = motion
	var cast: PackedFloat32Array = space.cast_motion(query)
	if cast.size() == 2 and cast[0] < .99:
		query.transform.origin += motion * minf(1.0, float(cast[1]) + .01)
		query.motion = Vector3.ZERO
		for hit: Dictionary in space.intersect_shape(query, 8):
			if hit.collider is Node3D: _contact(node, hit.collider, "swept_through_solid", query.transform.origin - offset)

func sample() -> void:
	if finished or not is_instance_valid(main): return
	samples += 1
	var objects: Array[Node3D] = []
	_collect(main, objects)
	var active: Dictionary = {}
	for node: Node3D in objects:
		var key: String = str(node.get_instance_id())
		active[key] = true
		var visible_now: bool = node.is_visible_in_tree()
		var at: Vector3 = node.global_position
		var before: Dictionary = previous.get(key, {})
		if not census.has(key):
			var category: String = _category(node)
			var info: Dictionary = {"path": str(node.get_path()), "model": str(node.get_meta("model_id", node.get_meta("audit_model", ""))),
				"category": category, "parent": str(node.get_parent().get_path()), "first_sample": samples,
				"item": str(node.get_meta("audit_item", "")),
				"spawn_order": int(node.get_meta("spawn_order", -1)), "spawn_ms": int(node.get_meta("spawn_ms", -1)),
				"first_position": _position(at), "visible": visible_now}
			if node.has_meta("model_id"):
				var box: AABB = node.global_transform * WorldBuilder.local_aabb(node)
				info["bounds"] = {"minimum": _position(box.position), "extent": _position(box.size)}
			elif node is GeometryInstance3D:
				var box: AABB = node.global_transform * (node as GeometryInstance3D).get_aabb()
				info["bounds"] = {"minimum": _position(box.position), "extent": _position(box.size)}
				if node is MultiMeshInstance3D: info["instances"] = (node as MultiMeshInstance3D).multimesh.instance_count
			elif node is NPC:
				var box: AABB = node.model.global_transform * WorldBuilder.local_aabb(node.model)
				info["bounds"] = {"minimum": _position(box.position), "extent": _position(box.size)}
			census[key] = info
			if category in ["character", "animal"]: moving_nodes.append(weakref(node))
			_emit("discovered", info)
		if before.is_empty() or bool(before.visible) != visible_now:
			_emit("visibility", {"path": str(node.get_path()), "visible": visible_now, "position": _position(at)})
		elif visible_now and at.distance_to(before.position) > .025:
			var distance: float = at.distance_to(before.position)
			_emit("jump" if distance > 3.0 else "motion", {"path": str(node.get_path()), "from": _position(before.position),
				"to": _position(at), "distance": distance, "motion_reason": str(node.get_meta("motion_reason", "ordinary"))})
		previous[key] = {"position": at, "visible": visible_now}
	for key: String in previous.keys():
		if not active.has(key):
			_emit("removed", {"path": str(census[key].path)})
			previous.erase(key)

func finish() -> void:
	if finished or output == "": return
	sample()
	finished = true
	if event_file: event_file.flush(); event_file.close()
	var counts: Dictionary = {}
	for info: Dictionary in census.values(): counts[info.category] = int(counts.get(info.category, 0)) + 1
	var bounded: Array = census.values().filter(func(info: Dictionary): return info.has("bounds") and info.category in ["prop","plant","animal","character"])
	bounded.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.bounds.minimum[0]) < float(b.bounds.minimum[0]))
	for left: int in bounded.size():
		var a: Dictionary = bounded[left]
		var a_box := AABB(_vector(a.bounds.minimum),_vector(a.bounds.extent))
		if minf(a_box.size.x,minf(a_box.size.y,a_box.size.z))<=.012:continue
		for right: int in range(left+1,bounded.size()):
			var b: Dictionary = bounded[right]
			if float(b.bounds.minimum[0]) > a_box.end.x: break
			if str(a.path).begins_with(str(b.path)+"/") or str(b.path).begins_with(str(a.path)+"/"): continue
			var b_box := AABB(_vector(b.bounds.minimum),_vector(b.bounds.extent))
			if minf(b_box.size.x,minf(b_box.size.y,b_box.size.z))<=.012:continue
			if a_box.grow(-.006).intersects(b_box.grow(-.006)):
				render_candidates.append({"a":a.path,"b":b.path,"categories":[a.category,b.category],"status":"unreviewed_rest_bounds_candidate"})
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"samples": samples, "seconds": elapsed, "categories": counts,
			"objects": census.values(), "contacts": contacts.values(), "events": events, "render_candidates": render_candidates,
			"scope": "Real live instance census, visibility, positions and physics probes. Discovery is not creation; spawn_order records WorldBuilder creation. Contacts are physics candidates for investigation, not mesh-render proof. Authored cuts retained. No game state changed by observer."}, "  "))
	print("SPATIAL AUDIT objects=%d contacts=%d samples=%d" % [census.size(), contacts.size(), samples])

func _vector(at: Array) -> Vector3: return Vector3(float(at[0]),float(at[1]),float(at[2]))

func _exit_tree() -> void:
	finish()

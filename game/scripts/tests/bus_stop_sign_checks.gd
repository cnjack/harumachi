extends RefCounted
## Inspect rendered triangles and text dimensions, including the rejected thin plate.
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("BUS_STOP_SIGN", label, ok, detail)

func _faces(root: Node3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		faces.append_array(mesh.global_transform * mesh.mesh.get_faces())
	return faces

func _hits(faces: PackedVector3Array, from: Vector3, to: Vector3) -> Array[float]:
	var distances: Array[float] = []
	for index: int in range(0, faces.size(), 3):
		var point: Variant = Geometry3D.segment_intersects_triangle(from, to, faces[index], faces[index + 1], faces[index + 2])
		if not point is Vector3: continue
		var distance: float = from.distance_to(point)
		var duplicate := false
		for previous: float in distances:
			if absf(previous - distance) < .00001: duplicate = true
		if not duplicate: distances.append(distance)
	distances.sort()
	return distances

func _first(faces: PackedVector3Array, from: Vector3, to: Vector3) -> float:
	var distances: Array[float] = _hits(faces, from, to)
	return distances[0] if not distances.is_empty() else INF

func _source_faces(shelter: Node3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(shelter):
		# R06's original visible mesh is the root or its direct imported child.
		if mesh == shelter or mesh.get_parent() == shelter:
			faces.append_array(mesh.global_transform * mesh.mesh.get_faces())
	return faces

func _thickness(header: Node3D) -> Array[float]:
	var board := header.get_node_or_null("Board") as MeshInstance3D
	var depths: Array[float] = []
	if board == null: return depths
	var faces: PackedVector3Array = _faces(board)
	for x: float in [-1.0, 0.0, 1.0]:
		for y: float in [-.08, 0.0, .08]:
			var distances: Array[float] = _hits(faces, header.to_global(Vector3(x, y, .2)), header.to_global(Vector3(x, y, -.2)))
			depths.append(distances[-1] - distances[0] if distances.size() >= 2 else 0.0)
	return depths

func _ink_gaps(header: Node3D) -> Array[float]:
	var gaps: Array[float] = []
	var faces: PackedVector3Array = _faces(header)
	for ink: Label3D in header.find_children("*", "Label3D", true, false):
		var width: float = ink.font.get_string_size(ink.text, HORIZONTAL_ALIGNMENT_LEFT, -1, ink.font_size).x * ink.pixel_size
		var height: float = ink.font.get_height(ink.font_size) * ink.pixel_size
		var normal: Vector3 = ink.global_basis.z.normalized()
		for x: float in [-.5, 0.0, .5]:
			for y: float in [-.5, 0.0, .5]:
				var at: Vector3 = ink.to_global(Vector3(x * width, y * height, 0))
				gaps.append(_first(faces, at + normal * .003, at - normal * .06) - .003)
	return gaps

func _mount_contacts(shelter: Node3D, header: Node3D) -> Array[float]:
	var gaps: Array[float] = []
	var source: PackedVector3Array = _source_faces(shelter)
	for name_value: String in ["RoofMount_Left", "RoofMount_Right"]:
		var mount := header.get_node_or_null(name_value) as Node3D
		var anchor: MeshInstance3D = mount.get_node_or_null("EaveAnchor") as MeshInstance3D if mount != null else null
		if anchor == null: return []
		var anchor_faces: PackedVector3Array = _faces(anchor)
		var normal: Vector3 = anchor.global_basis.z.normalized()
		for x: float in [-.025, .025]:
			for y: float in [-.022, .022]:
				var origin: Vector3 = anchor.to_global(Vector3(x, y, -.04))
				var front: Vector3 = origin + normal * .08
				var anchor_back: float = _first(anchor_faces, origin, front)
				var source_front: float = .08 - _first(source, front, origin)
				gaps.append(anchor_back - source_front)
	return gaps

func _occupied(mesh_faces: Array[PackedVector3Array], at: Vector3) -> bool:
	var end: Vector3 = at + Vector3(.813, .291, .503).normalized() * 5.0
	for faces: PackedVector3Array in mesh_faces:
		if _hits(faces, at, end).size() % 2 == 1: return true
	return false

func _continuous_mounts(header: Node3D) -> bool:
	var parts: Array[PackedVector3Array] = []
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(header): parts.append(_faces(mesh))
	for name_value: String in ["RoofMount_Left", "RoofMount_Right"]:
		var mount := header.get_node_or_null(name_value) as Node3D
		if mount == null: return false
		# Follow the actual load path from the eave anchor, through the bent arm,
		# through its rear strap, and into the casing. A cosmetic bracket fails.
		for step: int in 21:
			var at: Vector3 = mount.to_global(Vector3(0, -.025, -.002 + float(step) * .004))
			if not _occupied(parts, at): return false
	return true

func _range(values: Array[float], minimum: float, maximum: float, count: int) -> bool:
	if values.size() != count: return false
	for value: float in values:
		if not is_finite(value) or value < minimum or value > maximum: return false
	return true

func run() -> void:
	var shelter := main.world.get_node("R06") as Node3D
	var header := shelter.get_node("StopName") as Node3D
	# Exact old source recipe, measured before changing TransitStop. Run the
	# same geometric checks first so the old screenshot defect cannot pass.
	var predecessor: Node3D = ClearSignage.plate(shelter, "RejectedStopNameFixture", Vector2(2.4, .28), Vector3(0, 2.13, 1.02), 0, Color(.19, .40, .36))
	predecessor.add_child(ClearSignage.label("晴町  HARUMACHI", Vector3(0, 0, .02), 0, .21, Color(.99, .96, .83)))
	var old_depths: Array[float] = _thickness(predecessor)
	var old_gaps: Array[float] = _ink_gaps(predecessor)
	check("the previous 18 mm sheet fails the solid sign casing depth check", not _range(old_depths, .045, .11, 9), str(old_depths))
	check("the previous text floats more than 2 mm in front of its sheet", not _range(old_gaps, -.0003, .002, 9), str(old_gaps))
	check("the previous sign fails the real eave connection check", not _range(_mount_contacts(shelter, predecessor), -.004, .002, 8) and not _continuous_mounts(predecessor))
	predecessor.free()

	var depths: Array[float] = _thickness(header)
	var gaps: Array[float] = _ink_gaps(header)
	var contacts: Array[float] = _mount_contacts(shelter, header)
	check("the casing is 45–110 mm deep at nine actual triangle sections", _range(depths, .045, .11, 9), str(depths))
	check("all station lettering lies within 2 mm of its supporting face", _range(gaps, -.0003, .002, 18), str(gaps))
	check("both mounting plates contact the existing eave at all four bearing samples", _range(contacts, -.004, .002, 8), str(contacts))
	check("both bent mounting arms form a continuous physical path into the casing", _continuous_mounts(header))

	var normal: Vector3 = header.global_basis.z.normalized()
	var painted := true
	var caption := ""
	for ink: Label3D in header.find_children("*", "Label3D", true, false):
		caption += ink.text
		painted = painted and ink.shaded and not ink.no_depth_test and ink.billboard == BaseMaterial3D.BILLBOARD_DISABLED and ink.global_basis.z.normalized().dot(normal) > .999
	check("station name and romanization use shaded surface-aligned lettering", painted and caption.contains("晴町") and caption.contains("HARUMACHI"))
	var local_box: AABB = shelter.global_transform.affine_inverse() * header.global_transform * WorldBuilder.local_aabb(header)
	check("the sign and its fixings leave at least two metres below the eave", local_box.position.y >= 2.0 and header.find_children("*", "CollisionObject3D", true, false).is_empty(), str(local_box))
	var timetable: Node3D = shelter.get_node("Timetable")
	var route: Node3D = shelter.get_node("RouteMap")
	var route_text := ""
	for panel: Node3D in [timetable, route]:
		for line: Label3D in panel.find_children("*", "Label3D", true, false): route_text += line.text
	check("route destinations and all departure times remain on the original timetable", route_text.contains("晴町 → 青海駅") and route_text.contains("08:10") and route_text.contains("10:40") and route_text.contains("13:20") and route_text.contains("16:50") and route_text.contains("18:30") and route_text.contains("山下橋"))

	var left_mount := header.get_node_or_null("RoofMount_Left") as Node3D
	var rejects_detachment := false
	if left_mount != null:
		var mount_original: Vector3 = left_mount.position
		left_mount.position.z += .03
		rejects_detachment = not _range(_mount_contacts(shelter, header), -.004, .002, 8)
		left_mount.position = mount_original
	check("moving an eave fixing 30 mm outward fails the support test", rejects_detachment)
	var arm := header.get_node_or_null("RoofMount_Left/BentArm") as MeshInstance3D
	var rejects_missing_arm := false
	if arm != null:
		var arm_original: Vector3 = arm.position
		arm.position.x += .20
		rejects_missing_arm = not _continuous_mounts(header)
		arm.position = arm_original
	check("moving a connecting arm aside exposes a broken physical load path", rejects_missing_arm)

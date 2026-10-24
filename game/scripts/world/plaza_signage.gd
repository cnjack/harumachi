extends RefCounted
## Notices are attached to rendered surfaces; outdoor activity boards have a real use.
const NOTICE_ARTWORK: Texture2D = preload("res://assets/ui/collection/col_poster.jpg")
const NOTICE_ARTWORK_SIDE := .32
const NOTE_TITLES := {
	"preparing": ["夏祭准备", "灯笼试挂"],
	"festival": ["夏祭入口", "树下集合"],
	"reunion": ["树下晚会", "围坐聊天"],
}

static func make_poster(world: WorldBuilder) -> Node3D:
	var board: Node3D = world.get_node("P02")
	var centre := Vector2(.36, 1.18)
	var extent := Vector2(.58, .82)
	var depth: float = _mount_depth(board, centre, extent)
	var root := Node3D.new()
	root.name = "Poster"
	board.add_child(root)
	root.position = Vector3(centre.x, centre.y, depth + .003)
	var paper := MeshInstance3D.new()
	paper.name = "PostedPaper"
	var shape := QuadMesh.new()
	shape.size = extent
	paper.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.98, .94, .82)
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	paper.material_override = material
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(paper)
	var illustration := MeshInstance3D.new()
	illustration.name = "NoticeIllustration"
	illustration.mesh = QuadMesh.new()
	illustration.position = Vector3(0, .035, .0015)
	var ink := StandardMaterial3D.new()
	ink.roughness = 1.0
	ink.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	illustration.material_override = ink
	illustration.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(illustration)
	set_illustration(root, NOTICE_ARTWORK)
	# Only the named illustration and caption change. The paper, heading, rules
	# and fixings remain in place when the final photograph is posted.
	var caption: Label3D = ClearSignage.label("周六小集市\n傍晚在庭院见", Vector3(0, -.245, .002), 0, .045, Color(.21, .30, .25))
	caption.name = "NoticeCaption"
	caption.shaded = true
	ClearSignage.fit(caption, Vector2(.52, .17), .01)
	root.add_child(caption)
	var details := Node3D.new()
	details.name = "PaperFixings"
	root.add_child(details)
	var heading: Label3D = ClearSignage.label("晴町告示", Vector3(0, .28, .002), 0, .070, Color(.21, .30, .25))
	heading.name = "PrintedHeading"
	heading.shaded = true
	details.add_child(heading)
	for y: float in [-.14, .21]:
		var rule := MeshInstance3D.new()
		rule.name = "PrintedRule_%d" % roundi(y * 100.0)
		var line := BoxMesh.new()
		line.size = Vector3(.44, .002, .001)
		rule.mesh = line
		rule.material_override = JapaneseArchitecture._flat(Color(.38, .46, .34))
		rule.position = Vector3(0, y, .001)
		rule.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		details.add_child(rule)
	for x: float in [-.25, .25]:
		var pin := MeshInstance3D.new()
		pin.name = "PaperPin_%d" % roundi(x * 100.0)
		var head := SphereMesh.new()
		head.radius = .006
		head.height = .006
		head.radial_segments = 8
		head.rings = 4
		pin.mesh = head
		pin.material_override = JapaneseArchitecture._flat(Color(.29, .32, .29))
		pin.position = Vector3(x, .37, .003)
		details.add_child(pin)
	root.visible = false
	return root

static func set_illustration(poster: Node3D, texture: Texture2D) -> void:
	var illustration: MeshInstance3D = poster.get_node_or_null("NoticeIllustration") as MeshInstance3D
	if illustration == null or texture == null: return
	var material: StandardMaterial3D = illustration.material_override as StandardMaterial3D
	var shape: QuadMesh = illustration.mesh as QuadMesh
	if material == null or shape == null: return
	material.albedo_texture = texture
	# Keep a landscape or portrait photograph inside the same square image area
	# without stretching its faces or covering the text below it.
	var pixels := Vector2(texture.get_width(), texture.get_height())
	shape.size = pixels * (NOTICE_ARTWORK_SIDE / maxf(pixels.x, pixels.y))

static func _mount_depth(board: Node3D, centre: Vector2, extent: Vector2) -> float:
	var front: float = surface_envelope(board, centre, extent)
	# Measured P02 front depth. The geometry regression catches a changed source.
	return front if is_finite(front) else .080

static func surface_envelope(board: Node3D, centre: Vector2, extent: Vector2, excluded: Node = null) -> float:
	# Clip every supporting triangle to the paper footprint. Sparse centre/edge
	# rays miss small raised fragments on this irregular generated noticeboard.
	var front: float = -INF
	var left: float = centre.x - extent.x * .5
	var right: float = centre.x + extent.x * .5
	var bottom: float = centre.y - extent.y * .5
	var top: float = centre.y + extent.y * .5
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(board):
		if excluded != null and (mesh == excluded or excluded.is_ancestor_of(mesh)): continue
		var transform: Transform3D = board.global_transform.affine_inverse() * mesh.global_transform
		var faces: PackedVector3Array = transform * mesh.mesh.get_faces()
		for index: int in range(0, faces.size(), 3):
			var a: Vector3 = faces[index]
			var b: Vector3 = faces[index + 1]
			var c: Vector3 = faces[index + 2]
			if maxf(a.x, maxf(b.x, c.x)) < left or minf(a.x, minf(b.x, c.x)) > right: continue
			if maxf(a.y, maxf(b.y, c.y)) < bottom or minf(a.y, minf(b.y, c.y)) > top: continue
			var clipped: Array[Vector3] = [a, b, c]
			clipped = _clip_surface(clipped, 0, left, false)
			clipped = _clip_surface(clipped, 0, right, true)
			clipped = _clip_surface(clipped, 1, bottom, false)
			clipped = _clip_surface(clipped, 1, top, true)
			for point: Vector3 in clipped: front = maxf(front, point.z)
	return front

static func _clip_surface(polygon: Array[Vector3], axis: int, boundary: float, keep_less: bool) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if polygon.is_empty(): return result
	var previous: Vector3 = polygon[-1]
	var was_inside: bool = previous[axis] <= boundary if keep_less else previous[axis] >= boundary
	for point: Vector3 in polygon:
		var inside: bool = point[axis] <= boundary if keep_less else point[axis] >= boundary
		if inside != was_inside:
			result.append(previous.lerp(point, (boundary - previous[axis]) / (point[axis] - previous[axis])))
		if inside: result.append(point)
		previous = point
		was_inside = inside
	return result

static func make_activity_note(world: WorldBuilder, parent: Node3D, at: Vector3, index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "ActivityNote_%d" % index
	parent.add_child(root)
	root.position = at
	root.rotation.y = PI
	var assembly: Node3D = ModularProps.part(world, root, "MS14_event_board", "SignAssembly", Vector3.ZERO)
	assembly.scale = Vector3(.68, .76, .9)
	var body: StaticBody3D = WorldBuilder.add_box_collider(assembly, .98, WorldBuilder.L_SOLID)
	body.set_meta("model_part", true)
	WorldBuilder.rest_on_terrain(root, .002, .004)
	root.visible = false
	return root

static func set_note_title(root: Node3D, context: String, index: int) -> void:
	if not NOTE_TITLES.has(context): return
	var title: String = NOTE_TITLES[context][index]
	var face: Node3D = root.find_child("EventBoard", true, false) as Node3D
	if face == null or str(face.get_meta("engraved_text", "")) == title: return
	ModularProps.engrave(face, title, Vector4(0, .12, .94, .14), true, .80)

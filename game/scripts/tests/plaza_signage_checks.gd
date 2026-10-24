extends RefCounted
## Test the rendered support triangles, not a tag claiming that a sign is attached.
var t: Node
var main: Node
var _support_faces: PackedVector3Array = PackedVector3Array()

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("PLAZA_SIGNAGE", label, ok, detail)

func _remember_support(root: Node3D, excluded: Node = null) -> void:
	_support_faces.clear()
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		if excluded != null and (mesh == excluded or excluded.is_ancestor_of(mesh)): continue
		_support_faces.append_array(mesh.global_transform * mesh.mesh.get_faces())

func _first_hit(from: Vector3, to: Vector3) -> float:
	var distance: float = INF
	for index: int in range(0, _support_faces.size(), 3):
		var intersection: Variant = Geometry3D.segment_intersects_triangle(from, to, _support_faces[index], _support_faces[index + 1], _support_faces[index + 2])
		if intersection is Vector3: distance = minf(distance, from.distance_to(intersection))
	return distance

func _solid(root: Node) -> bool:
	for body: StaticBody3D in root.find_children("*", "StaticBody3D", true, false):
		if body.collision_layer != 0: return true
	return false

func _has_supported_caption(frame: Node3D) -> bool:
	var face: MeshInstance3D = frame.find_child("EventBoard", true, false) as MeshInstance3D
	if face == null: return false
	var ink: ShaderMaterial = face.get_active_material(0) as ShaderMaterial
	if ink == null or not ink.get_shader_parameter("engraving_enabled") or not ink.get_shader_parameter("engraving_two_sided"): return false
	var mask: Texture2D = ink.get_shader_parameter("engraving_mask") as Texture2D
	if mask == null or mask.get_width() < 512: return false
	var rect: Vector4 = ink.get_shader_parameter("engraving_rect")
	_remember_support(face)
	for side: float in [-1.0, 1.0]:
		var outward: Vector3 = face.global_basis.z.normalized() * side
		for x: float in [-.45, .45]:
			for y: float in [-.45, .45]:
				var point: Vector3 = face.to_global(Vector3(rect.x + x * rect.z, rect.y + y * rect.w, side * .024))
				if _first_hit(point + outward * .01, point - outward * .05) > .025: return false
	return true

func _illustration_texture(poster: Node3D) -> Texture2D:
	var mesh: MeshInstance3D = poster.get_node_or_null("NoticeIllustration") as MeshInstance3D
	if mesh == null: return null
	var material: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	return material.albedo_texture if material != null else null

func _pixels(texture: Texture2D) -> Image:
	if texture == null: return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty(): return null
	if image.is_compressed() and image.decompress() != OK: return null
	return image

func _has_illustration(poster: Node3D) -> bool:
	var image: Image = _pixels(_illustration_texture(poster))
	if image == null or image.get_width() < 64 or image.get_height() < 64: return false
	var minimum := Vector3.ONE
	var maximum := Vector3.ZERO
	for x: int in range(5):
		for y: int in range(5):
			var pixel: Color = image.get_pixel(roundi(float(x) * float(image.get_width() - 1) / 4.0), roundi(float(y) * float(image.get_height() - 1) / 4.0))
			if pixel.a < .95: return false
			var rgb := Vector3(pixel.r, pixel.g, pixel.b)
			minimum = minimum.min(rgb)
			maximum = maximum.max(rgb)
	return (maximum - minimum).length() > .3

func _illustration_supported(poster: Node3D) -> bool:
	var illustration: MeshInstance3D = poster.get_node_or_null("NoticeIllustration") as MeshInstance3D
	var paper: MeshInstance3D = poster.get_node_or_null("PostedPaper") as MeshInstance3D
	var lower: MeshInstance3D = poster.get_node_or_null("PaperFixings/PrintedRule_-14") as MeshInstance3D
	var upper: MeshInstance3D = poster.get_node_or_null("PaperFixings/PrintedRule_21") as MeshInstance3D
	if illustration == null or paper == null or lower == null or upper == null: return false
	var bounds: AABB = illustration.get_aabb()
	var sheet: AABB = paper.get_aabb()
	if bounds.size.x <= 0 or bounds.size.y <= 0 or maxf(bounds.size.x, bounds.size.y) > .3201: return false
	var normal: Vector3 = illustration.global_basis.z.normalized()
	if normal.dot(paper.global_basis.z.normalized()) < .999: return false
	_remember_support(paper)
	for x: float in [-.5, 0., .5]:
		for y: float in [-.5, 0., .5]:
			var point: Vector3 = illustration.to_global(Vector3(x * bounds.size.x, y * bounds.size.y, 0))
			var local: Vector3 = paper.to_local(point)
			var on_notice: Vector3 = poster.to_local(point)
			if local.x < sheet.position.x + .02 or local.x > sheet.end.x - .02: return false
			if local.y < sheet.position.y + .02 or local.y > sheet.end.y - .02: return false
			if on_notice.y < lower.position.y + .01 or on_notice.y > upper.position.y - .01: return false
			var gap: float = _first_hit(point + normal * .001, point - normal * .02) - .001
			if gap < .0005 or gap > .003: return false
	return true

func _poster_artwork() -> void:
	var poster: Node3D = main.world.poster
	var lifecycle: Node = main.world.lifecycle
	var paper: MeshInstance3D = poster.get_node("PostedPaper") as MeshInstance3D
	var paper_material: StandardMaterial3D = paper.material_override as StandardMaterial3D
	var heading: Label3D = poster.get_node("PaperFixings/PrintedHeading") as Label3D
	var caption: Label3D = poster.get_node("NoticeCaption") as Label3D
	var paper_texture: Texture2D = paper_material.albedo_texture
	var paper_color: Color = paper_material.albedo_color
	var heading_text: String = heading.text
	var original_day: int = GameState.day
	var original_collection: Dictionary = GameState.collection.duplicate(true)
	var original_directory: String = SaveDB.directory
	var test_directory: String = original_directory.path_join("plaza_photo_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(test_directory)
	SaveDB.directory = test_directory
	GameState.day = 2
	GameState.collection.erase("col_photo_new")
	lifecycle.sync_state()
	var default_texture: Texture2D = _illustration_texture(poster)
	var photo: Image = Image.create(128, 80, false, Image.FORMAT_RGBA8)
	photo.fill(Color(.16, .42, .72))
	photo.fill_rect(Rect2i(64, 0, 64, 80), Color(.90, .45, .20))
	# Recreate the two observed prior states using the same real sheet geometry:
	# no image node, followed by the previous arbitrary-child texture replacement.
	var legacy: Node3D = poster.duplicate() as Node3D
	var old_art: Node = legacy.get_node_or_null("NoticeIllustration")
	if old_art != null: old_art.free()
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(legacy):
		if mesh.material_override != null: mesh.material_override = mesh.material_override.duplicate() as Material
	var old_blank_rejected: bool = not _has_illustration(legacy)
	for child: Node in legacy.get_children():
		if child is MeshInstance3D:
			(child.material_override as StandardMaterial3D).albedo_texture = ImageTexture.create_from_image(photo)
	var old_paper: MeshInstance3D = legacy.get_node("PostedPaper") as MeshInstance3D
	var old_replacement_rejected: bool = (old_paper.material_override as StandardMaterial3D).albedo_texture != paper_texture
	check("image regressions reject the old blank sheet and whole-sheet photo replacement", old_blank_rejected and old_replacement_rejected)
	legacy.free()
	check("posted notice contains a real opaque multicolour illustration", _has_illustration(poster))
	check("illustration fits between the rules with margins and real paper support", _illustration_supported(poster))
	var written: Error = photo.save_png(GameState.photo_path())
	GameState.day = 18
	GameState.collection["col_photo_new"] = {"day":18}
	lifecycle.sync_state()
	var posted: Image = _pixels(_illustration_texture(poster))
	var photo_matches: bool = posted != null and posted.get_size() == photo.get_size()
	if photo_matches:
		photo_matches = posted.get_pixel(8, 8).r < .3 and posted.get_pixel(8, 8).b > .6 and posted.get_pixel(120, 8).r > .8
	check("final photo changes the illustration while paper and title remain intact", written == OK and photo_matches and paper_material.albedo_texture == paper_texture and paper_material.albedo_color == paper_color and heading.text == heading_text and caption.text.contains("照片"))
	var illustration: MeshInstance3D = poster.get_node_or_null("NoticeIllustration") as MeshInstance3D
	var photo_fits: bool = illustration != null and _illustration_supported(poster)
	if photo_fits:
		var photo_bounds: AABB = illustration.get_aabb()
		photo_fits = absf(photo_bounds.size.x / photo_bounds.size.y - 1.6) < .001
	check("landscape photograph retains its aspect ratio inside the image area", photo_fits)
	GameState.collection.erase("col_photo_new")
	lifecycle.sync_state()
	check("returning to an unphotographed state restores the original illustration", default_texture != null and _illustration_texture(poster) == default_texture and _has_illustration(poster) and _illustration_supported(poster))
	DirAccess.remove_absolute(GameState.photo_path())
	GameState.collection["col_photo_new"] = {"day":18}
	lifecycle.sync_state()
	check("a missing photo file preserves the illustration instead of blanking the notice", default_texture != null and _illustration_texture(poster) == default_texture and _has_illustration(poster) and paper_material.albedo_texture == paper_texture)
	SaveDB.directory = original_directory
	GameState.day = original_day
	GameState.collection = original_collection
	lifecycle.sync_state()
	DirAccess.remove_absolute(test_directory)

func _activity_notes() -> void:
	var view: WorkroomView = main.world.interiors.workroom.get_node("WorkroomProject")
	var frames: Node3D = main.world.get_node("CommunityActivityNotes")
	GameState.flags.summer_workshop = {}
	GameState.flags.summer_gathering = {}
	GameState.quests.Q13 = {"state":"locked", "step":0}
	GameState.day = 2
	view.sync_state()
	main.world.set_region("farm")
	main.world.set_region("town")
	var dormant: bool = true
	for frame: Node3D in frames.get_children(): dormant = dormant and not frame.is_visible_in_tree() and not _solid(frame)
	check("ordinary return from the farm cannot resurrect the two blank activity frames", dormant)
	GameState.day = 16
	view.sync_state()
	dormant = true
	for frame: Node3D in frames.get_children(): dormant = dormant and not frame.is_visible_in_tree() and not _solid(frame)
	check("a calendar date alone does not erect signs before any preparation task", dormant)
	GameState.day = 17
	GameState.minute = 19.0 * 60.0
	view.sync_state()
	for frame: Node3D in frames.get_children():
		check("%s appears with collision only for a real event" % frame.name, frame.is_visible_in_tree() and _solid(frame))
		check("%s has readable ink on actual front and rear board triangles" % frame.name, _has_supported_caption(frame))
	GameState.day = 18
	view.sync_state()
	dormant = true
	for frame: Node3D in frames.get_children(): dormant = dormant and not frame.is_visible_in_tree() and not _solid(frame)
	check("both activity boards and collisions are stored after the event", dormant)
	GameState.day = 20
	SummerGathering.state().reunion_day = 20
	view.sync_state()
	for frame: Node3D in frames.get_children():
		check("%s is reused with supported lettering for an agreed reunion" % frame.name, frame.is_visible_in_tree() and _has_supported_caption(frame))

func run() -> void:
	var saved: Dictionary = GameState.to_dict().duplicate(true)
	GameState.day = 2
	GameState.minute = 10.5 * 60.0
	GameState.phase = "prep"
	GameState.clock_paused = true
	main.world.set_region("town")
	GameState.quests.Q04 = {"state":"done", "step":3}
	main.world.lifecycle.sync_state()
	var board: Node3D = main.world.get_node("P02")
	var poster: Node3D = main.world.poster
	var paper: MeshInstance3D
	for child: Node in poster.get_children():
		if child is MeshInstance3D:
			paper = child as MeshInstance3D
			break
	_remember_support(board, poster)
	var gaps: Array[float] = []
	var mounted: bool = paper != null
	var occluded: bool = paper != null
	if paper != null:
		var bounds: AABB = paper.get_aabb()
		var normal: Vector3 = paper.global_basis.z.normalized()
		for x: float in [-.45, 0.0, .45]:
			for y: float in [-.45, 0.0, .45]:
				var point: Vector3 = paper.to_global(Vector3(x * bounds.size.x, y * bounds.size.y, 0))
				var gap: float = _first_hit(point + normal * .002, point - normal * 1.5) - .002
				gaps.append(gap)
				mounted = mounted and gap >= -.001 and gap <= .025
				occluded = occluded and _first_hit(point - normal * .40, point) < .398
		check("posted sheet faces the same street side as the noticeboard", normal.dot(board.global_basis.z.normalized()) > .999)
		var centre: Vector3 = board.to_local(paper.global_position)
		var envelope: float = load("res://scripts/world/plaza_signage.gd").surface_envelope(board, Vector2(centre.x, centre.y), Vector2(bounds.size.x, bounds.size.y), poster)
		check("no raised board triangle penetrates any part of the posted sheet", centre.z - envelope >= .001, "paper=%f board_front=%f" % [centre.z, envelope])
	check("poster centre and all edges sit within 25 mm of actual P02 front triangles", mounted, str(gaps))
	check("the solid noticeboard occludes the whole poster from its rear", occluded)
	check("poster moves with the noticeboard instead of retaining a stale world position", board.is_ancestor_of(poster))
	check("completed posting still displays its notice", poster.is_visible_in_tree())
	_poster_artwork()
	GameState.quests.Q04 = {"state":"locked", "step":0}
	GameState.quests.Q05 = {"state":"locked", "step":0}
	GameState.quests.Q01 = {"state":"locked", "step":0}
	GameState.flags.summer_space = {"version":1, "phase":"invitation", "optional_wood":0}
	main.world.lifecycle.sync_state()
	var sign: Node3D = main.world.get_node("BuildSign")
	check("an unused planning sign is stored with its collision disabled", not sign.visible and not _solid(sign))
	_activity_notes()
	GameState.from_dict(saved)
	main.world.lifecycle.sync_state()
	(main.world.interiors.workroom.get_node("WorkroomProject") as WorkroomView).sync_state()

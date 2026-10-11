extends Node
## Real F8/Esc entry, viewport PNGs only. Never calls the OS Pictures writer.
var main: Node
var output := ""
var records: Array[Dictionary] = []


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	if output.is_empty():
		push_error("photo_context_probe requires --out=<isolated evidence directory>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	GameState.new_game()
	GameState.flags["arrival_home"] = true
	GameState.flags["house_key"] = true
	GameState.quests["Q00"] = {"state":"done", "step":GameState.quests_db["Q00"].steps.size()}
	GameState.clock_paused = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.ui.instant = true
	main.ui.auto = false
	run.call_deferred()


func frames(count: int) -> void:
	for index: int in count: await get_tree().process_frame


func tap(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(1)


func expected_bounds(context: String) -> Rect2:
	if context in ["store", "bakery", "workroom"]:
		var spec: Dictionary = InteriorBuilder.SPECS[context]
		var origin: Vector3 = spec.origin
		var size: Vector2 = spec.size
		return Rect2(Vector2(origin.x, origin.z) - size * .5, size).grow(7.0)
	if context == "house":
		var bounds := Rect2()
		for index: int in HouseBuilder.ROOMS.size():
			var room: Dictionary = HouseBuilder.ROOMS[index]
			var rect: Array = room.rect
			var piece := Rect2(Vector2(float(rect[0]), float(rect[1])), Vector2(float(rect[2]) - float(rect[0]), float(rect[3]) - float(rect[1])))
			bounds = piece if index == 0 else bounds.merge(piece)
		bounds.position += Vector2(HouseBuilder.ORIGIN.x, HouseBuilder.ORIGIN.z)
		return bounds.grow(7.0)
	return Rect2(-58, -35, 106, 125) if context == "town" else Rect2(FarmBuilder.ORIGIN.x - 35, -40, 185, 110)


func within(position: Vector3, bounds: Rect2) -> bool:
	return position.x >= bounds.position.x - .001 and position.x <= bounds.end.x + .001 and position.z >= bounds.position.y - .001 and position.z <= bounds.end.y + .001 and position.y >= .549 and position.y <= 24.001


func prepare(context: String) -> void:
	if main.in_room:
		if main.room_kind == "house": await main.exit_room()
		else: await main.exit_interior()
	if main.world.region == "farm": await main.leave_farm()
	if context == "house": await main.enter_room()
	elif context in ["store", "bakery", "workroom"]: await main.enter_interior(context)
	elif context == "farm": await main.go_farm()
	main.player.velocity = Vector3.ZERO
	await frames(12)


func shot(filename: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var picture: Image = get_viewport().get_texture().get_image()
	var error: Error = picture.save_png(output.path_join(filename))
	return {"file":filename,"sha256":FileAccess.get_sha256(output.path_join(filename)),"save_error":error}


func home_garden_card() -> MeshInstance3D:
	# The material exists in old production, so the same harness can prove the
	# former free-camera leak without relying on a new property or helper.
	for child: Node in main.world.house.get_children():
		if not child is MeshInstance3D: continue
		var candidate: MeshInstance3D = child as MeshInstance3D
		if candidate.mesh == null: continue
		var material: StandardMaterial3D = candidate.get_active_material(0) as StandardMaterial3D
		if candidate.mesh is QuadMesh and material != null and material.albedo_texture != null and material.albedo_texture.resource_path.ends_with("/card_garden.jpg"):
			return candidate
	return null


func backdrop_state(card: MeshInstance3D) -> Dictionary:
	return {"exists": card != null, "visible": card.visible if card != null else false,
		"visible_in_tree": card.is_visible_in_tree() if card != null else false}


func run() -> void:
	await frames(30)
	var garden: MeshInstance3D = home_garden_card()
	var garden_transform: Transform3D = garden.global_transform if garden != null else Transform3D.IDENTITY
	var garden_material: Material = garden.get_active_material(0) if garden != null else null
	for context: String in ["house", "store", "bakery", "workroom", "farm", "town"]:
		await prepare(context)
		var bounds: Rect2 = expected_bounds(context)
		var old_camera: Camera3D = get_viewport().get_camera_3d()
		var old_position: Vector3 = old_camera.global_position
		var old_pause: bool = GameState.clock_paused
		var old_actor: bool = main.player.model_root.visible
		var old_marker: bool = main.marker.visible
		var old_ambient: bool = main.ui.ambient_layer.visible
		var old_tags: Dictionary = {}
		for id: String in main.npcs: old_tags[id] = main.npcs[id].tag.visible
		var normal_backdrop: Dictionary = backdrop_state(garden)
		await tap(KEY_F8)
		var first_position: Vector3 = main.photo.camera.global_position
		var entry_ok: bool = main.photo.active and get_viewport().get_camera_3d() == main.photo.camera and first_position.distance_to(old_position) < .05 and within(first_position, bounds)
		var first_png: Dictionary = await shot(context + "_first_frame.png")
		var photo_backdrop: Dictionary = backdrop_state(garden)
		# Explicit boundary fixture, not a claim of native camera locomotion.
		# F8/Esc above/below still pass through the real buffered input dispatcher.
		main.photo.camera.global_position = Vector3(bounds.end.x + 20, 30, bounds.end.y + 20)
		main.photo._process(0.0)
		var clipped_position: Vector3 = main.photo.camera.global_position
		var boundary_ok: bool = within(clipped_position, bounds) and absf(clipped_position.x - bounds.end.x) < .001 and absf(clipped_position.z - bounds.end.y) < .001
		var boundary_png: Dictionary = await shot(context + "_boundary_fixture.png")
		var boundary_backdrop: Dictionary = backdrop_state(garden)
		await tap(KEY_ESCAPE)
		await frames(2)
		var restored_backdrop: Dictionary = backdrop_state(garden)
		var restored: bool = not main.photo.active and get_viewport().get_camera_3d() == old_camera and GameState.clock_paused == old_pause and main.player.model_root.visible == old_actor and main.marker.visible == old_marker and main.ui.ambient_layer.visible == old_ambient and not GameState._ui_locks.has("photo")
		for id: String in old_tags: restored = restored and main.npcs[id].tag.visible == old_tags[id]
		var unchanged_backdrop: bool = garden != null and garden.global_transform == garden_transform and garden.get_active_material(0) == garden_material
		var backdrop_ok: bool = context != "house" or unchanged_backdrop and normal_backdrop.visible_in_tree and not photo_backdrop.visible and not boundary_backdrop.visible and restored_backdrop.visible_in_tree
		var passed: bool = entry_ok and boundary_ok and restored and backdrop_ok and int(first_png.save_error) == OK and int(boundary_png.save_error) == OK
		records.append({"context":context,"passed":passed,"entry_preserved":entry_ok,"boundary_correct":boundary_ok,"restored":restored,"backdrop_policy_passed":backdrop_ok,"backdrop_geometry_material_unchanged":unchanged_backdrop,
			"backdrop":{"normal":normal_backdrop,"photo":photo_backdrop,"boundary":boundary_backdrop,"restored":restored_backdrop},
			"expected_rect":[bounds.position.x,bounds.position.y,bounds.end.x,bounds.end.y],"before_position":old_position,"first_position":first_position,"clipped_position":clipped_position,"photos":[first_png,boundary_png]})
		print("PHOTO_CONTEXT ", JSON.stringify(records[-1]))
	# A separate visual reference deliberately looks across the staging strip.
	# It is not F8 locomotion evidence and does not alter the six entry checks.
	await prepare("workroom")
	var reference := Camera3D.new()
	reference.name = "PhotoContextDiagnosticReference"
	main.add_child(reference)
	reference.fov = 50.0
	reference.far = 1200.0
	reference.global_position = Vector3(110, 6, 400)
	reference.look_at(Vector3(80, 1.5, 400))
	reference.make_current()
	var reference_png: Dictionary = await shot("workroom_west_reference.png")
	var visible_rooms: Dictionary = {}
	for kind: String in main.world.interiors: visible_rooms[kind] = main.world.interiors[kind].is_visible_in_tree()
	var references: Array[Dictionary] = [{"kind":"diagnostic_reference_not_F8_movement","camera":[110,6,400],"focus":[80,1.5,400],"photo":reference_png,"house_visible":main.world.house.is_visible_in_tree(),"interior_visible":visible_rooms,"backdrop":backdrop_state(garden)}]
	main.rig.cam.make_current()
	reference.queue_free()
	var failed: int = records.filter(func(row: Dictionary): return not row.passed).size()
	var report := {"passed":failed == 0 and int(reference_png.save_error) == OK,"checks":records.size(),"failed":failed,"records":records,"reference_shots":references,"scope":"Actual F8 and Esc with flushed input; first rendered frame and explicit out-of-bounds camera fixture. The normal home painting is preserved, hidden in free photos and restored on Esc. One separate visual reference is not native movement proof. Extreme boundary/reference cameras may show the outside of the existing staging set. Viewport PNGs in the isolated evidence directory; no F12 or OS Pictures write."}
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	get_tree().quit(0 if failed == 0 else 1)

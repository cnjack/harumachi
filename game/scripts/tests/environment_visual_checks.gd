extends RefCounted
## Weather regressions found by comparing the same home camera in six conditions.
var t: Node
var main: Node


func _init(runner: Node) -> void:
	t = runner
	main = runner.main


func check(label: String, ok: bool, detail: String = "") -> void:
	t.check("ENVIRONMENT_VISUAL", label, ok, detail)


func strength(house: HouseBuilder) -> float:
	if house.beams == null or not house.beams.visible:
		return 0.0
	var total: float = 0.0
	for sheet: MeshInstance3D in house.beams.get_children():
		# Count only actual visible rendered triangle sheets with the beam shader.
		var material: ShaderMaterial = sheet.get_active_material(0) as ShaderMaterial
		if not sheet.visible or sheet.mesh == null or sheet.mesh.get_faces().is_empty() or material == null:
			continue
		if material.shader.resource_path != "res://shaders/house_beam.gdshader":
			continue
		total += float(material.get_shader_parameter("strength"))
	return total


func look(hour: float, weather: String) -> void:
	GameState.minute = hour * 60.0
	GameState.weather = weather
	main.world.update_time(GameState.minute, weather, true)


func window_weather(rain: bool) -> bool:
	for kind: String in ["store", "bakery", "workroom"]:
		var room: InteriorBuilder = main.world.interiors[kind]
		var count: int = 0
		for view: MeshInstance3D in room.find_children("SummerView", "MeshInstance3D", true, false):
			var material: ShaderMaterial = view.get_active_material(0) as ShaderMaterial
			if not view.visible or view.mesh == null or view.mesh.get_faces().is_empty() or material == null:
				return false
			var amount: Variant = material.get_shader_parameter("cloud_amount")
			var tint: Variant = material.get_shader_parameter("weather_tint")
			if amount == null or not tint is Vector3:
				return false
			if rain and (float(amount) < .99 or (tint as Vector3).x > .75):
				return false
			if not rain and (not is_zero_approx(float(amount)) or (tint as Vector3).distance_to(Vector3.ONE) > .001):
				return false
			count += 1
		if count == 0:
			return false
	return true


func home_window_weather(rain: bool) -> bool:
	var count: int = 0
	for view: MeshInstance3D in main.world.house.find_children("HomeWindowView", "MeshInstance3D", true, false):
		var material: ShaderMaterial = view.get_active_material(0) as ShaderMaterial
		if material == null or view.mesh == null or view.mesh.get_faces().is_empty():
			return false
		var crop: Variant = material.get_shader_parameter("uv_scale")
		var amount: Variant = material.get_shader_parameter("cloud_amount")
		if not crop is Vector2 or amount == null or not bool(material.get_shader_parameter("front_only")):
			return false
		if (crop as Vector2).x <= 0.0 or (crop as Vector2).y <= 0.0 or not material.get_shader_parameter("view_tex") is Texture2D:
			return false
		if rain and float(amount) < .99 or not rain and not is_zero_approx(float(amount)):
			return false
		count += 1
	return count == 2


func run() -> void:
	var world: WorldBuilder = main.world
	var house: HouseBuilder = world.house
	var original_hour: float = GameState.minute / 60.0
	var original_weather: String = GameState.weather
	var original_phase: String = GameState.phase
	var original_indoor: bool = world.indoor
	var original_public: String = world.public_interior_kind
	var original_position: Vector3 = main.player.global_position
	var original_in_room: bool = main.in_room
	var original_room_kind: String = main.room_kind
	var original_region: String = world.region
	var original_amb_check: float = main._amb_check
	var original_house_room: String = house.current_room
	var original_camera: Dictionary = {"yaw": main.rig.yaw, "pitch": main.rig.pitch, "dist": main.rig.dist, "fixed": main.rig.fixed, "collide": main.rig.collide}
	GameState.phase = "prep"
	world.set_indoor_look(true)
	look(12.0, "sunny")
	var sunny: float = strength(house)
	var sunny_direct_light: float = world.sun.light_energy
	check("sunny window shafts use visible rendered triangles rather than an unused setting", sunny > 1.0 and house.beams.get_child_count() == 10, str(sunny))
	var daytime_lamps: Array[float] = []
	for lamp: OmniLight3D in house.lamps:
		daytime_lamps.append(lamp.light_energy)
	look(12.0, "rain")
	check("a same-hour change to rain removes visible shafts and the actual direct window sunlight", strength(house) == 0.0 and not house.beams.visible and world.sun.light_energy < .001)
	check("rain immediately hides lingering sunlit dust as well as stopping emission", not house.dust.visible and not house.dust.emitting)
	check("every actual public-room window renders overcast weather rather than unchanged blue sunshine", window_weather(true))
	var rainy_home_windows: bool = home_window_weather(true)
	look(12.0, "cloudy")
	var cloudy: float = strength(house)
	check("overcast daylight weakens actual directional sunlight and keeps faint shafts", cloudy > 0.0 and cloudy <= sunny * .25 and world.sun.light_energy <= sunny_direct_light * .35, "sunny=%.3f cloudy=%.3f" % [sunny, cloudy])
	check("overcast sunlit dust follows the actual reduced shaft strength", house.dust.visible and house.dust.emitting and house.dust.amount_ratio <= .25)
	look(12.0, "sunny")
	check("clear weather restores the original rendered shaft strength without a day-night change", absf(strength(house) - sunny) < .0001 and house.dust.visible and house.dust.emitting and is_equal_approx(house.dust.amount_ratio, 1.0))
	check("clear weather restores all three public-room window materials without changing their geometry", window_weather(false))
	check("both house window views change with rain and recover while preserving inward faces and image cropping", rainy_home_windows and home_window_weather(false))
	var unchanged_lamps: bool = true
	for index: int in house.lamps.size():
		unchanged_lamps = unchanged_lamps and is_equal_approx(house.lamps[index].light_energy, daytime_lamps[index])
	check("changing window sunlight preserves the separate daytime lamp state", unchanged_lamps)
	look(21.0, "rain")
	check("night retains warm room lamps while direct shafts and dust stay hidden", strength(house) == 0.0 and not house.dust.visible and house.lamps.all(func(lamp: OmniLight3D): return lamp.light_energy > 1.0))
	var dust_material: StandardMaterial3D = house.dust.draw_pass_1.surface_get_material(0) as StandardMaterial3D
	var round_mote: bool = false
	if dust_material != null and dust_material.albedo_texture is GradientTexture2D:
		# GradientTexture2D is uploaded lazily by the renderer; headless mode has
		# no texture Image. Inspect its radial alpha source and verify native frames.
		var texture: GradientTexture2D = dust_material.albedo_texture as GradientTexture2D
		round_mote = texture.fill == GradientTexture2D.FILL_RADIAL and texture.gradient.sample(0.0).a > .8 and texture.gradient.sample(1.0).a < .01 and texture.fill_from.distance_to(Vector2(.5, .5)) < .001
	check("a close camera sees soft round dust rather than an opaque square billboard", round_mote)
	# Do not let the one-second ambient refresh hide a delayed indoor-rain bug.
	main._amb_check = 100.0
	world.set_region("town")
	look(12.0, "rain")
	main.weather_fx.set_weather("rain", false)
	var outdoor_started: bool = main.weather_fx.rain.visible and main.weather_fx.rain.emitting
	main._put_in_room(HouseBuilder.spawn_point())
	var house_stopped: bool = not main.weather_fx.rain.visible and not main.weather_fx.rain.emitting
	await main.exit_room()
	var house_resumed: bool = main.weather_fx.rain.visible and main.weather_fx.rain.emitting
	await main.enter_interior("store")
	var shop_stopped: bool = not main.weather_fx.rain.visible and not main.weather_fx.rain.emitting
	await main.exit_interior()
	var shop_resumed: bool = main.weather_fx.rain.visible and main.weather_fx.rain.emitting
	check("home and public-room entries stop rain immediately and both exits restore it without a periodic tick", outdoor_started and house_stopped and house_resumed and shop_stopped and shop_resumed, "outside=%s home=%s/%s shop=%s/%s" % [outdoor_started, house_stopped, house_resumed, shop_stopped, shop_resumed])
	var restored_public_light: bool = true
	for kind: String in ["store", "bakery", "workroom"]:
		await main.enter_interior(kind)
		var normal_sun: Vector3 = world.sun.rotation_degrees
		var doorway: Vector3 = main.player.global_position
		main._put_in_room(doorway)
		restored_public_light = restored_public_light and world.public_interior_kind == kind and world.sun.rotation_degrees.distance_to(normal_sun) < .001 and normal_sun.distance_to(Vector3(-33, 110, 0)) < .001
	check("restoring any public interior retains its normal window-light direction and room identity", restored_public_light)
	await lake_ground_checks()
	await backdrop_ground_checks()
	await living_carrier_checks()
	await living_location_checks()
	await upper_bark_camera_check()
	await continuous_ribbon_check()
	await yard_weather_check()
	await public_house_visibility_check()
	await photo_context_check()
	GameState.phase = original_phase
	GameState.minute = original_hour * 60.0
	GameState.weather = original_weather
	main._amb_check = original_amb_check
	main.in_room = original_in_room
	main.room_kind = original_room_kind
	GameState.player_in_room = original_in_room
	main.player.global_position = original_position
	world.set_region(original_region)
	house.update_cutaway(original_house_room, false)
	world.set_indoor_look(original_indoor, original_public)
	world.update_time(GameState.minute, GameState.weather, true)
	if main.has_method("_sync_weather"):
		main.call("_sync_weather")
	else:
		main.weather_fx.set_weather(original_weather, original_in_room)
	main.rig.yaw = original_camera.yaw
	main.rig.pitch = original_camera.pitch
	main.rig.dist = original_camera.dist
	main.rig.fixed = original_camera.fixed
	main.rig.collide = original_camera.collide
	main.rig.snap()
	main.update_npcs(true)


func photo_context_bounds(context: String) -> Rect2:
	if context in ["store", "bakery", "workroom"]:
		var spec: Dictionary = InteriorBuilder.SPECS[context]
		var origin: Vector3 = spec.origin
		var size: Vector2 = spec.size
		return Rect2(Vector2(origin.x, origin.z) - size * .5, size).grow(7.0)
	if context == "house":
		var bounds := Rect2()
		for index: int in HouseBuilder.ROOMS.size():
			var rect: Array = HouseBuilder.ROOMS[index].rect
			var piece := Rect2(Vector2(float(rect[0]), float(rect[1])), Vector2(float(rect[2]) - float(rect[0]), float(rect[3]) - float(rect[1])))
			bounds = piece if index == 0 else bounds.merge(piece)
		bounds.position += Vector2(HouseBuilder.ORIGIN.x, HouseBuilder.ORIGIN.z)
		return bounds.grow(7.0)
	return Rect2(-58, -35, 106, 125) if context == "town" else Rect2(FarmBuilder.ORIGIN.x - 35, -40, 185, 110)


func photo_context_check() -> void:
	# The legacy PhotoMode API is available on the original source as well;
	# no new production bounds helper is called by this old-failure regression.
	var valid: bool = true
	var details: Array[String] = []
	var saved_pause: bool = GameState.clock_paused
	var saved_region: String = GameState.player_region
	var garden: MeshInstance3D = home_garden_card()
	var garden_transform: Transform3D = garden.global_transform if garden != null else Transform3D.IDENTITY
	var garden_material: Material = garden.get_active_material(0) if garden != null else null
	for context: String in ["house", "store", "bakery", "workroom", "farm", "town"]:
		if main.in_room:
			if main.room_kind == "house": await main.exit_room()
			else: await main.exit_interior()
		if main.world.region == "farm": await main.leave_farm()
		if context == "house": await main.enter_room()
		elif context in ["store", "bakery", "workroom"]: await main.enter_interior(context)
		elif context == "farm": await main.go_farm()
		await t.frames(2)
		GameState.clock_paused = context != "farm"
		var bounds: Rect2 = photo_context_bounds(context)
		var old_camera: Camera3D = main.get_viewport().get_camera_3d()
		var old_position: Vector3 = old_camera.global_position
		var old_pause: bool = GameState.clock_paused
		var old_actor: bool = main.player.model_root.visible
		var old_marker: bool = main.marker.visible
		var old_ambient: bool = main.ui.ambient_layer.visible
		var tags := {}
		for id: String in main.npcs: tags[id] = main.npcs[id].tag.visible
		var normal_backdrop: bool = garden != null and garden.is_visible_in_tree() == (context == "house")
		main.photo.toggle()
		main.photo._process(0.0)
		await t.frames(2)
		var entry: bool = main.photo.active and main.get_viewport().get_camera_3d() == main.photo.camera and main.photo.camera.global_position.distance_to(old_position) < .05
		var photo_backdrop_hidden: bool = garden != null and not garden.visible
		# Match the real photo writer's shared-world SubViewport without writing
		# an OS picture or depending on any newly added production API.
		var photo_viewport := SubViewport.new()
		photo_viewport.world_3d = main.get_world_3d()
		main.add_child(photo_viewport)
		var photo_lens := Camera3D.new()
		photo_viewport.add_child(photo_lens)
		photo_lens.make_current()
		await t.frames(2)
		photo_backdrop_hidden = photo_backdrop_hidden and garden != null and not garden.visible
		photo_viewport.free()
		var limits: bool = true
		for corner: Vector3 in [Vector3(bounds.position.x - 20, -5, bounds.position.y - 20), Vector3(bounds.end.x + 20, 30, bounds.end.y + 20)]:
			main.photo.camera.global_position = corner
			main.photo._process(0.0)
			var expected := Vector3(clampf(corner.x, bounds.position.x, bounds.end.x), clampf(corner.y, .55, 24), clampf(corner.z, bounds.position.y, bounds.end.y))
			limits = limits and main.photo.camera.global_position.distance_to(expected) < .001
		main.photo.finish()
		await t.frames(2)
		var restored: bool = not main.photo.active and main.get_viewport().get_camera_3d() == old_camera and GameState.clock_paused == old_pause and main.player.model_root.visible == old_actor and main.marker.visible == old_marker and main.ui.ambient_layer.visible == old_ambient and not GameState._ui_locks.has("photo")
		for id: String in tags: restored = restored and main.npcs[id].tag.visible == tags[id]
		var backdrop_restored: bool = garden != null and garden.is_visible_in_tree() == (context == "house") and garden.global_transform == garden_transform and garden.get_active_material(0) == garden_material
		var independent_hidden: bool = true
		if context == "house":
			var diagnostic := Camera3D.new()
			main.add_child(diagnostic)
			diagnostic.global_transform = old_camera.global_transform
			diagnostic.make_current()
			await t.frames(2)
			independent_hidden = garden != null and not garden.visible
			old_camera.make_current()
			diagnostic.free()
			await t.frames(2)
			backdrop_restored = backdrop_restored and garden != null and garden.is_visible_in_tree()
		valid = valid and entry and limits and restored and normal_backdrop and photo_backdrop_hidden and backdrop_restored and independent_hidden
		details.append("%s entry=%s bounds=%s restore=%s card_normal=%s card_photo_hidden=%s card_restored=%s independent_hidden=%s" % [context, entry, limits, restored, normal_backdrop, photo_backdrop_hidden, backdrop_restored, independent_hidden])
	GameState.clock_paused = saved_pause
	GameState.player_region = saved_region
	check("photo mode preserves contextual cameras and restoration while the unchanged home painting appears only through its normal diorama lens", valid, str(details))


func home_garden_card() -> MeshInstance3D:
	# Identify the original mesh by its material on legacy and current production.
	for child: Node in main.world.house.get_children():
		if not child is MeshInstance3D: continue
		var candidate: MeshInstance3D = child as MeshInstance3D
		if candidate.mesh == null: continue
		var material: StandardMaterial3D = candidate.get_active_material(0) as StandardMaterial3D
		if candidate.mesh is QuadMesh and material != null and material.albedo_texture != null and material.albedo_texture.resource_path.ends_with("/card_garden.jpg"):
			return candidate
	return null


func room_visuals_match(context: String) -> bool:
	var house_expected: bool = context in ["house", "outdoor"]
	if main.world.house.is_visible_in_tree() != house_expected: return false
	for kind: String in main.world.interiors:
		var expected: bool = (context == kind) if context != "outdoor" else main.world.region != "farm"
		if main.world.interiors[kind].is_visible_in_tree() != expected: return false
	return true


func public_house_visibility_check() -> void:
	# Existing APIs and the original material identify the actual inactive
	# garden card on both old and new sources, without new helper dependencies.
	var house: HouseBuilder = main.world.house
	var garden: MeshInstance3D = null
	for child: Node in house.get_children():
		if not child is MeshInstance3D: continue
		var candidate: MeshInstance3D = child as MeshInstance3D
		if candidate.mesh == null: continue
		var candidate_material: StandardMaterial3D = candidate.get_active_material(0) as StandardMaterial3D
		if candidate.mesh is QuadMesh and candidate_material != null and candidate_material.albedo_texture != null and candidate_material.albedo_texture.resource_path.ends_with("/card_garden.jpg"):
			garden = candidate
			break
	if garden == null:
		check("interior entry and restore show only the current house/public room while original outdoor policy geometry and material remain intact", false, "original garden card missing")
		return
	var transform_before: Transform3D = garden.global_transform
	var material_before: Material = garden.get_active_material(0)
	var texture_before: Texture2D = (material_before as StandardMaterial3D).albedo_texture
	var room_transforms: Dictionary = {}
	for kind: String in main.world.interiors: room_transforms[kind] = main.world.interiors[kind].global_transform
	var saved_fields := {}
	for key: String in ["has_player_pos", "player_pos", "player_yaw", "player_in_room", "player_region", "load_on_enter", "clock_paused"]:
		saved_fields[key] = GameState.get(key)
	GameState.clock_paused = true
	main.world.set_region("town")
	look(12.0, "sunny")
	var valid: bool = true
	var details: Array[String] = []
	for kind: String in ["store", "bakery", "workroom"]:
		await main.enter_interior(kind)
		var entry_owned: bool = room_visuals_match(kind)
		main.world.set_region("town")
		var resync_owned: bool = room_visuals_match(kind)
		main._put_in_room(main.player.global_position)
		var placed_owned: bool = room_visuals_match(kind)
		GameState.has_player_pos = true
		GameState.player_pos = main.player.global_position
		GameState.player_yaw = main.player._face_yaw
		GameState.player_in_room = true
		GameState.player_region = "town"
		main._restore()
		var restored_owned: bool = main.room_kind == kind and room_visuals_match(kind)
		await main.exit_interior()
		var outdoor_visible: bool = not main.in_room and room_visuals_match("outdoor")
		await main.enter_room()
		main.world.set_region("town")
		var home_owned: bool = main.room_kind == "house" and room_visuals_match("house")
		GameState.player_pos = main.player.global_position
		GameState.player_in_room = true
		main._restore()
		var restored_home_owned: bool = main.room_kind == "house" and room_visuals_match("house")
		await main.exit_room()
		var exit_visible: bool = not main.in_room and room_visuals_match("outdoor")
		valid = valid and entry_owned and resync_owned and placed_owned and restored_owned and outdoor_visible and home_owned and restored_home_owned and exit_visible
		valid = valid and garden.global_transform == transform_before and garden.get_active_material(0) == material_before and (garden.get_active_material(0) as StandardMaterial3D).albedo_texture == texture_before
		details.append("%s entry=%s resync=%s put=%s restore=%s street=%s home=%s restore_home=%s exit=%s" % [kind, entry_owned, resync_owned, placed_owned, restored_owned, outdoor_visible, home_owned, restored_home_owned, exit_visible])
	main.world.set_region("farm")
	valid = valid and room_visuals_match("outdoor")
	main.world.set_region("town")
	valid = valid and room_visuals_match("outdoor")
	for kind: String in room_transforms: valid = valid and main.world.interiors[kind].global_transform == room_transforms[kind]
	for key: String in saved_fields: GameState.set(key, saved_fields[key])
	check("interior entry and restore show only the current house/public room while original outdoor policy geometry and material remain intact", valid, str(details))


func yard_weather_check() -> void:
	# Use existing entry and physical-room APIs so this exact test also runs
	# against the old production source and fails normally, without new methods.
	main.world.set_region("town")
	main._amb_check = 100.0
	GameState.weather = "rain"
	var unchanged_minute: float = GameState.minute
	var yard_position: Vector3 = HouseBuilder.ORIGIN + Vector3(2.0, -.40, -5.4)
	var engawa_position: Vector3 = HouseBuilder.ORIGIN + Vector3(2.0, .05, -4.0)
	var room: Dictionary = HouseBuilder.room_at(yard_position - HouseBuilder.ORIGIN)
	var rect: Array = room.rect
	var expected_bounds := Vector4(HouseBuilder.ORIGIN.x + float(rect[0]), HouseBuilder.ORIGIN.z + float(rect[1]), HouseBuilder.ORIGIN.x + float(rect[2]), HouseBuilder.ORIGIN.z + float(rect[3]))
	var expected_area: float = (float(rect[2]) - float(rect[0])) * (float(rect[3]) - float(rect[1]))
	main._put_in_room(yard_position)
	var rain: GPUParticles3D = main.weather_fx.rain
	var yard_started: bool = rain.visible and rain.emitting
	var rain_material: ShaderMaterial = rain.draw_pass_1.surface_get_material(0) as ShaderMaterial
	var actual_clip: Variant = rain_material.get_shader_parameter("clip_rect") if rain_material != null else null
	var clipped_to_yard: bool = rain_material != null and bool(rain_material.get_shader_parameter("clip_region")) and actual_clip is Vector4 and (actual_clip as Vector4).distance_to(expected_bounds) < .0001
	var pm: ParticleProcessMaterial = rain.process_material as ParticleProcessMaterial
	var density_preserved: bool = absf(float(rain.amount) - 1400.0 * expected_area / (28.0 * 28.0)) <= 1.0 and absf(pm.emission_box_extents.x * 2.0 - (expected_bounds.z - expected_bounds.x)) < .0001 and absf(pm.emission_box_extents.z * 2.0 - (expected_bounds.w - expected_bounds.y)) < .0001
	main.player.global_position = engawa_position
	main._physics_process(0.0)
	var engawa_dry: bool = main.world.house.current_room == "engawa" and not rain.visible and not rain.emitting
	main.player.global_position = yard_position
	main._physics_process(0.0)
	var yard_resumed: bool = main.world.house.current_room == "yard" and rain.visible and rain.emitting
	main.player.global_position = HouseBuilder.ORIGIN + Vector3(2.0, .05, -.5)
	main._physics_process(0.0)
	var living_dry: bool = not rain.visible and not rain.emitting
	GameState.weather = "sunny"
	main._put_in_room(yard_position)
	var sunny_yard_dry: bool = not rain.visible and not rain.emitting
	GameState.weather = "rain"
	main._put_in_room(yard_position)
	await main.exit_room()
	var outdoor_reset: bool = rain.visible and rain.emitting and rain.amount == 1400 and rain_material != null and not bool(rain_material.get_shader_parameter("clip_region")) and pm.emission_box_extents.distance_to(Vector3(14, .5, 14)) < .0001
	check("the real uncovered yard restores clipped rain at outdoor density and immediately dries beneath the engawa without any minute or periodic tick", yard_started and clipped_to_yard and density_preserved and engawa_dry and yard_resumed and living_dry and sunny_yard_dry and outdoor_reset and is_equal_approx(GameState.minute, unchanged_minute),
		"entry=%s rect=%s density=%s engawa=%s return=%s living=%s sunny=%s outdoor=%s minute=%s" % [yard_started, clipped_to_yard, density_preserved, engawa_dry, yard_resumed, living_dry, sunny_yard_dry, outdoor_reset, GameState.minute - unchanged_minute])


func upper_bark_camera_check() -> void:
	main.world.set_region("town")
	await t.frames(2)
	var hero: Node3D = null
	for plant: Node in main.world.get_children():
		if plant.get_meta("model_id", "") == "T05_old_shade_tree": hero = plant as Node3D; break
	var actual_bark: bool = hero != null
	var bark_meshes: int = 0
	var camera_bodies: int = 0
	var solid_bodies: int = 0
	if hero != null:
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(hero):
			var bodies: Array[Node] = mesh.find_children("*", "StaticBody3D", false, false)
			if not str(mesh.name).begins_with("Trunk"):
				actual_bark = actual_bark and bodies.is_empty()
				continue
			bark_meshes += 1
			actual_bark = actual_bark and bodies.size() == 1
			for node: StaticBody3D in bodies:
				camera_bodies += 1
				var shapes: Array[Node] = node.find_children("*", "CollisionShape3D", false, false)
				actual_bark = actual_bark and node.collision_layer == WorldBuilder.L_CAMERA and node.collision_mask == 0 and node.has_meta("model_part") and shapes.size() == 1
				if shapes.size() != 1: continue
				var shape: CollisionShape3D = shapes[0] as CollisionShape3D
				actual_bark = actual_bark and shape.shape is ConcavePolygonShape3D
				if shape.shape is ConcavePolygonShape3D:
					actual_bark = actual_bark and (shape.shape as ConcavePolygonShape3D).get_faces() == mesh.mesh.get_faces() and (shape.shape as ConcavePolygonShape3D).backface_collision
		for node: StaticBody3D in hero.find_children("*", "StaticBody3D", true, false):
			if node.collision_layer & WorldBuilder.L_SOLID: solid_bodies += 1
		var trunk_body: StaticBody3D = hero.get_node_or_null("TrunkCollision") as StaticBody3D
		actual_bark = actual_bark and trunk_body != null and solid_bodies == 1
		if trunk_body != null:
			var original_shapes: Array[Node] = trunk_body.find_children("*", "CollisionShape3D", false, false)
			actual_bark = actual_bark and original_shapes.size() == 2
			for shape: CollisionShape3D in original_shapes:
				var cylinder: CylinderShape3D = shape.shape as CylinderShape3D
				if cylinder == null: actual_bark = false; continue
				if shape.name == "RootClearance":
					actual_bark = actual_bark and absf(cylinder.radius - 2.35) < .0001 and absf(cylinder.height - .70) < .0001
				else:
					actual_bark = actual_bark and absf(cylinder.radius - 1.35) < .0001 and absf(cylinder.height - 2.0) < .0001 and absf(shape.position.z - .55) < .0001
	var old_bad_point := Vector3(4.4741669, 2.8000002, 7.3787193)
	var lantern_focus := Vector3(4.0, 2.4, 10.8)
	var ray := PhysicsRayQueryParameters3D.create(old_bad_point, lantern_focus, WorldBuilder.L_SOLID | WorldBuilder.L_CAMERA)
	ray.hit_back_faces = true
	ray.hit_from_inside = true
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(ray)
	var hit_bark: bool = not hit.is_empty() and (hit.collider as CollisionObject3D).collision_layer == WorldBuilder.L_CAMERA and hero != null and hero.is_ancestor_of(hit.collider)
	var camera_only: bool = (main.player.collision_mask & WorldBuilder.L_CAMERA) == 0 and (main.rig.arm.collision_mask & WorldBuilder.L_CAMERA) != 0
	check("upper rendered old-tree bark blocks the real camera and old inside-tree QA ray while original avatar/root cylinders stay unchanged", actual_bark and bark_meshes > 0 and camera_bodies == bark_meshes and hit_bark and camera_only,
		"bark=%d camera_bodies=%d solid_bodies=%d old_bad_ray=%s camera_only=%s" % [bark_meshes, camera_bodies, solid_bodies, hit_bark, camera_only])


func plate_matches(action: LivingAction, support: Node3D, ceiling: float) -> bool:
	if support == null or not support.is_visible_in_tree(): return false
	var plate: MeshInstance3D = action.prop.get_node("Plate") as MeshInstance3D
	var radius: float = (plate.mesh as CylinderMesh).top_radius
	for index: int in 17:
		var angle: float = TAU * float(index) / 16.0
		var point: Vector3 = action.prop.global_transform * Vector3(cos(angle) * (radius + .008) if index < 16 else 0.0, .0005, sin(angle) * (radius + .008) if index < 16 else 0.0)
		var height: float = WorldBuilder.surface_height(support, Vector2(point.x, point.z), ceiling)
		if not is_finite(height) or absf(height - point.y) > .004: return false
	return true


func ribbon_probe(mesh: MeshInstance3D, triangles: TriangleMesh, point: Vector2) -> Dictionary:
	var world_point: Vector3 = FarmBuilder.ORIGIN + Vector3(point.x, 0, point.y)
	return triangles.intersect_segment(mesh.to_local(world_point + Vector3.UP * 5.0), mesh.to_local(world_point - Vector3.UP * 5.0))


func continuous_ribbon_check() -> void:
	main.world.set_region("farm")
	await t.frames(2)
	var lake: LakesideBuilder = main.world.farm.lakeside
	var routes: Array[PackedVector2Array] = LakesideLayout.walk_paths().duplicate()
	var shore: PackedVector2Array = LakesideLayout.lake_outline(120, .7)
	shore.append(shore[0])
	routes.append(shore)
	for bank_side: float in [-1.0, 1.0]:
		var bank := PackedVector2Array()
		for index: int in 73:
			var x: float = -66.0 + float(index) * 2.0
			bank.append(Vector2(x, LakesideLayout.river_z(x) + bank_side * (LakesideLayout.river_half(x) + .7)))
		routes.append(bank)
	var widths: Array[float] = [2.6, 2.6, 2.6, 1.7, .82, .82]
	var checked: int = 0
	var holes: int = 0
	var physical_matches: bool = true
	var first_hole := Vector2.INF
	var first_mesh: MeshInstance3D = null
	var first_triangles: TriangleMesh = null
	var terrain_triangles: TriangleMesh = lake.ground_mesh.mesh.generate_triangle_mesh()
	var visible_above_terrain: bool = true
	var minimum_separation: float = INF
	for route_index: int in routes.size():
		var mesh: MeshInstance3D = lake.get_node_or_null("Shore_or_path_%d" % route_index) as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			holes += 1
			continue
		var triangles: TriangleMesh = mesh.mesh.generate_triangle_mesh()
		if route_index == 0: first_mesh = mesh; first_triangles = triangles
		var route: PackedVector2Array = routes[route_index]
		var closed: bool = route[0].distance_to(route[-1]) < .0001
		# Probe the actual old missing wedges, 70% of the half-width from centre.
		# The sample definition uses the two adjacent old segment edges, never a
		# new production helper or a metadata promise of continuity.
		for join: int in route.size() - 1:
			if join == 0 and not closed: continue
			var at: Vector2 = route[join]
			var before: Vector2 = route[join - 1] if join > 0 else route[-2]
			var after: Vector2 = route[join + 1]
			var edges: Array[Vector2] = []
			for segment: Array in [[before, at], [at, after]]:
				var middle: Vector2 = (segment[0] + segment[1]) * .5
				var delta: Vector2 = segment[1] - segment[0]
				var half: float = widths[route_index] * (.93 + .055 * sin(middle.x * .47 + middle.y * .21) + .035 * cos(middle.y * .79 - middle.x * .13)) * .5
				edges.append(Vector2(-delta.y, delta.x).normalized() * half)
			for join_side: float in [-1.0, 0.0, 1.0]:
				var point: Vector2 = at + (edges[0] + edges[1]) * (.35 * join_side)
				checked += 1
				var ribbon_hit: Dictionary = ribbon_probe(mesh, triangles, point)
				if ribbon_hit.is_empty():
					holes += 1
					if not first_hole.is_finite(): first_hole = point
				else:
					var terrain_hit: Dictionary = ribbon_probe(lake.ground_mesh, terrain_triangles, point)
					visible_above_terrain = visible_above_terrain and not terrain_hit.is_empty()
					if not terrain_hit.is_empty():
						var separation: float = mesh.to_global(ribbon_hit.position).y - lake.ground_mesh.to_global(terrain_hit.position).y
						minimum_separation = minf(minimum_separation, separation)
						visible_above_terrain = visible_above_terrain and separation > .005
		var bodies: Array[Node] = mesh.find_children("*", "StaticBody3D", true, false)
		if route_index >= 3:
			physical_matches = physical_matches and bodies.is_empty()
		elif bodies.size() != 1:
			physical_matches = false
		else:
			var body: StaticBody3D = bodies[0] as StaticBody3D
			var shapes: Array[Node] = body.find_children("*", "CollisionShape3D", false, false)
			physical_matches = physical_matches and body.collision_layer == WorldBuilder.L_GROUND and shapes.size() == 1
			if shapes.size() == 1:
				var shape: CollisionShape3D = shapes[0] as CollisionShape3D
				physical_matches = physical_matches and shape.shape is ConcavePolygonShape3D
				if shape.shape is ConcavePolygonShape3D: physical_matches = physical_matches and (shape.shape as ConcavePolygonShape3D).get_faces() == mesh.mesh.get_faces()
	var known_covered: bool = first_mesh != null and first_triangles != null
	if known_covered:
		for point: Vector2 in [Vector2(108.419526, -13.149316), Vector2(111.833681, -12.682088)]:
			var drawn: Dictionary = ribbon_probe(first_mesh, first_triangles, point)
			var start: Vector3 = FarmBuilder.ORIGIN + Vector3(point.x, 5.0, point.y)
			var physical: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, start - Vector3.UP * 10.0, WorldBuilder.L_GROUND))
			known_covered = known_covered and not drawn.is_empty() and not physical.is_empty()
			if not drawn.is_empty() and not physical.is_empty():
				known_covered = known_covered and absf(first_mesh.to_global(drawn.position).y - (physical.position as Vector3).y) < .008 and str((physical.collider as Node).name) == "Path_surface_collision"
	check("all six curved road and shore ribbons visibly cover their old inner 70-percent wedges above actual terrain and walking collision matches the continuous triangles", holes == 0 and checked > 1000 and physical_matches and known_covered and visible_above_terrain,
		"actual join probes=%d holes=%d first=%s physical=%s old_native_gap_points=%s minimum_above_terrain=%.5f" % [checked, holes, first_hole, physical_matches, known_covered, minimum_separation])


func table_collisions(model: Node3D, enabled: bool) -> bool:
	var bodies: Array[Node] = model.find_children("*", "CollisionObject3D", true, false)
	if bodies.is_empty(): return false
	for body: CollisionObject3D in bodies:
		if body.collision_layer != (WorldBuilder.L_SOLID if enabled else 0): return false
	return true


func living_location_checks() -> void:
	var event: Dictionary = DailyLife.event("tea")
	var original_event: Dictionary = event.duplicate(true)
	var original_paused: bool = GameState.clock_paused
	var minute: float = GameState.minute
	var ticks: Array[int] = [0]
	var observe_tick: Callable = func(_value: int) -> void: ticks[0] += 1
	GameState.time_changed.connect(observe_tick)
	GameState.clock_paused = true
	event.state = "done"
	main.in_room = false
	main.room_kind = ""
	GameState.player_in_room = false
	main.world.set_region("town")
	var view: NeighbourMealView = main.story.neighbours.view
	# Establish the valid outdoor fixture. All following updates must come from
	# real location APIs; clock/state polling cannot excuse a delayed restoration.
	view.sync_state()
	var visible_before: bool = view.table_model.visible and view.tea.visible and table_collisions(view.table_model, true)
	await main.enter_room()
	var home_hidden: bool = not view.table_model.visible and not view.tea.visible and table_collisions(view.table_model, false) and not main.story.neighbours.table_available()
	# Cooking/inventory changes really emit this while indoors. Reproduce that
	# old path without consuming food or waiting for the next game minute.
	GameState.state_changed.emit()
	await main.exit_room()
	var home_returned: bool = view.table_model.visible and view.tea.visible and table_collisions(view.table_model, true) and main.story.neighbours.table_available()
	await main.enter_interior("store")
	var store_hidden: bool = not view.table_model.visible and not view.tea.visible and table_collisions(view.table_model, false)
	GameState.state_changed.emit()
	await main.exit_interior()
	var store_returned: bool = view.table_model.visible and view.tea.visible and table_collisions(view.table_model, true) and main.story.neighbours.table_available()
	await main.go_farm()
	var farm_hidden: bool = not view.table_model.visible and not view.tea.visible and table_collisions(view.table_model, false)
	await main.leave_farm()
	var farm_returned: bool = view.table_model.visible and view.tea.visible and table_collisions(view.table_model, true) and main.story.neighbours.table_available()
	check("real home shop and farm returns restore the shared table visibility collisions and meal entry without a clock tick", visible_before and home_hidden and home_returned and store_hidden and store_returned and farm_hidden and farm_returned and ticks[0] == 0 and is_equal_approx(GameState.minute, minute), "home=%s/%s store=%s/%s farm=%s/%s ticks=%d" % [home_hidden, home_returned, store_hidden, store_returned, farm_hidden, farm_returned, ticks[0]])
	GameState.time_changed.disconnect(observe_tick)
	event.clear()
	event.merge(original_event, true)
	GameState.clock_paused = original_paused
	view.sync_state()


func cup_matches(cups: Node3D, support: Node3D, ceiling: float) -> Dictionary:
	var bounds: AABB = cups.global_transform * WorldBuilder.local_aabb(cups)
	var height: float = WorldBuilder.surface_height(support, Vector2(cups.global_position.x, cups.global_position.z), ceiling)
	var gap: float = bounds.position.y - height
	var covered: bool = is_finite(height) and absf(gap) < .004
	var checked: int = 0
	# Inspect real low ceramic vertices, rather than handles/AABB corners that
	# never touch the tray. A tiny declared support cannot excuse overhanging cups.
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(cups):
		for vertex: Vector3 in mesh.mesh.get_faces():
			var point: Vector3 = mesh.global_transform * vertex
			if point.y > bounds.position.y + .003: continue
			checked += 1
			if not is_finite(WorldBuilder.surface_height(support, Vector2(point.x, point.z), ceiling)): covered = false
	return {"ok": covered and checked > 0, "gap": gap, "low_vertices": checked}


func living_carrier_checks() -> void:
	var view: DailyLifeView = main.story.daily.view
	var original_in_room: bool = main.in_room
	var original_position: Vector3 = main.player.global_position
	var original_meal_visible: bool = view.meal_root.visible
	var original_region: String = main.world.region
	if main.in_room:
		if main.room_kind == "house": await main.exit_room()
		else: await main.exit_interior()
	main.world.set_region("town")
	var cart: Node3D = main.world.get_node("G11_bread_cart")
	var board: MeshInstance3D = cart.get_node_or_null("LifeBakeryServingCounter") as MeshInstance3D
	var surface: Vector3 = view._food_surface()
	var action := LivingAction.new()
	main.add_child(action)
	action.surface_at = surface
	action.duration = 100.0
	action.setup(main.player, "eat", "melon_pan")
	action.set_process(false)
	var margin: bool = false
	if board != null:
		var local_surface: Vector3 = board.global_transform.affine_inverse() * surface
		var board_box: AABB = board.mesh.get_aabb()
		var plate: MeshInstance3D = action.prop.get_node("Plate") as MeshInstance3D
		var radius: float = (plate.mesh as CylinderMesh).top_radius
		margin = local_surface.x - radius > board_box.position.x + .02 and local_surface.x + radius < board_box.end.x - .02 and local_surface.z - radius > board_box.position.z + .02 and local_surface.z + radius < board_box.end.z - .02
	check("the real bakery eating plate and full margin rest on a visible counter below the canopy", board != null and board.get_meta("model_part", false) and surface.y > .5 and surface.y < 1.0 and margin and plate_matches(action, board, 1.05), "actual eating surface %s; complete plate margin %s" % [surface, margin])
	var paper_bounds: AABB = view.paper.global_transform * WorldBuilder.local_aabb(view.paper)
	var card_on_board: bool = false
	if board != null:
		var card_height: float = WorldBuilder.surface_height(board, Vector2(view.paper.global_position.x, view.paper.global_position.z), 1.05)
		var board_bounds: AABB = board.global_transform * board.get_aabb()
		var paper_footprint := Rect2(Vector2(paper_bounds.position.x, paper_bounds.position.z), Vector2(paper_bounds.size.x, paper_bounds.size.z))
		var food_footprint := Rect2(Vector2(surface.x - .093, surface.z - .093), Vector2(.186, .186))
		card_on_board = is_finite(card_height) and absf(paper_bounds.position.y - card_height) < .004 and paper_bounds.position.x >= board_bounds.position.x and paper_bounds.end.x <= board_bounds.end.x and paper_bounds.position.z >= board_bounds.position.z and paper_bounds.end.z <= board_bounds.end.z and not paper_footprint.intersects(food_footprint)
	check("the leaning bakery paper rests on the same real counter with its footprint separate from the plate", card_on_board, "paper base %.5f; food %s" % [paper_bounds.position.y, surface])
	action.free()
	var tea_tray: Node3D = view.tea_root.get_node("W12_cedar_tray")
	var tea_cups: Node3D = view.tea_root.get_node("W11_ceramic_set")
	var home_cups: Node3D = view.meal_root.get_node("W11_ceramic_set")
	var neighbour: NeighbourMealView = main.story.neighbours.view
	var neighbour_tray: Node3D = neighbour.tea.get_node("W12_cedar_tray")
	var neighbour_cups: Node3D = neighbour.tea.get_node("W11_ceramic_set")
	var tea_contact: Dictionary = cup_matches(tea_cups, tea_tray, (tea_tray.global_transform * WorldBuilder.local_aabb(tea_tray)).end.y + .01)
	var neighbour_contact: Dictionary = cup_matches(neighbour_cups, neighbour_tray, (neighbour_tray.global_transform * WorldBuilder.local_aabb(neighbour_tray)).end.y + .01)
	var home_contact: Dictionary = cup_matches(home_cups, main.world.house.get_node("J03_dining_set"), .95)
	check("all three living ceramic sets contact real supports and their low feet fit the tray instead of overhanging", tea_contact.ok and neighbour_contact.ok and home_contact.ok, "field=%s neighbour=%s home=%s" % [tea_contact, neighbour_contact, home_contact])
	# Use real location APIs so the table's scene is actually visible. Merely
	# changing room flags leaves the preceding public room active in the renderer.
	main._put_in_room(HouseBuilder.spawn_point())
	view.meal_root.visible = false
	var private_surface: Vector3 = view._food_surface()
	var private_action := LivingAction.new()
	main.add_child(private_action)
	private_action.surface_at = private_surface
	private_action.surface_normal = view._meal_normal()
	private_action.duration = 100.0
	private_action.setup(main.player, "eat", "onigiri")
	private_action.set_process(false)
	check("a brought-home meal before claiming the parcel uses the visible table rather than its hidden tray", plate_matches(private_action, main.world.house.get_node("J03_dining_set"), .95), "actual private surface %s" % private_surface)
	private_action.free()
	await main.exit_room()
	await main.enter_interior("bakery")
	var indoor_surface: Vector3 = view._food_surface()
	var indoor_action := LivingAction.new()
	main.add_child(indoor_action)
	indoor_action.surface_at = indoor_surface
	indoor_action.duration = 100.0
	indoor_action.setup(main.player, "eat", "melon_pan")
	indoor_action.set_process(false)
	var indoor_counter: Node3D = main.world.interiors.bakery.get_node("I04_shop_counter")
	var indoor_paper_bounds: AABB = view.paper_inside.global_transform * WorldBuilder.local_aabb(view.paper_inside)
	var indoor_paper_height: float = WorldBuilder.surface_height(indoor_counter, Vector2(view.paper_inside.global_position.x, view.paper_inside.global_position.z), 1.35)
	check("indoor bakery tasting and paper also use separate finite patches on the actual counter", indoor_surface.is_finite() and indoor_surface.y > .7 and plate_matches(indoor_action, indoor_counter, 1.35) and is_finite(indoor_paper_height) and absf(indoor_paper_bounds.position.y-indoor_paper_height)<.004 and Vector2(view.paper_inside.global_position.x-indoor_surface.x,view.paper_inside.global_position.z-indoor_surface.z).length()>.45, "indoor food %s; paper base %.5f support %.5f" % [indoor_surface, indoor_paper_bounds.position.y, indoor_paper_height])
	indoor_action.free()
	await main.exit_interior()
	var clear: bool = true
	var shape := CapsuleShape3D.new()
	shape.radius = .32
	shape.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = WorldBuilder.L_SOLID | WorldBuilder.L_PLACED
	# Story._point is a marker position in older/current games, not an actual
	# Interactable. Read the native scene entry used by E in both versions.
	var entry_position: Vector3 = Vector3.INF
	for candidate: Node in main.get_tree().get_nodes_in_group("interactables"):
		if candidate is Interactable and candidate.id == "life_bakery_card":
			entry_position = candidate.global_position
			break
	var points: Array[Vector3] = []
	if entry_position.is_finite(): points.append(entry_position); points.append(entry_position + Vector3(0, 0, 1.15))
	else: clear = false
	for index: int in 17: points.append((Layout.NPC.ren.prep as Vector3).lerp(Vector3(-22.3, 0, -12.0), float(index) / 16.0))
	for point: Vector3 in points:
		query.transform = Transform3D(Basis.IDENTITY, Vector3(point.x, .8, point.z))
		if not main.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): clear = false
	var morning: ResidentMorning = main.story.morning
	var p08: Node3D = main.world.get_node("P08")
	var worktop: float = WorldBuilder.rendered_support_height(p08, view.tea_root.global_position, 1.4, true)
	print("LIVING_SUPPORT_AUDIT ", JSON.stringify({"tea_y": view.tea_root.global_position.y, "worktop_y": worktop,
		"tea_visible": view.tea_root.visible, "blocked": view.tea_root.get_meta("morning_blocked", false), "original_legal": morning.legal(morning.original_tray)}))
	check("the serving counter preserves both original E approaches and Ren's route while tea still has both clear worktop destinations", clear and is_finite(worktop) and worktop > .9 and worktop < 1.1 and morning.legal(morning.target_at(0)) and morning.legal(morning.target_at(1)))
	main.world.set_region(original_region)
	if original_in_room: main._put_in_room(original_position)
	else: main.player.global_position = original_position
	view.meal_root.visible = original_meal_visible


func lake_collision_height(at: Vector2) -> float:
	var position: Vector3 = FarmBuilder.ORIGIN + Vector3(at.x, 0, at.y)
	var ray := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 5.0, position - Vector3.UP * 5.0, WorldBuilder.L_GROUND)
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(ray)
	return (hit.position as Vector3).y if not hit.is_empty() else -INF


func lake_visible_ground(at: Vector2) -> float:
	var lakeside: LakesideBuilder = main.world.farm.lakeside
	var point: Vector2 = at + Vector2(FarmBuilder.ORIGIN.x, FarmBuilder.ORIGIN.z)
	var highest: float = WorldBuilder.surface_height(lakeside.ground_mesh, point, 4.0)
	for path: MeshInstance3D in lakeside.find_children("Shore_or_path_*", "MeshInstance3D", true, false):
		if path.visible:
			highest = maxf(highest, WorldBuilder.surface_height(path, point, 4.0))
	return highest


func lake_path_matches(points: Array[Vector2]) -> Dictionary:
	var maximum: float = 0.0
	var valid: bool = true
	for point: Vector2 in points:
		var drawn: float = lake_visible_ground(point)
		var physical: float = lake_collision_height(point)
		valid = valid and is_finite(drawn) and is_finite(physical)
		maximum = maxf(maximum, absf(drawn - physical))
	return {"ok": valid and maximum < .008, "maximum": maximum}


func lake_bridge_matches() -> Dictionary:
	var maximum: float = 0.0
	var valid: bool = true
	for bridge: Node3D in [main.world.farm.get_node("P_bridge"), main.world.farm.lakeside.get_node("P_bridge")]:
		for offset: float in [-3.3, 0.0, 3.3]:
			var centre: Vector3 = bridge.global_position + Vector3(0, 0, offset)
			var local: Vector2 = Vector2(centre.x - FarmBuilder.ORIGIN.x, centre.z - FarmBuilder.ORIGIN.z)
			var physical: float = lake_collision_height(local)
			var drawn: float = -INF
			# A three-centimetre plank joint is intentional. Sample a small foot
			# footprint on visible boards; never count the invisible collision deck.
			for delta: Vector2 in [Vector2.ZERO, Vector2(.045, 0), Vector2(-.045, 0), Vector2(0, .045), Vector2(0, -.045)]:
				for plank: MeshInstance3D in WorldBuilder.find_meshes(bridge):
					if not plank.visible or not str(plank.name).begins_with("planks"):
						continue
					drawn = maxf(drawn, WorldBuilder.surface_height(plank, Vector2(centre.x, centre.z) + delta, physical + .12))
			valid = valid and is_finite(drawn) and is_finite(physical)
			maximum = maxf(maximum, absf(drawn - physical))
	return {"ok": valid and maximum < .03, "maximum": maximum}


func lake_ground_checks() -> void:
	var original_region: String = main.world.region
	main.world.set_region("farm")
	await t.frames(2)
	var lakeside: LakesideBuilder = main.world.farm.lakeside
	var paths: Array[Node] = lakeside.find_children("Shore_or_path_*", "MeshInstance3D", true, false)
	var exact: bool = true
	var walking_paths: int = 0
	var shoreline_decoration_unchanged: bool = true
	for node: Node in paths:
		var path: MeshInstance3D = node as MeshInstance3D
		if not path.get_meta("walkable_ribbon", false):
			shoreline_decoration_unchanged = shoreline_decoration_unchanged and path.get_node_or_null("Path_surface_collision") == null
			continue
		walking_paths += 1
		var body: StaticBody3D = path.get_node_or_null("Path_surface_collision") as StaticBody3D
		var shape: CollisionShape3D = body.get_node_or_null("Rendered_surface") as CollisionShape3D if body != null else null
		exact = exact and body != null and shape != null
		if body != null and shape != null:
			exact = exact and body.collision_layer == WorldBuilder.L_GROUND and body.collision_mask == 0 and shape.shape is ConcavePolygonShape3D
			if shape.shape is ConcavePolygonShape3D:
				exact = exact and (shape.shape as ConcavePolygonShape3D).get_faces() == path.mesh.get_faces()
	var north: Dictionary = lake_path_matches([Vector2(105, -12.5625), Vector2(104.166667, -12.588542), Vector2(110, -11.9)])
	check("the north-bank slope uses exact static walking-path triangles at its highest visible surface", exact and walking_paths == 3 and north.ok, "walking paths %d; maximum contact difference %.5f m" % [walking_paths, float(north.maximum)])
	var shore: Dictionary = lake_path_matches([Vector2(138, 19), Vector2(94, 48), Vector2(131, 40), Vector2(48, 19.4)])
	var bridges: Dictionary = lake_bridge_matches()
	var continuous: bool = true
	var prior: float = lake_collision_height(Vector2(103, -12.59))
	var largest_step: float = 0.0
	for index: int in range(1, 81):
		var along: float = float(index) / 80.0
		var point: Vector2 = Vector2(103, -12.59).lerp(Vector2(111, -11.8), along)
		var contact: float = lake_collision_height(point)
		continuous = continuous and is_finite(contact)
		largest_step = maxf(largest_step, absf(contact - prior))
		prior = contact
	check("the walking paths and both real bridge decks stay supported without holes or abrupt steps", shore.ok and bridges.ok and continuous and largest_step < .035, "shore gap %.5f m; bridge footprint gap %.5f m; largest 10 cm step %.5f m" % [float(shore.maximum), float(bridges.maximum), largest_step])
	var terrain_body: StaticBody3D = lakeside.get_node("Terrain_collision") as StaticBody3D
	var terrain_unchanged: bool = lakeside.ground_mesh.visible and terrain_body.collision_layer == WorldBuilder.L_GROUND
	var terrain_shape: CollisionShape3D
	for child: Node in terrain_body.get_children():
		if child is CollisionShape3D:
			terrain_shape = child as CollisionShape3D
	if terrain_shape == null or not terrain_shape.shape is ConcavePolygonShape3D:
		terrain_unchanged = false
	else:
		terrain_unchanged = terrain_unchanged and (terrain_shape.shape as ConcavePolygonShape3D).get_faces() == lakeside.ground_mesh.mesh.get_faces()
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var river_guard: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(FarmBuilder.ORIGIN + Vector3(10, 1, 11), FarmBuilder.ORIGIN + Vector3(10, 1, 17), WorldBuilder.L_BLOCK))
	var lake_guard: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(FarmBuilder.ORIGIN + Vector3(140, 1, 18), FarmBuilder.ORIGIN + Vector3(125, 1, 18), WorldBuilder.L_BLOCK))
	var bridge_open: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(FarmBuilder.ORIGIN + Vector3(0, 1, 12), FarmBuilder.ORIGIN + Vector3(0, 1, 22), WorldBuilder.L_BLOCK))
	check("original terrain and water guards remain intact while shoreline decoration gains no extra walkable floor", terrain_unchanged and shoreline_decoration_unchanged and not river_guard.is_empty() and not lake_guard.is_empty() and bridge_open.is_empty())
	main.world.set_region(original_region)


func backdrop_coverage() -> Array[float]:
	var observer:=Vector2(-2.6,18.8)
	var intervals: Array[Vector3]=[]
	for node: Node3D in main.world.find_children("*","Node3D",true,false):
		var id: String=str(node.get_meta("model_id",""))
		if not id.begins_with("T0") or node.global_position.x>200.0 or node.global_position.z>200.0:continue
		var relative:=Vector2(node.global_position.x,node.global_position.z)-observer
		if relative.length()<45.0:continue
		var middle: float=atan2(relative.x,-relative.y)
		var lo: float=INF
		var hi: float=-INF
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(node):
			if not mesh.visible or not str(mesh.name).begins_with("Foliage"):continue
			for surface: int in mesh.mesh.get_surface_count():
				var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for vertex: Vector3 in vertices:
					var world_vertex: Vector3=mesh.global_transform*vertex
					if world_vertex.y<4.0:continue
					var delta:=Vector2(world_vertex.x,world_vertex.z)-observer
					var angle: float=wrapf(atan2(delta.x,-delta.y)-middle,-PI,PI)
					lo=minf(lo,angle);hi=maxf(hi,angle)
		if is_finite(lo) and is_finite(hi):intervals.append(Vector3(middle,lo,hi))
	var coverage: Array[float]=[]
	for sector in 8:
		var count: int=0
		for sample in 91:
			var angle: float=TAU*float(sector)/8.0+deg_to_rad(-22.5+float(sample)*.5)
			for interval: Vector3 in intervals:
				var delta: float=wrapf(angle-interval.x,-PI,PI)
				if delta>=interval.y and delta<=interval.z:count+=1;break
		coverage.append(float(count)/91.0)
	return coverage


func backdrop_ground_checks() -> void:
	main.world.set_region("town")
	await t.frames(2)
	var coverage: Array[float]=backdrop_coverage()
	check("the southwest festival reverse view has actual distant tree-crown angular coverage",coverage[5]>=.40,"SW crown coverage %.3f"%coverage[5])
	check("all eight town directions have real middle-distance canopy silhouettes",coverage.all(func(value: float):return value>=.40),str(coverage))
	var skirts: Node3D=main.world.get_node_or_null("BackgroundMeadowSkirts") as Node3D
	var shape_range: float=0.0
	var vertices: int=0
	if skirts!=null:
		var skirts_bounds: AABB=WorldBuilder.local_aabb(skirts);shape_range=skirts_bounds.size.y
		for meadow_piece: MeshInstance3D in WorldBuilder.find_meshes(skirts):
			for surface: int in meadow_piece.mesh.get_surface_count():vertices+=(meadow_piece.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	check("the previously flat outer quadrants contain real gently raised ground vertices",skirts!=null and vertices>20000 and shape_range>1.5,"vertices %d; relief %.3f m"%[vertices,shape_range])
	var supported: bool=skirts!=null
	var maximum: float=0.0
	var space: PhysicsDirectSpaceState3D=main.get_world_3d().direct_space_state
	if skirts!=null:
		for skirt_point: Vector2 in [Vector2(-38,65),Vector2(-86,30),Vector2(-60,-60),Vector2(20,120),Vector2(74,145)]:
			var skirt_top:=Vector3(skirt_point.x,8,skirt_point.y)
			var skirt_hit: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(skirt_top,skirt_top-Vector3.UP*12,WorldBuilder.L_GROUND))
			var drawn: float=WorldBuilder.surface_height(skirts,skirt_point,7.0)
			var physical: float=(skirt_hit.position as Vector3).y if not skirt_hit.is_empty() else -INF
			supported=supported and is_finite(drawn) and is_finite(physical) and drawn>.08
			maximum=maxf(maximum,absf(drawn-physical))
	check("each new outer rise uses its actual visible triangles as ground support",supported and maximum<.008,"maximum ground difference %.5f m"%maximum)
	var local_bounds: bool=skirts!=null
	var patches: int=0
	var widest: float=0.0
	var open_rects: Array[Rect2]=[Rect2(-52.2,-25.2,94.9,57.4).grow(3.0),Rect2(-4.0,32.0,46.7,53.2).grow(3.0),WorldBuilder.EXIT_CUT.grow(2.0),Rect2(-148,-18,96,14.5),Rect2(52,0,128,132)]
	if skirts!=null:
		for local_piece: MeshInstance3D in WorldBuilder.find_meshes(skirts):
			patches+=1
			var bounds: AABB=local_piece.global_transform*local_piece.get_aabb()
			widest=maxf(widest,maxf(bounds.size.x,bounds.size.z))
			var patch_footprint:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
			for opening: Rect2 in open_rects:
				if patch_footprint.intersects(opening):local_bounds=false
			var bodies: Array[Node]=local_piece.find_children("*","StaticBody3D",true,false)
			if bodies.size()!=1:local_bounds=false;continue
			var body: StaticBody3D=bodies[0] as StaticBody3D
			var shapes: Array[Node]=body.find_children("*","CollisionShape3D",true,false)
			if shapes.size()!=1:local_bounds=false;continue
			var volume: CollisionShape3D=shapes[0] as CollisionShape3D
			if not volume.shape is ConcavePolygonShape3D or body.collision_layer!=WorldBuilder.L_GROUND or body.collision_mask!=0:local_bounds=false
			elif (volume.shape as ConcavePolygonShape3D).get_faces()!=local_piece.mesh.get_faces():local_bounds=false
	check("outer meadow mesh and collision bounds stay local and never span a playable hole or a tabletop",local_bounds and patches>20 and patches<800 and widest<=16.001,"actual patches %d; largest draw/physics span %.3f m"%[patches,widest])
	var play_clear: bool=true
	for protected_point: Vector2 in [Vector2(0,0),Vector2(19.7,56),Vector2(-41,-9.5),Vector2(20,77),Vector2(-60,-11)]:
		var protected_top:=Vector3(protected_point.x,5,protected_point.y)
		var protected_hit: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(protected_top,protected_top-Vector3.UP*10,WorldBuilder.L_GROUND))
		play_clear=play_clear and not protected_hit.is_empty() and absf((protected_hit.position as Vector3).y)<.006
	var exit_top:=Vector3(55,5,Layout.STREET_Z)
	var exit_hit: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(exit_top,exit_top-Vector3.UP*12,WorldBuilder.L_GROUND))
	play_clear=play_clear and not exit_hit.is_empty() and absf((exit_hit.position as Vector3).y-WorldBuilder.lane_depth(55))<.03
	var trees: Node3D=main.world.get_node_or_null("BackgroundTreeGroups") as Node3D
	if trees!=null:
		play_clear=play_clear and trees.find_children("*","StaticBody3D",true,false).is_empty()
		for tree: Node3D in trees.get_children():
			var tree_bounds: AABB=tree.global_transform*WorldBuilder.local_aabb(tree)
			var footprint:=Rect2(Vector2(tree_bounds.position.x,tree_bounds.position.z),Vector2(tree_bounds.size.x,tree_bounds.size.z))
			for rect: Rect2 in [Rect2(-52.2,-25.2,94.9,57.4),Rect2(-4,32,46.7,53.2),WorldBuilder.EXIT_CUT]:
				if footprint.intersects(rect.grow(.5)):play_clear=false
			var planted: float=backdrop_visible_height(Vector2(tree.global_position.x,tree.global_position.z),tree_bounds.position.y+.15)
			play_clear=play_clear and is_finite(planted) and absf(tree_bounds.position.y-planted)<.012
	var meadow: Node3D=main.world.get_node_or_null("BackgroundMeadow") as Node3D
	if meadow!=null:
		var edge_samples: Array[Vector3]=[]
		for chunk: MultiMeshInstance3D in meadow.get_children():
			for index: int in chunk.multimesh.instance_count:
				var root: Vector3=chunk.global_transform*chunk.multimesh.get_instance_transform(index).origin
				if root.x> -62.0 and root.x< -7.0 and root.z>30.0 and root.z<92.0 and edge_samples.size()<24:edge_samples.append(root)
		for grass_root: Vector3 in edge_samples:
			var ground: float=backdrop_visible_height(Vector2(grass_root.x,grass_root.z),grass_root.y+.15)
			play_clear=play_clear and is_finite(ground) and absf(grass_root.y-ground)<.012
	check("background planting rests on visible ground while streets homes residents animal paths and both exits stay unchanged",play_clear)


func backdrop_visible_height(point: Vector2,ceiling: float) -> float:
	var ground: float=-INF
	for name: String in ["FarMeadow_0","FarMeadow_1","FarMeadow_2","FarMeadow_3","BackgroundMeadowRise","BackgroundMeadowSkirts"]:
		var node: Node3D=main.world.get_node_or_null(name) as Node3D
		if node!=null:ground=maxf(ground,WorldBuilder.surface_height(node,point,ceiling))
	return ground

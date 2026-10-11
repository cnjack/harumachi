extends RefCounted
## Main-scene regressions for animal activity, discoverability and real support.
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t = runner
	main = runner.main

func check(label: String, passed: bool, detail: String = "") -> void:
	t.check("ANIMAL_QA", label, passed, detail)

func run() -> void:
	var original: Dictionary = GameState.to_dict().duplicate(true)
	var original_in_room: bool = main.in_room
	var original_room_kind: String = main.room_kind
	var original_region: String = main.world.region
	var original_indoor: bool = main.world.indoor
	var original_public_kind: String = main.world.public_interior_kind
	main.in_room = false
	main.room_kind = ""
	GameState.player_in_room = false
	GameState.player_region = "town"
	GameState.clock_paused = true
	GameState.weather = "sunny"
	GameState.minute = 630
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	main.player.global_position = Vector3(15, .05, -8)
	await t.frames(4)
	var walkers: Array = main.life.roaming_cats
	check("two animated cats are present in the main scene", walkers.size() == 2)
	var full_rigs: bool = walkers.size() == 2
	var clips_complete: bool = walkers.size() == 2
	for cat: CharacterBody3D in walkers:
		var skeletons: Array[Node] = cat.model.find_children("*", "Skeleton3D", true, false)
		full_rigs = full_rigs and not skeletons.is_empty() and (skeletons[0] as Skeleton3D).get_bone_count() == 59
		for clip: String in ["Idle", "Walk", "Run", "Sneak", "Sit", "SitDown", "StandUp", "Jump", "Stretch"]:
			clips_complete = clips_complete and cat.player.has_animation(clip)
	check("world cats retain the complete 59 joint rigs", full_rigs)
	check("world cats retain all nine gameplay actions", clips_complete)
	var front_route: bool = not walkers.is_empty()
	if not walkers.is_empty():
		for point: Vector3 in walkers[0].route:
			front_route = front_route and point.distance_to(Vector3(20, 0, 5.5)) < 15 and point.x >= 20.4 and point.x <= 21.6
	check("one animated cat stays discoverable on the shoulder near home", front_route)
	var safe_support: bool = not walkers.is_empty()
	for cat: CharacterBody3D in walkers:
		for point: Vector3 in cat.route:
			var route_support: float = WorldBuilder.surface_height(main.world, Vector2(point.x, point.z), .1, true)
			safe_support = safe_support and cat._clear(point) and is_finite(route_support) and absf(route_support - point.y) < .03
	check("cat route anchors have real ground and avoid solid props", safe_support)
	var safe_edges: bool = not walkers.is_empty()
	for cat: CharacterBody3D in walkers:
		for index: int in cat.route.size():
			var midpoint: Vector3 = cat.route[index].lerp(cat.route[(index + 1) % cat.route.size()], .5)
			var edge_support: float = WorldBuilder.surface_height(main.world, Vector2(midpoint.x, midpoint.z), .1, true)
			safe_edges = safe_edges and cat._clear(midpoint) and is_finite(edge_support) and absf(edge_support - midpoint.y) < .03
	check("cat route edges remain clear and supported between anchors", safe_edges)
	var migrated: bool = false
	if not walkers.is_empty():
		var migrating_cat: CharacterBody3D = walkers[0]
		var saved: Dictionary = migrating_cat.snapshot().duplicate(true)
		var legacy: Dictionary = saved.duplicate(true)
		legacy.position = [19.2, 0, 54.4]
		migrating_cat.reset_behaviour(migrating_cat.behaviour_seed, legacy)
		var first_migration: Dictionary = migrating_cat.snapshot().duplicate(true)
		var first_safe: bool = migrating_cat.habitat.has_point(Vector2(migrating_cat.global_position.x, migrating_cat.global_position.z)) and migrating_cat._clear(migrating_cat.global_position) and migrating_cat.global_position.distance_to(Vector3(19.2, 0, 54.4)) > 20
		var generator := RandomNumberGenerator.new()
		generator.seed = 771928
		legacy.rng_state = str(generator.state)
		migrating_cat.reset_behaviour(migrating_cat.behaviour_seed, legacy)
		migrated = first_safe and migrating_cat.habitat.has_point(Vector2(migrating_cat.global_position.x, migrating_cat.global_position.z)) and migrating_cat._clear(migrating_cat.global_position) and migrating_cat.snapshot().rng_state != first_migration.rng_state
		migrating_cat.reset_behaviour(migrating_cat.behaviour_seed, saved)
	check("old cat positions migrate safely while retaining the saved RNG stream", migrated)
	var home_cat: Node3D
	for node: Node in main.world.house.find_children("*", "Node3D", true, false):
		if node.get_meta("model_id", "") == "G08_cat": home_cat = node as Node3D; break
	var home_material: ShaderMaterial
	if home_cat != null:
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(home_cat):
			var material: ShaderMaterial = mesh.get_active_material(0) as ShaderMaterial
			if material != null and material.shader == load("res://shaders/animal_motion.gdshader"):
				home_material = material; break
	check("the original sleeping home cat has live breathing", home_cat != null and home_material != null)
	var first_phase: float = float(home_material.get_shader_parameter("phase")) if home_material != null else 0
	await t.frames(40)
	check("home cat breathing keeps advancing in the main scene", home_material != null and float(home_material.get_shader_parameter("phase")) > first_phase + .2)
	var home_grounded: bool = false
	if home_cat != null:
		var bounds: AABB = home_cat.global_transform * WorldBuilder.local_aabb(home_cat)
		var home_support: float = WorldBuilder.surface_height(main.world.house,
			Vector2(home_cat.global_position.x, home_cat.global_position.z), bounds.position.y + .025, true)
		home_grounded = is_finite(home_support) and absf(bounds.position.y - home_support) < .015
	check("home cat cushion stays on the rendered engawa floor", home_grounded)
	var activation: bool = true
	for weather: String in ["rain", "sunny"]:
		GameState.weather = weather
		await t.frames(3)
		for cat: CharacterBody3D in walkers:
			activation = activation and cat.player.active == (weather == "sunny") and cat.is_physics_processing() == (weather == "sunny")
	check("rain shelter and sunny return resume the actual cat controllers", activation)
	await _goldfish_checks()
	await _rain_and_bird_checks()
	_insect_checks()
	GameState.from_dict(original)
	main._restore()
	main.in_room = original_in_room
	main.room_kind = original_room_kind
	main.world.set_region(original_region)
	main.world.set_indoor_look(original_indoor, original_public_kind)
	GameState.clock_paused = true

func _goldfish_checks() -> void:
	var house_was_visible: bool = main.world.house.visible
	main.world.house.show()
	var bowl: Node3D = main.world.house.goldfish
	GameState.flags.goldfish_home = false
	main.world.house.sync_state()
	await t.frames(3)
	var controller: Node3D = bowl.get_node_or_null("GoldfishLife") as Node3D
	var fish: Node3D = bowl.get_node_or_null("GoldfishLife/CaughtGoldfish") as Node3D
	check("no home goldfish appears before an actual catch", fish == null or not fish.is_visible_in_tree())
	GameState.flags.goldfish_home = true
	main.world.house.sync_state()
	await t.frames(3)
	var water: MeshInstance3D = bowl.get_node_or_null("GoldfishLife/BowlWater") as MeshInstance3D
	check("a brought-home goldfish has a real visible body and water", fish != null and fish.is_visible_in_tree() and fish.get_node_or_null("Body") is MeshInstance3D and water != null)
	var contained: bool = false
	if fish != null and water != null and controller != null:
		var bowl_bounds: AABB = WorldBuilder.local_aabb(bowl)
		var fish_bounds: AABB = bowl.global_transform.affine_inverse() * (fish.global_transform * WorldBuilder.local_aabb(fish))
		var centre: Vector3 = controller.get("centre")
		var radius: float = float(controller.get("swim_radius"))
		var water_disc: CylinderMesh = water.mesh as CylinderMesh
		var bowl_radius: float = minf(bowl_bounds.size.x, bowl_bounds.size.z) * .5
		var radial_limit: float = Vector2(fish_bounds.get_center().x - centre.x, fish_bounds.get_center().z - centre.z).length() + Vector2(fish_bounds.size.x, fish_bounds.size.z).length() * .5
		contained = fish_bounds.end.y < water.position.y - .005 and fish_bounds.position.y > bowl_bounds.position.y + .04 and water.position.y < bowl_bounds.end.y - .03 and radial_limit < radius and water_disc != null and water_disc.top_radius < bowl_radius - .004 and water_disc.top_radius > bowl_radius * .8
	check("the actual fish fits inside the bowl below its water surface", contained)
	var previous_phase: float = float(controller.get("phase")) if controller != null else 0
	var previous_position: Vector3 = fish.position if fish != null else Vector3.ZERO
	await t.frames(40)
	check("home goldfish actually swims rather than remaining an empty display", controller != null and float(controller.get("phase")) > previous_phase + .2 and fish.position.distance_to(previous_position) > .005)
	main.world.house.sync_state()
	main.world.house.sync_state()
	check("repeated save-flag synchronization keeps exactly one caught fish", bowl.find_children("GoldfishLife", "Node", true, false).size() == 1 and bowl.find_children("CaughtGoldfish", "Node", true, false).size() == 1)
	main.world.house.visible = house_was_visible

func _rain_and_bird_checks() -> void:
	var positions: Array[Vector3] = []
	for entry: Dictionary in main.life.cats: positions.append(entry.node.global_position)
	var pets_before: int = int(GameState.flags.get("ambient_cat_pets", 0))
	GameState.weather = "rain"
	await t.frames(3)
	var sheltered: bool = true
	for index: int in main.life.cats.size():
		var target: Interactable = main.life.get_node_or_null("CatInteract_%d" % index) as Interactable
		sheltered = sheltered and not main.life.cats[index].node.is_visible_in_tree() and target != null and not target.is_visible_in_tree() and target.radius == 0 and target.body == null
	main.life.pet_cat(0)
	check("outdoor resting cats shelter from rain with no ghost pet prompt", sheltered and int(GameState.flags.get("ambient_cat_pets", 0)) == pets_before)
	GameState.weather = "sunny"
	var returned: bool = true
	for index: int in main.life.cats.size():
		main.world.set_region("farm" if index == 2 else "town")
		await t.frames(3)
		var target: Interactable = main.life.get_node_or_null("CatInteract_%d" % index) as Interactable
		returned = returned and main.life.cats[index].node.is_visible_in_tree() and main.life.cats[index].node.global_position.distance_to(positions[index]) < .001 and target != null and target.is_visible_in_tree() and absf(target.radius - 1.9) < .001
	check("after rain the same cats and pet targets return to their supported places", returned)
	main.world.set_region("town")
	var flock: Dictionary = main.life.flocks[0]
	var bird: Dictionary = flock.birds[0]
	var longest_edge: float = 0
	for pivot: Node3D in bird.anim.wings:
		for node: Node in pivot.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			for surface: int in mesh.mesh.get_surface_count():
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var count: int = indices.size() if not indices.is_empty() else vertices.size()
				for offset: int in range(0, count - 2, 3):
					for edge: int in range(3):
						var first: int = indices[offset + edge] if not indices.is_empty() else offset + edge
						var second: int = indices[offset + (edge + 1) % 3] if not indices.is_empty() else offset + (edge + 1) % 3
						longest_edge = maxf(longest_edge, vertices[first].distance_to(vertices[second]))
	check("sparrow wings keep a compact feather outline without giant triangle blades", longest_edge < .06 and WorldBuilder.local_aabb(bird.node).size.x < .33)
	var old_processing: bool = main.life.is_processing()
	main.life.set_process(false)
	var old_state: String = flock.state
	var old_timer: float = flock.timer
	var old_birds: Array[Dictionary] = []
	for member: Dictionary in flock.birds:
		old_birds.append({"position": member.node.position, "rotation": member.node.rotation,
			"visible": member.node.visible, "velocity": member.vel, "phase": member.anim.phase})
		member.vel = Vector3(3, 2, 0)
	flock.state = "fly"
	flock.timer = 0
	main.life._update_flock(flock, .25, Vector3(-100, 0, -100))
	check("takeoff leans the bird body toward actual flight rather than backwards", bird.node.rotation.x > .25)
	flock.state = old_state
	flock.timer = old_timer
	for index: int in flock.birds.size():
		var restored_bird: Dictionary = flock.birds[index]
		restored_bird.node.position = old_birds[index].position
		restored_bird.node.rotation = old_birds[index].rotation
		restored_bird.node.visible = old_birds[index].visible
		restored_bird.vel = old_birds[index].velocity
		restored_bird.anim.phase = old_birds[index].phase
	main.life.set_process(old_processing)

func _insect_checks() -> void:
	var butterfly_ok: bool = false
	var dragonfly_ok: bool = false
	for entry: Dictionary in main.life.flyers:
		if entry.kind == "butterfly" and not butterfly_ok:
			var butterfly_wing: MeshInstance3D = entry.l as MeshInstance3D
			butterfly_ok = entry.node.get_node_or_null("Body") != null and entry.node.get_node_or_null("Antenna_-1") != null and entry.node.get_node_or_null("Antenna_1") != null and not butterfly_wing.mesh is QuadMesh and butterfly_wing.mesh.get_aabb().size.z > .04
		if entry.kind == "dragonfly" and not dragonfly_ok:
			dragonfly_ok = entry.node.get_node_or_null("Eyes") != null and entry.node.get_node_or_null("Body") != null and entry.wings.size() == 4
			for dragon_wing: MeshInstance3D in entry.wings:
				var material: StandardMaterial3D = dragon_wing.material_override as StandardMaterial3D
				dragonfly_ok = dragonfly_ok and not dragon_wing.mesh is QuadMesh and material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and not (dragon_wing.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray).is_empty()
	check("butterflies have curved lobed wings, a body and two antennae", butterfly_ok)
	check("dragonflies have four translucent curved wings and an actual segmented body", dragonfly_ok)

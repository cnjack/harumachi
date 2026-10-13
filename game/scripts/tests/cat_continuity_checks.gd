extends RefCounted
## Two physical cats, continuous motion, and the same animals after weather/region changes.
var t: Object
var main: Node
const CAT_MODELS: Array[String] = ["G08_cat", "A20_cat_sleep", "A22_cat_sit", "AN_cat_orange_walk", "AN_cat_calico_walk"]

func _init(runner: Object) -> void:
	t = runner
	main = runner.main

func check(label: String, passed: bool, detail: String = "") -> void:
	t.check("CAT_CONTINUITY", label, passed, detail)

func _physical_cats(root: Node, found: Array[Node3D]) -> void:
	if root is Node3D and str(root.get_meta("model_id", "")) in CAT_MODELS: found.append(root as Node3D)
	for child: Node in root.get_children(): _physical_cats(child, found)

func run() -> void:
	var original: Dictionary = GameState.to_dict().duplicate(true)
	var region_before: String = main.world.region
	var indoor_before: bool = main.world.indoor
	var public_before: String = main.world.public_interior_kind
	var life_was_processing: bool = main.life.is_processing()
	GameState.clock_paused = true
	GameState.weather = "sunny"
	GameState.minute = 630
	main.world.set_region("town")
	main.world.set_indoor_look(false)
	main.player.global_position = Vector3(-30, .05, 20)
	await t.frames(3)
	var all: Array[Node3D] = []
	_physical_cats(main, all)
	var cats: Array = main.life.roaming_cats
	check("the entire world contains exactly two physical cat models", all.size() == 2 and cats.size() == 2, "%d physical models; %d controllers" % [all.size(), cats.size()])
	check("walls, farm benches and the house contain no additional static cats", all.all(func(cat: Node3D) -> bool: return str(cat.get_meta("model_id", "")).begins_with("AN_cat_")))
	check("the removed home cat leaves no ghost interaction", main.find_child("P_house_cat", true, false) == null)
	var good_speed: bool = cats.size() == 2
	for cat: CharacterBody3D in cats: good_speed = good_speed and cat.speed >= .32 and cat.speed <= .45
	check("normal walking is a natural 0.32 to 0.45 metres per second", good_speed)
	var saved: Array[Dictionary] = []
	var places: Array[Vector3] = []
	for cat: CharacterBody3D in cats:
		saved.append(cat.snapshot().duplicate(true)); places.append(cat.global_position)
		cat.set_physics_process(false)
	main.life.set_process(false)
	var weather_visible: bool = cats.size() == 2
	var weather_continuous: bool = cats.size() == 2
	for moment: Array in [["rain", 630], ["sunny", 1380], ["sunny", 630]]:
		GameState.weather = moment[0]; GameState.minute = moment[1]
		main.life._process(0.0)
		for index: int in cats.size():
			var cat: CharacterBody3D = cats[index]
			weather_visible = weather_visible and cat.visible
			weather_continuous = weather_continuous and cat.global_position.distance_to(places[index]) < .0001
	check("rain and night never make either cat disappear", weather_visible)
	check("rain and night transitions never relocate either cat", weather_continuous)
	var region_continuous: bool = cats.size() == 2
	for region: String in ["farm", "town"]:
		main.world.set_region(region)
		main.life._process(0.0)
		for index: int in cats.size():
			var cat: CharacterBody3D = cats[index]
			region_continuous = region_continuous and cat.global_position.distance_to(places[index]) < .0001
			if region == "farm": region_continuous = region_continuous and not cat.is_physics_processing()
	check("leaving and returning resumes the same cats at their exact positions", region_continuous)
	var targets_follow: bool = main.life.cats.size() == 2
	for entry: Dictionary in main.life.cats:
		targets_follow = targets_follow and entry.node in cats and entry.interact.global_position.distance_to(entry.node.global_position + Vector3(0, .3, 0)) < .03
	check("pet prompts follow the two physical cats rather than abandoned wall locations", targets_follow)
	# Measure real fixed-step movement including turns, yields and changing animation clips.
	main.life._process(0.0)
	var previous: Array[Vector3] = []
	var max_step: Array[float] = [0.0, 0.0]
	var distance: Array[float] = [0.0, 0.0]
	var grounded: bool = cats.size() == 2
	for cat: CharacterBody3D in cats:
		previous.append(cat.global_position)
		cat.rest_left = 0.0; cat.rest_pose = "Idle"; cat.locomotion = "Walk"
		cat.set_physics_process(true)
	var old_scale: float = Engine.time_scale
	Engine.time_scale = 4.0
	for frame: int in range(420):
		await main.get_tree().physics_frame
		for index: int in cats.size():
			var cat: CharacterBody3D = cats[index]
			var step: float = cat.global_position.distance_to(previous[index])
			max_step[index] = maxf(max_step[index], step)
			distance[index] += step
			previous[index] = cat.global_position
			grounded = grounded and absf(cat.global_position.y) < .035
	Engine.time_scale = old_scale
	check("every runtime step stays within physical movement limits without teleporting", max_step.all(func(step: float) -> bool: return step < .065), str(max_step))
	check("both cats actually travel more than one metre through the rendered scene", distance.all(func(value: float) -> bool: return value > 1.0), str(distance))
	check("both cats remain on actual ground while roaming", grounded)
	var no_runtime_relocation: bool = true
	for index: int in cats.size():
		var cat: CharacterBody3D = cats[index]
		var here: Vector3 = cat.global_position
		cat.waiting_for_spawn = true; cat.rest_left = 0.0
		cat._physics_process(.02)
		no_runtime_relocation = no_runtime_relocation and cat.global_position.distance_to(here) < .0001
		cat.waiting_for_spawn = false
	check("waiting for a blocked entry cannot reset a live cat to a random anchor", no_runtime_relocation)
	for index: int in cats.size(): cats[index].reset_behaviour(int(saved[index].seed), saved[index])
	main.life.set_process(life_was_processing)
	GameState.from_dict(original)
	main.world.set_region(region_before)
	main.world.set_indoor_look(indoor_before, public_before)
	main.life._process(0.0)

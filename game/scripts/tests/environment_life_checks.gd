extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void: t=runner; main=runner.main
func check(label: String, ok: bool, detail: String="") -> void: t.check("ENVIRONMENT_LIFE",label,ok,detail)
func run() -> void:
	var life: Node = main.get_node_or_null("EnvironmentLife")
	check("shared outdoor environment controller is present",life!=null)
	check("daisies, reeds, clover and seed grasses exist",main.world.get_meta("meadow_detail_count",0)>80)
	check("eave wind chimes are actually placed",life!=null and life.get("chimes").size()>=3)
	check("falling leaves come from real tree crowns",life!=null and life.get("leaf_sources").size()>=8)
	check("weather drives cloud cover and the visible sun",main.world.sky_mat.get_shader_parameter("cloud_cover")!=null and main.world.sky_mat.get_shader_parameter("sun_direction")!=null)
	check("river shader accepts linked rain ripples",main.world.farm.water_mat.get_shader_parameter("rain_amount")!=null)
	if life==null:return
	var saved: Dictionary=GameState.to_dict().duplicate(true)
	var previous_region: String=main.world.region
	main.world.set_region("town");main.world.set_indoor_look(false)
	GameState.weather="sunny";GameState.minute=630;life.tick(.1)
	var sunny: Dictionary=life.state.duplicate(true)
	GameState.weather="rain";life.tick(.1)
	check("rain strengthens the shared wind and cloud cover",life.state.wind>sunny.wind and life.state.cloud_cover>sunny.cloud_cover)
	check("rain hides the sun and enables water ripples",life.state.sun_visibility==0.0 and main.world.farm.water_mat.get_shader_parameter("rain_amount")==1.0)
	check("rain streaks lean with the same wind direction",main.weather_fx.rain.process_material.direction.x>0.0)
	var pivot: Node3D=life.chimes[0].pivot
	var mount: Vector3=pivot.position
	life.elapsed=2.0;life.tick(0.0);var first: Vector3=pivot.rotation
	life.elapsed=3.0;life.tick(0.0)
	check("chime body sways without moving its suspension point",pivot.position==mount and pivot.rotation.distance_to(first)>.01)
	var source: Dictionary=life.leaf_sources[0]
	var leaf: Dictionary=life.emit_leaf(source)
	var leaf_start: Vector3=leaf.node.global_position
	var leaf_previous: Vector3=leaf_start
	var horizontal_travel: float=0.0
	# Flutter can cancel wind displacement at one instant. Measure the actual
	# path over several intervals instead of treating that phase as no movement.
	for interval: int in 3:
		life.tick(.3)
		var leaf_now: Vector3=leaf.node.global_position
		horizontal_travel+=Vector2(leaf_now.x-leaf_previous.x,leaf_now.z-leaf_previous.z).length()
		leaf_previous=leaf_now
	check("windborne leaves fall and drift",leaf.node.global_position.y<leaf_start.y and horizontal_travel>.01,"horizontal path=%.5f m"%horizontal_travel)
	for index: int in 90:life.emit_leaf(source)
	check("falling leaves have a bounded pool",life.leaves.size()<=life.MAX_LEAVES)
	GameState.weather="sunny";main.world.set_region("farm")
	main.player.global_position=FarmBuilder.ORIGIN+Vector3(10,.1,12);life.tick(.1)
	var near_gain: float=life.river_gain
	main.player.global_position=FarmBuilder.ORIGIN+Vector3(10,.1,-9);life.tick(.1)
	check("river sound follows actual distance to water",near_gain>life.river_gain+.08)
	check("reeds stay on banks and leave paths and fishing stands open",life.plants.safe_reeds())
	check("small plants are rooted at rendered terrain height",life.plants.rooted())
	check("vegetation stays in bounded patches",life.plants.batch_count>0 and life.plants.batch_count<70)
	check("meadow and reeds use the actual textured Hyper3D assets",life.plants.roots.all(func(entry: Dictionary):return entry.node.get_meta("model_id","") in ["V04_daisy_meadow","V05_river_reeds"]))
	check("wind chimes use the generated model with a separate paper hinge",life.chimes.all(func(chime: Dictionary):return chime.model.get_meta("model_id","")=="E01_furin" and chime.paper.get_child_count()>0))
	var provider_stats: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/_stats/V04_daisy_meadow.json"))
	check("formal meadow retains a detailed mesh and 2K painted texture",int(provider_stats.get("tris",0))>=10000 and int(provider_stats.get("tex",0))>=2048)
	check("river and leaf loops are loaded on the ambience bus",life.river_audio.stream!=null and life.wind_audio.stream!=null and life.river_audio.bus=="Ambience")
	main.world.set_indoor_look(true);life.tick(.1)
	check("indoors silence outdoor loops and clear leaves",life.river_gain==0.0 and life.wind_gain==0.0 and life.leaves.is_empty() and not life.chimes[0].sound.playing)
	main.weather_fx.set_weather("rain",true)
	check("indoors stop rain emissions",not main.weather_fx.rain.emitting and not main.weather_fx.rain.visible)
	main.world.set_indoor_look(false);main.world.set_region("town");GameState.weather="rain";main.life._process(0.0)
	check("rain suspends butterflies and roaming cats",main.life.flyers.all(func(f: Dictionary):return not f.node.visible) and main.life.roaming_cats.all(func(c: CharacterBody3D):return not c.is_physics_processing()))
	GameState.from_dict(saved);main.world.set_region(previous_region);main.world.set_indoor_look(false)

class_name EnvironmentLife
extends Node3D
## Shared wind, weather, crown leaves, eave chimes and distance-based outdoor sound.
const MAX_LEAVES := 48
const WEATHER := {
	"sunny":{"wind":1.0,"cloud_cover":.28,"rain":0.0,"sun_visibility":1.0},
	"cloudy":{"wind":1.35,"cloud_cover":.70,"rain":0.0,"sun_visibility":.28},
	"rain":{"wind":2.1,"cloud_cover":.96,"rain":1.0,"sun_visibility":0.0},
}
var world: WorldBuilder
var player: Node3D
var plants: MeadowDetails
var chimes: Array[Dictionary] = []
var leaf_sources: Array[Dictionary] = []
var leaves: Array[Dictionary] = []
var state: Dictionary = {}
var elapsed := 0.0
var wind_direction := Vector2(.8,.6)
var wind_power := 1.0
var river_audio: AudioStreamPlayer
var wind_audio: AudioStreamPlayer
var river_gain := 0.0
var wind_gain := 0.0
var rng := RandomNumberGenerator.new()
var _leaf_timer := 0.0
var _sky_timer := 0.0
var _sky_weather := ""
var _sky_indoor := false
var _region := ""
var _leaf_mesh: ArrayMesh
var _leaf_material: StandardMaterial3D

func setup(w: WorldBuilder,p: Node3D) -> void:
	world=w;player=p;rng.seed=606106
	plants=MeadowDetails.new();plants.build(world)
	_leaf_mesh=_make_leaf()
	_leaf_material=_matte(Color(.56,.69,.27));_leaf_material.vertex_color_use_as_albedo=true
	for node: Node in world.find_children("*","Node3D",true,false):
		var id: String=str(node.get_meta("model_id",""))
		if not id.begins_with("T0"):continue
		var tree:=node as Node3D
		var box: AABB=tree.global_transform*WorldBuilder.local_aabb(tree)
		if box.size.y<2.0:continue
		leaf_sources.append({"center":Vector3(box.get_center().x,box.end.y-box.size.y*.22,box.get_center().z),
			"radius":minf(box.size.x,box.size.z)*.30,"floor":box.position.y,"region":"farm" if tree.global_position.x>500 else "town"})
	for index: int in 3:
		var at: Vector3=[Vector3(-1.25,2.65,-15.7),Vector3(-12.6,2.6,-15.5),Vector3(22.9,2.55,5.4)][index]
		_build_chime(at,index)
	river_audio=_loop("amb/river_close.ogg","RiverNearWater")
	wind_audio=_loop("amb/leaves_wind.ogg","BreezeInLeaves")
	tick(0.0)

static func wind_at(time_value: float,weather: String) -> float:
	var profile: Dictionary=WEATHER.get(weather,WEATHER.sunny)
	return float(profile.wind)*(.84+.20*sin(time_value*.43)+.10*sin(time_value*1.07))

func _process(delta: float) -> void:
	if world!=null:tick(delta)

func tick(delta: float) -> void:
	elapsed+=delta
	state=(WEATHER.get(GameState.weather,WEATHER.sunny) as Dictionary).duplicate()
	wind_power=wind_at(Time.get_ticks_msec()/1000.0,GameState.weather)
	wind_direction=Vector2(.8+.12*sin(elapsed*.09),.6).normalized()
	RenderingServer.global_shader_parameter_set("wind_strength",wind_power)
	RenderingServer.global_shader_parameter_set("wind_direction",wind_direction)
	world.farm.water_mat.set_shader_parameter("rain_amount",state.rain)
	world.farm.water_mat.set_shader_parameter("wave_strength",clampf(wind_power,.65,2.7))
	_sky_timer-=delta
	if _sky_timer<=0.0 or _sky_weather!=GameState.weather or _sky_indoor!=world.indoor:
		world.sky_mat.set_shader_parameter("cloud_cover",state.cloud_cover)
		world.sky_mat.set_shader_parameter("sun_visibility",state.sun_visibility if not world.indoor else 0.0)
		var outdoor_direction: Vector3=Basis.from_euler(world.look.get("rot",Vector3(-48,-35,0))*PI/180.0).z.normalized()
		world.sky_mat.set_shader_parameter("sun_direction",outdoor_direction)
		world.sky_mat.set_shader_parameter("cloud_offset",Vector2(elapsed*.007,elapsed*.003))
		_sky_timer=.8;_sky_weather=GameState.weather;_sky_indoor=world.indoor
	var region: String=world.region
	if world.indoor or region!=_region:
		_clear_leaves();_region=region
	_update_chimes(delta)
	_update_sound(delta)
	if world.indoor:return
	_leaf_timer-=delta
	if _leaf_timer<=0.0:
		var nearby: Array[Dictionary]=[]
		for source: Dictionary in leaf_sources:
			if source.region==region and source.center.distance_to(player.global_position)<32.0:nearby.append(source)
		if not nearby.is_empty():emit_leaf(nearby[rng.randi_range(0,nearby.size()-1)])
		_leaf_timer=rng.randf_range(.4,1.1)/maxf(wind_power,.5)
	for leaf: Dictionary in leaves.duplicate():
		leaf.age+=delta
		var age: float=leaf.age
		var position_value: Vector3=leaf.origin+Vector3(wind_direction.x,0,wind_direction.y)*age*wind_power*.42
		position_value.y-=age*.53
		position_value.x+=sin(age*2.3+leaf.phase)*.18
		position_value.z+=cos(age*1.8+leaf.phase)*.14
		leaf.node.global_position=position_value
		leaf.node.rotation=Vector3(sin(age*2.4+leaf.phase)*.7,age*.8+leaf.phase,cos(age*1.7)*.5)
		if position_value.y<=float(leaf.floor)+.025 or age>12.0:
			leaf.node.queue_free();leaves.erase(leaf)

func emit_leaf(source: Dictionary) -> Dictionary:
	if leaves.size()>=MAX_LEAVES:
		leaves[0].node.queue_free();leaves.pop_front()
	var node:=MeshInstance3D.new();node.name="WindLeaf_%d"%rng.randi()
	node.mesh=_leaf_mesh;node.material_override=_leaf_material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var origin: Vector3=source.center+Vector3(rng.randf_range(-source.radius,source.radius),rng.randf_range(-.35,.35),rng.randf_range(-source.radius,source.radius))
	node.global_position=origin
	node.scale=Vector3.ONE*rng.randf_range(.75,1.25)
	var leaf: Dictionary={"node":node,"origin":origin,"age":0.0,"phase":rng.randf()*TAU,"floor":source.floor}
	leaves.append(leaf);return leaf

func _clear_leaves() -> void:
	for leaf: Dictionary in leaves:leaf.node.queue_free()
	leaves.clear()

func _update_chimes(delta: float) -> void:
	for chime: Dictionary in chimes:
		chime.pivot.visible=not world.indoor and world.region=="town"
		var phase: float=elapsed*1.7+chime.phase
		var tilt: float=sin(phase)*.075*wind_power
		chime.pivot.rotation=Vector3(tilt*.65,0,tilt)
		chime.paper.rotation.z=sin(phase*1.6+.5)*.22*wind_power
		chime.wait=maxf(0.0,float(chime.wait)-delta)
		var audible: bool=chime.pivot.visible and Audio.game_on and chime.pivot.global_position.distance_to(player.global_position)<13.0
		if not audible:
			chime.sound.stop();continue
		# A strike happens after a swing crosses its center, with a quiet irregular rest.
		if signf(tilt)!=signf(float(chime.previous)) and chime.wait<=0.0 and absf(tilt-float(chime.previous))>.0001:
			chime.sound.pitch_scale=rng.randf_range(.95,1.07)
			chime.sound.volume_db=-16.0+minf(wind_power,2.3)*2.0
			chime.sound.play();chime.wait=rng.randf_range(2.8,6.0)/maxf(wind_power,.8)
		chime.previous=tilt

func _update_sound(delta: float) -> void:
	var outdoors:=not world.indoor
	var local: Vector3=player.global_position-FarmBuilder.ORIGIN
	var distance: float=maxf(0.0,LakesideLayout.water_distance(Vector2(local.x,local.z)))
	river_gain=(1.0-smoothstep(2.0,22.0,distance))*(1.0 if local.x<74.0 else .42) if outdoors and world.region=="farm" else 0.0
	wind_gain=clampf(wind_power*.16,0,.42) if outdoors else 0.0
	for pair: Array in [[river_audio,river_gain],[wind_audio,wind_gain]]:
		var audio: AudioStreamPlayer=pair[0]
		var gain: float=pair[1] if Audio.game_on else 0.0
		if gain<=0.0:audio.stop();audio.volume_db=-60.0;continue
		if not audio.playing:audio.play()
		audio.volume_db=linear_to_db(maxf(lerpf(db_to_linear(audio.volume_db),gain*.5,1.0-exp(-delta*2.5)),.001))

func _loop(path: String,node_name: String) -> AudioStreamPlayer:
	var audio:=AudioStreamPlayer.new();audio.name=node_name;audio.bus="Ambience"
	audio.stream=Audio.stream(path);audio.volume_db=-60;add_child(audio);return audio

static func _matte(colour: Color) -> StandardMaterial3D:
	var material_value:=StandardMaterial3D.new();material_value.albedo_color=colour
	material_value.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON
	material_value.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
	material_value.roughness=1.0;material_value.cull_mode=BaseMaterial3D.CULL_DISABLED
	return material_value

func _build_chime(at: Vector3,index: int) -> void:
	var pivot:=Node3D.new();pivot.name="EaveChime_%d"%index;add_child(pivot);pivot.position=at
	var model:=world.spawn("E01_furin",Vector3.ZERO,0.0,0,pivot)
	assert(model!=null,"Validated Hyper3D wind chime is required")
	model.set_meta("suspended",true)
	HouseBuilder.toonify(model)
	var paper:=model.find_child("PaperPivot",true,false) as Node3D
	assert(paper!=null,"Paper tag must retain its independent hinge")
	var sound:=AudioStreamPlayer3D.new();sound.name="ChimeStrike";sound.bus="Ambience";sound.max_distance=14.0;sound.unit_size=2.0
	sound.stream=Audio.stream("sfx/wind_chime.wav");pivot.add_child(sound)
	chimes.append({"pivot":pivot,"model":model,"paper":paper,"sound":sound,"phase":float(index)*1.9,"wait":2.0+index,"previous":0.0})

func _make_leaf() -> ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3]=[Vector3(0,.012,0),Vector3(-.035,0,-.025),Vector3(0,0,-.085),Vector3(.035,0,-.025),Vector3(0,0,.085)]
	for triangle: Array in [[0,1,2],[0,2,3],[0,3,4],[0,4,1]]:
		for index: int in triangle:
			st.set_color(Color(.74,.84,.48) if index==0 else Color(.65,.75,.41));st.set_normal(Vector3.UP);st.add_vertex(points[index])
	return st.commit()

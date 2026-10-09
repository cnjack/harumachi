class_name WeatherFX
extends Node3D
## Rain around the camera on rainy days (outdoors only): thin falling streaks plus a light mist.

var rig: Node3D
var rain: GPUParticles3D
var _on := false


func _ready() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 1400
	rain.lifetime = 0.9
	rain.preprocess = 0.9
	rain.visibility_aabb = AABB(Vector3(-16, -14, -16), Vector3(32, 28, 32))
	rain.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 0.5, 14)
	pm.direction = Vector3(0.12, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 15.0
	pm.initial_velocity_max = 19.0
	pm.gravity = Vector3(0, -6, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.albedo_color = Color(0.78, 0.85, 0.98, 0.32)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gt := GradientTexture2D.new()
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 1.0))
	gt.gradient = g
	m.albedo_texture = gt
	q.material = m
	rain.draw_pass_1 = q
	rain.emitting = false
	rain.visible = false
	add_child(rain)


func set_weather(w: String, indoor: bool) -> void:
	var on := w == "rain" and not indoor
	if on == _on:
		return
	_on = on
	rain.visible = on
	rain.emitting = on


func _process(_delta: float) -> void:
	if _on and rig:
		rain.global_position = rig.global_position + Vector3(0, 9.0, 0)
		var power: float=EnvironmentLife.wind_at(Time.get_ticks_msec()/1000.0,GameState.weather)
		var material_value:=rain.process_material as ParticleProcessMaterial
		material_value.direction=Vector3(.8*power*.12,-1,.6*power*.12).normalized()

class_name WeatherFX
extends Node3D
## Rain around the camera on rainy days (outdoors only): thin falling streaks plus a light mist.

var rig: Node3D
var rain: GPUParticles3D
var _on := false
var _clip_rect := Rect2()
var _rain_material: ShaderMaterial
const ShelterMap = preload("res://scripts/world/rain_shelter_map.gd")
var _stall_shelter: ShelterMap
var _shelter_transform := Transform3D.IDENTITY
var _shelter_visible := false
const RAIN_AMOUNT := 1400
const RAIN_EXTENT := 14.0


func _ready() -> void:
	rain = GPUParticles3D.new()
	rain.amount = RAIN_AMOUNT
	rain.lifetime = 0.9
	rain.preprocess = 0.9
	rain.visibility_aabb = AABB(Vector3(-16, -14, -16), Vector3(32, 28, 32))
	rain.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(RAIN_EXTENT, 0.5, RAIN_EXTENT)
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
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = preload("res://shaders/rain_streak.gdshader")
	q.material = _rain_material
	rain.draw_pass_1 = q
	rain.emitting = false
	rain.visible = false
	add_child(rain)
	prepare_stall_shelter()


func set_weather(w: String, indoor: bool, exposed_rect: Rect2 = Rect2()) -> void:
	prepare_stall_shelter()
	var on := w == "rain" and not indoor
	var next_rect: Rect2 = exposed_rect if on and exposed_rect.has_area() else Rect2()
	if on == _on and next_rect == _clip_rect:
		return
	var region_changed: bool = next_rect != _clip_rect
	_clip_rect = next_rect
	_rain_material.set_shader_parameter("clip_region", _clip_rect.has_area())
	_rain_material.set_shader_parameter("clip_rect", Vector4(_clip_rect.position.x, _clip_rect.position.y, _clip_rect.end.x, _clip_rect.end.y))
	var pm: ParticleProcessMaterial = rain.process_material as ParticleProcessMaterial
	if _clip_rect.has_area():
		pm.emission_box_extents = Vector3(_clip_rect.size.x * .5, .5, _clip_rect.size.y * .5)
		# A small uncovered yard receives the same drops per square metre as
		# the 28m outdoor volume, rather than all 1400 drops compressed indoors.
		rain.amount = maxi(1, roundi(float(RAIN_AMOUNT) * _clip_rect.get_area() / pow(RAIN_EXTENT * 2.0, 2.0)))
	else:
		pm.emission_box_extents = Vector3(RAIN_EXTENT, .5, RAIN_EXTENT)
		rain.amount = RAIN_AMOUNT
	_update_origin()
	if on and (not _on or region_changed):
		rain.restart()
	_on = on
	rain.visible = on
	rain.emitting = on


func _process(_delta: float) -> void:
	if _on and rig:
		_update_origin()
		prepare_stall_shelter()
		var power: float=EnvironmentLife.wind_at(Time.get_ticks_msec()/1000.0,GameState.weather)
		var material_value:=rain.process_material as ParticleProcessMaterial
		material_value.direction=Vector3(.8*power*.12,-1,.6*power*.12).normalized()


func _update_origin() -> void:
	if not is_instance_valid(rig): return
	if _clip_rect.has_area():
		var centre: Vector2 = _clip_rect.get_center()
		rain.global_position = Vector3(centre.x, rig.global_position.y + 9.0, centre.y)
	else:
		rain.global_position = rig.global_position + Vector3(0, 9.0, 0)


func prepare_stall_shelter() -> bool:
	if _rain_material==null:return false
	var stall: Node3D=get_parent().get_node_or_null("World/P09") as Node3D
	if not is_instance_valid(stall):
		_stall_shelter=null
		_shelter_visible=false
		_rain_material.set_shader_parameter("shelter_enabled",false)
		return false
	if _stall_shelter==null or _stall_shelter.model()!=stall:
		var measured: ShelterMap=ShelterMap.new()
		if not measured.build(stall):
			_rain_material.set_shader_parameter("shelter_enabled",false)
			return false
		_stall_shelter=measured
		var rect: Rect2=_stall_shelter.rectangle
		_rain_material.set_shader_parameter("shelter_height",_stall_shelter.texture)
		_rain_material.set_shader_parameter("shelter_rect",Vector4(rect.position.x,rect.position.y,rect.end.x,rect.end.y))
		_rain_material.set_shader_parameter("shelter_surface_margin",ShelterMap.SURFACE_MARGIN)
		_shelter_transform=Transform3D()
		_shelter_visible=not stall.is_visible_in_tree()
	if _shelter_transform!=stall.global_transform or _shelter_visible!=stall.is_visible_in_tree():
		_shelter_transform=stall.global_transform
		_shelter_visible=stall.is_visible_in_tree()
		_rain_material.set_shader_parameter("shelter_world_to_local",Projection(_shelter_transform.affine_inverse()))
		_rain_material.set_shader_parameter("shelter_enabled",_shelter_visible)
	return true


func rain_is_sheltered_at(world_point: Vector3) -> bool:
	return prepare_stall_shelter() and _stall_shelter.sheltered_at(world_point)


func rain_shelter_status() -> Dictionary:
	return _stall_shelter.metadata() if prepare_stall_shelter() else {}

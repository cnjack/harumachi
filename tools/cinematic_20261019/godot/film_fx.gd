extends Node3D
## Deterministic fireworks: every spark is a function of film time, so a slow
## frame capture cannot outrun the simulation.

var cam: Camera3D
var bursts: Array[Dictionary] = []
var mesh: ImmediateMesh
var mesh_instance: MeshInstance3D
var material: StandardMaterial3D
var flash_light: OmniLight3D


func setup(camera: Camera3D, events: Array[Dictionary]) -> void:
	cam = camera
	mesh = ImmediateMesh.new()
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	add_child(mesh_instance)
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.82, 0.6)
	flash_light.omni_range = 34.0
	flash_light.light_energy = 0.0
	flash_light.shadow_enabled = false
	add_child(flash_light)
	for event: Dictionary in events:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(event.get("seed", 1))
		var count: int = int(event.get("count", 80))
		var origin: Vector3 = event.get("pos", Vector3.ZERO)
		var burst_color: Color = event.get("color", Color.WHITE)
		var sparks: Array[Dictionary] = []
		for i in count:
			var direction := Vector3(
				rng.randf_range(-1.0, 1.0),
				rng.randf_range(-0.32, 1.0),
				rng.randf_range(-1.0, 1.0)).normalized()
			sparks.append({
				"dir": direction,
				"speed": rng.randf_range(float(event.get("speed_min", 7.0)), float(event.get("speed_max", 12.0))),
				"life": rng.randf_range(float(event.get("life_min", 1.2)), float(event.get("life_max", 2.3))),
			})
		bursts.append({
			"time": float(event.get("time", 0.0)),
			"pos": origin,
			"color": burst_color,
			"rise": float(event.get("rise", 0.9)),
			"sparks": sparks,
			"flash_size": float(event.get("flash_size", 2.6)),
		})


func update_time(t: float) -> void:
	if cam == null or not is_instance_valid(cam) or mesh == null:
		return
	mesh.clear_surfaces()
	var right: Vector3 = cam.global_transform.basis.x
	var up: Vector3 = cam.global_transform.basis.y
	var started := false
	var best_energy := 0.0
	var best_pos := Vector3.ZERO
	for burst: Dictionary in bursts:
		var age: float = t - float(burst["time"])
		var rise: float = float(burst["rise"])
		if age < -rise or age > 2.9:
			continue
		if not started:
			mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
			started = true
		var burst_pos: Vector3 = burst["pos"]
		if age < 0.0 and rise > 0.001:
			_draw_shell(burst, age, rise, right, up)
			best_energy = maxf(best_energy, 1.2)
			best_pos = burst_pos
		elif age >= 0.0:
			_draw_burst(burst, age, right, up)
			if float(burst["flash_size"]) < 1.0:
				continue
			var energy: float = maxf(0.0, 1.0 - age) * (1.5 + float(burst["flash_size"]))
			if energy > best_energy:
				best_energy = energy
				best_pos = burst_pos
	if started:
		mesh.surface_end()
	if is_instance_valid(flash_light):
		if best_energy > 0.05:
			flash_light.global_position = best_pos + Vector3(0.0, -1.0, 0.0)
			flash_light.light_energy = best_energy
		else:
			flash_light.light_energy = 0.0


func _draw_shell(burst: Dictionary, age: float, rise: float, right: Vector3, up: Vector3) -> void:
	var target: Vector3 = burst["pos"]
	var start: Vector3 = target + Vector3(0.0, -11.0, 8.0)
	var u: float = clampf(1.0 + age / rise, 0.0, 1.0)
	var eased: float = u * u * (3.0 - 2.0 * u)
	var head: Vector3 = start.lerp(target, eased)
	var tail: Vector3 = start.lerp(target, maxf(0.0, eased - 0.18))
	var color := Color(1.0, 0.84, 0.5, 0.9)
	_ribbon(tail, head, 0.05, color, right, up)
	_glow(head, 0.24, color, right, up)


func _draw_burst(burst: Dictionary, age: float, right: Vector3, up: Vector3) -> void:
	var origin: Vector3 = burst["pos"]
	var base_color: Color = burst["color"]
	var sparks: Array = burst["sparks"]
	for spark: Dictionary in sparks:
		var life: float = float(spark["life"])
		if age > life:
			continue
		var frac: float = age / life
		var drag := 2.1
		var distance: float = float(spark["speed"]) * (1.0 - exp(-drag * age)) / drag
		var previous_distance: float = float(spark["speed"]) * (1.0 - exp(-drag * maxf(0.0, age - 0.08))) / drag
		var direction: Vector3 = spark["dir"]
		var head: Vector3 = origin + direction * distance + Vector3(0.0, -1.35 * age * age, 0.0)
		var tail: Vector3 = origin + direction * previous_distance + Vector3(0.0, -1.35 * maxf(0.0, age - 0.08) * maxf(0.0, age - 0.08), 0.0)
		var color: Color = base_color.lerp(Color(1.0, 1.0, 1.0, 1.0), clampf(1.0 - frac * 3.2, 0.0, 1.0))
		color.a = pow(1.0 - frac, 1.45) * 0.95
		color = color * 1.4
		_ribbon(tail, head, 0.05 * (1.0 - frac * 0.55), color, right, up)
		_glow(head, 0.12 * (1.0 - frac * 0.35), color, right, up)
	if age < 0.55:
		var fade: float = 1.0 - age / 0.55
		var flash_color := base_color
		flash_color.a = fade * fade * 0.4
		_glow(origin, float(burst["flash_size"]) * (1.0 + age * 2.2), flash_color, right, up)


func _ribbon(a: Vector3, b: Vector3, width: float, color: Color, right: Vector3, up: Vector3) -> void:
	if a.distance_squared_to(b) < 0.000001:
		return
	var view: Vector3 = (b - a).normalized()
	var side: Vector3 = right - view * right.dot(view)
	if side.length_squared() < 0.0001:
		side = up - view * up.dot(view)
	if side.length_squared() < 0.0001:
		return
	side = side.normalized() * width
	var p0: Vector3 = a - side
	var p1: Vector3 = a + side
	var p2: Vector3 = b + side
	var p3: Vector3 = b - side
	_vertex(p0, color)
	_vertex(p1, color)
	_vertex(p2, color)
	_vertex(p0, color)
	_vertex(p2, color)
	_vertex(p3, color)


func _glow(center: Vector3, size: float, color: Color, right: Vector3, up: Vector3) -> void:
	var edge := Color(color.r, color.g, color.b, 0.0)
	var segments := 10
	var prev := center + right * size
	for i in range(1, segments + 1):
		var angle := float(i) / float(segments) * TAU
		var point := center + right * (cos(angle) * size) + up * (sin(angle) * size)
		_vertex(center, color)
		_vertex(prev, edge)
		_vertex(point, edge)
		prev = point


func _vertex(point: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(point)

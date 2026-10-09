class_name FestivalFX
extends Node3D
## Fireworks over the far bank of the river (hanabi) and paper lanterns drifting down it (obon).

var shells: Array[GPUParticles3D] = []
var flashes: Array[OmniLight3D] = []
var fireworks_on := false
var rate := 1.0              # bursts per second
var _t := 0.0
var _i := 0
var lanterns: Array = []     # [{node, speed, bob}]
var lantern_scene: PackedScene
var lanterns_on := false
var _lt := 0.0
const PALETTE := [Color(1.0, 0.82, 0.35), Color(1.0, 0.45, 0.4), Color(0.55, 0.8, 1.0), Color(0.7, 1.0, 0.55), Color(1.0, 0.6, 0.95), Color(1.0, 1.0, 0.9)]


func _ready() -> void:
	for i in 8:
		var p := GPUParticles3D.new()
		p.amount = 160
		p.lifetime = 2.2
		p.one_shot = true
		p.explosiveness = 0.96
		p.emitting = false
		p.local_coords = false
		p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.3
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 180.0
		pm.initial_velocity_min = 9.0
		pm.initial_velocity_max = 11.5
		pm.gravity = Vector3(0, -3.2, 0)
		pm.damping_min = 2.2
		pm.damping_max = 3.0
		pm.scale_min = 0.8
		pm.scale_max = 1.3
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.55, Color(1, 1, 1, 0.9))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.45, 0.45)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.vertex_color_use_as_albedo = true
		var dot := GradientTexture2D.new()
		dot.fill = GradientTexture2D.FILL_RADIAL
		dot.fill_from = Vector2(0.5, 0.5)
		dot.fill_to = Vector2(0.5, 0.0)
		var dg := Gradient.new()
		dg.set_color(0, Color(1, 1, 1, 1))
		dg.set_color(1, Color(1, 1, 1, 0))
		dot.gradient = dg
		m.albedo_texture = dot
		q.material = m
		p.draw_pass_1 = q
		add_child(p)
		shells.append(p)
		var l := OmniLight3D.new()
		l.omni_range = 40.0
		l.light_energy = 0.0
		add_child(l)
		flashes.append(l)
	lantern_scene = WorldBuilder.model_scene("P_toro")


func burst(pos: Vector3, col: Color) -> void:
	var p := shells[_i % shells.size()]
	var l := flashes[_i % flashes.size()]
	_i += 1
	p.global_position = pos
	(p.process_material as ParticleProcessMaterial).color = col * 2.2
	p.restart()
	p.emitting = true
	l.global_position = pos
	l.light_color = col
	l.light_energy = 3.0
	create_tween().tween_property(l, "light_energy", 0.0, 0.9)
	if Audio.game_on:
		Audio.fx("boom", -6.0 - randf() * 4.0)


func _process(delta: float) -> void:
	if fireworks_on:
		_t -= delta
		if _t <= 0.0:
			_t = randf_range(0.6, 1.6) / rate
			var c: Color = PALETTE[randi() % PALETTE.size()]
			burst(global_position + Vector3(randf_range(-18, 18), randf_range(24, 34), randf_range(40, 62)), c)
			if randf() < 0.3:
				burst(global_position + Vector3(randf_range(-18, 18), randf_range(20, 30), randf_range(40, 62)), PALETTE[randi() % PALETTE.size()])
	if lanterns_on:
		_lt -= delta
		if _lt <= 0.0:
			_lt = randf_range(2.5, 4.5)
			float_lantern(false, Vector3(randf_range(-26.0, -8.0), 0, randf_range(15.0, 19.0)))
	for e in lanterns.duplicate():
		var n: Node3D = e.node
		e.t += delta
		n.position.x += e.speed * delta
		n.position.y = -0.3 + sin(e.t * 1.6) * 0.02
		n.rotation.y += delta * 0.1
		if n.position.x > 32.0:
			n.queue_free()
			lanterns.erase(e)


func float_lantern(from_bridge: bool, at: Vector3 = Vector3.ZERO) -> void:
	if lantern_scene == null:
		return
	var n: Node3D = lantern_scene.instantiate()
	add_child(n)
	n.position = Vector3(0.6, -0.3, 16.6) if from_bridge else at + Vector3(0, -0.3, 0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.78, 0.45)
	l.light_energy = 1.2
	l.omni_range = 2.6
	l.position = Vector3(0, 0.3, 0)
	n.add_child(l)
	lanterns.append({"node": n, "speed": randf_range(0.35, 0.5), "t": randf() * 5.0})

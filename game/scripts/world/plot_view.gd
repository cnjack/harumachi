class_name PlotView
extends Node3D
## One planting plot: a raised soil bed (or the Q03 planter), weeds while it is wild, crop models
## for the current growth stage, darker soil when watered today and a sparkle when it is ripe.
## refresh() is cheap and only rebuilds when the visible state actually changes.

## How many plants sit in one bed, by crop (tall plants get fewer, larger slots).
const SLOTS := {
	"radish": [Vector2(-0.26, -0.26), Vector2(0.26, -0.26), Vector2(-0.26, 0.26), Vector2(0.26, 0.26)],
	"komatsuna": [Vector2(-0.27, -0.27), Vector2(0.27, -0.27), Vector2(-0.27, 0.27), Vector2(0.27, 0.27)],
	"strawberry": [Vector2(-0.26, -0.24), Vector2(0.26, -0.24), Vector2(-0.26, 0.26), Vector2(0.26, 0.26)],
	"edamame": [Vector2(-0.24, -0.1), Vector2(0.24, 0.12)],
	"tomato": [Vector2(-0.26, 0.0), Vector2(0.26, 0.05)],
	"cucumber": [Vector2(0.0, 0.0)],
	"sunflower": [Vector2(-0.22, -0.12), Vector2(0.24, 0.16)],
}

var pid := ""
var wb: WorldBuilder
var bed: Node3D
var soil_mats: Array[StandardMaterial3D] = []
var soil_base: Array[Color] = []
var top := 0.26          # soil surface height (local)
var inner := 1.0         # scale of the planting area (the greenhouse beds are smaller)
var spread := Vector2.ONE  # extra x / z spread of the plant slots (the long courtyard planter)
var crops: Node3D
var weeds: Node3D
var glow: Sprite3D
var _key := ""
var _t := 0.0


func setup(world: WorldBuilder, plot_id: String, with_bed: bool = true, bed_scale: float = 0.95,
		soil_top: float = -1.0, slot_spread: Vector2 = Vector2.ONE) -> void:
	wb = world
	pid = plot_id
	name = "Plot_" + plot_id
	inner = bed_scale / 0.95
	spread = slot_spread
	if soil_top >= 0.0:
		top = soil_top
	if with_bed:
		bed = wb.spawn("F08_soil_plot", Vector3.ZERO, 0.0, 0, self)
		if bed:
			bed.scale = Vector3(bed_scale, 0.6, bed_scale)
			WorldBuilder.add_box_collider(bed, 0.92, WorldBuilder.L_SOLID)
			top = WorldBuilder.local_aabb(bed).end.y * 0.6 * 0.82
			for mi in WorldBuilder.find_meshes(bed):
				for si in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(si)
					if m is StandardMaterial3D:
						var d := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
						mi.set_surface_override_material(si, d)
						soil_mats.append(d)
						soil_base.append(d.albedo_color)
	crops = Node3D.new()
	crops.position.y = top
	add_child(crops)
	weeds = Node3D.new()
	weeds.position.y = top - 0.02
	add_child(weeds)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(plot_id)
	for i in 4:
		var w := wb.spawn("M12b_shrub", Vector3(rng.randf_range(-0.38, 0.38) * inner * spread.x, 0, rng.randf_range(-0.38, 0.38) * inner * spread.y), rng.randf() * 360.0, 0, weeds, rng.randf_range(0.14, 0.22))
		if w:
			for mi in WorldBuilder.find_meshes(w):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow = Sprite3D.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.98, 0.8, 1.0))
	g.set_color(1, Color(1.0, 0.85, 0.35, 0.0))
	gt.gradient = g
	gt.width = 64
	gt.height = 64
	glow.texture = gt
	glow.pixel_size = 0.0075
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.shaded = false
	glow.no_depth_test = false
	glow.modulate = Color(1, 1, 1, 0.8)
	glow.visible = false
	add_child(glow)
	refresh(true)


func refresh(force: bool = false) -> void:
	var G := GameState
	var p: Dictionary = G.plots.get(pid, {})
	var st := G.plot_state(pid)
	var key := "%s|%s|%s" % [st, p.get("crop", ""), p.get("water", false)]
	if key == _key and not force:
		return
	_key = key
	weeds.visible = st == "wild" or st == "locked"
	var wet: bool = p.get("water", false) and not (st in ["locked", "wild"])
	for i in soil_mats.size():
		soil_mats[i].albedo_color = soil_base[i] * (Color(0.66, 0.6, 0.58) if wet else Color(1, 1, 1))
		soil_mats[i].roughness = 0.55 if wet else 1.0
	for c in crops.get_children():
		c.queue_free()
	glow.visible = st == "ripe"
	var cid: String = p.get("crop", "")
	if cid == "" or st in ["locked", "wild", "tilled"]:
		return
	var model: String = G.crop_def(cid).get("model", "")
	var slots: Array = SLOTS.get(cid, [Vector2.ZERO])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pid + cid)
	for s in slots:
		var at := Vector3(s.x * inner * spread.x, 0, s.y * inner * spread.y)
		var yaw := rng.randf_range(-40.0, 40.0)
		match st:
			"seeded":
				_mound(at)
			"sprout":
				wb.spawn("C01_seedling", at, yaw * 3.0, 0, crops, rng.randf_range(0.8, 1.05))
			"growing":
				wb.spawn(model, at, yaw, 0, crops, rng.randf_range(0.5, 0.6) * inner)
			"ripe":
				wb.spawn(model, at, yaw, 0, crops, rng.randf_range(0.92, 1.05) * inner)
	if st == "ripe":
		var h := WorldBuilder.local_aabb(crops).end.y if crops.get_child_count() > 0 else 0.4
		glow.position.y = top + h + 0.25


func _mound(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.05
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.22, 0.16)
	m.roughness = 1.0
	mi.material_override = m
	mi.position = at + Vector3(0, 0.005, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crops.add_child(mi)


func _process(delta: float) -> void:
	if glow.visible:
		_t += delta
		var s := 0.85 + 0.2 * sin(_t * 3.2)
		glow.scale = Vector3.ONE * s
		glow.modulate.a = 0.4 + 0.25 * sin(_t * 3.2 + 1.0)

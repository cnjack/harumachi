class_name GrassField
extends Node3D
## v0.6 lawns are blade grass: `lawn()` fills rectangles with clumps of tapered blades (MultiMesh
## chunks, grass_blade.gdshader). `scatter()` still places the painted wildflower tufts, now only as a
## sparse accent. Keep-out rectangles and circles leave paths, beds and buildings clear; blades get
## shorter within half a metre of them and may spill a little over the edge, so borders look worn.

const CHUNK := 16.0
const BLADE_CHUNK := 8.0
static var _mat: ShaderMaterial
static var _mesh: ArrayMesh
static var _blade_mat := {}
static var _clumps := {}

## per style: blade height range (m), blades per clump, clump radius, lean, draw distance, palette tweak
const STYLES := {
	"plaza": {"h": Vector2(0.08, 0.22), "n": 9, "r": 0.15, "lean": 0.04, "range": 38.0, "dry": 0.08, "bright": 1.0},
	"lawn": {"h": Vector2(0.12, 0.24), "n": 15, "r": 0.24, "lean": 0.06, "range": 38.0, "dry": 0.04, "bright": 1.0},
	"meadow": {"h": Vector2(0.18, 0.42), "n": 17, "r": 0.3, "lean": 0.09, "range": 42.0, "dry": 0.09, "bright": 1.0},
	"tall": {"h": Vector2(0.45, 0.9), "n": 13, "r": 0.32, "lean": 0.15, "range": 46.0, "dry": 0.2, "bright": 0.94},
}
const MIX_FLOWERS := [0.0, 0.25, 2.0, 1.4, 1.2, 0.0, 0.0, 1.0]

## weights per atlas cell: lush, tall, clover, dandelion, violet, dry, fern, cosmos
const MIX_LAWN := [5, 2, 3, 1.2, 1.0, 0.6, 0.8, 0.5]
const MIX_MEADOW := [4, 3, 2, 1.4, 1.4, 1.2, 1.2, 1.0]
const MIX_EDGE := [3, 3, 0.6, 0.5, 0.6, 2.0, 1.6, 0.3]


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/tuft.gdshader")
		_mat.set_shader_parameter("atlas", load("res://assets/textures/tufts_atlas.png"))
	return _mat


static func mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := PI / 2.0 * k + 0.3
		var d := Vector3(cos(a), 0, sin(a)) * 0.5
		var v := [-d, d, d + Vector3(0, 1, 0), -d + Vector3(0, 1, 0)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[i])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[i])
	_mesh = st.commit()
	return _mesh


static func blade_material(style: String) -> ShaderMaterial:
	if not _blade_mat.has(style):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/grass_blade.gdshader")
		m.set_shader_parameter("dry_amount", float(STYLES[style].dry))
		m.set_shader_parameter("brightness", float(STYLES[style].bright))
		if style=="plaza":
			m.set_shader_parameter("root_col",Color(.20,.34,.15))
			m.set_shader_parameter("fresh_col",Color(.61,.77,.29))
			m.set_shader_parameter("deep_col",Color(.29,.49,.26))
		_blade_mat[style] = m
	return _blade_mat[style]


## One clump: n tapered blades (3 segments + tip) leaning a little outwards. UV.y = height 0..1,
## UV.x = side of the blade, COLOR.r / .g = per-blade random.
static func clump_mesh(style: String, variant: int) -> ArrayMesh:
	var key := "%s%d" % [style, variant]
	if _clumps.has(key):
		return _clumps[key]
	var S: Dictionary = STYLES[style]
	var rng := RandomNumberGenerator.new()
	rng.seed = 911 + variant * 37 + style.length()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var levels := [0.0, 0.38, 0.72, 1.0]
	for b in int(S.n):
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * float(S.r)
		var base := Vector3(cos(ang) * rad, 0, sin(ang) * rad)
		var h := rng.randf_range(S.h.x, S.h.y)
		var w := rng.randf_range(0.035, 0.058) * (1.2 if style == "tall" else 1.0)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face))
		var out := Vector3(cos(ang), 0, sin(ang)) * (0.4 + rad / float(S.r)) + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
		var lean: float = float(S.lean) * rng.randf_range(0.5, 1.6)
		var r1 := rng.randf()
		var r2 := rng.randf()
		var pts := []
		for t in levels:
			var c: Vector3 = base + out.normalized() * lean * t * t * h / 0.3 + Vector3(0, h * t * (1.0 - 0.12 * t * t), 0)
			var hw: float = w * 0.5 * (1.0 - t) * (1.0 - t * 0.2)
			pts.append([c - side * hw, c + side * hw, t])
		var col := Color(r1, r2, 0.0)
		var nrm := side.cross(Vector3.UP).normalized()
		for i in levels.size() - 1:
			var a0: Array = pts[i]
			var a1: Array = pts[i + 1]
			var quad := [[a0[0], 0.0, a0[2]], [a0[1], 1.0, a0[2]], [a1[1], 1.0, a1[2]], [a1[0], 0.0, a1[2]]]
			var tris := [0, 1, 2, 0, 2, 3] if i < levels.size() - 2 else [0, 1, 2]
			for k in tris:
				var q: Array = quad[k]
				st.set_color(col)
				st.set_normal(nrm)
				st.set_uv(Vector2(q[1], q[2]))
				st.add_vertex(q[0])
	var m := st.commit()
	_clumps[key] = m
	return m


## Blade grass over rects. density = clumps per square metre.
func lawn(rects: Array, avoid: Array = [], style: String = "lawn", density: float = 4.0, seed_n: int = 1, y: float = 0.0, height_at: Callable = Callable(), keep: Callable = Callable()) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var S: Dictionary = STYLES[style]
	var chunks := {}
	# spill: blades may sit this far inside a keep-out rect, so a lawn's border is not a ruler line
	var spill := 0.14
	for r in rects:
		var area := (float(r[2]) - float(r[0])) * (float(r[3]) - float(r[1]))
		var n := int(area * density)
		for i in n:
			var x := rng.randf_range(r[0], r[2])
			var z := rng.randf_range(r[1], r[3])
			if style=="plaza":
				var border: float=minf(minf(x-float(r[0]),float(r[2])-x),minf(z-float(r[1]),float(r[3])-z))
				var edge_noise: float=.13+.37*(.5+.5*sin(x*4.7+z*3.1))
				if border<edge_noise and rng.randf()>.28: continue
			if keep.is_valid() and not bool(keep.call(Vector2(x,z))):
				continue
			var edge := _edge_dist(x, z, avoid)
			if edge < -spill * rng.randf():
				continue
			# patches: thicker, taller grass in some places, thin and short in others
			var patch := sin(x * 0.31 + z * 0.13) * cos(z * 0.27 - x * 0.09) * 0.6 + sin(x * 0.9 - z * 0.7) * 0.4
			if patch < -0.55 and rng.randf() < 0.4:
				continue
			var s := rng.randf_range(0.8, 1.2) * (1.0 + patch * 0.22)
			s *= lerpf(0.55, 1.0, clampf(edge / 0.55, 0.0, 1.0))
			var key := Vector2i(int(floor(x / BLADE_CHUNK)), int(floor(z / BLADE_CHUNK)))
			if not chunks.has(key):
				chunks[key] = []
			var ground_y: float = float(height_at.call(Vector2(x,z))) if height_at.is_valid() else y
			chunks[key].append([Vector3(x, ground_y, z), rng.randf() * TAU, s, rng.randf(), rng.randi() % 3])
	var count := 0
	for key in chunks:
		var by_v := [[], [], []]
		for e in chunks[key]:
			by_v[e[4]].append(e)
		for v in 3:
			var list: Array = by_v[v]
			if list.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = clump_mesh(style, v)
			mm.instance_count = list.size()
			for i in list.size():
				var e: Array = list[i]
				var b := Basis(Vector3.UP, e[1]).scaled(Vector3(e[2], e[2], e[2]))
				mm.set_instance_transform(i, Transform3D(b, e[0]))
				mm.set_instance_custom_data(i, Color(e[3], 0, 0, 0))
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = blade_material(style)
			mi.set_meta("grass_style",style)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = float(S.range)
			mi.visibility_range_end_margin = 6.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mi)
			count += list.size()
	return count


## Signed distance (m) to the nearest keep-out shape: negative inside one.
static func _edge_dist(x: float, z: float, avoid: Array) -> float:
	var best := 99.0
	for a in avoid:
		var d: float
		if a.size() == 2:
			d = Vector2(x, z).distance_to(a[0]) - float(a[1])
		else:
			var dx := maxf(float(a[0]) - x, x - float(a[2]))
			var dz := maxf(float(a[1]) - z, z - float(a[3]))
			d = Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length() + minf(maxf(dx, dz), 0.0)
		best = minf(best, d)
	return best


## Painted wildflower / grass tufts (crossed quads). v0.6 uses them only as a sparse accent.
## rects: [[x0, z0, x1, z1], ...] in local space; avoid: rects [x0,z0,x1,z1] or circles [Vector2, r]
func scatter(rects: Array, density: float, avoid: Array = [], mix: Array = MIX_LAWN, size: Vector2 = Vector2(0.35, 0.6), seed_n: int = 1, y: float = 0.0, height_at: Callable = Callable(), keep: Callable = Callable()) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var chunks := {}
	var total_w := 0.0
	for w in mix:
		total_w += float(w)
	for r in rects:
		var area := (float(r[2]) - float(r[0])) * (float(r[3]) - float(r[1]))
		var n := int(area * density)
		for i in n:
			var x := rng.randf_range(r[0], r[2])
			var z := rng.randf_range(r[1], r[3])
			if _blocked(x, z, avoid):
				continue
			if keep.is_valid() and not bool(keep.call(Vector2(x,z))):continue
			# clumps: thin out by a cheap noise so the lawn is not an even carpet
			var clump := sin(x * 0.37 + z * 0.11) * cos(z * 0.29 - x * 0.07)
			if clump < -0.35 and rng.randf() < 0.7:
				continue
			var pick := rng.randf() * total_w
			var cell := 0
			for c in mix.size():
				pick -= float(mix[c])
				if pick <= 0.0:
					cell = c
					break
			var key := Vector2i(int(floor(x / CHUNK)), int(floor(z / CHUNK)))
			if not chunks.has(key):
				chunks[key] = []
			var s := rng.randf_range(size.x, size.y) * (1.25 if cell in [1, 5, 7] else 1.0)
			var ground_y: float = float(height_at.call(Vector2(x,z))) if height_at.is_valid() else y
			chunks[key].append([Vector3(x, ground_y, z), rng.randf() * TAU, s, cell, rng.randf(), rng.randf()])
	var count := 0
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh()
		mm.instance_count = list.size()
		for i in list.size():
			var e: Array = list[i]
			var b := Basis(Vector3.UP, e[1]).scaled(Vector3(e[2] * 1.3, e[2], e[2] * 1.3))
			mm.set_instance_transform(i, Transform3D(b, e[0]))
			mm.set_instance_custom_data(i, Color(float(e[3]), e[4], e[5], 0))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 58.0
		mi.visibility_range_end_margin = 8.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mi)
		count += list.size()
	return count


static func _blocked(x: float, z: float, avoid: Array) -> bool:
	for a in avoid:
		if a.size() == 2:
			if Vector2(x, z).distance_to(a[0]) < float(a[1]):
				return true
		elif x >= float(a[0]) and x <= float(a[2]) and z >= float(a[1]) and z <= float(a[3]):
			return true
	return false

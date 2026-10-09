class_name InteriorBuilder
extends Node3D
## v0.6 shop interiors: 晴町商店 (the general store, Kazuko) and 莲的面包店 (the bakery, Ren).
## Each is a small cut-away room seen from a fixed diorama camera like the player's house: full back
## and side walls, a low front wall with the door, painted walls and floors (house shaders, toon
## lighting), furniture models, shelves stocked with goods, pendant lamps and interaction points.

## v0.7: both rooms scaled up 1.375x (E-W) / 1.333x (N-S) from the original 8x6 footprint so the
## shops read as real rooms with walking space around the fixtures, not a shelf-packed box. Every
## coordinate below (furniture, points, lamps, keeper) was scaled by the same factors so pieces that
## used to hug a wall still hug the new, farther-out wall.
const SPECS := {
	"store": {
		"name": "晴町商店", "origin": Vector3(50, 0, 400), "size": Vector2(11.0, 8.0), "floor": "wood", "wall": "plaster",
		"back_wall": "plaster", "exit": Vector3(-36.0, 0.1, -13.2), "exit_yaw": 0.0, "door_x": 0.0,
		"furniture": [
			["I04_shop_counter", -3.575, 1.8, 90.0, 1.0, true],
			["P_gondola", -0.962, -0.8, 0.0, 1.0, true],
			["P_gondola", 2.131, 0.733, 0.0, 1.0, true],
			["I03_drink_fridge", 4.606, -3.267, 0.0, 1.0, true],
			["I07_ice_freezer", 4.537, 1.267, -90.0, 1.0, true],
			["G10_store_shelf", -3.506, -3.267, 0.0, 1.0, true],
			["D03_veg_crates", 3.575, 2.933, 0.0, 0.9, true],
		],
		"lamps": [Vector3(-2.062, 2.55, 0.0), Vector3(2.475, 2.55, 0.0)],
		# [id, x, y, z, radius]
		"points": [["store_counter", -2.337, 1.0, 1.8, 1.6], ["store_exit", 0.0, 0.9, 3.933, 1.5],
			["store_fridge", 4.606, 1.0, -2.467, 1.3], ["store_freezer", 3.713, 0.8, 1.267, 1.3]],
		"keeper": Vector3(-4.812, 0.0, 1.8), "keeper_yaw": 90.0,
	},
	"bakery": {
		"name": "莲的面包店", "origin": Vector3(80, 0, 400), "size": Vector2(11.0, 8.0), "floor": "kitchen", "wall": "plaster",
		"back_wall": "kitchen_tile", "exit": Vector3(-25.6, 0.1, -13.2), "exit_yaw": 0.0, "door_x": 2.2,
		"furniture": [
			["I05_bread_shelf", -4.991, -1.467, 90.0, 1.0, true],    # backs against the west wall
			["I05_bread_shelf", -4.991, 0.533, 90.0, 1.0, true],
			["I02_cake_showcase", 0.481, 0.533, 0.0, 1.0, true],     # next to the counter: one line of glass and wood
			["I04_shop_counter", 2.681, 0.533, 0.0, 1.0, true],
			["P_deck_oven", 3.506, -3.2, 0.0, 1.0, true],
			["I08_stone_mill", -3.3, -3.267, 0.0, 1.0, true],
			["G11_bread_cart", -3.506, 3.067, 0.0, 0.9, true],       # front-left, clear of the door and the walk to the oven
		],
		"lamps": [Vector3(-2.2, 2.55, 0.267), Vector3(2.2, 2.55, -0.8)],
		"points": [["bakery_counter", 2.681, 1.0, 1.667, 1.5], ["bakery_exit", 2.2, 0.9, 3.933, 1.5],
			["bakery_oven", 3.506, 1.0, -2.133, 1.4], ["bakery_mill", -3.3, 0.8, -2.333, 1.4], ["cake_showcase", 0.481, 1.0, 1.6, 1.3]],
		"keeper": Vector3(2.681, 0.0, -0.733), "keeper_yaw": 0.0,
	},
	"workroom": {
		"name": "社区工作间", "origin": Vector3(110, 0, 400), "size": Vector2(12, 9), "floor": "wood", "wall": "plaster", "back_wall": "plaster",
		"exit": Vector3(-23.2, .1, -7.1), "exit_yaw": 180.0, "door_x": 0.0, "furniture": [["W13_cedar_worktable", -1.2, -.4, 0.0, 1.0, true]],
		"lamps": [Vector3(-2.2, 2.55, .4), Vector3(2.2, 2.55, -1.6)],
		"points": [["workroom_exit", 0, .9, 4.35, 1.4], ["workroom_archive", -4.7, 1.0, -2.5, 1.5],
			["workroom_table", -1.2, .9, .5, 1.4], ["workroom_lantern_test", 1.8, 1.0, -.5, 1.4], ["workroom_sign", 4.8, 1.0, 1.5, 1.3]],
	},
}
const WALL_H := 2.8
const FRONT_H := 0.85

var wb: WorldBuilder
var kind := ""
var spec: Dictionary
var origin := Vector3.ZERO
var lamps: Array[OmniLight3D] = []
var pieces: Array[Node3D] = []      # the furniture models, in SPECS order (the tests check their footprints)
var bakery_sign: Label3D
var wall_shelves: Array[Node3D] = []


static func spec_for(k: String) -> Dictionary:
	return SPECS.get(k, {})


static func at(world_pos: Vector3) -> String:
	for k in SPECS:
		var o: Vector3 = SPECS[k].origin
		var s: Vector2 = SPECS[k].size
		var l := world_pos - o
		if absf(l.x) <= s.x / 2.0 + 0.5 and absf(l.z) <= s.y / 2.0 + 0.5:
			return k
	return ""


## True once the player (world position) has walked out through the door of interior k.
static func walked_out(k: String, p: Vector3) -> bool:
	var s: Dictionary = SPECS[k]
	var l: Vector3 = p - (s.origin as Vector3)
	return l.z > (s.size as Vector2).y / 2.0 + 0.3 and absf(l.x - float(s.door_x)) < 1.2


static func door_point(k: String) -> Vector3:
	var s: Dictionary = SPECS[k]
	return s.origin + Vector3(float(s.door_x), 0.05, s.size.y / 2.0 - 0.7)


func build(world: WorldBuilder, k: String) -> void:
	wb = world
	kind = k
	spec = SPECS[k]
	origin = spec.origin
	name = "Interior_" + k
	position = origin
	var house := world.house
	var w: float = spec.size.x
	var d: float = spec.size.y
	# floor and a solid base under it
	var fm := house.floor_mat(str(spec.floor), [-w / 2.0, -d / 2.0, w / 2.0, d / 2.0])
	fm.set_shader_parameter("house_origin", origin)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, d)
	fl.mesh = pm
	fl.material_override = fm
	fl.position.y = 0.002
	add_child(fl)
	# the ground collider reaches as far as the painted street outside the door (_outside), so nothing is a hole;
	# walking out through the door takes you back to the real street (Main._physics_process)
	_collider(Vector3(w + 16.0, 0.4, d + 12.0), Vector3(0, -0.2, 3.0), WorldBuilder.L_GROUND)
	# walls: back (north), sides, a low front wall broken by the door
	# Shop ceilings are 2.8 m; do not reuse the house's 2.4 m cornice height/material instance.
	var wm := house.wall_mat(str(spec.wall)).duplicate() as ShaderMaterial
	var bm := house.wall_mat(str(spec.back_wall)).duplicate() as ShaderMaterial
	# Headless does not return implicit shader defaults. Select the finish by the room spec.
	for finish: Array in [[wm, str(spec.wall)], [bm, str(spec.back_wall)]]:
		var shop_mat := finish[0] as ShaderMaterial
		if finish[1] == "plaster":
			shop_mat.set_shader_parameter("cornice_y", WALL_H - 0.07)
			shop_mat.set_shader_parameter("wood_tex", load("res://assets/textures/architecture/cedar-grain.jpg"))
			shop_mat.set_shader_parameter("wain_tint", Color(0.73, 0.61, 0.48))
			shop_mat.set_shader_parameter("tint",{"store":Color(.96,.98,.91),"bakery":Color(1.0,.96,.86),"workroom":Color(.93,.97,1.0)}[k])
			shop_mat.set_shader_parameter("wain_tint",{"store":Color(.69,.62,.48),"bakery":Color(.79,.65,.48),"workroom":Color(.63,.64,.55)}[k])
	fm.set_shader_parameter("tint",{"store":Color(.89,.87,.79),"bakery":Color(1.0,.94,.80),"workroom":Color(.81,.86,.81)}[k])
	_wall(Vector3(w, WALL_H, 0.16), Vector3(0, WALL_H / 2.0, -d / 2.0 - 0.08), bm)
	_wall(Vector3(0.16, WALL_H, d), Vector3(-w / 2.0 - 0.08, WALL_H / 2.0, 0), wm)
	_wall(Vector3(0.16, WALL_H, d), Vector3(w / 2.0 + 0.08, WALL_H / 2.0, 0), wm)
	var dx: float = spec.door_x
	var left := (dx - 0.8) - (-w / 2.0)
	var right := (w / 2.0) - (dx + 0.8)
	_wall(Vector3(left, FRONT_H, 0.16), Vector3(-w / 2.0 + left / 2.0, FRONT_H / 2.0, d / 2.0 + 0.08), wm)
	_wall(Vector3(right, FRONT_H, 0.16), Vector3(w / 2.0 - right / 2.0, FRONT_H / 2.0, d / 2.0 + 0.08), wm)
	# door frame posts and a noren over the door
	var wood := house.wood_mat(true)
	for x in [dx - 0.85, dx + 0.85]:
		_box(Vector3(0.1, FRONT_H + 0.3, 0.2), Vector3(x, (FRONT_H + 0.3) / 2.0, d / 2.0 + 0.08), wood)
	# shadow-only roof so the light comes in through the open front like through the shop windows
	var roof := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(w + 0.6, 0.1, d + 0.4)
	roof.mesh = rb
	roof.position = Vector3(0, WALL_H + 0.05, -0.2)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(roof)
	# a back-room doorway with a noren on the back wall
	var noren := house.flat_mat(Color(0.18, 0.28, 0.46) if k == "store" else Color(0.72, 0.36, 0.22), "noren_" + k)
	var back_door_x := -0.275 if k == "store" else -0.825
	for strip in 4:
		_box(Vector3(0.255, 0.5, 0.035), Vector3(back_door_x - 0.411 + strip * 0.274, 1.85, -d / 2.0 + 0.07), noren, false)
	_box(Vector3(1.1, 1.62, 0.02), Vector3(back_door_x, 0.81, -d / 2.0 + 0.01), house.flat_mat(Color(0.2, 0.17, 0.15), "doorway"), false)
	for jamb_x: float in [back_door_x - 0.6, back_door_x + 0.6]:
		_box(Vector3(0.08, 2.17, 0.1), Vector3(jamb_x, 1.085, -d / 2.0 + 0.075), wood)
	_box(Vector3(1.28, 0.09, 0.12), Vector3(back_door_x, 2.17, -d / 2.0 + 0.07), wood)
	JapaneseArchitecture.shop_frames(self)
	# furniture
	for f in spec.furniture:
		var n := wb.spawn(f[0], Vector3(f[1], 0, f[2]), f[3], 1 if f[5] else 0, self, f[4])
		if n:
			HouseBuilder.toonify(n)
			pieces.append(n)
	if k == "store":
		# ShopContent fills these shelves with real product meshes.
		_wall_shelf(Vector3(2.2, 0, -d / 2.0 + 0.16), 2.0, 0.0, [0.95, 1.4, 1.85], [0, 1, 2, 3, 4, 5, 12, 13, 14, 15])
		_wall_shelf(Vector3(-w / 2.0 + 0.16, 0, -0.467), 1.8, PI / 2.0, [1.0, 1.45, 1.9], [6, 7, 8, 9, 10, 11, 18, 19, 20, 21])
		# ShopContent mounts the television and illustrated shop posters.
	elif k == "bakery":
		_stock_bread()
		_worktable()
		_wall_shelf(Vector3(0.825, 0, -d / 2.0 + 0.16), 1.6, 0.0, [1.45, 1.9], [16, 17, 15, 14, 16, 17])
		# ShopContent mounts the new illustrated bakery poster.
		_picture("ban_kitchen", Vector3(-w / 2.0 + 0.02, 1.95, 2.533), PI / 2.0)
	elif k == "workroom":
		_build_workroom()
	_outside(w, d)
	if k == "bakery":
		_build_bakery_sign()
		GameState.state_changed.connect(sync_bakery_sign)
	# pendant lamps (warm; brighter in the evening)
	for p in spec.lamps:
		_lamp(p)
	for pt in spec.points:
		var it := Interactable.new()
		it.id = pt[0]
		it.radius = pt[4]
		add_child(it)
		it.position = Vector3(pt[1], pt[2], pt[3])
	RoomIdentity.build(self)


func _wall(size: Vector3, pos: Vector3, m: Material) -> void:
	_box(size, pos, m)
	_collider(size, pos, WorldBuilder.L_SOLID)


func _build_bakery_sign() -> void:
	var top := 0.9
	if pieces.size() >= 7:
		for child in pieces[6].find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			top = maxf(top, bounds.end.y - origin.y)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.64, 0.4, 0.24)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(1.0, 0.95, 0.8)
	_box(Vector3(0.04, 0.18, 0.04), Vector3(-3.506, top + 0.09, 3.067), wood)
	_box(Vector3(0.68, 0.4, 0.035), Vector3(-3.506, top + 0.36, 3.067), paper)
	bakery_sign = Label3D.new()
	bakery_sign.name = "BakeryTrialSign"
	bakery_sign.font = load("res://assets/fonts/LXGWWenKai-Medium.ttf")
	bakery_sign.font_size = 40
	bakery_sign.pixel_size = 0.0019
	bakery_sign.outline_size = 0
	bakery_sign.modulate = Color(0.3, 0.18, 0.11)
	bakery_sign.position = Vector3(-3.506, top + 0.36, 3.09)
	add_child(bakery_sign)
	var point := Interactable.new()
	point.name = "BakeryOrderPoint"
	point.id = "bakery_orders"
	point.radius = 1.4
	point.position = Vector3(-2.48, 1.1, 3.067)
	add_child(point)
	sync_bakery_sign()


func sync_bakery_sign() -> void:
	if bakery_sign == null:
		return
	var G := GameState
	if not G.flags.has("bakery_menu"):
		bakery_sign.text = "街坊试吃\n先做一小份"
	elif int(G.flags.bakery_menu) == 0:
		bakery_sign.text = "菠萝包\n三明治少量试吃"
	else:
		bakery_sign.text = "街坊三明治\n菠萝包也留着"


func _box(size: Vector3, pos: Vector3, m: Material, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _collider(size: Vector3, pos: Vector3, layer: int) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = pos
	add_child(b)


func _lamp(p: Vector3) -> void:
	var shade := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.26
	cm.height = 0.22
	shade.mesh = cm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.98, 0.9, 0.72)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.82, 0.55)
	sm.emission_energy_multiplier = 1.4
	shade.material_override = sm
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shade.position = p
	add_child(shade)
	var cord := _box(Vector3(0.015, WALL_H - p.y, 0.015), Vector3(p.x, (WALL_H + p.y) / 2.0, p.z), wb.house.flat_mat(Color(0.15, 0.13, 0.12), "cord"), false)
	cord.name = "Cord"
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.6)
	l.omni_range = 5.5
	l.light_energy = 1.2
	l.shadow_enabled = true
	l.position = p + Vector3(0, -0.25, 0)
	add_child(l)
	lamps.append(l)


## Daylight comes in through the open front; lamps carry the room after dark.
func set_evening(evening: bool) -> void:
	for l in lamps:
		l.light_energy = 2.2 if evening else 1.0


# ------------------------------------------------------------------ goods on the shelves
static var _goods_mats: Array = []


static func goods_mat(cell: int) -> StandardMaterial3D:
	if _goods_mats.is_empty():
		var tex: Texture2D = load("res://assets/textures/products_atlas.png")
		for i in 24:
			var m := StandardMaterial3D.new()
			m.albedo_texture = tex
			m.uv1_scale = Vector3(1.0 / 6.0, 1.0 / 4.0, 1.0)
			m.uv1_offset = Vector3(float(i % 6) / 6.0, float(i / 6) / 4.0, 0.0)
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			m.roughness = 0.7
			_goods_mats.append(m)
	return _goods_mats[cell % 24]


## Rows of product fronts (a thin box with the product painting on its face) on both sides of each
## gondola's four shelves. Heights follow the I06 model (fit to 1.5 m).
func _stock_gondolas() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var side := StandardMaterial3D.new()
	side.albedo_color = Color(0.93, 0.9, 0.84)
	side.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	for f in spec.furniture:
		if f[0] != "P_gondola":
			continue
		var cx: float = f[1]
		var cz: float = f[2]
		# the shelf runs along X, its two faces look north and south (the camera sees the south face)
		for level in [0.14, 0.48, 0.82, 1.16]:
			for face in [-1.0, 1.0]:
				var x := -0.84
				while x < 0.84:
					var cell := rng.randi() % 24
					var wdt := 0.13 + rng.randf() * 0.05
					var hgt := 0.16 + rng.randf() * 0.1 if level < 1.1 else 0.14 + rng.randf() * 0.06
					var mi := MeshInstance3D.new()
					var qm := QuadMesh.new()
					qm.size = Vector2(wdt, hgt)
					mi.mesh = qm
					mi.material_override = goods_mat(cell)
					mi.position = Vector3(cx + x + wdt / 2.0, level + hgt / 2.0, cz + face * 0.22)
					mi.rotation.y = 0.0 if face > 0.0 else PI
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(mi)
					var back := _box(Vector3(wdt - 0.01, hgt, 0.16), Vector3(cx + x + wdt / 2.0, level + hgt / 2.0, cz + face * 0.13), side, false)
					back.name = "Goods"
					x += wdt + 0.012


## Bread on the rattan trays of both bread shelves: each tray gets one kind, a row of 3–5.
## The four trays, measured from the I05 mesh (upward faces grouped by height), in the shelf's own frame:
## [height of the tray's middle, depth of its middle (+Z = front), usable width]. They slope up toward the
## front by about TRAY_TILT, so the bread is tipped the same way to lie on them.
const TRAYS := [[0.27, 0.08, 0.84], [0.61, 0.0, 0.76], [0.94, -0.08, 0.76], [1.26, -0.12, 0.74]]
const TRAY_TILT := 0.42

func _stock_bread() -> void:
	var kinds := ["B01_melon_pan", "B02_croissant", "B05_anpan", "B06_curry_pan", "B04_shokupan", "B03_baguette"]
	var k := 0
	for f in spec.furniture:
		if f[0] != "I05_bread_shelf":
			continue
		var shelf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(f[3]))), Vector3(float(f[1]), 0.0, float(f[2])))
		for t in TRAYS:
			var kind_id: String = kinds[k % kinds.size()]
			k += 1
			var ps := WorldBuilder.model_scene(kind_id)
			if ps == null:
				continue
			var n := 3 if kind_id in ["B03_baguette", "B04_shokupan"] else 5
			var wdt: float = t[2]
			for i in n:
				var b: Node3D = ps.instantiate()
				add_child(b)
				var local := Vector3(-wdt / 2.0 + (i + 0.5) * wdt / n + 0.04, float(t[0]) + 0.02, float(t[1]))
				var spin := randf_range(-0.35, 0.35) + (PI / 2.0 if kind_id == "B03_baguette" else 0.0)
				b.transform = shelf * Transform3D(Basis(Vector3.RIGHT, -TRAY_TILT) * Basis(Vector3.UP, spin), local)
				HouseBuilder.toonify(b)


## Wooden wall shelf with goods facing into the room (and so toward the camera).
func _wall_shelf(at: Vector3, length: float, yaw: float, levels: Array, cells: Array) -> void:
	var wood := wb.house.wood_mat(false)
	var n := Node3D.new()
	n.position = at
	n.rotation.y = yaw
	add_child(n)
	n.name="WallStockShelf_%d"%wall_shelves.size()
	n.set_meta("levels",levels);n.set_meta("shelf_length",length);wall_shelves.append(n)
	for shelf_index: int in levels.size():
		var shelf_y: float=levels[shelf_index]
		var plank:=MeshInstance3D.new();plank.name="ShelfBoard_%d"%shelf_index
		var board:=BoxMesh.new();board.size=Vector3(length,.035,.3)
		plank.mesh=board;plank.material_override=wood;plank.position=Vector3(0,shelf_y-.018,.14);n.add_child(plank)
	for sx in [-length / 2.0, length / 2.0]:
		var side := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.035, levels.back() - levels[0] + 0.5, 0.3)
		side.mesh = sb
		side.material_override = wood
		side.position = Vector3(sx, (levels[0] + levels.back()) / 2.0, 0.14)
		n.add_child(side)


## A framed painting (one of the codex banners) on a wall.
func _picture(banner: String, at: Vector3, yaw: float) -> void:
	var path := "res://assets/ui/banners/%s.jpg" % banner
	if not ResourceLoader.exists(path):
		return
	var n := Node3D.new()
	n.position = at
	n.rotation.y = yaw
	add_child(n)
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(1.36, 0.46, 0.03)
	frame.mesh = fb
	frame.material_override = wb.house.wood_mat(true)
	n.add_child(frame)
	var pic := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.28, 0.38)
	pic.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	pic.material_override = m
	pic.position.z = 0.017
	n.add_child(pic)


## The street outside the cut-away front, so the room does not float in green.
func _outside(w: float, d: float) -> void:
	var m := WorldBuilder.ground_material("stone")
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w + 16.0, d + 12.0)
	mi.mesh = pm
	mi.material_override = m
	mi.position = Vector3(0, -0.012, 3.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _worktable() -> void:
	var wood := wb.house.wood_mat(false)
	_box(Vector3(1.6, 0.06, 0.8), Vector3(-0.275, 0.86, -2.933), wood)
	for x in [-0.975, 0.425]:
		for z in [-3.233, -2.633]:
			_box(Vector3(0.06, 0.84, 0.06), Vector3(x, 0.42, z), wood)
	_collider(Vector3(1.6, 0.9, 0.8), Vector3(-0.275, 0.45, -2.933), WorldBuilder.L_SOLID)
	var dough := StandardMaterial3D.new()
	dough.albedo_color = Color(0.96, 0.9, 0.78)
	dough.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	for i in 3:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.1
		mi.mesh = sm
		mi.material_override = dough
		mi.position = Vector3(-0.775 + i * 0.35, 0.92, -2.933)
		add_child(mi)
	var flour := StandardMaterial3D.new()
	flour.albedo_color = Color(0.98, 0.97, 0.95)
	_box(Vector3(0.9, 0.005, 0.5), Vector3(0.025, 0.892, -2.933), flour, false)

func _build_workroom() -> void:
	# The central worktable is the inspected Hyper3D asset in SPECS, spawned by WorldBuilder.
	var wood := wb.house.wood_mat(false)
	# Archive shelves, spare sign table and an actual trial hanging beam.
	for level: float in [.25, .8, 1.35]: _box(Vector3(1.0, .07, 1.5), Vector3(-5.35, level, -2.5), wood)
	_collider(Vector3(1.0, 1.4, 1.5), Vector3(-5.35, .7, -2.5), WorldBuilder.L_SOLID)
	var paper := wb.house.flat_mat(Color(.91, .85, .66), "workroom_paper")
	for index in 4: _box(Vector3(.35, .045, .5), Vector3(-5.16, .85 + index * .046, -2.35), paper, false)
	_box(Vector3(1.2, .08, .7), Vector3(4.9, .74, 1.5), wood)
	_collider(Vector3(1.2, .78, .7), Vector3(4.9, .39, 1.5), WorldBuilder.L_SOLID)
	_box(Vector3(3.0, .1, .1), Vector3(1.8, 2.9, -1.8), wood, false)
	for x: float in [.3, 3.3]:
		_box(Vector3(.08, 2.9, .08), Vector3(x, 1.45, -1.8), wood)
		_collider(Vector3(.08, 2.9, .08), Vector3(x, 1.45, -1.8), WorldBuilder.L_SOLID)
	# Spare washi dries beside the fixed aisle. It is a visible obstruction from the distant approach.
	WorkroomView.paper_frame(self,Vector3(.9,0,-1.0),wood,paper)
	ClearSignage.paper_tag(self,"ArchiveTag","账本与旧图纸",Vector3(-5.35,1.35,-1.736),Vector2(.88,.09),0,.059)
	ClearSignage.paper_tag(self,"WorktableTag","共同工作台",Vector3(-1.20,.656,-.005),Vector2(.84,.115),0,.068)
	ClearSignage.paper_tag(self,"TrialTag","试挂架",Vector3(2.94,2.84,-1.73),Vector2(.64,.15),0,.083)
	var view := WorkroomView.new()
	add_child(view)
	view.setup(self)

class_name HouseBuilder
extends Node3D
## The player's home: a one-storey Japanese house (genkan, hall, kitchen, living room, bedroom,
## engawa) seen as a cut-away diorama. Rooms, walls, openings and furniture come from the tables
## below, in house-local metres (+X east, +Z south). The camera looks north from the south, so
## east-west walls on the south side of the player's room drop to a low stub (`update_cutaway`).

const ORIGIN := Layout.ROOM_ORIGIN
const WALL_H := 2.4
const STUB_H := 0.32
const WALL_T := 0.14
const DOOR_H := 1.86
const GENKAN_Y := -0.12
const GROUND_Y := -0.45
const SPAWN_LOCAL := Vector3(5.0, 0.05, 3.75)
const EXIT_Z := 4.72            # walking south past this line inside the door gap leaves the house
const DOOR_X := [4.3, 5.7]

## id, name, rect [x0, z0, x1, z1], floor look, footstep surface
const ROOMS := [
	{"id": "bedroom", "name": "卧室", "rect": [-6.5, -3.3, -1.5, 1.0], "floor": "wood", "step": "wood"},
	{"id": "living", "name": "客厅", "rect": [-1.5, -3.3, 6.5, 1.0], "floor": "tatami", "step": "tatami"},
	{"id": "kitchen", "name": "厨房", "rect": [-6.5, 1.0, 0.5, 4.5], "floor": "kitchen", "step": "wood"},
	{"id": "hall", "name": "走廊", "rect": [0.5, 1.0, 3.5, 4.5], "floor": "wood", "step": "wood"},
	{"id": "genkan", "name": "玄关", "rect": [3.5, 1.0, 6.5, 4.5], "floor": "wood", "step": "wood"},
	{"id": "engawa", "name": "缘侧", "rect": [-1.5, -4.6, 6.5, -3.3], "floor": "engawa", "step": "wood"},
	{"id": "yard", "name": "小院", "rect": [-1.5, -8.3, 6.5, -4.62], "floor": "", "step": "grass", "outdoor": true},
]
## Four plots in the yard (opened with the hoe in Q06) and the garden tap next to them.
const YARD_PLOTS := {"yard0": Vector3(3.3, 0, -6.05), "yard1": Vector3(4.9, 0, -6.05),
		"yard2": Vector3(3.3, 0, -7.55), "yard3": Vector3(4.9, 0, -7.55),
		"yard4": Vector3(-0.55, 0, -6.05), "yard5": Vector3(-0.55, 0, -7.55)}
const YARD_TAP := Vector3(6.05, 0, -5.2)
const PEBBLE_RECT := [3.5, 2.8, 6.5, 4.5]
## Indoor daytime sun (degrees, matches WorldBuilder.apply_phase) used to sweep the light shafts.
const SUN_DAY_ROT := Vector3(-33.0, 204.0, 0.0)
## Shadow-only roof pieces [x0, z0, x1, z1].
const ROOF_PARTS := [[-7.0, -3.42, -1.5, 5.1], [-1.5, -4.05, 7.0, 5.1]]
## Light shafts: [x0, x1, wall z, sill, top, eave z, posts, post width (u), strength]
const BEAM_OPENINGS := [
	[-1.25, 6.25, -3.3, 0.0, 1.9, -4.05, 3, 0.012, 0.2],
	[-4.4, -2.6, -3.3, 0.9, 1.95, -3.42, 4, 0.03, 0.15],
]

## Wall lines. "ew" walls run east-west at z = a.y; openings are [from, to, kind] along the
## line's running axis. kinds: door (to DOOR_H), glass (to 1.9, open to the engawa),
## window [from, to, "window", sill, top, view] (view: "card" shows a painted view outside).
const WALLS := [
	{"id": "n_bed", "a": Vector2(-6.5, -3.3), "b": Vector2(-1.5, -3.3), "open": [[-4.4, -2.6, "window", 0.9, 1.95, ""]]},
	{"id": "n_liv", "a": Vector2(-1.5, -3.3), "b": Vector2(6.5, -3.3), "open": [[-1.25, 6.25, "glass"]]},
	{"id": "m_bed", "a": Vector2(-6.5, 1.0), "b": Vector2(-1.5, 1.0), "open": []},
	{"id": "m_liv", "a": Vector2(-1.5, 1.0), "b": Vector2(6.5, 1.0), "open": [[1.3, 2.5, "door"], [4.4, 5.6, "door"]]},
	{"id": "s_ext", "a": Vector2(-6.5, 4.5), "b": Vector2(6.5, 4.5), "open": [[4.3, 5.7, "door"]], "always_cut": true},
	{"id": "w_ext", "a": Vector2(-6.5, -3.3), "b": Vector2(-6.5, 4.5), "open": [[2.3, 3.7, "window", 1.2, 1.95, "card"]]},
	{"id": "e_ext", "a": Vector2(6.5, -3.3), "b": Vector2(6.5, 4.5), "open": [[-2.9, -1.5, "window", 0.85, 1.95, "card"]]},
	{"id": "p_bed", "a": Vector2(-1.5, -3.3), "b": Vector2(-1.5, 1.0), "open": [[-1.8, -0.6, "door"]]},
	{"id": "p_kit", "a": Vector2(0.5, 1.0), "b": Vector2(0.5, 4.5), "open": [[2.0, 3.2, "door"]]},
	{"id": "p_gen", "a": Vector2(3.5, 1.0), "b": Vector2(3.5, 1.2), "open": []},
]

## Furniture: [model, x, z, yaw, collide, y]
const FURNITURE := [
	["I01_bed", -5.75, -2.2, 0.0, 1, 0.0],
	["I02_desk", -3.5, -2.93, 0.0, 1, 0.0],
	["I06_floor_lamp", -4.75, -3.0, 0.0, 2, 0.0],
	["I07_monstera", -1.95, 0.55, 0.0, 2, 0.0],
	["J07_kotatsu", 2.4, -1.25, 0.0, 1, 0.0],
	["J06_tv_board", 6.12, -0.1, -90.0, 1, 0.0],
	["J09_tansu", -1.18, 0.4, 90.0, 1, 0.0],
	["I03_bookshelf", -1.3, -2.65, 90.0, 1, 0.0],
	["J08_fan", 5.9, -2.95, -30.0, 2, 0.0],
	["G06_zabuton", -0.7, -2.95, 10.0, 2, 0.0],    # v0.7.3: clear of the bookshelf
	["J01_kitchen_counter", -6.14, 3.0, 90.0, 1, 0.0],
	["J02_fridge", -6.1, 1.38, 90.0, 1, 0.0],
	["J04_rice_cabinet", -4.35, 1.26, 0.0, 1, 0.0],
	["J05_dish_cabinet", -2.95, 1.22, 0.0, 1, 0.0],
	["J03_dining_set", -2.3, 3.0, 0.0, 1, 0.0],
	["G07_hall_cabinet", 3.0, 1.24, 0.0, 1, 0.0],
	["G01_getabako", 6.18, 3.55, -90.0, 1, GENKAN_Y],
	["G08_cat", 3.3, -3.95, 25.0, 2, 0.0],
	["G03_laundry_stand", -4.0, -5.7, 0.0, 1, GROUND_Y],
	["A15_potted_plant", 0.9, 4.1, 0.0, 2, 0.0],
	["P_chest", 1.65, 4.05, 0.0, 1, 0.0],       # v0.7.3: levelled chest is wider; clear of the plant
]

## Interaction points: [id, x, y, z, radius]
const POINTS := [
	["room_door", 5.0, 0.8, 4.15, 1.4],
	["room_bed", -5.1, 0.7, -1.6, 1.4],
	["room_desk", -3.5, 0.9, -2.3, 1.3],
	["house_rice", -4.35, 0.9, 1.85, 1.4],
	["house_fridge", -5.55, 0.9, 1.45, 1.1],
	["house_tv", 5.35, 0.8, -0.1, 1.4],
	["house_kotatsu", 2.4, 0.5, -0.25, 1.4],
	["house_cat", 3.3, 0.4, -3.75, 1.3],
	["house_phone", 3.0, 0.9, 1.65, 1.2],
	["house_goldfish", -0.75, 0.5, -3.85, 1.3],
	["house_garden", 1.4, 0.8, -4.25, 1.6],
	["yard_tap", 6.05, 0.3, -5.2, 1.3],
	["house_stove", -5.5, 0.9, 3.35, 1.3],
	["house_chest", 1.35, 0.7, 3.5, 1.5],
	["room_closet", -5.95, 0.9, 0.25, 1.3],
	["life_pantry", -2.95, 0.9, 1.75, 1.35],
	["life_meal_table", -2.3, 0.9, 3.0, 1.45],
]

var wb: WorldBuilder
var cut_groups := {}            # wall id -> {"pivot": Node3D, "rails": [Node3D], "z": float, "cut": bool}
var boxes: Node3D
var goldfish: Node3D
var map_frame: Node3D
var future_note: Node3D
var future_note_label: Label3D
var lamps: Array[OmniLight3D] = []
var fills: Array[OmniLight3D] = []
var dust: GPUParticles3D
var beams: Node3D
var current_room := ""
var _mats := {}


func build(world: WorldBuilder) -> void:
	wb = world
	name = "House"
	position = ORIGIN
	_build_lot()
	_build_floors()
	for w in WALLS:
		_build_wall(w)
	_build_engawa()
	_build_details()
	_build_furniture()
	RoomIdentity.home(self)
	_build_future_note()
	_build_lights()
	_build_roof_shadow()
	_build_sunbeams()
	update_cutaway("genkan", false)
	sync_state()


static func room_at(local: Vector3) -> Dictionary:
	for r in ROOMS:
		var q: Array = r.rect
		if local.x >= q[0] - 0.05 and local.x <= q[2] + 0.05 and local.z >= q[1] - 0.05 and local.z <= q[3] + 0.05:
			return r
	return {}


## Intermediate doors keep indoor objectives from pointing through intact walls.
static func kitchen_waypoint(world_pos: Vector3) -> Variant:
	var local: Vector3 = world_pos - ORIGIN
	var room_id: String = str(room_at(local).get("id", ""))
	if room_id == "bedroom":
		return ORIGIN + Vector3(-1.5, 2.0, -1.2)
	if room_id == "living":
		if local.x >= 3.4:
			return ORIGIN + Vector3(5.0, 2.0, 1.5)
		if local.x < .85 and local.z < -.45:
			return ORIGIN + Vector3(.9, 2.0, -.6)
		if local.z < -.2:
			return ORIGIN + Vector3(1.9, 2.0, .15)
		return ORIGIN + Vector3(1.9, 2.0, 1.5)
	if room_id in ["hall", "genkan"]:
		return ORIGIN + Vector3(.1, 2.0, 2.6)
	if room_id == "yard":
		return ORIGIN + Vector3(1.5, 1.2, -4.85 if absf(local.x - 1.5) > .3 else -4.3)
	if room_id == "engawa":
		return ORIGIN + Vector3(1.9, 2.0, -2.5)
	return null


static func surface_at(world_pos: Vector3) -> String:
	var l := world_pos - ORIGIN
	if l.x >= PEBBLE_RECT[0] and l.x <= PEBBLE_RECT[2] and l.z >= PEBBLE_RECT[1]:
		return "stone"
	var r := room_at(l)
	return str(r.get("step", "wood"))


static func spawn_point() -> Vector3:
	return ORIGIN + SPAWN_LOCAL


# ------------------------------------------------------------------ materials
func _tex(n: String) -> Texture2D:
	return load("res://assets/textures/house/%s.jpg" % n)


func floor_mat(kind: String, rect: Array) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/house_floor.gdshader")
	m.set_shader_parameter("room_rect", Vector4(rect[0], rect[1], rect[2], rect[3]))
	m.set_shader_parameter("house_origin", ORIGIN)
	match kind:
		"wood":
			m.set_shader_parameter("albedo_tex", SurfaceFinish.GRAIN)
			m.set_shader_parameter("painted_planks",true)
			m.set_shader_parameter("tile", 2.2)
			m.set_shader_parameter("tint", Color(0.93, 0.86, 0.8))
		"kitchen":
			m.set_shader_parameter("albedo_tex", SurfaceFinish.GRAIN)
			m.set_shader_parameter("painted_planks",true)
			m.set_shader_parameter("tile", 1.8)
			m.set_shader_parameter("tint", Color(1.0, 0.95, 0.88))
		"tatami":
			m.set_shader_parameter("albedo_tex", _tex("tatami"))
			m.set_shader_parameter("floor_mode", 1)
			m.set_shader_parameter("tile", 1.4)
			m.set_shader_parameter("tint", Color(1.0, 0.99, 0.93))
		"genkan":
			m.set_shader_parameter("albedo_tex", _tex("genkan"))
			m.set_shader_parameter("floor_mode", 2)
			m.set_shader_parameter("tile", 1.3)
			m.set_shader_parameter("edge_dark", 0.3)
		"engawa":
			m.set_shader_parameter("albedo_tex", _tex("engawa"))
			m.set_shader_parameter("floor_mode", 3)
			m.set_shader_parameter("tile", 2.4)
			m.set_shader_parameter("edge_dark", 0.08)
			m.set_shader_parameter("tint", Color(1.02, 0.97, 0.9))
	return m


func wall_mat(kind: String = "plaster") -> ShaderMaterial:
	if _mats.has("wall_" + kind):
		return _mats["wall_" + kind]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/house_wall.gdshader")
	m.set_shader_parameter("albedo_tex", _tex(kind))
	m.set_shader_parameter("wood_tex", _tex("wood_floor"))
	if kind == "kitchen_tile" or kind == "fusuma":
		m.set_shader_parameter("tile", 0.9 if kind == "kitchen_tile" else 1.8)
		m.set_shader_parameter("foot_dark", 0.0 if kind == "kitchen_tile" else 0.05)
		m.set_shader_parameter("skirting_h", -2.0)
		m.set_shader_parameter("cornice_y", 9.0)
		m.set_shader_parameter("mottle", 0.0)
	else:
		# plaster rooms get the wooden wainscot, skirting, nageshi rail and cornice
		m.set_shader_parameter("tint", Color(1.0, 0.97, 0.92))
		m.set_shader_parameter("wainscot_h", 0.86)
		m.set_shader_parameter("nageshi_y", DOOR_H)
		m.set_shader_parameter("cornice_y", WALL_H - 0.07)
	_mats["wall_" + kind] = m
	return m


func wood_mat(dark: bool = true) -> StandardMaterial3D:
	var key := "wood_%s" % dark
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = SurfaceFinish.GRAIN
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.9, 0.9, 0.9)
	m.albedo_color = Color(0.46, 0.31, 0.21) if dark else Color(0.86, 0.7, 0.52)
	m.roughness = 0.6
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mats[key] = m
	return m


func flat_mat(c: Color, key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mats[key] = m
	return m


## Generated models use a PBR material; indoors they switch to a soft toon ramp so they sit
## with the painted walls and floors instead of looking like photographed objects.
static func toonify(root: Node) -> void:
	for mi in WorldBuilder.find_meshes(root):
		if mi.mesh == null:
			continue
		if mi.material_override is StandardMaterial3D:
			# Geometry override already wins over every surface. Combining both
			# creates redundant renderer references during dynamic prop cleanup.
			var whole: StandardMaterial3D=mi.material_override as StandardMaterial3D
			for surface_index: int in mi.mesh.get_surface_count():mi.set_surface_override_material(surface_index,null)
			if whole.diffuse_mode==BaseMaterial3D.DIFFUSE_TOON and whole.specular_mode==BaseMaterial3D.SPECULAR_DISABLED and whole.metallic==0:
				continue
			var converted:=whole.duplicate() as StandardMaterial3D
			converted.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON
			converted.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
			converted.roughness=.5;converted.metallic=0.0
			mi.material_override=converted
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src is StandardMaterial3D:
				var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				m.roughness = 0.5
				m.metallic = 0.0
				mi.set_surface_override_material(i, m)


# ------------------------------------------------------------------ primitives
func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = null, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi


func _collider(size: Vector3, pos: Vector3, layer: int, parent: Node = null, rot_x: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.position = pos
	body.rotation.x = rot_x
	(parent if parent else self).add_child(body)
	return body


# ------------------------------------------------------------------ lot, floors
func _build_lot() -> void:
	# garden ground all round the house, lower than the floor like a real raised Japanese house
	var gm := WorldBuilder.ground_material("grass")
	gm.set_shader_parameter("tint", Color(0.84, 0.9, 0.76))
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	g.mesh = pm
	g.material_override = gm
	g.position = Vector3(0, GROUND_Y, -2)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	var far := StandardMaterial3D.new()
	far.albedo_color = Color(0.36, 0.44, 0.3)
	far.roughness = 1.0
	var f2 := MeshInstance3D.new()
	var pm2 := PlaneMesh.new()
	pm2.size = Vector2(400, 400)
	f2.mesh = pm2
	f2.material_override = far
	f2.position = Vector3(0, GROUND_Y - 0.03, 0)
	add_child(f2)
	# foundation under the whole footprint (seen along the cut-away south edge)
	var found := flat_mat(Color(0.5, 0.44, 0.4), "found")
	# (its top stays under the sunken genkan floor at GENKAN_Y)
	_box(Vector3(13.2, -GROUND_Y, 9.4), Vector3(0, GROUND_Y / 2.0 - 0.16, 0.6), found, null, false)
	# garden bits: stepping stones, a hedge line, the painted garden beyond
	var stone := flat_mat(Color(0.72, 0.7, 0.66), "stone")
	for p in [Vector3(0.6, 0, -5.3), Vector3(1.5, 0, -6.1), Vector3(0.9, 0, -7.0), Vector3(1.9, 0, -7.8)]:
		var s := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.34
		cm.bottom_radius = 0.38
		cm.height = 0.08
		s.mesh = cm
		s.material_override = stone
		s.position = p + Vector3(0, GROUND_Y + 0.03, 0)
		s.scale = Vector3(1.0, 1.0, 0.8)
		add_child(s)
	for i in 9:
		var sh := wb.spawn("M12b_shrub", Vector3(-7.5 + i * 1.9, GROUND_Y, -8.8 + (0.25 if i % 2 else 0.0)), i * 37.0, 0, self, 0.9)
		if sh:
			toonify(sh)
	for spec in [[Vector3(-7.4, GROUND_Y, -6.2), 0.42], [Vector3(7.6, GROUND_Y, -6.0), 0.38]]:
		var tree := wb.spawn("T01_courtyard_tree", spec[0], 30.0, 0, self, spec[1])
		if tree:
			toonify(tree)
	# the painted garden beyond the hedge leans back to face the fixed diorama camera
	# (pitch ~50 deg), so it reads as a flat backdrop painting instead of a foreshortened wall
	var card := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(30, 30 * 1024.0 / 1536.0)
	card.mesh = qm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_texture = _tex("card_garden")
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(0.97, 0.97, 0.95)
	card.material_override = cmat
	wb.std_cards.append([cmat, cmat.albedo_color])
	var lean := deg_to_rad(-47.0)
	card.rotation.x = lean
	var up := Vector3(0, cos(lean), sin(lean))
	card.position = Vector3(0, GROUND_Y - 0.35, -9.35) + up * (qm.size.y / 2.0)
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(card)
	_build_fence()
	# engawa boundary with a gap at the stepping stone, which leads down into the little yard
	_collider(Vector3(2.55, 1.4, 0.2), Vector3(-0.325, 0.7, -4.72), WorldBuilder.L_PLACED)
	_collider(Vector3(4.55, 1.4, 0.2), Vector3(4.325, 0.7, -4.72), WorldBuilder.L_PLACED)
	_collider(Vector3(0.2, 1.4, 1.5), Vector3(-1.62, 0.7, -3.95), WorldBuilder.L_PLACED)
	_collider(Vector3(0.2, 1.4, 1.5), Vector3(6.62, 0.7, -3.95), WorldBuilder.L_PLACED)
	_build_yard()


var yard_plots := {}

func _build_yard() -> void:
	var L := WorldBuilder.L_GROUND
	_collider(Vector3(8.4, 0.4, 3.9), Vector3(2.5, GROUND_Y - 0.2, -6.5), L)
	var a := atan2(-GROUND_Y, 0.8)
	_collider(Vector3(1.1, 0.1, 0.94), Vector3(1.5, GROUND_Y / 2.0 - 0.05, -5.0), L, null, -a)
	var P := WorldBuilder.L_PLACED
	_collider(Vector3(0.2, 1.6, 3.8), Vector3(-1.62, GROUND_Y + 0.8, -6.5), P)
	_collider(Vector3(0.2, 1.6, 3.8), Vector3(6.62, GROUND_Y + 0.8, -6.5), P)
	_collider(Vector3(8.4, 1.6, 0.2), Vector3(2.5, GROUND_Y + 0.8, -8.42), P)
	var yg := GrassField.new()
	yg.name = "YardGrass"
	add_child(yg)
	var yard := [[-1.4, -8.25, 6.45, -4.75]]
	var beds := [[2.45, -8.35, 5.75, -5.25], [-1.25, -8.35, 0.15, -5.25], [0.2, -8.4, 2.3, -4.6], [Vector2(6.05, -5.2), 0.45]]
	var rim := [[-7.9, -8.9, 8.2, -8.3], [-7.9, -8.3, -1.7, -5.0], [6.7, -8.3, 8.2, -5.0]]
	yg.lawn(yard, beds, "lawn", 6.5, 31, GROUND_Y)
	yg.lawn(rim, [], "meadow", 4.0, 32, GROUND_Y)
	yg.scatter(yard + rim, 0.25, beds, GrassField.MIX_FLOWERS, Vector2(0.18, 0.32), 33, GROUND_Y)
	for id in YARD_PLOTS:
		var pv := PlotView.new()
		add_child(pv)
		pv.position = YARD_PLOTS[id] + Vector3(0, GROUND_Y, 0)
		pv.setup(wb, id, true, 0.88)
		yard_plots[id] = pv
	# garden tap: a concrete post, a brass faucet and a bucket
	var conc := flat_mat(Color(0.7, 0.69, 0.66), "tap_post")
	var brass := flat_mat(Color(0.78, 0.62, 0.3), "brass")
	_box(Vector3(0.16, 0.8, 0.16), YARD_TAP + Vector3(0, GROUND_Y + 0.4, 0), conc)
	_box(Vector3(0.06, 0.06, 0.16), YARD_TAP + Vector3(0, GROUND_Y + 0.68, 0.12), brass)
	_box(Vector3(0.1, 0.03, 0.03), YARD_TAP + Vector3(0, GROUND_Y + 0.74, 0.08), brass)
	var bucket := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.15
	cm.bottom_radius = 0.12
	cm.height = 0.25
	bucket.mesh = cm
	bucket.material_override = flat_mat(Color(0.35, 0.52, 0.66), "bucket")
	bucket.position = YARD_TAP + Vector3(-0.05, GROUND_Y + 0.125, 0.32)
	add_child(bucket)
	_collider(Vector3(0.3, 1.0, 0.3), YARD_TAP + Vector3(0, GROUND_Y + 0.5, 0), WorldBuilder.L_SOLID)


func refresh_plots() -> void:
	for id in yard_plots:
		(yard_plots[id] as PlotView).refresh()


## Low cedar board fence round the lot, with a gap for the path from the front door.
func _build_fence() -> void:
	var boards := StandardMaterial3D.new()
	boards.albedo_texture = _tex("engawa")
	boards.uv1_triplanar = true
	boards.uv1_world_triplanar = true
	boards.uv1_scale = Vector3(0.45, 0.45, 0.45)
	boards.albedo_color = Color(0.86, 0.74, 0.62)
	boards.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	boards.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var post := wood_mat(true)
	var h := 1.25
	var y0 := GROUND_Y
	var runs := [[Vector2(-8.8, -9.1), Vector2(-8.8, 6.4)], [Vector2(8.8, -9.1), Vector2(8.8, 6.4)],
			[Vector2(-8.8, 6.4), Vector2(3.9, 6.4)], [Vector2(6.1, 6.4), Vector2(8.8, 6.4)]]
	for r in runs:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var ln := a.distance_to(b)
		var along_x := absf(a.y - b.y) < 0.01
		var mid := (a + b) / 2.0
		var sz := Vector3(ln, h, 0.05) if along_x else Vector3(0.05, h, ln)
		_box(sz, Vector3(mid.x, y0 + h / 2.0, mid.y), boards)
		var cap := Vector3(ln + 0.08, 0.05, 0.1) if along_x else Vector3(0.1, 0.05, ln + 0.08)
		_box(cap, Vector3(mid.x, y0 + h + 0.025, mid.y), post)
		var n := int(ceil(ln / 1.8))
		for i in n + 1:
			var p := a.lerp(b, float(i) / float(n))
			_box(Vector3(0.09, h + 0.08, 0.09), Vector3(p.x, y0 + (h + 0.08) / 2.0, p.y), post)
	# stepping stones from the front door to the gate
	var stone := flat_mat(Color(0.74, 0.72, 0.68), "stone")
	for p in [Vector3(5.0, 0, 5.15), Vector3(4.8, 0, 5.85), Vector3(5.1, 0, 6.5)]:
		var s := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.3
		cm.bottom_radius = 0.33
		cm.height = 0.08
		s.mesh = cm
		s.material_override = stone
		s.position = p + Vector3(0, GROUND_Y + 0.03, 0)
		s.scale = Vector3(1.0, 1.0, 0.78)
		add_child(s)


func _build_floors() -> void:
	for r in ROOMS:
		if r.get("outdoor", false):
			continue
		var q: Array = r.rect
		if r.id == "genkan":
			q = [q[0], q[1], q[2], PEBBLE_RECT[1]]
		var sz := Vector3(q[2] - q[0], 0.1, q[3] - q[1])
		_box(sz, Vector3((q[0] + q[2]) / 2.0, -0.05, (q[1] + q[3]) / 2.0), floor_mat(r.floor, q), null, false)
	var p: Array = PEBBLE_RECT
	var pm := floor_mat("genkan", p)
	_box(Vector3(p[2] - p[0], 0.1, p[3] - p[1] + 0.3), Vector3((p[0] + p[2]) / 2.0, GENKAN_Y - 0.05 + 0.001, (p[1] + p[3]) / 2.0 + 0.15), pm, null, false)
	# raised wooden step edge (agari-kamachi) around the sunken genkan
	var dark := wood_mat(true)
	_box(Vector3(p[2] - p[0], 0.13, 0.12), Vector3((p[0] + p[2]) / 2.0, -0.065 + 0.002, p[1] + 0.06), dark)
	_box(Vector3(0.12, 0.13, p[3] - p[1]), Vector3(p[0] + 0.06, -0.065 + 0.002, (p[1] + p[3]) / 2.0), dark)
	# ground colliders: floor at 0, genkan at GENKAN_Y, ramps over the step edges
	var L := WorldBuilder.L_GROUND
	_collider(Vector3(13.0, 0.4, 7.4), Vector3(0, -0.2, -0.9), L)
	_collider(Vector3(10.0, 0.4, 1.7), Vector3(-1.5, -0.2, 3.65), L)
	_collider(Vector3(3.0, 0.4, 2.4), Vector3(5.0, GENKAN_Y - 0.2, 3.85), L)
	var a := atan2(-GENKAN_Y, 0.42)
	_collider(Vector3(3.0, 0.1, 0.44), Vector3(5.0, GENKAN_Y / 2.0 - 0.05, p[1] + 0.2), L, null, a)
	var ramp := _collider(Vector3(0.44, 0.1, 1.7), Vector3(p[0] + 0.2, GENKAN_Y / 2.0 - 0.05, 3.65), L)
	ramp.rotation = Vector3(0, 0, -a)


# ------------------------------------------------------------------ walls
func _build_wall(w: Dictionary) -> void:
	var a: Vector2 = w.a
	var b: Vector2 = w.b
	var ew: bool = absf(a.y - b.y) < 0.001
	var pivot := Node3D.new()
	pivot.name = "Wall_" + str(w.id)
	add_child(pivot)
	var rails: Array = []
	var s0: float = a.x if ew else a.y
	var s1: float = b.x if ew else b.y
	var fixed: float = a.y if ew else a.x
	var segs: Array = []   # solid [from, to, y0, y1]
	var cur := s0
	var opens: Array = w.open.duplicate()
	opens.sort_custom(func(p, q): return p[0] < q[0])
	var posts: Array = [s0, s1]
	for o in opens:
		var o0: float = o[0]
		var o1: float = o[1]
		if o0 > cur:
			segs.append([cur, o0, 0.0, WALL_H])
		var kind: String = o[2]
		var top := DOOR_H if kind == "door" else (1.9 if kind == "glass" else float(o[4]))
		if not w.get("always_cut", false):
			segs.append([o0, o1, top, WALL_H])
		if kind == "window":
			segs.append([o0, o1, 0.0, float(o[3])])
			_window(pivot, ew, fixed, o0, o1, float(o[3]), top, str(o[5]), rails)
		elif not w.get("always_cut", false):
			rails.append(_rail(pivot, ew, fixed, o0, o1, top))
			if kind == "glass":
				_glass(pivot, ew, fixed, o0, o1, top, rails)
		posts.append(o0)
		posts.append(o1)
		cur = o1
	if cur < s1:
		segs.append([cur, s1, 0.0, WALL_H])
	var mat := wall_mat()
	for sg in segs:
		var ln: float = sg[1] - sg[0]
		if ln <= 0.01:
			continue
		var h: float = sg[3] - sg[2]
		var mid: float = (sg[0] + sg[1]) / 2.0
		var y: float = (sg[2] + sg[3]) / 2.0
		var size := Vector3(ln, h, WALL_T) if ew else Vector3(WALL_T, h, ln)
		var pos := Vector3(mid, y, fixed) if ew else Vector3(fixed, y, mid)
		var piece := _box(size, pos, mat, pivot)
		if sg[2] > 0.5:
			rails.append(piece)   # lintels hide with the rails when the wall is cut down
		if sg[2] < 0.5:
			var csz := Vector3(ln, 2.0, WALL_T + 0.06) if ew else Vector3(WALL_T + 0.06, 2.0, ln)
			var cpos := Vector3(mid, 1.0, fixed) if ew else Vector3(fixed, 1.0, mid)
			_collider(csz, cpos, WorldBuilder.L_PLACED)
	var wood := wood_mat(true)
	var seen := {}
	for sp in posts:
		var k := snappedf(sp, 0.01)
		if seen.has(k):
			continue
		seen[k] = true
		var pp := Vector3(sp, WALL_H / 2.0, fixed) if ew else Vector3(fixed, WALL_H / 2.0, sp)
		_box(Vector3(0.15, WALL_H, 0.17) if ew else Vector3(0.17, WALL_H, 0.15), pp, wood, pivot)
	cut_groups[w.id] = {"pivot": pivot, "rails": rails, "z": fixed, "ew": ew, "cut": false,
			"always": bool(w.get("always_cut", false))}


func _rail(parent: Node3D, ew: bool, fixed: float, o0: float, o1: float, top: float) -> MeshInstance3D:
	var ln := o1 - o0
	var size := Vector3(ln, 0.08, WALL_T + 0.05) if ew else Vector3(WALL_T + 0.05, 0.08, ln)
	var pos := Vector3((o0 + o1) / 2.0, top + 0.04, fixed) if ew else Vector3(fixed, top + 0.04, (o0 + o1) / 2.0)
	return _box(size, pos, wood_mat(true), parent)


func _window(parent: Node3D, ew: bool, fixed: float, o0: float, o1: float, sill: float, top: float, view: String, rails: Array) -> void:
	var wood := wood_mat(true)
	var ln := o1 - o0
	var mid := (o0 + o1) / 2.0
	var h := top - sill
	rails.append(_rail(parent, ew, fixed, o0, o1, top))
	var sb := _box(Vector3(ln + 0.1, 0.06, WALL_T + 0.1) if ew else Vector3(WALL_T + 0.1, 0.06, ln + 0.1),
			Vector3(mid, sill, fixed) if ew else Vector3(fixed, sill, mid), wood, parent)
	rails.append(sb)
	# lattice bars (kumiko) in the frame
	var nb := int(ln / 0.45)
	for i in range(1, nb + 1):
		var s := o0 + ln * i / float(nb + 1)
		var bar := _box(Vector3(0.035, h, 0.04) if ew else Vector3(0.04, h, 0.035),
				Vector3(s, sill + h / 2.0, fixed) if ew else Vector3(fixed, sill + h / 2.0, s), wood, parent, false)
		rails.append(bar)
	var mb := _box(Vector3(ln, 0.035, 0.04) if ew else Vector3(0.04, 0.035, ln),
			Vector3(mid, sill + h * 0.55, fixed) if ew else Vector3(fixed, sill + h * 0.55, mid), wood, parent, false)
	rails.append(mb)
	if view == "card":
		# a painted view just behind the glass; it faces into the room, so from outside the
		# back face is culled and the card is invisible
		var card := MeshInstance3D.new()
		var qm := QuadMesh.new()
		var cw := ln + 0.3
		var ch := h + 0.3
		qm.size = Vector2(cw, ch)
		card.mesh = qm
		var m := StandardMaterial3D.new()
		m.albedo_texture = _tex("card_window")
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.04, 1.04, 1.04)
		var ta := 1536.0 / 1024.0
		var ca := cw / ch
		if ca < ta:
			m.uv1_scale = Vector3(ca / ta, 1.0, 1.0)
			m.uv1_offset = Vector3((1.0 - ca / ta) * 0.62, 0.0, 0.0)
		else:
			m.uv1_scale = Vector3(1.0, ta / ca, 1.0)
			m.uv1_offset = Vector3(0.0, (1.0 - ta / ca) * 0.4, 0.0)
		card.material_override = m
		wb.std_cards.append([m, m.albedo_color])
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var out := WALL_T / 2.0 + 0.12
		if ew:
			card.position = Vector3(mid, sill + h / 2.0, fixed + out * signf(fixed))
			card.rotation.y = PI if fixed > 0.0 else 0.0
		else:
			card.position = Vector3(fixed + out * signf(fixed), sill + h / 2.0, mid)
			card.rotation.y = -PI / 2.0 * signf(fixed)
		parent.add_child(card)


func _glass(parent: Node3D, ew: bool, fixed: float, o0: float, o1: float, top: float, rails: Array) -> void:
	# sliding glass doors pushed to the east end, plus slim intermediate posts
	var wood := wood_mat(true)
	var n := 4
	for i in range(1, n):
		var s := o0 + (o1 - o0) * i / float(n)
		var p := _box(Vector3(0.1, top, 0.1), Vector3(s, top / 2.0, fixed), wood, parent)
		rails.append(p)
		_collider(Vector3(0.12, 2.0, 0.12), Vector3(s, 1.0, fixed), WorldBuilder.L_PLACED)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.92, 1.0, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 2:
		var x0 := o1 - 0.95 * (k + 1) + 0.05
		var z := fixed - 0.04 - 0.05 * k
		var pane := _box(Vector3(0.9, top - 0.06, 0.012), Vector3(x0 + 0.45, top / 2.0, z), glass, parent, false)
		rails.append(pane)
		for fr in [[Vector3(0.9, 0.05, 0.035), Vector3(x0 + 0.45, 0.03, z)], [Vector3(0.9, 0.05, 0.035), Vector3(x0 + 0.45, top - 0.05, z)],
				[Vector3(0.05, top - 0.06, 0.035), Vector3(x0 + 0.02, top / 2.0, z)], [Vector3(0.05, top - 0.06, 0.035), Vector3(x0 + 0.88, top / 2.0, z)]]:
			rails.append(_box(fr[0], fr[1], wood, parent, false))


# ------------------------------------------------------------------ engawa, details
func _build_engawa() -> void:
	var wood := wood_mat(true)
	var r: Array = ROOMS[5].rect
	# edge beam and eave posts along the garden side
	_box(Vector3(r[2] - r[0] + 0.1, 0.14, 0.14), Vector3((r[0] + r[2]) / 2.0, -0.07, r[1] + 0.07), wood)
	_box(Vector3(r[2] - r[0], -GROUND_Y - 0.1, 0.1), Vector3((r[0] + r[2]) / 2.0, (GROUND_Y - 0.1) / 2.0 - 0.04, r[1] + 0.15), flat_mat(Color(0.3, 0.24, 0.2), "under"), null, false)
	for x in [r[0] + 0.08, 2.5, r[2] - 0.08]:
		_box(Vector3(0.13, WALL_H + 0.1, 0.13), Vector3(x, (WALL_H + 0.1) / 2.0, r[1] + 0.08), wood)
	# a flat stepping stone (kutsunugi-ishi) below the veranda
	_box(Vector3(0.9, 0.22, 0.5), Vector3(1.5, GROUND_Y + 0.11, r[1] - 0.35), flat_mat(Color(0.68, 0.66, 0.62), "stone2"))


func _build_details() -> void:
	# kitchen tile splash-back on the west wall under the window
	var tile := wall_mat("kitchen_tile")
	var t := _box(Vector3(0.03, 0.45, 2.2), Vector3(-6.5 + WALL_T / 2.0 + 0.016, 1.0, 3.0), tile, null, false)
	t.name = "Splashback"
	# fusuma panel slid open beside the bedroom door (living-room side)
	var fus := wall_mat("fusuma")
	var fp := _box(Vector3(0.03, DOOR_H - 0.02, 0.92), Vector3(-1.5 + WALL_T / 2.0 + 0.02, DOOR_H / 2.0, -2.25 + 0.0), fus, null, false)
	fp.name = "Fusuma"
	var wood := wood_mat(true)
	for fr in [[Vector3(0.04, DOOR_H, 0.04), Vector3(-1.5 + WALL_T / 2.0 + 0.025, DOOR_H / 2.0, -2.71)],
			[Vector3(0.04, DOOR_H, 0.04), Vector3(-1.5 + WALL_T / 2.0 + 0.025, DOOR_H / 2.0, -1.79)]]:
		_box(fr[0], fr[1], wood, null, false)
	# v0.6: grandma's oshiire closet on the bedroom's west wall (two fusuma doors in a wooden frame)
	var cl := _box(Vector3(0.5, 1.9, 1.34), Vector3(-6.5 + WALL_T / 2.0 + 0.26, 0.95, 0.25), wood, null, true)
	cl.name = "Oshiire"
	_collider(Vector3(0.5, 1.9, 1.34), Vector3(-6.5 + WALL_T / 2.0 + 0.26, 0.95, 0.25), WorldBuilder.L_SOLID)
	for k in 2:
		_box(Vector3(0.02, 1.72, 0.62), Vector3(-6.5 + WALL_T / 2.0 + 0.52, 0.95, 0.25 + (k - 0.5) * 0.64), fus, null, false)
	# rugs
	_rug(Vector3(-3.6, 0.006, -1.0), Vector2(1.9, 1.35), Color(0.55, 0.66, 0.78), Color(0.95, 0.9, 0.8))
	_rug(Vector3(5.0, GENKAN_Y + 0.006, 4.05), Vector2(1.2, 0.55), Color(0.36, 0.5, 0.42), Color(0.5, 0.64, 0.52))
	_rug(Vector3(-2.3, 0.006, 3.0), Vector2(2.1, 1.7), Color(0.9, 0.78, 0.6), Color(0.82, 0.62, 0.45))
	# noren curtain over the kitchen doorway (short, above head height)
	var noren := flat_mat(Color(0.2, 0.3, 0.46), "noren")
	for k in 2:
		_box(Vector3(0.02, 0.32, 0.55), Vector3(0.5 - WALL_T / 2.0 - 0.02, DOOR_H - 0.17, 2.32 + k * 0.57), noren, null, false)
	# front-door frame on the south stub
	for x in DOOR_X:
		_box(Vector3(0.12, 0.6, 0.16), Vector3(x, 0.3 + GENKAN_Y, 4.5), wood)


func _rug(pos: Vector3, size: Vector2, a: Color, b: Color) -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/house_rug.gdshader")
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("size", size)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_furniture() -> void:
	for f in FURNITURE:
		var n := wb.spawn(f[0], Vector3(f[1], f[5], f[2]), f[3], f[4], self)
		if n == null:
			continue
		toonify(n)
		for body in n.find_children("*", "StaticBody3D", true, false):
			(body as StaticBody3D).collision_layer = WorldBuilder.L_PLACED
	boxes = Node3D.new()
	boxes.name = "Boxes"
	add_child(boxes)
	# Keep the moving-in cluster beside the cabinet, clear of the living-room door.
	for spec in [[Vector3(0.35, 0, 0.25), 12.0]]:
		var b := wb.spawn("I08_boxes", spec[0], spec[1], 2, boxes)
		if b:
			toonify(b)
			for body in b.find_children("*", "StaticBody3D", true, false):
				(body as StaticBody3D).collision_layer = WorldBuilder.L_PLACED
	goldfish = wb.spawn("G05_goldfish_bowl", Vector3(-0.75, 0, -4.05), 0.0, 2, self)
	if goldfish:
		toonify(goldfish)
	map_frame = Node3D.new()
	map_frame.name = "MapFrame"
	add_child(map_frame)
	var fr := _box(Vector3(0.8, 0.8, 0.04), Vector3(-2.0, 1.45, -3.3 + WALL_T / 2.0 + 0.02), wood_mat(true), map_frame, false)
	fr.name = "Frame"
	var pic := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.68, 0.68)
	pic.mesh = qm
	var pm := StandardMaterial3D.new()
	var mp := "res://assets/minigames/puzzle/map.png"
	if ResourceLoader.exists(mp):
		pm.albedo_texture = load(mp)
	else:
		pm.albedo_color = Color(0.9, 0.85, 0.7)
	pm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	pic.material_override = pm
	pic.position = Vector3(-2.0, 1.45, -3.3 + WALL_T / 2.0 + 0.045)
	map_frame.add_child(pic)


func _build_lights() -> void:
	for spec in [[Vector3(2.4, 2.15, -1.2), 7.0], [Vector3(-2.6, 2.15, 2.8), 6.5], [Vector3(-4.2, 1.6, -1.8), 5.0], [Vector3(4.8, 2.1, 2.6), 4.5]]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.56)
		l.omni_range = spec[1]
		l.omni_attenuation = 1.2
		l.shadow_enabled = true
		l.light_energy = 0.0
		l.position = spec[0]
		add_child(l)
		lamps.append(l)
	# pendant shades above the kotatsu and the dining table
	var shade := StandardMaterial3D.new()
	shade.albedo_color = Color(1.0, 0.93, 0.78)
	shade.emission_enabled = true
	shade.emission = Color(1.0, 0.82, 0.55)
	shade.emission_energy_multiplier = 0.0
	_mats["shade"] = shade
	for p in [Vector3(2.4, 2.05, -1.2), Vector3(-2.6, 2.05, 2.8)]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.34
		cm.height = 0.26
		mi.mesh = cm
		mi.material_override = shade
		mi.position = p
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var cord := _box(Vector3(0.015, 0.4, 0.015), p + Vector3(0, 0.33, 0), flat_mat(Color(0.2, 0.18, 0.16), "cord"), null, false)
		cord.name = "Cord"
	# soft warm fill so shaded corners stay readable (no shadows, very low)
	for p in [Vector3(-4.0, 1.8, -1.2), Vector3(2.5, 1.8, -1.2), Vector3(-3.0, 1.8, 2.8), Vector3(3.5, 1.8, 2.8)]:
		var f := OmniLight3D.new()
		f.light_color = Color(1.0, 0.9, 0.8)
		f.omni_range = 5.5
		f.light_energy = 0.28
		f.shadow_enabled = false
		f.position = p
		add_child(f)
		fills.append(f)
	# dust motes floating in the sun coming through the glass doors
	dust = GPUParticles3D.new()
	dust.amount = 70
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.position = Vector3(2.5, 1.0, -2.3)
	dust.visibility_aabb = AABB(Vector3(-5, -1.5, -2.5), Vector3(10, 3, 5))
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(3.6, 0.9, 1.1)
	pmat.gravity = Vector3(0, 0.004, 0)
	pmat.initial_velocity_min = 0.01
	pmat.initial_velocity_max = 0.05
	pmat.direction = Vector3(0.3, 0.2, 1)
	pmat.spread = 180.0
	pmat.turbulence_enabled = true
	pmat.turbulence_noise_strength = 0.35
	pmat.turbulence_noise_scale = 1.4
	pmat.scale_min = 0.5
	pmat.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.25, Color(1, 1, 1, 1))
	fade.add_point(0.75, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pmat.color_ramp = gt
	dust.process_material = pmat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.018, 0.018)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(1.0, 0.95, 0.8, 0.8)
	qm.material = dm
	dust.draw_pass_1 = qm
	add_child(dust)


func _build_roof_shadow() -> void:
	# invisible roof: it only casts shadow, so sunlight reaches the rooms through the openings.
	# The eave over the engawa is kept short so the afternoon sun reaches deep into the living
	# room; over the bedroom it stops at the wall so the lattice window throws a sun patch.
	for spec in ROOF_PARTS:
		var r := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(spec[2] - spec[0], 0.1, spec[3] - spec[1])
		r.mesh = bm
		r.position = Vector3((spec[0] + spec[2]) / 2.0, WALL_H + 0.05, (spec[1] + spec[3]) / 2.0)
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(r)


## Painted light shafts through the north openings: stacks of additive sheets swept along the
## daytime sun direction, with gaps where the door posts or window lattice block the light.
func _build_sunbeams() -> void:
	beams = Node3D.new()
	beams.name = "Sunbeams"
	add_child(beams)
	var d := (Basis.from_euler(SUN_DAY_ROT * PI / 180.0) * Vector3(0, 0, -1)).normalized()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/house_beam.gdshader")
	_mats["beam"] = mat
	for spec in BEAM_OPENINGS:
		var x0: float = spec[0]
		var x1: float = spec[1]
		var zw: float = spec[2]
		var sill: float = spec[3]
		var top: float = spec[4]
		var eave_z: float = spec[5]
		# the eave cuts off the top of the opening: highest ray that still gets under it
		var lit_top: float = min(top, WALL_H - (zw - eave_z) * (-d.y / d.z))
		if lit_top <= sill + 0.05:
			continue
		var m := mat.duplicate() as ShaderMaterial
		m.set_shader_parameter("posts", float(spec[6]))
		m.set_shader_parameter("post_w", float(spec[7]))
		m.set_shader_parameter("strength", float(spec[8]))
		var layers := 5
		for i in layers:
			var hs: float = lerp(lit_top, sill, float(i) / float(layers))
			var t := hs / -d.y
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var p0 := Vector3(x0, hs, zw)
			var p1 := Vector3(x1, hs, zw)
			var q0 := p0 + d * t
			var q1 := p1 + d * t
			var n := (p1 - p0).cross(d).normalized()
			for v in [[p0, Vector2(0, 0)], [p1, Vector2(1, 0)], [q1, Vector2(1, 1)], [p0, Vector2(0, 0)], [q1, Vector2(1, 1)], [q0, Vector2(0, 1)]]:
				st.set_normal(n)
				st.set_uv(v[1])
				st.add_vertex(v[0])
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			beams.add_child(mi)


# ------------------------------------------------------------------ runtime
## Drop the east-west walls on the south side of the player's room to low stubs.
func update_cutaway(room_id: String, animate: bool = true) -> void:
	current_room = room_id
	var zmax := 99.0
	for r in ROOMS:
		if r.id == room_id:
			zmax = float(r.rect[3])
	for id in cut_groups:
		var g: Dictionary = cut_groups[id]
		var want: bool = g.always or (g.ew and float(g.z) >= zmax - 0.01)
		if want == g.cut and animate:
			continue
		g.cut = want
		var s := STUB_H / WALL_H if want else 1.0
		var pv: Node3D = g.pivot
		for rl in g.rails:
			(rl as Node3D).visible = not want
		if animate:
			var tw := pv.create_tween()
			tw.tween_property(pv, "scale:y", s, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			pv.scale.y = s


func track_player(world_pos: Vector3) -> void:
	var r := room_at(world_pos - ORIGIN)
	var id := str(r.get("id", current_room))
	if id != current_room and id != "":
		update_cutaway(id)


func room_name(world_pos: Vector3) -> String:
	return str(room_at(world_pos - ORIGIN).get("name", "我的家"))


func sync_state() -> void:
	var F := GameState.flags
	if boxes:
		boxes.visible = not F.get("house_tidy", false)
		for body in boxes.find_children("*", "StaticBody3D", true, false):
			(body as StaticBody3D).collision_layer = 0 if F.get("house_tidy", false) else WorldBuilder.L_PLACED
	if goldfish:
		goldfish.visible = F.get("goldfish_home", false)
	if map_frame:
		map_frame.visible = F.get("map_framed", false)
	if is_instance_valid(future_note):
		var direction: Dictionary = MainlineProgress.direction()
		future_note.visible = not direction.is_empty()
		if future_note.visible: future_note_label.text = str(MainlineProgress.DIRECTION_CAPTIONS[int(direction.choice)])

func _build_future_note() -> void:
	var desk: Node3D = get_node_or_null("I02_desk")
	if desk==null: return
	var at: Vector3 = ORIGIN+Vector3(-3.5,0,-2.66)
	var height: float = WorldBuilder.rendered_support_height(desk,at,1.2)
	future_note=Node3D.new()
	future_note.name="SummerDirectionNote"
	add_child(future_note)
	future_note.position=Vector3(at.x-ORIGIN.x,height+.012,at.z-ORIGIN.z)
	var sheet:=MeshInstance3D.new()
	var paper:=PlaneMesh.new()
	paper.size=Vector2(.36,.28)
	sheet.mesh=paper
	sheet.material_override=flat_mat(Color(.98,.93,.78),"future_note_paper")
	future_note.add_child(sheet)
	future_note_label=Label3D.new()
	future_note_label.font=load("res://assets/fonts/LXGWWenKai-Medium.ttf")
	future_note_label.font_size=40
	future_note_label.pixel_size=.0017
	future_note_label.outline_size=0
	future_note_label.modulate=Color(.24,.32,.25)
	future_note_label.position.y=.002
	future_note_label.rotation.x=-PI/2
	future_note.add_child(future_note_label)


var _evening_state := -1

func set_evening(on: bool, animate: bool) -> void:
	if _evening_state == int(on) and not animate:
		return
	_evening_state = int(on)
	var e := 1.3 if on else 0.0
	var fill := 0.12 if on else 0.28
	var shade: StandardMaterial3D = _mats.get("shade")
	if animate:
		var tw := create_tween().set_parallel(true)
		for l in lamps:
			tw.tween_property(l, "light_energy", e, 1.5)
		for f in fills:
			tw.tween_property(f, "light_energy", fill, 1.5)
		if shade:
			tw.tween_property(shade, "emission_energy_multiplier", 2.2 if on else 0.0, 1.5)
	else:
		for l in lamps:
			l.light_energy = e
		for f in fills:
			f.light_energy = fill
		if shade:
			shade.emission_energy_multiplier = 2.2 if on else 0.0
	if dust:
		dust.emitting = not on
	if beams:
		beams.visible = not on

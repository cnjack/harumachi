class_name WorldBuilder
extends Node3D
## Builds the static town from Layout: ground, buildings, props, walls, plants, background
## cards, sky and lighting. The player's house (the only interior) is built by HouseBuilder.

const L_GROUND := 1
const L_SOLID := 2
const L_ACTORS := 4
const L_CAMERA := 8
const L_PLACED := 16
const L_BLOCK := 32          # player-only keep-outs: the camera arm passes through them
const GATE_TITLE_Y := 2.35   # measured centre of the replacement gate's name plaque
const GATE_POST_CENTERS := [Vector3(-1.82, 1.5, -0.05), Vector3(1.77, 1.5, 0.04)]
const NEAR_TREES := ["T02_summer_tree", "T03_round_ginkgo", "T04_slender_cedar"]

static var _cache := {}
static var _spawn_order := 0

## Match the rendered base to its actual support; a small embed roots trees in soil.
static func rest_on(instance: Node3D,surface_y: float,embed: float=0.0) -> void:
	var bounds: AABB=instance.global_transform*local_aabb(instance)
	instance.global_position.y += surface_y-embed-bounds.position.y
	instance.set_meta("support_y",surface_y)
	instance.set_meta("support_embed",embed)

## Intersect a vertical line with rendered triangles (including supports without colliders).
static func surface_height(instance: Node3D,at: Vector2,ceiling: float=INF,terrain_only: bool=false) -> float:
	var highest: float=-INF
	for mesh_instance: MeshInstance3D in find_meshes(instance):
		if terrain_only:
			var ancestor: Node=mesh_instance
			var belongs_to_model:=false
			while ancestor!=null:
				if ancestor.has_meta("model_id"):belongs_to_model=true;break
				ancestor=ancestor.get_parent()
			if belongs_to_model:continue
		var bounds: AABB=mesh_instance.global_transform*mesh_instance.get_aabb()
		if not Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(.001).has_point(at):continue
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays: Array=mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var count: int=indices.size() if not indices.is_empty() else vertices.size()
			for offset in range(0,count-2,3):
				var a: Vector3=mesh_instance.global_transform*vertices[indices[offset] if not indices.is_empty() else offset]
				var b: Vector3=mesh_instance.global_transform*vertices[indices[offset+1] if not indices.is_empty() else offset+1]
				var c: Vector3=mesh_instance.global_transform*vertices[indices[offset+2] if not indices.is_empty() else offset+2]
				var ab:=Vector2(b.x-a.x,b.z-a.z);var ac:=Vector2(c.x-a.x,c.z-a.z);var ap:=at-Vector2(a.x,a.z)
				var determinant:=ab.cross(ac)
				if absf(determinant)<.0000001:continue
				var u:=ap.cross(ac)/determinant;var v:=ab.cross(ap)/determinant
				if u<-.001 or v<-.001 or u+v>1.001:continue
				var height:=a.y+(b.y-a.y)*u+(c.y-a.y)*v
				if height<=ceiling:highest=maxf(highest,height)
	return highest

static func rest_on_terrain(instance: Node3D,fallback_y: float,embed: float=.025) -> void:
	var owner: Node=instance.get_parent()
	while owner!=null and not owner is WorldBuilder:owner=owner.get_parent()
	var height: float=fallback_y
	if owner is WorldBuilder:
		var actual:=surface_height(owner,Vector2(instance.global_position.x,instance.global_position.z),fallback_y+.40,true)
		if is_finite(actual):height=actual
	rest_on(instance,height,embed)

var clock_face: VillageClock
var bus: TownBus
var sun: DirectionalLight3D
var env: Environment
var world_env: WorldEnvironment
var planter_plants: Node3D
var planter_soil_mat: ShaderMaterial
var tomatoes: Node3D
var stall_bread: Node3D
var stall_bread_surface := Vector3.INF
var bakery_market_sign: Label3D
var poster: Node3D
var lamp_lights: Array[OmniLight3D] = []
var window_mats: Array[ShaderMaterial] = []   # v0.7.3 shop windows (ShopWindows)
var building_life: Array[Dictionary] = []
var sky_mat: ShaderMaterial
var card_mats: Array[ShaderMaterial] = []
var std_cards: Array = []   # [StandardMaterial3D, base colour]: unshaded painted views (the house garden)
var look := {}          # the last applied time-of-day look (tests read it)
var stats := {"models": 0, "missing": []}


static func model_scene(id: String) -> PackedScene:
	if _cache.has(id):
		return _cache[id]
	var path := "res://assets/models/%s.glb" % id
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	_cache[id] = ps
	return ps


## Instance a generated model. Returns null (and records it) when the GLB is not available yet.
func spawn(id: String, pos: Vector3, yaw_deg: float, collide: int = 1, parent: Node = null, scale_f: float = 1.0) -> Node3D:
	var ps := model_scene(id)
	if ps == null:
		if not stats.missing.has(id):
			stats.missing.append(id)
		return null
	var n: Node3D = ps.instantiate()
	n.name = id
	n.set_meta("model_id", id)
	_spawn_order += 1
	n.set_meta("spawn_order", _spawn_order)
	n.set_meta("spawn_ms", Time.get_ticks_msec())
	n.position = pos
	n.rotation.y = deg_to_rad(yaw_deg)
	n.scale = Vector3.ONE * scale_f
	(parent if parent else self).add_child(n)
	stats.models += 1
	for mi in find_meshes(n):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	SurfaceFinish.apply(n,id)
	if id in ["P_farm_gate", "P_signpost", "P_bridge", "P_yagura", "H01", "H02", "H03", "S06", "S01", "S02", "S03", "S05", "S08", "M01_timber_machiya", "M03_gable_house", "M05_residential"]:
		HouseBuilder.toonify(n)
	if id.begins_with("T0"):
		n.set_meta("tree_geometry_version",2)
	if SWAY.has(id):
		make_sway(n, SWAY[id][0], SWAY[id][1])
	if collide > 0:
		add_box_collider(n, 0.9 if collide == 1 else 0.6, L_SOLID)
	return n


## Models that move in the wind: [amplitude (fraction of height), speed]
const SWAY := {
	"T05_old_shade_tree": [.006,.75],
	"T01_courtyard_tree": [0.022, 0.9], "M12b_shrub": [0.05, 1.3], "M12d_flower_bush": [0.05, 1.15],
	"T02_summer_tree": [0.012, 0.65],
	"T03_round_ginkgo": [0.012, 0.60], "T04_slender_cedar": [0.009, 0.75],
	"A15_potted_plant": [0.035, 1.4], "A14_hydrangea_pot": [0.03, 1.2],
	"C01_seedling": [0.08, 1.9], "C02_radish": [0.07, 1.6], "C03_komatsuna": [0.06, 1.7], "C04_tomato": [0.05, 1.3],
	"C05_cucumber": [0.03, 1.2], "C06_edamame": [0.06, 1.5], "C07_sunflower": [0.045, 1.0], "C08_strawberry": [0.06, 1.8],
	"F04_scarecrow": [0.012, 0.8],
	"V01_fern": [.035,1.2],"V02_wildflowers": [.03,1.4],"V03_grass_clump": [.045,1.3],
	"V04_daisy_meadow": [.045,1.2],"V05_river_reeds": [.045,1.05],
	"C09_carrot": [.05,1.6],"C10_potato": [.05,1.4],"C11_eggplant": [.045,1.3],"C12_corn": [.035,1.0],
	"C13_pumpkin": [.03,1.1],"C14_watermelon": [.025,1.0],"C15_wheat": [.06,1.6],"C16_onion": [.05,1.4],
	"D11_reeds": [.045,1.15],"W04_sunflower_pot": [.035,1.2],"W05_hydrangea_pot": [.03,1.2],"W06_lily_vase": [.035,1.25],
}
static var _sway_cache := {}


## Swap the imported matte materials for the wind shader (shared per material + mesh height).
static func make_sway(root: Node3D, amp: float, speed: float) -> void:
	for mi in find_meshes(root):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var h := maxf(mesh.get_aabb().end.y, 0.05)
		var wind_id: String=str(root.get_meta("wind_model_id",root.get_meta("model_id","")))
		var anchored_height: float=h*.32 if wind_id in ["A14_hydrangea_pot","A15_potted_plant","W04_sunflower_pot","W05_hydrangea_pot","W06_lily_vase"] else 0.0
		for si in mesh.get_surface_count():
			var src := mi.get_surface_override_material(si)
			if src == null:
				src = mesh.surface_get_material(si)
			if not (src is StandardMaterial3D):
				continue
			var role: int=1 if mi.name.begins_with("Foliage") else (0 if mi.name.begins_with("Trunk") else 2)
			var key := "%d_%.3f_%.3f_%d" % [src.get_instance_id(), h, amp,role]
			var sm: ShaderMaterial = _sway_cache.get(key)
			if sm == null:
				var sd := src as StandardMaterial3D
				sm = ShaderMaterial.new()
				sm.shader = load("res://shaders/foliage_sway.gdshader")
				sm.set_shader_parameter("albedo_tex", sd.albedo_texture)
				sm.set_shader_parameter("has_texture",sd.albedo_texture!=null)
				sm.set_shader_parameter("albedo_color", sd.albedo_color)
				sm.set_shader_parameter("use_normal", sd.normal_enabled and sd.normal_texture != null)
				if sd.normal_texture:
					sm.set_shader_parameter("normal_tex", sd.normal_texture)
				sm.set_shader_parameter("roughness", clampf(sd.roughness, 0.6, 1.0))
				sm.set_shader_parameter("height", h)
				sm.set_shader_parameter("anchored_height",anchored_height)
				sm.set_shader_parameter("amp", amp)
				sm.set_shader_parameter("speed", speed)
				sm.set_shader_parameter("part_role",role)
				_sway_cache[key] = sm
			mi.set_surface_override_material(si, sm)


static func set_wind(weather: String) -> void:
	RenderingServer.global_shader_parameter_set("wind_strength", {"sunny": 1.0, "cloudy": 1.35, "rain": 2.1}.get(weather, 1.0))


static func find_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(find_meshes(c))
	return out


## Gate posts are separate blockers; the opening stays walkable.
static func add_gate_colliders(gate: Node3D) -> void:
	for post_index in GATE_POST_CENTERS.size():
		var body := StaticBody3D.new()
		body.name = "GatePostCollider_%d" % post_index
		body.position = GATE_POST_CENTERS[post_index]
		body.collision_layer = L_SOLID
		body.collision_mask = 0
		body.set_meta("model_part", "P_farm_gate")
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.55, 3.0, 0.34)
		shape.shape = box
		body.add_child(shape)
		gate.add_child(body)


static func local_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in find_meshes(root):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != root and p != null:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func add_box_collider(n: Node3D, shrink: float, layer: int) -> StaticBody3D:
	var box := local_aabb(n)
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(max(box.size.x * shrink, 0.25), box.size.y, max(box.size.z * shrink, 0.25))
	cs.shape = sh
	cs.position = box.get_center()
	body.add_child(cs)
	n.add_child(body)
	return body


static func ground_material(kind: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ground.gdshader")
	var painted: String = {"stone":"stone", "grass":"grass", "gravel":"sand", "sand":"sand"}.get(kind, "")
	m.set_shader_parameter("albedo_tex", load("res://assets/textures/town_detail/%s.png" % painted) if painted!="" else load("res://assets/textures/%s.jpg" % kind))
	m.set_shader_parameter("structured_texture", true)
	match kind:
		"stone":
			m.set_shader_parameter("tile", 4.0)
			m.set_shader_parameter("tint", Color(1.0, 0.99, 0.97))
			m.set_shader_parameter("surface_wear",.17)
			m.set_shader_parameter("wear_tex",load("res://assets/textures/lakeside_polish/creek_stone.png"))
		"gravel", "sand":
			m.set_shader_parameter("tile", 2.4)
			m.set_shader_parameter("tint", Color(0.97, 0.94, 0.9))
			if kind=="gravel":
				m.set_shader_parameter("surface_wear",.28)
				m.set_shader_parameter("wear_tex",load("res://assets/textures/lakeside_polish/path.png"))
		"grass":
			# v0.6: painted to match the blade grass (GrassField) instead of a photographed texture
			m.set_shader_parameter("lawn_mode", true)
			m.set_shader_parameter("tile", 2.8)
			m.set_shader_parameter("tint", Color(1, 1, 1))
			m.set_shader_parameter("feather", 0.35)
	return m


# ------------------------------------------------------------------ build
func build() -> void:
	for step in build_steps():
		step.call()


func build_async() -> void:
	var steps := build_steps()
	for i in steps.size():
		Loading.progress("布置晴町的街道", 0.7 + 0.25 * float(i) / float(steps.size()))
		await get_tree().process_frame
		steps[i].call()


func build_steps() -> Array[Callable]:
	var steps: Array[Callable] = [_build_environment, _build_ground, _build_walls]
	for b in Layout.BUILDINGS:
		steps.append(_spawn_building.bind(b))
	for p in Layout.PROPS:
		steps.append(spawn.bind(p[0], Vector3(p[1], 0, p[2]), p[3], p[4]))
	for t in Layout.PLANTS:
		steps.append(_spawn_plant.bind(t))
	steps.append(_build_residential)
	steps.append_array([_build_planter, _build_mg_stations, _build_stall_extras, _build_board_poster, _build_lamps, _build_build_sign, _build_backdrop, _build_house, _build_farm, _build_town_v05, _build_festivals, _build_detail_signs, set_region.bind("town")])
	return steps


func _build_residential() -> void:
	ResidentialLife.build(self)
	bus=TownBus.new();add_child(bus);bus.build(self)

func _build_detail_signs() -> void:
	var clock_model:=get_node_or_null("R11") as Node3D
	if clock_model:
		clock_face=VillageClock.new();clock_face.build(clock_model)
	TransitStop.build(self)
	set_meta("clear_sign_count",ClearSignage.upgrade_existing(self))

func _spawn_building(spec: Array) -> void:
	var building := spawn(spec[0], Vector3(spec[1], 0, spec[2]), spec[3], spec[4])
	if building:
		if float(spec[2])>32:building.name="SouthHome_%d_%d"%[int(spec[1]),int(spec[2])]
		window_mats.append_array(ShopWindows.add(building, spec[0], self))
		building_life.append(BuildingLife.add(building, spec[0]))


func _spawn_plant(spec: Array) -> void:
	var tree := spawn(spec[0], Vector3(spec[1], 0, spec[2]), spec[3], 0, null, spec[4])
	if tree:
		if str(spec[0]).begins_with("T"):
			rest_on_terrain(tree,-0.03 if float(spec[2]) < -25.2 else .008)
		var radius: float = {"T05_old_shade_tree": 1.05, "T01_courtyard_tree": 0.5, "M12d_flower_bush": 0.5, "M12b_shrub": 0.4}.get(spec[0], 0.35)
		_trunk_collider(tree, radius)


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky_blend.gdshader")
	sky_mat.set_shader_parameter("sky_day", load("res://assets/textures/sky_equirect.jpg"))
	sky_mat.set_shader_parameter("sky_dusk", load("res://assets/textures/sky_dusk.jpg"))
	sky_mat.set_shader_parameter("sky_night", load("res://assets/textures/sky_night.jpg"))
	sky_mat.set_shader_parameter("cloud_tex",load("res://assets/textures/bg/cloud_0.png"))
	sky_mat.set_shader_parameter("cloud_tex_second",load("res://assets/textures/bg/cloud_1.png"))
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = .84
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.46
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.84, 0.95)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.35
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.03
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 125.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.rotation_degrees = Vector3(-48, -35, 0)
	add_child(sun)


func _plane(rect: Array, mat: Material, y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(rect[2] - rect[0], rect[3] - rect[1])
	mi.mesh = pm
	mi.material_override = mat
	mi.set_instance_shader_parameter("plane_size", pm.size)
	mi.position = Vector3((rect[0] + rect[2]) / 2.0, y, (rect[1] + rect[3]) / 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_ground() -> void:
	var mats := {}
	var i := 0
	for g in Layout.GROUND:
		if not mats.has(g[0]):
			mats[g[0]] = ground_material(g[0])
		# later patches sit a hair higher so overlaps never z-fight
		_plane([g[1], g[2], g[3], g[4]], mats[g[0]], 0.002 * i)
		i += 1
	# curbs between street and sidewalks (visual only)
	var curb := StandardMaterial3D.new()
	curb.albedo_color = Color(0.74, 0.73, 0.7)
	curb.roughness = 1.0
	for z in [Layout.STREET_Z - Layout.STREET_HALF, Layout.STREET_Z + Layout.STREET_HALF]:
		var c := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(94.9, 0.06, 0.22)
		c.mesh = bm
		c.material_override = curb
		c.position = Vector3(-4.75, 0.03, z)
		add_child(c)
	# painted street centre line fragments
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.93, 0.9, 0.82)
	paint.roughness = 1.0
	for x in range(-49, 41, 6):
		var d := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.6, 0.14)
		d.mesh = pm
		d.material_override = paint
		d.position = Vector3(x, 0.02, Layout.STREET_Z)
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(d)
	# far ground that runs under the backdrop
	var far := StandardMaterial3D.new()
	far.albedo_color = Color(0.56, 0.62, 0.42)
	far.roughness = 1.0
	# stops short of the house lot (Layout.ROOM_ORIGIN, z = 400), which has its own garden ground,
	# and leaves a hole where the lane down to the allotment cuts into the slope (_build_town_exit)
	var c: Rect2 = EXIT_CUT
	_plane([-400.0, -400.0, 400.0, c.position.y], far, -0.03)
	_plane([-400.0, c.end.y, 400.0, 360.0], far, -0.03)
	_plane([-400.0, c.position.y, c.position.x, c.end.y], far, -0.03)
	_plane([c.end.x, c.position.y, 400.0, c.end.y], far, -0.03)
	# floor collider around the same hole; the lane mesh brings its own collider for the hole
	var body := StaticBody3D.new()
	body.collision_layer = L_GROUND
	for r in [[-200.0, -200.0, 200.0, c.position.y], [-200.0, c.end.y, 200.0, 200.0],
			[-200.0, c.position.y, c.position.x, c.end.y], [c.end.x, c.position.y, 200.0, c.end.y]]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(r[2] - r[0], 1, r[3] - r[1])
		cs.shape = sh
		cs.position = Vector3((r[0] + r[2]) / 2.0, -0.5, (r[1] + r[3]) / 2.0)
		body.add_child(cs)
	add_child(body)


func _build_walls() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/blockwall.gdshader")
	for i in Layout.WALLS.size():
		var w: Array = Layout.WALLS[i]
		var a := Vector3(w[0], 0, w[1])
		var b := Vector3(w[2], 0, w[3])
		var h: float = w[4]
		var wall_mat := mat.duplicate() as ShaderMaterial
		wall_mat.set_shader_parameter("plaster", true)
		var wall := add_wall(a, b, h, wall_mat, self)
		wall.name = "BoundaryWall_%d" % i
		JapaneseArchitecture.courtyard_coping(wall, a.distance_to(b), h)


static func add_wall(a: Vector3, b: Vector3, h: float, mat: Material, parent: Node, thick: float = 0.18) -> MeshInstance3D:
	var len := a.distance_to(b)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(len + thick, h, thick)
	mi.mesh = bm
	mi.material_override = mat
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("wall_top", h)
	mi.position = (a + b) / 2.0 + Vector3(0, h / 2.0, 0)
	mi.rotation.y = -atan2(b.z - a.z, b.x - a.x)
	parent.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = L_SOLID
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(len + thick, max(h, 1.2), thick + 0.1)
	cs.shape = sh
	cs.position.y = (max(h, 1.2) - h) / 2.0
	body.add_child(cs)
	mi.add_child(body)
	return mi


func _trunk_collider(tree: Node3D, r: float) -> void:
	var body := StaticBody3D.new()
	body.name = "TrunkCollision"
	body.set_meta("model_part", tree.get_meta("model_id", "tree"))
	body.collision_layer = L_SOLID
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = 2.0
	cs.shape = sh
	cs.position.y = 1.0
	body.add_child(cs)
	tree.add_child(body)


# ------------------------------------------------------------------ quest-reactive props
func _build_planter() -> void:
	var root := Node3D.new()
	root.name = "Planter"
	root.position = Layout.PLANTER_POS
	root.rotation.y = deg_to_rad(Layout.PLANTER_YAW)
	add_child(root)
	var box := spawn("H12a_box", Vector3.ZERO, 0, 0, root)
	if box:
		add_box_collider(box, 0.95, L_SOLID)
		for mi in find_meshes(box):
			var m: Mesh = mi.mesh
			for s in m.get_surface_count():
				var sm := m.surface_get_material(s)
				if sm and sm.resource_name == "M_soil":
					planter_soil_mat = ShaderMaterial.new()
					planter_soil_mat.shader = load("res://shaders/ground.gdshader")
					planter_soil_mat.set_shader_parameter("albedo_tex", load("res://assets/textures/gravel.jpg"))
					planter_soil_mat.set_shader_parameter("tint", Color(0.42, 0.3, 0.22))
					planter_soil_mat.set_shader_parameter("tile", 0.8)
					mi.set_surface_override_material(s, planter_soil_mat)
	# plants grow from the soil line, so scale them around a pivot at soil height
	var pivot := Node3D.new()
	pivot.name = "PlantPivot"
	pivot.position.y = 0.32
	root.add_child(pivot)
	var plants := spawn("H12a_plants", Vector3(0, -0.32, 0), 0, 0, pivot)
	planter_plants = pivot
	tomatoes = Node3D.new()
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.9, 0.16, 0.1)
	red.roughness = 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 11:
		var s := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.03
		sp.height = 0.06
		s.mesh = sp
		s.material_override = red
		s.position = Vector3(rng.randf_range(-0.05, 0.42), rng.randf_range(0.2, 0.45), rng.randf_range(-0.12, 0.12))
		tomatoes.add_child(s)
	pivot.add_child(tomatoes)
	if plants == null:
		pivot.visible = false
	# after Q03 the planter becomes an ordinary plot ("court") with the same crops as the farm
	court_plot = PlotView.new()
	root.add_child(court_plot)
	court_plot.setup(self, "court", false, 0.95, 0.32, Vector2(1.45, 0.62))
	set_crop_stage(0, false)


var court_plot: PlotView

## The Q03 story planter shows its own tomato growth until the plot opens, then the plot view takes over.
func sync_court() -> void:
	var open: bool = GameState.plots.get("court", {}).get("open", false)
	if court_plot:
		court_plot.visible = open
		if open:
			court_plot.refresh()
	if planter_plants and open:
		planter_plants.visible = false
		tomatoes.visible = false


func set_crop_stage(stage: int, animate: bool = true) -> void:
	if planter_plants == null:
		return
	if GameState.plots.get("court", {}).get("open", false):
		sync_court()
		return
	var sc: float = [0.001, 0.12, 0.45, 1.0][clampi(stage, 0, 3)]
	planter_plants.visible = stage > 0
	tomatoes.visible = stage >= 3
	if animate and is_inside_tree():
		var tw := create_tween()
		tw.tween_property(planter_plants, "scale", Vector3(1, sc, 1) if stage < 3 else Vector3.ONE, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		planter_plants.scale = Vector3(1, sc, 1) if stage < 3 else Vector3.ONE


func water_soil() -> void:
	if planter_soil_mat == null:
		return
	var tw := create_tween()
	tw.tween_method(func(v): planter_soil_mat.set_shader_parameter("wet", v), 0.0, 0.8, 0.6)
	tw.tween_interval(6.0)
	tw.tween_method(func(v): planter_soil_mat.set_shader_parameter("wet", v), 0.8, 0.25, 8.0)


func splash_at(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, -6, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.35, 0.02, 0.18)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	p.process_material = pm
	var drop := SphereMesh.new()
	drop.radius = 0.012
	drop.height = 0.05
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.7, 0.85, 1.0, 0.8)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = dm
	p.draw_pass_1 = drop
	p.amount = 90
	p.lifetime = 0.45
	p.one_shot = false
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(func():
		p.emitting = false
		get_tree().create_timer(1.0).timeout.connect(p.queue_free))


func _build_stall_extras() -> void:
	# bread basket that appears after Q02 (procedural: wicker bowl + loaves)
	stall_bread = Node3D.new()
	stall_bread.name = "StallBread"
	# The basket belongs on the actual empty counter, including its full perimeter.
	# Generated models can change their deck height; never keep the old .525 m datum.
	var counter: Node3D=get_node_or_null("P09")
	if counter!=null:
		var candidate:=Vector3(counter.global_position.x-.6,0,counter.global_position.z)
		candidate.y=rendered_support_height(counter,candidate,1.35,true)
		var supported: bool=is_finite(candidate.y) and candidate.y>.4
		for index: int in 8:
			var angle: float=TAU*index/8.0
			var offset:=Vector3(cos(angle)*.26,0,sin(angle)*.26)
			var height: float=rendered_support_height(counter,candidate+offset,1.35,true)
			if not is_finite(height) or absf(height-candidate.y)>.02:supported=false
		if supported:stall_bread_surface=candidate
	stall_bread.position=stall_bread_surface+Vector3.UP*.06 if stall_bread_surface.is_finite() else Vector3(1.4,.585,15.1)
	var wicker := StandardMaterial3D.new()
	wicker.albedo_color = Color(0.72, 0.52, 0.3)
	wicker.roughness = 1.0
	var bowl := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.26
	cyl.bottom_radius = 0.2
	cyl.height = 0.12
	bowl.mesh = cyl
	bowl.material_override = wicker
	stall_bread.add_child(bowl)
	var crust := StandardMaterial3D.new()
	crust.albedo_color = Color(0.86, 0.58, 0.26)
	crust.roughness = 0.8
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 7:
		var b := MeshInstance3D.new()
		b.name = "BreadRoll_%d" % i
		var sp := SphereMesh.new()
		sp.radius = 0.075
		sp.height = 0.1
		b.mesh = sp
		b.material_override = crust
		var a := TAU * i / 7.0
		b.position = Vector3(cos(a) * 0.14, 0.09, sin(a) * 0.1) if i < 6 else Vector3(0, 0.13, 0)
		b.scale = Vector3(1.3, 1.0, 1.0)
		b.rotation.y = rng.randf() * TAU
		stall_bread.add_child(b)
	stall_bread.visible = false
	add_child(stall_bread)
	var samples := Node3D.new()
	samples.name = "BakerySandwiches"
	stall_bread.add_child(samples)
	for i in 3:
		var sandwich := Node3D.new()
		sandwich.name = "Sandwich_%d" % i
		sandwich.position = Vector3(-0.12 + i * 0.12, 0.14, 0.04)
		samples.add_child(sandwich)
		for layer in 4:
			var piece := MeshInstance3D.new()
			piece.name = "Layer_%d" % layer
			var bread_mesh := BoxMesh.new()
			bread_mesh.size = Vector3(0.13, 0.025, 0.13)
			piece.mesh = bread_mesh
			piece.position.y = layer * 0.027
			var bread_mat := StandardMaterial3D.new()
			bread_mat.albedo_color = [Color(0.93, 0.76, 0.48), Color(0.32, 0.61, 0.29), Color(0.86, 0.31, 0.23), Color(0.98, 0.87, 0.64)][layer]
			piece.material_override = bread_mat
			sandwich.add_child(piece)
	bakery_market_sign = Label3D.new()
	bakery_market_sign.name = "BakeryMarketMenu"
	bakery_market_sign.font = load("res://assets/fonts/LXGWWenKai-Medium.ttf")
	bakery_market_sign.font_size = 48
	bakery_market_sign.pixel_size = 0.0015
	bakery_market_sign.position = Vector3(0.0, 0.48, -0.024)
	bakery_market_sign.rotation.y = PI
	bakery_market_sign.modulate = Color(0.3, 0.18, 0.11)
	bakery_market_sign.outline_size = 0
	var paper_board := MeshInstance3D.new()
	paper_board.name = "BakeryMarketPaper"
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(0.8, 0.34, 0.035)
	paper_board.mesh = board_mesh
	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_color = Color(1.0, 0.95, 0.8)
	paper_board.material_override = paper_mat
	paper_board.position = Vector3(0, 0.48, 0)
	stall_bread.add_child(paper_board)
	var post := MeshInstance3D.new()
	post.name = "BakeryMarketPost"
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.025, 0.3, 0.025)
	post.mesh = post_mesh
	post.material_override = wicker
	post.position = Vector3(0, 0.2, 0)
	stall_bread.add_child(post)
	stall_bread.add_child(bakery_market_sign)
	GameState.state_changed.connect(sync_bakery_menu)
	sync_bakery_menu()


func sync_bakery_menu() -> void:
	if bakery_market_sign == null:
		return
	var G := GameState
	bakery_market_sign.visible = G.flags.get("bakery_first_served", false)
	var samples: Node3D = stall_bread.get_node("BakerySandwiches")
	samples.visible = bakery_market_sign.visible
	var fresh := int(G.flags.get("bakery_menu", 0)) == 1
	for i in 3:
		samples.get_child(i).visible = fresh or i < 1
	for child in stall_bread.get_children():
		if str(child.name).begins_with("BreadRoll_"):
			child.visible = not bakery_market_sign.visible or not fresh or str(child.name).trim_prefix("BreadRoll_").to_int() < 3
	stall_bread.get_node("BakeryMarketPaper").visible = bakery_market_sign.visible
	stall_bread.get_node("BakeryMarketPost").visible = bakery_market_sign.visible
	bakery_market_sign.text = "菠萝包\n三明治少量试吃" if int(G.flags.get("bakery_menu", 0)) == 0 else "街坊三明治\n菠萝包也留着"


func _build_board_poster() -> void:
	poster = Node3D.new()
	poster.name = "Poster"
	# notice board faces north (-Z); the poster sits just in front of its panel
	poster.position = Vector3(-8.1, 1.45, -5.16)
	poster.rotation.y = PI
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.62, 0.85)
	q.mesh = qm
	var pm := StandardMaterial3D.new()
	var tex_path := "res://assets/ui/poster.png"
	if ResourceLoader.exists(tex_path):
		pm.albedo_texture = load(tex_path)
	else:
		pm.albedo_color = Color(1.0, 0.93, 0.78)
	pm.roughness = 1.0
	q.material_override = pm
	poster.add_child(q)
	var lbl := Label3D.new()
	lbl.text = "周末小集市\n庭院 · 周六傍晚"
	lbl.font_size = 48
	lbl.pixel_size = 0.0028
	lbl.modulate = Color(0.35, 0.18, 0.1)
	lbl.outline_size = 0
	lbl.position = Vector3(0, -0.28, 0.004)
	lbl.double_sided = false
	poster.add_child(lbl)
	poster.visible = false
	add_child(poster)


func _build_lamps() -> void:
	for p in Layout.PROPS:
		if p[0] == "R08a":
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.78, 0.5)
			l.light_energy = 0.0
			l.omni_range = 7.0
			l.shadow_enabled = false
			l.position = Vector3(p[1], 3.9, p[2])
			add_child(l)
			lamp_lights.append(l)


func _build_build_sign() -> void:
	var root := Node3D.new()
	root.name = "BuildSign"
	root.position = Layout.BUILD_SIGN_POS
	add_child(root)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.38, 0.24)
	wood.roughness = 0.9
	# posts stand just outside the board's edges so they never cover the lettering
	for x in [-0.6, 0.6]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.08, 1.4, 0.08)
		post.mesh = pb
		post.material_override = wood
		post.position = Vector3(x, 0.65, 0)
		root.add_child(post)
	var board := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.1, 0.62, 0.05)
	board.mesh = bb
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.97, 0.93, 0.82)
	board.material_override = bm
	board.position = Vector3(0, 1.05, 0)
	root.add_child(board)
	for side in [-1.0, 1.0]:
		var lbl := Label3D.new()
		lbl.text = "集市布置区\n桌椅 · 装饰"
		lbl.font_size = 44
		lbl.pixel_size = 0.0036
		lbl.line_spacing = 6
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.modulate = Color(0.36, 0.22, 0.12)
		lbl.outline_size = 0
		lbl.double_sided = false
		lbl.position = Vector3(0, 1.05, 0.03 * side)
		lbl.rotation.y = 0.0 if side > 0.0 else PI
		root.add_child(lbl)
	var body := StaticBody3D.new()
	body.collision_layer = L_SOLID
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.0, 1.3, 0.15)
	cs.shape = sh
	cs.position.y = 0.65
	body.add_child(cs)
	root.add_child(body)


# ------------------------------------------------------------------ mini-game stations
var goldfish_tank: Node3D
var taiko_drum: Node3D

func _build_mg_stations() -> void:
	goldfish_tank = spawn("G02_goldfish_tank", Layout.GOLDFISH_POS, 90.0, 1)
	taiko_drum = spawn("G09_taiko", Layout.TAIKO_POS, 90.0, 1)


# ------------------------------------------------------------------ backdrop
func _card(tex_name: String, center: Vector3, width: float, face_yaw_deg: float, haze: float = 0.15, y_base: float = 0.0, parent: Node = null) -> MeshInstance3D:
	var tex: Texture2D = load("res://assets/textures/bg/%s.png" % tex_name)
	var h := width * tex.get_height() / float(tex.get_width())
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(width, h)
	mi.mesh = qm
	mi.set_meta("backdrop_tex", tex_name)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/card.gdshader")
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("haze_amount", haze)
	mi.material_override = m
	card_mats.append(m)
	mi.position = center + Vector3(0, y_base + h / 2.0, 0)
	mi.rotation.y = deg_to_rad(face_yaw_deg)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi


func _build_backdrop() -> void:
	# north: ridge, near hills, hillside houses, pagoda, roofline
	_card("bg_far_ridge", Vector3(0, 0, -330), 900.0, 0, 0.35, -8.0)
	_card("bg_near_hills", Vector3(-20, 0, -240), 700.0, 0, 0.25, -6.0)
	_card("bg_hill_houses", Vector3(95, 0, -170), 90.0, -20, 0.2, -4.0)
	_card("bg_pagoda_card", Vector3(-55, 0, -150), 48.0, 15, 0.12, -2.0)
	_card("bg_roofline", Vector3(0, 0, -62), 170.0, 0, 0.1, -1.0)
	# south / east / west hills so every camera angle has a horizon
	_card("bg_near_hills", Vector3(0, 0, 230), 700.0, 180, 0.28, -6.0)
	_card("bg_near_hills", Vector3(240, 0, 0), 700.0, -90, 0.28, -6.0)
	_card("bg_near_hills", Vector3(-240, 0, 0), 700.0, 90, 0.28, -6.0)
	_card("bg_roofline", Vector3(0, 0, 128), 170.0, 180, 0.1, -1.0)
	_card("bg_roofline", Vector3(96, 0, 32), 180.0, -90, 0.1, -1.0)
	_card("bg_roofline", Vector3(-85, 0, 0), 150.0, 90, 0.1, -1.0)
	# Actual model trees beside the boundary walls; distant hills remain painted scenery.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var ring := [
		[Vector3(-58, 0, -31), Vector3(48, 0, -31), 0.0], [Vector3(-58, 0, -28), Vector3(-58, 0, 12), 90.0],
		[Vector3(48, 0, -28), Vector3(48, 0, 89), -90.0], [Vector3(-56, 0, 13), Vector3(-15, 0, 13), 180.0],
		[Vector3(-5, 0, 92), Vector3(46, 0, 92), 180.0],
	]
	for seg in ring:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var n := int(a.distance_to(b) / 9.0)
		for i in n:
			var t := (i + rng.randf_range(0.1, 0.9)) / float(n)
			var p := a.lerp(b, t)
			var tree_scale := rng.randf_range(.95, 1.38)
			var yaw := rng.randf_range(-180.0, 180.0)
			if (p.x < -53 and p.z > -17 and p.z < -5) or EXIT_CUT.grow(1.0).has_point(Vector2(p.x, p.z)):
				continue
			var tree_id: String = NEAR_TREES[(i + int(seg[2] / 90.0) + NEAR_TREES.size()) % NEAR_TREES.size()]
			var tree := spawn(tree_id, p, yaw, 0, self, tree_scale)
			if tree:
				tree.set_meta("near_background_tree", true)
				rest_on_terrain(tree,-.03)


# ------------------------------------------------------------------ v0.5 town dressing
func _sign_label(text: String, pos: Vector3, yaw: float, size: int = 28) -> void:
	for side in [0.0, PI]:
		var l := Label3D.new()
		l.text = text
		l.font_size = size
		l.pixel_size = 0.0036
		l.modulate = Color(0.3, 0.2, 0.12)
		l.outline_size = 0
		l.double_sided = false
		l.position = pos + Vector3(sin(yaw + side), 0, cos(yaw + side)) * 0.035
		l.rotation.y = yaw + side
		add_child(l)


# ------------------------------------------------------------------ v0.6: the lane down to the allotment
## The east end of the street opens under the same lantern gate that stands at the farm's entrance, and a
## gravel lane drops away between grass banks into the trees. The farm side has the matching climb
## (FarmBuilder._lane_up), so leaving and coming back read as one road.
const EXIT_CUT := Rect2(42.7, -19.0, 21.3, 16.0)     # x 42.7..64, z -19..-3: where the far ground is cut away
const EXIT_GATE := Vector3(43.7, 0, -11.0)


## Sunken (h < 0) or raised (h > 0) lane along +X. The path is 2 * half_path wide at height h(x); grass banks
## run from its edges to the flat ground at |z - zc| = bank. h(x) eases from h_a (x <= xa) to h_b (x >= xb).
## cap_end closes the far end of a cut with a grass face turned back toward -X.
static func lane(parent: Node3D, x0: float, x1: float, zc: float, half_path: float, bank: float,
		xa: float, xb: float, h_a: float, h_b: float, path_mat: Material, bank_mat: Material, cap_end: bool) -> MeshInstance3D:
	var steps := maxi(2, int((x1 - x0) / 0.6))
	var zs: Array[float] = [zc - bank, zc - half_path, zc + half_path, zc + bank]
	var sts: Array[SurfaceTool] = [SurfaceTool.new(), SurfaceTool.new()]
	for st in sts:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pt := func(x: float, k: int) -> Vector3:
		var h := lerpf(h_a, h_b, smoothstep(xa, xb, x)) if k == 1 or k == 2 else 0.0
		return Vector3(x, h, zs[k])
	for i in steps:
		var xl := lerpf(x0, x1, i / float(steps))
		var xr := lerpf(x0, x1, (i + 1) / float(steps))
		for k in 3:
			var st: SurfaceTool = sts[0] if k == 1 else sts[1]
			var p00: Vector3 = pt.call(xl, k)
			var p10: Vector3 = pt.call(xr, k)
			var p01: Vector3 = pt.call(xl, k + 1)
			var p11: Vector3 = pt.call(xr, k + 1)
			_tri(st, p00, p10, p01)
			_tri(st, p10, p11, p01)
	if cap_end:
		var t1 := Vector3(x1, 0, zs[0])
		var t2 := Vector3(x1, 0, zs[3])
		_tri(sts[1], t1, t2, pt.call(x1, 2))
		_tri(sts[1], t1, pt.call(x1, 2), pt.call(x1, 1))
	var mesh := sts[0].commit()
	sts[1].commit(mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, path_mat)
	mi.set_surface_override_material(1, bank_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Lane"
	parent.add_child(mi)
	# scenery only (the player is kept out), but props on the banks are checked against it
	var gb := StaticBody3D.new()
	gb.collision_layer = L_GROUND
	gb.collision_mask = 0
	var gcs := CollisionShape3D.new()
	gcs.shape = mesh.create_trimesh_shape()
	gb.add_child(gcs)
	mi.add_child(gb)
	return mi


## Height of a lane's bank at `off` metres from its centre line: flat path, then a straight
## slope back up (or down) to the surrounding ground at `bank`.
static func lane_side_y(h: float, off: float, half_path: float, bank: float) -> float:
	var o := absf(off)
	if o <= half_path:
		return h
	return h * clampf((bank - o) / (bank - half_path), 0.0, 1.0)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot front faces wind clockwise; (c - a) x (b - a) is then the outward normal
	var n := (c - a).cross(b - a).normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)


static func lane_depth(x: float) -> float:
	return lerpf(0.0, -3.4, smoothstep(45.6, 63.0, x))


func _build_town_exit() -> void:
	var path := ground_material("gravel")
	path.set_shader_parameter("tint", Color(0.95, 0.9, 0.82))
	var bank := ground_material("grass")
	bank.set_shader_parameter("feather", 0.0)   # match FarmBuilder._lane_up so both ends of the lane read the same
	var c: Rect2 = EXIT_CUT
	lane(self, c.position.x, c.end.x, Layout.STREET_Z, 1.3, c.size.y / 2.0, 45.6, 63.0, 0.0, -3.4, path, bank, true)
	# gravel apron where the stone street gives way to the lane
	_plane([42.7, Layout.STREET_Z - 2.2, 45.6, Layout.STREET_Z + 2.2], path, 0.004)
	# the same lantern gate as the farm's, so the two ends match
	var gate := spawn("P_farm_gate", EXIT_GATE, 90.0, 0, self, 1.0)
	if gate:
		add_gate_colliders(gate)
	for side in [0.0, PI]:
		var l := Label3D.new()
		l.text = "河边农园" if side == 0.0 else "晴町 石板主街"
		l.name = "GateTitle_town_%d" % int(side * 100.0)
		l.font_size = 34
		l.pixel_size = 0.0036
		l.modulate = Color(0.3, 0.2, 0.12)
		l.double_sided = false
		l.rotation.y = -PI / 2.0 + side
		l.position = EXIT_GATE + Vector3(0, GATE_TITLE_Y, 0) + Vector3(sin(l.rotation.y), 0, cos(l.rotation.y)) * 0.065
		add_child(l)
	for z in [-1.5, 1.5]:
		var ol := OmniLight3D.new()
		ol.position = EXIT_GATE + Vector3(0, 2.0, z)
		ol.omni_range = 5.0
		ol.light_color = Color(1.0, 0.55, 0.4)
		ol.light_energy = 0.0
		add_child(ol)
		lamp_lights.append(ol)
	# player-only keep-out just past the gate: the lane is scenery, [E] under the gate takes you down
	_block(Vector3(0.4, 3.0, 12.0), Vector3(46.4, 1.5, Layout.STREET_Z), L_BLOCK)
	_block(Vector3(3.8, 3.0, 0.4), Vector3(44.6, 1.5, Layout.STREET_Z - 3.5), L_BLOCK)
	_block(Vector3(3.8, 3.0, 0.4), Vector3(44.6, 1.5, Layout.STREET_Z + 3.5), L_BLOCK)
	# the lane runs down into the trees; a few stand on the banks
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	for t in [[63.2, 0.0, 15.0], [61.0, -6.0, 12.0], [61.4, 5.4, 12.0], [55.0, -7.4, 9.0], [56.5, 6.8, 9.5], [50.0, -7.8, 7.0], [49.4, 7.6, 7.5]]:
		var x: float = t[0]
		var z: float = Layout.STREET_Z + t[1]
		var off := absf(t[1]) / (c.size.y / 2.0)
		var y := lane_depth(x) * clampf(1.0 - (off - 0.16) / 0.84, 0.0, 1.0)
		var lane_tree := spawn(NEAR_TREES[rng.randi() % NEAR_TREES.size()], Vector3(x, y, z), rng.randf_range(-180.0,180.0), 0, self, clampf(float(t[2])/10.0,.78,1.28))
		if lane_tree:
			lane_tree.set_meta("near_background_tree", true)
			rest_on_terrain(lane_tree,y)
	for x in [47.6, 52.4]:
		spawn("P_toro", Vector3(x, lane_side_y(lane_depth(x), 2.0, 1.3, c.size.y / 2.0), Layout.STREET_Z - 2.0), 90.0, 0, self, 0.8)


func _block(size: Vector3, pos: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.position = pos
	body.add_child(cs)
	add_child(body)
	return body


func _build_town_v05() -> void:
	_build_nature_accents()
	_build_town_exit()
	# signpost at the east end: the way down to the allotment
	_sign_label("河边农园 →", Vector3(40.6, 2.0, -7.2), 0.0, 28)
	_sign_label("← 公交站", Vector3(39.4, 1.6, -7.2), 0.0, 28)
	_sign_label("住宅支巷 ↗", Vector3(40.54, 1.2, -7.45), deg_to_rad(-25.0), 24)
	var down := Label3D.new()
	down.text = "河边农园 →"
	down.font_size = 64
	down.pixel_size = 0.006
	down.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	down.modulate = Color(1.0, 0.97, 0.88)
	down.outline_size = 16
	down.outline_modulate = Color(0.32, 0.2, 0.12, 0.9)
	down.position = EXIT_GATE + Vector3(0, 4.0, 0)
	down.visibility_range_end = 60.0
	add_child(down)
	# S01 now owns its measured timber name board and lettering in the GLB.
	var g := GrassField.new()
	g.name = "TownGrass"
	add_child(g)
	var n := 0
	var fl := 0
	for lw in Layout.LAWNS:
		n += g.lawn([lw[0]], lw[1], "lawn", 6.0, 3 + n)
		fl += g.scatter([lw[0]], 0.1, lw[1], GrassField.MIX_FLOWERS, Vector2(0.2, 0.34), 5 + fl)
	# meadow blades on the flat crest of the exit-lane bank (EXIT_CUT), same style as the farm side's
	# FarmBuilder._lane_up, so the two ends of the lane match instead of the town side reading as a bare
	# painted hill. Only the crest is safe: the lane() bank mesh only holds height 0 near x<=45.6 and at
	# the outer edges z<=-17 / z>=-5, everywhere else it slopes down into the cut.
	var gate_apron := [Vector2(EXIT_GATE.x, EXIT_GATE.z), 3.4]
	var lane_crest := [[42.7, -19.0, 45.6, -3.0], [42.7, -19.0, 64.0, -17.0], [42.7, -5.0, 64.0, -3.0]]
	n += g.lawn(lane_crest, [gate_apron], "meadow", 5.0, 30)
	fl += g.scatter(lane_crest, 0.3, [gate_apron], GrassField.MIX_FLOWERS, Vector2(0.24, 0.42), 31)
	# weeds along the foot of the courtyard walls and the lane walls
	var walls := [[-13.0, -5.2, -12.4, 9.8], [-13.0, 23.6, 17.0, 24.1], [16.6, -5.2, 17.1, 6.8], [16.6, 10.2, 17.1, 18.0],
			[17.3, 10.0, 17.8, 30.0], [21.6, -5.0, 22.1, 0.8]]
	var gaps := [[Vector2(-2.0, 23.3), 1.4], [Vector2(3.4, 23.3), 1.4], [Vector2(9.0, 22.9), 1.2]]
	n += g.lawn(walls, gaps, "tall", 3.0, 21)
	fl += g.scatter(walls, 0.5, gaps, GrassField.MIX_FLOWERS, Vector2(0.22, 0.4), 22)
	var avoid: Array = [[17.0,32.0,22.4,86.0],[-4.0,49.6,43.0,53.0],[-4.0,66.6,43.0,70.0]]
	for home: Array in Layout.BUILDINGS:
		if float(home[2])>32:
			avoid.append([float(home[1])-6.2,float(home[2])-5.2,float(home[1])+6.2,float(home[2])+5.2])
	var south_count:=g.lawn([[-3.0,33.0,42.0,84.0]],avoid,"lawn",6.0,610)
	set_meta("south_grass_clumps",south_count)
	n+=south_count
	print("GRASS town clumps ", n, " flowers ", fl)


func _build_nature_accents() -> void:
	var count:=0
	for entry: Array in [["V01_fern",-11.7,11.7],["V01_fern",-10.8,20.5],["V01_fern",15.9,19.9],
		["V02_wildflowers",-9.4,19.3],["V02_wildflowers",-7.7,22.5],["V02_wildflowers",13.4,21.8],
		["V03_grass_clump",-12.4,13.0],["V03_grass_clump",-12.1,18.9],["V03_grass_clump",15.8,20.8],
		["V01_fern",-1.0,54.0],["V02_wildflowers",25.5,51.5],["V03_grass_clump",37.5,63.0]]:
		var plant:=spawn(str(entry[0]),Vector3(float(entry[1]),0,float(entry[2])),count*47,0)
		if plant:plant.name="NatureAccent_%d"%count;rest_on_terrain(plant,.01,.004);count+=1
	set_meta("nature_accent_count",count)
	var shade:=ground_material("stone");shade.set_shader_parameter("feather",.7)
	var paving:=_plane([.3,3.3,7.7,10.7],shade,.065);paving.name="OldTreeShadePaving"
	var paving_body:=StaticBody3D.new();paving_body.name="PavingSupport";paving_body.collision_layer=L_GROUND
	paving_body.set_meta("model_part","OldTreeShadePaving")
	var paving_shape:=CollisionShape3D.new();var paving_box:=BoxShape3D.new()
	paving_box.size=Vector3(7.4,.065,7.4);paving_shape.shape=paving_box;paving_shape.position.y=-.0325
	paving_body.add_child(paving_shape);paving.add_child(paving_body)
	var old_tree:=get_node_or_null("T05_old_shade_tree") as Node3D
	if old_tree:rest_on(old_tree,.065,.012)
	for index in 2:
		var seat:=spawn("A12_bench",Vector3(.75 if index==0 else 7.25,.065,8.1),90 if index==0 else -90,0)
		if seat:seat.name="OldTreeSeat_%d"%index;rest_on(seat,.065)


# ------------------------------------------------------------------ festival decorations
var fest_nodes := {}
var tanzaku_root: Node3D
var contest_root: Node3D
var offering: Node3D
var moon: MeshInstance3D
const TANABATA_BAMBOO := [Vector3(-4.4, 0, -3.2), Vector3(2.2, 0, -3.3)]
const YAGURA_POS := Vector3(-2.6, 0, 18.8)
const CONTEST_TABLE := Vector3(-6.2, 0, 8.9)

func _fest_root(fid: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Fest_" + fid
	n.visible = false
	add_child(n)
	fest_nodes[fid] = n
	return n


func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.6
	m.roughness = 0.8
	return m


## A sagging string of paper lanterns between two points, with one light in the middle.
## v0.6: real chochin (P_chochin_red 祭 / P_chochin_white 晴, alternating) that sway in the wind.
func lantern_string(a: Vector3, b: Vector3, n: int, parent: Node3D) -> void:
	var cord := StandardMaterial3D.new()
	cord.albedo_color = Color(0.2, 0.18, 0.16)
	var sag := a.distance_to(b) * 0.1
	var pts: Array[Vector3] = []
	for i in n + 1:
		var t := float(i) / n
		pts.append(a.lerp(b, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0))
	var scenes := [model_scene("P_chochin_red"), model_scene("P_chochin_white")]
	var face := atan2(b.x - a.x, b.z - a.z) - PI / 2.0
	for i in n:
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.012
		cm.height = pts[i].distance_to(pts[i + 1])
		cm.radial_segments = 4
		seg.mesh = cm
		seg.material_override = cord
		parent.add_child(seg)
		seg.global_position = (pts[i] + pts[i + 1]) / 2.0
		seg.look_at(pts[i + 1], Vector3.UP)
		seg.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hang_chochin(scenes[i % 2], (pts[i] + pts[i + 1]) / 2.0, face, parent)
	var l := OmniLight3D.new()
	l.omni_range = 7.0
	l.light_energy = 0.0
	l.light_color = Color(1.0, 0.6, 0.42)
	parent.add_child(l)
	l.global_position = pts[n / 2] + Vector3(0, -0.5, 0)
	lamp_lights.append(l)


func _pole(p: Vector3, h: float, parent: Node3D) -> Vector3:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.08
	cm.height = h
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.33, 0.24)
	mi.material_override = m
	mi.position = p + Vector3(0, h / 2.0, 0)
	parent.add_child(mi)
	return p + Vector3(0, h - 0.1, 0)


func _build_festivals() -> void:
	# 七夕: two decorated bamboo branches just inside the courtyard gate
	var tb := _fest_root("tanabata")
	for p in TANABATA_BAMBOO:
		spawn("E02_tanabata_bamboo", p, randf() * 360.0, 2, tb, 1.0)
	tanzaku_root = Node3D.new()
	tb.add_child(tanzaku_root)
	lantern_string(Vector3(-4.4, 2.6, -3.2), Vector3(2.2, 2.6, -3.3), 8, tb)
	# 品评会: a long table with the rivals' entries
	contest_root = _fest_root("contest")
	spawn("P_long_table", CONTEST_TABLE, 0.0, 1, contest_root, 1.0)
	for e in [["C02_radish", -1.1, 1.3], ["C07_sunflower", 0.0, 0.5], ["C08_strawberry", 1.1, 1.8]]:
		spawn(e[0], CONTEST_TABLE + Vector3(e[1], 0.8, 0.0), 0.0, 0, contest_root, e[2])
	var lb := Label3D.new()
	lb.text = "晴町蔬菜品评会"
	lb.font_size = 56
	lb.pixel_size = 0.005
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.modulate = Color(1.0, 0.95, 0.85)
	lb.outline_size = 12
	lb.outline_modulate = Color(0.4, 0.2, 0.1, 0.9)
	lb.position = CONTEST_TABLE + Vector3(0, 2.4, 0)
	contest_root.add_child(lb)
	# 夏祭: bon-odori tower, stalls and lantern strings over the courtyard
	var nm := _fest_root("natsumatsuri")
	spawn("P_yagura", YAGURA_POS, 0.0, 1, nm, 1.0)
	spawn("E01_yatai", Vector3(5.8, 0, 20.9), 180.0, 1, nm, 1.0)
	spawn("E01_yatai", Vector3(9.2, 0, 20.9), 180.0, 1, nm, 1.0)
	var top := YAGURA_POS + Vector3(0, 3.8, 0)
	for p in [Vector3(-11.8, 0, 11.0), Vector3(-11.8, 0, 23.2), Vector3(4.8, 0, 23.6), Vector3(8.0, 0, 13.0), Vector3(-2.6, 0, 10.2)]:
		var tip := _pole(p, 3.4, nm)
		lantern_string(top, tip, 10, nm)
	lantern_string(Vector3(-6.0, 2.8, -4.9), Vector3(0.0, 2.8, -4.9), 7, nm)
	# the day before the festival the children hang teru-teru-bozu in the zelkova (LORE.md: the rain stops for festivals)
	var tt: Texture2D = load("res://assets/ui/icons/teruteru.png") if ResourceLoader.exists("res://assets/ui/icons/teruteru.png") else null
	if tt:
		for k in 7:
			var a := TAU * k / 7.0 + 0.3
			var sp := Sprite3D.new()
			sp.texture = tt
			sp.pixel_size = 0.0019
			sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			sp.shaded = false
			sp.position = Vector3(4.0 + cos(a) * 2.3, 3.0 + 0.35 * sin(k * 1.7), 7.0 + sin(a) * 2.3)
			nm.add_child(sp)
	# 月见: the offering stand
	var tk := _fest_root("tsukimi")
	offering = spawn("P_offer_stand", Vector3(-1.4, 0, -2.0), 0.0, 1, tk, 1.0)
	if offering:
		offering.visible = true
	# a large full moon low over the courtyard wall (the painted night sky's moon sits too high to frame)
	moon = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(46, 46)
	moon.mesh = q
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mm.disable_fog = true
	mm.albedo_texture = load("res://assets/textures/moon.png")
	mm.albedo_color = Color(1.25, 1.22, 1.15)
	moon.material_override = mm
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon.position = Vector3(95, 118, 420)
	moon.visible = false
	tk.add_child(moon)


var swing: Array = []   # [lantern, phase] for every hanging chochin


## Hang one chochin (origin at its hook) at `at`; it sways a little with the wind.
func hang_chochin(ps: PackedScene, at: Vector3, yaw: float, parent: Node3D, scale_f: float = 1.0) -> Node3D:
	if ps == null:
		return null
	var lan: Node3D = ps.instantiate()
	parent.add_child(lan)
	lan.global_position = at
	lan.rotation.y = yaw
	lan.scale = Vector3.ONE * scale_f
	for mi in lan.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	swing.append([lan, randf() * TAU, yaw])
	return lan


func _process(_delta: float) -> void:
	if swing.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	for e in swing.duplicate():
		var candidate: Variant=e[0]
		if not is_instance_valid(candidate):
			swing.erase(e)
			continue
		var lan:=candidate as Node3D
		if not lan.is_visible_in_tree():
			continue
		var ph: float = e[1]
		var power: float=EnvironmentLife.wind_at(t,GameState.weather)
		lan.rotation = Vector3(sin(t * 1.1 + ph) * 0.05 * power, float(e[2]) + sin(t * 0.37 + ph) * 0.12, sin(t * 1.4 + ph * 1.7) * 0.07 * power)


func sync_festivals() -> void:
	var on := GameState.festivals_decorated()
	for fid in fest_nodes:
		var show: bool = on.has(fid) and region != "farm"
		(fest_nodes[fid] as Node3D).visible = show
		for body in (fest_nodes[fid] as Node).find_children("*", "StaticBody3D", true, false):
			(body as StaticBody3D).collision_layer = L_SOLID if show else 0
	if farm:
		for fid in farm.fest_nodes:
			(farm.fest_nodes[fid] as Node3D).visible = on.has(fid)
	# a wish written this summer stays on the bamboo
	if tanzaku_root and tanzaku_root.get_child_count() == 0 and GameState.flags.has("tanabata_wish"):
		hang_tanzaku(int(GameState.flags.tanabata_wish))


func hang_tanzaku(wish: int) -> void:
	if tanzaku_root == null:
		return
	var cols := [Color(0.95, 0.45, 0.5), Color(0.45, 0.65, 0.95), Color(0.98, 0.85, 0.35), Color(0.55, 0.85, 0.5)]
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.3)
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_color = cols[wish % cols.size()]
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = m.albedo_color * 0.3
	q.material_override = m
	q.position = TANABATA_BAMBOO[0] + Vector3(0.35, 1.5, 0.3)
	tanzaku_root.add_child(q)


func show_contest_entry(iid: String) -> void:
	if contest_root == null:
		return
	var model: String = GameState.crop_def(str(GameState.item(iid).get("crop", ""))).get("model", "")
	if model != "":
		var n := spawn(model, CONTEST_TABLE + Vector3(-0.1, 0.8, 0.35), 0.0, 0, contest_root, 1.0)
		if n:
			var box := local_aabb(n)
			var k := 0.5 / maxf(box.size.y, 0.2)
			n.scale = Vector3.ONE * minf(k, 1.2)


func show_offering(on: bool) -> void:
	if offering:
		offering.visible = on


# ------------------------------------------------------------------ farm & regions
var farm: FarmBuilder
var region := "town"

func _build_farm() -> void:
	farm = FarmBuilder.new()
	add_child(farm)
	farm.build(self)
	lamp_lights.append_array(farm.lamp_lights)


## Only the region the player is in is drawn (the town and the farm are 700 m apart).
func set_region(r: String) -> void:
	region = r
	for c in get_children():
		if c == world_env or c == sun or c == house or c == farm or not (c is Node3D):
			continue
		(c as Node3D).visible = r != "farm"
	if farm:
		farm.visible = r == "farm"
	sync_festivals()


# ------------------------------------------------------------------ interior
var house: HouseBuilder

var interiors := {}

func _build_house() -> void:
	house = HouseBuilder.new()
	add_child(house)
	house.build(self)
	# v0.6: the general store and the bakery have insides too (InteriorBuilder)
	for k in InteriorBuilder.SPECS:
		var ib := InteriorBuilder.new()
		add_child(ib)
		ib.build(self, k)
		interiors[k] = ib


# ------------------------------------------------------------------ phase look
var indoor := false

## Indoors the sun comes low through the garden-side glass doors (the house has an invisible,
## shadow-only roof), shadows turn a soft lavender, and a thin volumetric haze shows the light
## shafts. Outdoors everything returns to the town look.
func set_indoor_look(on: bool) -> void:
	indoor = on
	env.fog_enabled = not on
	env.volumetric_fog_enabled = on and not OS.has_feature("web")
	env.volumetric_fog_density = 0.0065
	env.volumetric_fog_albedo = Color(1.0, 0.96, 0.9)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 40.0
	env.ssil_enabled = on and not OS.has_feature("web")
	env.ssil_intensity = 0.65
	env.ambient_light_color = Color(0.8, 0.78, 0.96)
	env.ambient_light_sky_contribution = 0.55 if on else 1.0
	env.glow_bloom = 0.08 if on else 0.04
	sun.directional_shadow_max_distance = 40.0 if on else 90.0
	apply_phase(GameState.phase, false)


## Keyframes of the outdoor look, by hour:
## [hour, sun pitch, sun yaw, sun colour, sun energy, ambient, fog colour, fog density, saturation,
##  dusk sky weight, night sky weight, sky energy, street lamps]
const LOOK_KEYS := [
	[0.0, -48.0, 40.0, Color(0.58, 0.66, 1.0), 0.32, 0.4, Color(0.22, 0.27, 0.42), 0.0065, 0.95, 0.05, 1.0, 0.72, 2.0],
	[5.0, -30.0, 38.0, Color(0.6, 0.66, 0.95), 0.25, 0.42, Color(0.36, 0.42, 0.6), 0.0065, 0.98, 0.25, 0.75, 0.72, 1.6],
	[6.3, -9.0, 28.0, Color(1.0, 0.8, 0.64), 0.85, 0.74, Color(0.82, 0.8, 0.86), 0.0055, 1.04, 0.45, 0.08, 0.88, 0.0],
	[8.0, -27.0, 8.0, Color(1.0, 0.91, 0.8), 1.35, 0.95, Color(0.79, 0.85, 0.93), 0.0045, 1.07, 0.06, 0.0, 1.0, 0.0],
	[11.5, -48.0, -35.0, Color(1.0, 0.95, 0.86), 1.55, 1.05, Color(0.74, 0.84, 0.95), 0.0035, 1.08, 0.0, 0.0, 1.0, 0.0],
	[14.5, -42.0, -48.0, Color(1.0, 0.94, 0.83), 1.52, 1.02, Color(0.75, 0.84, 0.94), 0.0037, 1.09, 0.03, 0.0, 1.0, 0.0],
	[16.3, -27.0, -62.0, Color(1.0, 0.82, 0.62), 1.36, 0.9, Color(0.92, 0.82, 0.72), 0.0045, 1.12, 0.5, 0.0, 1.0, 0.0],
	[17.3, -18.0, -70.0, Color(1.0, 0.72, 0.48), 1.25, 0.8, Color(0.95, 0.78, 0.64), 0.0052, 1.14, 0.9, 0.0, 1.0, 0.0],
	[18.5, -7.0, -78.0, Color(1.0, 0.62, 0.44), 0.75, 0.64, Color(0.72, 0.62, 0.72), 0.0048, 1.1, 1.0, 0.15, 0.9, 1.6],
	[19.3, -3.0, -80.0, Color(0.7, 0.54, 0.68), 0.14, 0.5, Color(0.45, 0.43, 0.6), 0.0055, 1.02, 0.7, 0.55, 0.8, 1.8],
	[19.7, -40.0, 50.0, Color(0.55, 0.64, 1.0), 0.12, 0.46, Color(0.32, 0.34, 0.52), 0.006, 0.98, 0.4, 0.8, 0.76, 2.0],
	[20.6, -46.0, 42.0, Color(0.58, 0.66, 1.0), 0.33, 0.4, Color(0.23, 0.28, 0.43), 0.0065, 0.95, 0.08, 1.0, 0.72, 2.0],
	[24.0, -52.0, 30.0, Color(0.58, 0.66, 1.0), 0.32, 0.4, Color(0.22, 0.27, 0.42), 0.0065, 0.95, 0.05, 1.0, 0.72, 2.0],
]
## Weather changes the look multiplicatively: [sun, ambient, saturation shift, fog x, sky tint]
const WEATHER_MOD := {
	"sunny": [1.0, 1.0, 0.0, 1.0, Color(1, 1, 1)],
	"cloudy": [0.5, 1.02, -0.1, 1.45, Color(0.84, 0.86, 0.9)],
	"rain": [0.28, 0.9, -0.2, 2.3, Color(0.6, 0.64, 0.7)],
}
var _look_tween: Tween
var _sky_min := -999.0
var _sky_weather := ""


static func look_at_hour(h: float) -> Dictionary:
	var a: Array = LOOK_KEYS[0]
	var b: Array = LOOK_KEYS[0]
	for i in LOOK_KEYS.size() - 1:
		if h >= float(LOOK_KEYS[i][0]) and h <= float(LOOK_KEYS[i + 1][0]):
			a = LOOK_KEYS[i]
			b = LOOK_KEYS[i + 1]
			break
	var t := 0.0 if float(b[0]) <= float(a[0]) else (h - float(a[0])) / (float(b[0]) - float(a[0]))
	t = t * t * (3.0 - 2.0 * t)
	return {
		"rot": Vector3(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), 0),
		"col": (a[3] as Color).lerp(b[3], t), "sun": lerpf(a[4], b[4], t), "amb": lerpf(a[5], b[5], t),
		"fog": (a[6] as Color).lerp(b[6], t), "fog_d": lerpf(a[7], b[7], t), "sat": lerpf(a[8], b[8], t),
		"dusk": lerpf(a[9], b[9], t), "night": lerpf(a[10], b[10], t), "sky": lerpf(a[11], b[11], t),
		"lamp": lerpf(a[12], b[12], t),
	}


## Drive sun, sky, fog, lamps and the painted backdrops from the clock (called every frame by main).
func update_time(minute: float, weather: String, force: bool = false) -> void:
	if _look_tween and _look_tween.is_running() and not force:
		return
	_apply_look(minute, weather, force)


func _apply_look(minute: float, weather: String, force: bool = false) -> void:
	var L := look_at_hour(minute / 60.0)
	var W: Array = WEATHER_MOD.get(weather, WEATHER_MOD.sunny)
	var market := GameState.phase == "market"
	L.sun *= W[0] * 1.08
	L.amb *= W[1] * .84
	L.sat += W[2]
	L.fog_d *= W[3] * .52
	if weather == "rain":
		L.fog = L.fog.lerp(Color(0.6, 0.64, 0.7) * (0.4 + 0.6 * (1.0 - L.night)), 0.55)
	if market:
		L.lamp = maxf(L.lamp, 1.6)
	look = L
	if moon:
		moon.visible = L.night > 0.35
	var evening := minute >= 16.5 * 60.0 or minute < 6.3 * 60.0 or market
	if house:
		house.set_evening(evening, false)
	for k in interiors:
		(interiors[k] as InteriorBuilder).set_evening(evening)
	if indoor:
		var i_rot := Vector3(-16, 228, 0) if evening else HouseBuilder.SUN_DAY_ROT
		sun.rotation_degrees = i_rot
		var night_in := clampf(L.night, 0.0, 1.0)
		sun.light_color = (Color(1.0, 0.64, 0.42) if evening else Color(1.0, 0.92, 0.78)).lerp(Color(0.55, 0.62, 0.95), night_in)
		sun.light_energy = (1.4 if evening else 1.62) * lerpf(1.0, 0.05, night_in) * lerpf(1.0, W[0], 0.6)
		env.ambient_light_energy = (0.42 if evening else 0.58) * lerpf(1.0, 0.6, night_in)
		env.adjustment_saturation = (1.14 if evening else 1.1) + W[2] * 0.5
		for l in lamp_lights:
			l.light_energy = 0.0
	else:
		sun.rotation_degrees = L.rot
		sun.light_color = L.col
		sun.light_energy = L.sun
		env.fog_light_color = L.fog
		env.fog_density = L.fog_d
		env.ambient_light_energy = L.amb
		env.adjustment_saturation = L.sat
		for l in lamp_lights:
			l.light_energy = L.lamp
		ShopWindows.light(window_mats, L.lamp, L.fog)
		BuildingLife.update(building_life, minute, L.lamp)
	# the sky's radiance map is rebuilt when it changes, so only touch it every couple of game minutes
	if force or absf(minute - _sky_min) >= 2.0 or weather != _sky_weather:
		_sky_min = minute
		_sky_weather = weather
		sky_mat.set_shader_parameter("dusk_w", clampf(L.dusk, 0.0, 1.0))
		sky_mat.set_shader_parameter("night_w", clampf(L.night, 0.0, 1.0))
		sky_mat.set_shader_parameter("energy", L.sky)
		sky_mat.set_shader_parameter("tint", Vector3(W[4].r, W[4].g, W[4].b))
		sky_mat.set_shader_parameter("drift", fmod(minute / 1440.0 * 0.35 + float(GameState.day) * 0.13, 1.0))
		var ct := Color(1, 1, 1).lerp(Color(1.0, 0.8, 0.72), clampf(L.dusk, 0.0, 1.0) * 0.7).lerp(Color(0.3, 0.36, 0.55), clampf(L.night, 0.0, 1.0))
		ct = ct * lerpf(1.0, 0.8, 1.0 - W[1] + (0.2 if weather == "rain" else 0.0))
		var hz := Color(0.72, 0.82, 0.93).lerp(L.fog, 0.6)
		for m in card_mats:
			m.set_shader_parameter("tint", ct)
			m.set_shader_parameter("haze", hz)
		for pair in std_cards:
			(pair[0] as StandardMaterial3D).albedo_color = (pair[1] as Color) * ct
		if farm and farm.water_mat:
			farm.water_mat.set_shader_parameter("dusk_w",clampf(L.dusk,0,1))
			farm.water_mat.set_shader_parameter("night_w",clampf(L.night,0,1))
			farm.water_mat.set_shader_parameter("sun_direction",sun.global_basis.z.normalized())
			farm.water_mat.set_shader_parameter("tint", Color(1, 1, 1).lerp(Color(1.0, 0.82, 0.7), clampf(L.dusk, 0.0, 1.0) * 0.6).lerp(Color(0.28, 0.34, 0.5), clampf(L.night, 0.0, 1.0)))
		set_wind(weather)


## Kept for the story and tests: re-applies the look for the current clock, optionally as a
## 2.5 s blend from `from_minute` (used when the market opens and time jumps to the evening).
func apply_phase(phase: String, animate: bool, from_minute: float = -1.0) -> void:
	if house:
		house.set_evening(phase == "market" or GameState.minute >= 16.5 * 60.0, animate)
	if not animate or from_minute < 0.0 or indoor:
		_apply_look(GameState.minute, GameState.weather, true)
		return
	if _look_tween:
		_look_tween.kill()
	_look_tween = create_tween()
	_look_tween.tween_method(func(m): _apply_look(m, GameState.weather, true), from_minute, GameState.minute, 2.5)


## Highest near-horizontal rendered triangle over this point; chair backs cannot fake a table top.
static func rendered_support_height(model: Node3D, at: Vector3, max_height: float = INF, require_hit: bool = false) -> float:
	var highest := -1000.0
	for mesh_node: MeshInstance3D in find_meshes(model):
		for surface_index in mesh_node.mesh.get_surface_count():
			var arrays: Array = mesh_node.mesh.surface_get_arrays(surface_index)
			if arrays.is_empty():
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			var count: int = indices.size() if not indices.is_empty() else vertices.size()
			for face_index in range(0, count - 2, 3):
				var a: Vector3 = mesh_node.global_transform * vertices[indices[face_index] if not indices.is_empty() else face_index]
				var b: Vector3 = mesh_node.global_transform * vertices[indices[face_index + 1] if not indices.is_empty() else face_index + 1]
				var c: Vector3 = mesh_node.global_transform * vertices[indices[face_index + 2] if not indices.is_empty() else face_index + 2]
				var normal: Vector3 = (b - a).cross(c - a)
				if absf(normal.y) < normal.length() * .85:
					continue
				var den: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
				if absf(den) < .000001:
					continue
				var u: float = ((b.z - c.z) * (at.x - c.x) + (c.x - b.x) * (at.z - c.z)) / den
				var v: float = ((c.z - a.z) * (at.x - c.x) + (a.x - c.x) * (at.z - c.z)) / den
				if u >= -.001 and v >= -.001 and u + v <= 1.001:
					var height: float = a.y * u + b.y * v + c.y * (1.0 - u - v)
					if height <= max_height: highest = maxf(highest, height)
	if highest < -999.0: return -INF if require_hit else model.global_position.y
	return highest

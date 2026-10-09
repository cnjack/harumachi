class_name FarmBuilder
extends Node3D
## 河边市民农园: the riverside allotment reached from the east end of the main street.
## A separate walkable region far east of the town (the town is hidden while the player is here).
## Local axes: +Z is south toward the river, the entrance path comes in from the west.

const ORIGIN := Vector3(700, 0, 0)
const ENTRY := Vector3(-24.6, 0.1, 0.4)        # where the player arrives from town
const ENTRY_YAW := -90.0                        # facing +X (east) into the farm
const RIVER := [14.0, 20.0]                     # river z range
const BRIDGE_X := 0.0

## Interactables: [id, x, z, y, radius]
const POINTS := [
	["farm_exit", -27.6, 0.3, 1.0, 2.6],
	["farm_shed", -10.6, -5.9, 1.1, 2.2],
	["farm_pump", -7.2, -2.9, 0.9, 1.7],
	["farm_compost", -13.9, -3.9, 0.8, 1.8],
	["veggie_stand", 6.5, 1.9, 1.0, 1.9],
	["farm_bench", 9.6, 11.6, 0.7, 1.8],
	["farm_sign", -21.5, -1.9, 1.0, 1.8],
	["scarecrow", 6.3, -5.3, 1.1, 1.6],
	["farm_logs", -15.2, -8.6, 0.8, 1.7],
	["farm_hokora", -6.6, 25.3, 0.9, 1.6],
]
const PLOT_COLS := [-3.45, -1.15, 1.15, 3.45]
const PLOT_ROWS := [-3.0, -5.3, -7.6]
const GH_POS := Vector3(11.8, 0, -6.4)
const GH2_POS := Vector3(11.8, 0, -11.6)
const GH_PLOTS := {"gh0": Vector3(11.8, 0, -5.0), "gh1": Vector3(11.8, 0, -7.0), "gh2": Vector3(11.8, 0, -10.2), "gh3": Vector3(11.8, 0, -12.2)}
const GATE_POS := Vector3(-26.2, 0, 0.3)
## Props that make the allotment feel used: [model, x, z, yaw, collide, scale]
const DECOR := [
	["D07_kei_truck", -10.0, 2.85, 90.0, 1, 1.0], ["D03_veg_crates", 8.3, 3.3, 15.0, 1, 1.0],
	["D03_veg_crates", -13.0, -7.8, -20.0, 1, 0.9], ["D01_wheelbarrow", -6.3, -9.2, 35.0, 1, 1.0],
	["D02_rain_barrel", -8.8, -9.3, 0.0, 1, 1.0], ["D08_tool_rack", -12.9, -9.6, 0.0, 1, 1.0],
	["D09_log_pile", -15.2, -9.8, 10.0, 1, 1.0], ["D06_well", -15.5, 6.8, 180.0, 1, 1.0],
	["D12_flower_planter", 4.3, 3.3, 180.0, 1, 1.0], ["D12_flower_planter", -23.4, -2.9, 0.0, 1, 1.0],
	["D10_rocks", -24.2, 9.6, 40.0, 1, 1.1], ["D10_rocks", 14.6, 9.9, 200.0, 1, 0.9], ["D10_rocks", 22.3, -7.2, 90.0, 1, 1.2],
	["D10_rocks", -9.0, 27.4, 120.0, 1, 1.0], ["D05_hokora", -6.6, 26.2, 180.0, 1, 1.0], ["D04_stone_lantern", -4.6, 25.9, 180.0, 1, 1.0],
	["D04_stone_lantern", 4.4, 25.9, 180.0, 1, 1.0],
	["D11_reeds", -20.0, 13.2, 0.0, 0, 1.0], ["D11_reeds", -12.8, 13.3, 70.0, 0, 0.9], ["D11_reeds", -6.4, 13.2, 140.0, 0, 1.1],
	["D11_reeds", 5.6, 13.3, 30.0, 0, 1.0], ["D11_reeds", 13.2, 13.2, 200.0, 0, 0.9], ["D11_reeds", 19.4, 13.3, 90.0, 0, 1.0],
	["D11_reeds", -16.8, 20.8, 10.0, 0, 1.0], ["D11_reeds", -9.4, 20.8, 250.0, 0, 0.9], ["D11_reeds", 9.2, 20.8, 120.0, 0, 1.1],
	["D11_reeds", 15.8, 20.8, 60.0, 0, 1.0],
]

var wb: WorldBuilder
var plot_views := {}
var fx: FestivalFX
var fest_nodes := {}
var water_mat: ShaderMaterial
var lakeside: LakesideBuilder
var lamp_lights: Array[OmniLight3D] = []


static func plot_pos(id: String) -> Vector3:
	if GH_PLOTS.has(id):
		return GH_PLOTS[id]
	var i := int(id.substr(4))
	return Vector3(PLOT_COLS[i % 4], 0, PLOT_ROWS[i / 4])


func build(world: WorldBuilder) -> void:
	wb = world
	name = "Farm"
	position = ORIGIN
	_ground()
	_river()
	_field()
	_buildings()
	_greenery()
	_boundary()
	_lamps()
	_backdrop()
	_landmarks()
	_decor()
	_grass()
	_festival_decor()
	fx = FestivalFX.new()
	fx.name = "FestivalFX"
	add_child(fx)
	for id in GameState.plot_ids():
		if id.begins_with("farm") or id.begins_with("gh"):
			var pv := PlotView.new()
			add_child(pv)
			pv.position = plot_pos(id)
			pv.setup(wb, id, true, 0.8 if id.begins_with("gh") else 0.95)
			plot_views[id] = pv


func refresh_plots() -> void:
	for id in plot_views:
		(plot_views[id] as PlotView).refresh()


# ------------------------------------------------------------------ terrain
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


func _solid(size: Vector3, pos: Vector3, layer: int = WorldBuilder.L_SOLID) -> void:
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


func _ground() -> void:
	lakeside = LakesideBuilder.new()
	add_child(lakeside)
	lakeside.build(wb)
	water_mat = lakeside.water_mat
	var path := WorldBuilder.ground_material("gravel")
	path.set_shader_parameter("tint", Color(0.95, 0.9, 0.82))
	path.set_shader_parameter("feather", 0.3)        # grass creeps over the path edges
	_plane([-32, -0.9, 20, 1.5], path, 0.012)            # main path along the field
	_plane([-1.1, 1.5, 1.1, RIVER[0]], path, 0.012)      # to the bridge
	_plane([-1.1, RIVER[1], 1.1, 25.0], path, 0.012)     # off the bridge on the far bank
	_plane([-9.0, 24.6, 10.5, 26.2], path, 0.012)        # the riverside walk: shrine, lanterns, bench
	_plane([-12.5, -6.2, -5.5, -0.9], path, 0.011)       # yard in front of the shed
	_plane([9.8, -4.4, 13.8, -0.9], path, 0.011)         # greenhouse apron
	_plane([13.6, -12.0, 14.8, -0.9], path, 0.011)       # to the second greenhouse
	var soil := WorldBuilder.ground_material("gravel")
	soil.set_shader_parameter("tint", Color(0.55, 0.42, 0.32))
	_plane([-5.0, -9.0, 5.0, -1.8], soil, 0.01)          # worked soil between the beds


func _river() -> void:
	# a proper bank-to-bank bridge (built in Blender, art/tools/proc_models.py): its hidden "deck" strip
	# is the walkable surface, the rest is looks
	var bridge := wb.spawn("P_bridge", Vector3(BRIDGE_X, 0.0, (RIVER[0] + RIVER[1]) / 2.0), 0.0, 0, self, 1.0)
	if bridge:
		LakesideMaterials.decorate_bridge(bridge)
		for mi in WorldBuilder.find_meshes(bridge):
			if str(mi.name).begins_with("deck") or str(mi.get_parent().name).begins_with("deck"):
				mi.visible = false
				var body := StaticBody3D.new()
				body.collision_layer = WorldBuilder.L_GROUND
				var shape := CollisionShape3D.new()
				shape.shape = mi.mesh.create_trimesh_shape()
				body.add_child(shape)
				mi.add_child(body)
		# the railings keep the player on the deck
		for side in [-1.0, 1.0]:
			_solid(Vector3(0.15, 1.6, 10.0), Vector3(BRIDGE_X + side * 0.98, 0.8, (RIVER[0] + RIVER[1]) / 2.0))


# ------------------------------------------------------------------ the allotment
func _field() -> void:
	# low cedar fence round the beds, open toward the path
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.36, 0.24)
	wood.roughness = 0.95
	var rect := [-5.4, -9.4, 5.4, -1.6]
	var posts := []
	for x in range(0, 12):
		var px: float = rect[0] + (rect[2] - rect[0]) * x / 11.0
		posts.append(Vector3(px, 0, rect[1]))
	for z in range(1, 5):
		var pz: float = rect[1] + (rect[3] - rect[1]) * z / 5.0
		posts.append(Vector3(rect[0], 0, pz))
		posts.append(Vector3(rect[2], 0, pz))
	for p in posts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.8, 0.09)
		mi.mesh = bm
		mi.material_override = wood
		mi.position = p + Vector3(0, 0.4, 0)
		add_child(mi)
	for spec in [[Vector3(0, 0.55, rect[1]), Vector3(rect[2] - rect[0], 0.05, 0.04)],
			[Vector3(rect[0], 0.55, (rect[1] + rect[3]) / 2.0 - 0.8), Vector3(0.04, 0.05, rect[3] - rect[1] - 1.6)],
			[Vector3(rect[2], 0.55, (rect[1] + rect[3]) / 2.0 - 0.8), Vector3(0.04, 0.05, rect[3] - rect[1] - 1.6)]]:
		for dy in [0.0, -0.25]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = spec[1]
			mi.mesh = bm
			mi.material_override = wood
			mi.position = spec[0] + Vector3(0, dy, 0)
			add_child(mi)
	_solid(Vector3(rect[2] - rect[0], 1.2, 0.2), Vector3(0, 0.6, rect[1]))
	_solid(Vector3(0.2, 1.2, rect[3] - rect[1]), Vector3(rect[0], 0.6, (rect[1] + rect[3]) / 2.0))
	_solid(Vector3(0.2, 1.2, rect[3] - rect[1]), Vector3(rect[2], 0.6, (rect[1] + rect[3]) / 2.0))
	wb.spawn("F04_scarecrow", Vector3(6.3, 0, -5.3), -20.0, 2, self, 1.0)
	# name board at the entrance
	var sign := Node3D.new()
	sign.name="FarmNameSign"
	sign.position = Vector3(-21.5, 0, -2.4)
	sign.rotation.z=deg_to_rad(-.7)
	sign.set_meta("decorated_sign",true)
	add_child(sign)
	for x in [-0.55, 0.55]:
		var post := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.08, 1.5, 0.08)
		post.mesh = pb
		post.material_override = LakesideMaterials.wood(sign.global_position,true,true)
		post.position = Vector3(x, 0.75, 0)
		sign.add_child(post)
	var board := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.12, 0.55, 0.05)
	board.mesh = bb
	board.material_override = LakesideMaterials.sign_face()
	board.position = Vector3(0, 1.2, 0)
	sign.add_child(board)
	for pin_index: int in range(4):
		var pin: MeshInstance3D=MeshInstance3D.new()
		pin.name="OldIronPin_%d"%pin_index
		var head: CylinderMesh=CylinderMesh.new()
		head.top_radius=.009;head.bottom_radius=.009;head.height=.004;head.radial_segments=8
		pin.mesh=head
		pin.material_override=JapaneseArchitecture._flat(Color(.29,.30,.28))
		pin.rotation.x=PI/2.0
		pin.position=Vector3(-.48 if pin_index%2==0 else .48,1.2+(-.20 if pin_index<2 else .20),.028)
		sign.add_child(pin)
	for side in [-1.0, 1.0]:
		var lbl := Label3D.new()
		lbl.text = "晴町 市民农园"
		lbl.font_size = 40
		lbl.pixel_size = 0.0034
		lbl.modulate = Color(0.32, 0.22, 0.14)
		lbl.outline_size = 0
		lbl.double_sided = false
		lbl.position = Vector3(0, 1.2, 0.03 * side)
		lbl.rotation.y = 0.0 if side > 0.0 else PI
		sign.add_child(lbl)


func _buildings() -> void:
	wb.spawn("F01_tool_shed", Vector3(-10.6, 0, -8.2), 0.0, 1, self, 1.0)
	wb.spawn("F02_hand_pump", Vector3(-7.2, 0, -3.8), 0.0, 1, self, 1.0)
	wb.spawn("F03_compost_bin", Vector3(-13.9, 0, -4.9), 20.0, 1, self, 1.0)
	wb.spawn("F06_veggie_stand", Vector3(6.5, 0, 2.9), 180.0, 1, self, 1.0)
	_greenhouse(GH_POS)
	_greenhouse(GH2_POS)
	for bench_spec: Array in [[Vector3(9.6,0,12.3),0.0],[Vector3(8.8,0,24.4),180.0],[Vector3(-16.4,0,-1.9),0.0]]:
		var bench:=wb.spawn("A12_bench",bench_spec[0],bench_spec[1],1,self,1.0)
		if bench:WorldBuilder.rest_on_terrain(bench,0.0,0.0)
	wb.spawn("A16_planter_box", Vector3(-8.6, 0, -7.9), 0.0, 1, self, 1.0)
	wb.spawn("A15_potted_plant", Vector3(-12.7, 0, -6.6), 0.0, 0, self, 1.0)


func _greenhouse(at: Vector3) -> void:
	var gh := wb.spawn("F05_greenhouse", at, 0.0, 0, self, 1.0)
	if gh:
		# milky film: see the strawberries inside, keep the pipe frame readable
		for mi in WorldBuilder.find_meshes(gh):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for si in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(si)
				if src is StandardMaterial3D:
					var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
					m.albedo_color = Color(1, 1, 1, 0.42)
					m.cull_mode = BaseMaterial3D.CULL_DISABLED
					mi.set_surface_override_material(si, m)
		var box := WorldBuilder.local_aabb(gh)
		var hx := box.size.x / 2.0
		var hz := box.size.z / 2.0
		_solid(Vector3(0.15, 2.2, box.size.z), at + Vector3(-hx, 1.1, 0))
		_solid(Vector3(0.15, 2.2, box.size.z), at + Vector3(hx, 1.1, 0))
		_solid(Vector3(box.size.x, 2.2, 0.15), at + Vector3(0, 1.1, -hz))
		# the film lets soft light through; keep the inside readable
		var fill := OmniLight3D.new()
		fill.position = at + Vector3(0, 1.8, 0)
		fill.omni_range = 4.0
		fill.light_energy = 0.6
		fill.light_color = Color(1.0, 0.97, 0.9)
		add_child(fill)


func _greenery() -> void:
	for t in [[-19.0, -12.0, 0.62], [17.5, -12.5, 0.56], [-25.0, 6.5, 0.5], [23.0, 6.0, 0.52], [-6.0, -15.0, 0.6],
			[-17.0, 26.0, 0.66], [22.0, 27.0, 0.6], [3.5, 30.0, 0.55]]:
		var tree := wb.spawn("T01_courtyard_tree", Vector3(t[0], 0, t[1]), randf() * 360.0, 0, self, t[2])
		if tree:
			wb._trunk_collider(tree, 0.5)
	for b in [[-15.5, -8.8], [-4.0, -11.5], [14.6, -14.6], [-24.0, -4.5], [18.5, 1.5], [-9.5, 11.5], [12.0, 11.8], [-20.0, 11.2]]:
		wb.spawn("M12b_shrub", Vector3(b[0], 0, b[1]), randf() * 360.0, 2, self, randf_range(0.9, 1.2))
	for h in [[-3.5, 12.4], [4.0, 12.6], [15.5, 12.2], [-14.0, 12.5]]:
		wb.spawn("M12d_flower_bush", Vector3(h[0], 0, h[1]), randf() * 360.0, 2, self, randf_range(0.8, 1.0))
	# Two small summer groups; the bridge and opposite-bank view remain open.
	for flower_index: int in range(4):
		var flower_x: float = [-16.8,-15.5,14.0,15.3][flower_index]
		var flower_z: float = LakesideLayout.river_z(flower_x)+LakesideLayout.river_half(flower_x)+1.8
		var flower_ground: float = LakesideLayout.height_at(Vector2(flower_x,flower_z))
		var flower: Node3D = wb.spawn("C07_sunflower",Vector3(flower_x,flower_ground,flower_z),[174.0,191.0,168.0,184.0][flower_index],0,self,[.84,.96,.86,.93][flower_index])
		if flower:flower.set_meta("far_bank_sunflower",true)


func _boundary() -> void:
	var rect := LakesideLayout.BOUNDS
	_solid(Vector3(.4,20,rect.size.y),Vector3(rect.position.x,10,rect.get_center().y),WorldBuilder.L_BLOCK)
	_solid(Vector3(.4,20,rect.size.y),Vector3(rect.end.x,10,rect.get_center().y),WorldBuilder.L_BLOCK)
	_solid(Vector3(rect.size.x,20,.4),Vector3(rect.get_center().x,10,rect.position.y),WorldBuilder.L_BLOCK)
	_solid(Vector3(rect.size.x,20,.4),Vector3(rect.get_center().x,10,rect.end.y),WorldBuilder.L_BLOCK)


func _lamps() -> void:
	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color(1.0, 0.9, 0.7)
	bulb.emission_enabled = true
	bulb.emission = Color(1.0, 0.8, 0.5)
	bulb.emission_energy_multiplier = 3.0
	var arm := StandardMaterial3D.new()
	arm.albedo_color = Color(0.3, 0.3, 0.32)
	for p in [Vector3(-16.8, 0, 2.9), Vector3(2.4, 0, 12.9), Vector3(15.5, 0, 2.9)]:
		# a simple wooden post with a lamp arm, lit from dusk to dawn
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.09
		cm.height = 3.6
		post.mesh = cm
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.42, 0.33, 0.25)
		post.material_override = wood
		post.position = p + Vector3(0, 1.8, 0)
		add_child(post)
		var am := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, 0.7)
		am.mesh = bm
		am.material_override = arm
		am.position = p + Vector3(0, 3.45, -0.3)
		add_child(am)
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.16
		b.mesh = sm
		b.material_override = bulb
		b.position = p + Vector3(0, 3.33, -0.62)
		add_child(b)
		_solid(Vector3(0.25, 3.6, 0.25), p + Vector3(0, 1.8, 0))
		var l := OmniLight3D.new()
		l.position = p + Vector3(0, 3.2, -0.62)
		l.omni_range = 9.0
		l.omni_attenuation = 0.7
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		lamp_lights.append(l)
	_neighbour_plots()


## Other gardeners' beds east of the greenhouse and behind the shed, so the allotment feels used.
func _neighbour_plots() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var crops := ["C04_tomato", "C05_cucumber", "C06_edamame", "C02_radish", "C03_komatsuna", "C07_sunflower"]
	var beds := []
	for r in 3:
		for c in 2:
			beds.append(Vector3(16.6 + c * 2.3, 0, -3.4 - r * 2.3))
	for r in 2:
		for c in 2:
			beds.append(Vector3(-20.8 + c * 2.3, 0, -6.6 - r * 2.3))
	for b in beds:
		var bed := wb.spawn("F08_soil_plot", b, rng.randf_range(-3, 3), 1, self, 1.0)
		if bed:
			bed.scale = Vector3(0.95, 0.6, 0.95)
		var model: String = crops[rng.randi() % crops.size()]
		var n := 1 if model in ["C05_cucumber"] else (2 if model in ["C04_tomato", "C07_sunflower", "C06_edamame"] else 4)
		for i in n:
			var off := Vector3(0, 0, 0) if n == 1 else (Vector3((i - 0.5) * 0.5, 0, rng.randf_range(-0.1, 0.1)) if n == 2 else Vector3(((i % 2) - 0.5) * 0.52, 0, ((i / 2) - 0.5) * 0.52))
			wb.spawn(model, b + off + Vector3(0, 0.23, 0), rng.randf() * 360.0, 0, self, rng.randf_range(0.6, 1.0))
	# a few odds and ends: a watering can by the beds, stacked crates at the shed
	wb.spawn("A16_planter_box", Vector3(19.0, 0, -9.8), 90.0, 1, self, 0.9)
	wb.spawn("A15_potted_plant", Vector3(-17.8, 0, -4.2), 0.0, 0, self, 1.0)


func _backdrop() -> void:
	# Sparse distant ridges leave the new lake's sky open; the old tall forest
	# paintings read as a vertical wall when approached from the expanded map.
	for spec in [[Vector3(60,0,-350),0.0],[Vector3(60,0,390),180.0],[Vector3(470,0,15),-90.0],[Vector3(-400,0,15),90.0]]:
		wb._card("bg_far_ridge",spec[0],900.0,float(spec[1]),.55,-10.0,self)
	var trees := ["bg_tree_a", "bg_tree_b", "bg_tree_c"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	# The old 206-475 px cards stood 3-4 m from the walkable boundary and read as a blurry wall.
	# Full-resolution alpha sprites are a far layer; actual trees provide parallax in front.
	for seg in [[Vector3(-56, 0, -59), Vector3(164, 0, -59), 0.0], [Vector3(-56, 0, -59), Vector3(-56, 0, 85), 90.0],
			[Vector3(164, 0, -59), Vector3(164, 0, 85), -90.0], [Vector3(-56, 0, 85), Vector3(164, 0, 85), 180.0]]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var n := int(a.distance_to(b) / 10.0)
		for i in n:
			var t := (i + rng.randf_range(0.1, 0.9)) / float(n)
			var tex: String = trees[rng.randi() % 3]
			var w := rng.randf_range(12.0, 17.0)
			var yaw: float = seg[2] + rng.randf_range(-12.0, 12.0)
			var p := a.lerp(b, t)
			if p.x < -30.0 and absf(p.z - LANE_Z) < LANE_BANK + 1.0:
				continue      # keep the climb back to town in view
			wb._card(tex, p, w, yaw, 0.12, -0.3, self)
	for pos: Vector3 in [Vector3(-47, 0, -12), Vector3(-47, 0, 10), Vector3(-47, 0, 27), Vector3(154, 0, -12),
		Vector3(154, 0, 8), Vector3(154, 0, 27), Vector3(-23, 0, -33), Vector3(-4, 0, -33), Vector3(17, 0, -33),
		Vector3(-22, 0, 48), Vector3(-2, 0, 48), Vector3(20, 0, 48)]:
		var tree_id: String = WorldBuilder.NEAR_TREES[rng.randi() % WorldBuilder.NEAR_TREES.size()]
		var tree := wb.spawn(tree_id, Vector3(pos.x,LakesideLayout.height_at(Vector2(pos.x,pos.z)),pos.z), rng.randf_range(-180.0, 180.0), 0, self, rng.randf_range(.80, 1.10))
		if tree:
			WorldBuilder.rest_on_terrain(tree,LakesideLayout.height_at(Vector2(pos.x,pos.z)))
			for mesh: MeshInstance3D in WorldBuilder.find_meshes(tree):
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lane_up(trees)


## v0.6: the path climbs west out of the allotment between grass banks and disappears into the trees at the
## top, the other end of the lane that drops out of town under the matching gate (WorldBuilder._build_town_exit).
const LANE_Z := 0.3
const LANE_BANK := 7.0

static func lane_height(x: float) -> float:
	return lerpf(3.2, 0.0, smoothstep(-50.0, -32.5, x))


func _lane_up(trees: Array) -> void:
	var path := WorldBuilder.ground_material("gravel")
	path.set_shader_parameter("tint", Color(0.95, 0.9, 0.82))
	var bank := WorldBuilder.ground_material("grass")
	bank.set_shader_parameter("feather", 0.0)
	WorldBuilder.lane(self, -56.0, -30.2, LANE_Z, 1.2, LANE_BANK, -50.0, -32.5, 3.2, 0.0, path, bank, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 62
	for t in [[-56.5, 0.0, 15.0], [-54.0, -5.4, 12.0], [-54.5, 5.6, 12.0]]:
		var x: float = t[0]
		var off := absf(t[1]) / LANE_BANK
		var y := lane_height(x) * clampf(1.0 - (off - 0.17) / 0.83, 0.0, 1.0)
		var slope_tree:=wb.spawn(WorldBuilder.NEAR_TREES[rng.randi() % WorldBuilder.NEAR_TREES.size()], Vector3(x, y, LANE_Z + t[1]), rng.randf_range(-180.0,180.0), 0, self, rng.randf_range(1.0,1.2))
		if slope_tree:WorldBuilder.rest_on_terrain(slope_tree,y)
	for near: Vector2 in [Vector2(-45.0, -6.6), Vector2(-44.0, 6.8), Vector2(-38.0, -7.4), Vector2(-37.4, 7.8)]:
		var off := absf(near.y) / LANE_BANK
		var y := lane_height(near.x) * clampf(1.0 - (off - 0.17) / 0.83, 0.0, 1.0)
		var verge_tree:=wb.spawn("T01_courtyard_tree", Vector3(near.x, y, LANE_Z + near.y), rng.randf_range(-180.0, 180.0), 0, self, 0.22)
		if verge_tree:WorldBuilder.rest_on_terrain(verge_tree,y)
	for x in [-35.0, -41.0]:
		wb.spawn("P_toro", Vector3(x, WorldBuilder.lane_side_y(lane_height(x), 2.0, 1.2, LANE_BANK), LANE_Z + 2.0), -90.0, 0, self, 0.8)


# ------------------------------------------------------------------ v0.5: landmarks, props, meadow
var gate_lights: Array[OmniLight3D] = []

func _label(text: String, pos: Vector3, yaw: float, size: int = 40, parent: Node3D = null, both: bool = true) -> void:
	for side in ([0.0, PI] if both else [0.0]):
		var l := Label3D.new()
		l.text = text
		l.font_size = size
		l.pixel_size = 0.0036
		l.modulate = Color(0.3, 0.2, 0.12)
		l.outline_size = 0
		l.double_sided = false
		if text == "晴町 市民农园":
			l.name = "GateTitle_farm_%d" % int(side * 100.0)
		var offset := 0.065 if text == "晴町 市民农园" else 0.035
		l.position = pos + Vector3(sin(yaw + side), 0, cos(yaw + side)) * offset
		l.rotation.y = yaw + side
		(parent if parent else self).add_child(l)


func _landmarks() -> void:
	# the way back to town: a lantern gate over the path and a signpost, both visible from the fields
	var gate := wb.spawn("P_farm_gate", GATE_POS, 90.0, 0, self, 1.0)
	if gate:
		WorldBuilder.add_gate_colliders(gate)
	_label("晴町 市民农园", GATE_POS + Vector3(0, WorldBuilder.GATE_TITLE_Y, 0), PI / 2.0, 34)
	for z in [-1.5, 1.5]:
		var l := OmniLight3D.new()
		l.position = GATE_POS + Vector3(0, 2.0, z)
		l.omni_range = 5.0
		l.light_color = Color(1.0, 0.55, 0.4)
		l.light_energy = 0.0
		add_child(l)
		gate_lights.append(l)
		lamp_lights.append(l)
	var back := Label3D.new()
	back.text = "← 回晴町"
	back.font_size = 72
	back.pixel_size = 0.006
	back.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	back.modulate = Color(1.0, 0.97, 0.88)
	back.outline_size = 16
	back.outline_modulate = Color(0.32, 0.2, 0.12, 0.9)
	back.position = GATE_POS + Vector3(0, 3.9, 0)
	back.name = "BackToTown"
	add_child(back)
	var sp := wb.spawn("P_signpost", Vector3(-22.6, 0, 1.9), 0.0, 2, self, 1.0)
	if sp:
		LakesideMaterials.decorate_bridge(sp)
		# board 0 points +X (into the farm), board 1 -X (back to town), board 2 toward the river
		_label("菜地 · 温室 →", Vector3(-22.6 + 0.6, 2.0, 1.9), 0.0, 26)
		_label("← 回晴町", Vector3(-22.6 - 0.6, 1.6, 1.9), 0.0, 30)
		_label("河边 · 木桥 ↘", Vector3(-22.6 + 0.54, 1.2, 1.9 + 0.25), deg_to_rad(-25.0), 24)


func _fest_root(fid: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Fest_" + fid
	n.visible = false
	add_child(n)
	fest_nodes[fid] = n
	return n


## v0.6: Obon hangs white bellflower lanterns along the near bank; the fireworks night strings
## red and white chochin between bamboo poles. sync_festivals() shows them on their days.
func _festival_decor() -> void:
	var bamboo := StandardMaterial3D.new()
	bamboo.albedo_color = Color(0.55, 0.62, 0.36)
	bamboo.roughness = 0.8
	var pole := func(parent: Node3D, x: float, z: float, h: float) -> void:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.045
		cm.height = h
		cm.radial_segments = 8
		mi.mesh = cm
		mi.material_override = bamboo
		mi.position = Vector3(x, h / 2.0, z)
		parent.add_child(mi)
	var ob := _fest_root("obon")
	var bon := WorldBuilder.model_scene("P_chochin_bon")
	for x in [-20.0, -14.0, -8.0, -3.2, 3.2, 8.0, 14.0, 20.0]:
		var z := RIVER[0] - 1.6
		pole.call(ob, x, z, 2.1)
		var arm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.04, 0.5)
		arm.mesh = bm
		arm.material_override = bamboo
		arm.position = Vector3(x, 2.02, z + 0.22)
		ob.add_child(arm)
		wb.hang_chochin(bon, global_transform * Vector3(x, 2.0, z + 0.42), 0.0, ob)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.86, 0.66)
		l.light_energy = 0.9
		l.omni_range = 3.2
		l.position = Vector3(x, 1.6, z + 0.42)
		ob.add_child(l)
	var hb := _fest_root("hanabi")
	var xs := [-22.0, -13.0, -4.0, 4.0, 13.0, 22.0]
	for i in xs.size():
		pole.call(hb, xs[i], RIVER[0] - 2.4, 2.6)
	for i in xs.size() - 1:
		if absf(xs[i]) < 1.0 or (xs[i] < 0.0 and xs[i + 1] > 0.0):
			continue          # leave the path to the bridge open
		wb.lantern_string(global_transform * Vector3(xs[i], 2.55, RIVER[0] - 2.4), global_transform * Vector3(xs[i + 1], 2.55, RIVER[0] - 2.4), 7, hb)


func _decor() -> void:
	for d in DECOR:
		wb.spawn(d[0], Vector3(d[1], 0, d[2]), d[3], d[4], self, d[5])


func _grass() -> void:
	var g := GrassField.new()
	g.name = "Meadow"
	add_child(g)
	var avoid := [
		[-32.0, -1.2, 20.0, 1.8], [-1.4, 1.2, 1.4, 25.2], [-9.2, 24.3, 10.7, 26.5], [-12.8, -6.5, -5.2, -0.6],
		[9.6, -14.2, 15.0, -0.6], [-5.8, -9.8, 5.8, -1.3], [15.3, -9.6, 21.8, -2.1], [-22.2, -10.5, -17.3, -5.2],
		[-12.4, -10.0, -8.5, -6.4], [-11.9, 1.6, -8.1, 4.1], [5.4, 1.9, 9.4, 4.1], [3.0, 2.4, 5.6, 4.1],
		[Vector2(-15.5, 6.8), 1.5], [Vector2(9.6, 12.3), 1.3], [Vector2(8.8, 24.4), 1.3], [Vector2(-16.4, -1.9), 1.2],
		[Vector2(GATE_POS.x, GATE_POS.z), 2.2], [Vector2(-22.6, 1.9), 0.6], [Vector2(-7.2, -3.8), 1.2], [Vector2(-13.9, -4.9), 1.0],
		[Vector2(6.3, -5.3), 0.6], [Vector2(-6.6, 26.2), 1.2],
		[5.4, 4.4, 12.2, 11.6],        # mown patch behind the riverside bench: the fireworks camera sits here
	]
	var near := [[-30.0,-15.5,27.5,16.8]]
	var far := [[-30.0,17.2,27.5,30.5]]
	var height_fn: Callable = func(p:Vector2)->float:return LakesideLayout.height_at(p)
	var near_keep: Callable = func(p:Vector2)->bool:return p.y<LakesideLayout.river_z(p.x) and LakesideLayout.water_distance(p)>1.25
	var far_keep: Callable = func(p:Vector2)->bool:return p.y>LakesideLayout.river_z(p.x) and LakesideLayout.water_distance(p)>1.25
	var dry_keep: Callable = func(p:Vector2)->bool:return LakesideLayout.water_distance(p)>1.25
	var n := g.lawn(near,avoid,"meadow",6.0,7,0.0,height_fn,near_keep)
	n += g.lawn(far,avoid,"meadow",5.0,8,0.0,height_fn,far_keep)
	n += g.lawn([[-45.0, -24.0, -30.0, LANE_Z - LANE_BANK], [-45.0, LANE_Z + LANE_BANK, -30.0, 30.0],
			[-30.0, -24.0, 27.5, -15.5]], [], "meadow", 1.4, 9)
	# tall grass along both river banks, parted by the bridge
	var banks := [[-30.0,10.5,27.5,24.5]]
	var bank_keep: Callable = func(p:Vector2)->bool:return LakesideLayout.water_distance(p)>1.2 and LakesideLayout.water_distance(p)<2.15 and p.distance_to(LakesideLayout.SPOTS.fish_river.stand)>1.3
	n += g.lawn(banks,[[-1.6,0,1.6,40.0]],"tall",4.5,10,0.0,height_fn,bank_keep)
	var fl := g.scatter(near+far,.16,avoid,GrassField.MIX_FLOWERS,Vector2(.24,.42),11,0.0,height_fn,dry_keep)
	fl += g.scatter(banks,.35,[[-1.6,0,1.6,40.0]],GrassField.MIX_EDGE,Vector2(.5,.85),12,0.0,height_fn,bank_keep)
	print("GRASS farm clumps ", n, " flowers ", fl)


func float_lantern(from_bridge: bool) -> void:
	if fx:
		fx.float_lantern(from_bridge)

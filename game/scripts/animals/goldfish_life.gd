extends Node3D
## One caught fish in the existing ceramic bowl; geometry follows its save flag.
var phase: float = 0.0
var water_y: float
var swim_radius: float
var centre := Vector3.ZERO
var fish: Node3D
var tail: Node3D
var water: MeshInstance3D
var fish_length: float = .075

func setup(bowl: Node3D) -> void:
	var bounds: AABB = WorldBuilder.local_aabb(bowl)
	centre = bounds.get_center()
	water_y = bounds.position.y + bounds.size.y * .70
	# The shipping bowl's inner section is 254–256 mm at this height;
	# extend the surface slightly into that wall, below its 264 mm outer skin.
	swim_radius = minf(bounds.size.x, bounds.size.z) * .47
	set_meta("model_part", "home_goldfish_life")
	water = MeshInstance3D.new()
	water.name = "BowlWater"
	water.set_meta("model_part", "home_goldfish_water")
	var disc := CylinderMesh.new()
	disc.top_radius = swim_radius
	disc.bottom_radius = swim_radius
	disc.height = .001
	disc.radial_segments = 48
	water.mesh = disc
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(.40, .76, .88, .28)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	water_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water.material_override = water_material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(centre.x, water_y, centre.z)
	add_child(water)
	fish = Node3D.new()
	fish.name = "CaughtGoldfish"
	fish.set_meta("model_part", "caught_goldfish")
	add_child(fish)
	var orange: StandardMaterial3D = _mat(Color(.94, .29, .09))
	var cream: StandardMaterial3D = _mat(Color(1.0, .88, .63))
	var black: StandardMaterial3D = _mat(Color(.045, .045, .07))
	_ellipsoid("Body", Vector3(.013, .014, .029), Vector3.ZERO, orange, fish)
	_ellipsoid("Belly", Vector3(.0118, .004, .023), Vector3(0, -.010, .001), cream, fish)
	for side: float in [-1.0, 1.0]:
		_ellipsoid("Eye_%d" % int(side), Vector3(.0022, .0024, .0024), Vector3(side * .011, .004, .018), black, fish)
		_ellipsoid("EyeGlint_%d" % int(side), Vector3(.0008, .0008, .0008), Vector3(side * .0126, .005, .019), cream, fish)
	tail = Node3D.new()
	tail.name = "Tail"
	tail.position.z = -.026
	fish.add_child(tail)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		for segment: int in range(6):
			var a: float = float(segment) / 6.0
			var b: float = float(segment + 1) / 6.0
			var first: Vector3 = Vector3(side * sin(a * PI * .80) * .023, sin(a * PI) * .004, -.012 - a * .021)
			var second: Vector3 = Vector3(side * sin(b * PI * .80) * .023, sin(b * PI) * .004, -.012 - b * .021)
			for vertex: Vector3 in [Vector3.ZERO, first, second]: builder.add_vertex(vertex)
	builder.generate_normals()
	var fin := MeshInstance3D.new()
	fin.name = "CaudalFin"
	fin.mesh = builder.commit()
	fin.material_override = _mat(Color(1.0, .48, .23))
	fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tail.add_child(fin)
	_update_pose()
	visible = bool(GameState.flags.get("goldfish_home", false))

func _mat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1
	return material

func _ellipsoid(label: String, radii: Vector3, at: Vector3, material: Material, parent: Node3D) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 16
	mesh.rings = 8
	node.mesh = mesh
	node.scale = radii
	node.position = at
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

func _process(delta: float) -> void:
	visible = bool(GameState.flags.get("goldfish_home", false))
	if not is_visible_in_tree() or fish == null: return
	phase += delta
	_update_pose()

func _update_pose() -> void:
	var angle: float = phase * .65
	fish.position = Vector3(centre.x + cos(angle) * swim_radius * .43,
		water_y - .045 + sin(phase * 1.1) * .006, centre.z + sin(angle) * swim_radius * .32)
	fish.rotation.y = atan2(-sin(angle) * .43, cos(angle) * .32)
	tail.rotation.y = sin(phase * 8) * .32

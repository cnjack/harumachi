extends RefCounted
## Small deterministic anime silhouettes; flight, timing and RNG remain in AmbientLife.

static func material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	result.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.roughness = 1
	if transparent: result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return result

static func ellipsoid(parent: Node3D, label: String, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 12
	mesh.rings = 6
	node.mesh = mesh
	node.scale = size
	node.position = at
	node.material_override = material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func butterfly_body(parent: Node3D) -> void:
	var color := Color(.22, .18, .14)
	ellipsoid(parent, "Body", Vector3.ZERO, Vector3(.0026, .0028, .015), color)
	ellipsoid(parent, "Head", Vector3(0, .001, .015), Vector3(.0035, .0035, .0035), color)
	for side: float in [-1.0, 1.0]:
		var start := Vector3(side * .0015, .002, .017)
		var end := Vector3(side * .008, .005, .030)
		var antenna := MeshInstance3D.new()
		antenna.name = "Antenna_%d" % int(side)
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = .00045
		cylinder.bottom_radius = .0005
		cylinder.height = start.distance_to(end)
		cylinder.radial_segments = 6
		antenna.mesh = cylinder
		antenna.position = (start + end) * .5
		antenna.basis = Basis(Quaternion(Vector3.UP, (end - start).normalized()))
		antenna.material_override = material(color)
		antenna.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(antenna)
		ellipsoid(parent, "AntennaTip_%d" % int(side), end, Vector3.ONE * .0009, color)

static func butterfly_wing(side: float, color: Color) -> MeshInstance3D:
	var outline: Array[Vector2] = []
	var curves: Array[Array] = [
		[Vector2.ZERO,Vector2(.016,.045),Vector2(.053,.055),Vector2(.052,.028)],
		[Vector2(.052,.028),Vector2(.052,.012),Vector2(.040,.004),Vector2(.034,-.003)],
		[Vector2(.034,-.003),Vector2(.055,-.020),Vector2(.030,-.050),Vector2(.015,-.030)],
		[Vector2(.015,-.030),Vector2(.008,-.020),Vector2(.004,-.010),Vector2.ZERO],
	]
	for curve: Array in curves:
		for sample: int in range(8):
			var t: float = float(sample) / 8.0
			var inverse: float = 1.0 - t
			outline.append(((curve[0] as Vector2)*inverse*inverse*inverse + (curve[1] as Vector2)*3*inverse*inverse*t + (curve[2] as Vector2)*3*inverse*t*t + (curve[3] as Vector2)*t*t*t)*.8)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in outline.size():
		var a: Vector2 = outline[index]
		var b: Vector2 = outline[(index + 1) % outline.size()]
		builder.set_color(color)
		for point: Vector2 in [Vector2.ZERO, a * .94, b * .94]: builder.add_vertex(Vector3(point.x * side, 0, point.y))
		builder.set_color(Color(.37, .31, .25))
		for point: Vector2 in [a*.94,a,b,b*.94,a*.94,b]: builder.add_vertex(Vector3(point.x * side, .0001, point.y))
	# Fine veins are geometry, so a backlit wing still has a readable shape.
	for tip: Vector2 in [Vector2(.033,.024),Vector2(.035,.009),Vector2(.026,-.020)]:
		var normal: Vector2 = Vector2(-tip.y, tip.x).normalized() * .00035
		builder.set_color(Color(.58,.50,.37))
		for point: Vector2 in [Vector2.ZERO,tip+normal,tip-normal]: builder.add_vertex(Vector3(point.x*side,.0003,point.y))
	builder.generate_normals()
	var node := MeshInstance3D.new()
	node.name = "ButterflyWing_%d" % int(side)
	node.mesh = builder.commit()
	var wing_material: StandardMaterial3D = material(Color.WHITE)
	wing_material.vertex_color_use_as_albedo = true
	node.material_override = wing_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func dragonfly_body(parent: Node3D, color: Color) -> void:
	var body := Node3D.new()
	body.name = "Body"
	parent.add_child(body)
	ellipsoid(body,"Thorax",Vector3(0,0,.009),Vector3(.005,.005,.010),color.darkened(.2))
	for index: int in range(7):
		var radius: float = .0032 - float(index) * .00023
		ellipsoid(body,"Abdomen_%d"%index,Vector3(0,0,-.004-float(index)*.007),Vector3(radius,radius,.0045),color if index%2==0 else color.darkened(.25))
	var eyes := Node3D.new()
	eyes.name = "Eyes"
	parent.add_child(eyes)
	for side: float in [-1.0,1.0]:
		ellipsoid(eyes,"Eye_%d"%int(side),Vector3(side*.0038,.001,.020),Vector3(.0038,.0038,.004),Color(.24,.27,.20))

static func dragonfly_wing(side: float) -> MeshInstance3D:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(24):
		var a: float = float(index) / 24.0 * TAU
		var b: float = float(index+1) / 24.0 * TAU
		var first := Vector3(side*(.035+.035*cos(a)),0,sin(a)*.007)
		var second := Vector3(side*(.035+.035*cos(b)),0,sin(b)*.007)
		builder.set_color(Color(.84,.91,.94,.48))
		for point: Vector3 in [Vector3(side*.035,0,0),first*.96,second*.96]: builder.add_vertex(point)
		builder.set_color(Color(.43,.51,.52,.72))
		for point: Vector3 in [first*.96,first,second,second*.96,first*.96,second]: builder.add_vertex(point)
	for index: int in range(5):
		var across: float = .012+float(index)*.010
		var width: float = sqrt(maxf(0,1-pow((across-.035)/.035,2)))*.0065
		builder.set_color(Color(.43,.51,.52,.60))
		for point: Vector3 in [Vector3(side*(across-.0003),.0001,-width),Vector3(side*(across+.0003),.0001,width),Vector3(side*(across-.0003),.0001,width)]: builder.add_vertex(point)
	builder.generate_normals()
	var node := MeshInstance3D.new()
	node.name = "DragonflyWing_%d" % int(side)
	node.mesh = builder.commit()
	var wing_material: StandardMaterial3D = material(Color.WHITE,true)
	wing_material.vertex_color_use_as_albedo = true
	node.material_override = wing_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

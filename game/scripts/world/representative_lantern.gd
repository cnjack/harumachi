class_name RepresentativeLantern
extends Node3D
## Procedural greybox with crisp colours; the work identity survives each scene use.
var rotating_part: Node3D
var lamp: OmniLight3D
var caption: Label3D

func build(stage: int, pattern: String, purpose: String, angle: float = 0.0, support_y: float = -1.0) -> void:
	set_meta("work_id", str(WorkshopProject.state().work_id))
	var cedar := StandardMaterial3D.new()
	cedar.albedo_color = Color(.43, .28, .15)
	cedar.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	cedar.roughness = 1.0
	for level: float in [-.22, .22]:
		var ring := TorusMesh.new()
		ring.inner_radius = .15
		ring.outer_radius = .17
		ring.rings = 24
		ring.ring_segments = 6
		_mesh(ring, cedar, Vector3(0, level, 0))
	for index in 12:
		var rib := BoxMesh.new()
		rib.size = Vector3(.015, .44, .015)
		var theta: float = TAU * index / 12.0
		_mesh(rib, cedar, Vector3(sin(theta) * .155, 0, cos(theta) * .155))
	if stage >= 2:
		var paper := StandardMaterial3D.new()
		paper.albedo_color = Color(.98, .9, .66) if pattern == "leaf" else Color(.76, .88, .98)
		paper.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		paper.emission_enabled = true
		paper.emission = Color(.8, .43, .13)
		paper.emission_energy_multiplier = .25
		var shell := CylinderMesh.new()
		shell.top_radius = .151
		shell.bottom_radius = .151
		shell.height = .4
		shell.radial_segments = 24
		_mesh(shell, paper, Vector3.ZERO)
		var ink := StandardMaterial3D.new()
		ink.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		ink.albedo_color = Color(.27, .43, .26) if pattern == "leaf" else Color(.21, .43, .68)
		if pattern == "leaf":
			for index in 2:
				var leaf := SphereMesh.new()
				leaf.radius = .035
				leaf.height = .09
				leaf.radial_segments = 12
				leaf.rings = 6
				var node: MeshInstance3D = _mesh(leaf, ink, Vector3(-.04 + index * .06, .1, .156))
				node.scale = Vector3(.65, 1.0, .12)
				node.rotation.z = -.55 if index == 0 else .55
		else:
			for row in 2:
				var stroke := ImmediateMesh.new()
				stroke.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
				for index in 21:
					var x: float = -.095 + .0095 * index
					stroke.surface_add_vertex(Vector3(x, .075 + row * .035 + sin(index * PI / 10.0) * .012, .162))
				stroke.surface_end()
				_mesh(stroke, ink, Vector3.ZERO)
		caption = Label3D.new()
		caption.font = load("res://assets/fonts/LXGWWenKai-Medium.ttf")
		caption.font_size = 54
		caption.pixel_size = .00125
		caption.outline_size = 0
		caption.modulate = Color(.17, .27, .3)
		caption.text = "树下见" if purpose == "meeting" else "入口 →"
		caption.position = Vector3(0, 0, .157)
		add_child(caption)
	if stage >= 3:
		var cord := BoxMesh.new()
		var length: float = maxf(.05, support_y - global_position.y - .22) if support_y >= 0 else .3
		cord.size = Vector3(.012, length, .012)
		_mesh(cord, cedar, Vector3(0, .22 + length / 2.0, 0))
		var body := StaticBody3D.new()
		body.collision_layer = WorldBuilder.L_SOLID
		body.collision_mask = 0
		body.set_meta("model_part", true)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(.34, .46, .34)
		shape.shape = box
		body.add_child(shape)
		add_child(body)
	else:
		rotating_part = Node3D.new()
		rotating_part.name = "AssemblyPart"
		add_child(rotating_part)
		var amber := StandardMaterial3D.new()
		amber.albedo_color = Color(.95, .51, .12)
		var part := BoxMesh.new()
		part.size = Vector3(.035, .46, .035)
		_mesh(part, amber, Vector3(0, 0, .19), rotating_part)
		rotating_part.rotation_degrees.y = angle
		var green := StandardMaterial3D.new()
		green.albedo_color = Color(.26, .68, .47)
		var socket := BoxMesh.new()
		socket.size = Vector3(.05, .07, .05)
		var target: float = deg_to_rad(float(WorkshopProject.TARGETS[mini(stage, 2)]))
		_mesh(socket, green, Vector3(sin(target) * .19, .21, cos(target) * .19))
	lamp = OmniLight3D.new()
	lamp.light_color = Color(1, .66, .32)
	lamp.light_energy = .65 if stage >= 3 else 0.0
	lamp.omni_range = 3.0
	add_child(lamp)

func _mesh(mesh: Mesh, material: Material, at: Vector3, parent: Node3D = null) -> MeshInstance3D:
	if parent == null: parent = self
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node

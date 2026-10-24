class_name StreetTree
extends RefCounted
## A street-sized zelkova with an actual opening in the paving and rooted soil.
const MODEL := "T12_street_zelkova"
const CENTRE := Vector2(-18.0, -16.2)
const SOIL_Y := -.012
const HOLE := Rect2(-18.62, -16.82, 1.24, 1.24)
const OUTER_HALF := .77


## Split the ground patch instead of covering intact paving with a brown disc.
static func ground_patches(rect: Array) -> Array[Array]:
	var source := Rect2(float(rect[0]), float(rect[1]), float(rect[2])-float(rect[0]), float(rect[3])-float(rect[1]))
	if not source.intersects(HOLE): return [rect]
	var cut: Rect2 = source.intersection(HOLE)
	var parts: Array[Array] = []
	for part: Rect2 in [
		Rect2(source.position, Vector2(source.size.x, cut.position.y-source.position.y)),
		Rect2(Vector2(source.position.x, cut.end.y), Vector2(source.size.x, source.end.y-cut.end.y)),
		Rect2(Vector2(source.position.x, cut.position.y), Vector2(cut.position.x-source.position.x, cut.size.y)),
		Rect2(Vector2(cut.end.x, cut.position.y), Vector2(source.end.x-cut.end.x, cut.size.y))]:
		if part.size.x > .0001 and part.size.y > .0001:
			parts.append([part.position.x, part.position.y, part.end.x, part.end.y])
	return parts


static func plant(world: WorldBuilder, tree: Node3D) -> void:
	var bed := Node3D.new()
	bed.name = "StreetTreeBed"
	bed.position = Vector3(CENTRE.x, 0, CENTRE.y)
	world.add_child(bed)
	var soil := MeshInstance3D.new()
	soil.name = "RecessedSoil"
	var surface := PlaneMesh.new()
	surface.size = HOLE.size
	soil.mesh = surface
	soil.position.y = SOIL_Y
	soil.material_override = JapaneseArchitecture._flat(Color(.22, .155, .09))
	bed.add_child(soil)
	# Eight short stones read as an open planted pit. Their bevel is real mesh.
	for side: int in 4:
		for half: int in 2:
			var stone := MeshInstance3D.new()
			stone.name = "Coping_%d_%d" % [side, half]
			stone.mesh = _coping_mesh(Vector3(.762, .074, .15), .018)
			stone.rotation.y = side * PI * .5
			var local := Vector3((float(half)-.5)*.77, .026, -.695)
			stone.position = Basis(Vector3.UP, side*PI*.5)*local
			stone.material_override = JapaneseArchitecture._flat(Color(.57, .56, .49) if (side+half)%2 else Color(.63, .61, .53))
			bed.add_child(stone)
	WorldBuilder.rest_on(tree, SOIL_Y, .008)
	WorldBuilder.make_sway(tree, .008, .8)
	var body := StaticBody3D.new()
	body.name = "PlantedRootCollision"
	body.collision_layer = WorldBuilder.L_SOLID
	body.collision_mask = 0
	body.set_meta("model_part", MODEL)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = .24
	cylinder.height = 1.8
	shape.shape = cylinder
	shape.position.y = .9
	body.add_child(shape)
	tree.add_child(body)


static func _coping_mesh(size: Vector3, bevel: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x: float = size.x*.5
	var z: float = size.z*.5
	var top: float = size.y*.5
	var bottom: float = -size.y*.5
	var lower: Array[Vector3] = [Vector3(-x,bottom,-z), Vector3(x,bottom,-z), Vector3(x,bottom,z), Vector3(-x,bottom,z)]
	var shoulder: Array[Vector3] = [Vector3(-x,top-bevel,-z), Vector3(x,top-bevel,-z), Vector3(x,top-bevel,z), Vector3(-x,top-bevel,z)]
	var crown: Array[Vector3] = [Vector3(-x+bevel,top,-z+bevel), Vector3(x-bevel,top,-z+bevel), Vector3(x-bevel,top,z-bevel), Vector3(-x+bevel,top,z-bevel)]
	for side: int in 4:
		var following: int = (side+1)%4
		_quad(st, lower[following], lower[side], shoulder[side], shoulder[following])
		_quad(st, shoulder[following], shoulder[side], crown[side], crown[following])
	_quad(st, crown[3], crown[2], crown[1], crown[0])
	_quad(st, lower[0], lower[1], lower[2], lower[3])
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.set_normal((b-a).cross(c-a).normalized())
	# Godot uses clockwise front faces; normals still point out of the stone.
	for point: Vector3 in [a, c, b, a, d, c]: st.add_vertex(point)

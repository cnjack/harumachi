class_name Hyper3DFurniture
extends RefCounted
## Reuse inspected generated furniture while retaining real support parts and UVs.
static var _fitted: Dictionary = {}

static func _axis(value: float, source: float, target: float, band: float) -> Vector2:
	if target < band * 2.2:
		return Vector2(value * target / source, target / source)
	var inner: float = source * .5 - band
	var next_inner: float = target * .5 - band
	if absf(value) > inner:
		return Vector2(signf(value) * (next_inner + absf(value) - inner), 1.)
	return Vector2(value * next_inner / inner, next_inner / inner)

static func _height(value: float, source: float, target: float, lower: bool) -> Vector2:
	if lower and value <= .2225: return Vector2(value, 1.)
	var start: float = .2225 if lower else 0.
	var ratio: float = (target - start) / (source - start)
	return Vector2(start + (value - start) * ratio, ratio)

static func _fit(source: Mesh, id: String, width: float, depth: float, height: float, origin_y: float=0.) -> ArrayMesh:
	var key: String = "%d/%s/%.5f/%.5f/%.5f/%.5f" % [source.get_instance_id(), id, width, depth, height, origin_y]
	if _fitted.has(key): return _fitted[key] as ArrayMesh
	var size: Vector3 = {"HFF05_utility_stand":Vector3(.9,.84,.6), "HFF04_low_table":Vector3(1.45,.43,.85), "HFF06_indoor_bench":Vector3(1.55,.43,.52)}[id]
	var result := ArrayMesh.new()
	for surface: int in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		for index: int in vertices.size():
			var point: Vector3 = vertices[index]
			var x: Vector2 = _axis(point.x, size.x, width, minf(.13, size.x * .2))
			var z: Vector2 = _axis(point.z, size.z, depth, minf(.10, size.z * .2))
			var y: Vector2 = _height(point.y, size.y, height, id == "HFF05_utility_stand")
			vertices[index] = Vector3(x.x, y.x-origin_y, z.x)
			if index < normals.size(): normals[index] = (normals[index] / Vector3(x.y, y.y, z.y)).normalized()
			if tangents.size() >= (index + 1) * 4:
				var tangent := (Vector3(tangents[index*4], tangents[index*4+1], tangents[index*4+2]) * Vector3(x.y, y.y, z.y)).normalized()
				tangents[index*4] = tangent.x; tangents[index*4+1] = tangent.y; tangents[index*4+2] = tangent.z
		arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
		if not tangents.is_empty(): arrays[Mesh.ARRAY_TANGENT] = tangents
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, source.surface_get_material(surface))
	_fitted[key] = result
	return result

static func bench(parent: Node3D, label: String, at: Vector3, width: float, depth: float, height: float) -> MeshInstance3D:
	var ancestor: Node = parent
	while ancestor != null and not ancestor is WorldBuilder: ancestor = ancestor.get_parent()
	if ancestor == null: return null
	var id: String = "HFF05_utility_stand"
	if height < .50:
		id = "HFF06_indoor_bench" if ("Bench" in label or "Seat" in label or "Step" in label) and depth < .75 else "HFF04_low_table"
	var instance: Node3D = (ancestor as WorldBuilder).spawn(id, at, 0, 0, parent)
	if instance == null: return null
	instance.name = label + "Fixture"
	# Long desks should extend the authored board span, not stretch a shallow
	# table's depth fourfold. Rotate the original geometry/UVs together.
	var turn: bool=depth>width*1.15
	var fitted_width: float=depth if turn else width
	var fitted_depth: float=width if turn else depth
	if turn:instance.rotation.y=PI*.5
	var top: MeshInstance3D
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(instance):
		var origin_y: float=height-.0275 if str(mesh.name)=="Top" else (.20 if str(mesh.name)=="LowerBoard" else 0.)
		mesh.mesh = _fit(mesh.mesh, id, fitted_width, fitted_depth, height, origin_y)
		mesh.position.y=origin_y
		mesh.material_override = null
		for surface: int in mesh.mesh.get_surface_count(): mesh.set_surface_override_material(surface, null)
		if str(mesh.name) == "Top": top = mesh; mesh.name = label
		elif str(mesh.name) == "LowerBoard": mesh.name = label + "LowerBoard"
	FurnitureWoodFinish.apply(instance, id)
	if top == null: return null
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(instance):
		for surface: int in mesh.mesh.get_surface_count():
			var finish: ShaderMaterial = mesh.get_active_material(surface) as ShaderMaterial
			if finish != null:
				finish.set_shader_parameter("use_profile", FurnitureWoodFinish.profile_for(label))
				finish.set_shader_parameter("wear_strength", .65 if FurnitureWoodFinish.profile_for(label) == 2 else .46)
	top.material_override = top.get_active_material(0)
	top.set_meta("furniture_wood_board", true)
	top.set_meta("furniture_wood_profile", FurnitureWoodFinish.profile_for(label))
	var body := StaticBody3D.new(); body.collision_layer = WorldBuilder.L_SOLID; body.collision_mask = 0; body.set_meta("model_part", true)
	var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = top.get_aabb().size
	collision.shape = shape; collision.position = top.get_aabb().get_center(); body.add_child(collision); top.add_child(body)
	instance.set_meta("hyper3d_reuse", label)
	return top

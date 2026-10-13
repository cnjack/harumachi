extends Node3D
## Four small shallow-water fish reuse one complete fish from the accepted tank.
## Fixed looping paths never reset or teleport; no collision, gameplay or save state.
const COUNT := 4
const SOURCE_CENTER := Vector3(-.47,.385,.27)
var elapsed: float=0.0
var animals: Array[Node3D]=[]
var finishes: Array[ShaderMaterial]=[]
var world: WorldBuilder
var _night_amount: float=-1.0

func build(owner_world: WorldBuilder) -> void:
	world=owner_world;name="RiverFish"
	var source: Node3D=world.spawn("G02_goldfish_tank",Vector3.ZERO,0.0,0,self)
	if source==null:return
	var parts: Array[Dictionary]=[]
	var retained: int=0
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(source):
		if not (str(mesh.name).begins_with("Goldfish") or str(mesh.name).begins_with("FishEyes")):continue
		var relative: Transform3D=source.global_transform.affine_inverse()*mesh.global_transform
		var copied:=SurfaceTool.new();copied.begin(Mesh.PRIMITIVE_TRIANGLES)
		var triangles: int=0
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array=mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var count: int=(indices.size() if not indices.is_empty() else vertices.size())/3
			for triangle: int in count:
				var points: Array[Vector3]=[]
				var face_normals: Array[Vector3]=[]
				for corner: int in 3:
					var index: int=indices[triangle*3+corner] if not indices.is_empty() else triangle*3+corner
					points.append(relative*vertices[index]-SOURCE_CENTER)
					face_normals.append((relative.basis*normals[index]).normalized())
				if (points[0]+points[1]+points[2]).length()/3.0>.14:continue
				for corner: int in 3:
					copied.set_normal(face_normals[corner]);copied.add_vertex(points[corner])
				triangles+=1
		if triangles==0:continue
		parts.append({"mesh":copied.commit(),"eye":str(mesh.name).begins_with("FishEyes")});retained+=triangles
	source.free()
	set_meta("reused_source_triangles",retained);set_meta("fish_count",COUNT)
	for index: int in COUNT:
		var fish:=Node3D.new();fish.name="RiverFish_%d"%index
		fish.set_meta("model_part","river_fish");add_child(fish);animals.append(fish)
		fish.scale=Vector3.ONE*(1.05+float(index%3)*.13)
		for part_index: int in parts.size():
			var node:=MeshInstance3D.new();node.name="RetainedTankPart_%d"%part_index
			node.mesh=parts[part_index].mesh
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var material:=ShaderMaterial.new();material.shader=load("res://shaders/river_fish.gdshader")
			material.set_shader_parameter("body_color",Color(.055,.07,.08) if parts[part_index].eye else (Color(.41,.48,.37) if index%2==0 else Color(.49,.59,.58)))
			material.set_shader_parameter("phase",float(index)*1.7)
			node.material_override=material;fish.add_child(node);finishes.append(material)
	_update_pose()

static func sample_position(index: int,time_value: float) -> Vector3:
	var angle: float=time_value*(.32+float(index)*.018)+float(index)*1.37
	var center:=Vector3(7.2+float(index)*.55,LakesideLayout.WATER_Y-.16,16.05+float(index%2)*.24)
	return center+Vector3(cos(angle)*(.83+index*.06),sin(time_value*.8+index)*.012,sin(angle)*.30)

func _process(delta: float) -> void:
	if not is_visible_in_tree():return
	elapsed+=delta;_update_pose()

func _update_pose() -> void:
	var night: float=clampf(float(world.look.get("night",0.0)),0.0,1.0)
	if not is_equal_approx(_night_amount,night):
		for material: ShaderMaterial in finishes:material.set_shader_parameter("night_amount",night)
		_night_amount=night
	for index: int in animals.size():
		var fish: Node3D=animals[index]
		fish.position=sample_position(index,elapsed)
		var tangent: Vector3=sample_position(index,elapsed+.04)-fish.position
		fish.rotation.y=atan2(-tangent.z,tangent.x)

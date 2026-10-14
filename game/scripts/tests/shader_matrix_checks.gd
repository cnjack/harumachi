extends RefCounted
## Inspect actual active material bindings, not source-code setter strings.
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t=runner
	main=runner.main

func check(label: String,ok: bool,detail: String="") -> void:
	t.check("SHADER_MATRICES",label,ok,detail)

func declarations(shader: Shader) -> Dictionary:
	var result: Dictionary={}
	for item: Dictionary in shader.get_shader_uniform_list():result[str(item.name)]=item
	return result

func model_root(mesh: MeshInstance3D) -> Node3D:
	var node: Node=mesh
	while node!=null:
		if node is Node3D and node.has_meta("model_id"):return node as Node3D
		node=node.get_parent()
	return null

func parameter_bool(material: ShaderMaterial,names: Dictionary,key: String) -> bool:
	if not names.has(key):return false
	var value: Variant=material.get_shader_parameter(key)
	return bool(value) if value!=null else false

func fixture() -> Node3D:
	# Use a real imported timber asset and the original SurfaceFinish.apply path.
	# Its nested local transform makes identity an observably wrong result even
	# when an imported world's other meshes happen to have identity part poses.
	var parent:=Node3D.new()
	parent.name="ShaderMatrixImportedTimberFixture"
	parent.set_meta("model_id","W13_cedar_worktable")
	main.add_child(parent)
	parent.position=Vector3(43,1.2,-27)
	parent.rotation=Vector3(.05,-.41,.03)
	parent.visible=false
	var scene: PackedScene=WorldBuilder.model_scene("W13_cedar_worktable")
	if scene==null:return parent
	var asset: Node3D=scene.instantiate() as Node3D
	parent.add_child(asset)
	if asset.has_meta("model_id"):asset.remove_meta("model_id")
	asset.position=Vector3(.23,.11,-.17)
	asset.rotation=Vector3(.17,.31,-.08)
	asset.scale=Vector3(.90,1.10,.95)
	SurfaceFinish.apply(parent,"W13_cedar_worktable")
	return parent

func run() -> void:
	var imported_fixture: Node3D=fixture()
	var type_bad: Array[String]=[]
	var geometry_bad: Array[String]=[]
	var bindings:=0
	var non_identity:=0
	var pure_timber:=0
	var categories: Dictionary={}
	var unique: Dictionary={}
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(main):
		if mesh.mesh==null:continue
		for surface: int in mesh.mesh.get_surface_count():
			var material: ShaderMaterial=mesh.get_active_material(surface) as ShaderMaterial
			if material==null or material.shader==null:continue
			var names: Dictionary=declarations(material.shader)
			if not names.has("part_transform"):continue
			bindings+=1
			unique[material.get_instance_id()]=true
			var path: String=material.shader.resource_path.get_file()
			var kind_value: Variant=material.get_shader_parameter("finish_kind") if names.has("finish_kind") else null
			var kind: int=int(kind_value) if kind_value!=null else (0 if names.has("finish_kind") else -1)
			var measured_timber: bool=path=="painted_finish.gdshader" and parameter_bool(material,names,"timber_detail") and kind!=4
			var role: String=path
			if path=="painted_finish.gdshader":
				role="notice_kind4" if kind==4 else ("timber_measurement_space" if measured_timber else "original_surface_finish_apply")
			elif path in ["sign_support_refined.gdshader","direction_support.gdshader"]:role="direction_or_sign_support"
			categories[role]=int(categories.get(role,0))+1
			var label: String="%s surface%d %s"%[mesh.get_path(),surface,role]
			var value: Variant=material.get_shader_parameter("part_transform")
			if not value is Projection:
				type_bad.append("%s stored%s"%[label,type_string(typeof(value))])
				geometry_bad.append(label+" has no usable Projection")
				continue
			var actual: Projection=value as Projection
			var expected_transform:=Transform3D.IDENTITY
			var root: Node3D=model_root(mesh)
			if measured_timber:
				pure_timber+=1
			elif root==null:
				geometry_bad.append(label+" has no nearest model_id root")
				continue
			else:expected_transform=root.global_transform.affine_inverse()*mesh.global_transform
			var expected:=Projection(expected_transform)
			var maximum_error:=0.0
			var identity_error:=0.0
			for column: int in 4:
				for row: int in 4:
					maximum_error=maxf(maximum_error,absf(actual[column][row]-expected[column][row]))
					identity_error=maxf(identity_error,absf(expected[column][row]-Projection.IDENTITY[column][row]))
			if identity_error>.000001:non_identity+=1
			var box: AABB=mesh.get_aabb()
			var point: Vector3=box.get_center()+box.size*Vector3(.137,-.091,.113)
			var mapped: Vector4=actual*Vector4(point.x,point.y,point.z,1)
			var target: Vector3=point if measured_timber else root.to_local(mesh.to_global(point))
			var point_error: float=Vector3(mapped.x,mapped.y,mapped.z).distance_to(target)
			var returned: Vector4=actual.inverse()*mapped
			var round_trip: float=(mesh.global_basis*(Vector3(returned.x,returned.y,returned.z)-point)).length()
			if maximum_error>.00001 or point_error>.0002 or round_trip>.0002 or absf(mapped.w-1.0)>.00001:
				geometry_bad.append("%s matrix%.8f point%.8f roundtrip%.8f"%[label,maximum_error,point_error,round_trip])
	var required: Array[String]=["notice_kind4","direction_or_sign_support","chalk_face.gdshader","public_facade_finish.gdshader","original_surface_finish_apply","timber_measurement_space"]
	for role: String in required:
		if int(categories.get(role,0))==0:geometry_bad.append("missing actual material family "+role)
	check("every active part_transform mat4 stores a Projection including original SurfaceFinish",bindings>0 and type_bad.is_empty(),str({"bindings":bindings,"unique_materials":unique.size(),"bad":type_bad}))
	check("all16matrix elements and point round trips match real model space with nonidentity coverage",bindings>0 and non_identity>0 and pure_timber>0 and geometry_bad.is_empty(),str({"categories":categories,"non_identity":non_identity,"intentional_identity_timber":pure_timber,"bad":geometry_bad}))
	check_rotated_cafe_grain()
	imported_fixture.free()

func check_rotated_cafe_grain() -> void:
	# These two original Cedar backs are .48m wide along meshX and yawed+/-90deg.
	# Their rendered width lies along the parent table's Z. Assert the actual
	# active material axis2 directly; do not call/reproduce the production selector.
	var samples: Array[Dictionary]=[]
	var found: Dictionary={}
	var correct:=true
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(main):
		if str(mesh.name) not in ["ChairLeftBack","ChairRightBack"]:continue
		var cafe: Node3D=model_root(mesh)
		if cafe==null or cafe.get_meta("model_id","")!="P_cafe_table":continue
		found[str(mesh.name)]=true
		var local_size: Vector3=mesh.get_aabb().size
		var root_direction: Vector3=cafe.to_local(mesh.to_global(Vector3.RIGHT))-cafe.to_local(mesh.to_global(Vector3.ZERO))
		for surface: int in mesh.mesh.get_surface_count():
			var material: ShaderMaterial=mesh.get_active_material(surface) as ShaderMaterial
			var stored: Variant=material.get_shader_parameter("grain_axis") if material!=null else null
			var axis: int=int(stored) if stored!=null else -1
			var measured: bool=local_size.x>.44 and local_size.x<.50 and local_size.y>.28 and local_size.y<.42 and local_size.z>.03 and local_size.z<.16 and absf(absf(root_direction.z)-1.)<.0001 and absf(root_direction.x)<.0001
			correct=correct and measured and axis==2
			samples.append({"node":str(mesh.get_path()),"local_size":str(local_size),"root_mesh_x_direction":str(root_direction),"actual_grain_axis":axis,"required_axis":2})
	check("real rotated cafe left and right backs use rootZ grain rather than localX",correct and found.size()==2 and samples.size()>=2,str(samples))

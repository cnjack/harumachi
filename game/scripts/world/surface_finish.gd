class_name SurfaceFinish
extends RefCounted
const SHADER: Shader=preload("res://shaders/painted_finish.gdshader")
const GRAIN: Texture2D=preload("res://assets/textures/architecture/cedar-grain.jpg")

static func apply(root: Node3D,id: String) -> void:
	if id not in ["W13_cedar_worktable","I02_cake_showcase","P_long_table","P_offer_stand","J03_dining_set","J07_kotatsu","P_community_table","P_cafe_table","P_reading_chair","P_low_bookcase","P_coffee_station","W17_display_shelf","I05_bread_shelf","I04_shop_counter"]:return
	for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		for index: int in mesh.mesh.get_surface_count():
			var original: StandardMaterial3D=mesh.get_active_material(index) as StandardMaterial3D
			if original==null:continue
			var role: String=original.resource_name.to_lower()
			if role.begins_with("hyper3d_"):continue
			var kind: int=0
			if id=="J03_dining_set":kind=2
			elif id=="J07_kotatsu":kind=3
			elif role.contains("cloth"):kind=1
			elif not (role.contains("wood") or role.contains("oak") or role.contains("cedar")):continue
			var material:=ShaderMaterial.new();material.shader=SHADER
			material.set_shader_parameter("wood_tex",GRAIN)
			var part_transform: Transform3D=root.global_transform.affine_inverse()*mesh.global_transform
			material.set_shader_parameter("part_transform",Projection(part_transform))
			material.set_shader_parameter("finish_kind",kind)
			var extent: Vector3=(part_transform*mesh.get_aabb()).size
			material.set_shader_parameter("grain_axis",1 if extent.y>maxf(extent.x,extent.z) else (2 if extent.z>extent.x else 0))
			material.set_shader_parameter("base_color",Color(.76,.59,.40) if kind==0 or kind==2 else Color(.94,.90,.79))
			if role.contains("dark") or role.contains("plug"):material.set_shader_parameter("base_color",Color(.47,.34,.23))
			material.set_shader_parameter("has_original",original.albedo_texture!=null)
			material.set_shader_parameter("albedo_tex",original.albedo_texture)
			mesh.set_surface_override_material(index,material)
	root.set_meta("painted_finish",true)

static func refined_grain() -> Texture2D:
	return MaterialRefinement.texture("cedar_weathered.png","res://assets/textures/architecture/cedar-grain.jpg")

static func timber(bounds: AABB,colour: Color=Color(.68,.51,.32),axis: int=-1,horizontal_faces: bool=false,paint: float=0.0) -> ShaderMaterial:
	var material:=ShaderMaterial.new();material.shader=SHADER
	var extent: Vector3=bounds.size
	var long_axis: int=axis if axis>=0 else (1 if extent.y>maxf(extent.x,extent.z) else (2 if extent.z>extent.x else 0))
	material.set_shader_parameter("wood_tex",refined_grain())
	material.set_shader_parameter("part_transform",Projection(Transform3D.IDENTITY))
	material.set_shader_parameter("grain_axis",long_axis)
	material.set_shader_parameter("base_color",colour)
	material.set_shader_parameter("grain_strength",.62)
	material.set_shader_parameter("timber_detail",true)
	material.set_shader_parameter("horizontal_face_grain",horizontal_faces)
	material.set_shader_parameter("part_min",bounds.position)
	material.set_shader_parameter("part_size",bounds.size)
	material.set_shader_parameter("old_paint",paint)
	return material

static func surface_bounds(mesh: Mesh,index: int) -> AABB:
	var arrays: Array=mesh.surface_get_arrays(index)
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	if points.is_empty():return mesh.get_aabb()
	var box:=AABB(points[0],Vector3.ZERO)
	for point: Vector3 in points:box=box.expand(point)
	return box

static func decorate_timber(root: Node3D) -> void:
	# Select original wood surfaces only. Combined post/board meshes get independent grain axes.
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		if not mesh.visible:continue
		for index: int in mesh.mesh.get_surface_count():
			var source: Material=mesh.mesh.surface_get_material(index)
			var role: String=source.resource_name.to_lower() if source!=null else ""
			if not (role.contains("wood") or role.contains("cedar") or role.contains("oak")):continue
			var box: AABB=surface_bounds(mesh.mesh,index)
			var dark: bool=role.contains("dark")
			var horizontal: bool=box.size.x>box.size.y*1.4 and box.size.x>box.size.z
			var material: ShaderMaterial=timber(box,Color(.47,.37,.25) if dark else Color(.73,.56,.36),-1,horizontal)
			configure_components(material,mesh.mesh,index)
			mesh.set_surface_override_material(index,material)
			mesh.material_override=null
	root.set_meta("timber_parts_refined",true)

static func _component_root(parents: PackedInt32Array,index: int) -> int:
	var cursor: int=index
	while parents[cursor]!=cursor:cursor=parents[cursor]
	return cursor

static func timber_components(mesh: Mesh,surface: int) -> Array[AABB]:
	# Joined GLB parts share a surface. Weld positions only for measuring each connected timber;
	# vertex/index/UV/normal arrays and model bytes remain untouched.
	var arrays: Array=mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var parents:=PackedInt32Array();parents.resize(vertices.size())
	var welded: Dictionary={}
	for index: int in vertices.size():
		parents[index]=index
		var point: Vector3=vertices[index]*100000.
		var key:=Vector3i(roundi(point.x),roundi(point.y),roundi(point.z))
		if welded.has(key):parents[index]=int(welded[key])
		else:welded[key]=index
	if indices.is_empty():
		indices.resize(vertices.size())
		for index: int in vertices.size():indices[index]=index
	for triangle: int in range(0,indices.size(),3):
		if triangle+2>=indices.size():break
		var first: int=_component_root(parents,indices[triangle])
		for corner: int in [1,2]:
			var other: int=_component_root(parents,indices[triangle+corner]);parents[other]=first
	var boxes: Dictionary={}
	for index: int in vertices.size():
		var component: int=_component_root(parents,index)
		boxes[component]=(boxes[component] as AABB).expand(vertices[index]) if boxes.has(component) else AABB(vertices[index],Vector3.ZERO)
	var result: Array[AABB]=[]
	for box: AABB in boxes.values():result.append(box)
	return result

static func configure_components(material: ShaderMaterial,mesh: Mesh,surface: int) -> void:
	var boxes: Array[AABB]=timber_components(mesh,surface)
	if boxes.size()<=1 or boxes.size()>64:return
	var minima:=PackedVector4Array();var maxima:=PackedVector4Array()
	for box: AABB in boxes:
		var extent: Vector3=box.size
		var axis: int=1 if extent.y>maxf(extent.x,extent.z) else (2 if extent.z>extent.x else 0)
		minima.append(Vector4(box.position.x-.00002,box.position.y-.00002,box.position.z-.00002,float(axis)))
		maxima.append(Vector4(box.end.x+.00002,box.end.y+.00002,box.end.z+.00002,0.))
	material.set_shader_parameter("component_count",boxes.size())
	material.set_shader_parameter("component_min",minima)
	material.set_shader_parameter("component_max",maxima)
	material.set_meta("measured_timber_components",boxes.size())

static func notice_frame(root: Node3D) -> void:
	var poster: Node=root.get_node_or_null("Poster")
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		# The runtime notice is paper, printed artwork and fixings, not frame wood.
		if poster!=null and poster.is_ancestor_of(mesh):continue
		for index: int in mesh.mesh.get_surface_count():
			var original: StandardMaterial3D=mesh.get_active_material(index) as StandardMaterial3D
			if original==null or original.albedo_texture==null:continue
			var material: ShaderMaterial=timber(surface_bounds(mesh.mesh,index),Color(.61,.44,.28),0)
			material.set_shader_parameter("finish_kind",4)
			material.set_shader_parameter("part_transform",Projection(root.global_transform.affine_inverse()*mesh.global_transform))
			material.set_shader_parameter("has_original",true)
			material.set_shader_parameter("albedo_tex",original.albedo_texture)
			mesh.set_surface_override_material(index,material)
			mesh.material_override=null
	root.set_meta("notice_frame_refined",true)

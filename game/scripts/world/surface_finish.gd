class_name SurfaceFinish
extends RefCounted
const SHADER: Shader=preload("res://shaders/painted_finish.gdshader")
const GRAIN: Texture2D=preload("res://assets/textures/architecture/cedar-grain.jpg")

static func apply(root: Node3D,id: String) -> void:
	if id not in ["W13_cedar_worktable","I02_cake_showcase","P_long_table","P_offer_stand","J03_dining_set","J07_kotatsu"]:return
	for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		for index: int in mesh.mesh.get_surface_count():
			var original: StandardMaterial3D=mesh.get_active_material(index) as StandardMaterial3D
			if original==null:continue
			var role: String=original.resource_name.to_lower()
			var kind: int=0
			if id=="J03_dining_set":kind=2
			elif id=="J07_kotatsu":kind=3
			elif role.contains("cloth"):kind=1
			elif not (role.contains("wood") or role.contains("oak") or role.contains("cedar")):continue
			var material:=ShaderMaterial.new();material.shader=SHADER
			material.set_shader_parameter("wood_tex",GRAIN)
			material.set_shader_parameter("part_transform",root.global_transform.affine_inverse()*mesh.global_transform)
			material.set_shader_parameter("finish_kind",kind)
			var extent: Vector3=mesh.get_aabb().size
			material.set_shader_parameter("grain_axis",1 if extent.y>maxf(extent.x,extent.z) else (2 if extent.z>extent.x else 0))
			material.set_shader_parameter("base_color",Color(.76,.59,.40) if kind==0 or kind==2 else Color(.94,.90,.79))
			if role.contains("dark") or role.contains("plug"):material.set_shader_parameter("base_color",Color(.47,.34,.23))
			material.set_shader_parameter("has_original",original.albedo_texture!=null)
			material.set_shader_parameter("albedo_tex",original.albedo_texture)
			mesh.set_surface_override_material(index,material)
	root.set_meta("painted_finish",true)

class_name AnimalMotion
extends RefCounted
## Local anatomical motion on the original art; articulated wings are separate geometry.
var materials: Array[ShaderMaterial]=[]
var wings: Array[Node3D]=[]
var phase:=0.0
var kind:=0

func _init(model: Node3D, animal_kind: int) -> void:
	kind=animal_kind
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(model):
		for surface in mesh.mesh.get_surface_count():
			var source: Material=mesh.get_surface_override_material(surface)
			if source==null:source=mesh.mesh.surface_get_material(surface)
			if not source is StandardMaterial3D:continue
			var base:=source as StandardMaterial3D
			var material:=ShaderMaterial.new();material.shader=load("res://shaders/animal_motion.gdshader")
			material.set_shader_parameter("albedo_color",base.albedo_color)
			material.set_shader_parameter("has_texture",base.albedo_texture!=null)
			if base.albedo_texture:material.set_shader_parameter("albedo_tex",base.albedo_texture)
			material.set_shader_parameter("animal_kind",kind)
			material.set_shader_parameter("body_height",mesh.mesh.get_aabb().end.y)
			mesh.set_surface_override_material(surface,material);materials.append(material)
	if kind==0:
		for side in [-1.0,1.0]:
			var pivot:=Node3D.new();pivot.name="WingPivot_%d"%wings.size();pivot.position=Vector3(side*.029,.067,0);model.add_child(pivot)
			var feather_material:=StandardMaterial3D.new();feather_material.albedo_color=Color(.33,.25,.19);feather_material.roughness=1
			feather_material.cull_mode=BaseMaterial3D.CULL_DISABLED
			var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			for feather in 4:
				var z:=float(feather)*.018-.025
				var reach:=.115+float(3-feather)*.016
				var points: Array[Vector3]=[Vector3.ZERO,Vector3(side*reach,0,z-.015),Vector3(side*(reach+.016),.006,z),Vector3(side*reach,0,z+.013)]
				for vertex: int in [0,1,2,0,2,3]:builder.add_vertex(points[vertex])
			builder.generate_normals();var wing:=MeshInstance3D.new();wing.name="Feathers";wing.mesh=builder.commit();wing.material_override=feather_material;pivot.add_child(wing)
			pivot.visible=false;wings.append(pivot)

func update(delta: float, flying: bool=false, peck: float=0.0, head_yaw: float=0.0) -> void:
	phase+=delta
	for material in materials:
		material.set_shader_parameter("phase",phase);material.set_shader_parameter("head_yaw",head_yaw);material.set_shader_parameter("peck",peck)
	for i in wings.size():
		wings[i].visible=flying
		wings[i].rotation.z=sin(phase*38.0)*.95*(1.0 if i==0 else -1.0)

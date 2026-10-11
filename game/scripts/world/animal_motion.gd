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
			var feather_material:=StandardMaterial3D.new();feather_material.albedo_color=Color.WHITE;feather_material.vertex_color_use_as_albedo=true;feather_material.roughness=1
			feather_material.diffuse_mode=BaseMaterial3D.DIFFUSE_TOON;feather_material.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
			feather_material.cull_mode=BaseMaterial3D.CULL_DISABLED
			var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			# A curved leading edge and short overlapping feathers form one wing.
			# Tessellating its chord avoids the old four giant triangular blades.
			for span: int in range(8):
				for chord: int in range(3):
					var points: Array[Vector3] = []
					for pair: Vector2 in [Vector2(span,chord),Vector2(span+1,chord),Vector2(span+1,chord+1),Vector2(span,chord+1)]:
						var across: float = pair.x / 8.0
						var fraction: float = pair.y / 3.0
						var front: float = .026*(1.0-across)-.028*across*across
						var width: float = .035+.025*sin(across*PI)
						points.append(Vector3(side*.115*across, sin(across*PI)*.004, front-width*fraction))
					builder.set_color(Color(.37,.26,.17) if chord==0 else Color(.48,.35,.23))
					for vertex: int in [0,1,2,0,2,3]:builder.add_vertex(points[vertex])
			for feather: int in range(5):
				var start_x: float = .032+float(feather)*.016
				var start_z: float = -.011-float(feather)*.008
				for section: int in range(6):
					var outline: Array[Vector3] = []
					for feather_pair: Vector2 in [Vector2(section,-1),Vector2(section+1,-1),Vector2(section+1,1),Vector2(section,1)]:
						var feather_fraction: float = feather_pair.x / 6.0
						var half_width: float = sin(feather_fraction*PI)*.007
						outline.append(Vector3(side*(start_x+feather_fraction*.010+feather_pair.y*half_width),-.001,start_z-feather_fraction*.034))
					builder.set_color(Color(.63,.47,.31) if feather%2==0 else Color(.45,.31,.20))
					for vertex: int in [0,1,2,0,2,3]:builder.add_vertex(outline[vertex])
			builder.generate_normals();var wing:=MeshInstance3D.new();wing.name="Feathers";wing.mesh=builder.commit();wing.material_override=feather_material;pivot.add_child(wing)
			pivot.visible=false;wings.append(pivot)

func update(delta: float, flying: bool=false, peck: float=0.0, head_yaw: float=0.0) -> void:
	phase+=delta
	for material in materials:
		material.set_shader_parameter("phase",phase);material.set_shader_parameter("head_yaw",head_yaw);material.set_shader_parameter("peck",peck)
	for i in wings.size():
		wings[i].visible=flying
		wings[i].rotation.z=sin(phase*38.0)*.95*(1.0 if i==0 else -1.0)

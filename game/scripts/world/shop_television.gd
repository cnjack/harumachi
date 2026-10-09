class_name ShopTelevision
extends RefCounted
## A measured glass surface and a quiet analogue signal, with brief tuning interference.

static func make_screen() -> MeshInstance3D:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/shop_tv_surface.json"))
	var columns: int=int(data.columns);var rows: int=int(data.rows)
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var uvs:=PackedVector2Array();var indices:=PackedInt32Array()
	for point: Array in data.points:
		vertices.append(Vector3(float(point[0]),float(point[1]),float(point[2])))
		uvs.append(Vector2(float(point[3]),float(point[4])))
	for row: int in rows:
		for column: int in columns:
			var left: Vector3=vertices[row*columns+maxi(0,column-1)]
			var right: Vector3=vertices[row*columns+mini(columns-1,column+1)]
			var above: Vector3=vertices[maxi(0,row-1)*columns+column]
			var below: Vector3=vertices[mini(rows-1,row+1)*columns+column]
			normals.append(Vector3(-(right.z-left.z)/(right.x-left.x),-(below.z-above.z)/(below.y-above.y),1).normalized())
			if row>=rows-1 or column>=columns-1:continue
			var index: int=row*columns+column
			indices.append_array(PackedInt32Array([index,index+1,index+columns,index+1,index+columns+1,index+columns]))
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var screen:=MeshInstance3D.new();screen.name="LiveBroadcastScreen";screen.mesh=mesh
	var material:=ShaderMaterial.new();material.shader=load("res://shaders/shop_television.gdshader")
	material.set_shader_parameter("town_programme",load("res://assets/textures/shop_life/tv_town.png"))
	material.set_shader_parameter("farm_programme",load("res://assets/textures/shop_life/tv_farm.png"))
	material.set_shader_parameter("snow_amount",.13);material.set_shader_parameter("tuning_amount",0.0)
	screen.material_override=material;screen.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.set_meta("measured_source_sha256",str(data.source_sha256))
	return screen

static func update(screen: MeshInstance3D,elapsed: float,opened: bool,rain: bool) -> void:
	var material: ShaderMaterial=screen.material_override
	var tuning: float=1.0-smoothstep(.08,.65,fmod(elapsed,12.0)) if opened else 0.0
	material.set_shader_parameter("broadcast_on",opened)
	material.set_shader_parameter("channel",int(elapsed/12.0)%2)
	material.set_shader_parameter("rain_amount",1.0 if rain else 0.0)
	material.set_shader_parameter("snow_amount",.13+.87*tuning if opened else 0.0)
	material.set_shader_parameter("tuning_amount",tuning)

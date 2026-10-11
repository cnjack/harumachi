class_name MaterialRefinement
extends RefCounted
## Material-only setup. WorldBuilder owns geometry, placement and collision.
const DIRECTORY := "res://assets/textures/material_refine_20261011/"
const WALL_SHADER: Shader = preload("res://shaders/blockwall.gdshader")

static func texture(file: String,fallback: String="") -> Texture2D:
	var path: String=DIRECTORY+file
	if ResourceLoader.exists(path):return load(path) as Texture2D
	return load(fallback) as Texture2D if fallback!="" else null

static func wall_material(base_y: float,top_y: float,seed_value: float,footing: bool=false) -> ShaderMaterial:
	var material:=ShaderMaterial.new();material.shader=WALL_SHADER
	material.set_shader_parameter("plaster",not footing)
	material.set_shader_parameter("footing_only",footing)
	material.set_shader_parameter("wall_base",base_y)
	material.set_shader_parameter("wall_top",top_y)
	material.set_shader_parameter("detail_seed",seed_value)
	material.set_shader_parameter("local_weathering",true)
	var paint: Texture2D=texture("plaster_aged.png")
	material.set_shader_parameter("has_plaster_tex",paint!=null)
	material.set_shader_parameter("plaster_tex",paint)
	return material

static func configure_wall(wall: MeshInstance3D,height: float,index: int) -> void:
	var bottom: float=wall.global_position.y-height*.5
	wall.material_override=wall_material(bottom,bottom+height,float(index)*2.71)
	wall_contacts(wall.material_override as ShaderMaterial,wall,height)
	wall.set_meta("local_wall_weathering",true)

static func configure_street(material: ShaderMaterial,kind: String) -> void:
	if kind!="stone":return
	# Keep the authored paving and its joints. New painting only supplies subtle stone colour.
	material.set_shader_parameter("street_detail",true)
	material.set_shader_parameter("surface_wear",0.0)
	material.set_shader_parameter("wet",0.0)
	var stone: Texture2D=texture("street_stone.png","res://assets/textures/town_detail/stone.png")
	material.set_shader_parameter("street_paint",stone)
	var entrances:=PackedVector4Array()
	for point: Array in Layout.POINTS:
		if str(point[0]) in ["home_door","center_door","shop_store","bakery","shop_florist","shop_zakka","library","bus_stop"]:
			entrances.append(Vector4(float(point[1]),float(point[2]),1.45,.85))
	material.set_shader_parameter("entrance_count",entrances.size())
	material.set_shader_parameter("entrances",entrances)
	var edges:=PackedVector4Array()
	for wall: Array in Layout.WALLS:edges.append(Vector4(float(wall[0]),float(wall[1]),float(wall[2]),float(wall[3])))
	material.set_shader_parameter("wall_edge_count",edges.size())
	material.set_shader_parameter("wall_edges",edges)

static func wall_contacts(material: ShaderMaterial,wall: MeshInstance3D,height: float) -> void:
	var tangent: Vector3=wall.global_basis.x.normalized()
	var along_z: bool=absf(tangent.z)>absf(tangent.x)
	var half_length: float=wall.mesh.get_aabb().size.x*.5-.09
	var a: Vector3=wall.global_position-tangent*half_length
	var b: Vector3=wall.global_position+tangent*half_length
	var zones:=PackedVector4Array()
	# End corners trap splash; actual nearby planter/soil positions supply the remaining patches.
	for end: Vector3 in [a+tangent*.22,b-tangent*.22]:zones.append(Vector4(end.z if along_z else end.x,.36,.15,.68))
	var candidates: Array=Layout.PROPS.duplicate();candidates.append_array(Layout.PLANTS)
	var line:=Vector2(b.x-a.x,b.z-a.z)
	var start:=Vector2(a.x,a.z)
	for prop: Array in candidates:
		var id: String=str(prop[0])
		if not (id.contains("plant") or id.contains("pot") or id.contains("bush") or id.contains("rain_barrel") or id=="P12"):continue
		var point:=Vector2(float(prop[1]),float(prop[2]))
		var along: float=clampf((point-start).dot(line)/maxf(line.length_squared(),.001),0.,1.)
		var closest: Vector2=start+line*along
		if point.distance_to(closest)>1.35:continue
		zones.append(Vector4(closest.y if along_z else closest.x,.55,.18+.10*float(zones.size()%2),.80))
		if zones.size()==8:break
	material.set_shader_parameter("contact_count",zones.size())
	material.set_shader_parameter("contacts",zones)
	var source: ShaderMaterial=wall.material_override as ShaderMaterial
	if source!=null:
		var seed_value: Variant=source.get_shader_parameter("detail_seed")
		if seed_value!=null:material.set_shader_parameter("detail_seed",float(seed_value))
	material.set_shader_parameter("wall_base",wall.global_position.y-height*.5)

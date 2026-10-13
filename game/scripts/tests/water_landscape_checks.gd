extends RefCounted
## Geometry and runtime contracts; native water pixels remain a separate acceptance gate.
var t: Object
var main: Node
func _init(runner: Object) -> void:
	t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:
	t.check("WATER_LANDSCAPE",label,ok,detail)
func run() -> void:
	var lake: Node3D=main.world.farm.lakeside
	var surface: MeshInstance3D=lake.get_node("Connected_lake_and_river")
	var arrays: Array=surface.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	var longest: float=0.0
	var triangles: int=(indices.size() if not indices.is_empty() else vertices.size())/3
	for triangle: int in triangles:
		for edge: int in 3:
			var first: int=indices[triangle*3+edge] if not indices.is_empty() else triangle*3+edge
			var second: int=indices[triangle*3+(edge+1)%3] if not indices.is_empty() else triangle*3+(edge+1)%3
			longest=maxf(longest,vertices[first].distance_to(vertices[second]))
	check("actual wet surface is subdivided enough for metre-scale moving waves",triangles>=5000 and longest<=1.05,"triangles=%d longest_edge=%.3fm"%[triangles,longest])
	var material: ShaderMaterial=main.world.farm.water_mat
	var uniforms: Dictionary={}
	for parameter: Dictionary in material.shader.get_shader_uniform_list():uniforms[str(parameter.name)]=true
	check("selected production water declares wave bands and broad directional reflection",uniforms.has("ripple_contrast") and uniforms.has("sun_path_width") and float(material.get_shader_parameter("ripple_contrast"))>=.055 and float(material.get_shader_parameter("sun_path_width"))<=32.0)
	var animation_override: Variant=material.get_shader_parameter("animation_time")
	check("production wave animation follows real render time",animation_override==null or float(animation_override)<0.0)
	var physical: Array=lake.find_children("*","CollisionShape3D",true,false)
	var water_collision: bool=false
	for collision: CollisionShape3D in physical:
		if surface.is_ancestor_of(collision):water_collision=true
	check("wave geometry adds no walking collider",not water_collision)
	for farm: bool in [false,true]:
		var parent: Node3D=main.world.farm if farm else main.world
		var mountains: Node3D=parent.get_node_or_null("LandscapeCoverage/DistantMountains")
		var good: bool=mountains!=null
		var total: int=0
		if mountains:
			for ridge: Node3D in mountains.get_children():
				var bounds: AABB=ridge.global_transform*WorldBuilder.local_aabb(ridge)
				good=good and ridge.get_meta("model_id","")=="V19_distant_cliff" and bounds.size.y>=26.0 and ridge.position.length()>350.0 and ridge.find_children("*","CollisionShape3D",true,false).is_empty()
				for mesh: MeshInstance3D in WorldBuilder.find_meshes(ridge):
					var finish: ShaderMaterial=mesh.material_override as ShaderMaterial
					good=good and finish!=null and finish.shader.resource_path=="res://shaders/distant_mountain.gdshader"
					total+=1
		check(("farm" if farm else "town")+" has modelled distant ridges beyond the tree horizon without colliders",good and total>=12,"ridge_meshes=%d"%total)
	var fish: Node3D=lake.get_node_or_null("RiverFish")
	check("river fish reuse the accepted tank geometry as separate submerged animals",fish!=null and int(fish.get_meta("reused_source_triangles",0))>80 and int(fish.get_meta("fish_count",0))==4)
	if fish and fish.has_method("sample_position"):
		var routes_ok: bool=true
		var deepest_gap: float=INF
		var maximum_step: float=0.0
		for index: int in 4:
			var prior:=Vector3.INF
			for sample: int in 1201:
				var at: Vector3=fish.call("sample_position",index,float(sample)*.1)
				var bed: float=LakesideLayout.height_at(Vector2(at.x,at.z))
				deepest_gap=minf(deepest_gap,at.y-bed)
				routes_ok=routes_ok and at.y<LakesideLayout.WATER_Y-.08 and at.y>bed+.06 and LakesideLayout.water_distance(Vector2(at.x,at.z))<-.45
				if prior.is_finite():maximum_step=maxf(maximum_step,prior.distance_to(at))
				prior=at
		check("all fish routes stay below water above the real bed and move continuously",routes_ok and maximum_step<.045,"min_bed_gap=%.3f maximum_100ms_step=%.4f"%[deepest_gap,maximum_step])
	else:check("all fish routes stay below water above the real bed and move continuously",false)
	# Census the physical sources, not just each member of the stored array:
	# a full four-slot array previously hid the missing original bank lamp.
	var lamp_count: int=int(material.get_shader_parameter("reflection_lamp_count"))
	var bound: Variant=material.get_shader_parameter("reflection_lamps")
	var weights: Variant=material.get_shader_parameter("reflection_lamp_weights")
	var expected: int=0
	var missing: Array[String]=[]
	var wrong_weights: Array[String]=[]
	for lamp: OmniLight3D in main.world.farm.lamp_lights:
		var local_lamp: Vector3=lake.to_local(lamp.global_position)
		if absf(LakesideLayout.water_distance(Vector2(local_lamp.x,local_lamp.z)))>8.0:continue
		expected+=1
		var matched: int=-1
		for index: int in lamp_count:
			if bound!=null and (bound[index] as Vector3).distance_to(lamp.global_position)<.001:matched=index
		if matched<0:missing.append(str(lamp.global_position));continue
		var wanted: float=float(lamp.get_meta("outdoor_energy_scale",1.0))
		if weights==null or matched>=weights.size() or absf(float(weights[matched])-wanted)>.0001:wrong_weights.append("%s expected %.2f"%[str(lamp.global_position),wanted])
	check("every nearby physical lamp is bound once with its actual outdoor energy scale",expected>=5 and lamp_count==expected and lamp_count<=8 and uniforms.has("reflection_lamp_weights") and missing.is_empty() and wrong_weights.is_empty(),"expected=%d bound=%d missing=%s wrong_weights=%s"%[expected,lamp_count,str(missing),str(wrong_weights)])

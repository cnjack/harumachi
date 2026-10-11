extends RefCounted
var t: Node
var main: Node

func _init(runner: Node) -> void:
	t=runner
	main=runner.main

func check(label: String,ok: bool,detail: String="") -> void:
	t.check("STALL_RAIN_SHELTER",label,ok,detail)

func is_sheltered(fx: Node,point: Vector3) -> bool:
	# Old WeatherFX must execute normal assertions rather than fail to parse
	# because it lacks a new method.
	return bool(fx.call("rain_is_sheltered_at",point)) if fx.has_method("rain_is_sheltered_at") else false

func run() -> void:
	var fx: Node=main.weather_fx
	var stall: Node3D=main.world.get_node_or_null("P09")
	var original_visible: bool=stall.visible
	var original_region: String=main.world.region
	main.world.set_region("town")
	stall.show()
	var ready: bool=bool(fx.call("prepare_stall_shelter")) if fx.has_method("prepare_stall_shelter") else false
	var status: Dictionary=fx.call("rain_shelter_status") if fx.has_method("rain_shelter_status") else {}
	check("rain shelter is sampled once from the real continuous canopy",ready and int(status.get("samples",0))==1625 and int(status.get("valid_samples",0))==1625,str(status))
	var below:=0
	var above:=0
	var compared:=0
	for x: float in [-.9,0.0,.9]:
		for z: float in [-.35,0.0,.35]:
			var at: Vector3=stall.to_global(Vector3(x,0,z))
			var actual_top: float=WorldBuilder.rendered_support_height(stall,at,stall.global_position.y+2.0,true)
			if not is_finite(actual_top):continue
			compared+=1
			if is_sheltered(fx,Vector3(at.x,actual_top-.04,at.z)):below+=1
			if not is_sheltered(fx,Vector3(at.x,actual_top+.04,at.z)):above+=1
	check("actual roof blocks only the rain below it and keeps rain above it",compared==9 and below==9 and above==9,str({"actual_samples":compared,"below_dry":below,"above_wet":above}))
	var outside_wet:=true
	for local: Vector3 in [Vector3(-1.45,1.0,0),Vector3(1.45,1.0,0),Vector3(0,1.0,-.65),Vector3(0,1.0,.65)]:
		outside_wet=outside_wet and not is_sheltered(fx,stall.to_global(local))
	var saved_transform: Transform3D=stall.global_transform
	stall.global_transform=Transform3D(Basis(Vector3.UP,.37),Vector3(27,.23,-19))
	var moved_below: bool=is_sheltered(fx,stall.to_global(Vector3(0,1.50,0)))
	var old_position_wet: bool=not is_sheltered(fx,saved_transform*Vector3(0,1.50,0))
	stall.global_transform=saved_transform
	stall.hide()
	var hidden_wet: bool=not is_sheltered(fx,stall.to_global(Vector3(0,1.50,0)))
	stall.visible=original_visible
	main.world.set_region(original_region)
	if fx.has_method("prepare_stall_shelter"):fx.call("prepare_stall_shelter")
	check("local roof mask follows translated rotated geometry and excludes outside or hidden regions",outside_wet and moved_below and old_position_wet and hidden_wet,str({"outside_wet":outside_wet,"moved_dry":moved_below,"old_position_wet":old_position_wet,"hidden_wet":hidden_wet}))
	var mat: ShaderMaterial=fx.get("_rain_material") as ShaderMaterial
	var parameters: Dictionary={}
	if mat!=null and mat.shader!=null:
		for item: Dictionary in mat.shader.get_shader_uniform_list():parameters[str(item.name)]=true
	var wired: bool=parameters.has("shelter_height") and parameters.has("shelter_world_to_local") and parameters.has("shelter_enabled")
	if wired:
		var uploaded: Variant=mat.get_shader_parameter("shelter_world_to_local")
		wired=mat.get_shader_parameter("shelter_height") is Texture2D and uploaded is Projection
		if wired:
			var matrix: Projection=uploaded as Projection
			var expected:=Projection(stall.global_transform.affine_inverse())
			for column: int in 4:
				for row: int in 4:
					wired=wired and absf(matrix[column][row]-expected[column][row])<.00001
			var world_point: Vector3=stall.to_global(Vector3(.37,1.5,.19))
			var actual_local: Vector4=matrix*Vector4(world_point.x,world_point.y,world_point.z,1)
			wired=wired and Vector3(actual_local.x,actual_local.y,actual_local.z).distance_to(Vector3(.37,1.5,.19))<.00001
	check("the production particle shader receives the measured height texture and current inverse transform",wired,str(parameters.keys()))

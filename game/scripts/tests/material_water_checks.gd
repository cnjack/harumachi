extends RefCounted
## Physical/material contracts; real GPU comparisons remain a separate native gate.
## Uses existing classes only, so the same file can report meaningful failures on old production.
var runner: Node

func _init(value: Node) -> void:
	runner=value

func _check(label: String,ok: bool,detail: String="") -> void:
	runner.call("check","MATERIAL_WATER",label,ok,detail)

func _declares(material: ShaderMaterial,names: PackedStringArray) -> bool:
	# ShaderMaterial accepts stored overrides even when the active shader omits
	# them. Check compiled declarations, including #includes, rather than set/get.
	if material==null or material.shader==null:return false
	var actual: Dictionary={}
	for parameter: Dictionary in material.shader.get_shader_uniform_list():
		actual[str(parameter.get("name",""))]=true
	for name: String in names:
		if not actual.has(name):return false
	return true

func _expanded_source(source: String,path: String,visited: Dictionary) -> String:
	var result: String=source
	var include_pattern:=RegEx.new()
	include_pattern.compile("#include\\s+\"([^\"]+)\"")
	for found: RegExMatch in include_pattern.search_all(source):
		var included: String=found.get_string(1)
		if not included.begins_with("res://"):included=path.get_base_dir().path_join(included).simplify_path()
		if visited.has(included) or not FileAccess.file_exists(included):continue
		visited[included]=true
		result+="\n"+_expanded_source(FileAccess.get_file_as_string(included),included,visited)
	return result

func _has_depth_sampler(material: ShaderMaterial) -> bool:
	# Godot deliberately hides hint_depth_texture from get_shader_uniform_list.
	# Resolve the active wrapper's include closure and require both declaration
	# and actual sampling, rather than accepting a stored material override.
	if material==null or material.shader==null:return false
	var shader: Shader=material.shader
	var source: String=_expanded_source(shader.code,shader.resource_path,{shader.resource_path:true})
	var declaration:=RegEx.new()
	declaration.compile("(?m)^\\s*uniform\\s+sampler2D\\s+scene_depth\\s*:\\s*hint_depth_texture\\b")
	var sample:=RegEx.new()
	sample.compile("\\btexture(?:Lod)?\\s*\\(\\s*scene_depth\\s*,")
	return declaration.search(source)!=null and sample.search(source)!=null

func _radius(root: Node3D) -> float:
	var result: float=0.0
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(root):
		for surface: int in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var p: Vector3=mesh.global_transform*vertex-root.global_position
				result=maxf(result,Vector2(p.x,p.z).length())
	return result

func run() -> void:
	var main: Node=runner.get("main") as Node
	var world: WorldBuilder=main.get("world") as WorldBuilder
	var lake: Node3D=world.farm.lakeside
	var material: ShaderMaterial=world.farm.water_mat
	await runner.call("frames",2)
	var water_y: float=lake.global_position.y+LakesideLayout.WATER_Y
	var counts: Dictionary={"bank":0,"half":0,"below":0}
	var groups: Dictionary={}
	var widths: Array[float]=[]
	var support_bad: Array[String]=[]
	var path_bad: Array[String]=[]
	var fishing_bad: Array[String]=[]
	var collider_bad: Array[String]=[]
	var texture_bad: Array[String]=[]
	var wet_bad: Array[String]=[]
	var stones: int=0
	for child: Node in lake.get_children():
		if not child.has_meta("creek_stone"):continue
		var rock: Node3D=child as Node3D
		var bounds: AABB=rock.global_transform*WorldBuilder.local_aabb(rock)
		var local_point: Vector3=lake.to_local(rock.global_position)
		var point:=Vector2(local_point.x,local_point.z)
		var radius: float=_radius(rock)
		widths.append(radius*2.0)
		stones+=1
		if bounds.position.y>=water_y-.008:counts.bank+=1
		elif bounds.end.y<water_y-.04:counts.below+=1
		elif bounds.position.y<water_y-.04 and bounds.end.y>water_y+.04:counts.half+=1
		var group: int=int(rock.get_meta("creek_stone_group",-1))
		if group>=0:groups[group]=int(groups.get(group,0))+1
		var ray:=PhysicsRayQueryParameters3D.create(rock.global_position+Vector3.UP*2.0,rock.global_position-Vector3.UP*4.0,WorldBuilder.L_GROUND)
		var support: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
		if support.is_empty() or absf(bounds.position.y-(support.get("position",Vector3.INF) as Vector3).y)>.04:support_bad.append(str(rock.name))
		if LakesideLayout.path_distance(point)-radius<1.70-.002:path_bad.append(str(rock.name))
		for spot_id: String in LakesideLayout.SPOTS:
			var spot: Dictionary=LakesideLayout.SPOTS[spot_id]
			var cast: Vector2=spot["float"]-spot.stand
			var fraction: float=clampf((point-spot.stand).dot(cast)/cast.length_squared(),0.0,1.0)
			if point.distance_to(spot.stand)-radius<.998 or point.distance_to(spot["float"])-radius<1.348 or point.distance_to(spot.stand+cast*fraction)-radius<.438:
				fishing_bad.append(str(rock.name)+"/"+spot_id)
		for body: Node in rock.find_children("*","CollisionObject3D",true,false):
			if (body as CollisionObject3D).collision_layer!=0:collider_bad.append(str(body.get_path()))
		for mesh: MeshInstance3D in WorldBuilder.find_meshes(rock):
			var painted: ShaderMaterial=mesh.material_override as ShaderMaterial
			if painted==null:
				texture_bad.append(str(mesh.get_path()));wet_bad.append(str(mesh.get_path()));continue
			var texture: Texture2D=painted.get_shader_parameter("painted_tex") as Texture2D
			if texture==null or texture.resource_path!="res://assets/textures/material_refine_20261011/creek_stone.png":texture_bad.append(str(mesh.get_path()))
			var level: Variant=painted.get_shader_parameter("water_level")
			var wet: Variant=painted.get_shader_parameter("wet_darkening")
			var band: Variant=painted.get_shader_parameter("wet_band_height")
			if not _declares(painted,["water_level","wet_darkening","wet_band_height"]) or level==null or wet==null or band==null or absf(float(level)-water_y)>.001 or float(wet)<.65 or float(wet)>.80 or float(band)<.01 or float(band)>.04:wet_bad.append(str(mesh.get_path()))
	var grouped: int=0
	for members: Variant in groups.values():
		if int(members)>=2:grouped+=1
	_check("rendered stones include dry bank, half-wet and submerged levels",int(counts.bank)>=8 and int(counts.half)>=20 and int(counts.below)>=20,str(counts))
	_check("stones form sparse multi-size bank groups",stones>=60 and grouped>=24,"stones=%d groups=%d"%[stones,grouped])
	_check("actual horizontal stone sizes vary beyond the old uniform range",widths.size()>=60 and float(widths.max())/maxf(.001,float(widths.min()))>2.2,str([widths.min(),widths.max()]) if not widths.is_empty() else "no stones")
	_check("every stone rests on the real rendered stream-bed collision",stones>=60 and support_bad.is_empty(),str(support_bad))
	_check("whole stone footprints preserve the walking ribbon clearance",stones>=60 and path_bad.is_empty(),str(path_bad))
	_check("whole stone footprints clear four fishing stands, floats and cast lanes",stones>=60 and fishing_bad.is_empty(),str(fishing_bad))
	_check("decorative stones add no player or ground colliders",stones>=60 and collider_bad.is_empty(),str(collider_bad))
	_check("real stone materials use the approved painted refinement",stones>=60 and texture_bad.is_empty(),str(texture_bad))
	_check("wet boundaries use the actual water height and restrained darkening",stones>=60 and wet_bad.is_empty(),str(wet_bad))
	var opacity: Variant=material.get_shader_parameter("shallow_opacity")
	_check("shallow water leaves enough contrast for real bottom stones",_declares(material,["shallow_opacity"]) and _has_depth_sampler(material) and opacity!=null and float(opacity)>=.25 and float(opacity)<=.40,str(opacity))
	var middle: Variant=material.get_shader_parameter("middle_color")
	var shallow: Variant=material.get_shader_parameter("shallow_color")
	var deep: Variant=material.get_shader_parameter("deep_color")
	var bands_ok: bool=_declares(material,["middle_color","shallow_color","deep_color"]) and middle is Color and shallow is Color and deep is Color
	if bands_ok:
		var a: Color=shallow as Color
		var b: Color=middle as Color
		var c: Color=deep as Color
		bands_ok=Vector3(a.r,a.g,a.b).distance_to(Vector3(b.r,b.g,b.b))>.20 and Vector3(b.r,b.g,b.b).distance_to(Vector3(c.r,c.g,c.b))>.20
	_check("depth palette has distinct shallow, middle and deep bands",bands_ok,str([shallow,middle,deep]))
	var ring_radius: Variant=material.get_shader_parameter("rain_ring_radius")
	var ring_width: Variant=material.get_shader_parameter("rain_ring_width")
	var ring_strength: Variant=material.get_shader_parameter("rain_ring_strength")
	_check("summer rain ripples stay below 36cm diameter with thin weak rings",_declares(material,["rain_amount","rain_ring_radius","rain_ring_width","rain_ring_strength"]) and ring_radius!=null and ring_width!=null and ring_strength!=null and float(ring_radius)<=.18 and float(ring_radius)>=.08 and float(ring_width)<=.012 and float(ring_strength)<=.14,str([ring_radius,ring_width,ring_strength]))
	var lamp_count: Variant=material.get_shader_parameter("reflection_lamp_count")
	var lamp_positions: Variant=material.get_shader_parameter("reflection_lamps")
	var lights_ok: bool=_declares(material,["reflection_lamps","reflection_lamp_count","lamp_amount"]) and lamp_count!=null and int(lamp_count)>=1 and int(lamp_count)<=4 and (lamp_positions is PackedVector3Array or lamp_positions is Array)
	if lights_ok:
		for lamp_index: int in int(lamp_count):
			var found: bool=false
			for lamp: OmniLight3D in world.farm.lamp_lights:
				if lamp.global_position.distance_to(lamp_positions[lamp_index] as Vector3)<.001:found=true
			lights_ok=lights_ok and found
	_check("night reflection sources match real nearby lamp positions",lights_ok,str(lamp_count))
	var old_indoor: bool=world.indoor
	world.indoor=false
	world.update_time(720.0,"sunny",true)
	var day_sun: Variant=material.get_shader_parameter("sunlight_amount")
	world.update_time(720.0,"rain",true)
	var rain_sun: Variant=material.get_shader_parameter("sunlight_amount")
	world.update_time(1260.0,"sunny",true)
	var night: Variant=material.get_shader_parameter("night_w")
	var lamps: Variant=material.get_shader_parameter("lamp_amount")
	var moon_position: Variant=material.get_shader_parameter("moon_position")
	var clock_ok: bool=_declares(material,["sunlight_amount","sun_direction","moonlight_amount","moon_position","lamp_amount","night_w","dusk_w"]) and day_sun!=null and rain_sun!=null and night!=null and lamps!=null and moon_position is Vector3
	if clock_ok:clock_ok=float(day_sun)>.9 and float(rain_sun)<.6 and float(night)>.9 and float(lamps)>.8 and world.moon!=null and (moon_position as Vector3).distance_to(world.moon.global_position)<.001
	_check("actual weather and clock drive solar, moon and bridge light gates",clock_ok,str([day_sun,rain_sun,night,lamps]))
	world.indoor=old_indoor
	world.update_time(GameState.minute,GameState.weather,true)

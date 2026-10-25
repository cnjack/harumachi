extends RefCounted
## Copies only explicitly selected surfaces; every original resource is retained for A/B.
const RESPONSE: String = "#include \"res://shaders/material_poc_response.gdshaderinc\"\n"
var bindings: Array[Dictionary] = []
var report: Array[Dictionary] = []
var shaders: Dictionary = {}
var water_candidate: ShaderMaterial
var water_source: ShaderMaterial

func prepare(world: WorldBuilder) -> void:
	for mesh: MeshInstance3D in WorldBuilder.find_meshes(world):
		if mesh.mesh == null: continue
		var path: String = str(world.get_path_to(mesh))
		if not (path.begins_with("S02/") or path.begins_with("Farm/Lakeside/P_bridge/") or path == "Farm/Lakeside/Connected_lake_and_river"): continue
		var indices: Array[int] = []
		if mesh.material_override != null: indices.append(-1)
		if indices.is_empty():
			for surface: int in range(mesh.mesh.get_surface_count()): indices.append(surface)
		for index: int in indices:
			var original: Material = mesh.material_override if index == -1 else mesh.get_active_material(index)
			var candidate: Material = _candidate(original, path)
			if candidate == null: continue
			bindings.append({"mesh":mesh, "index":index, "original":mesh.material_override if index == -1 else mesh.get_surface_override_material(index), "candidate":candidate})
			report.append({"node":path, "surface":index, "source_shader":original.shader.resource_path if original is ShaderMaterial else "StandardMaterial3D", "source_name":original.resource_name, "candidate":candidate.resource_name})

func apply(enabled: bool) -> void:
	if water_candidate and water_source:
		for parameter: Dictionary in water_source.shader.get_shader_uniform_list():
			water_candidate.set_shader_parameter(parameter.name, water_source.get_shader_parameter(parameter.name))
	for binding: Dictionary in bindings:
		var mesh: MeshInstance3D = binding.mesh as MeshInstance3D
		var value: Material = binding.candidate if enabled else binding.original
		if int(binding.index) == -1: mesh.material_override = value
		else: mesh.set_surface_override_material(int(binding.index), value)

func sync_water_environment(world: WorldBuilder, lighting_enabled: bool) -> void:
	if water_candidate == null: return
	for sky: String in ["sky_day", "sky_dusk", "sky_night"]:
		water_candidate.set_shader_parameter(sky, world.sky_mat.get_shader_parameter(sky))
	water_candidate.set_shader_parameter("sky_drift", world.sky_mat.get_shader_parameter("drift"))
	water_candidate.set_shader_parameter("sky_dusk_offset", world.sky_mat.get_shader_parameter("dusk_offset"))
	water_candidate.set_shader_parameter("sky_night_offset", world.sky_mat.get_shader_parameter("night_offset"))
	water_candidate.set_shader_parameter("cloud_cover", world.sky_mat.get_shader_parameter("cloud_cover"))
	water_candidate.set_shader_parameter("sky_vertical_scale", 2.4 if lighting_enabled else 1.0)
	water_candidate.set_shader_parameter("poc_sky", lighting_enabled)
	if lighting_enabled:
		water_candidate.set_shader_parameter("sun_direction",world.sun.global_basis.z.normalized())
		water_candidate.set_shader_parameter("moon_position",FarmBuilder.ORIGIN+Vector3(94,0,41)+world.sun.global_basis.z.normalized()*10000.0)

func _candidate(original: Material, node_path: String) -> Material:
	if original is ShaderMaterial:
		var source: ShaderMaterial = original as ShaderMaterial
		var path: String = source.shader.resource_path
		if path.ends_with("furniture_wood.gdshader") and node_path.begins_with("Farm/Lakeside/P_bridge/"):
			var bridge_material: ShaderMaterial = source.duplicate() as ShaderMaterial
			bridge_material.shader = _bridge_shader(path)
			bridge_material.set_shader_parameter("roughness_base", .86)
			bridge_material.set_shader_parameter("roughness_polished", .68)
			bridge_material.set_shader_parameter("reflectance", .27)
			bridge_material.set_shader_parameter("authored_detail_strength", 1.35)
			bridge_material.set_shader_parameter("sheen_strength", .24)
			bridge_material.resource_name = "POC current dark bridge timber response"
			return bridge_material
		if path.ends_with("material_options/water.gdshader"):
			water_source = source
			water_candidate = source.duplicate() as ShaderMaterial
			water_candidate.shader = _water_shader()
			water_candidate.resource_name = "POC sky reflection and water absorption"
			return water_candidate
		if path.ends_with("public_facade_finish.gdshader") or path.ends_with("painted_finish.gdshader"):
			var material: ShaderMaterial = source.duplicate() as ShaderMaterial
			material.shader = _response_shader(path)
			material.resource_name = "POC timber/plaster/canvas response"
			return material
		return null
	if original is StandardMaterial3D:
		var source: StandardMaterial3D = original as StandardMaterial3D
		var role: String = str(node_path.get_file())
		var wood: bool = role.begins_with("WindowSill") or role.begins_with("WindowJamb") or role.begins_with("BakeryRack") or role == "DoorBreadTable" or role == "RearWainscot" or role == "RearChairRail"
		var steel: bool = role.begins_with("AwningBrace") or role.begins_with("AwningBracket")
		if not wood and not steel: return null
		var material: StandardMaterial3D = source.duplicate() as StandardMaterial3D
		material.resource_name = "POC wood joinery" if wood else "POC coated steel"
		material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		material.roughness = .56 if wood else .43
		material.metallic_specular = .32 if wood else .42
		# Painted metal is a dielectric coating, not an all-metallic awning.
		material.metallic = 0.0
		return material
	return null

func _response_shader(path: String) -> Shader:
	if shaders.has(path): return shaders[path] as Shader
	var code: String = FileAccess.get_file_as_string(path)
	var token: String
	var replacement: String
	if path.ends_with("public_facade_finish.gdshader"):
		token = "ALBEDO=c.rgb;ROUGHNESS=1.;"
		replacement = """
	// Source atlas supplies colour; geometric zones keep the roof/brick/cloth matte.
	float joinery = timber * float(p.y > .94 && p.y < 5.15) * (1. - cloth);
	ROUGHNESS = mix(.90, .61 + (grain - .5) * .12, joinery);
	ROUGHNESS = mix(ROUGHNESS, .96, cloth);
	SPECULAR = mix(.10, .33, joinery) * (1. - cloth * .85);
	// Keep all source paint: plaster wear, curtain folds, window divisions and seams.
	// Only the material response changes; do not blur or recolour the source atlas.
	float height_m = (grain - .5) * .0018 * joinery + (weave - .5) * .00035 * cloth;
	NORMAL = poc_surface_normal(NORMAL, VERTEX, height_m);
	ALBEDO = c.rgb;
	poc_roughness = ROUGHNESS;
	poc_f0 = .16 * SPECULAR * SPECULAR;
"""
	else:
		token = "ALBEDO=colour;ROUGHNESS=1.;SPECULAR=0.;"
		replacement = """
	// Bridge wood uses its existing board-aligned painting; top rails are smoother.
	float along = grain_axis == 1 ? p.y : (grain_axis == 2 ? p.z : p.x);
	float across = grain_axis == 1 ? (abs(normal_part.x) > .5 ? p.z : p.x) : (grain_axis == 2 ? (abs(normal_part.y) > .5 ? p.x : p.y) : (abs(normal_part.y) > .5 ? p.z : p.y));
	float fibre = dot(texture(wood_tex, vec2(across * 2.2, along * .75)).rgb, vec3(.2126,.7152,.0722));
	float rail_top = smoothstep(.72, .94, normal_part.y);
	ROUGHNESS = clamp(.76 - rail_top * .16 + (fibre - .5) * .14, .54, .86);
	SPECULAR = .32;
	NORMAL = poc_surface_normal(NORMAL, VERTEX, (fibre - .5) * .0022);
	ALBEDO = colour;
	poc_roughness = ROUGHNESS;
	poc_f0 = .16 * SPECULAR * SPECULAR;
"""
	# Fail visibly if the owning shader changes instead of silently patching the wrong text.
	assert(code.count(token) == 1, "POC source shader changed: " + path)
	code = code.replace("render_mode diffuse_toon,specular_disabled;", "render_mode specular_schlick_ggx;\n" + RESPONSE)
	code = code.replace("render_mode diffuse_toon, specular_disabled;", "render_mode specular_schlick_ggx;\n" + RESPONSE)
	code = code.replace(token, replacement)
	var shader: Shader = Shader.new()
	shader.code = code
	shaders[path] = shader
	return shader

func _bridge_shader(path: String) -> Shader:
	if shaders.has(path): return shaders[path] as Shader
	var code: String = FileAccess.get_file_as_string(path)
	var token: String = "reflection_f0 = .16 * SPECULAR * SPECULAR;"
	assert(code.count(token) == 1, "POC bridge source changed")
	code = code.replace("void vertex()", "#include \"res://shaders/material_poc_bump.gdshaderinc\"\nvoid vertex()")
	code = code.replace(token, "NORMAL = poc_surface_normal(NORMAL, VERTEX, (grain - .5) * .0012 * timber);\n\t" + token)
	var shader: Shader = Shader.new()
	shader.code = code
	shaders[path] = shader
	return shader

func _water_shader() -> Shader:
	# Reuse the real shoreline, depth sampling, analytic waves, foam and light positions.
	# This optical study evaluates reflected sky once, separately from diffuse scene light.
	var code: String = FileAccess.get_file_as_string("res://shaders/lakeside_water_surface.gdshaderinc")
	var changes: Dictionary = {
		"varying vec2 p;":"uniform float sky_drift=0.;\nuniform float sky_dusk_offset=0.;\nuniform float sky_night_offset=0.;\nuniform float sky_vertical_scale=1.;\nuniform float cloud_cover=.28;\nuniform bool poc_sky=false;\n#include \"res://shaders/material_poc_water_reflection.gdshaderinc\"\nvarying vec2 p;",
		# Godot SKY_COORDS uses atan(x,-z), whereas the inherited water UV uses
		# atan(z,x)+PI: subtract a quarter turn before applying the POC panorama scale.
		"vec3 sky=mix(":"sky_uv.y=clamp((poc_sky?.55:.5)+(sky_uv.y-.5)*sky_vertical_scale,0.,1.);\n if(poc_sky)sky_uv.x-=.25;\n sky_uv.x*=poc_sky?3.:1.;\n vec3 sky=mix(",
		"vec2 slopes=ripple.xy+water_fine_slopes(p,t);":"vec2 slopes=ripple.xy*.65+water_fine_slopes(p,t)*.18;",
		"texture(sky_day,sky_uv)":"texture(sky_day,sky_uv+vec2(sky_drift,0.))",
		"texture(sky_dusk,sky_uv)":"texture(sky_dusk,sky_uv+vec2(sky_dusk_offset+sky_drift*(poc_sky?1.:.5),0.))",
		"texture(sky_night,sky_uv)":"texture(sky_night,sky_uv+vec2(sky_night_offset+sky_drift*(poc_sky?1.:.25),0.))",
		"col=mix(col,sky,.09+fresnel*.23);":"""
	 sky=mix(sky,vec3(.20,.28,.38),smoothstep(.45,.96,cloud_cover)*.80);
	 vec3 reflection_origin=(VIEW_MATRIX*vec4(world_position+normal*.06,1.)).xyz;
	 vec3 reflection_ray=normalize((VIEW_MATRIX*vec4(reflected,0.)).xyz);
	 vec4 scene_hit=poc_scene_reflection(reflection_origin,reflection_ray,PROJECTION_MATRIX,INV_PROJECTION_MATRIX,INV_VIEW_MATRIX,world_position.y);
	 sky=mix(sky,scene_hit.rgb,scene_hit.a);
	 col*=mix(1.0,.22,night_w);
	 col=mix(col,sky,.16+fresnel*.72);
""",
		"col=mix(col,night_palette,night_w*.55);":"col=mix(col,night_palette,night_w*.12);",
		"ALBEDO=col*surface_tint;":"ALBEDO=col;",
		"EMISSION=col*mix(surface_tint*.075,vec3(.16),night_w)+sun_color*sun_glints*.42+":"EMISSION=col*.70+sun_color*sun_glints*.42+",
		"ALPHA=clamp(mix(shallow_opacity,.98,smoothstep(.12,2.2,depth))+rain_amount*.035,0.0,1.0);":"ALPHA=clamp(mix(.65,.99,smoothstep(.08,1.1,depth))+rain_amount*.035,0.0,1.0);"
	}
	for token: String in changes:
		assert(code.count(token) == 1, "POC water source changed: " + token)
		code = code.replace(token, changes[token])
	var shader: Shader = Shader.new()
	shader.code = "shader_type spatial;\nrender_mode blend_mix,depth_draw_never,ambient_light_disabled,cull_disabled;\n" + code + "\nvoid light(){if(LIGHT_IS_DIRECTIONAL)DIFFUSE_LIGHT+=vec3(.30)*ATTENUATION;}\n"
	return shader

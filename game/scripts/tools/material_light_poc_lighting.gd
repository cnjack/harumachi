extends RefCounted
## Art-directed lighting profiles for the opt-in POC, not physical lux calibration.
const PROFILES: Dictionary = {
	"morning":{"sun":1.70, "ambient":.44, "sky":Color(.67,.76,1.0), "warm":Color(1.0,.88,.69), "fog":Color(.68,.78,.94), "begin":42.0, "end":180.0},
	"noon":{"sun":1.85, "ambient":.48, "sky":Color(.67,.77,1.0), "warm":Color(1.0,.95,.83), "fog":Color(.69,.82,.96), "begin":50.0, "end":190.0},
	"overcast":{"sun":.32, "ambient":.66, "sky":Color(.79,.83,.96), "warm":Color(.93,.96,1.0), "fog":Color(.69,.77,.86), "begin":35.0, "end":160.0},
	"rain":{"sun":.12, "ambient":.48, "sky":Color(.65,.76,.90), "warm":Color(.79,.86,1.0), "fog":Color(.49,.62,.76), "begin":22.0, "end":135.0},
	"sunset":{"sun":1.65, "ambient":.44, "sky":Color(.65,.68,.96), "warm":Color(1.0,.76,.46), "fog":Color(.70,.66,.79), "begin":35.0, "end":175.0},
	"night":{"sun":.25, "ambient":.29, "sky":Color(.53,.64,.94), "warm":Color(.63,.73,1.0), "fog":Color(.18,.25,.42), "begin":35.0, "end":170.0}
}
var probe: ReflectionProbe
var window_light: SpotLight3D
var original_sun: Dictionary
var refresh_index: int = 0
var sky_shader: Shader
const SKY_TEXTURES: Dictionary = {
	"sky_day":preload("res://assets/material_light_poc/sky_day.png"),
	"sky_dusk":preload("res://assets/material_light_poc/sky_dusk.png"),
	"sky_night":preload("res://assets/material_light_poc/sky_night.png")
}

func prepare(world: WorldBuilder) -> void:
	var sky_code: String = FileAccess.get_file_as_string("res://shaders/sky_blend.gdshader")
	assert(sky_code.count("vec2 uv = SKY_COORDS;") == 1, "POC sky source changed")
	sky_shader = Shader.new()
	# Compress the panorama's oversized cloud banks toward the horizon in both sky and water.
	sky_shader.code = sky_code.replace("vec2 uv = SKY_COORDS;", "vec2 uv = vec2(SKY_COORDS.x, clamp(.5 + (SKY_COORDS.y - .5) * 2.7, 0., 1.));")
	original_sun = {"angular":world.sun.light_angular_distance, "blur":world.sun.shadow_blur, "bias":world.sun.shadow_bias, "normal_bias":world.sun.shadow_normal_bias}
	probe = ReflectionProbe.new()
	probe.name = "POC_BakeryReflection"
	probe.size = Vector3(11,9,12)
	probe.position = Vector3(-24,2.5,-15)
	probe.max_distance = 28
	probe.intensity = .65
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.visible = false
	world.add_child(probe)
	window_light = SpotLight3D.new()
	window_light.name = "POC_BakeryWindowBounce"
	window_light.position = Vector3(-24.55,1.55,-16.15)
	window_light.light_color = Color(1.0,.72,.40)
	window_light.spot_range = 4.5
	window_light.spot_angle = 68.0
	window_light.spot_attenuation = 1.1
	window_light.spot_angle_attenuation = .5
	window_light.rotation_degrees = Vector3(-27.0,180.0,0)
	window_light.light_size = .65
	window_light.shadow_enabled = true
	window_light.visible = false
	world.add_child(window_light)

func apply(world: WorldBuilder, condition: Dictionary, region: String, enabled: bool) -> void:
	probe.visible = enabled and region == "town"
	window_light.visible = enabled and region == "town"
	world.sun.light_angular_distance = float(original_sun.angular)
	world.sun.shadow_blur = float(original_sun.blur)
	world.sun.shadow_bias = float(original_sun.bias)
	world.sun.shadow_normal_bias = float(original_sun.normal_bias)
	if not enabled: return
	world.sky_mat.shader = sky_shader
	for key: String in SKY_TEXTURES:
		world.sky_mat.set_shader_parameter(key, SKY_TEXTURES[key])
	# The new panoramas have no painted sun and retain matching cloud coordinates.
	world.sky_mat.set_shader_parameter("dusk_offset", 0.0)
	world.sky_mat.set_shader_parameter("night_offset", 0.0)
	var profile: Dictionary = PROFILES[condition.id]
	world.sun.light_energy = float(profile.sun)
	world.sun.light_color = profile.warm
	world.sun.light_angular_distance = .38 if condition.weather == "sunny" else 2.0
	world.sun.shadow_blur = 1.0
	world.sun.shadow_bias = .035
	world.sun.shadow_normal_bias = .65
	var env: Environment = world.env
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = profile.sky
	env.ambient_light_sky_contribution = .32
	env.ambient_light_energy = float(profile.ambient)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.adjustment_contrast = 1.03
	env.adjustment_saturation = 1.04 if condition.weather == "sunny" else .99
	env.ssao_enabled = true
	env.ssao_radius = .42
	env.ssao_intensity = 1.25
	env.ssao_light_affect = 0.0
	env.ssil_enabled = true
	env.ssil_radius = 2.0
	env.ssil_intensity = .35
	env.ssil_sharpness = .9
	env.fog_light_color = profile.fog
	env.fog_depth_begin = float(profile.begin)
	env.fog_depth_end = float(profile.end)
	env.fog_depth_curve = 1.45
	env.fog_aerial_perspective = .20
	env.glow_bloom = 0.0
	env.glow_intensity = .25
	env.glow_hdr_threshold = 1.55
	window_light.light_energy = 2.0 if condition.id == "night" else (.8 if condition.id == "rain" else .12)
	# UPDATE_ONCE is refreshed on time/weather changes, never every rendered frame.
	refresh_index += 1
	probe.position.x = -24.0 + float(refresh_index % 2) * .001

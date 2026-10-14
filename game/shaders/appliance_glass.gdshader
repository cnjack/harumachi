shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, specular_schlick_ggx;
#include "res://shaders/furniture_reflection.gdshaderinc"
// Actual transparent panes retain their tint and reveal the existing cavity/products.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap;
uniform vec4 base_color : source_color = vec4(.72, .85, .90, .12);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool has_albedo = false;
uniform bool has_emission = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float opacity = .12;
uniform float gloss_strength = .18;
varying float reflection_f0;
varying float reflection_roughness;

void fragment() {
	float edge = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	vec2 authored_uv = UV * uv_scale + uv_offset;
	ALBEDO = base_color.rgb * (has_albedo ? texture(albedo_tex, authored_uv).rgb : vec3(1.0));
	ALPHA = clamp(opacity + edge * .075, .045, .28);
	ROUGHNESS = .26;
	SPECULAR = clamp(gloss_strength * 2.25, 0.0, .60);
	reflection_f0 = .16 * SPECULAR * SPECULAR;
	reflection_roughness = ROUGHNESS;
	EMISSION = emission_color.rgb * (has_emission ? texture(emission_tex, authored_uv).rgb : vec3(1.0));
}

void light() {
	float facing = abs(dot(normalize(NORMAL), normalize(LIGHT)));
	float cel = mix(.24, 1.0, smoothstep(.12, .23, facing));
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * cel / 3.14159265;
	SPECULAR_LIGHT += furniture_ggx(NORMAL, VIEW, LIGHT, reflection_roughness, reflection_f0) * LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT;
}

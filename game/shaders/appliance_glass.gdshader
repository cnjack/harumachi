shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
// Actual transparent panes retain their tint and reveal the existing cavity/products.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap;
uniform vec4 base_color : source_color = vec4(.72, .85, .90, .12);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool has_albedo = false;
uniform bool has_emission = false;
uniform float opacity = .12;
uniform float gloss_strength = .18;

void fragment() {
	float edge = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	ALBEDO = base_color.rgb * (has_albedo ? texture(albedo_tex, UV).rgb : vec3(1.0));
	ALPHA = clamp(opacity + edge * .075, .045, .28);
	ROUGHNESS = .38;
	SPECULAR = 0.0;
	EMISSION = emission_color.rgb * (has_emission ? texture(emission_tex, UV).rgb : vec3(1.0));
}

void light() {
	vec3 normal = normalize(NORMAL);
	float incidence = abs(dot(normal, normalize(LIGHT)));
	// Base tint is applied once by the renderer after all lights accumulate.
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (.24 + .76 * incidence) / 3.14159265;
	float alignment = abs(dot(normal, normalize(normalize(LIGHT) + normalize(VIEW))));
	float lobe = pow(alignment, 42.0);
	float band = .28 * lobe + .72 * smoothstep(.32, .62, lobe);
	SPECULAR_LIGHT += vec3(.90, .96, 1.0) * LIGHT_COLOR * ATTENUATION * band * gloss_strength;
}

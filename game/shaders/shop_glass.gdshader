shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
// Thin real glazing. All products and the room behind are actual geometry.
uniform float lamp = 0.42;
uniform vec3 sky_col : source_color = vec3(0.72, 0.82, 0.94);
uniform float gloss_strength = 0.16;
void fragment() {
	float grazing = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	ALBEDO = sky_col;
	ALPHA = 0.045 + 0.14 * grazing;
	ROUGHNESS = 0.42;
	SPECULAR = 0.0;
}

void light() {
	vec3 normal = normalize(NORMAL);
	float incidence = abs(dot(normal, normalize(LIGHT)));
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (.28 + .72 * incidence) / 3.14159265;
	float alignment = abs(dot(normal, normalize(normalize(LIGHT) + normalize(VIEW))));
	float lobe = pow(alignment, 42.0);
	float band = .28 * lobe + .72 * smoothstep(.32, .62, lobe);
	SPECULAR_LIGHT += vec3(.92, .97, 1.0) * LIGHT_COLOR * ATTENUATION * band * gloss_strength;
}

shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
// Thin real glazing. All products and the room behind are actual geometry.
uniform float lamp = 0.42;
uniform vec3 sky_col : source_color = vec3(0.72, 0.82, 0.94);
void fragment() {
	float grazing = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	ALBEDO = sky_col;
	ALPHA = 0.045 + 0.14 * grazing;
	ROUGHNESS = 0.72;
	SPECULAR = 0.0;
}

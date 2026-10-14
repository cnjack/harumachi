shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
#include "res://shaders/furniture_reflection.gdshaderinc"
// Thin real glazing. All products and the room behind are actual geometry.
uniform float lamp = 0.42;
uniform vec3 sky_col : source_color = vec3(0.72, 0.82, 0.94);
uniform float gloss_strength = 0.16;
varying float reflection_f0;
void fragment() {
	float grazing = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	ALBEDO = sky_col;
	ALPHA = 0.045 + 0.14 * grazing;
	ROUGHNESS = 0.42;
	SPECULAR = .46 * clamp(gloss_strength / .16, 0., 1.2);
	reflection_f0 = .16 * SPECULAR * SPECULAR;
}

void light() {
	vec3 normal = normalize(NORMAL);
	float incidence = abs(dot(normal, normalize(LIGHT)));
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (.28 + .72 * incidence) / 3.14159265;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * furniture_ggx(NORMAL, VIEW, LIGHT, .42, reflection_f0);
}

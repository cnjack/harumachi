shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_toon, specular_toon;
// A single thin pane: reflection changes with camera angle, never with UV.
// No emission or extra reflection layer, so the cab stays readable at night.
uniform vec3 sky_tint : source_color = vec3(0.60, 0.77, 0.82);
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float edge = pow(1.0 - clamp(abs(dot(n, v)), 0.0, 1.0), 3.0);
	vec3 reflected_world = normalize((INV_VIEW_MATRIX * vec4(reflect(-v, n), 0.0)).xyz);
	float sky = smoothstep(-0.06, 0.48, reflected_world.y);
	float sky_band = smoothstep(0.18, 0.30, reflected_world.y)
		* (1.0 - smoothstep(0.48, 0.62, reflected_world.y));
	vec3 sky_colour = mix(vec3(0.52, 0.66, 0.76), vec3(0.77, 0.86, 0.90), sky);
	ALBEDO = mix(sky_tint, sky_colour, 0.20 + sky_band * 0.23);
	ALPHA = 0.075 + edge * 0.13 + sky_band * 0.024;
	ROUGHNESS = 0.24;
	SPECULAR = 0.32;
	METALLIC = 0.0;
}

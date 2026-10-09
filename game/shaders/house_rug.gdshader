shader_type spatial;
// Woven rug: soft stripes, a border band and a fine weave, lit like the floors.
render_mode specular_disabled;

uniform vec4 color_a : source_color = vec4(0.55, 0.66, 0.78, 1.0);
uniform vec4 color_b : source_color = vec4(0.95, 0.9, 0.8, 1.0);
uniform vec2 size = vec2(2.0, 1.4);
uniform vec4 shadow_tint : source_color = vec4(0.62, 0.6, 0.9, 1.0);
uniform float shadow_fill = 0.16;

void fragment() {
	vec2 p = UV * size;
	float edge = min(min(p.x, size.x - p.x), min(p.y, size.y - p.y));
	float stripe = smoothstep(0.45, 0.55, fract(p.x * 2.2));
	vec3 c = mix(color_a.rgb, mix(color_a.rgb, color_b.rgb, 0.45), stripe);
	c = mix(c, color_b.rgb, step(edge, 0.09) * step(0.035, edge));
	c = mix(c, color_a.rgb * 0.8, step(edge, 0.035));
	float weave = 0.5 + 0.5 * sin(p.x * 180.0) * sin(p.y * 180.0);
	c *= 0.94 + 0.06 * weave;
	ALBEDO = c;
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	vec3 col = LIGHT_COLOR / PI;
	if (LIGHT_IS_DIRECTIONAL) {
		float band = smoothstep(0.28, 0.72, ndl * ATTENUATION * 1.6);
		DIFFUSE_LIGHT += col * (band + shadow_tint.rgb * shadow_fill * (1.0 - band));
	} else {
		float a = ndl * ATTENUATION;
		DIFFUSE_LIGHT += col * (smoothstep(0.01, 0.12, a) * 0.45 + smoothstep(0.22, 0.42, a) * 0.55);
	}
}

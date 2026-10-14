shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
// Thin anime glazing: actual seats and the far window remain visible.
// Broad soft sky bands give the pane a reading without a metallic mirror.
uniform vec3 sky_tint : source_color = vec3(0.63, 0.80, 0.90);
void fragment() {
	float edge = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.5);
	float stripe = smoothstep(0.58, 0.60, UV.x + UV.y * 0.36) * (1.0 - smoothstep(0.70, 0.72, UV.x + UV.y * 0.36));
	ALBEDO = mix(sky_tint, vec3(0.92, 0.97, 1.0), stripe * 0.43);
	ALPHA = 0.10 + edge * 0.17 + stripe * 0.075;
	ROUGHNESS = 0.8;
	SPECULAR = 0.0;
}

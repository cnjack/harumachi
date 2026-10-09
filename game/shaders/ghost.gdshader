shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;
uniform vec4 color : source_color = vec4(0.3, 1.0, 0.45, 0.45);
void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = color.rgb;
	ALPHA = color.a * (0.55 + 0.45 * rim);
}

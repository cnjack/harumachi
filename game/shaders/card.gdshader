shader_type spatial;
// Painted background card: unshaded, alpha-tested, faded into the sky with distance haze.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 haze : source_color = vec4(0.72, 0.82, 0.93, 1.0);
uniform float haze_amount = 0.15;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.45) { discard; }
	ALBEDO = mix(c.rgb * tint.rgb, haze.rgb, haze_amount);
}

shader_type spatial;
// Painted light shaft sheet (additive). UV.x runs across the opening, UV.y from the opening (0)
// to where the ray meets the floor (1). Posts or lattice bars leave soft dark gaps at fixed u,
// slow streaks drift across, and the sheet fades out when seen edge-on so it never shows a line.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform float strength = 0.1;
uniform float posts = 3.0;
uniform float post_w = 0.012;

void fragment() {
	vec2 uv = UV;
	float edge = smoothstep(0.0, 0.05, uv.x) * smoothstep(1.0, 0.95, uv.x);
	float along = (1.0 - 0.65 * uv.y) * smoothstep(0.0, 0.06, uv.y) * smoothstep(1.0, 0.72, uv.y);
	float gap = 1.0;
	if (posts > 0.5) {
		float f = fract(uv.x * (posts + 1.0));
		float dd = min(f, 1.0 - f) / (posts + 1.0);
		gap = smoothstep(post_w * 0.6, post_w * 1.6, dd);
	}
	float streak = 0.72 + 0.28 * sin(uv.x * 41.0 + TIME * 0.35) * sin(uv.x * 11.0 - TIME * 0.21 + uv.y * 2.0);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = strength * edge * along * gap * streak * smoothstep(0.04, 0.3, facing);
	ALBEDO = beam_color.rgb * a;
}

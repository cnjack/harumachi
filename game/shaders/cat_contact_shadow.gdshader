shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

void fragment() {
	vec2 q=(UV-vec2(0.5))*2.0;
	float edge=1.0-smoothstep(0.35,1.0,length(q));
	ALBEDO=vec3(0.15,0.12,0.17);
	ALPHA=edge*0.22;
}

shader_type canvas_item;
uniform vec4 paper_color : source_color = vec4(0.99, 0.97, 0.90, 0.85);
void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	float alpha = 1.0 - smoothstep(0.91, 1.0, radius);
	COLOR = vec4(paper_color.rgb, paper_color.a * alpha);
}
